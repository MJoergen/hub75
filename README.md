# HUB75 LED matrix driver

A VHDL core that drives a HUB75 RGB LED matrix panel, targeting the Digilent
Nexys 4 DDR (Artix-7 `xc7a100tcsg324-1`). Written for a DFRobot 32x16 / 6 mm
pitch panel — 1/8 scan, three address lines — and generic over panel geometry
and colour depth.

All VHDL is **VHDL-2008** (`ghdl --std=08`, `read_vhdl -vhdl2008` in Vivado) and
follows the conventions in
[qnice_cpu's CODING_STYLE.md](https://github.com/MJoergen/qnice_cpu/blob/main/CODING_STYLE.md);
`vsg.yml` is that repository's, unmodified.

## Status

| | |
|---|---|
| `make test` | **passes** — 96 latches over 2 frames, every pixel, row address and blanking interval checked |
| `make formal` | **passes** — `bmc` and `cover`, 6 assertions and 3 cover statements |
| `make lint` | **clean** — 0 errors, 0 warnings across all 8 files |
| `make synth` | **builds** — 109 LUTs, 126 FFs, 37 CARRY4, 2 RAMB18E1, 0 problems (Yosys, flattened) |
| `make bit` | **never run** — no Vivado on the machine this was written on |

Measured refresh at the default settings: **879 us per frame, 1137 Hz**, against
the 300 Hz these panels are specified for.

## Commands

```
make test                      # self-checking simulation; the exit code is the verdict
make test COLOR_BITS=8         # ... at a different colour depth
make sim                       # same, plus a waveform in gtkwave
make formal                    # SymbiYosys over hub75_scan
make lint                      # vsg against vsg.yml
make synth                     # Yosys, for a resource count without Vivado
make bit                       # Vivado bitstream (needs Vivado at $XILINX_DIR)
make clean
```

## Architecture

```
pattern_gen ──► hub75 ─┬─► frame_buffer ─┬─► sdp_ram (upper half, rows 0-7)
                       │                 └─► sdp_ram (lower half, rows 8-15)
                       └─► hub75_scan ──────► the twelve HUB75 pins
```

* **`hub75_scan`** is the core. It sequences SHIFT / LATCH / DISPLAY for every
  (row, bit-plane) pair and generates grey scale by **binary code modulation**:
  bit-plane *p* is displayed for `2**p * G_BASE_TICKS` ticks, so an 8-bit
  channel costs 8 passes rather than 255. Read its header first; everything
  load-bearing about the timing is written down there.
* **`frame_buffer`** splits the picture into the two halves the panel drives
  simultaneously, so that "read two pixels at once" becomes two ordinary
  one-read RAMs. One address per port is what a block RAM has; three does not
  fit, and the synthesiser silently duplicates the array if you ask for it.
* **`sdp_ram`** is a plain one-write / one-read RAM, one process, one driver,
  no shared variable. Yosys infers a RAMB18E1 per instance.
* **`pattern_gen`** is scaffolding — a drifting colour gradient so you can tell
  a working panel from a dark one. Replace it.

## Wiring

**[Full breadboard build guide](docs/wiring.html)** — parts list, drawings and a
step-by-step, including the two 74AHCT245 level shifters this needs.

Twelve signals over two Pmod headers. HUB75 pin 12 (`D`, the fourth address
line) is unused: this is a 1/8 scan panel and has only three.

| HUB75 pin | Signal | Nexys 4 DDR |
|---|---|---|
| 1, 2, 3 | R1, G1, B1 | JB1, JB2, JB3 |
| 5, 6, 7 | R2, G2, B2 | JB4, JB7, JB8 |
| 13, 14 | CLK, LAT | JB9, JB10 |
| 9, 10, 11 | A, B, C | JC1, JC2, JC3 |
| 15 | OE | JC4 |
| 4, 8, 16 | GND | Pmod pins 5 / 11 |

**Two things will bite you, in this order.**

*Power.* The panel needs its own 5 V supply at 2 A or better, with its ground
tied to the board's. It draws about 2 A at full white. Feeding it from the
Nexys 4 DDR is how you get a board that resets when the picture gets bright.

*Level shifting.* The Artix-7's Pmod pins are 3.3 V LVCMOS; the panel's input
buffer is typically a 74HC245 on a 5 V rail, whose guaranteed input high is
3.5 V. Driving it directly is **out of spec even when it appears to work** — it
survives a short ribbon on the bench and fails intermittently everywhere else.
Put a 74AHCT245 in between and the problem is gone.

The pin numbers in `hw/nexys4ddr.xdc` are transcribed from Digilent's master
constraints; check them against the file for your board revision before the
first run.

## Verification

`test/tb_hub75.vhd` does not check that the simulation finished — it decodes the
panel interface the way the panel itself would. It fills the frame buffer with a
known picture while the scanner is held in reset, then on every rising edge of
`hub75_clk_o` captures the six colour pins into the next column slot, and on
every rising edge of `hub75_lat_o` checks:

* the captured row against the bit-plane of the picture that should have been
  sent, per column and per channel;
* the row address against the row it should have been sent for;
* that the panel was blanked while the latch happened;
* that exactly `G_COLS` clock pulses preceded it.

It tracks the expected (row, plane) sequence independently, so correct-looking
data emitted in the wrong order fails. The verdict is `std.env.finish(0)` or
`stop(1)`, so the exit code is the result.

`formal/hub75_scan.psl` states the properties that make the panel interface
safe rather than merely correct: reset blanks the panel, a latch only ever
happens while blanked, the shift clock never runs while the latch is open, the
row address never moves while the panel is lit, and the pulse count between
latches is exactly the column count. `bmc` and `cover` both pass.

`prove` (k-induction) is deliberately **not** in the task list: `f_pulse_budget`
does not close, because induction may start from a state where the shadow pulse
counter already sits at its limit mid-row. The invariant that would close it is
described in a comment above the property. Left open rather than stated wrongly.

## What this does not do

* **No double buffering.** A picture rewritten faster than the frame rate will
  tear. `pattern_gen` sidesteps it by changing its picture about fifty times a
  second; anything that cannot should add a second `frame_buffer` and swap at
  the top of a frame.
* **No overlap between shifting and displaying.** The panel is blanked for the
  `G_COLS + 6` ticks it takes to shift and latch a row, which costs brightness
  but not correctness — each plane's display time is still exactly
  `2**p * G_BASE_TICKS`, so the weighting is untouched. Overlapping the shift of
  the next row with the display of the current one is the obvious next
  optimisation and the reason the phases are already separate states.
* **No gamma correction.** BCM is linear in time; eyes are not.
* **One panel.** Chaining is `G_COLS` times the number of panels plus a wider
  frame buffer, but it has not been tried.
