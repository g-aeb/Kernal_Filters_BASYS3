`timescale 1ns / 1ps

// Owns frame browsing: debounces BTNL/BTNR, edge-detects each into a
// single one-cycle step pulse per press (not continuous while held),
// and maintains frame_idx, wrapping in both directions. When
// auto_play_en is high, a free-running timer also advances frame_idx at
// AUTOPLAY_PERIOD_CYCLES intervals -- any manual step (while autoplay is
// on or off) restarts that timer, so a button press never fights with an
// autoplay tick landing on the same or a nearby cycle.
module frame_nav #(
    parameter int NUM_FRAMES = 24,
    parameter int AUTOPLAY_PERIOD_CYCLES = 25_000_000,  // 4 fps @ 100MHz; override small for sim
    localparam int FRAME_IDX_W = (NUM_FRAMES > 1) ? $clog2(NUM_FRAMES) : 1
) (
    input logic clk,
    input logic rst,

    input logic btnl_raw,
    input logic btnr_raw,
    input logic auto_play_en,

    output logic [FRAME_IDX_W-1:0] frame_idx,
    output logic                   frame_idx_changed  // one-cycle pulse: manual step or autoplay tick
);

  logic btnl_db, btnr_db, btnl_db_prev, btnr_db_prev;

  debounce u_db_btnl (
      .clk(clk),
      .rst(rst),
      .in (btnl_raw),
      .out(btnl_db)
  );
  debounce u_db_btnr (
      .clk(clk),
      .rst(rst),
      .in (btnr_raw),
      .out(btnr_db)
  );

  always_ff @(posedge clk) begin
    if (rst) begin
      btnl_db_prev <= 1'b0;
      btnr_db_prev <= 1'b0;
    end else begin
      btnl_db_prev <= btnl_db;
      btnr_db_prev <= btnr_db;
    end
  end

  logic step_dec_pulse, step_inc_pulse;
  assign step_dec_pulse = btnl_db & ~btnl_db_prev;
  assign step_inc_pulse = btnr_db & ~btnr_db_prev;

  localparam int AP_W = $clog2(AUTOPLAY_PERIOD_CYCLES);
  logic [AP_W-1:0] autoplay_cnt;
  logic autoplay_tick;

  always_ff @(posedge clk) begin
    if (rst || !auto_play_en || step_dec_pulse || step_inc_pulse) begin
      autoplay_cnt  <= '0;
      autoplay_tick <= 1'b0;
    end else if (autoplay_cnt == AP_W'(AUTOPLAY_PERIOD_CYCLES - 1)) begin
      autoplay_cnt  <= '0;
      autoplay_tick <= 1'b1;
    end else begin
      autoplay_cnt  <= autoplay_cnt + 1'b1;
      autoplay_tick <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      frame_idx <= '0;
    end else if (step_dec_pulse) begin
      frame_idx <= (frame_idx == '0) ? FRAME_IDX_W'(NUM_FRAMES - 1) : frame_idx - 1'b1;
    end else if (step_inc_pulse || autoplay_tick) begin
      frame_idx <= (frame_idx == FRAME_IDX_W'(NUM_FRAMES - 1)) ? '0 : frame_idx + 1'b1;
    end
  end

  assign frame_idx_changed = step_dec_pulse | step_inc_pulse | autoplay_tick;

endmodule
