# Vivado build script for the Nexys 4 DDR.
#
# Run with:  make bit      (or: vivado -mode tcl -source hw/build.tcl)
#
# Written on a machine with no Vivado installed, so the VHDL is verified by
# simulation and by SymbiYosys rather than by this flow. It has since been run:
# synthesis, placement, phys_opt and routing all complete.

set part xc7a100tcsg324-1

# Vivado will not create an output directory for you, and every -file below
# writes into this one. "make bit" creates it as well, so that the log and the
# journal can be pointed here too; this line is what makes the script work when
# it is sourced on its own.
file mkdir build

read_vhdl -vhdl2008 [glob src/*.vhd]
read_xdc hw/nexys4ddr.xdc

synth_design -top top_nexys4ddr -part $part -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

report_timing_summary -file build/timing.txt
report_utilization    -file build/utilization.txt

write_bitstream -force build/top_nexys4ddr.bit
exit
