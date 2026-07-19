`timescale 1ns / 1ps

// Elaboration + basic power-up smoke test for the render_ctrl ->
// frame_buffer -> pmod_oledrgb hierarchy (i.e. everything top.sv wires
// together, minus the top module boundary itself). Not a functional
// check of pixel values (that's covered by tb_kernel_filter_core /
// tb_cascade / tb_sobel_pipeline) -- this confirms the pieces integrate,
// reset cleanly, and that a render pass actually starts and the OLED FSM
// leaves reset.
//
// render_ctrl is instantiated directly here, rather than through top,
// because Icarus Verilog can't forward a `parameter string` by reference
// through a module boundary (`.F(F)` where F is the parent's own string
// parameter) -- confirmed as a general tool limitation, not specific to
// this design. top.sv uses exactly that pattern to forward INIT_FILE to
// render_ctrl, which is standard, portable SystemVerilog that Vivado
// handles correctly; top.sv's switch-debounce/edge-detect logic itself is
// simple enough to have been verified by inspection rather than sim.
module tb_top_smoke;

  localparam int IMG_WIDTH  = 16;
  localparam int IMG_HEIGHT = 10;
  localparam int NUM_PIX = IMG_WIDTH * IMG_HEIGHT;
  localparam int ADDR_W = $clog2(NUM_PIX);

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst;
  logic [1:0] disp_mode;
  logic cascade_en;
  logic render_trigger;
  logic rendering;

  logic fb_we;
  logic [ADDR_W-1:0] fb_waddr;
  logic [15:0] fb_wdata;

  render_ctrl #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .INIT_FILE ("tb_sobel_test_image.mem")
  ) u_render_ctrl (
      .clk           (clk),
      .rst           (rst),
      .disp_mode     (disp_mode),
      .cascade_en    (cascade_en),
      .render_trigger(render_trigger),
      .fb_we         (fb_we),
      .fb_waddr      (fb_waddr),
      .fb_wdata      (fb_wdata),
      .rendering     (rendering)
  );

  logic [ADDR_W-1:0] fb_raddr;
  logic [15:0] fb_rdata;

  frame_buffer #(
      .NUM_PIX(NUM_PIX),
      .DATA_W (16)
  ) u_frame_buffer (
      .clk  (clk),
      .we   (fb_we),
      .waddr(fb_waddr),
      .wdata(fb_wdata),
      .raddr(fb_raddr),
      .rdata(fb_rdata)
  );

  logic oled_sclk, oled_sdin, oled_dc, oled_csn, oled_resn, oled_vccen, oled_pmoden;

  pmod_oledrgb #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .CLK_DIV   (2)
  ) u_oled (
      .clk        (clk),
      .rst        (rst),
      .fb_raddr   (fb_raddr),
      .fb_rdata   (fb_rdata),
      .oled_sclk  (oled_sclk),
      .oled_sdin  (oled_sdin),
      .oled_dc    (oled_dc),
      .oled_csn   (oled_csn),
      .oled_resn  (oled_resn),
      .oled_vccen (oled_vccen),
      .oled_pmoden(oled_pmoden)
  );

  initial begin
    rst            = 1'b1;
    disp_mode      = 2'b00;
    cascade_en     = 1'b0;
    render_trigger = 1'b0;
    repeat (4) @(posedge clk);
    rst = 1'b0;

    render_trigger = 1'b1;
    @(posedge clk);

    wait (rendering === 1'b1);
    $display("PASS: render pass started");

    wait (rendering === 1'b0);
    render_trigger = 1'b0;
    $display("PASS: render pass completed");

    wait (oled_resn === 1'b1);
    $display("PASS: OLED driver released its own reset");

    // Trigger a second render pass and confirm it starts.
    disp_mode      = 2'b11;
    render_trigger = 1'b1;
    @(posedge clk);
    wait (rendering === 1'b1);
    $display("PASS: second render_trigger started another render pass");

    $display("ALL SMOKE CHECKS PASSED");
    $finish;
  end

  initial begin
    #50_000_000;
    $display("FAIL: timeout in top-level smoke test");
    $finish;
  end

endmodule
