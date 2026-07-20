# Kernal_Filters_BASYS3

A reconfigurable spatial-convolution kernel filter, implemented in Verilog/SystemVerilog for the Digilent Basys 3 (Xilinx Artix-7) FPGA, applied to Sobel edge detection and displayed on a PMOD OLEDrgb.

## Overview

Sobel edge detection works by convolving an image with two small kernels — one that responds to vertical edges (Gx) and one that responds to horizontal edges (Gy). The classic 3x3 Sobel kernels are:

```
        -1  0  1              -1 -2 -1
Gx  =   -2  0  2        Gy  =   0  0  0
        -1  0  1               1  2  1
```

Each output pixel is the weighted sum of a pixel neighborhood, so Gx and Gy convolution are structurally identical — the same sliding-window, multiply-accumulate operation, just with different coefficients loaded in. That means a single piece of hardware — one generic kernel filter datapath — can implement Gx, Gy, or any other NxN kernel just by swapping the coefficient set fed into it. Nothing about the pipeline (line buffers, sliding window, MAC array, accumulator) changes between filters.

The two gradient outputs are combined per-pixel into a gradient magnitude, approximated in hardware as `|Gx| + |Gy|` (avoiding a square root) to produce the final edge-detected image.

## Architecture

```
image_rom --> [pre-stage: identity/blur] --+--> [Gx]      -> gx     --+
 (BRAM,         (cascade_en selects)       +--> [Gy]      -> gy     --+--> mode mux --> frame_buffer --> PMOD OLEDrgb
  96x64 8-bit                              +--> [bypass]  -> bypass --+     (RGB565)      (BRAM)          (SPI, SSD1331)
  grayscale)
```

- **`kernel_filter_core`** (`src/kernel_filter_core.sv`) is the reusable engine: a parameterized NxN convolution (line buffers, sliding window, MAC array) whose behavior is entirely defined by a runtime `coeffs` input. `sobel_pipeline` instantiates it **four times** — pre-stage, Gx, Gy, and bypass — all sharing the identical hardware, differing only in which coefficients are loaded.
- **`sobel_pipeline`** (`src/sobel_pipeline.sv`) composes those four instances plus `magnitude_combine` into the full Sobel datapath, and muxes between four display modes based on `disp_mode`:
  - `00` = bypass (the pre-stage's own output — the original image, or blurred if cascade is enabled)
  - `01` = Gx only (vertical-edge strength)
  - `10` = Gy only (horizontal-edge strength)
  - `11` = magnitude (combined Sobel edges, `|Gx| + |Gy|`)
- **Cascade mode** (`cascade_en`): the pre-stage ahead of Gx/Gy is always present in the pipeline. With cascade off it's loaded with an identity kernel (pure pass-through); with cascade on it's loaded with a blur kernel, so Gx/Gy end up operating on a blurred image — a second, different coefficient set running through the exact same reused hardware, chained ahead of the first.
- **`render_ctrl`** (`src/render_ctrl.sv`) owns `image_rom` and a small FSM: on trigger, it clears the frame buffer to black, then streams the source image through `sobel_pipeline`, writing each output pixel (converted 8-bit grayscale -> RGB565) to its address in `frame_buffer`.
- **`frame_buffer`** (`src/frame_buffer.sv`) is a dual-port BRAM decoupling the fast pixel pipeline (write side) from the much slower SPI writes to the display (read side, driven continuously by `pmod_oledrgb`).
- **`pmod_oledrgb`** (`src/pmod_oledrgb.sv`) is the SSD1331 SPI driver: runs the panel's init sequence once, sets the address window to the full screen once, then streams `frame_buffer`'s contents out over SPI forever.

Switches: `SW[1:0]` select the display mode, `SW[2]` enables cascade; changing either triggers a fresh render pass. `SW[15:3]` are reserved (e.g. for selecting among multiple stored images later). `BTNC` is the global reset.

`LD[3:0]` are a permanent bring-up/health-check debug ladder for the OLED path, since the SPI protocol and pin mapping to the physical panel can't be verified in simulation:

| LED | Meaning | If it never lights |
|---|---|---|
| LD0 | Heartbeat — blinks off the system clock, independent of everything else | Bitstream isn't running at all |
| LD1 | `oled_resn` — goes high almost immediately after reset releases, dips low briefly (~5us) for the actual reset pulse around the 20ms mark, then stays high | OLED driver's power-up sequencing or the `oled_resn` pin mapping |
| LD2 | Sticky: latches once the full power-on sequence (~145ms: PMODEN settle, reset pulse, command-lock/init bytes, VCCEN settle, display ON, post-ON wait) finishes and pixel streaming starts | SPI/init FSM is stuck partway through power-on — check the SPI clock mode/idle polarity and the command-lock unlock byte first |
| LD3 | Sticky: latches once a full render pass into the frame buffer completes | Image pipeline itself (independent of the OLED path) |

LD2 in particular takes a little over 145ms to light after reset (the OLED's documented power-on sequence has ~145ms of mandatory settling time built in), so give it a moment before concluding it's stuck.

## Hardware

- **Board**: Digilent Basys 3 (Xilinx Artix-7 XC7A35T)
- **Display**: PMOD OLEDrgb — 96x64 RGB OLED, 16-bit color (RGB565), SSD1331-based, connected via PMOD JB (SPI)
- **Inputs**: Basys 3 slide switches (filter mode select / cascade enable), BTNC (reset)
- **Outputs**: LD0-LD3 (bring-up debug LEDs, see table above)

## Toolchain

- **HDL**: Verilog / SystemVerilog
- **Synthesis & Implementation**: Xilinx Vivado (WebPACK / free license)
- **Simulation**: Icarus Verilog (used during development — see caveats below) or Vivado Simulator (XSim)

## Repository Structure

```
Kernal_Filters_BASYS3/
├── src/                      # Synthesizable RTL
│   ├── kernel_coeffs_pkg.sv  #   Coefficient ROM (Sobel Gx/Gy, identity, blur)
│   ├── kernel_filter_core.sv #   Generic reconfigurable NxN convolution engine
│   ├── magnitude_combine.sv  #   |Gx| + |Gy|, saturated
│   ├── sobel_pipeline.sv     #   Composes the core into the full Sobel datapath + mode mux
│   ├── image_rom.sv          #   Source image BRAM, streams in raster order
│   ├── frame_buffer.sv       #   Dual-port output frame BRAM
│   ├── render_ctrl.sv        #   Clear + stream FSM, drives image_rom -> sobel_pipeline -> frame_buffer
│   ├── pmod_oledrgb.sv       #   SSD1331 SPI driver
│   ├── debounce.sv           #   Switch/button debouncer
│   └── top.sv                #   Top-level, switch handling, module wiring
├── sim/                      # Testbenches + generated .mem test images
├── constraints/basys3.xdc    # Pin mapping, clock constraint
├── vivado/build.tcl          # Recreates the Vivado project from scratch
├── photos/                   # Pictures of the board/display running
└── tools/
    ├── gen_test_image.py     # Synthetic placeholder test image generator
    └── img_to_mem.py         # Downsizes a real photo to 96x64 for image_rom
```

## Building in Vivado

```
vivado -mode batch -source vivado/build.tcl
```

This creates `vivado/project/kernel_filters_basys3.xpr` (gitignored) with all sources, the constraints file, and `sim/test_image.mem` added as a memory initialization file. Open it in the GUI, or continue in batch mode, to run synthesis/implementation and generate a bitstream.

## Loading a real image

`sim/test_image.mem` (the default `image_rom` contents) is a synthetic placeholder — a gradient, border, and circle, generated by `tools/gen_test_image.py`. To load an actual photo instead:

```
pip install pillow
python tools/img_to_mem.py your_photo.jpg --out sim/test_image.mem --preview
```

This grayscales, center-crops, and downsizes the image to 96x64, writes it as a `$readmemh`-compatible `.mem` file, and (with `--preview`) also saves a 16x-upscaled PNG so you can see exactly what will be loaded before resynthesizing. `--fit contain` letterboxes instead of cropping, and `--fit stretch` ignores aspect ratio entirely.

## Simulation

Every module below `top.sv` has been simulated (with Icarus Verilog) and checked against a from-scratch behavioral reference, including full pixel-count and coverage checks:

- `sim/tb_kernel_filter_core.sv` — the generic core against identity/Gx/Gy/blur, verifying the convolution math and output timing/coordinates.
- `sim/tb_cascade.sv` — two `kernel_filter_core` instances chained directly, verifying the core composes correctly when a downstream stage's input coordinates don't start at (0,0).
- `sim/tb_sobel_pipeline.sv` — the full pipeline across all 4 display modes x 2 cascade settings, at both a small test size and the real 96x64 resolution (44,160 pixels checked with zero mismatches).
- `sim/tb_pmod_oledrgb.sv` — SPI byte-shifter mechanics and FSM sequencing (init -> window -> streaming).

**Known simulator limitation**: Icarus Verilog (as of the version used here) can't elaborate a `parameter string` that's forwarded by reference through more than one level of module hierarchy (`top` -> `render_ctrl` -> `image_rom`, both using `.INIT_FILE(INIT_FILE)`). This is a standard, portable SystemVerilog pattern that Vivado's synthesizer and XSim handle correctly — it only affects simulating `top.sv`/`render_ctrl.sv` standalone in Icarus. `sim/tb_top_smoke.sv` works around it by instantiating `render_ctrl` directly with a literal `INIT_FILE` string, which verifies everything except `top.sv`'s own (simple) switch-debounce/edge-detect glue logic.

## Status

Working end-to-end on real hardware: image source -> Sobel pipeline -> frame buffer -> OLED driver, displayed live on the PMOD OLEDrgb over PMOD JB. See `photos/` for pictures of the board running.

Getting here took two rounds of hardware bring-up, since the SPI protocol/pin mapping to the physical panel couldn't be verified in simulation:

**Round 1 — no output at all.** Cross-checking against Digilent's Pmod OLEDrgb Reference Manual turned up several concrete bugs in the original guesses:

- **SPI mode was wrong entirely** — the SSD1331 requires mode 3 (clock idles high, data changes on the falling edge, captured on the rising edge); the original driver used mode 0 (idle low).
- **Missing command-lock unlock byte** (`0xFD, 0x12`) — without it the controller won't accept any of the configuration commands that follow.
- **VCCEN power sequencing was backwards** — it must stay low through the entire configuration sequence and only go high afterward, right before the display-ON command, not immediately alongside PMODEN.
- **PMOD pin mapping was off by one from SCLK onward** — pin 3 on the Pmod OLEDrgb connector is genuinely not-connected, which the original mapping missed, shifting SCK/D-C/RES/VCCEN/PMODEN each one JB position early.
- Also added the disable-scrolling and explicit GRAM-clear commands from Digilent's documented sequence, and the ~145ms of mandatory power-on settling time (PMODEN/VCCEN/post-display-ON waits) that were missing.

**Round 2 — still dark after the above.** To rule out a bad physical connector, every OLED signal was temporarily fanned out to both PMOD JB and PMOD JC from a single bitstream (since removed) so the module could be tried on either without resynthesizing — still dark on both, which pointed away from the connector and at the driver logic instead. The actual cause: `pmod_oledrgb.sv`'s `oled_dc` (data/command select) signal was driven by two separate `always_ff` blocks — the low-level SPI byte-shifter (correctly, per-byte) and a leftover direct assignment in the top-level power-on FSM (always to constant `0`). Simulators silently resolve multi-driven signals like this by event order, so it passed simulation every time, but Vivado's synthesizer collapsed the conflict to the constant driver and discarded the real one, permanently tying `oled_dc` to command mode — every pixel byte streamed out was interpreted by the SSD1331 as a command, so nothing ever rendered, regardless of connector. The FPGA-side debug LEDs (LD0-LD3) still reported a clean power-on and streaming start throughout, since they only reflect internal FSM state, not what the physical panel did with the bytes. Removing the redundant FSM-side drive fixed it.
