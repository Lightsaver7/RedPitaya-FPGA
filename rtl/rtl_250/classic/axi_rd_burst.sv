/*
A queued AXI read requester.
Request and data FIFOs must be external.
*/


// synopsys translate_off
`timescale 1ns / 1ps
// synopsys translate_on

module axi_rd_burst #(
  parameter   DW  =  64          , // data width (8,16,...,1024)
  parameter   DWB =  DW/8        , // data width in bytes
  parameter   DWW =  $clog2(DWB),
  parameter   AW  =  32          , // address width
  parameter   LW  =   8          , // length width
  parameter   BYTE_SEL = 0       ,
  parameter   FW  = 4            , // legacy, kept for compatibility
  parameter   SW  = DW >> 3      , // strobe width - 1 bit for every data byte
  parameter   CMD_FIFO_DEPTH = 8
)
(
   // AXI master signals
   axi_sys_if.s           axi_sys            ,

   // configuration signals
   input                  cfg_clk_i          , // config clock
   input                  cfg_rstn_i         , // config reset

   input       [ AW-1: 0] ctrl_addr_i        , // request start address
   input       [ LW-1: 0] ctrl_size_i        , // request size (beats-1)
   input       [  3-1: 0] ctrl_rsize_i       , // read size (in bytes)
   input                  ctrl_val_i         , // request transfer
   output                 ctrl_rdy_o         , // request accepted

   // data
   output reg  [ DW-1: 0] rd_data_o          , // read data @axi_clk
   output reg  [ AW-1: 0] rd_addr_o          , // debug address stream @axi_clk
   output reg             rd_dval_o          , // read data valid @axi_clk
   input                  rd_drdy_i          , // read data ready @axi_clk

   output      [ 32-1: 0] diags_o            , // diagnostics @axi_clk


   output reg             ctrl_busy_o        , // status @axi_clk
   output reg             stat_busy_o          // status @cfg_clk
);

//---------------------------------------------------------------------------------
//
// Command queue

localparam integer CMD_AW = (CMD_FIFO_DEPTH <= 2) ? 1 : $clog2(CMD_FIFO_DEPTH);
localparam integer CMD_W  = AW + LW + 3;
localparam integer BEATS_W = LW + CMD_AW + 2;

reg [CMD_W-1:0] cmd_fifo [0:CMD_FIFO_DEPTH-1];
reg [CMD_AW-1:0] cmd_wr_ptr;
reg [CMD_AW-1:0] cmd_rd_ptr;
reg [CMD_AW:0]   cmd_fill_lvl;

wire cmd_full  = cmd_fill_lvl == CMD_FIFO_DEPTH;
wire cmd_empty = cmd_fill_lvl == 0;
wire cmd_push  = ctrl_val_i && !cmd_full;
wire cmd_pop   = !cmd_empty && (!axi_sys.rvalid || axi_sys.rardy);

assign ctrl_rdy_o = !cmd_full;

always @ (posedge axi_sys.clk)
begin
   if (!axi_sys.rstn) begin
      cmd_wr_ptr   <= 'h0;
      cmd_rd_ptr   <= 'h0;
      cmd_fill_lvl <= 'h0;
   end
   else begin
      if (cmd_push) begin
         cmd_fifo[cmd_wr_ptr] <= {ctrl_rsize_i, ctrl_size_i, ctrl_addr_i};
         cmd_wr_ptr <= cmd_wr_ptr + 1'b1;
      end

      if (cmd_pop) begin
         cmd_rd_ptr <= cmd_rd_ptr + 1'b1;
      end

      case ({cmd_push, cmd_pop})
        2'b10: cmd_fill_lvl <= cmd_fill_lvl + 1'b1;
        2'b01: cmd_fill_lvl <= cmd_fill_lvl - 1'b1;
        default: cmd_fill_lvl <= cmd_fill_lvl;
      endcase
   end
end

//---------------------------------------------------------------------------------
//
// Read address channel

reg [BEATS_W-1:0] beats_pending;
wire [CMD_W-1:0] cmd_head = cmd_fifo[cmd_rd_ptr];
wire [2:0]       cmd_rsize = cmd_head[CMD_W-1 -: 3];
wire [LW-1:0]    cmd_size  = cmd_head[AW+LW-1 -: LW];
wire [AW-1:0]    cmd_addr  = cmd_head[AW-1:0];

wire ar_xfer = axi_sys.ARtransfer;
wire r_xfer  = axi_sys.Rtransfer;

always @ (posedge axi_sys.clk)
begin
   if (!axi_sys.rstn) begin
      axi_sys.rvalid <= 1'b0;
      axi_sys.raddr  <= {AW{1'b0}};
      axi_sys.rlen   <= {LW{1'b0}};
      axi_sys.rsize  <= 3'h0;
      axi_sys.rfixed <= 1'b0;
   end
   else begin
      axi_sys.rfixed <= 1'b0;

      if (cmd_pop) begin
         axi_sys.rvalid <= 1'b1;
         axi_sys.raddr  <= cmd_addr;
         axi_sys.rlen   <= cmd_size;
         axi_sys.rsize  <= cmd_rsize;
      end
      else if (axi_sys.rvalid && axi_sys.rardy) begin
         axi_sys.rvalid <= 1'b0;
      end
   end
end

always @ (posedge axi_sys.clk)
begin
   if (!axi_sys.rstn) begin
      beats_pending <= 'h0;
   end
   else begin
      case ({ar_xfer, r_xfer})
        2'b10: beats_pending <= beats_pending + {{(BEATS_W-LW){1'b0}}, axi_sys.rlen} + 1'b1;
        2'b01: if (beats_pending > 0)
                 beats_pending <= beats_pending - 1'b1;
        2'b11: beats_pending <= beats_pending + {{(BEATS_W-LW){1'b0}}, axi_sys.rlen};
        default: beats_pending <= beats_pending;
      endcase
   end
end

//------------------------------------------------------------------------------
// Data channel / consumer interface

assign axi_sys.rrdys = rd_drdy_i;

always @(posedge axi_sys.clk)
begin
   if (!axi_sys.rstn) begin
      rd_data_o <= {DW{1'b0}};
      rd_dval_o <= 1'b0;
      rd_addr_o <= {AW{1'b0}};
   end
   else begin
      rd_data_o <= axi_sys.rdata;
      rd_dval_o <= r_xfer;

      // Debug-only address stream tracker.
      if (ar_xfer)
         rd_addr_o <= axi_sys.raddr;
      else if (r_xfer)
         rd_addr_o <= rd_addr_o + DWB;
   end
end

//------------------------------------------------------------------------------
// Status

wire busy_axi = axi_sys.rvalid || !cmd_empty || (beats_pending != 0);
wire [31:0] beats_pending_ext = beats_pending;
wire [31:0] cmd_fill_ext      = cmd_fill_lvl;

always @(posedge axi_sys.clk)
begin
   if (!axi_sys.rstn)
      ctrl_busy_o <= 1'b0;
   else
      ctrl_busy_o <= busy_axi;
end

assign diags_o = {
  5'h0,
  beats_pending_ext[9:0],
  cmd_fill_ext[7:0],
  axi_sys.rvalid,
  axi_sys.rardy,
  axi_sys.Rtransfer,
  ctrl_rdy_o,
  cmd_pop,
  cmd_push,
  busy_axi,
  2'b0
};

//------------------------------------------------------------------------------
// cfg domain

reg [1:0] stat_busy_csff;

always @ (posedge cfg_clk_i)
begin
   if (!cfg_rstn_i) begin
      stat_busy_csff <= 2'h0;
      stat_busy_o    <= 1'b0;
   end
   else begin
      stat_busy_csff <= {stat_busy_csff[0], busy_axi};
      stat_busy_o    <= stat_busy_csff[1];
   end
end

endmodule // axi_rd_burst
