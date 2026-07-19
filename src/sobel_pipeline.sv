`timescale 1ns / 1ps

// Composes four instances of the shared kernel_filter_core into the full
// Sobel edge-detection datapath:
//
//                                          +-> [bypass: identity] -> bypass --+
//   pix_in -> [pre-stage: identity/blur] --+-> [Gx]                -> gx     --+--> mode mux -> disp_val
//                                          +-> [Gy]                -> gy     --+
//
// The pre-stage is always present in the pipeline; when cascade_en is low
// it's loaded with the identity kernel (pure pass-through), and when high
// it's loaded with a blur kernel. Either way it demonstrates the same
// point as the Gx/Gy/bypass stages downstream of it: identical hardware,
// different coefficients. Cascading it ahead of Gx/Gy/bypass (rather than
// wiring pix_in around it) also means every mode has the same fixed
// pipeline latency and border crop, so a single coordinate stream can
// drive the frame buffer regardless of disp_mode. The bypass stage exists
// purely so "show the pre-stage's own output" goes through a
// kernel_filter_core instance with the exact same latency as Gx/Gy,
// instead of a hand-matched delay line that has to track their timing.
//
// disp_mode:
//   00 = bypass      (pre-stage output, i.e. original or blurred image)
//   01 = Gx only     (vertical-edge gradient magnitude)
//   10 = Gy only     (horizontal-edge gradient magnitude)
//   11 = magnitude   (combined Sobel edge magnitude, |Gx| + |Gy|)
module sobel_pipeline #(
    parameter int IMG_WIDTH  = 96,
    parameter int IMG_HEIGHT = 64,
    parameter int PIX_W      = 8,
    parameter int COEF_W     = 8,
    parameter int KSIZE      = 3
) (
    input logic clk,
    input logic rst,

    input logic                          pix_valid_in,
    input logic [             PIX_W-1:0] pix_in,
    input logic [$clog2(IMG_WIDTH)-1:0]  col_in,
    input logic [$clog2(IMG_HEIGHT)-1:0] row_in,

    input logic [1:0] disp_mode,
    input logic       cascade_en,

    output logic                          pix_valid_out,
    output logic [             PIX_W-1:0] disp_val_out,
    output logic [$clog2(IMG_WIDTH)-1:0]  col_out,
    output logic [$clog2(IMG_HEIGHT)-1:0] row_out
);

  localparam int COL_W = $clog2(IMG_WIDTH);
  localparam int ROW_W = $clog2(IMG_HEIGHT);
  localparam int ACC_W = PIX_W + COEF_W + $clog2(KSIZE * KSIZE) + 1;

  // -----------------------------------------------------------------------
  // Pre-stage: identity or blur, selected by cascade_en. Reuses the exact
  // same kernel_filter_core as Gx/Gy -- only the coefficients differ.
  // -----------------------------------------------------------------------
  logic signed [COEF_W-1:0] pre_coeffs[0:(KSIZE*KSIZE)-1];
  logic [3:0] pre_shift;
  int pre_kid;

  always_comb begin
    pre_kid = cascade_en ? kernel_coeffs_pkg::KID_BLUR : kernel_coeffs_pkg::KID_IDENTITY;
    for (int i = 0; i < KSIZE * KSIZE; i++) pre_coeffs[i] = kernel_coeffs_pkg::get_coeff(pre_kid, i);
    pre_shift = kernel_coeffs_pkg::get_shift(pre_kid);
  end

  logic                signed [ACC_W-1:0] pre_pix_raw;
  logic                                   pre_valid;
  logic [COL_W-1:0]                       pre_col;
  logic [ROW_W-1:0]                       pre_row;

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_pre (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pix_valid_in),
      .pix_in       (pix_in),
      .col_in       (col_in),
      .row_in       (row_in),
      .coeffs       (pre_coeffs),
      .norm_shift   (pre_shift),
      .pix_valid_out(pre_valid),
      .pix_out      (pre_pix_raw),
      .col_out      (pre_col),
      .row_out      (pre_row)
  );

  // Identity/blur coefficients are non-negative and normalized, so the
  // pre-stage output is always a valid 0..255 pixel -- truncation is safe.
  logic [PIX_W-1:0] pre_pix;
  assign pre_pix = pre_pix_raw[PIX_W-1:0];

  // -----------------------------------------------------------------------
  // Gx / Gy stages, fed by the pre-stage's (already-cropped) output stream.
  // -----------------------------------------------------------------------
  logic signed [ACC_W-1:0] gx_raw, gy_raw;
  logic                    gx_valid, gy_valid;
  logic [    COL_W-1:0]    gx_col, gy_col;
  logic [    ROW_W-1:0]    gx_row, gy_row;

  logic signed [COEF_W-1:0] gx_coeffs[0:(KSIZE*KSIZE)-1];
  logic signed [COEF_W-1:0] gy_coeffs[0:(KSIZE*KSIZE)-1];

  always_comb begin
    for (int i = 0; i < KSIZE * KSIZE; i++) begin
      gx_coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_coeffs_pkg::KID_SOBEL_GX, i);
      gy_coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_coeffs_pkg::KID_SOBEL_GY, i);
    end
  end

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_gx (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pre_valid),
      .pix_in       (pre_pix),
      .col_in       (pre_col),
      .row_in       (pre_row),
      .coeffs       (gx_coeffs),
      .norm_shift   (kernel_coeffs_pkg::get_shift(kernel_coeffs_pkg::KID_SOBEL_GX)),
      .pix_valid_out(gx_valid),
      .pix_out      (gx_raw),
      .col_out      (gx_col),
      .row_out      (gx_row)
  );

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_gy (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pre_valid),
      .pix_in       (pre_pix),
      .col_in       (pre_col),
      .row_in       (pre_row),
      .coeffs       (gy_coeffs),
      .norm_shift   (kernel_coeffs_pkg::get_shift(kernel_coeffs_pkg::KID_SOBEL_GY)),
      .pix_valid_out(gy_valid),
      .pix_out      (gy_raw),
      .col_out      (gy_col),
      .row_out      (gy_row)
  );

  // Bypass stage: identity kernel, fed by the exact same pre_valid/pre_pix
  // stream as Gx/Gy. Earlier this was a hand-rolled shift-register chain
  // sized to "match" Gx/Gy's latency by manual cycle-counting -- fragile,
  // and it got the count wrong (verified against the testbench). Running
  // it through kernel_filter_core instead guarantees identical latency by
  // construction, since it's structurally the same instance as u_gx/u_gy.
  logic signed [COEF_W-1:0] bypass_coeffs[0:(KSIZE*KSIZE)-1];
  always_comb begin
    for (int i = 0; i < KSIZE * KSIZE; i++)
      bypass_coeffs[i] = kernel_coeffs_pkg::get_coeff(kernel_coeffs_pkg::KID_IDENTITY, i);
  end

  logic signed [ACC_W-1:0] bypass_raw;
  logic                    bypass_valid;
  logic [    COL_W-1:0]    bypass_col;
  logic [    ROW_W-1:0]    bypass_row;

  kernel_filter_core #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .KSIZE     (KSIZE),
      .PIX_W     (PIX_W),
      .COEF_W    (COEF_W)
  ) u_bypass (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (pre_valid),
      .pix_in       (pre_pix),
      .col_in       (pre_col),
      .row_in       (pre_row),
      .coeffs       (bypass_coeffs),
      .norm_shift   (kernel_coeffs_pkg::get_shift(kernel_coeffs_pkg::KID_IDENTITY)),
      .pix_valid_out(bypass_valid),
      .pix_out      (bypass_raw),
      .col_out      (bypass_col),
      .row_out      (bypass_row)
  );

  // gx, gy and bypass are all fed the identical upstream stream through
  // structurally identical kernel_filter_core instances, so their
  // valid/coord timing is always in lockstep -- gx's is used as the
  // canonical reference throughout.

  // -----------------------------------------------------------------------
  // Magnitude combine (registered, 1 cycle): |Gx| + |Gy|, saturated.
  // -----------------------------------------------------------------------
  logic       mag_valid;
  logic [PIX_W-1:0] mag_val;

  magnitude_combine #(
      .IN_W (ACC_W),
      .OUT_W(PIX_W)
  ) u_mag (
      .clk      (clk),
      .rst      (rst),
      .valid_in (gx_valid),
      .gx_in    (gx_raw),
      .gy_in    (gy_raw),
      .valid_out(mag_valid),
      .mag_out  (mag_val)
  );

  // -----------------------------------------------------------------------
  // Gx-only / Gy-only display candidates: |value|, saturated to PIX_W bits,
  // registered once to match magnitude_combine's 1-cycle latency.
  // -----------------------------------------------------------------------
  function automatic logic [PIX_W-1:0] abs_sat(input logic signed [ACC_W-1:0] v);
    logic [ACC_W-1:0] a;
    begin
      a = (v < 0) ? ACC_W'(-v) : ACC_W'(v);
      abs_sat = (a > {PIX_W{1'b1}}) ? {PIX_W{1'b1}} : a[PIX_W-1:0];
    end
  endfunction

  logic [PIX_W-1:0] gx_disp_r, gy_disp_r, bypass_disp_r;
  always_ff @(posedge clk) begin
    if (gx_valid) begin
      gx_disp_r     <= abs_sat(gx_raw);
      gy_disp_r     <= abs_sat(gy_raw);
      // Identity coefficients are non-negative and normalized, so this is
      // always a valid 0..255 pixel -- truncation is safe, same as pre_pix.
      bypass_disp_r <= bypass_raw[PIX_W-1:0];
    end
  end

  // Coordinates, delayed by 1 cycle to match the registered candidates above.
  logic [COL_W-1:0] col_r;
  logic [ROW_W-1:0] row_r;
  logic             valid_r;
  always_ff @(posedge clk) begin
    if (rst) valid_r <= 1'b0;
    else valid_r <= gx_valid;
    if (gx_valid) begin
      col_r <= gx_col;
      row_r <= gx_row;
    end
  end

  // -----------------------------------------------------------------------
  // Final mode mux + output register.
  // -----------------------------------------------------------------------
  logic [PIX_W-1:0] disp_comb;
  always_comb begin
    unique case (disp_mode)
      2'b00:   disp_comb = bypass_disp_r;
      2'b01:   disp_comb = gx_disp_r;
      2'b10:   disp_comb = gy_disp_r;
      2'b11:   disp_comb = mag_val;
      default: disp_comb = mag_val;
    endcase
  end

  always_ff @(posedge clk) begin
    if (rst) pix_valid_out <= 1'b0;
    else pix_valid_out <= valid_r;
    if (valid_r) begin
      disp_val_out <= disp_comb;
      col_out       <= col_r;
      row_out       <= row_r;
    end
  end

endmodule
