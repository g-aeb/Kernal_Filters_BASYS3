`timescale 1ns / 1ps

// Top-level for the Basys 3: reads the source image from image_rom (inside
// render_ctrl), runs it through the shared kernel_filter_core-based Sobel
// pipeline, and displays the result on a PMOD OLEDrgb.
//
// SW[1:0] select the display mode (bypass / Gx / Gy / magnitude), SW[2]
// enables the cascaded pre-filter (identity vs blur ahead of Sobel).
// SW[15:3] are reserved for future use (e.g. selecting among multiple
// stored images). Changing any of SW[2:0] triggers a fresh render pass;
// BTNC is the global reset.
module top #(
    parameter  int    IMG_WIDTH  = 96,
    parameter  int    IMG_HEIGHT = 64,
    parameter  string INIT_FILE  = "test_image.mem"
) (
    input logic clk100mhz,
    input logic btnc,

    input logic [15:0] sw,

    output logic oled_sclk,
    output logic oled_sdin,
    output logic oled_dc,
    output logic oled_csn,
    output logic oled_resn,
    output logic oled_vccen,
    output logic oled_pmoden
);

  localparam int NUM_PIX = IMG_WIDTH * IMG_HEIGHT;
  localparam int ADDR_W = $clog2(NUM_PIX);

  logic rst;
  assign rst = btnc;

  // -----------------------------------------------------------------------
  // Switch decoding: debounce first, then edge-detect on the debounced
  // value so a render pass is only triggered by a settled switch change,
  // not switch bounce.
  // -----------------------------------------------------------------------
  logic [1:0] disp_mode;
  logic       cascade_en;

  debounce u_db_mode0 (
      .clk(clk100mhz),
      .rst(rst),
      .in (sw[0]),
      .out(disp_mode[0])
  );
  debounce u_db_mode1 (
      .clk(clk100mhz),
      .rst(rst),
      .in (sw[1]),
      .out(disp_mode[1])
  );
  debounce u_db_cascade (
      .clk(clk100mhz),
      .rst(rst),
      .in (sw[2]),
      .out(cascade_en)
  );

  logic [2:0] mode_bits, mode_bits_prev;
  assign mode_bits = {cascade_en, disp_mode};

  logic rendering;
  logic want_render;

  always_ff @(posedge clk100mhz) begin
    if (rst) begin
      mode_bits_prev <= '0;
      want_render    <= 1'b1;  // render once on startup
    end else begin
      if (mode_bits != mode_bits_prev) begin
        mode_bits_prev <= mode_bits;
        want_render    <= 1'b1;
      end else if (rendering) begin
        // render_ctrl has picked up the request (left IDLE) -- clear it
        // so finishing this pass doesn't immediately trigger another.
        want_render <= 1'b0;
      end
    end
  end

  // -----------------------------------------------------------------------
  // Render pipeline: image_rom -> sobel_pipeline -> frame_buffer (write side).
  // -----------------------------------------------------------------------
  logic              fb_we;
  logic [ADDR_W-1:0] fb_waddr;
  logic [      15:0] fb_wdata;

  render_ctrl #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .INIT_FILE (INIT_FILE)
  ) u_render_ctrl (
      .clk           (clk100mhz),
      .rst           (rst),
      .disp_mode     (disp_mode),
      .cascade_en    (cascade_en),
      .render_trigger(want_render),
      .fb_we         (fb_we),
      .fb_waddr      (fb_waddr),
      .fb_wdata      (fb_wdata),
      .rendering     (rendering)
  );

  // -----------------------------------------------------------------------
  // Shared frame buffer: render_ctrl writes, pmod_oledrgb reads continuously.
  // -----------------------------------------------------------------------
  logic [ADDR_W-1:0] fb_raddr;
  logic [      15:0] fb_rdata;

  frame_buffer #(
      .NUM_PIX(NUM_PIX),
      .DATA_W (16)
  ) u_frame_buffer (
      .clk  (clk100mhz),
      .we   (fb_we),
      .waddr(fb_waddr),
      .wdata(fb_wdata),
      .raddr(fb_raddr),
      .rdata(fb_rdata)
  );

  // -----------------------------------------------------------------------
  // OLED output.
  // -----------------------------------------------------------------------
  pmod_oledrgb #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT)
  ) u_oled (
      .clk        (clk100mhz),
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

endmodule
