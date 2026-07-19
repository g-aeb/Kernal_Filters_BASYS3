## Basys 3 constraints for the Sobel kernel-filter project.
##
## Clock, reset button, and switch pin locations below are Digilent's
## standard Basys 3 Master XDC assignments. The PMOD OLEDrgb mapping
## (JB, both rows) follows Digilent's published PmodOLEDrgb-on-Basys3
## reference pinout (CS/SDIN/SCK/DC on JB1-JB4, RES/VCCEN/PMODEN on
## JB7-JB9) -- double-check it against the PmodOLEDrgb reference manual
## and your actual board silkscreen before relying on it; this is the one
## part of the project that can't be verified without real hardware.

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
## PMOD OLEDrgb (PMOD JB, both rows -- 12-pin connector)
## ---------------------------------------------------------------------
set_property PACKAGE_PIN A14 [get_ports oled_csn]
set_property PACKAGE_PIN A16 [get_ports oled_sdin]
set_property PACKAGE_PIN B15 [get_ports oled_sclk]
set_property PACKAGE_PIN B16 [get_ports oled_dc]
set_property PACKAGE_PIN A15 [get_ports oled_resn]
set_property PACKAGE_PIN A17 [get_ports oled_vccen]
set_property PACKAGE_PIN C15 [get_ports oled_pmoden]
set_property IOSTANDARD LVCMOS33 [get_ports {oled_csn oled_sdin oled_sclk oled_dc oled_resn oled_vccen oled_pmoden}]

## ---------------------------------------------------------------------
## Config
## ---------------------------------------------------------------------
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
