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
//

localparam int AXI_BURST_BYTES = AXI_BURST_LEN*DW/8;

typedef enum logic [2:0] {
  ST_IDLE,
  ST_INIT,
  ST_RELOAD,
  ST_ADDR_INC,
  ST_ADDR_RDY,
  ST_WAIT_FOR_FIFO,
  ST_READ
} axi_to_fifo_state_t;

axi_to_fifo_state_t axi_rd_state_registered;
axi_to_fifo_state_t axi_rd_state_next;

logic [AW-1:0] axi_read_addr;
logic [AW-1:0] axi_start_addr;
logic [AW-1:0] axi_stop_addr;
logic [AW-1:0] axi_request_size;
logic [AW-1:0] axi_read_size_bytes;
logic          axi_read_start;
logic          axi_fsm_reset;

logic [DW-1:0] dat_fifo_idata_i;
logic [AW-1:0] dat_fifo_iaddr;
logic          dat_fifo_wr_r;
logic          df_wr_rdy;
logic          ctrl_busy;
logic          stat_busy;

logic [AW-1:0] dac_rd_size;
logic [2:0]    dac_rd_rsize;

assign dac_rd_size  = AXI_BURST_LEN-1;
assign dac_rd_rsize = 3'h3;

//---------------------------------------------------------------------------------
//
//  addr cfg sync for axi

logic            req_fifo_rd_valid;
logic            req_fifo_empty;
logic [64-1:0]    req_fifo_in;
logic [64-1:0]    req_fifo_out;
logic [64-1:0]    req_fifo_out_r;
logic [AW-1:0]    req_start_addr;
logic [AW-1:0]    req_stop_addr;
wire             req_fifo_rd = (axi_rd_state_registered == ST_IDLE) && !req_fifo_empty;
assign req_fifo_in = {set_axi_start_i, set_axi_stop_i};

// Always stores only one request
sync_fifo inst_sync_fifo
(
  .wr_clk         (dac_clk_i        ),
  .rd_clk         (axi_sys.clk       ),
  .rst            (!dac_rstn_i       ),
  .din            (req_fifo_in       ),
  .wr_en          (start_pulse_i     ),
  .full           (                  ),
  .dout           (req_fifo_out      ),
  .rd_en          (req_fifo_rd       ),
  .empty          (req_fifo_empty    ),
  .valid          (req_fifo_rd_valid ),
  .wr_rst_busy    (                  ),
  .rd_rst_busy    (                  )
);

// commands for AXI module
always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    req_fifo_out_r <= '0;
  end else if (req_fifo_rd_valid) begin
    req_fifo_out_r <= req_fifo_out;
  end
end

assign req_start_addr = req_fifo_out_r[1*AW +: AW];
assign req_stop_addr  = req_fifo_out_r[0*AW +: AW];

//---------------------------------------------------------------------------------
//
//  FSM reset sync

(* ASYNC_REG = "TRUE" *) logic set_fsm_rst_sync1;
(* ASYNC_REG = "TRUE" *) logic set_fsm_rst_sync2;

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    set_fsm_rst_sync1 <= 1'b0;
    set_fsm_rst_sync2 <= 1'b0;
  end else begin
    set_fsm_rst_sync1 <= set_rst_i;
    set_fsm_rst_sync2 <= set_fsm_rst_sync1;
  end
end

assign axi_fsm_reset = set_fsm_rst_sync2;

//---------------------------------------------------------------------------------
//
//  FSM for reading from axi to fifo

always_ff @( posedge axi_sys.clk ) begin
  if (!axi_sys.rstn || axi_fsm_reset) begin
    axi_rd_state_registered <= ST_IDLE;
    axi_read_addr           <= '0;
    axi_request_size        <= '0;
    axi_read_size_bytes     <= '0;
    axi_read_start          <= '0;
    axi_start_addr          <= '0;
    axi_stop_addr           <= '0;
    axi_fifo_reset          <= '0;
  end else begin
    axi_rd_state_registered <= axi_rd_state_next;
    axi_read_start <= 1'b0;
    axi_fifo_reset <= 1'b0;

    if (axi_rd_state_registered == ST_IDLE) begin
      axi_fifo_reset <= 1'b1;
    end

    if (axi_rd_state_registered == ST_INIT) begin
      axi_start_addr <= req_start_addr;
      axi_stop_addr  <= req_stop_addr;

      axi_request_size    <= dac_rd_size;
      axi_read_size_bytes <= dac_rd_rsize;
    end

    if (axi_rd_state_registered == ST_RELOAD) begin
      axi_read_addr <= axi_start_addr;
    end

    if (axi_rd_state_registered == ST_READ && axi_rd_state_next == ST_ADDR_INC) begin
      axi_read_addr <= axi_read_addr + AXI_BURST_BYTES;
    end

    if (axi_rd_state_registered == ST_WAIT_FOR_FIFO && axi_rd_state_next == ST_ADDR_RDY) begin
      axi_read_start <= 1'b1;
    end
  end
end

always_comb begin : fsm_axi_read
  axi_rd_state_next = axi_rd_state_registered;

  unique case (axi_rd_state_registered)
    ST_IDLE: begin
      if (req_fifo_rd_valid)
        axi_rd_state_next = ST_INIT;
    end

    ST_INIT: begin
      if (!dat_fifo_rst_busy)
        axi_rd_state_next = ST_RELOAD;
    end

    ST_RELOAD: begin
      axi_rd_state_next = ST_WAIT_FOR_FIFO;
    end

    ST_ADDR_INC: begin
      axi_rd_state_next = ST_WAIT_FOR_FIFO;
    end

    ST_WAIT_FOR_FIFO: begin
      if (dat_wr_fifo_lvl < DATA_REQUEST_LEVEL)
        axi_rd_state_next = ST_ADDR_RDY;
    end

    ST_ADDR_RDY: begin
      if (ctrl_busy)
        axi_rd_state_next = ST_READ;
    end

    ST_READ: begin
      if (!ctrl_busy) begin
        if (dat_fifo_iaddr >= axi_stop_addr) begin
          axi_rd_state_next = ST_RELOAD;
        end else begin
          axi_rd_state_next = ST_ADDR_INC;
        end
      end
    end

    default:
      axi_rd_state_next = ST_IDLE;
  endcase
end

//---------------------------------------------------------------------------------
//
//  interface to AXI

always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    dat_fifo_wr_r <= '0;
  end else begin
    dat_fifo_wr_r <= dat_fifo_wr;
  end
end

assign df_wr_rdy = !dat_fifo_full && !dat_fifo_wr && !dat_fifo_wr_r;

axi_rd_burst #(
  .DW  (DW),
  .AW  (AW),
  .LW  (LW)
) i_rdburst (
  // AXI master signals
  .axi_sys      (axi_sys            ),

  // configuration signals
  .cfg_clk_i    (dac_clk_i          ),
  .cfg_rstn_i   (dac_rstn_i         ),

  .ctrl_addr_i  (axi_read_addr      ),
  .ctrl_size_i  (axi_request_size   ),
  .ctrl_rsize_i (axi_read_size_bytes),
  .ctrl_val_i   (axi_read_start     ),

  // data
  .rd_data_o    (dat_fifo_idata_i   ),
  .rd_addr_o    (dat_fifo_iaddr     ),
  .rd_dval_o    (dat_fifo_wr        ),
  .rd_drdy_i    (df_wr_rdy          ),
  .ctrl_busy_o  (ctrl_busy          ),
  .stat_busy_o  (stat_busy          )
);

assign dat_fifo_idata = dat_fifo_idata_i;

endmodule
