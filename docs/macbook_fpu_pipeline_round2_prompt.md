# Task: round-2 FPU pipeline — register the exception-event derivation (sim-first)

You are in the **LBMacTwo_MiSTer** repo. This is the **second** sim-first VHDL pipeline beat on
the mc68881 FPU. Round 1 (commit c030f1a) registered the fp80 conversion (`cir_conv_src_reg`) and
WORKED — on real hardware the cpu_fpu corpus now passes FSAVE/FRESTORE and integer→fp80 conversions
that used to crash. Your deliverable is a VHDL diff that the cpu_fpu corpus accepts without
regression; the Windows/FPGA session does the HW build + slow-corner timing close.

## Why (HW-confirmed, with a fresh slow-corner audit)

Post-round-1 the corpus runs far but fails **non-deterministically** on real HW — test 44 one run,
test 3 the next — i.e. a **timing lottery**, not a logic bug. Two failure flavors, both halting at
the bench's STOP point (PC 0x41120, AS frozen):
- **trap** (probe `exc_seen=1`) — the FPU raised a spurious exception.
- **wrong result** (`exc_seen=0`) — a compute/result path delivered a bad value.

Slow-corner `report_timing` (scripts/report_fpu_cones.tcl) — ALL ~3000 worst setup violators are
in `mc68881_top:u_fpu`, and they collapse to the **exception-event derivation**:

| destination register            | violating paths | worst slack |
|---------------------------------|-----------------|-------------|
| `exc_event_force_inexact_reg`   | 2963            | -1.434      |
| `exc_event_result_reg`          | 20              | -1.103      |
| `fp_reg_file_reg` (conv result) | 17              | -1.107      |

~99% funnel into the exception-event flag/result registers — a deep combinational fan-in collapsing
onto them on a single edge. Round 1 registered the conversion *value*, but the exception-event
derivation (inexact detection etc.) still computes from the deep cone on one edge.

## The locus (`rtl/mc68881/vhdl/mc68881_top.vhd`)

Signals ~364-371: `exc_event_valid_reg`, `exc_event_result_reg` (fp80), `exc_event_force_inexact_reg`.
- WRITE sites: ~2810-2825 (packed: `packed_result_fp_reg`, `packed_result_inexact_reg`),
  ~3154-3160 (move: `move_exc_result`, `move_exc_force_inexact`), ~3318-3319, ~3389-3390.
- CONSUME site: ~2338-2358 (the `exc_event_valid_reg='1'` branch →
  `class_result := exc_event_result_reg`, `class_force_inexact := exc_event_force_inexact_reg`).

The deep cone is the `move_exc_force_inexact` / inexact-detection logic feeding
`exc_event_force_inexact_reg` (and the fp80 `exc_event_result_reg`). They are computed on the same
edge as the (now-registered) conversion but from un-registered intermediate logic.

## The change (approach — adapt as the bench/timing demand)

Mirror round 1: insert a register beat so the exception-event flag/result derivation is captured one
edge before it's consumed at the ~2338 classification, rather than fanning the full cone into
`exc_event_*_reg` on the launch edge. Concretely: compute `move_exc_force_inexact` /
`move_exc_result` / packed inexact from the **registered** `cir_conv_src_reg` (round-1 stage) and/or
stage them through a dedicated `*_exc_*_stage_reg`, so `exc_event_force_inexact_reg` /
`exc_event_result_reg` become a shallow register→register copy. The dialog FSM already hosts the
conversion beat in `CIR_XFER_SRC_WAIT` — reuse that spacing; +1 cycle latency, no new state, results
and CIR dialog sequence IDENTICAL. If the 17 `fp_reg_file_reg` (-1.107) paths don't fall out with the
placement shift, give the conversion-result write the same shallow treatment.

Do the FPU_68881 path (default generic). The 68882 `pending_launch` mirror is statically unreachable
in this build — leave a NOTE like round 1 did.

## Validate (the whole point — iterate until clean)

Per CLAUDE.md: regen Verilog from VHDL (rtl/mc68881/convert_to_verilog.sh), build+run the cpu_fpu
corpus. **Baseline first** (unmodified) with YOUR ghdl, then after — the pass criterion is
**byte-identical PASS/FAIL set** (round 1 was 1102/218, the 218 = known ghdl-synth-drift artifacts:
FDIV/FCMP+FDBcc/FSQRT/FMOVEM.X — NOT bugs). The +1 cycle must be invisible to the 0-delay sim:
numeric results, FPSR exception flags, and CIR dialog sequence unchanged. Iterate until the diff set
vs baseline is empty.

## Deliverables
- `git diff rtl/mc68881/vhdl/mc68881_top.vhd` (final), committed locally + pushed (cross-machine sync
  is via the github remote now). Also regenerate + commit the .v (rtl/mc68881/fpu_lite/mc68881_top.v)
  with your ghdl — note the ~45k-line ghdl-version drift is expected; Quartus builds from the VHDL.
- Baseline vs after corpus numbers + any newly-failing tests (should be none).
- One paragraph on the register stage(s) added + the FSM edge, so the FPGA session confirms the build.

The win on the FPGA side: slow-corner worst setup leaves u_fpu (or is small enough that the real
hardware is deterministic), and the HW cpu_fpu corpus completes all 1320 the same way across reboots.

## References
- Round-1 handoff: docs/macbook_fpu_pipeline_prompt.md (the pattern you'll mirror).
- Diagnosis: docs/fetch_corruption_confirmed_20260613.md.
- Upstream truth: ../68881-fpga/.  Build/sim notes: CLAUDE.md (adapt WSL paths for macOS).
