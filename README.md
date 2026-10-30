# Synchronous FIFO in SystemVerilog

A synchronous FIFO (first in, first out) designed in two different ways, each verified with
a self-checking testbench and then synthesized and timed in Vivado for a Spartan-7 FPGA
(Digilent Arty S7-25). The goal was to compare the two designs on correctness, area and speed.

Method A is the FIFO I used to fix a lost-byte bug in my UART project
([uart-rtl-validation-spartan7](https://github.com/micahpinto/uart-rtl-validation-spartan7)).
Method B is the version that also works for an asynchronous (dual-clock) FIFO.

## What a FIFO does

A FIFO is a small waiting line for data. The writer puts bytes in, the reader takes them out
in the same order. It lets two blocks that don't run in step (bursts, short pauses) pass data
without losing any.

```
 writer ----->  [ 3A ][ 7F ][ 12 ][    ][    ] ...  -----> reader
              ↑ oldest (read next)   ↑ next free slot
```

Inside, it is a circular buffer: a small memory, a **write pointer** (the next free slot)
and a **read pointer** (the oldest byte). Both pointers move forward and wrap around to 0.
With a power-of-2 depth the wrap happens by itself when the pointer overflows.

## Interface (identical for both designs)

| Port | Dir | Meaning |
|---|---|---|
| `i_Clk` | in | one clock for both sides |
| `i_Wr_En` | in | write request |
| `i_Wr_Data[WIDTH-1:0]` | in | byte to write |
| `i_Rd_En` | in | read request |
| `o_Rd_Data[WIDTH-1:0]` | out | the oldest byte, always visible (first-word fall-through) |
| `o_Empty` | out | nothing to read |
| `o_Full` | out | no room to write |

Parameters: `WIDTH` (bits per slot, default 8) and `DEPTH` (number of slots, default 16,
must be a power of 2).

Safety rules inside both designs: a write is ignored when full, a read is ignored when empty
(`w_Wr = i_Wr_En && !o_Full`, `w_Rd = i_Rd_En && !o_Empty`). Only the pointers are reset,
never the memory.

## The two designs

The only problem to solve: when the two pointers are equal, the FIFO is either **empty** or
**full**. The two methods tell these apart differently.

### Method A: count register (`design/fifo_count.sv`)

A separate counter goes +1 on a write, −1 on a read, unchanged when both happen in the
same clock.

- empty = `count == 0`
- full = `count == DEPTH`
- For DEPTH 16: 4-bit pointers + a 5-bit count (0 to 16) = **13 flip-flops**

### Method B: extra "lap" bit (`design/fifo_lapbit.sv`)

Each pointer gets one extra bit on top that flips every time the pointer wraps around
(a lap counter). No count register.

- empty = pointers completely equal (same slot, same lap)
- full = same slot bits, **different** lap bit
- For DEPTH 16: two 5-bit pointers = **10 flip-flops**

| | Method A (count) | Method B (lap bit) |
|---|---|---|
| Stores | two pointers + a count | two pointers, 1 bit wider |
| Empty | `count == 0` | pointers equal |
| Full | `count == DEPTH` | same slot, different lap bit |
| Bytes waiting | `count` | `wr_ptr − rd_ptr` |
| Works for an async FIFO | no (one counter can't be updated by two clocks) | yes |

## Verification

One testbench per design (`sim/fifo_count_tb.sv`, `sim/fifo_lapbit_tb.sv`), identical except
for the module name, so both designs get exactly the same traffic.

- **Reference model:** a SystemVerilog queue holds what the FIFO *should* contain.
  Accepted write - `push_back`, accepted read - `pop_front`.
- **Checked on every clock** (at the falling edge, when everything is stable):
  `empty` and `full` must match the model exactly, and `o_Rd_Data` must equal the oldest
  byte in the model.
- **Directed tests:** write 3 / read 3 in order, fill to full, write when full (must be
  refused), drain to empty (the refused byte must never appear), read when empty (refused),
  write + read in the same clock.
- **Random test:** 5,000 clocks in 4 phases (mostly writes, mostly reads, balanced, anything).
- **Coverage counters** prove the corner cases were really reached.
- `DEPTH = 4` in the testbench so full and empty happen often.

## Results

### Simulation (Vivado simulator)

Both designs: **TEST PASSED, 0 errors.**

| Coverage | Count |
|---|---|
| Accepted writes | 1,614 |
| Accepted reads | 1,611 |
| Same-clock write + read | 497 |
| Writes refused when full | 883 |
| Reads refused when empty | 926 |

### Synthesis and timing

Arty S7-25 (xc7s25csga324-1), out-of-context synthesis and implementation,
DEPTH 16 × WIDTH 8, constrained at 100 MHz (`constraints/fifo_timing.xdc`).

| | Method A (count) | Method B (lap bit) |
|---|---|---|
| Flip-flops | 13 | **10** |
| LUT as memory (distributed RAM) | 8 | 8 |
| LUT as logic | 15 | **11** |
| LUT total | 23 | **19** |
| WNS (setup slack) at 100 MHz | **6.858 ns** | 6.582 ns |
| WHS (hold slack) | 0.038 ns | 0.085 ns |
| WPWS (pulse width slack) | 3.750 ns | 3.750 ns |
| Estimated Fmax = 1 / (10 ns − WNS) | **≈ 318 MHz** | ≈ 292 MHz |
| Worst path | `r_Count[3]` - memory write enable, 1 logic level, 2.525 ns (logic 0.580 + net 1.945), fanout 12 | `r_Rd_Ptr[2]` - memory write enable, 2 logic levels, 2.801 ns (logic 0.842 + net 1.959), fanout 17 |

**Conclusion: Method B is smaller, Method A is slightly faster.**

- A's full check (`count == 16`) depends on only a few bits and fits in one 6-input LUT.
- B's full check compares two 5-bit pointers (10 inputs), which needs two LUT levels.
- Both meet 100 MHz with a large margin. Area and speed are different things: fewer
  flip-flops does not mean a shorter worst path.
- The 16 × 8 memory became distributed RAM (LUTs used as memory, 128 bits in 8 LUTs),
  because it has no reset and a combinational read.
- Out of context, Vivado reports the ports as unconstrained (no input/output delay);
  this is expected, only flip-flop to flip-flop paths are timed.

All reports and screenshots are in `results/`.

## What I got wrong

I predicted Method A would be **slower**, because it has an adder/subtractor for the count.
The timing report showed the opposite: FPGA adders use fast dedicated carry chains, and speed
is decided by the single longest path, which here was B's wider pointer comparison.

## Repository layout

```
design/        fifo_count.sv, fifo_lapbit.sv
sim/           fifo_count_tb.sv, fifo_lapbit_tb.sv
constraints/   fifo_timing.xdc   (100 MHz clock for out-of-context timing)
results/       console logs, waveforms, utilization, timing summary, worst path (both methods)
```
