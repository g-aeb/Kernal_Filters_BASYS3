`timescale 1ns / 1ps

// Self-checking testbench for frame_store: verifies the
// frame_idx*NUM_PIX address-offset math, full-coverage streaming (every
// (col,row) of the selected frame visited exactly once per frame_start
// pass), and that a frame_idx change mid-stream does NOT corrupt an
// in-flight render (frame_idx is only latched into the frame base
// address at frame_start).
//
// The fixture (tb_frame_store_test.mem) is a pure ramp -- mem[i] = i mod
// 256 -- generated with:
//   python -c "
//   for f in range(5):
//       for p in range(12):
//           print(f'{(f*12+p) % 256:02x}')
//   " > sim/tb_frame_store_test.mem
// so the reference model is a formula (frame*NUM_PIX + row*IMG_WIDTH+col)
// mod 256, not a second copied array.
//
// Out-of-range frame_idx is deliberately NOT exercised here -- keeping
// frame_idx within [0, NUM_FRAMES) is frame_nav's contract, not
// frame_store's to defend against.
module tb_frame_store;

  localparam int IMG_WIDTH = 4;
  localparam int IMG_HEIGHT = 3;
  localparam int PIX_W = 8;
  localparam int NUM_FRAMES = 5;
  localparam int NUM_PIX = IMG_WIDTH * IMG_HEIGHT;
  localparam int COL_W = $clog2(IMG_WIDTH);
  localparam int ROW_W = $clog2(IMG_HEIGHT);
  localparam int FRAME_IDX_W = $clog2(NUM_FRAMES);

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst, frame_start, rd_en;
  logic [FRAME_IDX_W-1:0] frame_idx;
  logic pix_valid;
  logic [PIX_W-1:0] pix_data;
  logic [COL_W-1:0] col;
  logic [ROW_W-1:0] row;

  frame_store #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .PIX_W     (PIX_W),
      .NUM_FRAMES(NUM_FRAMES),
      .INIT_FILE ("tb_frame_store_test.mem")
  ) dut (
      .clk        (clk),
      .rst        (rst),
      .frame_start(frame_start),
      .rd_en      (rd_en),
      .frame_idx  (frame_idx),
      .pix_valid  (pix_valid),
      .pix_data   (pix_data),
      .col        (col),
      .row        (row)
  );

  int mismatches = 0;
  int checks = 0;
  bit seen[0:NUM_PIX-1];

  // Streams one full frame (NUM_PIX valid cycles) for `frame`, checking
  // every (pix_data, col, row) triple against the ramp formula and
  // tracking full pixel coverage.
  task automatic stream_and_check(input int frame);
    int pos, expected;
    for (int i = 0; i < NUM_PIX; i++) seen[i] = 1'b0;

    frame_idx   <= FRAME_IDX_W'(frame);
    frame_start <= 1'b1;
    rd_en       <= 1'b0;
    @(posedge clk);
    frame_start <= 1'b0;
    rd_en       <= 1'b1;

    for (int i = 0; i < NUM_PIX; i++) begin
      @(posedge clk);
      #1;  // let nonblocking updates settle before sampling
      if (pix_valid) begin
        pos      = int'(row) * IMG_WIDTH + int'(col);
        expected = (frame * NUM_PIX + pos) % 256;
        checks++;
        if (int'(pix_data) !== expected) begin
          $display("MISMATCH frame=%0d col=%0d row=%0d: got %0d expected %0d", frame, col, row, pix_data,
                    expected);
          mismatches++;
        end
        if (seen[pos]) begin
          $display("DUP frame=%0d col=%0d row=%0d seen twice", frame, col, row);
          mismatches++;
        end
        seen[pos] = 1'b1;
      end
    end
    rd_en <= 1'b0;

    for (int i = 0; i < NUM_PIX; i++) begin
      if (!seen[i]) begin
        $display("MISSING frame=%0d pixel index %0d never visited", frame, i);
        mismatches++;
      end
    end
  endtask

  initial begin
    rst         = 1'b1;
    frame_start = 1'b0;
    rd_en       = 1'b0;
    frame_idx   = '0;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    // Full addressing + coverage check for every frame in the store.
    for (int f = 0; f < NUM_FRAMES; f++) stream_and_check(f);
    $display("PASS: all %0d frames streamed with correct addressing and full pixel coverage (%0d checks so far)",
              NUM_FRAMES, checks);

    // Latch-at-frame_start check: start frame 2, then change frame_idx
    // mid-stream to 4 and confirm the in-flight stream stays on frame 2.
    begin
      int frame, pos, expected, wrong_frame_seen;
      frame            = 2;
      wrong_frame_seen = 0;

      frame_idx   <= FRAME_IDX_W'(frame);
      frame_start <= 1'b1;
      rd_en       <= 1'b0;
      @(posedge clk);
      frame_start <= 1'b0;
      rd_en       <= 1'b1;

      for (int i = 0; i < NUM_PIX; i++) begin
        @(posedge clk);
        #1;
        if (i == NUM_PIX / 2) frame_idx <= FRAME_IDX_W'(4);  // change mid-stream
        if (pix_valid) begin
          pos      = int'(row) * IMG_WIDTH + int'(col);
          expected = (frame * NUM_PIX + pos) % 256;
          checks++;
          if (int'(pix_data) !== expected) begin
            wrong_frame_seen++;
            $display("MISMATCH (mid-stream frame_idx change) col=%0d row=%0d: got %0d expected %0d", col, row,
                      pix_data, expected);
          end
        end
      end
      rd_en <= 1'b0;

      if (wrong_frame_seen == 0)
        $display("PASS: frame_idx change mid-stream did not corrupt the in-flight frame");
      else begin
        $display("FAIL: %0d mismatches after mid-stream frame_idx change", wrong_frame_seen);
        mismatches += wrong_frame_seen;
      end
    end

    if (mismatches == 0) $display("ALL FRAME_STORE CHECKS PASSED (%0d total checks)", checks);
    else $display("FAIL: %0d total mismatches out of %0d checks", mismatches, checks);
    $finish;
  end

endmodule
