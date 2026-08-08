# Round-3 FPU pipeline — results + FPGA-session handoff

Sim-first deliverable for the round-3 prompt (the two residual slow-corner
FMOVE-FPn→memory conversion cones). Done on the MacBook with **ghdl 6.0.0 +
verilator 5.048** (`ghdl synth --out=verilog` emits Verilog directly — no
oss-cad-suite/yosys needed).

Rounds 1 (`c030f1a`, `cir_conv_src_reg`) and 2 (`9b72f48`, FMOVE→mem `.S`/`.D`
exception derivation) are DONE and HW-verified at the timing level. This beat
pipelines the last two single-edge conversion captures the slow-corner STA still
flagged.

Commits (pushed to `origin/7-1-2-boot-working`):
- VHDL logic change (reviewable, the diff below).
- regenerated `rtl/mc68881/fpu_lite/mc68881_top.v` (ghdl net-rename churn,
  ~46k lines touched; the file is net **shorter** — 67258 → 64855 lines —
  because the duplicated `fp80_from_double` recompute collapsed to one register
  and the packed encoder lifted out of the deep move dispatch).
- this doc.

## What changed (the register stage(s) + the edge)

Both targets are FMOVE-FPn→**memory** inline conversions that were computed on
the move-issue edge in the peripheral-mode move block (`MOVE_CFG_MODE_REG_TO_MEM`
inside `alu_control_proc`). The fix mirrors rounds 1/2: the staging block at the
**top of `alu_control_proc`** runs every edge, fed by the already-combinational
`conv_fp_src` / `conv_single_out` / `conv_double_out` (which track the move
source and are stable for cycles before a reg→mem move issues), and now also
captures these two cones one edge ahead. No new FSM state; +1 cycle of
CPU-paced, protocol-invisible latency.

1. **`fp80_to_packed96_fast` — was the worst path in the design (-1.920 ns,
   19,369 paths).** New register `move_packed_encode_reg` is assigned
   `fp80_to_packed96_fast(conv_fp_src)` every edge in the staging block. The
   inline `packed_word := fp80_to_packed96_fast(move_result)` at the
   `packed_decimal_full_g=false` fast path (the synthesized fpu_lite flavor)
   becomes `packed_word := move_packed_encode_reg` — a shallow register read.
   `conv_fp_src == move_result` at that consume site (it is
   `fp_reg_file_reg(move_cfg_decoded_reg.src_idx)`, the same source register the
   move reads), so the value is identical. The `.P`/`packed_decimal_full_g=true`
   full path (the multicycled packed engine) is untouched.

2. **`move_exc_double_inexact_reg` (-1.506 ns, 631 paths) — round-2's own .D
   staging reg.** The inline inexact recompute
   `if fp80_from_double(conv_double_out) /= conv_fp_src` re-evaluated the deep
   `fp80_from_double` cone on the issue edge instead of reusing the round-trip
   round-2 already registered. New pre-stage register `move_exc_double_rt_pre_reg`
   now terminates the `fp80_from_double` cone one edge earlier; both
   `move_exc_double_rt_reg` (the staged round-trip value) and the inexact compare
   read it, so `move_exc_double_inexact_reg`'s fan-in is a register-to-register
   difference. The `.S` mirror got the same treatment symmetrically
   (`move_exc_single_rt_pre_reg`, the milder -0.355 path) since it falls straight
   out of the same block.

## Validation

| corpus                         | baseline | after  |
|--------------------------------|----------|--------|
| cpu_fpu_full_corpus.json       | 1102/218 | 1102/218 — **full output byte-identical (md5 match)** |
| save_restore_corpus.json       | 8/0      | 8/0    |
| double_saverestore_corpus.json | 3/0      | 3/0    |
| fline_trap_regression.json     | 24/0     | 24/0   |

Baseline regenerated from the unmodified (round-2) VHDL with the same local ghdl,
so the comparison isolates this change from ghdl-version drift. The 218 fails are
the known ghdl-synth-drift artifacts (FDIV ×79 / FCMP ×43 / FSQRT ×40 / FSQRT.X
×40 / FMOVEM.X ×16), unchanged set. **No newly-failing tests.** The +1 cycle of
latency is invisible to the 0-delay sim.

## Caveat the FPGA session must know (validation gap — same as round-2)

The cpu_fpu bench drives the FPU through the **CIR coprocessor dialog**, which
never reaches the inline peripheral-mode move block these stages serve (it only
fires on a direct `ADDR_OPSEL` bus write, `cir_launch_alu='0'`). So the
byte-identical corpus confirms *no regression* but does **not** positively
exercise the changed cones. Both registers are still real synthesized logic
(`op_sel_write_decoded` is a live bus signal), which is why they carried the
worst-setup paths — **the slow-corner `report_timing` re-run is the authoritative
check** that `fp80_to_packed96_fast` and `move_exc_double_inexact_reg` left the
violator list.

## Scope note carried forward

Round-3 does NOT target the early-corpus test-3/4 boot wedge — that is
SDRAM-read-path instruction-fetch corruption (CPU/arbiter coherency residual),
orthogonal to the FPU, whose FSM is idle through the hang. This beat's HW payoff
(Finder SANE decimal conversions, FMOVE.X register chains) is gated behind that
separate fetch-corruption fix, but the sim-first RTL work is independent and
landed here.
