`timescale 1ns / 1ps

// Simple shift-register debouncer: an input must be stable for
// STABLE_CYCLES consecutive clock cycles before out changes. At 100MHz
// with the default 17 cycles that's ~170ns, not enough for a real
// mechanical switch by itself -- clk is expected to be pre-divided (or
// STABLE_CYCLES scaled up) so the effective sampling interval is on the
// order of 1ms for physical switches/buttons.
module debounce #(
    parameter int STABLE_CYCLES = 17
) (
    input  logic clk,
    input  logic rst,
    input  logic in,
    output logic out
);

  logic [STABLE_CYCLES-1:0] shift_reg;
  logic                     out_r;

  always_ff @(posedge clk) begin
    if (rst) begin
      shift_reg <= '0;
      out_r     <= 1'b0;
    end else begin
      shift_reg <= {shift_reg[STABLE_CYCLES-2:0], in};
      if (&shift_reg) out_r <= 1'b1;
      else if (~|shift_reg) out_r <= 1'b0;
    end
  end

  assign out = out_r;

endmodule
