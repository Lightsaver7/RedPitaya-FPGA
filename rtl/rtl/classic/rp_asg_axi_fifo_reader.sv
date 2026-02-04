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
  output logic [14-1:0]       dac_o,
  input  logic               dac_clk_i,
  input  logic               dac_rstn_i,
  // trigger
  input  logic               trig_i,

  // configuration
  input  logic               set_rst_i,
  input  logic               set_axi_en_i,
  input  logic [32-1:0]       set_axi_start_i,
  input  logic [32-1:0]       set_axi_stop_i,
  input  logic [32-1:0]       set_axi_dec_i,
  input  logic [16-1:0]       set_cyc_cnt_i,
  output logic [20-1:0]       axi_state_o,
  output logic               axi_last_o,

  // start pulse to request AXI read
  output logic               start_pulse_o,

  // FIFO read-side interface
  input  logic [DW-1:0]       dat_fifo_out,
  input  logic               dat_rd_valid,
  input  logic               dat_fifo_empty,
  input  logic [RD_LVL_W-1:0] dat_rd_fifo_lvl,
  output logic               dat_fifo_rd
);

//---------------------------------------------------------------------------------

localparam int NUM_SAMPS = DW/16;

typedef enum logic [2:0] {
  RD_IDLE,
  RD_PRELOAD,
  RD_COLD_START,
  RD_READ,
  RD_READ_LAST,
  RD_VALID,
  RD_DECODING
} rd_state_t;

rd_state_t rd_state_q;
rd_state_t rd_state_d;

logic [AW-1:0] period_cnt_q;
logic [AW-1:0] period_words;
logic          last_pulse;
logic [31:0]   dec_wait_cycles;
logic [31:0]   dec_timer_q;
logic          dec_timeout;
logic [15:0]   cycle_cnt_q;

logic [15:0]   sample_buf [0:NUM_SAMPS-1];
logic [6:0]    preload_timer;
logic          fifo_active;
logic          dec_step;
logic [31:0]   dec_cnt_q;
logic [1:0]    sample_index;
logic          fifo_ready;

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

assign start_pulse_o = (trig_i & ~trig_r) && set_axi_en_i && (rd_state_q == RD_IDLE);

//---------------------------------------------------------------------------------
//
//  FSM for reading from fifo

// Read signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    dat_fifo_rd <= 1'b0;
  end else begin
    dat_fifo_rd <= 1'b0;

    if (rd_state_q == RD_PRELOAD && rd_state_d == RD_COLD_START) begin
      dat_fifo_rd <= 1'b1;
    end

    if (rd_state_q == RD_DECODING && rd_state_d == RD_READ) begin
      dat_fifo_rd <= 1'b1;
    end
  end
end

// period counter
// NOTE: incoming stop address is (real_stop - 4) due to upstream pipeline,
// so compensate by +4 to compute inclusive word count
assign period_words = ((set_axi_stop_i + 4 - set_axi_start_i) >> 3) + 1;
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    period_cnt_q <= 'b0;
  end else begin

    if (rd_state_q == RD_IDLE && rd_state_d == RD_PRELOAD) begin
      period_cnt_q <= period_words;
    end

    if (rd_state_q == RD_PRELOAD && rd_state_d == RD_COLD_START) begin
      if (|period_cnt_q)
        period_cnt_q <= period_cnt_q - 1;
    end

    if (rd_state_q == RD_DECODING && rd_state_d == RD_READ) begin
      if (|period_cnt_q)
        period_cnt_q <= period_cnt_q - 1;
      else
        period_cnt_q <= period_words - 1;
    end
  end
end

// Last signal
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    last_pulse <= 1'b0;
  end else begin
    last_pulse <= 1'b0;

    if (rd_state_q == RD_READ_LAST && sample_index == 2'b10) begin
      last_pulse <= 1'b1;
    end

    if (rd_state_q == RD_VALID && rd_state_d == RD_DECODING) begin
      if (period_cnt_q == (period_words - 1)) begin
        last_pulse <= 1'b1;
      end
    end
  end
end

// Cycle counter
always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    cycle_cnt_q <= 'b0;
  end else begin

    if (rd_state_q == RD_PRELOAD) begin
      cycle_cnt_q <= set_cyc_cnt_i;
    end

    if (rd_state_q == RD_DECODING && rd_state_d == RD_READ) begin
      if (!(|period_cnt_q) && |cycle_cnt_q)
        cycle_cnt_q <= cycle_cnt_q - 1;
    end
  end
end

// Decode pointer
always_ff @( posedge dac_clk_i ) begin : decode_pointer
  if (!dac_rstn_i || set_rst_i) begin
    sample_index <= 'b00;
  end else begin
    if ((rd_state_q == RD_READ ||
         rd_state_q == RD_READ_LAST ||
         rd_state_q == RD_DECODING ||
         rd_state_q == RD_VALID) &&
         rd_state_d != RD_IDLE) begin
      if (dec_step)
        sample_index <= sample_index + 1;
    end else begin
      sample_index <= 'b00;
    end
  end
end

always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    rd_state_q <= RD_IDLE;
  end else begin
    rd_state_q <= rd_state_d;
  end
end

always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    dec_timer_q <= 0;
  end else begin
    if (rd_state_q == RD_DECODING)
      dec_timer_q <= dec_timer_q + 1;
    else
      dec_timer_q <= 0;
  end
end

always_ff @( posedge dac_clk_i ) begin
  if (!dac_rstn_i || set_rst_i) begin
    preload_timer <= 0;
  end else begin
    if (rd_state_q == RD_PRELOAD)
      preload_timer <= preload_timer + 1;
    else if (rd_state_q == RD_IDLE)
      preload_timer <= 0;
  end
end

always_comb begin : fsm_fifo_read
  rd_state_d = rd_state_q;

  unique case (rd_state_q)
    RD_IDLE: begin
      if (start_pulse_o)
        rd_state_d = RD_PRELOAD;
    end

    RD_PRELOAD: begin
      // use a timer because the FIFO filling time is different for several channels.
      if (preload_timer >= FIFO_PRELOAD_SIZE)
        rd_state_d = RD_COLD_START;
    end

    RD_COLD_START: begin
      if (dat_rd_valid)
        rd_state_d = RD_DECODING;
    end

    RD_READ: begin
      rd_state_d = RD_VALID;
    end

    RD_VALID: begin
      if (dat_rd_valid)
        rd_state_d = RD_DECODING;
    end

    RD_DECODING: begin
      if (dec_timeout) begin
        if (|period_cnt_q) begin
          rd_state_d = RD_READ;
        end else begin
          if (cycle_cnt_q == 1)
            rd_state_d = RD_READ_LAST;
          else
            rd_state_d = RD_READ;
        end
      end
    end

    RD_READ_LAST: begin
      if (sample_index == 2'b11)
        rd_state_d = RD_IDLE;
    end

    default:
      rd_state_d = RD_IDLE;
  endcase
end

assign dec_wait_cycles = (set_axi_dec_i << 2) - 4;
assign dec_timeout     = dec_timer_q == dec_wait_cycles;
assign axi_last_o      = last_pulse;
assign fifo_active     = rd_state_q != RD_IDLE;
assign fifo_ready      = rd_state_q != RD_IDLE &&
                         rd_state_q != RD_PRELOAD &&
                         rd_state_q != RD_COLD_START;
assign axi_state_o  =  {1'b0,            // [19:19]
                        dat_rd_fifo_lvl, // [12:18]
                        5'b0,            // [7:11]
                        1'b0,            // [6:6]
                        dat_fifo_empty,  // [5:5]
                        1'b0,            // [4:4]
                        fifo_active,     // [3:3]
                        1'b0,            // [2:2]
                        fifo_ready,      // [1:1]
                        1'b0};           // [0:0]

always_ff @(posedge dac_clk_i) begin // reading data from 64 bit FIFO
  if (fifo_ready) // 1 clock delay due to inbuilt FIFO registers
    dac_o <= sample_buf[sample_index][14-1:0];
end

//---------------------------------------------------------------------------------
//
//  decimation timer

always_ff @(posedge dac_clk_i) begin
  if (!dac_rstn_i) begin
    dec_cnt_q <= 32'h1;
  end else begin
    if (fifo_ready) begin
      if (dec_cnt_q < set_axi_dec_i)
        dec_cnt_q <= dec_cnt_q + 1;
      else
        dec_cnt_q <= 32'h1;
    end else begin
      dec_cnt_q <= 32'h1;
    end
  end
end

assign dec_step = dec_cnt_q == set_axi_dec_i;

//---------------------------------------------------------------------------------
//
// data decoding

genvar GV;
generate
for (GV = 0; GV < NUM_SAMPS; GV = GV + 1) begin : read_decoder
  always_ff @(posedge dac_clk_i) begin
    if (!dac_rstn_i || set_rst_i) begin
      sample_buf[GV] <= '0;
    end else if (dat_rd_valid) begin
      sample_buf[GV] <= dat_fifo_out[GV*16 +: 16];
    end
  end
end
endgenerate

endmodule
