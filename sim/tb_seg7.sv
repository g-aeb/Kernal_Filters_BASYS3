`timescale 1ns / 1ps

// Self-checking testbench for seg7: verifies the active-low segment
// decode against an independent reference table for a representative
// sweep of values, confirms an[3:2] are never driven, exactly one of
// an[1:0] is low at any time, and the digit-swap interval matches
// REFRESH_CYCLES.
module tb_seg7;

  localparam int VALUE_W = 8;
  localparam int REFRESH_CYCLES = 40;  // small for fast sim

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst;
  logic [VALUE_W-1:0] value;
  logic [6:0] seg;
  logic [3:0] an;

  seg7 #(
      .VALUE_W(VALUE_W),
      .REFRESH_CYCLES(REFRESH_CYCLES)
  ) dut (
      .clk  (clk),
      .rst  (rst),
      .value(value),
      .seg  (seg),
      .an   (an)
  );

  // Independent reference decode table (active-low {g,f,e,d,c,b,a}) --
  // deliberately not shared code with seg7.sv's own table.
  function automatic logic [6:0] ref_decode(input int d);
    case (d)
      0: ref_decode = 7'b1000000;
      1: ref_decode = 7'b1111001;
      2: ref_decode = 7'b0100100;
      3: ref_decode = 7'b0110000;
      4: ref_decode = 7'b0011001;
      5: ref_decode = 7'b0010010;
      6: ref_decode = 7'b0000010;
      7: ref_decode = 7'b1111000;
      8: ref_decode = 7'b0000000;
      9: ref_decode = 7'b0010000;
      default: ref_decode = 7'b1111111;
    endcase
  endfunction

  int mismatches = 0;
  int checks = 0;

  task automatic check_value(input int v);
    int ones_ref, tens_ref;
    int cycles_since_swap;
    logic last_an1, last_an0;
    // cycles_since_swap resets fresh at the top of every call, but the
    // DUT's digit_sel/refresh_cnt free-run continuously across calls --
    // so the FIRST swap detected in a given call only measures the
    // remainder of whatever period was already in progress when this
    // call started, not a full period. Every swap after that first one,
    // within this same call, starts its count right at a true swap
    // boundary and gets a full, validatable period.
    bit swap_seen_this_call;
    swap_seen_this_call = 1'b0;

    value <= VALUE_W'(v);
    ones_ref = v % 10;
    tens_ref = (v / 10) % 10;

    // Sample across more than 2 full refresh periods so both digits are
    // observed and at least one an[3:2]/an[1:0] mutual-exclusivity and
    // swap-interval check happens per call.
    cycles_since_swap = 0;
    last_an1           = an[1];
    last_an0           = an[0];
    for (int i = 0; i < REFRESH_CYCLES * 3; i++) begin
      @(posedge clk);
      #1;
      checks++;

      if (an[3:2] !== 2'b11) begin
        $display("MISMATCH v=%0d: an[3:2] driven (an=%b), expected always off", v, an);
        mismatches++;
      end
      if (!((an[1:0] == 2'b10) ^ (an[1:0] == 2'b01)) || an[1:0] == 2'b00) begin
        $display("MISMATCH v=%0d: an[1:0]=%b, expected exactly one of the two low", v, an[1:0]);
        mismatches++;
      end

      if (an[0] === 1'b0) begin  // ones digit active
        if (seg !== ref_decode(ones_ref)) begin
          $display("MISMATCH v=%0d ones digit: seg=%b expected=%b", v, seg, ref_decode(ones_ref));
          mismatches++;
        end
      end else if (an[1] === 1'b0) begin  // tens digit active
        if (seg !== ref_decode(tens_ref)) begin
          $display("MISMATCH v=%0d tens digit: seg=%b expected=%b", v, seg, ref_decode(tens_ref));
          mismatches++;
        end
      end

      if (an[1] !== last_an1 || an[0] !== last_an0) begin
        // Steady-state interval between two swap *detections* is
        // REFRESH_CYCLES-1: the detection iterations themselves (the
        // swap edge, both start and end of the interval) aren't counted
        // by the increments in between.
        if (swap_seen_this_call && cycles_since_swap !== REFRESH_CYCLES - 1) begin
          $display("MISMATCH v=%0d: digit swapped after %0d cycles, expected %0d", v, cycles_since_swap,
                    REFRESH_CYCLES - 1);
          mismatches++;
        end
        swap_seen_this_call = 1'b1;
        cycles_since_swap = 0;
        last_an1 = an[1];
        last_an0 = an[0];
      end else begin
        cycles_since_swap++;
      end
    end
  endtask

  initial begin
    rst   = 1'b1;
    value = '0;
    repeat (3) @(posedge clk);
    rst = 1'b0;
    @(posedge clk);

    check_value(0);
    check_value(1);
    check_value(9);
    check_value(10);
    check_value(23);
    check_value(39);
    check_value(99);

    if (mismatches == 0) $display("ALL SEG7 CHECKS PASSED (%0d total checks)", checks);
    else $display("FAIL: %0d total mismatches out of %0d checks", mismatches, checks);
    $finish;
  end

endmodule
