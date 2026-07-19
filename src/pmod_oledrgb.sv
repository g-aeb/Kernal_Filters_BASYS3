`timescale 1ns / 1ps

// SPI driver for the Digilent PmodOLEDrgb (SSD1331 controller, 96x64
// RGB565). Follows Digilent's published power-on sequence and SPI timing
// exactly (Pmod OLEDrgb Reference Manual, "Interfacing with the Pmod" /
// "Quick Data Acquisition" sections): SPI mode 3, command-lock unlock
// byte, and the specific VCCEN/PMODEN/RES power sequencing the panel
// needs to come up cleanly. Runs that sequence once, sets the address
// window to the full screen once, then streams frame_buffer's contents
// out over SPI forever -- the controller auto-increments and wraps its
// GRAM pointer within the configured window, so no per-pixel addressing
// commands are needed after setup.
module pmod_oledrgb #(
    parameter int IMG_WIDTH  = 96,
    parameter int IMG_HEIGHT = 64,
    // SCLK frequency = clk / (2*CLK_DIV). Default: 100MHz / 16 = 6.25MHz
    // -> 160ns period, comfortably over the SSD1331's 150ns minimum.
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
    output logic oled_pmoden,

    // High once the init sequence and address-window setup have both
    // completed and pixel streaming has begun. Intended for a top-level
    // debug LED, not part of the functional datapath.
    output logic streaming
);

  localparam int NUM_PIX = IMG_WIDTH * IMG_HEIGHT;
  localparam int ADDR_W = $clog2(NUM_PIX);

  // -------------------------------------------------------------------
  // Low-level SPI byte shifter: SPI mode 3 (clock idles high, data
  // changes on the falling edge, the slave captures on the rising edge),
  // MSB first. CS held low for the whole session -- the datasheet
  // explicitly describes driving CS low and keeping it there as the
  // normal way to talk to this controller.
  // -------------------------------------------------------------------
  assign oled_csn = 1'b0;

  logic [7:0] byte_data;
  logic       byte_dc;
  logic       byte_start;
  logic       byte_busy;

  logic [7:0] shift_reg;
  logic [3:0] bit_cnt;
  logic [$clog2(CLK_DIV+1)-1:0] div_cnt;
  // Defined initial value (not just X) so SCLK has a clean, deterministic
  // idle-high state from time 0 in simulation, before the first reset
  // even takes effect -- matches real FPGA power-up register semantics.
  logic       sclk_r = 1'b1;

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
      sclk_r    <= 1'b1;  // idle high (mode 3)
      oled_dc   <= 1'b0;
      div_cnt   <= '0;
      bit_cnt   <= '0;
      shift_reg <= '0;
    end else begin
      case (spi_state)
        SPI_IDLE: begin
          sclk_r <= 1'b1;
          if (byte_start) begin
            shift_reg <= byte_data;
            oled_dc   <= byte_dc;
            bit_cnt   <= 4'd0;
            div_cnt   <= '0;
            byte_busy <= 1'b1;
            sclk_r    <= 1'b0;  // fall immediately -- MSB is now valid on SDIN
            spi_state <= SPI_LOW;
          end else begin
            byte_busy <= 1'b0;
          end
        end

        SPI_LOW: begin
          // SCLK is low, SDIN (= shift_reg[7]) is stable; wait half a
          // clock period, then raise SCLK so the slave captures it.
          if (div_cnt == CLK_DIV[$bits(div_cnt)-1:0] - 1'b1) begin
            div_cnt   <= '0;
            sclk_r    <= 1'b1;
            spi_state <= SPI_HIGH;
          end else begin
            div_cnt <= div_cnt + 1'b1;
          end
        end

        SPI_HIGH: begin
          // Bit just captured on this rising edge. Wait half a period,
          // then either fall again for the next bit's data, or return to
          // idle-high once all 8 bits are done.
          if (div_cnt == CLK_DIV[$bits(div_cnt)-1:0] - 1'b1) begin
            div_cnt <= '0;
            if (bit_cnt == 4'd7) begin
              spi_state <= SPI_IDLE;
              byte_busy <= 1'b0;
            end else begin
              shift_reg <= {shift_reg[6:0], 1'b0};
              bit_cnt   <= bit_cnt + 1'b1;
              sclk_r    <= 1'b0;
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
  // SSD1331 init command sequence, in Digilent's documented order:
  // command-lock unlock, display off, then the panel configuration
  // registers, disable scrolling, and an explicit GRAM clear -- all
  // still with D/C=0 (command parameters are sent with D/C=0 on this
  // controller too, not just the command opcodes). Display ON (0xAF) is
  // deliberately *not* in this table -- Digilent's sequence sends it
  // only after VCCEN goes high and settles, handled as its own state
  // below.
  // -------------------------------------------------------------------
  localparam int INIT_LEN = 44;
  logic [7:0] init_rom[0:INIT_LEN-1];
  initial begin
    init_rom[0]  = 8'hFD;
    init_rom[1]  = 8'h12;  // command lock: unlock command mode
    init_rom[2]  = 8'hAE;  // display off
    init_rom[3]  = 8'hA0;
    init_rom[4]  = 8'h72;  // remap/color depth: RGB565, horizontal increment
    init_rom[5]  = 8'hA1;
    init_rom[6]  = 8'h00;  // display start line
    init_rom[7]  = 8'hA2;
    init_rom[8]  = 8'h00;  // display offset
    init_rom[9]  = 8'hA4;  // normal display mode
    init_rom[10] = 8'hA8;
    init_rom[11] = 8'h3F;  // multiplex ratio 1/64
    init_rom[12] = 8'hAD;
    init_rom[13] = 8'h8E;  // master config
    init_rom[14] = 8'hB0;
    init_rom[15] = 8'h0B;  // power save mode
    init_rom[16] = 8'hB1;
    init_rom[17] = 8'h31;  // phase 1/2 period
    init_rom[18] = 8'hB3;
    init_rom[19] = 8'hF0;  // clock divider / oscillator frequency
    init_rom[20] = 8'h8A;
    init_rom[21] = 8'h64;  // precharge speed A
    init_rom[22] = 8'h8B;
    init_rom[23] = 8'h78;  // precharge speed B
    init_rom[24] = 8'h8C;
    init_rom[25] = 8'h64;  // precharge speed C
    init_rom[26] = 8'hBB;
    init_rom[27] = 8'h3A;  // precharge voltage
    init_rom[28] = 8'hBE;
    init_rom[29] = 8'h3E;  // VCOMH voltage
    init_rom[30] = 8'h87;
    init_rom[31] = 8'h06;  // master current
    init_rom[32] = 8'h81;
    init_rom[33] = 8'h91;  // contrast A (red)
    init_rom[34] = 8'h82;
    init_rom[35] = 8'h50;  // contrast B (green)
    init_rom[36] = 8'h83;
    init_rom[37] = 8'h7D;  // contrast C (blue)
    init_rom[38] = 8'h2E;  // disable scrolling
    init_rom[39] = 8'h25;
    init_rom[40] = 8'h00;  // clear window: start column 0
    init_rom[41] = 8'h00;  //               start row 0
  end
  // Split into two initial blocks purely so no single one exceeds a
  // convenient line count; both run at time 0.
  initial begin
    init_rom[42] = 8'(IMG_WIDTH - 1);   // clear window: end column
    init_rom[43] = 8'(IMG_HEIGHT - 1);  // clear window: end row
  end

  // Column/row address window for the streaming loop, set once to the
  // full screen.
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
  // Top-level sequencing FSM, following Digilent's documented power-on
  // sequence step by step:
  //   1. D/C low, RES high, VCCEN low                  (OS_RESET, entry)
  //   2. PMODEN high, delay 20ms                        (OS_PMODEN_WAIT)
  //   3. RES low >=3us, then RES high, wait >=3us        (OS_RESET_PULSE_*)
  //   4. Send unlock + config + disable-scroll + clear   (OS_INIT)
  //   5. VCCEN high, delay 25ms                          (OS_VCCEN_WAIT)
  //   6. Display ON (0xAF)                                (OS_DISPLAY_ON)
  //   7. Wait >=100ms before further operation            (OS_POST_ON_WAIT)
  //   8. Set the address window, then stream pixels forever.
  // -------------------------------------------------------------------
  typedef enum logic [3:0] {
    OS_RESET,
    OS_PMODEN_WAIT,
    OS_RESET_PULSE_LOW,
    OS_RESET_PULSE_HIGH,
    OS_INIT,
    OS_VCCEN_WAIT,
    OS_DISPLAY_ON,
    OS_POST_ON_WAIT,
    OS_SET_WINDOW,
    OS_STREAM_ADDR,
    OS_STREAM_HI,
    OS_STREAM_LO
  } oled_state_t;
  oled_state_t state;

  // Cycle counts at 100MHz. A single 24-bit counter (up to ~168ms) is
  // reused across every wait state below.
  localparam int PMODEN_SETTLE_CYCLES = 2_000_000;  // 20ms
  localparam int RESET_PULSE_CYCLES = 500;  // >3us
  localparam int RESET_COMPLETE_CYCLES = 500;  // >3us
  localparam int VCCEN_SETTLE_CYCLES = 2_500_000;  // 25ms
  localparam int POST_ON_CYCLES = 10_000_000;  // 100ms

  logic [23:0] wait_cnt;
  logic [$clog2(INIT_LEN)-1:0] init_idx;
  logic [$clog2(WIN_LEN)-1:0] win_idx;
  logic [ADDR_W-1:0] pix_addr;
  logic byte_issued;

  always_ff @(posedge clk) begin
    if (rst) begin
      state       <= OS_RESET;
      oled_dc     <= 1'b0;
      oled_resn   <= 1'b1;
      oled_vccen  <= 1'b0;
      oled_pmoden <= 1'b0;
      wait_cnt    <= '0;
      init_idx    <= '0;
      win_idx     <= '0;
      pix_addr    <= '0;
      byte_start  <= 1'b0;
      byte_issued <= 1'b0;
      fb_raddr    <= '0;
    end else begin
      byte_start <= 1'b0;

      case (state)
        // D/C low, RES high, VCCEN low -- entry state for the whole
        // sequence, then move straight on to bringing PMODEN up.
        OS_RESET: begin
          oled_dc     <= 1'b0;
          oled_resn   <= 1'b1;
          oled_vccen  <= 1'b0;
          oled_pmoden <= 1'b1;
          wait_cnt    <= '0;
          state       <= OS_PMODEN_WAIT;
        end

        // PMODEN has been high since the OS_RESET cycle; let the 3.3V
        // rail stabilize before doing anything else.
        OS_PMODEN_WAIT: begin
          if (wait_cnt == 24'(PMODEN_SETTLE_CYCLES - 1)) begin
            wait_cnt  <= '0;
            oled_resn <= 1'b0;
            state     <= OS_RESET_PULSE_LOW;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
          end
        end

        // Pulse RES low to actually reset the display controller.
        OS_RESET_PULSE_LOW: begin
          if (wait_cnt == 24'(RESET_PULSE_CYCLES - 1)) begin
            wait_cnt  <= '0;
            oled_resn <= 1'b1;
            state     <= OS_RESET_PULSE_HIGH;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
          end
        end

        // Let the reset operation complete before sending any commands.
        OS_RESET_PULSE_HIGH: begin
          if (wait_cnt == 24'(RESET_COMPLETE_CYCLES - 1)) begin
            wait_cnt <= '0;
            init_idx <= '0;
            state    <= OS_INIT;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
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
              wait_cnt   <= '0;
              oled_vccen <= 1'b1;
              state      <= OS_VCCEN_WAIT;
            end else begin
              init_idx <= init_idx + 1'b1;
            end
          end
        end

        // VCCEN has been high since the last OS_INIT cycle; let the
        // panel's positive supply settle before turning the display on.
        OS_VCCEN_WAIT: begin
          if (wait_cnt == 24'(VCCEN_SETTLE_CYCLES - 1)) begin
            wait_cnt <= '0;
            state    <= OS_DISPLAY_ON;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
          end
        end

        OS_DISPLAY_ON: begin
          if (!byte_issued && !byte_busy) begin
            byte_data   <= 8'hAF;  // display ON
            byte_dc     <= 1'b0;
            byte_start  <= 1'b1;
            byte_issued <= 1'b1;
          end else if (byte_issued && !byte_busy && !byte_start) begin
            byte_issued <= 1'b0;
            wait_cnt    <= '0;
            state       <= OS_POST_ON_WAIT;
          end
        end

        OS_POST_ON_WAIT: begin
          if (wait_cnt == 24'(POST_ON_CYCLES - 1)) begin
            win_idx <= '0;
            state   <= OS_SET_WINDOW;
          end else begin
            wait_cnt <= wait_cnt + 1'b1;
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

  assign streaming = (state == OS_STREAM_ADDR) || (state == OS_STREAM_HI) || (state == OS_STREAM_LO);

endmodule
