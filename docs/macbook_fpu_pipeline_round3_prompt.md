# Task: round-3 FPU pipeline — the two residual slow-corner conversion cones (sim-first)

You are in **LBMacTwo_MiSTer**. This is the **third** sim-first VHDL pipeline beat on the mc68881
FPU. Rounds 1 (`c030f1a`, cir_conv_src) and 2 (`9b72f48`, FMOVE→mem exc derivation) are DONE and
HW-verified at the timing level by the FPGA session: the slow-corner Quartus STA confirms
`exc_event_force_inexact_reg` / `exc_event_result_reg` left the violator list, and `fp_reg_file_reg`
closed to -0.088. **Your deliverable is a VHDL diff the cpu_fpu corpus accepts byte-identically;**
the Windows/FPGA session does the HW build + slow-corner timing close.

## IMPORTANT scope note (read first)

Round-3 does **NOT** target the early-corpus test-3/4 boot wedge. The FPGA session localized that
wedge (HW probe PFLO = `0xFFF6` garbage F-line, 57k fetch count) to **SDRAM-read-path instruction-
fetch corruption** — a CPU/arbiter coherency residual, orthogonal to the FPU (the FPU FSM is idle
through the hang; its datapath is STA-clean). Round-3 fixes the **FPU-specific** corpus tests
(FMOVE.X register chains #994–1033, packed/decimal moves) and Finder SANE decimal conversions — its
HW payoff is gated behind the separate fetch-corruption fix, but the sim-first RTL work is
independent and worth landing now.

## The two residual slow-corner violators (Quartus slow-model STA, this build)

Both are FMOVE-FPn→**memory** inline conversions computed on the move-issue edge — the same class
rounds 1 and 2 pipelined. Neither is multicycle-able honestly (single-edge captures).

1. **`fp80_to_packed96_fast` — worst -1.920 ns, 19,369 paths (the worst path in the whole design).**
   Locus: `rtl/mc68881/vhdl/mc68881_top.vhd:3155`
   `packed_word := fp80_to_packed96_fast(move_result);`  (the `else` of `packed_decimal_full_g`,
   which is FALSE in fpu_lite → this fast/fallback path is the synthesized one). `move_result`
   derives combinationally from `operand_reg`, so the launch is `operand_reg → fp80_to_packed96_fast`
   on one edge.
   FIX: pre-compute `fp80_to_packed96_fast(move_result)` into a dedicated registered stage one edge
   before the move dispatch consumes it — mirror the round-2 `move_exc_*_reg` staging block at the
   top of `alu_control_proc` (~line 2848). The inline `packed_word :=` then becomes a shallow
   register read. The `.P`/`packed_decimal_full_g=true` full path (line 3110, via `operand_hi16_reg`,
   already multicycled) is untouched.

2. **`move_exc_double_inexact_reg` — -1.506 ns, 631 paths.**
   This is round-2's OWN .D staging reg. The deep cone is the inline recompute at ~line 2873:
   `if fp80_from_double(conv_double_out) /= conv_fp_src then move_exc_double_inexact_reg <= '1';`
   — it recomputes `fp80_from_double(conv_double_out)` on the issue edge instead of reusing the
   already-registered `move_exc_double_rt_reg` (which is assigned `fp80_from_double(conv_double_out)`
   the same edge). FIX: stage the `fp80_from_double(conv_double_out)` round-trip ONE edge earlier
   (a new `move_exc_double_rt_pre_reg`) and drive both `move_exc_double_rt_reg` and the inexact
   compare from that registered value, so the `fp80_from_double` cone terminates at a single-driver
   reg one beat before `move_exc_double_inexact_reg`. The `.S` mirror (`move_exc_single_inexact_reg`,
   -0.355) is mild — give it the same treatment only if it falls out naturally.

Diff against `../68881-fpga/` first (authoritative upstream) — if upstream pipelines packed encode,
port theirs.

## Validate (the whole point — iterate until clean)

Per CLAUDE.md (adapt WSL→macOS): regen `.v` (`rtl/mc68881/convert_to_verilog.sh`), build+run the
cpu_fpu corpus. **Baseline first** with YOUR ghdl, then after — pass criterion is a **byte-identical
PASS/FAIL set** (the ~218 fails are known ghdl-synth-drift artifacts: FDIV/FCMP/FSQRT/FMOVEM.X — NOT
bugs). The +1 cycle of latency must be invisible to the 0-delay sim (numeric results, FPSR flags,
CIR dialog sequence unchanged). Also run save_restore_corpus.json (8/0) and
double_saverestore_corpus.json (3/0) — must stay clean.

## Deliverables
- `git diff rtl/mc68881/vhdl/mc68881_top.vhd` (final), committed locally + pushed (github remote is
  the cross-machine sync). Regenerate + commit the `.v` (`rtl/mc68881/fpu_lite/mc68881_top.v`) — the
  ~45k-line ghdl-version drift is expected; Quartus builds from the VHDL.
- Baseline vs after corpus numbers + any newly-failing tests (should be none).
- One paragraph on the register stage(s) added + the FSM edge.

## References
- Round-2 prompt/results: docs/macbook_fpu_pipeline_round2_prompt.md, _round2_results.md (the pattern).
- FPGA-session timing data: scratch/round2_timing_findings.md (per-register slow-corner slack).
- Upstream truth: ../68881-fpga/.  Build/sim notes: CLAUDE.md.
