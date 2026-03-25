/*
  AXI -> FIFO writer for ASG
  - Receives start/stop requests in DAC clock domain
  - Issues AXI burst reads and fills data FIFO in AXI clock domain
*/

module rp_asg_axi_fifo_writer #(
  parameter int DW = 64,
  parameter int AW = 32,
  parameter int LW = 4,
  parameter int AXI_BURST_LEN = 16,
  parameter int DATA_REQUEST_LEVEL = 128-16,
  parameter int WR_LVL_W = 7
)(
  input  logic               dac_clk_i,
  input  logic               dac_rstn_i,
  input  logic               start_pulse_i,
  input  logic               set_rst_i,
  input  logic [AW-1:0]       set_axi_start_i,
  input  logic [AW-1:0]       set_axi_stop_i,
  axi_sys_if.s               axi_sys,

  // FIFO write-side interface
  output logic [DW-1:0]       dat_fifo_idata,
  output logic               dat_fifo_wr,
  input  logic               dat_fifo_full,
  input  logic [WR_LVL_W-1:0] dat_wr_fifo_lvl,
  input  logic               dat_fifo_rst_busy,
  output logic               axi_fifo_reset
);

//---------------------------------------------------------------------------------

localparam int AXI_BURST_BYTES = AXI_BURST_LEN*DW/8;
localparam int BURST_WORDS     = AXI_BURST_LEN-1;
localparam logic [2:0] AXI_RSIZE = 3'h3; // 8 bytes per beat for 64-bit data

typedef enum logic [2:0] {
  WR_IDLE,
  WR_INIT,
  WR_RELOAD,
  WR_ADDR_INC,
  WR_ADDR_RDY,
  WR_WAIT_FIFO,
  WR_READ
} wr_state_t;

wr_state_t wr_state_q;
wr_state_t wr_state_d;

logic [AW-1:0] rd_addr_q;
logic [AW-1:0] start_addr_q;
logic [AW-1:0] stop_addr_q;
logic [LW-1:0] burst_words_q;
logic [2:0]    rsize_q;
logic          rd_start_pulse;
logic          fsm_reset_sync;

logic [AW-1:0] dat_fifo_iaddr;

logic          fifo_wr_dly;
logic          fifo_wr_ready;
logic          axi_busy;

//---------------------------------------------------------------------------------
//
//  addr cfg sync for axi

localparam int REQ_W = 128;

logic           req_valid;
logic           req_empty;
logic [REQ_W-1:0] req_payload;
logic [REQ_W-1:0] req_fifo_out;
logic [REQ_W-1:0] req_data_q;
logic [AW-1:0]  req_start_addr;
logic [AW-1:0]  req_stop_addr;
wire            req_pop = (wr_state_q == WR_IDLE) && !req_empty;
assign req_payload = {{(REQ_W-2*AW){1'b0}}, set_axi_start_i, set_axi_stop_i};

// Always stores only one request
sync_fifo inst_sync_fifo
(
  .wr_clk         (dac_clk_i        ),
  .rd_clk         (axi_sys.clk       ),
  .rst            (!dac_rstn_i || set_rst_i),
  .din            (req_payload      ),
  .wr_en          (start_pulse_i     ),
  .full           (                  ),
  .dout           (req_fifo_out      ),
  .rd_en          (req_pop           ),
  .empty          (req_empty         ),
  .valid          (req_valid         ),
  .wr_rst_busy    (                  ),
  .rd_rst_busy    (                  )
);

// latch request after fifo pop
always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn || fsm_reset_sync) begin
    req_data_q <= '0;
  end else if (req_valid) begin
    req_data_q <= req_fifo_out;
  end
end

assign req_start_addr = req_data_q[1*AW +: AW];
assign req_stop_addr  = req_data_q[0*AW +: AW];

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
//  FSM for reading from AXI to FIFO

always_ff @( posedge axi_sys.clk ) begin
  if (!axi_sys.rstn || fsm_reset_sync) begin
    wr_state_q      <= WR_IDLE;
    rd_addr_q       <= '0;
    burst_words_q   <= '0;
    rsize_q         <= '0;
    rd_start_pulse  <= 1'b0;
    start_addr_q    <= '0;
    stop_addr_q     <= '0;
    axi_fifo_reset  <= 1'b0;
  end else begin
    wr_state_q     <= wr_state_d;
    rd_start_pulse <= 1'b0;
    axi_fifo_reset <= 1'b0;

    if (wr_state_q == WR_IDLE) begin
      axi_fifo_reset <= 1'b1;
    end

    if (wr_state_q == WR_INIT) begin
      start_addr_q  <= req_start_addr;
      stop_addr_q   <= req_stop_addr;
      burst_words_q <= BURST_WORDS;
      rsize_q       <= AXI_RSIZE;
    end

    if (wr_state_q == WR_RELOAD) begin
      rd_addr_q <= start_addr_q;
    end

    if (wr_state_q == WR_READ && wr_state_d == WR_ADDR_INC) begin
      rd_addr_q <= rd_addr_q + AXI_BURST_BYTES;
    end

    if (wr_state_q == WR_WAIT_FIFO && wr_state_d == WR_ADDR_RDY) begin
      rd_start_pulse <= 1'b1;
    end
  end
end

always_comb begin : fsm_axi_read
  wr_state_d = wr_state_q;

  unique case (wr_state_q)
    WR_IDLE: begin
      if (req_valid)
        wr_state_d = WR_INIT;
    end

    WR_INIT: begin
      if (!dat_fifo_rst_busy)
        wr_state_d = WR_RELOAD;
    end

    WR_RELOAD: begin
      wr_state_d = WR_WAIT_FIFO;
    end

    WR_ADDR_INC: begin
      wr_state_d = WR_WAIT_FIFO;
    end

    WR_WAIT_FIFO: begin
      if (dat_wr_fifo_lvl < DATA_REQUEST_LEVEL)
        wr_state_d = WR_ADDR_RDY;
    end

    WR_ADDR_RDY: begin
      if (axi_busy)
        wr_state_d = WR_READ;
    end

    WR_READ: begin
      if (!axi_busy) begin
        if (dat_fifo_iaddr >= stop_addr_q) begin
          wr_state_d = WR_RELOAD;
        end else begin
          wr_state_d = WR_ADDR_INC;
        end
      end
    end

    default:
      wr_state_d = WR_IDLE;
  endcase
end

//---------------------------------------------------------------------------------
//
//  interface to AXI

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    fifo_wr_dly <= '0;
  end else begin
    fifo_wr_dly <= dat_fifo_wr;
  end
end

assign fifo_wr_ready = !dat_fifo_full && !dat_fifo_wr && !fifo_wr_dly;

axi_rd_burst #(
  .DW  (DW),
  .AW  (AW),
  .LW  (LW)
) i_rdburst (
  // AXI master signals
  .axi_sys      (axi_sys       ),

  // configuration signals
  .cfg_clk_i    (dac_clk_i     ),
  .cfg_rstn_i   (dac_rstn_i    ),

  .ctrl_addr_i  (rd_addr_q     ),
  .ctrl_size_i  (burst_words_q ),
  .ctrl_rsize_i (rsize_q       ),
  .ctrl_val_i   (rd_start_pulse),

  // data
  .rd_data_o    (dat_fifo_idata),
  .rd_addr_o    (dat_fifo_iaddr),
  .rd_dval_o    (dat_fifo_wr   ),
  .rd_drdy_i    (fifo_wr_ready ),
  .ctrl_busy_o  (axi_busy      ),
  .stat_busy_o  (              )
);

endmodule
