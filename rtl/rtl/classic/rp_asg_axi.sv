/*
Implements several features:
1) Reads data from the axi cyclically and continuously fills the fifo
2) Implements logic for reading a single entire buffer from the fifo

TODO Split the logic into several modules
TODO Fix synchronization issues with signals from different clock domains 

    +-------------+       +------------+     +------+      +--------------+
    |             |       |            |     |      |      |              |
---->  read addr  +------>| sync_fifo  +-----> FSM  <------+ axi_rd_burst |
    |             |       |            |     |      |      |              |
    +-------------+       +------------+     +--+---+      +--------------+
                                                |                          
                                                |                          
                    +------------+       +------v-------+                  
                    |            |       |              |                  
<-------------------+  Read FSM  |<------+ asg_dat_fifo |                  
                    |            |       |              |                  
                    +------------+       +--------------+                  
 */

module rp_asg_axi #(
  parameter RSZ=16
)(
   // DAC
   output reg  [ 14-1: 0] dac_o           ,  //!< dac data output
   input                  dac_clk_i       ,  //!< dac clock
   input                  dac_rstn_i      ,  //!< dac reset - active low
   // trigger
   input                  trig_i          ,  //!< software trigger
   // buffer ctrl
   axi_sys_if.s           axi_sys         ,

   // configuration
   input                  set_rst_i       ,  //!< set FSM to reset
   input                  set_axi_en_i    ,  //!< enable AXI buffer read
   input      [  32-1: 0] set_axi_start_i ,  //!< AXI start address
   input      [  32-1: 0] set_axi_stop_i  ,  //!< AXI stop address
   input      [  32-1: 0] set_axi_dec_i   ,  //!< AXI decimation
   input      [  16-1: 0] set_cyc_cnt_i   ,  //!< limit number of writes
   output     [  20-1: 0] axi_state_o     ,  //!< AXI state
   output                 axi_last_o         //!< AXI final sample
);

//---------------------------------------------------------------------------------
//

localparam DW = 64;
localparam AW = 32;
localparam LW =  4;
localparam AXI_BURST_LEN    = 16;
localparam AXI_BURST_BYTES  = AXI_BURST_LEN*DW/8;
localparam NUM_SAMPS        = DW/16;
localparam DATA_REQUEST_LEVEL = 128-16;
localparam FIFO_PRELOAD_SIZE = 64;

assign dac_rd_size  = AXI_BURST_LEN-1;
assign dac_rd_rsize =  3'h3;

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


typedef enum logic [2:0] {
  ST_RD_IDLE,
  ST_RD_PRELOAD,
  ST_RD_COLD_START,
  ST_RD_READ,
  ST_RD_READ_LAST,
  ST_RD_VALID,
  ST_RD_DECODING
} fifo_read_state_t;

fifo_read_state_t fifo_rd_state_registered; 
fifo_read_state_t fifo_rd_state_next;


logic [   AW-1:0] axi_read_addr;
logic [   AW-1:0] axi_start_addr;
logic [   AW-1:0] axi_stop_addr;
logic [   AW-1:0] axi_request_size;
logic [   AW-1:0] axi_period_size;
logic [   AW-1:0] period_size;
logic [   AW-1:0] axi_read_size_bytes;
logic             axi_read_start;
logic             axi_fsm_reset;
logic             axi_fifo_reset;
logic             axi_last;
logic [   32-1:0] decoding_time;
logic [   32-1:0] decoding_timer;
logic             decoding_timeout;
logic [   16-1:0] cyc_cnt;


reg   [ 16-1:0]   samp_buf [0:NUM_SAMPS-1]; // sample buffer
logic [   AW-1:0] dac_rd_size;
logic [    3-1:0] dac_rd_rsize;

logic [   DW-1:0] dat_fifo_idata; 
logic [   AW-1:0] dat_fifo_iaddr; 
logic             dat_fifo_wr;
logic             dat_fifo_wr_r;
logic             dat_fifo_full;
logic [   DW-1:0] dat_fifo_out;
logic [   7-1:0]  dat_fifo_rd_timer;
logic             df_wr_rdy;
logic             dat_fifo_rst_busy;

logic             dat_fifo_rd;
logic             dat_fifo_empty;
logic             df_first_valid;
logic             dac_rden;
logic             dec_val;
logic             dat_rd_valid;

logic [    7-1:0] dat_rd_fifo_lvl; 
logic [    7-1:0] dat_wr_fifo_lvl; 


logic             ctrl_busy; 
logic             stat_busy; 

logic [   32-1:0] dec_cnt; 
logic [    2-1:0] fifo_rd_rp; 

// //---------------------------------------------------------------------------------
// //
// //  Trig sync

logic trig_r;
logic start_pulse_dac;

always_ff @(posedge dac_clk_i) begin
  if (!dac_rstn_i)
    trig_r <= 1'b0;
  else
    trig_r <= trig_i;
end

assign start_pulse_dac = (trig_i & ~trig_r) && set_axi_en_i && (fifo_rd_state_registered == ST_RD_IDLE);

// //---------------------------------------------------------------------------------
// //
// //  addr cfg sync for axi

logic req_fifo_rd_valid;
logic req_fifo_empty;
logic [  64-1:0] req_fifo_in;
logic [  64-1:0] req_fifo_out;
logic [  64-1:0] req_fifo_out_r;
logic [  32-1:0] req_start_addr;
logic [  32-1:0] req_stop_addr;
wire req_fifo_rd = (axi_rd_state_registered == ST_IDLE) && !req_fifo_empty;
assign req_fifo_in = {set_axi_start_i, set_axi_stop_i};

// Always stores only one request
sync_fifo inst_sync_fifo
( 
  .wr_clk         (dac_clk_i        ),
  .rd_clk         (axi_sys.clk      ),
  .rst            (!dac_rstn_i      ),
  .din            (req_fifo_in      ),
  .wr_en          (start_pulse_dac  ),
  .full           (                 ),
  .dout           (req_fifo_out     ),
  .rd_en          (req_fifo_rd      ),
  .empty          (req_fifo_empty   ),
  .valid          (req_fifo_rd_valid),
  .wr_rst_busy    (                 ),
  .rd_rst_busy    (                 )
);

// commands for AXI module
always @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    req_fifo_out_r <= '0;
  end else if (req_fifo_rd_valid) begin
    req_fifo_out_r <= req_fifo_out;
  end
end

assign req_start_addr  =  req_fifo_out_r[1*AW +: AW];
assign req_stop_addr   =  req_fifo_out_r[0*AW +: AW];

// //---------------------------------------------------------------------------------
// //
// //  FSM reset sync

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

// //---------------------------------------------------------------------------------
// //
// //  FSM for reading from axi to fifo

always_ff @( posedge axi_sys.clk ) begin
  if (!axi_sys.rstn || axi_fsm_reset) begin
    axi_rd_state_registered <= ST_IDLE;
    axi_read_addr       <= '0;
    axi_request_size    <= '0;
    axi_read_size_bytes <= '0;
    axi_read_start      <= '0;
    axi_start_addr      <= '0;
    axi_stop_addr       <= '0;
    axi_fifo_reset      <= '0;
  end else begin
    axi_rd_state_registered <= axi_rd_state_next;
    axi_read_start <= 1'b0;
    axi_fifo_reset <= 1'b0;

    if (axi_rd_state_registered == ST_IDLE) begin
      axi_fifo_reset <= 1'b1; 
    end

    if (axi_rd_state_registered == ST_INIT) begin
      axi_start_addr <= req_start_addr;
      axi_stop_addr <= req_stop_addr;

      axi_request_size <= dac_rd_size;
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
  axi_rd_state_next             = axi_rd_state_registered;

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

// //---------------------------------------------------------------------------------
// //
// //  FSM for reading from fifo

// Read signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    dat_fifo_rd              <= 'b0;
  end else begin
    dat_fifo_rd <= 'b0;

    if (fifo_rd_state_registered == ST_RD_PRELOAD && fifo_rd_state_next == ST_RD_COLD_START) begin
      dat_fifo_rd <= 'b1;
    end

    if (fifo_rd_state_registered == ST_RD_DECODING && fifo_rd_state_next == ST_RD_READ) begin
      dat_fifo_rd <= 'b1;
    end
  end
end

// period counter
// NOTE: incoming stop address is (real_stop - 4) due to upstream pipeline,
// so compensate by +4 to compute inclusive word count
assign period_size = ((set_axi_stop_i + 4 - set_axi_start_i) >> 3) + 1;
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    axi_period_size          <= 'b0;
  end else begin

    if (fifo_rd_state_registered == ST_RD_IDLE && fifo_rd_state_next == ST_RD_PRELOAD) begin
      axi_period_size <= period_size;
    end

    if (fifo_rd_state_registered == ST_RD_PRELOAD && fifo_rd_state_next == ST_RD_COLD_START) begin
      if (|axi_period_size)
        axi_period_size <= axi_period_size - 1;
    end

    if (fifo_rd_state_registered == ST_RD_DECODING && fifo_rd_state_next == ST_RD_READ) begin
      if (|axi_period_size)
        axi_period_size <= axi_period_size - 1;
      else
        axi_period_size <= period_size - 1;
    end
  end
end

// Last signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    axi_last                 <= 'b0;
  end else begin
    axi_last  <= 'b0;

    if (fifo_rd_state_registered == ST_RD_READ_LAST && fifo_rd_rp == 2'b10) begin
      axi_last <= 1'b1;
    end

    if (fifo_rd_state_registered == ST_RD_VALID && fifo_rd_state_next == ST_RD_DECODING) begin
      if (axi_period_size == (period_size - 1)) begin
        axi_last <= 1'b1;
      end
    end
  end
end
      
// Last signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    cyc_cnt <= 'b0;
  end else begin

    if (fifo_rd_state_registered == ST_RD_PRELOAD) begin
      cyc_cnt <= set_cyc_cnt_i;
    end

    if (fifo_rd_state_registered == ST_RD_DECODING && fifo_rd_state_next == ST_RD_READ) begin
      if (!(|axi_period_size) && |cyc_cnt)
        cyc_cnt <= cyc_cnt - 1;
    end
  end
end

// Decode pointer
always_ff @( posedge dac_clk_i ) begin : decode_pointer
  if (!dac_rstn_i || set_rst_i) begin
    fifo_rd_rp <= 'b00;
  end else begin
    if ((fifo_rd_state_registered == ST_RD_READ || 
         fifo_rd_state_registered == ST_RD_READ_LAST || 
         fifo_rd_state_registered == ST_RD_DECODING || 
         fifo_rd_state_registered == ST_RD_VALID) && 
         fifo_rd_state_next != ST_RD_IDLE) begin
      if (dec_val)
        fifo_rd_rp <= fifo_rd_rp + 1;
    end else begin
      fifo_rd_rp <= 'b00;
    end
  end
end

always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    fifo_rd_state_registered <= ST_RD_IDLE;
  end else begin
    fifo_rd_state_registered <= fifo_rd_state_next;
  end
end

always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    decoding_timer <= 0;
  end else begin
    if (fifo_rd_state_registered == ST_RD_DECODING)
      decoding_timer <= decoding_timer + 1;
    else
      decoding_timer <= 0;
  end
end


always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    dat_fifo_rd_timer <= ST_RD_IDLE;
  end else begin
    if (fifo_rd_state_registered == ST_RD_PRELOAD)
      dat_fifo_rd_timer <= dat_fifo_rd_timer + 1;
    else if (fifo_rd_state_registered == ST_RD_IDLE)
      dat_fifo_rd_timer <= 0;
  end
end


always_comb begin : fsm_fifo_read
  fifo_rd_state_next = fifo_rd_state_registered;

  unique case (fifo_rd_state_registered)
    ST_RD_IDLE: begin
      if (start_pulse_dac)
        fifo_rd_state_next = ST_RD_PRELOAD;
    end

    ST_RD_PRELOAD: begin
      // use a timer because the FIFO filling time is different for several channels.
      if (dat_fifo_rd_timer >= FIFO_PRELOAD_SIZE)
        fifo_rd_state_next = ST_RD_COLD_START;
    end

    ST_RD_COLD_START: begin
      if (dat_rd_valid)
        fifo_rd_state_next = ST_RD_DECODING;
    end
    
    ST_RD_READ: begin
      fifo_rd_state_next = ST_RD_VALID;
    end

    ST_RD_VALID: begin
      if (dat_rd_valid)
        fifo_rd_state_next = ST_RD_DECODING;
    end

    ST_RD_DECODING: begin
      if (decoding_timeout) begin
        if (|axi_period_size) begin
          fifo_rd_state_next = ST_RD_READ;        
        end else begin
          if (cyc_cnt == 1)
            fifo_rd_state_next = ST_RD_READ_LAST;
          else 
            fifo_rd_state_next = ST_RD_READ;   
        end
      end
    end

    ST_RD_READ_LAST: begin
      if (fifo_rd_rp == 2'b11)
        fifo_rd_state_next = ST_RD_IDLE;
    end

    default: 
      fifo_rd_state_next = ST_RD_IDLE;
  endcase
end

assign decoding_time = (set_axi_dec_i << 2) - 4;
assign decoding_timeout = decoding_timer == decoding_time;
assign axi_last_o     = axi_last;
assign df_first_valid = ~dat_fifo_empty;
assign df_wr_rdy    = !dat_fifo_full && !dat_fifo_wr && !dat_fifo_wr_r;
assign dac_rden     = fifo_rd_state_registered != ST_RD_IDLE;
assign fifo_ready   = fifo_rd_state_registered != ST_RD_IDLE && fifo_rd_state_registered != ST_RD_PRELOAD && fifo_rd_state_registered != ST_RD_COLD_START;
assign axi_state_o  =  {1'b0,           // [19:19]
                        dat_rd_fifo_lvl,// [12:18]
                        5'b0,           // [7:11]
                        1'b0,           // [6:6]
                        dat_fifo_empty, // [5:5]
                        1'b0,           // [4:4]
                        dac_rden,       // [3:3]
                        1'b0,           // [2:2]
                        fifo_ready,     // [1:1]
                        1'b0};          // [0:0]


always_ff @(posedge axi_sys.clk) begin
  if (!axi_sys.rstn) begin
    dat_fifo_wr_r <= '0;
  end else begin
    dat_fifo_wr_r <= dat_fifo_wr;
  end
end

always_ff @(posedge dac_clk_i) begin // reading data from 64 bit FIFO
  if (fifo_ready) // 1 clock delay due to inbuilt FIFO registers
    dac_o  <= samp_buf[fifo_rd_rp][14-1:0];
end

// //---------------------------------------------------------------------------------
// //
// //  decimation timer

always_ff @(posedge dac_clk_i) begin
  if (!dac_rstn_i) begin
    dec_cnt <=  32'h1 ;
  end else begin
    if (fifo_ready) begin
      if (dec_cnt < set_axi_dec_i)
        dec_cnt <= dec_cnt + 1;
      else
        dec_cnt <= 32'h1;
    end else begin 
        dec_cnt <= 32'h1;
    end
  end
end

assign dec_val = dec_cnt == set_axi_dec_i;

// //---------------------------------------------------------------------------------
// //
// // data decoding

genvar GV;
generate
for (GV = 0; GV < NUM_SAMPS; GV = GV + 1) begin : read_decoder
  always_ff @(posedge dac_clk_i) begin
    if (!dac_rstn_i || set_rst_i) begin
      samp_buf[GV] <= '0;
    end else if (dat_rd_valid) begin
      samp_buf[GV] <= dat_fifo_out[GV*16 +: 16];  
    end
  end
end
endgenerate


// //---------------------------------------------------------------------------------
// //
// // axi memory -> fifo -> output

asg_dat_fifo inst_asg_dat_fifo
(
  .wr_clk         (axi_sys.clk      ),
  .rd_clk         (dac_clk_i        ),
  .rst            (axi_fifo_reset   ),
  .din            (dat_fifo_idata   ),
  .wr_en          (dat_fifo_wr      ),
  .wr_data_count  (dat_wr_fifo_lvl  ),
  .full           (dat_fifo_full    ),
  .dout           (dat_fifo_out     ),
  .rd_en          (dat_fifo_rd      ),
  .rd_data_count  (dat_rd_fifo_lvl  ),
  .valid          (dat_rd_valid     ),
  .empty          (dat_fifo_empty   ),
  .wr_rst_busy    (dat_fifo_rst_busy),
  .rd_rst_busy    (                 )
);

//---------------------------------------------------------------------------------
//
//  interface to AXI

  axi_rd_burst #(
    .DW  (  DW  ) , // data width (8,16,...,1024)
    .AW  (  AW  ) , // address width
    .LW  (  LW  )   // address width of FIFO pointers
  )
  i_rdburst
  (

    // AXI master signals
    .axi_sys      (  axi_sys          ) ,

    // configuration signals
    .cfg_clk_i    (  dac_clk_i        ) , // config clock
    .cfg_rstn_i   (  dac_rstn_i       ) , // config reset

    .ctrl_addr_i  (  axi_read_addr      ) , // request start address
    .ctrl_size_i  (  axi_request_size   ) , // request size
    .ctrl_rsize_i (  axi_read_size_bytes) , // read size ( in bytes)
    .ctrl_val_i   (  axi_read_start     ) , // request transfer

    // data
    .rd_data_o    (  dat_fifo_idata   ) , // read data
    .rd_addr_o    (  dat_fifo_iaddr   ) , // read data
    .rd_dval_o    (  dat_fifo_wr      ) , // read data valid
    .rd_drdy_i    (  df_wr_rdy        ) , // read data ready
    .ctrl_busy_o  (  ctrl_busy        ) , // busy @axi_clk
    .stat_busy_o  (  stat_busy        )   // status @cfg_clk
  );

// ila_1 dac_clk_dut (
// 	.clk(dac_clk_i), // input wire clk

// 	.probe0(trig_i),                    // [0:0]
// 	.probe1(dat_rd_fifo_lvl),           // [6:0]
// 	.probe2(dat_fifo_rd),               // [0:0]
// 	.probe3(dat_fifo_out),              // [63:0]
// 	.probe4(fifo_rd_state_next),        // [2:0]
// 	.probe5(fifo_rd_state_registered),  // [2:0]
// 	.probe6(dac_o),                     // [13:0]
// 	.probe7(dec_cnt[16-1:0]),           // [15:0]
// 	.probe8(fifo_rd_rp),                // [2:0]
//   .probe9(dat_rd_valid),              // [0:0]
//   .probe10(axi_period_size),          // [31:0]
//   .probe11(set_axi_start_i),          // [31:0]
//   .probe12(set_axi_stop_i),           // [31:0]
//   .probe13(axi_last_o),               // [0:0]
//   .probe14(dec_val),                  // [0:0]
//   .probe15(cyc_cnt),                   // [15:0]
//   .probe16(dec_val),                  // [0:0]
//   .probe17(dec_val),                  // [0:0]
//   .probe18(dec_val)                   // [0:0]
// );

// ila_0 axi_dut (
// 	.clk(axi_sys.clk), // input wire clk

// 	.probe0(start_pulse_dac),          // [0:0]  
// 	.probe1(req_stop_addr),            // [31:0] 
// 	.probe2(axi_request_size),          // [3:0] 
// 	.probe3(ctrl_busy),                 // [0:0] 
// 	.probe4(req_fifo_out),            // [63:0] 
// 	.probe5(req_start_addr),           // [31:0] 
// 	.probe6(dat_fifo_wr),               // [0:0] 
// 	.probe7(df_wr_rdy),                 // [0:0]
// 	.probe8(axi_read_start),            // [0:0]
// 	.probe9(set_rst_i),                 // [0:0]
//   .probe10(axi_rd_state_next),        // [2:0]
//   .probe11(axi_rd_state_registered),  // [2:0]
//   .probe12({1'b0, dat_wr_fifo_lvl})   // [7:0]
// );

endmodule
