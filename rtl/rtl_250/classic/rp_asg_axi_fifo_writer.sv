/*
  AXI -> FIFO writer for ASG
  - Receives start/stop requests in DAC clock domain
  - Issues AXI burst reads in AXI clock domain
  - Keeps cyclic read order strictly A1 -> A2 -> A1
*/

module rp_asg_axi_fifo_writer #(
  parameter int DW = 64,
  parameter int AW = 32,
  parameter int LW = 4,
  parameter int AXI_BURST_LEN = 16,
  parameter int DATA_REQUEST_LEVEL = 128-16,
  parameter int WR_LVL_W = 7,
  parameter int FIFO_LVL_MIN = 192,
  parameter int FIFO_LVL_MAX = 224
)(
  input  logic                 dac_clk_i,
  input  logic                 dac_rstn_i,
  input  logic                 start_pulse_i,
  input  logic                 set_rst_i,
  input  logic [AW-1:0]        set_axi_start_i,
  input  logic [AW-1:0]        set_axi_stop_i,
  axi_sys_if.s                 axi_sys,

  // FIFO write-side interface
  output logic [DW-1:0]        dat_fifo_idata,
  output logic                 dat_fifo_wr,
  input  logic                 dat_fifo_full,
  input  logic [WR_LVL_W-1:0]  dat_wr_fifo_lvl,
  input  logic                 dat_fifo_rst_busy,
  output logic                 axi_fifo_reset
);

//---------------------------------------------------------------------------------

localparam int AXI_RSIZE = 3'h3; // 8 bytes per beat for 64-bit data
localparam int FIFO_DEPTH_WORDS = (1 << WR_LVL_W);
localparam logic [LW:0] AXI_BURST_LEN_WORDS = AXI_BURST_LEN;
localparam logic [WR_LVL_W-1:0] FIFO_LVL_MIN_C = FIFO_LVL_MIN;
localparam logic [WR_LVL_W-1:0] FIFO_LVL_MAX_C = FIFO_LVL_MAX;

typedef enum logic [1:0] {
  WR_IDLE,
  WR_INIT,
  WR_RUN
} wr_state_t;

wr_state_t wr_state_q;
wr_state_t wr_state_d;

logic [AW-1:0] start_addr_q;
logic [AW-1:0] stop_addr_q;
logic [AW-1:0] req_addr_q;
logic [AW:0]   cycle_words_q;
logic [AW:0]   words_left_q;
logic          prefetch_active_q;

logic          fsm_reset_sync;
logic          fifo_wr_dly;
logic          fifo_wr_ready;
logic          axi_busy;
logic [AW-1:0] dat_fifo_iaddr;

//---------------------------------------------------------------------------------
//
//  addr cfg sync for axi

localparam int REQ_W = 128;

logic              req_empty;
logic [REQ_W-1:0]  req_payload;
logic [REQ_W-1:0]  req_fifo_out;
logic [REQ_W-1:0]  req_data_q;
logic              req_loaded;
logic              req_pop_d;
logic [AW-1:0]     req_start_addr;
logic [AW-1:0]     req_stop_addr;
wire               req_pop = (wr_state_q == WR_IDLE) && !req_empty && !req_loaded;

assign req_payload = {{(REQ_W-2*AW){1'b0}}, set_axi_start_i, set_axi_stop_i};

sync_fifo inst_sync_fifo
(
  .wr_clk         (dac_clk_i                ),
  .rd_clk         (axi_sys.clk              ),
  .rst            (!dac_rstn_i || set_rst_i ),
  .din            (req_payload              ),
  .wr_en          (start_pulse_i            ),
  .full           (                         ),
  .dout           (req_fifo_out             ),
  .rd_en          (req_pop                  ),
  .empty          (req_empty                ),
  .wr_rst_busy    (                         ),
  .rd_rst_busy    (                         )
);

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn || fsm_reset_sync) begin
    req_data_q <= '0;
    req_loaded <= 1'b0;
    req_pop_d  <= 1'b0;
  end else begin
    req_pop_d <= req_pop;
    if (req_pop_d) begin
      req_data_q <= req_fifo_out;
      req_loaded <= 1'b1;
    end else if (wr_state_q == WR_INIT) begin
      req_loaded <= 1'b0;
    end
  end
end

assign req_start_addr = req_data_q[1*AW +: AW];
assign req_stop_addr  = req_data_q[0*AW +: AW];

wire [AW:0] cycle_words_init = (req_stop_addr >= req_start_addr) ?
                               (((req_stop_addr - req_start_addr) >> 3) + {{AW{1'b0}},1'b1}) :
                               {{AW{1'b0}},1'b1};

//---------------------------------------------------------------------------------
//
//  FSM reset sync

(* ASYNC_REG = "TRUE" *) logic fsm_reset_ff1;
(* ASYNC_REG = "TRUE" *) logic fsm_reset_ff2;

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    fsm_reset_ff1 <= 1'b0;
    fsm_reset_ff2 <= 1'b0;
  end else begin
    fsm_reset_ff1 <= set_rst_i;
    fsm_reset_ff2 <= fsm_reset_ff1;
  end
end

assign fsm_reset_sync = fsm_reset_ff2;

//---------------------------------------------------------------------------------
//
//  Cyclic command scheduler

logic [LW:0]          burst_words_issue;
logic [LW-1:0]        burst_len_issue;
logic                 rd_cmd_rdy;
logic                 rd_cmd_issue;
logic [WR_LVL_W:0]    fifo_words_used;
logic [WR_LVL_W:0]    fifo_words_free;
logic [WR_LVL_W:0]    burst_words_issue_ext;
logic                 fifo_has_space_for_burst;

assign fifo_words_used = {1'b0, dat_wr_fifo_lvl};
assign fifo_words_free = FIFO_DEPTH_WORDS - fifo_words_used;

assign burst_words_issue = (words_left_q == 0) ? {(LW+1){1'b0}} :
                           ((words_left_q > AXI_BURST_LEN_WORDS) ? AXI_BURST_LEN_WORDS : words_left_q[LW:0]);
assign burst_len_issue = burst_words_issue[LW-1:0] - {{(LW-1){1'b0}},1'b1};
assign burst_words_issue_ext = {{(WR_LVL_W-LW){1'b0}}, burst_words_issue};
assign fifo_has_space_for_burst = fifo_words_free >= burst_words_issue_ext;

assign rd_cmd_issue = (wr_state_q == WR_RUN) &&
                      !dat_fifo_rst_busy &&
                      prefetch_active_q &&
                      (burst_words_issue != 0) &&
                      rd_cmd_rdy &&
                      fifo_has_space_for_burst;

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn || fsm_reset_sync) begin
    wr_state_q         <= WR_IDLE;
    start_addr_q       <= '0;
    stop_addr_q        <= '0;
    req_addr_q         <= '0;
    cycle_words_q      <= {{AW{1'b0}},1'b1};
    words_left_q       <= {{AW{1'b0}},1'b1};
    prefetch_active_q  <= 1'b0;
    axi_fifo_reset     <= 1'b1;
  end else begin
    wr_state_q <= wr_state_d;

    // Keep data FIFO in reset while idle.
    axi_fifo_reset <= (wr_state_d == WR_IDLE);

    if (wr_state_q == WR_IDLE && wr_state_d == WR_INIT) begin
      start_addr_q      <= req_start_addr;
      stop_addr_q       <= req_stop_addr;
      req_addr_q        <= req_start_addr;
      cycle_words_q     <= cycle_words_init;
      words_left_q      <= cycle_words_init;
      prefetch_active_q <= 1'b1;
    end else if (wr_state_q == WR_RUN) begin
      // FIFO prefetch hysteresis.
      if (dat_wr_fifo_lvl <= FIFO_LVL_MIN_C)
        prefetch_active_q <= 1'b1;
      else if (dat_wr_fifo_lvl >= FIFO_LVL_MAX_C)
        prefetch_active_q <= 1'b0;

      if (rd_cmd_issue) begin
        if (words_left_q <= burst_words_issue) begin
          // End of cycle: wrap to A1.
          req_addr_q   <= start_addr_q;
          words_left_q <= cycle_words_q;
        end else begin
          req_addr_q   <= req_addr_q + ({{(AW-(LW+1)){1'b0}}, burst_words_issue} << 3);
          words_left_q <= words_left_q - burst_words_issue;
        end
      end
    end
  end
end

always_comb begin
  wr_state_d = wr_state_q;

  unique case (wr_state_q)
    WR_IDLE: begin
      if (req_loaded)
        wr_state_d = WR_INIT;
    end

    WR_INIT: begin
      if (!dat_fifo_rst_busy)
        wr_state_d = WR_RUN;
    end

    WR_RUN: begin
      wr_state_d = WR_RUN;
    end

    default: begin
      wr_state_d = WR_IDLE;
    end
  endcase
end

//---------------------------------------------------------------------------------
//
//  interface to AXI

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn)
    fifo_wr_dly <= 1'b0;
  else
    fifo_wr_dly <= dat_fifo_wr;
end

assign fifo_wr_ready = !dat_fifo_full && !dat_fifo_wr && !fifo_wr_dly;

axi_rd_burst #(
  .DW             (DW),
  .AW             (AW),
  .LW             (LW),
  .CMD_FIFO_DEPTH (8)
) i_rdburst (
  // AXI master signals
  .axi_sys      (axi_sys        ),

  // configuration signals
  .cfg_clk_i    (dac_clk_i      ),
  .cfg_rstn_i   (dac_rstn_i     ),

  .ctrl_addr_i  (req_addr_q     ),
  .ctrl_size_i  (burst_len_issue),
  .ctrl_rsize_i (AXI_RSIZE      ),
  .ctrl_val_i   (rd_cmd_issue   ),
  .ctrl_rdy_o   (rd_cmd_rdy     ),

  // data
  .rd_data_o    (dat_fifo_idata ),
  .rd_addr_o    (dat_fifo_iaddr ),
  .rd_dval_o    (dat_fifo_wr    ),
  .rd_drdy_i    (fifo_wr_ready  ),
  .diags_o      (               ),
  .ctrl_busy_o  (axi_busy       ),
  .stat_busy_o  (               )
);

endmodule
