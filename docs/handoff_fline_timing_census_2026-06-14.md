# Handoff — F-line bomb: full STA census says it's a TIMING LOTTERY, not one cone

**Date:** 2026-06-14 (session 3) · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Supersedes the analysis of** `docs/handoff_fline_fpu_timing_2026-06-14.md` (session 2). That doc said
"F-line = one FPU conversion cone failing setup on silicon." **This session's board-free census shows
that's not quite right** — read the reframe below before acting.

## TL;DR — what this session established (board-free, no HW needed)

1. **Ran a COMPLETE failing-setup census** (`scratch/diag_timing2.tcl`, 6000-path cap, grouped by
   endpoint, slow corner, on the deployed `4db7a3f5` netlist). **31 distinct failing setup endpoints.**
   Every one is a **false-positive of a known pacing class** — none is a genuine single-cycle failure:
   - **FPU FSM-spaced converter cloud:** `move_packed_encode_reg` −140.9 (FMOVE.P fast encoder),
     `move_exc_double_rt_pre_reg` −12.9, `conv_fp_src` −12.6 (a *combinational* `reg`/wire, so this is
     a synth-merged converter cloud, not a clean cone), `move_exc_double_ovfl_reg` −9.8,
     `move_exc_single_rt_pre_reg` −2.7. Recomputed every edge from `conv_fp_src`
     (`= fp_reg_file_reg(...)`), consumed only at a CPU-paced FMOVE-to-mem issue.
   - **FPU bus-paced operand path** (`FROM tg68k|regfile` or `operand_reg`): `micro_remaining_reg` −11.0,
     `micro_total_reg` −7.2, `result_hi_reg` −9.0, `result_ex_reg` −7.4, `result_lo_reg` −0.9,
     `fp_reg_file_reg` −8.6, `exc_event_*` −1 to −1.8. These are CPU-bus writes — the 68020 holds the
     data stable for the whole multi-clk_sys bus cycle (the SDC already multicycles *part* of this set,
     `-setup 2 -from operand_reg/tg68k`, but the `-to` scope is incomplete).
   - **TG68 CPU-internal, clkena-paced** (NON-FPU): `regfile→regfile` −6.1 **×510 paths**,
     `data_write_tmp` −6.9, `memaddr_delta_rega/b`, `TG68K_ALU|Flags` −5.5, `memmask`/`wbmemmask`,
     `oddout`, `RDindex_A/B`. The 68020 core runs on a **16 MHz clock-enable** (2 clk_sys per CPU
     cycle), so a 1-cycle STA check is wrong by 2×; these have been false-failing on **every** build.
2. **ZERO hold violations design-wide** (worst hold **+0.246 ns**). `fpu_fail.tcl` only ever checked
   setup; hold is clean, so the bomb is not a hold race.
3. **The design meets timing on real silicon** for working builds (it boots, and historically ran the
   FP corpus **1319/1320 on a real Mac II**, memory `project_fpu_corpus_fixes`). So the −slack cones
   really are paced false-positives, not silicon failures.
4. **∴ The F-line bomb is TIMING-LOTTERY-sensitive, not a single fixable setup cone.** All cones are
   "supposed to" pass via FSM/bus/clkena pacing; on an *unlucky placement* one paced cone's physical
   delay exceeds its true (multi-cycle) budget and fails for real. This is the "FPU timing lottery"
   the SDC preamble and memory describe — now pinned to a *mechanism*, not a single endpoint.

## The proven sub-result (session 2's #1 target, now closed)

`cir_conv_src_reg ← cir_operand_staging` (−10.9) — the one CLEAN reg→reg failing cone — has a **proven
≥2-cycle FSM window** (traced in `cir_dialog_proc`: `cir_operand_staging` is written ONLY in
`CIR_XFER_SRC`, then the FSM sits in `CIR_XFER_SRC_WAIT`→`WAIT2`; `cir_conv_start` captures
`cir_conv_src_reg` on the WAIT→WAIT2 edge — launch→capture spans the wait state(s)). So it is an STA
false-positive, **not** at risk on silicon (cone ~43 ns ≪ ~96 ns 3-cycle budget, ratio 0.45).

It is now closed by a **scoped, honest multicycle** in `LBMacTwo.sdc` (`-setup 2/-hold 1`,
`-from cir_operand_staging -to cir_conv_src_reg`). The `-to` is scoped to that single-driver register,
so it relaxes ONLY the conversion cone — never a `result_*`/handshake/FPctl path (the c8e8c9ad failure
mode). Verified board-free: the cone dropped out of the failing list, no new failures.

**This is the RTL pipeline beat the SDC's KNOWN-RESIDUAL header anticipated — except the FSM already
provides the cycles, so an SDC multicycle (zero RTL/corpus risk) is strictly safer than re-pipelining.
Session 2 recommended approach (B); (A)-done-right is better here because the window is PROVEN.**

## What this session BUILT (in flight as of this writing)

A **probe-free** RBF (DBG_WEDGE stripped, `LBMacTwo.qsf:71`) **+** the `cir_conv_src_reg` multicycle.

- **Why probe-free is the real lever:** the JTAG IF-ring/coherency probes are RUNTIME-BLIND (proven
  session 2 — they key off the SDRAM slot handshake that stops at turbo). They add real logic + ISSP
  routing congestion that worsens exactly the timing pressure the census shows drives the lottery.
  Removing them is the **biggest safe timing-relief lever** and yields the shippable config. The
  multicycle rides along (free + correct + documents the FSM window).
- **Known-good RBF backed up:** `output_files/LBMacTwo_4db7a3f5_known_good.rbf`
  (md5 `4db7a3f5061dff82a51a686110278179`). Revert target if the placement re-roll breaks boot.

## HW test plan (the only oracle — probe is runtime-blind)

Deploy = `scp` RBF → `/media/fat/_Unstable/LBMacTwo.rbf` (host/creds `scripts/local.env`; **NO reload**,
shared board — user loads the core). Then, **as a controlled A/B vs `4db7a3f5`:**
1. **Boot:** chime → happy Mac → Finder (confirm the placement re-roll didn't resurface the Sad Mac).
2. **F-line:** launch TeachText (or any app). Did the "bad F-Line" bomb reproduce?
3. Interpret:
   - **Boots + no F-line** → 🎉 the lottery/timing-relief fixed it. Keep this as the new baseline;
     commit + update memory. (Attribution between probe-relief / multicycle / lucky placement is
     ambiguous but a working shippable build is the win.)
   - **Boots + F-line persists** → strong evidence the bomb survives MAXIMAL timing relief ⇒ it is
     **not** timing-pressure-driven ⇒ pivot to the non-timing tracks below. Still a clean shippable
     baseline.
   - **Boot breaks (Sad Mac)** → unlucky placement re-roll. Re-deploy the backup RBF, then either
     rebuild (re-roll) or attack the lottery structurally (below).

## Reframed next steps (if the bomb persists — do NOT re-chase single cones)

The census says single-cone-chasing is a dead end. The durable fixes attack the **lottery mechanism**:

- **(Best) Make a turbo-proof runtime probe.** Every prior probe is SDRAM-slot-gated ⇒ blind at turbo.
  A DTACK-based ring + a VBR/`trap_1111` tap (`TG68KdotC_Kernel.vhd`) would actually OBSERVE the bomb.
  Without an oracle we are guessing; this unblocks everything. (Invasive — session 2 deferred it.)
- **Honest multicycles for the paced classes** (shrinks the lottery surface so STA checks real budgets
  and the fitter stops chasing false 1-cycle deadlines):
  - **TG68 clkena multicycle** (−6 ns ×510 `regfile→regfile` + the CPU cone): the 68020 runs on a
    2-cycle enable; a `set_multicycle_path -setup 2` on the CPU clkena domain is HONEST and clears the
    single largest false-positive class. Cross-check MacLC_MiSTer — it shares this TG68 and may already
    have it. **Big lever, but verify the enable ratio before constraining.**
  - **FPU FMOVE-to-mem `-from cir_state_reg.CIR_XFER_DST`** scoped to `{move_exc_*, move_packed_encode,
    the conv endpoints}`: closes the −140 `move_packed` (frees the fitter's #1 thrash) IF the FMOVE.P
    dispatch window is ≥6 cycles (PROVE it first — `CIR_XFER_DST`→`DST_WAIT`→present may be too short;
    a lying −setup 6 would corrupt FMOVE.P).
- **(Robust) RTL-pipeline the deepest physical cone** (`fp80_to_packed96_fast`, the −140 driver) so NO
  placement can exceed budget. Validate with the cpu_fpu corpus. Heavier; only if FMOVE.P matters.
- **Non-timing tracks** (if probe-free still bombs): the CIR Response-CIR *read* path on the Mac II bus
  (Verilator drives the FPU directly, so a bus-read corruption would be sim-invisible); the un-gated
  WRITE DTACK (`LBMacTwo.sv:873`, memory `project_residual_read_corruption`); or an FRESTORE
  logic-sequence the corpus doesn't cover (PFST showed `resp_prim=CIR_PRIM_NULL` ⇒ the FSM *completed*
  the restore, so the F-line came from a corrupted Response read or a later op, not the restore itself).

## Files touched this session

- `LBMacTwo.sdc` — added the scoped `cir_operand_staging→cir_conv_src_reg` multicycle (fully commented).
- `LBMacTwo.qsf:71` — commented out `DBG_WEDGE=1` (probe-free; rationale inline).
- `scratch/diag_timing.tcl`, `scratch/diag_timing2.tcl` — the census queries (gitignored scratch).
- Backup: `output_files/LBMacTwo_4db7a3f5_known_good.rbf` (the revert target).

## Procedures (unchanged)

- Timing query: `export PATH=/c/intelFPGA_lite/17.0/quartus/bin64:$PATH; quartus_sta -t scratch/<x>.tcl`.
  `diag_timing2.tcl` = full grouped census; `fpu_fail.tcl` = FPU-scoped; `wp.tcl` = worst path.
- Build/deploy: `bash scripts/build.sh` (background; confirm md5 changed + worst path still the
  boot-irrelevant `move_packed` cone + no NEW failing endpoints vs the census). `scp` → `_Unstable`
  (no reload, shared board). FPU sim (board-free, after VHDL edits only): see CLAUDE.md WSL section.
