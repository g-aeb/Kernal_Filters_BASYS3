`timescale 1ns / 1ps

// Simple true dual-port synchronous RAM holding one full rendered frame.
// The filter pipeline (render_ctrl) owns the write port; the OLED driver
// (oled_ctrl) owns the read port and continuously scans it out over SPI.
// Decoupling the two this way means the fast one-pixel-per-clock filter
// pipeline never has to backpressure-wait on the much slower SPI writes.
module frame_buffer #(
    parameter  int NUM_PIX = 96 * 64,
    parameter  int DATA_W  = 16,
    localparam int ADDR_W  = $clog2(NUM_PIX)
) (
    input logic clk,

    input logic             we,
    input logic [ADDR_W-1:0] waddr,
    input logic [DATA_W-1:0] wdata,

    input  logic [ADDR_W-1:0] raddr,
    output logic [DATA_W-1:0] rdata
);

  (* ram_style = "block" *) logic [DATA_W-1:0] mem[0:NUM_PIX-1];

  always_ff @(posedge clk) begin
    if (we) mem[waddr] <= wdata;
  end

  always_ff @(posedge clk) begin
    rdata <= mem[raddr];
  end

endmodule
