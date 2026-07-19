`timescale 1ns / 1ps

// Focused test: two kernel_filter_core instances chained directly
// (identity -> Sobel Gx), isolated from sobel_pipeline's mode-mux/delay
// -matching logic, to check whether cascading itself (two stages, second
// one fed by the first one's already-cropped coordinate stream) is
// correct on its own.
module tb_cascade;

  localparam int IMG_WIDTH  = 16;
  localparam int IMG_HEIGHT = 10;
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

  logic signed [COEF_W-1:0] id_coeffs[0:8];
  logic signed [COEF_W-1:0] gx_coeffs[0:8];
  initial begin
    for (int i = 0; i < 9; i++) begin
      id_coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_coeffs_pkg::KID_IDENTITY, i);
      gx_coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_coeffs_pkg::KID_SOBEL_GX, i);
    end
  end

  logic signed [ACC_W-1:0] pre_raw;
  logic pre_valid;
  logic [COL_W-1:0] pre_col;
  logic [ROW_W-1:0] pre_row;
  logic [PIX_W-1:0] pre_pix;
  assign pre_pix = pre_raw[PIX_W-1:0];

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_pre (
      .clk(clk), .rst(rst),
      .pix_valid_in(pix_valid_in), .pix_in(pix_in), .col_in(col_in), .row_in(row_in),
      .coeffs(id_coeffs), .norm_shift(4'd0),
      .pix_valid_out(pre_valid), .pix_out(pre_raw), .col_out(pre_col), .row_out(pre_row)
  );

  logic signed [ACC_W-1:0] gx_raw;
  logic gx_valid;
  logic [COL_W-1:0] gx_col;
  logic [ROW_W-1:0] gx_row;

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_gx (
      .clk(clk), .rst(rst),
      .pix_valid_in(pre_valid), .pix_in(pre_pix), .col_in(pre_col), .row_in(pre_row),
      .coeffs(gx_coeffs), .norm_shift(4'd0),
      .pix_valid_out(gx_valid), .pix_out(gx_raw), .col_out(gx_col), .row_out(gx_row)
  );

  logic [7:0] img[0:NUM_PIX-1];
  initial $readmemh("tb_sobel_test_image.mem", img);

  function automatic int ref_gx(input int row, input int col);
    int sum;
    begin
      sum = 0;
      for (int dr = -1; dr <= 1; dr++)
        for (int dc = -1; dc <= 1; dc++)
          sum += int'(img[(row + dr) * IMG_WIDTH + (col + dc)]) * int'(kernel_coeffs_pkg::get_coeff(
              kernel_coeffs_pkg::KID_SOBEL_GX, (dr + 1) * 3 + (dc + 1)));
      ref_gx = sum;
    end
  endfunction

  int total_errors = 0;
  int total_checked = 0;
  bit seen[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

  int exp_val;
  always @(posedge clk) begin
    if (gx_valid) begin
      exp_val = ref_gx(gx_row, gx_col);
      total_checked++;
      if (seen[gx_row][gx_col]) begin
        $display("ERROR duplicate at row=%0d col=%0d", gx_row, gx_col);
        total_errors++;
      end
      seen[gx_row][gx_col] = 1'b1;
      if (int'(gx_raw) !== exp_val) begin
        $display("ERROR row=%0d col=%0d dut=%0d expected=%0d (pre_pix at emit=%0d)", gx_row, gx_col,
                  int'(gx_raw), exp_val, pre_pix);
        total_errors++;
      end
    end
  end

  initial begin
    rst          = 1'b1;
    pix_valid_in = 1'b0;
    pix_in       = '0;
    col_in       = '0;
    row_in       = '0;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    for (int i = 0; i < NUM_PIX; i++) begin
      pix_valid_in <= 1'b1;
      pix_in       <= img[i];
      col_in       <= COL_W'(i % IMG_WIDTH);
      row_in       <= ROW_W'(i / IMG_WIDTH);
      @(posedge clk);
    end
    pix_valid_in <= 1'b0;
    repeat (12) @(posedge clk);

    if (total_errors == 0) $display("ALL TESTS PASSED (%0d pixels checked)", total_checked);
    else $display("TESTS FAILED: %0d errors out of %0d pixels checked", total_errors, total_checked);
    $finish;
  end

endmodule
