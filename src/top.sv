`timescale 1ns / 1ps

// Top-level for the Basys 3: reads the source image from frame_store
// (inside render_ctrl), runs it through the shared kernel_filter_core-based
// Sobel pipeline, and displays the result on a PMOD OLEDrgb.
//
// SW[1:0] select the display mode (bypass / Gx / Gy / magnitude), SW[2]
// enables the cascaded pre-filter (identity vs blur ahead of Sobel), SW[3]
// enables frame auto-play (see frame_nav.sv). SW[15:4] are reserved for
// future use. Changing any of SW[2:0] triggers a fresh render pass; BTNC is
// the global reset, BTNL/BTNR manually step to the previous/next stored
// frame (see frame_nav.sv) -- the current frame index is also shown live on
// the onboard 7-segment display (see seg7.sv).
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
    parameter  int    NUM_FRAMES = 24,
    parameter  string INIT_FILE  = "frame_store.mem"
) (
    input logic clk100mhz,
    input logic btnc,
    input logic btnl,
    input logic btnr,

    input logic [15:0] sw,

    output logic [3:0] led,

    output logic oled_sclk,
    output logic oled_sdin,
    output logic oled_dc,
    output logic oled_csn,
    output logic oled_resn,
    output logic oled_vccen,
    output logic oled_pmoden,

    output logic [6:0] seg,
    output logic [3:0] an
);

  localparam int NUM_PIX = IMG_WIDTH * IMG_HEIGHT;
  localparam int ADDR_W = $clog2(NUM_PIX);
  localparam int FRAME_IDX_W = (NUM_FRAMES > 1) ? $clog2(NUM_FRAMES) : 1;

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

  // -----------------------------------------------------------------------
  // Frame browsing: BTNL/BTNR manually step, SW[3] enables auto-play. The
  // current frame_idx is also shown live on the 7-segment display.
  // -----------------------------------------------------------------------
  logic [FRAME_IDX_W-1:0] frame_idx;
  logic                   frame_idx_changed;

  frame_nav #(
      .NUM_FRAMES(NUM_FRAMES)
  ) u_frame_nav (
      .clk              (clk100mhz),
      .rst              (rst),
      .btnl_raw         (btnl),
      .btnr_raw         (btnr),
      .auto_play_en     (sw[3]),
      .frame_idx        (frame_idx),
      .frame_idx_changed(frame_idx_changed)
  );

  seg7 #(
      .VALUE_W(FRAME_IDX_W)
  ) u_seg7 (
      .clk  (clk100mhz),
      .rst  (rst),
      .value(frame_idx),
      .seg  (seg),
      .an   (an)
  );

  logic rendering;
  logic want_render;

  always_ff @(posedge clk100mhz) begin
    if (rst) begin
      mode_bits_prev <= '0;
      want_render    <= 1'b1;  // render once on startup
    end else begin
      if (mode_bits != mode_bits_prev || frame_idx_changed) begin
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
  // Render pipeline: frame_store -> sobel_pipeline -> frame_buffer (write side).
  // -----------------------------------------------------------------------
  logic              fb_we;
  logic [ADDR_W-1:0] fb_waddr;
  logic [      15:0] fb_wdata;

  render_ctrl #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .NUM_FRAMES(NUM_FRAMES),
      .INIT_FILE (INIT_FILE)
  ) u_render_ctrl (
      .clk           (clk100mhz),
      .rst           (rst),
      .disp_mode     (disp_mode),
      .cascade_en    (cascade_en),
      .render_trigger(want_render),
      .frame_idx     (frame_idx),
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
  logic oled_streaming;

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
      .oled_pmoden(oled_pmoden),
      .streaming  (oled_streaming)
  );

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
