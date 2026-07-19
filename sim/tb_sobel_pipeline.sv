`timescale 1ns / 1ps

// Integration testbench for sobel_pipeline: streams a small known image
// through the full pre-stage -> Gx/Gy -> mode-mux datapath for every
// combination of disp_mode and cascade_en, and checks both the pixel
// count (border-crop bookkeeping across two cascaded 3x3 stages) and the
// actual values against a from-scratch behavioral reference model.
module tb_sobel_pipeline;

  localparam int IMG_WIDTH  = 16;
  localparam int IMG_HEIGHT = 10;
  localparam int KSIZE      = 3;
  localparam int PIX_W      = 8;
  localparam int COEF_W     = 8;
  localparam int NUM_PIX    = IMG_WIDTH * IMG_HEIGHT;
  localparam int COL_W      = $clog2(IMG_WIDTH);
  localparam int ROW_W      = $clog2(IMG_HEIGHT);
  localparam int MARGIN     = 2;  // two cascaded 3x3 stages, 1px crop each

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst;
  logic pix_valid_in;
  logic [PIX_W-1:0] pix_in;
  logic [COL_W-1:0] col_in;
  logic [ROW_W-1:0] row_in;
  logic [1:0] disp_mode;
  logic cascade_en;

  logic pix_valid_out;
  logic [PIX_W-1:0] disp_val_out;
  logic [COL_W-1:0] col_out;
  logic [ROW_W-1:0] row_out;

  sobel_pipeline #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W),
      .KSIZE     (KSIZE)
  ) dut (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pix_valid_in),
      .pix_in       (pix_in),
      .col_in       (col_in),
      .row_in       (row_in),
      .disp_mode    (disp_mode),
      .cascade_en   (cascade_en),
      .pix_valid_out(pix_valid_out),
      .disp_val_out (disp_val_out),
      .col_out      (col_out),
      .row_out      (row_out)
  );

  logic [7:0] img[0:NUM_PIX-1];
  initial $readmemh("tb_sobel_test_image.mem", img);

  function automatic int pre_val(input int row, input int col, input int cascade_en);
    int kid;
    int sum;
    begin
      kid = cascade_en ? kernel_coeffs_pkg::KID_BLUR : kernel_coeffs_pkg::KID_IDENTITY;
      sum = 0;
      for (int dr = -1; dr <= 1; dr++)
        for (int dc = -1; dc <= 1; dc++)
          sum += int'(img[(row + dr) * IMG_WIDTH + (col + dc)]) * int'(kernel_coeffs_pkg::get_coeff(
              kid, (dr + 1) * 3 + (dc + 1)));
      pre_val = sum >>> kernel_coeffs_pkg::get_shift(kid);
    end
  endfunction

  function automatic int grad_val(input int row, input int col, input int cascade_en, input int kid);
    int sum;
    begin
      sum = 0;
      for (int dr = -1; dr <= 1; dr++)
        for (int dc = -1; dc <= 1; dc++)
          sum += pre_val(row + dr, col + dc, cascade_en) * int'(kernel_coeffs_pkg::get_coeff(
              kid, (dr + 1) * 3 + (dc + 1)));
      grad_val = sum;
    end
  endfunction

  function automatic int disp_val_ref(input int row, input int col, input int mode, input int cascade_en);
    int gx, gy, a;
    begin
      case (mode)
        0: disp_val_ref = pre_val(row, col, cascade_en);
        1: begin
          gx = grad_val(row, col, cascade_en, kernel_coeffs_pkg::KID_SOBEL_GX);
          a = gx < 0 ? -gx : gx;
          disp_val_ref = (a > 255) ? 255 : a;
        end
        2: begin
          gy = grad_val(row, col, cascade_en, kernel_coeffs_pkg::KID_SOBEL_GY);
          a = gy < 0 ? -gy : gy;
          disp_val_ref = (a > 255) ? 255 : a;
        end
        default: begin
          gx = grad_val(row, col, cascade_en, kernel_coeffs_pkg::KID_SOBEL_GX);
          gy = grad_val(row, col, cascade_en, kernel_coeffs_pkg::KID_SOBEL_GY);
          a  = (gx < 0 ? -gx : gx) + (gy < 0 ? -gy : gy);
          disp_val_ref = (a > 255) ? 255 : a;
        end
      endcase
    end
  endfunction

  int total_errors = 0;
  int total_checked = 0;
  int cur_mode, cur_cascade;
  int exp_val;
  bit seen[0:IMG_HEIGHT-1][0:IMG_WIDTH-1];

  always @(posedge clk) begin
    if (pix_valid_out) begin
      exp_val = disp_val_ref(row_out, col_out, cur_mode, cur_cascade);
      total_checked++;
      if (seen[row_out][col_out]) begin
        $display("ERROR duplicate output at row=%0d col=%0d", row_out, col_out);
        total_errors++;
      end
      seen[row_out][col_out] = 1'b1;
      if (int'(disp_val_out) !== exp_val) begin
        $display("ERROR mode=%0d cascade=%0d row=%0d col=%0d dut=%0d expected=%0d", cur_mode,
                  cur_cascade, row_out, col_out, int'(disp_val_out), exp_val);
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
    repeat (12) @(posedge clk);
  endtask

  task automatic run_case(input int mode, input int cascade);
    int checked_before, errors_before, valid_count_before;
    int expected_count;
    for (int r = 0; r < IMG_HEIGHT; r++)
      for (int c = 0; c < IMG_WIDTH; c++) seen[r][c] = 1'b0;
    disp_mode   = 2'(mode);
    cascade_en  = cascade[0];
    cur_mode    = mode;
    cur_cascade = cascade;
    checked_before = total_checked;
    errors_before  = total_errors;
    stream_frame();

    expected_count = (IMG_WIDTH - 2 * MARGIN) * (IMG_HEIGHT - 2 * MARGIN);
    if (total_checked - checked_before != expected_count) begin
      $display("ERROR mode=%0d cascade=%0d wrong valid count: got=%0d expected=%0d", mode, cascade,
                total_checked - checked_before, expected_count);
      total_errors++;
    end

    $display("[mode=%0d cascade=%0d] checked=%0d new_errors=%0d", mode, cascade,
              total_checked - checked_before, total_errors - errors_before);
  endtask

  initial begin
    rst          = 1'b1;
    pix_valid_in = 1'b0;
    pix_in       = '0;
    col_in       = '0;
    row_in       = '0;
    disp_mode    = 2'b11;
    cascade_en   = 1'b0;
    repeat (4) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);

    for (int cascade = 0; cascade < 2; cascade++)
      for (int mode = 0; mode < 4; mode++) run_case(mode, cascade);

    if (total_errors == 0) $display("ALL TESTS PASSED (%0d pixels checked)", total_checked);
    else $display("TESTS FAILED: %0d errors out of %0d pixels checked", total_errors, total_checked);

    $finish;
  end

endmodule
