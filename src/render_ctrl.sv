`timescale 1ns / 1ps

// Orchestrates one full render pass into the frame buffer: first clears
// every pixel to black, then streams the source image through
// sobel_pipeline and writes each output pixel to its (row, col) address,
// converting the 8-bit grayscale display value to RGB565.
//
// A render pass is triggered by render_trigger (pulsed on reset, whenever
// the mode switches change, or whenever frame_idx changes -- see top.sv).
// Re-clearing before
// every pass matters because different modes crop a different-sized
// border (bypass/Gx/Gy/magnitude all share the same 2px crop today, but
// this keeps it correct if that ever changes), so stale border pixels
// from a previous pass never linger.
//
// oled_ctrl reads the frame buffer independently and continuously, so a
// render pass updates the displayed image pixel-by-pixel as it goes
// rather than atomically -- acceptable tearing for a switch-driven demo
// that isn't refreshing a live video feed.
module render_ctrl #(
    parameter  int    IMG_WIDTH  = 96,
    parameter  int    IMG_HEIGHT = 64,
    parameter  int    PIX_W      = 8,
    parameter  int    NUM_FRAMES = 24,
    parameter  string INIT_FILE  = "frame_store.mem",
    localparam int    NUM_PIX      = IMG_WIDTH * IMG_HEIGHT,
    localparam int    ADDR_W       = $clog2(NUM_PIX),
    localparam int    FRAME_IDX_W  = (NUM_FRAMES > 1) ? $clog2(NUM_FRAMES) : 1
) (
    input logic clk,
    input logic rst,

    input logic [1:0] disp_mode,
    input logic       cascade_en,
    input logic       render_trigger,
    input logic [FRAME_IDX_W-1:0] frame_idx,

    output logic              fb_we,
    output logic [ADDR_W-1:0] fb_waddr,
    output logic [      15:0] fb_wdata,

    output logic rendering
);

  localparam int COL_W = $clog2(IMG_WIDTH);
  localparam int ROW_W = $clog2(IMG_HEIGHT);

  typedef enum logic [1:0] {
    ST_IDLE,
    ST_CLEAR,
    ST_STREAM,
    ST_DRAIN
  } state_t;

  state_t state;

  logic [ADDR_W-1:0] clear_addr;
  logic [ADDR_W-1:0] stream_count;
  logic [       3:0] drain_count;
  localparam int DRAIN_CYCLES = 12;  // comfortably more than the pipeline's ~8-cycle max latency

  logic rom_frame_start, rom_rd_en, rom_valid;
  logic [PIX_W-1:0] rom_pix;
  logic [COL_W-1:0] rom_col;
  logic [ROW_W-1:0] rom_row;

  frame_store #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .PIX_W     (PIX_W),
      .NUM_FRAMES(NUM_FRAMES),
      .INIT_FILE (INIT_FILE)
  ) u_frame_store (
      .clk        (clk),
      .rst        (rst),
      .frame_start(rom_frame_start),
      .rd_en      (rom_rd_en),
      .frame_idx  (frame_idx),
      .pix_valid  (rom_valid),
      .pix_data   (rom_pix),
      .col        (rom_col),
      .row        (rom_row)
  );

  logic sp_valid;
  logic [PIX_W-1:0] sp_disp_val;
  logic [COL_W-1:0] sp_col;
  logic [ROW_W-1:0] sp_row;

  sobel_pipeline #(
      .IMG_WIDTH (IMG_WIDTH),
      .IMG_HEIGHT(IMG_HEIGHT),
      .PIX_W     (PIX_W)
  ) u_pipeline (
      .clk          (clk),
      .rst          (rst),
      .pix_valid_in (rom_valid),
      .pix_in       (rom_pix),
      .col_in       (rom_col),
      .row_in       (rom_row),
      .disp_mode    (disp_mode),
      .cascade_en   (cascade_en),
      .pix_valid_out(sp_valid),
      .disp_val_out (sp_disp_val),
      .col_out      (sp_col),
      .row_out      (sp_row)
  );

  // 8-bit grayscale -> RGB565, replicating luma across all three channels.
  logic [15:0] rgb565;
  assign rgb565 = {sp_disp_val[7:3], sp_disp_val[7:2], sp_disp_val[7:3]};

  always_ff @(posedge clk) begin
    if (rst) begin
      state        <= ST_IDLE;
      clear_addr   <= '0;
      stream_count <= '0;
      drain_count  <= '0;
    end else begin
      case (state)
        ST_IDLE: begin
          if (render_trigger) begin
            state      <= ST_CLEAR;
            clear_addr <= '0;
          end
        end

        ST_CLEAR: begin
          if (clear_addr == ADDR_W'(NUM_PIX - 1)) begin
            state        <= ST_STREAM;
            stream_count <= '0;
          end else begin
            clear_addr <= clear_addr + 1'b1;
          end
        end

        ST_STREAM: begin
          if (stream_count == ADDR_W'(NUM_PIX - 1)) begin
            state       <= ST_DRAIN;
            drain_count <= '0;
          end else begin
            stream_count <= stream_count + 1'b1;
          end
        end

        ST_DRAIN: begin
          if (drain_count == 4'(DRAIN_CYCLES - 1)) begin
            state <= ST_IDLE;
          end else begin
            drain_count <= drain_count + 1'b1;
          end
        end

        default: state <= ST_IDLE;
      endcase
    end
  end

  assign rom_frame_start = (state == ST_IDLE) && render_trigger;
  assign rom_rd_en       = (state == ST_STREAM);
  assign rendering       = (state != ST_IDLE);

  // Frame-buffer write port: clear pass writes black; stream pass writes
  // whatever sobel_pipeline produces, whenever it produces it.
  always_comb begin
    if (state == ST_CLEAR) begin
      fb_we    = 1'b1;
      fb_waddr = clear_addr;
      fb_wdata = 16'h0000;
    end else if (sp_valid) begin
      fb_we    = 1'b1;
      fb_waddr = ADDR_W'(sp_row) * ADDR_W'(IMG_WIDTH) + ADDR_W'(sp_col);
      fb_wdata = rgb565;
    end else begin
      fb_we    = 1'b0;
      fb_waddr = '0;
      fb_wdata = '0;
    end
  end

endmodule
