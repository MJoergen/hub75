## Digilent Nexys 4 DDR - HUB75 32x16 LED matrix panel driver
##
## VERIFY THE PMOD PIN NUMBERS against Digilent's own Nexys4DDR_Master.xdc for
## your board revision before running this. The clock, reset and LED pins below
## are stable across revisions; the Pmod assignments are transcribed and are the
## thing worth a second look.
##
## The panel needs twelve signals. Pin 12 of the HUB75 header (D, the fourth
## address line) is left unconnected: this is a 1/8 scan panel and has only
## three. Ground the panel through the Pmod ground pins (5 and 11 on each
## header) as well as through its own power connector.
##
## DO NOT drive the panel straight from these pins. See the note in
## src/top_nexys4ddr.vhd: put a 74AHCT245 in between.

## Configuration bank 0 properties. Without these, write_bitstream emits
## DRC CFGBVS-1: it cannot work out the I/O voltage support for bank 0. The
## Nexys 4 DDR ties that bank to 3.3 V.
set_property CFGBVS VCCO        [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## Clock: 100 MHz
set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { clk_i }]
create_clock -add -name sys_clk -period 10.000 -waveform {0 5.000} [get_ports { clk_i }]

## CPU_RESETN pushbutton, active low
set_property -dict { PACKAGE_PIN C12 IOSTANDARD LVCMOS33 } [get_ports { rstn_i }]

## Status LEDs: LD0 heartbeat, LD1 panel lit
set_property -dict { PACKAGE_PIN H17 IOSTANDARD LVCMOS33 } [get_ports { led_o[0] }]
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { led_o[1] }]

## Pmod JB - colour data (HUB75 pins 1,2,3,5,6,7) and the shift clock
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports { hub75_r1_o }];   # JB1  -> HUB75 pin 1
set_property -dict { PACKAGE_PIN F16 IOSTANDARD LVCMOS33 } [get_ports { hub75_g1_o }];   # JB2  -> HUB75 pin 2
set_property -dict { PACKAGE_PIN G16 IOSTANDARD LVCMOS33 } [get_ports { hub75_b1_o }];   # JB3  -> HUB75 pin 3
set_property -dict { PACKAGE_PIN H14 IOSTANDARD LVCMOS33 } [get_ports { hub75_r2_o }];   # JB4  -> HUB75 pin 5
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { hub75_g2_o }];   # JB7  -> HUB75 pin 6
set_property -dict { PACKAGE_PIN F13 IOSTANDARD LVCMOS33 } [get_ports { hub75_b2_o }];   # JB8  -> HUB75 pin 7
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { hub75_clk_o }];  # JB9  -> HUB75 pin 13
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports { hub75_lat_o }];  # JB10 -> HUB75 pin 14

## Pmod JC - row address and output enable
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports { hub75_a_o[0] }]; # JC1  -> HUB75 pin 9  (A)
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { hub75_a_o[1] }]; # JC2  -> HUB75 pin 10 (B)
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports { hub75_a_o[2] }]; # JC3  -> HUB75 pin 11 (C)
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { hub75_oe_n_o }]; # JC4  -> HUB75 pin 15

## The panel is a slow, asynchronous sink: it latches on our clock, not the
## FPGA's, so there is no timing relationship to constrain here. What matters is
## that the twelve outputs stay roughly in step with each other, which they do
## by construction -- they are all registered off the same clock.
set_false_path -to [get_ports { hub75_* led_o[*] }]
set_false_path -from [get_ports { rstn_i }]
