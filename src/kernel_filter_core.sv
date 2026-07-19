`timescale 1ns / 1ps

// Generic reconfigurable NxN spatial convolution engine.
//
// This single datapath implements every kernel filter in this project --
// Sobel Gx, Sobel Gy, blur, identity, whatever -- by loading different
// `coeffs` values. Nothing about the hardware changes between filters,
// only the coefficients fed in on the `coeffs` port.
//
// Streaming interface: pixels arrive one per cycle, in raster-scan order,
// accompanied by their (row, col) position. The core buffers KSIZE-1 rows
// internally, forms a KSIZE x KSIZE sliding window, and once the window is
// fully populated with real image data (not stream/frame edges), emits one
// filtered output pixel per cycle at a fixed 3-cycle latency. Output
// coordinates refer to the *center* of the window, so the outer
// (KSIZE-1)/2-pixel border of the image never produces a valid output --
// there's no full neighborhood to convolve there.
//
// The output is intentionally left as a full-width signed accumulator
// (un-clamped, un-biased) since downstream consumers differ: Sobel Gx/Gy
// need the signed value for magnitude combination, while a filter meant to
// be displayed directly would need clamping/offset that doesn't belong in
// this shared core.
module kernel_filter_core #(
    parameter  int IMG_WIDTH  = 96,
    parameter  int IMG_HEIGHT = 64,
    parameter  int KSIZE      = 3,                                   // must be odd
    parameter  int PIX_W      = 8,                                   // unsigned input pixel width
    parameter  int COEF_W     = 8,                                   // signed coefficient width
    localparam int COL_W      = $clog2(IMG_WIDTH),
    localparam int ROW_W      = $clog2(IMG_HEIGHT),
    localparam int ACC_W      = PIX_W + COEF_W + $clog2(KSIZE*KSIZE) + 1
) (
    input logic clk,
    input logic rst,

    input logic             pix_valid_in,
    input logic [PIX_W-1:0] pix_in,
    input logic [COL_W-1:0] col_in,
    input logic [ROW_W-1:0] row_in,

    // Coefficient bank, row-major: coeffs[r*KSIZE + c]. Static or slowly
    // changing relative to the pixel stream -- not part of the pipelined
    // valid/ready timing.
    input logic signed [COEF_W-1:0] coeffs[0:(KSIZE*KSIZE)-1],
    input logic [3:0]               norm_shift,  // arithmetic right-shift applied to the raw sum

    output logic                   pix_valid_out,
    output logic signed [ACC_W-1:0] pix_out,
    output logic [COL_W-1:0]        col_out,
    output logic [ROW_W-1:0]        row_out
);

  // -----------------------------------------------------------------------
  // Stage 0: line buffers -> KSIZE row taps, all vertically aligned to the
  // same column (i.e. the same pixel column across KSIZE consecutive rows).
  // row_tap[0] is the newest (current) row, row_tap[KSIZE-1] is the oldest.
  // -----------------------------------------------------------------------
  logic [PIX_W-1:0] line_buf[0:KSIZE-2][0:IMG_WIDTH-1];
  logic [PIX_W-1:0] row_tap [0:KSIZE-1];

  // row_tap[r] must line up with coeffs row r (row-major, r=0 is the
  // *top* of the kernel), so the newest incoming pixel -- the bottom-most
  // row of the window -- goes in row_tap[KSIZE-1], not row_tap[0].
  always_ff @(posedge clk) begin
    if (pix_valid_in) begin
      row_tap[KSIZE-1] <= pix_in;
      if (KSIZE > 1) begin
        row_tap[KSIZE-2]     <= line_buf[0][col_in];
        line_buf[0][col_in] <= pix_in;
        for (int i = 1; i < KSIZE - 1; i++) begin
          row_tap[KSIZE-2-i]   <= line_buf[i][col_in];
          line_buf[i][col_in] <= line_buf[i-1][col_in];
        end
      end
    end
  end

  logic          v_s0;
  logic [COL_W-1:0] col_s0;
  logic [ROW_W-1:0] row_s0;

  always_ff @(posedge clk) begin
    if (rst) v_s0 <= 1'b0;
    else v_s0 <= pix_valid_in;
    if (pix_valid_in) begin
      col_s0 <= col_in;
      row_s0 <= row_in;
    end
  end

  // -----------------------------------------------------------------------
  // Stage 1: horizontal shift -- KSIZE row taps slide into a KSIZE x KSIZE
  // window, one new column per cycle. window[r][KSIZE-1] is always the
  // newest column; window[r][0] the oldest.
  // -----------------------------------------------------------------------
  logic [PIX_W-1:0] window[0:KSIZE-1][0:KSIZE-1];

  always_ff @(posedge clk) begin
    if (v_s0) begin
      for (int r = 0; r < KSIZE; r++) begin
        for (int c = 0; c < KSIZE - 1; c++) window[r][c] <= window[r][c+1];
        window[r][KSIZE-1] <= row_tap[r];
      end
    end
  end

  logic          v_s1;
  logic [COL_W-1:0] col_s1;
  logic [ROW_W-1:0] row_s1;

  always_ff @(posedge clk) begin
    if (rst) v_s1 <= 1'b0;
    else v_s1 <= v_s0;
    if (v_s0) begin
      col_s1 <= col_s0;
      row_s1 <= row_s0;
    end
  end

  // -----------------------------------------------------------------------
  // Stage 2: MAC -- sum of products over the full window, then normalize.
  // -----------------------------------------------------------------------
  localparam int PROD_W = PIX_W + COEF_W + 1;
  logic signed [PROD_W-1:0] products[0:(KSIZE*KSIZE)-1];

  always_comb begin
    for (int r = 0; r < KSIZE; r++)
      for (int c = 0; c < KSIZE; c++)
        products[r*KSIZE+c] = $signed({1'b0, window[r][c]}) * coeffs[r*KSIZE+c];
  end

  logic signed [ACC_W-1:0] sum_comb;
  always_comb begin
    sum_comb = '0;
    for (int k = 0; k < KSIZE * KSIZE; k++) sum_comb += ACC_W'(products[k]);
  end

  logic signed [ACC_W-1:0] acc_r;
  logic                    v_s2;
  logic [   COL_W-1:0]     col_s2;
  logic [   ROW_W-1:0]     row_s2;

  always_ff @(posedge clk) begin
    if (rst) v_s2 <= 1'b0;
    else v_s2 <= v_s1;
    if (v_s1) begin
      acc_r  <= sum_comb >>> norm_shift;
      col_s2 <= col_s1;
      row_s2 <= row_s1;
    end
  end

  // A pixel is only valid once the window holds real image data on every
  // tap: KSIZE-1 rows of history buffered, and KSIZE-1 real columns shifted
  // in since the start of the current row.
  //
  // This is tracked with counters relative to *this instance's own*
  // stream -- rows_seen/cols_in_row, incremented from the pix_valid_in
  // pattern itself -- rather than by comparing the incoming row_in/col_in
  // values against a fixed threshold. That distinction matters when
  // cascading: a downstream instance's col_in/row_in don't start at
  // (0,0), since the upstream stage already cropped its own border, so a
  // threshold test against the raw incoming coordinates would trigger one
  // row/column too early.
  localparam int MARGIN = (KSIZE - 1) / 2;

  logic [COL_W-1:0] prev_col_in;
  logic [ROW_W-1:0] prev_row_in;
  logic             have_prev;
  logic [ ROW_W:0]  rows_seen;
  logic [ COL_W:0]  cols_in_row;

  // Combinational next-state, including the *current* pixel's contribution --
  // needed so the shadow pipeline below captures a count that already
  // accounts for this pixel, not the pre-update value from the last one.
  //
  // A column that doesn't increase means a new row just started; a row
  // that *also* doesn't increase at that same moment means a new frame
  // just started (row_in wrapped back around), so rows_seen resets rather
  // than incrementing. This works the same way whether row_in/col_in are
  // absolute frame coordinates starting at (0,0), as from image_rom, or
  // an upstream kernel_filter_core's already-cropped coordinate stream --
  // both still monotonically increase within a frame and wrap at its end,
  // which is all this depends on. That's what makes stages composable.
  logic [ROW_W:0] rows_seen_next;
  logic [COL_W:0] cols_in_row_next;

  always_comb begin
    if (!have_prev) begin
      rows_seen_next   = (ROW_W + 1)'(1);
      cols_in_row_next = (COL_W + 1)'(1);
    end else if (col_in <= prev_col_in) begin
      rows_seen_next   = (row_in <= prev_row_in) ? (ROW_W + 1)'(1) : rows_seen + 1'b1;
      cols_in_row_next = (COL_W + 1)'(1);
    end else begin
      rows_seen_next   = rows_seen;
      cols_in_row_next = cols_in_row + 1'b1;
    end
  end

  always_ff @(posedge clk) begin
    if (rst) begin
      have_prev   <= 1'b0;
      rows_seen   <= '0;
      cols_in_row <= '0;
    end else if (pix_valid_in) begin
      have_prev   <= 1'b1;
      rows_seen   <= rows_seen_next;
      cols_in_row <= cols_in_row_next;
      prev_col_in <= col_in;
      prev_row_in <= row_in;
    end
  end

  logic [ROW_W:0] rows_seen_s0, rows_seen_s1;
  logic [COL_W:0] cols_in_row_s0, cols_in_row_s1;

  always_ff @(posedge clk) begin
    if (pix_valid_in) begin
      rows_seen_s0   <= rows_seen_next;
      cols_in_row_s0 <= cols_in_row_next;
    end
    if (v_s0) begin
      rows_seen_s1   <= rows_seen_s0;
      cols_in_row_s1 <= cols_in_row_s0;
    end
  end

  logic in_bounds_s2;
  always_ff @(posedge clk) begin
    if (v_s1) in_bounds_s2 <= (rows_seen_s1 >= KSIZE) && (cols_in_row_s1 >= KSIZE);
  end

  assign pix_valid_out = v_s2 && in_bounds_s2;
  assign pix_out        = acc_r;
  assign col_out        = col_s2 - COL_W'(MARGIN);
  assign row_out        = row_s2 - ROW_W'(MARGIN);

endmodule
