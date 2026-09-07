# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

## What this is

A VHDL driver for a HUB75 RGB LED matrix panel, targeting the Digilent Nexys 4 DDR
(Artix-7 `xc7a100tcsg324-1`). Written for a DFRobot 32x16 / 6 mm pitch panel — 1/8 scan, three
address lines — and generic over geometry and colour depth.

All VHDL is **VHDL-2008** (`ghdl --std=08`, `read_vhdl -vhdl2008`). No `ghdl` invocation passes
`-frelaxed`. House style is
[qnice_cpu's CODING_STYLE.md](https://github.com/MJoergen/qnice_cpu/blob/main/CODING_STYLE.md) and
`vsg.yml` is that repository's file, unmodified — keep them in sync rather than diverging.

## Commands

```
make test                  # self-checking simulation; the exit code is the verdict
make test COLOR_BITS=8     # ... at another colour depth
make sim                   # same, plus a waveform in gtkwave
make formal                # SymbiYosys over hub75_scan (bmc + cover)
make lint                  # vsg; the tree is clean, 0 errors and 0 warnings
make synth                 # Yosys, for a resource count without Vivado
make bit                   # Vivado bitstream
make clean
```

`ghdl` here is the **mcode** backend: `ghdl -e` only checks elaboration and produces no
executable, so run with `ghdl -r`. Vivado is at `/opt/Xilinx/Vivado/{2022.2,2024.1}` and is **not
on `PATH`**; the Makefile's `XILINX_DIR` points at 2022.2, matching qnice_cpu.

## Verification

**A finished simulation is not a pass.** `test/tb_hub75.vhd` decodes the panel interface the way
the panel would: it fills the frame buffer while the scanner is held in reset, captures the six
colour pins on every rising edge of `hub75_clk_o`, and on every rising edge of `hub75_lat_o`
checks the captured row against the expected bit-plane, the row address, the blanking, and that
exactly `G_COLS` pulses preceded it. It tracks the expected (row, plane) order independently, so
correct data in the wrong order fails. Verdict is `std.env.finish(0)` / `stop(1)`.

`formal/hub75_scan.psl` covers the interface safety properties. `bmc` and `cover` pass. **`prove`
is deliberately not in the task list**: `f_pulse_budget` does not close under k-induction, because
induction may start with the shadow pulse counter already at its limit mid-row. The invariant that
would close it is described above the property. Do not add a `prove` task without closing it.

## Architecture

```
pattern_gen -> hub75 -+-> frame_buffer -+-> sdp_ram (upper half, rows 0-7)
                      |                 +-> sdp_ram (lower half, rows 8-15)
                      +-> hub75_scan ------> the twelve HUB75 pins
```

Grey scale is **binary code modulation**: bit-plane *p* is displayed for `2**p * G_BASE_TICKS`
ticks, so an N-bit channel costs N passes rather than `2**N`. Planes are the inner loop, rows the
outer one.

Five things are load-bearing and easy to undo by accident:

* **The frame buffer is two RAMs, not one array.** Reading both panel halves at once plus a write
  is three addresses, which does not fit one primitive; splitting it per half gives each RAM the
  one read and one write it has. Measured: Vivado packs the two into a **single RAMB36 tile**.
  "Simplifying" this to one array makes the synthesiser duplicate it.
* **The control outputs are internal signals (`pclk`, `lat`, `oe_n`) with power-up initialisers**,
  driven to the ports by concurrent assignment at the end of the architecture. Reset is
  synchronous and so cannot blank the panel until a clock has run; without the initialisers the
  panel can come up lit, and formal `f_latch_is_blanked` fails at step 0. Assigning the ports
  directly inside `p_scan` as well puts two drivers on them, which resolves to `'X'` and silently
  breaks everything.
* **The pixel pipeline is two ticks deep.** `col` runs to `G_COLS+1` and the shift clock is gated
  off for its first two ticks, which is what makes the `G_COLS` pulses carry columns 0..G_COLS-1.
  Shortening the count by one shifts the whole row by a pixel.
* **`lat_cnt` advances inside each `case` arm**, not once above the case: above it, the last arm
  runs the counter past the end of its range (GHDL bound check).
* **Non-overlapped shift is correct, not lazy.** The panel is blanked for the `G_COLS + 6` ticks a
  row takes to shift and latch. That constant per-plane overhead dims the panel uniformly; it does
  not distort the BCM weighting, because each plane's display phase is still exactly
  `2**p * G_BASE_TICKS`. Overlapping the next shift with the current display is the obvious
  optimisation and the reason the phases are separate states.

Generic contracts, stated in `hub75_scan.vhd`'s header: `G_CLK_DIV >= 2`, and `G_COLS`/`G_ROWS`
powers of two. If the picture comes out mirrored left-to-right on a given panel, count `col`
downwards; nothing else changes.

## Hardware

`hw/nexys4ddr.xdc`. **The Pmod package pins are transcribed from Digilent's master constraints and
have never been checked against a board** — Vivado accepting them proves only that they are legal
pins on this device. `CFGBVS`/`CONFIG_VOLTAGE` are set there because `write_bitstream` warns
without them. `hw/build.tcl` must `file mkdir build` itself, since Vivado will not create an output
directory and `make clean` removes it.

Last measured build (Vivado 2022.2, `-flatten_hierarchy rebuilt`): **WNS +5.210 ns** on the 10 ns
period, 0 failing endpoints, 88 LUTs, 124 registers, 1 block RAM tile, 16 IOB. Roughly twice the
period in hand, so `G_CLK_DIV` is set by what the panel accepts, not by what the FPGA can reach.

**Level shifting is not optional.** The Pmod pins are 3.3 V and the panel's input buffer is a
74HC245 on 5 V, whose guaranteed input high is 3.5 V. Two 74AHCT245s sit in between, and the OE
line carries a 10k pull-up to Pmod 3.3 V so the panel stays blanked while the FPGA is
unconfigured. The full build is in [docs/wiring.html](docs/wiring.html).

## Docs

`docs/*.html` is served by GitHub Pages from `main` at the repository root. A **relative** link to
a `.html` file renders as raw source on github.com, so README links to those pages use the
absolute `https://mjoergen.github.io/hub75/...` URL, with the repository path as a secondary
`(source)` link.
