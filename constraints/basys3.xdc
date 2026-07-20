## Basys 3 constraints for the Sobel kernel-filter project.
##
## Clock, reset button, and switch pin locations below are Digilent's
## standard Basys 3 Master XDC assignments. The PMOD OLEDrgb mapping (JB,
## both rows, 12-pin connector) follows the Pmod OLEDrgb Reference Manual's
## own pinout table exactly:
##   J1 pin:  1    2     3   4    5    6    7    8    9      10       11   12
##   Signal:  CS   MOSI  NC  SCK  GND  VCC  D/C  RES  VCCEN  PMODEN   GND  VCC
## mapped 1:1 onto Basys 3's JB1-JB12. Note pin 3 is NC (not connected) --
## an earlier draft of this file missed that and shifted SCK/D-C/RES/
## VCCEN/PMODEN each one JB position too early.

## ---------------------------------------------------------------------
## Clock (100 MHz)
## ---------------------------------------------------------------------
set_property PACKAGE_PIN W5 [get_ports clk100mhz]
set_property IOSTANDARD LVCMOS33 [get_ports clk100mhz]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports clk100mhz]

## ---------------------------------------------------------------------
## Reset button (BTNC)
## ---------------------------------------------------------------------
set_property PACKAGE_PIN U18 [get_ports btnc]
set_property IOSTANDARD LVCMOS33 [get_ports btnc]

## ---------------------------------------------------------------------
## Slide switches (SW0-SW15)
## SW0-SW1 = display mode, SW2 = cascade enable, SW3-SW15 = reserved
## ---------------------------------------------------------------------
set_property PACKAGE_PIN V17 [get_ports {sw[0]}]
set_property PACKAGE_PIN V16 [get_ports {sw[1]}]
set_property PACKAGE_PIN W16 [get_ports {sw[2]}]
set_property PACKAGE_PIN W17 [get_ports {sw[3]}]
set_property PACKAGE_PIN W15 [get_ports {sw[4]}]
set_property PACKAGE_PIN V15 [get_ports {sw[5]}]
set_property PACKAGE_PIN W14 [get_ports {sw[6]}]
set_property PACKAGE_PIN W13 [get_ports {sw[7]}]
set_property PACKAGE_PIN V2  [get_ports {sw[8]}]
set_property PACKAGE_PIN T3  [get_ports {sw[9]}]
set_property PACKAGE_PIN T2  [get_ports {sw[10]}]
set_property PACKAGE_PIN R3  [get_ports {sw[11]}]
set_property PACKAGE_PIN W2  [get_ports {sw[12]}]
set_property PACKAGE_PIN U1  [get_ports {sw[13]}]
set_property PACKAGE_PIN T1  [get_ports {sw[14]}]
set_property PACKAGE_PIN R2  [get_ports {sw[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

## ---------------------------------------------------------------------
## Debug LEDs (LD0-LD3) -- see top.sv header for what each one indicates
## ---------------------------------------------------------------------
set_property PACKAGE_PIN U16 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

## ---------------------------------------------------------------------
## PMOD OLEDrgb (PMOD JB, both rows -- 12-pin connector)
## JB1=CS, JB2=MOSI, JB3=NC, JB4=SCK, JB7=D/C, JB8=RES, JB9=VCCEN, JB10=PMODEN
## ---------------------------------------------------------------------
set_property PACKAGE_PIN A14 [get_ports oled_csn]
set_property PACKAGE_PIN A16 [get_ports oled_sdin]
set_property PACKAGE_PIN B16 [get_ports oled_sclk]
set_property PACKAGE_PIN A15 [get_ports oled_dc]
set_property PACKAGE_PIN A17 [get_ports oled_resn]
set_property PACKAGE_PIN C15 [get_ports oled_vccen]
set_property PACKAGE_PIN C16 [get_ports oled_pmoden]
set_property IOSTANDARD LVCMOS33 [get_ports {oled_csn oled_sdin oled_sclk oled_dc oled_resn oled_vccen oled_pmoden}]

## ---------------------------------------------------------------------
## PMOD OLEDrgb bring-up diagnostic duplicate (PMOD JC, both rows)
## Every oled_* signal above is fanned out bit-identically to oled2_* /
## JC in top.sv, confirmed against the Basys 3 Reference Manual's own
## pinout table (same JC1/JC2/JC4/JC7/JC8/JC9/JC10 positions as JB).
## Lets the physical module be moved to JC to isolate a bad port/
## connection without resynthesizing. Remove once the display is
## confirmed working on JB.
## ---------------------------------------------------------------------
set_property PACKAGE_PIN K17 [get_ports oled2_csn]
set_property PACKAGE_PIN M18 [get_ports oled2_sdin]
set_property PACKAGE_PIN P18 [get_ports oled2_sclk]
set_property PACKAGE_PIN L17 [get_ports oled2_dc]
set_property PACKAGE_PIN M19 [get_ports oled2_resn]
set_property PACKAGE_PIN P17 [get_ports oled2_vccen]
set_property PACKAGE_PIN R18 [get_ports oled2_pmoden]
set_property IOSTANDARD LVCMOS33 [get_ports {oled2_csn oled2_sdin oled2_sclk oled2_dc oled2_resn oled2_vccen oled2_pmoden}]

## ---------------------------------------------------------------------
## Config
## ---------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
