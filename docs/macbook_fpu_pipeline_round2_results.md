# Round-2 FPU pipeline — results + FPGA-session handoff

Sim-first deliverable for `docs/macbook_fpu_pipeline_round2_prompt.md`. Done on
the MacBook with **ghdl 6.0.0 + verilator 5.048** (no oss-cad-suite/yosys needed
— `ghdl synth --out=verilog` emits Verilog directly).

Commits (pushed to `origin/7-1-2-boot-working`):
- `9b72f48` — VHDL logic change (reviewable, 105 +/30 -).
- `6df887b` — regenerated `rtl/mc68881/fpu_lite/mc68881_top.v` (ghdl net-rename churn).

## What changed (the register stage + the edge)

Target: the slow-corner worst-setup endpoints `exc_event_force_inexact_reg`
(2963 paths, -1.434) and `exc_event_result_reg` (20, -1.103). The deep cone is
the **FMOVE FPn→mem (.S/.D) exception derivation** in `alu_control_proc`'s inline
move block: `conv_fp_src → fp80_to_single → fp80_from_single → fp80 compare →
exc_event_force_inexact_reg` (and the fp80 `exc_event_result_reg`), all on the
single op-issue edge.

Mirror of round 1: a block at the **top of `alu_control_proc`** (runs every edge,
fed by the already-combinational `conv_fp_src` / `conv_single_out` /
`conv_double_out`, which track the move source and are stable for cycles before a
reg→mem move issues) recomputes the .S/.D round trip + inexact/under/overflow and
captures them into dedicated single-driver registers:
`move_exc_single_rt_reg`, `move_exc_double_rt_reg`,
`move_exc_{single,double}_{inexact,unfl,ovfl}_reg`.
The inline `MOVE_CFG_MODE_REG_TO_MEM` `.S`/`.D` cases now just read those
registers, so `exc_event_force_inexact_reg`/`exc_event_result_reg` become shallow
register→register copies. The deep round-trip cone is now an isolated
register-to-register path terminating at single-driver regs — the FPGA session
can close it or surgically multicycle `move_exc_*_reg` without touching the
many-driver `exc_event_*_reg` (same lever as round 1's `cir_conv_src_reg`).

No new FSM state; +1 cycle of CPU-paced, protocol-invisible latency. The staged
expressions are line-for-line the old inline derivation with
`move_result == conv_fp_src`.

## Validation

| corpus                         | baseline | after  |
|--------------------------------|----------|--------|
| cpu_fpu_full_corpus.json       | 1102/218 | 1102/218 — **full output byte-identical** |
| save_restore_corpus.json       | 8/0      | 8/0    |
| double_saverestore_corpus.json | 3/0      | 3/0    |
| fline_trap_regression.json     | 24/0     | 24/0   |

The 218 fails are the known ghdl-synth-drift artifacts (FDIV/FCMP/FSQRT/
FMOVEM.X), unchanged set. **No newly-failing tests.**

## Caveat the FPGA session must know (validation gap)

The cpu_fpu bench drives the FPU through the **CIR coprocessor dialog**, which
routes reg→mem moves through `CIR_XFER_DST` staging and reg→reg/mem→reg moves
through the deferred `cir_move_pending` copy. The **inline peripheral-mode move
block this commit pipelines is never reached by the bench** (it only fires on a
direct `ADDR_OPSEL` bus write, `cir_launch_alu='0'`). So the byte-identical
corpus confirms *no regression* but does **not positively exercise the changed
cone** — and even on the live path the corpus FMOVE.S/.D values are exact
integers, so inexact/over/underflow never assert. The block IS synthesized
(`op_sel_write_decoded` is a real bus signal), which is why it carries the
worst-setup paths. **The slow-corner `report_timing` re-run is the authoritative
check** that `exc_event_force_inexact_reg`/`exc_event_result_reg` left the
violator list.

## Round-3 candidate (if needed)

The conv-result `fp_reg_file_reg` write (17 paths, -1.107) was left inline (per
prompt: only if it doesn't fall out). It is the dead inline mem→reg conversion
`fp_reg_file_reg(dst_idx) <= fp80_from_single(operand_reg(0))`. If the slow
corner still flags it after this placement shift, stage `move_result` for the
mem→reg `.S`/`.D` cases the same way. The 68882 `pending_launch` mirror remains
statically unreachable in the FPU_68881 build (round-1 NOTE still applies).
