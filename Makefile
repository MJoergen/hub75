# Available make targets:
# 'make test'    runs the self-checking simulation; exit code is the verdict
# 'make sim'     the same, but writes a waveform and opens gtkwave
# 'make formal'  runs SymbiYosys over the modules with PSL properties
# 'make lint'    checks every VHDL file against CODING_STYLE.md (needs vsg)
# 'make synth'   Yosys synthesis, for a LUT/FF/BRAM count without Vivado
# 'make bit'     Vivado synthesis and bitstream (needs Vivado at $XILINX_DIR)

XILINX_DIR = /opt/Xilinx/Vivado/2022.2

SOURCES += src/hub75_pkg.vhd
SOURCES += src/sdp_ram.vhd
SOURCES += src/frame_buffer.vhd
SOURCES += src/hub75_scan.vhd
SOURCES += src/hub75.vhd
SOURCES += src/pattern_gen.vhd
SOURCES += src/top_nexys4ddr.vhd

TEST_SOURCES += test/tb_hub75.vhd

TB    = tb_hub75
TOP   = top_nexys4ddr
BUILD = build

# Panel geometry. The defaults describe a 32x16 1/8 scan panel on a 100 MHz
# board; override on the command line to try another one, e.g.
#   make test COLOR_BITS=8 BASE_TICKS=40
COLS       ?= 32
ROWS       ?= 16
COLOR_BITS ?= 6
CLK_DIV    ?= 4
BASE_TICKS ?= 40

GENERICS = -gG_COLS=$(COLS) -gG_ROWS=$(ROWS) -gG_COLOR_BITS=$(COLOR_BITS) \
           -gG_CLK_DIV=$(CLK_DIV) -gG_BASE_TICKS=$(BASE_TICKS)


#############################################################################
# Simulation
#############################################################################

$(BUILD)/work-obj08.cf: $(SOURCES) $(TEST_SOURCES)
	mkdir -p $(BUILD)
	ghdl -i --std=08 --workdir=$(BUILD) $(SOURCES) $(TEST_SOURCES)
	ghdl -m --std=08 --workdir=$(BUILD) $(TB)

.PHONY: test
test: $(BUILD)/work-obj08.cf
	ghdl -r --std=08 --workdir=$(BUILD) $(TB) $(GENERICS)

.PHONY: sim
sim: $(BUILD)/work-obj08.cf
	ghdl -r --std=08 --workdir=$(BUILD) $(TB) $(GENERICS) --wave=$(BUILD)/$(TB).ghw
	gtkwave $(BUILD)/$(TB).ghw &


#############################################################################
# Formal verification
#############################################################################

.PHONY: formal
formal:
	cd formal && sby --yosys "yosys -m ghdl" -f hub75_scan.sby


#############################################################################
# Linting
#############################################################################

.PHONY: lint
lint:
	vsg -c vsg.yml -f $(SOURCES) $(TEST_SOURCES)


#############################################################################
# Synthesis
#############################################################################

# Yosys gets us a resource count and, more usefully, catches anything that
# simulates but will not build. It is not the shipping flow; Vivado is.
.PHONY: synth
synth:
	ghdl -a --std=08 --workdir=$(BUILD) $(SOURCES)
	yosys -m ghdl -p 'ghdl --std=08 --workdir=$(BUILD) $(GENERICS) $(TOP); synth_xilinx -top $(TOP)' > $(BUILD)/yosys.log
	@grep -A30 'Printing statistics' $(BUILD)/yosys.log | tail -25

# -mode batch so that a failure exits non-zero instead of dropping into the
# Vivado prompt; the log and journal go to $(BUILD) rather than the repo root.
.PHONY: bit
bit:
	mkdir -p $(BUILD)
	$(XILINX_DIR)/bin/vivado -mode batch -source hw/build.tcl \
	    -log $(BUILD)/vivado.log -journal $(BUILD)/vivado.jou


#############################################################################

.PHONY: clean
clean:
	rm -rf $(BUILD)
	rm -rf formal/hub75_scan_bmc formal/hub75_scan_cover formal/hub75_scan
	rm -f  *.edif *.log
