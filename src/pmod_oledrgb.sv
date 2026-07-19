`timescale 1ns / 1ps

// SPI driver for the Digilent PmodOLEDrgb (SSD1331 controller, 96x64
// RGB565). Runs the standard SSD1331 power-up/init command sequence once,
// sets the column/row address window to the full 96x64 screen a single
// time, then continuously streams frame_buffer's contents out over SPI
// forever -- the controller auto-increments and wraps its GRAM pointer
// within the configured window, so no per-pixel addressing commands are
// needed after the initial window setup.
//
// Note: exact init command values (contrast/precharge/clock-divider) are
// the commonly-published SSD1331 defaults; if the display doesn't come up
// correctly, cross-check them against the PmodOLEDrgb reference manual
// and adjust -- this is the one module in the project that can't be
// verified in simulation without a real device or a bus-functional model.
module pmod_oledrgb #(
    parameter int IMG_WIDTH  = 96,
    parameter int IMG_HEIGHT = 64,
    // SCLK frequency = clk / (2*CLK_DIV). Default: 100MHz / 16 = 6.25MHz,
    // comfortably under the SSD1331's ~150ns min clock period.
    parameter int CLK_DIV    = 8
) (
    input logic clk,
    input logic rst,

    // Frame buffer read port (registered, 1-cycle read latency).
    output logic [$clog2(IMG_WIDTH*IMG_HEIGHT)-1:0] fb_raddr,
    input  logic [15:0] fb_rdata,

    // PMOD OLEDrgb pins.
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

  // -------------------------------------------------------------------
  // Low-level SPI byte shifter: SPI mode 0, MSB first. CS held low for
  // the whole session -- this is a dedicated point-to-point bus, not
  // shared with any other device, so per-transaction chip-select
  // toggling isn't needed.
  // -------------------------------------------------------------------
  assign oled_csn = 1'b0;

  logic [7:0] byte_data;
  logic       byte_dc;
  logic       byte_start;
  logic       byte_busy;

  logic [7:0] shift_reg;
  logic [3:0] bit_cnt;
  logic [$clog2(CLK_DIV+1)-1:0] div_cnt;
  logic       sclk_r;

  typedef enum logic [1:0] {
    SPI_IDLE,
    SPI_LOW,
    SPI_HIGH
  } spi_state_t;
  spi_state_t spi_state;

  always_ff @(posedge clk) begin
    if (rst) begin
      spi_state <= SPI_IDLE;
      byte_busy <= 1'b0;
      sclk_r    <= 1'b0;
      oled_dc   <= 1'b0;
      div_cnt   <= '0;
      bit_cnt   <= '0;
      shift_reg <= '0;
    end else begin
      case (spi_state)
        SPI_IDLE: begin
          sclk_r <= 1'b0;
          if (byte_start) begin
            shift_reg <= byte_data;
            oled_dc   <= byte_dc;
            bit_cnt   <= 4'd0;
            div_cnt   <= '0;
            byte_busy <= 1'b1;
            spi_state <= SPI_LOW;
          end else begin
            byte_busy <= 1'b0;
          end
        end

        SPI_LOW: begin
          // SDIN (= shift_reg[7]) has been settled since we entered this
          // state; wait half a clock period, then raise SCLK so the
          // slave samples it.
          if (div_cnt == CLK_DIV[$bits(div_cnt)-1:0] - 1'b1) begin
            div_cnt   <= '0;
            sclk_r    <= 1'b1;
            spi_state <= SPI_HIGH;
          end else begin
            div_cnt <= div_cnt + 1'b1;
          end
        end

        SPI_HIGH: begin
          if (div_cnt == CLK_DIV[$bits(div_cnt)-1:0] - 1'b1) begin
            div_cnt   <= '0;
            sclk_r    <= 1'b0;
            shift_reg <= {shift_reg[6:0], 1'b0};
            if (bit_cnt == 4'd7) begin
              spi_state <= SPI_IDLE;
              byte_busy <= 1'b0;
            end else begin
              bit_cnt   <= bit_cnt + 1'b1;
              spi_state <= SPI_LOW;
            end
          end else begin
            div_cnt <= div_cnt + 1'b1;
          end
        end

        default: spi_state <= SPI_IDLE;
      endcase
    end
  end

  assign oled_sclk = sclk_r;
  assign oled_sdin = shift_reg[7];

  // -------------------------------------------------------------------
  // SSD1331 init command sequence (command bytes, D/C=0 throughout --
  // command *parameters* are still sent with D/C=0 on this controller,
  // only actual pixel/GRAM data uses D/C=1).
  // -------------------------------------------------------------------
  localparam int INIT_LEN = 37;
  logic [7:0] init_rom[0:INIT_LEN-1];
  initial begin
    init_rom[0]  = 8'hAE;  // display off
    init_rom[1]  = 8'hA0;
    init_rom[2]  = 8'h72;  // remap/color depth: RGB565, horizontal increment
    init_rom[3]  = 8'hA1;
    init_rom[4]  = 8'h00;  // display start line
    init_rom[5]  = 8'hA2;
    init_rom[6]  = 8'h00;  // display offset
    init_rom[7]  = 8'hA4;  // normal display mode
    init_rom[8]  = 8'hA8;
    init_rom[9]  = 8'h3F;  // multiplex ratio 1/64
    init_rom[10] = 8'hAD;
    init_rom[11] = 8'h8E;  // master config
    init_rom[12] = 8'hB0;
    init_rom[13] = 8'h0B;  // power save mode
    init_rom[14] = 8'hB1;
    init_rom[15] = 8'h31;  // phase 1/2 period
    init_rom[16] = 8'hB3;
    init_rom[17] = 8'hF0;  // clock divider / oscillator frequency
    init_rom[18] = 8'h8A;
    init_rom[19] = 8'h64;  // precharge speed A
    init_rom[20] = 8'h8B;
    init_rom[21] = 8'h78;  // precharge speed B
    init_rom[22] = 8'h8C;
    init_rom[23] = 8'h64;  // precharge speed C
    init_rom[24] = 8'hBB;
    init_rom[25] = 8'h3A;  // precharge voltage
    init_rom[26] = 8'hBE;
    init_rom[27] = 8'h3E;  // VCOMH voltage
    init_rom[28] = 8'h87;
    init_rom[29] = 8'h06;  // master current
    init_rom[30] = 8'h81;
    init_rom[31] = 8'h91;  // contrast A (red)
    init_rom[32] = 8'h82;
    init_rom[33] = 8'h50;  // contrast B (green)
    init_rom[34] = 8'h83;
    init_rom[35] = 8'h7D;  // contrast C (blue)
    init_rom[36] = 8'hAF;  // display ON
  end

  // Column/row address window, set once to the full screen.
  localparam int WIN_LEN = 6;
  logic [7:0] win_rom[0:WIN_LEN-1];
  initial begin
    win_rom[0] = 8'h15;
    win_rom[1] = 8'h00;
    win_rom[2] = 8'(IMG_WIDTH - 1);   // set column address: start=0, end=IMG_WIDTH-1
    win_rom[3] = 8'h75;
    win_rom[4] = 8'h00;
    win_rom[5] = 8'(IMG_HEIGHT - 1);  // set row address: start=0, end=IMG_HEIGHT-1
  end

  // -------------------------------------------------------------------
  // Top-level sequencing FSM.
  // -------------------------------------------------------------------
  typedef enum logic [2:0] {
    OS_RESET,
    OS_POWERUP_WAIT,
    OS_INIT,
    OS_SET_WINDOW,
    OS_STREAM_ADDR,
    OS_STREAM_HI,
    OS_STREAM_LO
  } oled_state_t;
  oled_state_t state;

  localparam int POWERUP_CYCLES = 16'hFFFF;  // ~655us at 100MHz, comfortably > SSD1331's reset spec

  logic [15:0] powerup_cnt;
  logic [$clog2(INIT_LEN)-1:0] init_idx;
  logic [$clog2(WIN_LEN)-1:0] win_idx;
  logic [ADDR_W-1:0] pix_addr;
  logic byte_issued;

  always_ff @(posedge clk) begin
    if (rst) begin
      state       <= OS_RESET;
      oled_resn   <= 1'b0;
      oled_vccen  <= 1'b0;
      oled_pmoden <= 1'b0;
      powerup_cnt <= '0;
      init_idx    <= '0;
      win_idx     <= '0;
      pix_addr    <= '0;
      byte_start  <= 1'b0;
      byte_issued <= 1'b0;
      fb_raddr    <= '0;
    end else begin
      byte_start <= 1'b0;

      case (state)
        // Hold the panel in reset while VCC/power enables settle.
        OS_RESET: begin
          oled_vccen  <= 1'b1;
          oled_pmoden <= 1'b1;
          oled_resn   <= 1'b0;
          if (powerup_cnt == POWERUP_CYCLES[15:0]) begin
            oled_resn   <= 1'b1;
            powerup_cnt <= '0;
            state       <= OS_POWERUP_WAIT;
          end else begin
            powerup_cnt <= powerup_cnt + 1'b1;
          end
        end

        // Let the panel settle out of reset before talking to it.
        OS_POWERUP_WAIT: begin
          if (powerup_cnt == POWERUP_CYCLES[15:0]) begin
            powerup_cnt <= '0;
            init_idx    <= '0;
            state       <= OS_INIT;
          end else begin
            powerup_cnt <= powerup_cnt + 1'b1;
          end
        end

        OS_INIT: begin
          if (!byte_issued && !byte_busy) begin
            byte_data   <= init_rom[init_idx];
            byte_dc     <= 1'b0;
            byte_start  <= 1'b1;
            byte_issued <= 1'b1;
          end else if (byte_issued && !byte_busy && !byte_start) begin
            byte_issued <= 1'b0;
            if (init_idx == INIT_LEN[$bits(init_idx)-1:0] - 1'b1) begin
              win_idx <= '0;
              state   <= OS_SET_WINDOW;
            end else begin
              init_idx <= init_idx + 1'b1;
            end
          end
        end

        OS_SET_WINDOW: begin
          if (!byte_issued && !byte_busy) begin
            byte_data   <= win_rom[win_idx];
            byte_dc     <= 1'b0;
            byte_start  <= 1'b1;
            byte_issued <= 1'b1;
          end else if (byte_issued && !byte_busy && !byte_start) begin
            byte_issued <= 1'b0;
            if (win_idx == WIN_LEN[$bits(win_idx)-1:0] - 1'b1) begin
              pix_addr <= '0;
              fb_raddr <= '0;
              state    <= OS_STREAM_ADDR;
            end else begin
              win_idx <= win_idx + 1'b1;
            end
          end
        end

        // Present the read address; frame_buffer's registered read port
        // needs one cycle before fb_rdata reflects it.
        OS_STREAM_ADDR: begin
          state <= OS_STREAM_HI;
        end

        OS_STREAM_HI: begin
          if (!byte_issued && !byte_busy) begin
            byte_data   <= fb_rdata[15:8];
            byte_dc     <= 1'b1;
            byte_start  <= 1'b1;
            byte_issued <= 1'b1;
          end else if (byte_issued && !byte_busy && !byte_start) begin
            byte_issued <= 1'b0;
            state       <= OS_STREAM_LO;
          end
        end

        OS_STREAM_LO: begin
          if (!byte_issued && !byte_busy) begin
            byte_data   <= fb_rdata[7:0];
            byte_dc     <= 1'b1;
            byte_start  <= 1'b1;
            byte_issued <= 1'b1;
          end else if (byte_issued && !byte_busy && !byte_start) begin
            byte_issued <= 1'b0;
            pix_addr    <= (pix_addr == ADDR_W'(NUM_PIX - 1)) ? '0 : pix_addr + 1'b1;
            fb_raddr    <= (pix_addr == ADDR_W'(NUM_PIX - 1)) ? '0 : pix_addr + 1'b1;
            state       <= OS_STREAM_ADDR;
          end
        end

        default: state <= OS_RESET;
      endcase
    end
  end

endmodule
