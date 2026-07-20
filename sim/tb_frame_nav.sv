`timescale 1ns / 1ps

// Self-checking testbench for frame_nav: verifies BTNL/BTNR debounce +
// edge-detect (one step per press, not continuous while held),
// wraparound in both directions, autoplay ticking at the configured
// period only when enabled, and that a manual step during autoplay
// still works and restarts the autoplay timer.
module tb_frame_nav;

  localparam int NUM_FRAMES = 5;
  // Small for fast sim, but kept well clear of debounce's ~17-cycle
  // settle time (below) so button-press and autoplay-tick timing windows
  // can't ambiguously overlap -- the button's debounced edge can land
  // anywhere in roughly [17, 25] cycles after a press, so margins below
  // are sized well outside that uncertainty window.
  localparam int AUTOPLAY_PERIOD_CYCLES = 100;
  localparam int FRAME_IDX_W = $clog2(NUM_FRAMES);

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst, btnl_raw, btnr_raw, auto_play_en;
  logic [FRAME_IDX_W-1:0] frame_idx;
  logic frame_idx_changed;

  frame_nav #(
      .NUM_FRAMES(NUM_FRAMES),
      .AUTOPLAY_PERIOD_CYCLES(AUTOPLAY_PERIOD_CYCLES)
  ) dut (
      .clk              (clk),
      .rst              (rst),
      .btnl_raw         (btnl_raw),
      .btnr_raw         (btnr_raw),
      .auto_play_en     (auto_play_en),
      .frame_idx        (frame_idx),
      .frame_idx_changed(frame_idx_changed)
  );

  int mismatches = 0;
  int checks = 0;

  task automatic check(input string what, input int got, input int expected);
    checks++;
    if (got !== expected) begin
      $display("MISMATCH %s: got %0d expected %0d", what, got, expected);
      mismatches++;
    end
  endtask

  // debounce's default STABLE_CYCLES=17 -- hold a level for comfortably
  // more than that before trusting the debounced/edge-detected result.
  localparam int SETTLE_CYCLES = 25;

  initial begin
    rst          = 1'b1;
    btnl_raw     = 1'b0;
    btnr_raw     = 1'b0;
    auto_play_en = 1'b0;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    repeat (SETTLE_CYCLES) @(posedge clk);
    check("initial frame_idx", frame_idx, 0);

    // ---- one step per press, not continuous while held ----
    btnr_raw <= 1'b1;
    repeat (SETTLE_CYCLES) @(posedge clk);
    check("frame_idx after btnr rising edge settles", frame_idx, 1);
    repeat (SETTLE_CYCLES) @(posedge clk);  // still held
    check("frame_idx unchanged while btnr held", frame_idx, 1);
    repeat (SETTLE_CYCLES) @(posedge clk);  // still held, more margin
    check("frame_idx still unchanged after extended hold", frame_idx, 1);
    btnr_raw <= 1'b0;
    repeat (SETTLE_CYCLES) @(posedge clk);
    check("frame_idx after releasing btnr", frame_idx, 1);

    // ---- step right through wraparound (NUM_FRAMES-1 -> 0) ----
    // frame_idx is already 1 at this point (from the single-press check
    // above), so only NUM_FRAMES-2 more presses are needed to reach
    // NUM_FRAMES-1 before the wrap-triggering press below.
    for (int i = 0; i < NUM_FRAMES - 2; i++) begin
      btnr_raw <= 1'b1;
      repeat (SETTLE_CYCLES) @(posedge clk);
      btnr_raw <= 1'b0;
      repeat (SETTLE_CYCLES) @(posedge clk);
    end
    check("frame_idx reached NUM_FRAMES-1", frame_idx, NUM_FRAMES - 1);
    btnr_raw <= 1'b1;
    repeat (SETTLE_CYCLES) @(posedge clk);
    btnr_raw <= 1'b0;
    repeat (SETTLE_CYCLES) @(posedge clk);
    check("frame_idx wrapped right past the top", frame_idx, 0);

    // ---- step left through wraparound (0 -> NUM_FRAMES-1) ----
    btnl_raw <= 1'b1;
    repeat (SETTLE_CYCLES) @(posedge clk);
    btnl_raw <= 1'b0;
    repeat (SETTLE_CYCLES) @(posedge clk);
    check("frame_idx wrapped left below zero", frame_idx, NUM_FRAMES - 1);

    // ---- autoplay: no advance while disabled ----
    repeat (AUTOPLAY_PERIOD_CYCLES * 3) @(posedge clk);
    check("frame_idx unchanged with autoplay disabled", frame_idx, NUM_FRAMES - 1);

    // ---- autoplay: periodic advance while enabled ----
    // Wait windows are period+small margin (comfortably under 2x the
    // period), so each check observes exactly one tick, not two.
    auto_play_en <= 1'b1;
    repeat (AUTOPLAY_PERIOD_CYCLES + 10) @(posedge clk);
    check("frame_idx after one autoplay period", frame_idx, 0);
    repeat (AUTOPLAY_PERIOD_CYCLES) @(posedge clk);
    check("frame_idx after a second autoplay period", frame_idx, 1);

    // ---- manual step during autoplay still works and restarts the timer ----
    btnr_raw <= 1'b1;
    repeat (SETTLE_CYCLES) @(posedge clk);
    btnr_raw <= 1'b0;
    check("frame_idx after manual step during autoplay", frame_idx, 2);
    // The manual step's debounced edge (and the autoplay-timer restart it
    // triggers) can land anywhere within roughly the SETTLE_CYCLES window
    // above, not at a precisely known cycle -- so check "not yet
    // advanced" well before even the earliest possible next-tick time,
    // and "advanced" well after even the latest possible one.
    repeat (AUTOPLAY_PERIOD_CYCLES - 30) @(posedge clk);
    check("frame_idx not yet advanced well before the restarted period elapses", frame_idx, 2);
    repeat (30 + SETTLE_CYCLES) @(posedge clk);
    check("frame_idx advanced once the restarted autoplay period elapsed", frame_idx, 3);

    auto_play_en <= 1'b0;

    if (mismatches == 0) $display("ALL FRAME_NAV CHECKS PASSED (%0d total checks)", checks);
    else $display("FAIL: %0d total mismatches out of %0d checks", mismatches, checks);
    $finish;
  end

  initial begin
    #200_000;
    $display("FAIL: timeout in tb_frame_nav");
    $finish;
  end

endmodule
