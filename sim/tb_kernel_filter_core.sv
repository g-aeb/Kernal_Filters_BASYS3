`timescale 1ns / 1ps

import kernel_coeffs_pkg::*;

// Self-checking testbench for kernel_filter_core. Streams a small known
// test image through the DUT for several coefficient sets (identity,
// Sobel Gx, Sobel Gy, blur) and compares every output pixel against a
// behavioral reference convolution computed directly from the same image
// array, verifying both the numeric result and the pipeline's row/col
// bookkeeping (coverage: every interior pixel seen exactly once).
module tb_kernel_filter_core;

  localparam int IMG_WIDTH  = 12;
  localparam int IMG_HEIGHT = 9;
  localparam int KSIZE      = 3;
  localparam int PIX_W      = 8;
  localparam int COEF_W     = 8;
  localparam int NUM_PIX    = IMG_WIDTH * IMG_HEIGHT;
  localparam int COL_W      = $clog2(IMG_WIDTH);
  localparam int ROW_W      = $clog2(IMG_HEIGHT);
  localparam int ACC_W      = PIX_W + COEF_W + $clog2(KSIZE * KSIZE) + 1;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst;
  logic pix_valid_in;
  logic [PIX_W-1:0] pix_in;
  logic [COL_W-1:0] col_in;
  logic [ROW_W-1:0] row_in;
  logic signed [COEF_W-1:0] coeffs[0:8];
  logic [3:0] norm_shift;

  logic pix_valid_out;
  logic signed [ACC_W-1:0] pix_out;
  logic [COL_W-1:0] col_out;
  logic [ROW_W-1:0] row_out;

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) dut (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pix_valid_in),
      .pix_in       (pix_in),
      .col_in       (col_in),
      .row_in       (row_in),
      .coeffs       (coeffs),
      .norm_shift   (norm_shift),
      .pix_valid_out(pix_valid_out),
      .pix_out      (pix_out),
      .col_out      (col_out),
      .row_out      (row_out)
  );

  logic [7:0] img[0:NUM_PIX-1];
  initial $readmemh("tb_test_image.mem", img);

  int cur_kernel_id;

  function automatic int ref_conv(input int row, input int col, input int kernel_id);
    int sum;
    begin
      sum = 0;
      for (int dr = -1; dr <= 1; dr++)
        for (int dc = -1; dc <= 1; dc++)
          sum += int'(img[(row + dr) * IMG_WIDTH + (col + dc)]) * int'(kernel_coeffs_pkg::get_coeff(
              kernel_id, (dr + 1) * 3 + (dc + 1)));
      ref_conv = sum >>> kernel_coeffs_pkg::get_shift(kernel_id);
    end
  endfunction

  int total_errors = 0;
  int total_checked = 0;
  bit seen[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

  // Scoreboard: watch DUT outputs continuously in the background.
  int exp_val;
  always @(posedge clk) begin
    if (pix_valid_out) begin
      exp_val = ref_conv(row_out, col_out, cur_kernel_id);
      total_checked++;
      if (seen[row_out][col_out]) begin
        $display("[%0t] ERROR duplicate output at row=%0d col=%0d", $time, row_out, col_out);
        total_errors++;
      end
      seen[row_out][col_out] = 1'b1;
      if (int'(pix_out) !== exp_val) begin
        $display("[%0t] ERROR row=%0d col=%0d dut=%0d expected=%0d", $time, row_out, col_out,
                  int'(pix_out), exp_val);
        total_errors++;
      end
    end
  end

  task automatic stream_frame();
    for (int i = 0; i < NUM_PIX; i++) begin
      pix_valid_in <= 1'b1;
      pix_in       <= img[i];
      col_in       <= COL_W'(i % IMG_WIDTH);
      row_in       <= ROW_W'(i / IMG_WIDTH);
      @(posedge clk);
    end
    pix_valid_in <= 1'b0;
    repeat (KSIZE + 3) @(posedge clk);
  endtask

  task automatic run_case(input string name, input int kernel_id);
    int checked_before;
    int errors_before;
    for (int r = 0; r < IMG_HEIGHT; r++)
      for (int cc = 0; cc < IMG_WIDTH; cc++) seen[r][cc] = 1'b0;
    for (int i = 0; i < KSIZE * KSIZE; i++) coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_id, i);
    norm_shift     = kernel_coeffs_pkg::get_shift(kernel_id);
    cur_kernel_id  = kernel_id;
    checked_before = total_checked;
    errors_before  = total_errors;
    stream_frame();

    // Coverage check: every interior pixel must have been seen exactly once.
    for (int r = 1; r < IMG_HEIGHT - 1; r++) begin
      for (int cc = 1; cc < IMG_WIDTH - 1; cc++) begin
        if (!seen[r][cc]) begin
          $display("ERROR [%s] missing output at row=%0d col=%0d", name, r, cc);
          total_errors++;
        end
      end
    end

    $display("[%s] checked=%0d new_errors=%0d", name, total_checked - checked_before,
              total_errors - errors_before);
  endtask

  initial begin
    rst          = 1'b1;
    pix_valid_in = 1'b0;
    pix_in       = '0;
    col_in       = '0;
    row_in       = '0;
    for (int i = 0; i < KSIZE * KSIZE; i++) coeffs[i] = kernel_coeffs_pkg::get_coeff(KID_IDENTITY, i);
    norm_shift = kernel_coeffs_pkg::get_shift(KID_IDENTITY);
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    run_case("IDENTITY", KID_IDENTITY);
    run_case("SOBEL_GX", KID_SOBEL_GX);
    run_case("SOBEL_GY", KID_SOBEL_GY);
    run_case("BLUR", KID_BLUR);

    if (total_errors == 0) $display("ALL TESTS PASSED (%0d pixels checked)", total_checked);
    else $display("TESTS FAILED: %0d errors out of %0d pixels checked", total_errors, total_checked);

    $finish;
  end

endmodule
