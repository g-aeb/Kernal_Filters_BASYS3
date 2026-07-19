`timescale 1ns / 1ps

// Coefficient sets for kernel_filter_core. Every kernel here shares the
// same 3x3 hardware datapath -- only the tap values (and normalization
// shift) change between filters. Coefficients are exposed as functions
// (scalar in, scalar out) rather than array-typed parameters so that
// callers build a coeffs[] array with a simple per-element loop -- this
// keeps the package portable across simulators with uneven support for
// unpacked-array parameters, and synthesizes to the same constant-folded
// LUTs in Vivado either way.
package kernel_coeffs_pkg;

  localparam int KSIZE_3 = 3;

  localparam int KID_IDENTITY = 0;
  localparam int KID_SOBEL_GX = 1;
  localparam int KID_SOBEL_GY = 2;
  localparam int KID_BLUR     = 3;

  // Row-major tap index: idx = row*3 + col, idx 0 = top-left, idx 8 = bottom-right.
  function automatic logic signed [7:0] get_coeff(input int kernel_id, input int idx);
    unique case (kernel_id)
      KID_IDENTITY:
      unique case (idx)
        4:       get_coeff = 8'sd1;
        default: get_coeff = 8'sd0;
      endcase
      KID_SOBEL_GX:
      unique case (idx)
        0, 6:    get_coeff = -8'sd1;
        2, 8:    get_coeff = 8'sd1;
        3:       get_coeff = -8'sd2;
        5:       get_coeff = 8'sd2;
        default: get_coeff = 8'sd0;
      endcase
      KID_SOBEL_GY:
      unique case (idx)
        0, 2:    get_coeff = -8'sd1;
        6, 8:    get_coeff = 8'sd1;
        1:       get_coeff = -8'sd2;
        7:       get_coeff = 8'sd2;
        default: get_coeff = 8'sd0;
      endcase
      KID_BLUR:
      unique case (idx)
        0, 2, 6, 8: get_coeff = 8'sd1;
        1, 3, 5, 7: get_coeff = 8'sd2;
        4:          get_coeff = 8'sd4;
        default:    get_coeff = 8'sd0;
      endcase
      default: get_coeff = 8'sd0;
    endcase
  endfunction

  // Normalization: raw sum-of-products >>> shift.
  function automatic logic [3:0] get_shift(input int kernel_id);
    unique case (kernel_id)
      KID_IDENTITY: get_shift = 4'd0;
      KID_SOBEL_GX: get_shift = 4'd0;
      KID_SOBEL_GY: get_shift = 4'd0;
      KID_BLUR:     get_shift = 4'd4;  // weights sum to 16
      default:      get_shift = 4'd0;
    endcase
  endfunction

endpackage
