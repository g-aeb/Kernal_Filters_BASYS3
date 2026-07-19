# Kernal_Filters_BASYS3

A reconfigurable spatial-convolution kernel filter, implemented in Verilog/SystemVerilog for the Digilent Basys 3 (Xilinx Artix-7) FPGA, applied to Sobel edge detection.

## Overview

Sobel edge detection works by convolving an image with two small kernels — one that responds to horizontal gradients (Gx) and one that responds to vertical gradients (Gy). The classic 3x3 Sobel kernels are:

```
        -1  0  1              -1 -2 -1
Gx  =   -2  0  2        Gy  =   0  0  0
        -1  0  1               1  2  1
```

Each output pixel is the weighted sum of a pixel neighborhood, so both Gx and Gy convolution are structurally identical — they're the same sliding-window, multiply-accumulate operation, just with different coefficients loaded in. That means a single piece of hardware — one generic kernel filter datapath — can implement Gx, Gy, or any other NxN kernel just by swapping the coefficient set fed into it. Nothing about the pipeline (line buffers, window register, MACs, accumulator) needs to change between filters.

The two gradient outputs, Gx and Gy, are then combined per-pixel into a gradient magnitude:

```
G = sqrt(Gx^2 + Gy^2)
```

approximated in hardware as `G ≈ |Gx| + |Gy|` to avoid a square root, giving the final edge-detected image.

## Project Goals

- **Generic kernel filter core**: one convolution engine (line buffers + sliding window + MAC array) whose behavior is entirely defined by the coefficients loaded into it, so it can be reused as Gx, Gy, or any other NxN filter (3x3, 5x5, ...) without re-synthesizing new datapaths.
- **Sobel edge detection**: two instances (or one time-multiplexed instance) of the kernel filter core configured with the Gx and Gy coefficient sets, run over the same incoming image stream.
- **Magnitude combination**: a per-pixel stage that combines the Gx and Gy outputs (`|Gx| + |Gy|`, saturated/clamped to the output pixel width) into a single edge-detected frame.
- **Switch-selectable filter modes**: use the Basys 3 slide switches to control the filter datapath at runtime, e.g.:
  - Toggle between Gx-only, Gy-only, and combined-magnitude output.
  - Bypass mode (pass-through / unfiltered image) for comparison.
  - Cascade mode — chain multiple kernel filter stages so the output of one filter feeds the input of the next (e.g. blur -> Sobel, or stacked edge passes), letting the switches select which stages are active in the chain.
- **Live display output**: stream the resulting image to a PMOD OLED display attached to the Basys 3 for real-time visual feedback of the selected filter mode.

## Hardware

- **Board**: Digilent Basys 3 (Xilinx Artix-7 XC7A35T)
- **Display**: PMOD OLED (128x32, SSD1306-based), connected via PMOD port
- **Inputs**: Basys 3 slide switches (filter mode select / cascade stage enable), pushbuttons (reset / frame control)

## Toolchain

- **HDL**: Verilog / SystemVerilog
- **Synthesis & Implementation**: Xilinx Vivado (WebPACK / free license)
- **Simulation**: Vivado Simulator (XSim)

## Repository Structure

```
Kernal_Filters_BASYS3/
├── src/            # Verilog/SystemVerilog RTL sources
├── sim/            # Testbenches and simulation sources
├── constraints/     # Basys 3 .xdc constraint files (pins, timing)
├── vivado/         # Vivado project files / TCL build scripts
└── docs/           # Design notes, block diagrams, kernel math
```

## Status

Early development — project scaffolding in progress.
