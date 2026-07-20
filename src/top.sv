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
//
// LD[3:0] are a bring-up debug ladder for the OLED path, since the SPI
// protocol/pin mapping to the physical panel can't be verified in
// simulation:
//   LD0 - heartbeat: blinks off the system clock, independent of
//         everything else. If this isn't blinking, the bitstream isn't
//         running at all.
//   LD1 - oled_resn: should go high (and stay high) a little over a
//         millisecond after reset releases. If LD0 blinks but this never
//         lights, the OLED driver's power-up sequencing or the oled_resn
//         pin mapping is the problem.
//   LD2 - sticky: latches high the first time the OLED driver finishes
//         its init sequence and address-window setup and starts
//         streaming pixels. If LD1 lights but this never does, the
//         SPI/init FSM is stuck -- suspect the SPI clock mode or the
//         permanently-low chip-select assumption.
//   LD3 - sticky: latches high the first time a full render pass into
//         the frame buffer completes. Independent of the OLED path --
//         confirms the image pipeline itself is running.
module top #(
    parameter  int    IMG_WIDTH  = 96,
    parameter  int    IMG_HEIGHT = 64,
    parameter  string INIT_FILE  = "test_image.mem"
) (
    input logic clk100mhz,
    input logic btnc,

    input logic [15:0] sw,

    output logic [3:0] led,

    // JB: the OLED's "home" connector. JC: a bring-up diagnostic --
    // every signal below is fanned out identically to both connectors
    // (see the OLED output section) so the physical module can be moved
    // between JB and JC to isolate a bad port/connection without
    // resynthesizing. Remove the JC duplication once the display is
    // confirmed working.
    output logic oled_sclk,
    output logic oled_sdin,
    output logic oled_dc,
    output logic oled_csn,
    output logic oled_resn,
    output logic oled_vccen,
    output logic oled_pmoden,

    output logic oled2_sclk,
    output logic oled2_sdin,
    output logic oled2_dc,
    output logic oled2_csn,
    output logic oled2_resn,
    output logic oled2_vccen,
    output logic oled2_pmoden
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
  // OLED output. u_oled drives a single set of internal signals, fanned
  // out identically to both the JB and JC connector ports below -- see
  // the port list comment for why.
  // -----------------------------------------------------------------------
  logic oled_streaming;

  logic oled_sclk_i, oled_sdin_i, oled_dc_i, oled_csn_i;
  logic oled_resn_i, oled_vccen_i, oled_pmoden_i;

  pmod_oledrgb #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT)
  ) u_oled (
      .clk        (clk100mhz),
      .rst        (rst),
      .fb_raddr   (fb_raddr),
      .fb_rdata   (fb_rdata),
      .oled_sclk  (oled_sclk_i),
      .oled_sdin  (oled_sdin_i),
      .oled_dc    (oled_dc_i),
      .oled_csn   (oled_csn_i),
      .oled_resn  (oled_resn_i),
      .oled_vccen (oled_vccen_i),
      .oled_pmoden(oled_pmoden_i),
      .streaming  (oled_streaming)
  );

  assign oled_sclk   = oled_sclk_i;
  assign oled_sdin   = oled_sdin_i;
  assign oled_dc     = oled_dc_i;
  assign oled_csn    = oled_csn_i;
  assign oled_resn   = oled_resn_i;
  assign oled_vccen  = oled_vccen_i;
  assign oled_pmoden = oled_pmoden_i;

  assign oled2_sclk   = oled_sclk_i;
  assign oled2_sdin   = oled_sdin_i;
  assign oled2_dc     = oled_dc_i;
  assign oled2_csn    = oled_csn_i;
  assign oled2_resn   = oled_resn_i;
  assign oled2_vccen  = oled_vccen_i;
  assign oled2_pmoden = oled_pmoden_i;

  // -----------------------------------------------------------------------
  // Debug LEDs (see module header for what each one means).
  // -----------------------------------------------------------------------
  logic [25:0] heartbeat_cnt;
  always_ff @(posedge clk100mhz) begin
    if (rst) heartbeat_cnt <= '0;
    else heartbeat_cnt <= heartbeat_cnt + 1'b1;
  end

  logic streaming_sticky;
  always_ff @(posedge clk100mhz) begin
    if (rst) streaming_sticky <= 1'b0;
    else if (oled_streaming) streaming_sticky <= 1'b1;
  end

  logic rendering_d;
  logic render_done_sticky;
  always_ff @(posedge clk100mhz) begin
    if (rst) begin
      rendering_d        <= 1'b0;
      render_done_sticky <= 1'b0;
    end else begin
      rendering_d <= rendering;
      // A falling edge on `rendering` means a render pass just finished.
      if (rendering_d && !rendering) render_done_sticky <= 1'b1;
    end
  end

  assign led[0] = heartbeat_cnt[25];
  assign led[1] = oled_resn;
  assign led[2] = streaming_sticky;
  assign led[3] = render_done_sticky;

endmodule
