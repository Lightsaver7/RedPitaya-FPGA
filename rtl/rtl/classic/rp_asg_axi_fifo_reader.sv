/*
  FIFO reader and DAC output for ASG
  - Handles trigger, FIFO preload, decimation and output to DAC
*/

module rp_asg_axi_fifo_reader #(
  parameter int DW = 64,
  parameter int AW = 32,
  parameter int FIFO_PRELOAD_SIZE = 64,
  parameter int RD_LVL_W = 7
)(
  // DAC
  output logic [14-1:0]      dac_o,
  input  logic              dac_clk_i,
  input  logic              dac_rstn_i,
  // trigger
  input  logic              trig_i,

  // configuration
  input  logic              set_rst_i,
  input  logic              set_axi_en_i,
  input  logic [32-1:0]      set_axi_start_i,
  input  logic [32-1:0]      set_axi_stop_i,
  input  logic [32-1:0]      set_axi_dec_i,
  input  logic [16-1:0]      set_cyc_cnt_i,
  output logic [20-1:0]      axi_state_o,
  output logic              axi_last_o,

  // start pulse to request AXI read
  output logic              start_pulse_o,

  // FIFO read-side interface
  input  logic [DW-1:0]      dat_fifo_out,
  input  logic              dat_rd_valid,
  input  logic              dat_fifo_empty,
  input  logic [RD_LVL_W-1:0] dat_rd_fifo_lvl,
  output logic              dat_fifo_rd
);

//---------------------------------------------------------------------------------
//

localparam int NUM_SAMPS = DW/16;

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

logic [AW-1:0]  axi_period_size;
logic [AW-1:0]  period_size;
logic           axi_last;
logic [32-1:0]  decoding_time;
logic [32-1:0]  decoding_timer;
logic           decoding_timeout;
logic [16-1:0]  cyc_cnt;

logic [16-1:0]  samp_buf [0:NUM_SAMPS-1];
logic [7-1:0]   dat_fifo_rd_timer;
logic           df_first_valid;
logic           dac_rden;
logic           dec_val;
logic [32-1:0]  dec_cnt;
logic [2-1:0]   fifo_rd_rp;
logic           fifo_ready;

//---------------------------------------------------------------------------------
//
//  Trig sync

logic trig_r;

always_ff @(posedge dac_clk_i) begin
  if (!dac_rstn_i)
    trig_r <= 1'b0;
  else
    trig_r <= trig_i;
end

assign start_pulse_o = (trig_i & ~trig_r) && set_axi_en_i && (fifo_rd_state_registered == ST_RD_IDLE);

//---------------------------------------------------------------------------------
//
//  FSM for reading from fifo

// Read signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    dat_fifo_rd <= 'b0;
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
    axi_period_size <= 'b0;
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
    axi_last <= 'b0;
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

// Cycle counter
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
      if (start_pulse_o)
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

assign decoding_time    = (set_axi_dec_i << 2) - 4;
assign decoding_timeout = decoding_timer == decoding_time;
assign axi_last_o       = axi_last;
assign df_first_valid   = ~dat_fifo_empty;
assign dac_rden         = fifo_rd_state_registered != ST_RD_IDLE;
assign fifo_ready       = fifo_rd_state_registered != ST_RD_IDLE &&
                          fifo_rd_state_registered != ST_RD_PRELOAD &&
                          fifo_rd_state_registered != ST_RD_COLD_START;
assign axi_state_o  =  {1'b0,            // [19:19]
                        dat_rd_fifo_lvl, // [12:18]
                        5'b0,            // [7:11]
                        1'b0,            // [6:6]
                        dat_fifo_empty,  // [5:5]
                        1'b0,            // [4:4]
                        dac_rden,        // [3:3]
                        1'b0,            // [2:2]
                        fifo_ready,      // [1:1]
                        1'b0};           // [0:0]

always_ff @(posedge dac_clk_i) begin // reading data from 64 bit FIFO
  if (fifo_ready) // 1 clock delay due to inbuilt FIFO registers
    dac_o <= samp_buf[fifo_rd_rp][14-1:0];
end

//---------------------------------------------------------------------------------
//
//  decimation timer

always_ff @(posedge dac_clk_i) begin
  if (!dac_rstn_i) begin
    dec_cnt <= 32'h1;
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

//---------------------------------------------------------------------------------
//
// data decoding

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

endmodule
