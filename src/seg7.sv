`timescale 1ns / 1ps

// 2-digit decimal (0-99) driver for the Basys 3's 4-digit multiplexed
// common-anode 7-segment display. Only an[1:0] are ever driven active --
// an[3:2] stay permanently off (this project only ever needs to show a
// small frame index). Time-multiplexes the two active digits at
// REFRESH_CYCLES intervals, fast enough for persistence of vision to
// read both as lit simultaneously.
module seg7 #(
    parameter int VALUE_W = 8,
    parameter int REFRESH_CYCLES = 100_000  // ~1kHz digit-swap @ 100MHz; override small for sim
) (
    input logic clk,
    input logic rst,

    input logic [VALUE_W-1:0] value,  // 0-99; values >=100 display the low 2 digits only

    output logic [6:0] seg,  // active-low {g,f,e,d,c,b,a}
    output logic [3:0] an    // active-low; only an[1:0] ever driven
);

  logic [3:0] ones, tens;
  assign ones = value % 10;
  assign tens = (value / 10) % 10;

  localparam int REF_W = $clog2(REFRESH_CYCLES);
  logic [REF_W-1:0] refresh_cnt;
  logic digit_sel;

  always_ff @(posedge clk) begin
    if (rst) begin
      refresh_cnt <= '0;
      digit_sel   <= 1'b0;
    end else if (refresh_cnt == REF_W'(REFRESH_CYCLES - 1)) begin
      refresh_cnt <= '0;
      digit_sel   <= ~digit_sel;
    end else begin
      refresh_cnt <= refresh_cnt + 1'b1;
    end
  end

  function automatic logic [6:0] seg7_decode(input logic [3:0] d);
    case (d)
      4'd0: seg7_decode = 7'b1000000;
      4'd1: seg7_decode = 7'b1111001;
      4'd2: seg7_decode = 7'b0100100;
      4'd3: seg7_decode = 7'b0110000;
      4'd4: seg7_decode = 7'b0011001;
      4'd5: seg7_decode = 7'b0010010;
      4'd6: seg7_decode = 7'b0000010;
      4'd7: seg7_decode = 7'b1111000;
      4'd8: seg7_decode = 7'b0000000;
      4'd9: seg7_decode = 7'b0010000;
      default: seg7_decode = 7'b1111111;  // blank
    endcase
  endfunction

  assign seg = seg7_decode(digit_sel ? tens : ones);
  assign an  = digit_sel ? 4'b1101 : 4'b1110;

endmodule
