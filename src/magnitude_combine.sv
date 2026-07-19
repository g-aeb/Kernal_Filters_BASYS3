`timescale 1ns / 1ps

// Combines two signed gradient outputs (Gx, Gy) into a single unsigned
// edge-magnitude pixel: mag = |gx| + |gy|, saturated to OUT_W bits.
// This is the L1 (city-block) approximation of sqrt(gx^2 + gy^2) -- avoids
// a square root in hardware at the cost of some accuracy, which is the
// standard tradeoff for real-time Sobel edge detection.
module magnitude_combine #(
    parameter int IN_W  = 21,
    parameter int OUT_W = 8
) (
    input logic clk,
    input logic rst,

    input logic                    valid_in,
    input logic signed [IN_W-1:0]  gx_in,
    input logic signed [IN_W-1:0]  gy_in,

    output logic             valid_out,
    output logic [OUT_W-1:0] mag_out
);

  logic [IN_W-1:0] abs_gx, abs_gy;
  logic [  IN_W:0] sum;

  always_comb begin
    abs_gx = (gx_in < 0) ? IN_W'(-gx_in) : IN_W'(gx_in);
    abs_gy = (gy_in < 0) ? IN_W'(-gy_in) : IN_W'(gy_in);
    sum    = {1'b0, abs_gx} + {1'b0, abs_gy};
  end

  localparam [IN_W:0] MAX_OUT = (1 << OUT_W) - 1;

  always_ff @(posedge clk) begin
    if (rst) begin
      valid_out <= 1'b0;
      mag_out   <= '0;
    end else begin
      valid_out <= valid_in;
      mag_out   <= (sum > MAX_OUT) ? {OUT_W{1'b1}} : sum[OUT_W-1:0];
    end
  end

endmodule
