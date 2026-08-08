# Handoff: FPU conversion-datapath pipeline beat (the remaining boot/runtime killer)

**Date:** written 2026-06-12 late evening · **Branch:** `7-1-2-boot-working` @ 0cc933d
**Predecessor:** `docs/handoff_scsi_bootfail_pram_2026-06-12.md` (morning state; superseded)

## The day in three findings (all proven, all recorded in memory)

1. **Board power was sick.** The 5V supply (4A brick with inline switch +
   5ft cable) brownied out the MiSTer Pi: the dbg_coldinit instrument caught
   **PLL unlocks = 15 (saturated)** mid-session, with garbled audio and
   textless dialogs. Replaced with an official Pi-5 USB-C supply →
   **unlocks = 0 across all subsequent reads**. The phantom-keystroke /
   dead-sshd / same-bitstream-different-day mysteries all trace here.
   Disks were NEVER corrupted (byte-verified ~6 times across the saga).
2. **The FPU timing lottery is closed.** `LBMacTwo.sdc` (commits dbb16b4 +
   6bbf4f9) multicycles the genuinely-slow FPU conversion cones from
   stable launchers only: worst setup slack **−173.4 → −1.6 ns**.
   Hard-won scope lessons are inline in the SDC comments — read them
   before touching it (c8e8c9ad died of over-relaxation: never relax
   handshake bits like result_ready_reg/exc_event_valid_reg, never blanket
   -from u_fpu|*, operator-loci names are rebuild-fragile).
3. **A real FPU datapath fault remains on clean power.** With power
   verified clean and ROM checksum-verified intact, System 7 still throws
   `"Finder" bad F-Line instruction` while browsing, and the FPU corpus
   bench **hard-crashes by ~test 5** (after multiple reboot attempts).

## Why the FMOVE conversion path is the prime suspect

- The SDC's two deliberately-unconstrained residual cones ARE this path:
  `cir_operand_staging → operand_reg` (−1.35) and
  `operand_reg → fp_reg_file_reg` (−1.56) — the fp80_from_single/double
  conversion at operand-transfer completion and the cir_move deferred
  copy. Both are genuine NEXT-EDGE captures (bus_frame_proc converts one
  edge after the last staging write; "CIR FMOVE deferred copy" commits one
  edge after operand_reg is written) — no honest multicycle exists.
  −1.6 ns at the slow corner can fail on real silicon.
- Even where multicycles ARE honest for CPU-paced dialogs, the corpus (and
  Finder SANE bursts) exercise **back-to-back/pipelined dialogs**
  (pending_launch / 68882-overlap paths) that compress the settle gaps the
  constraints assume. Constraint cleverness has hit its limit.
- Bench history: every recent build wedges the bench early with stray
  F-line in the inter-test FRESTORE preamble (66ba190f, a164163f, now
  9d7db2c6) EXCEPT one lucky placement (af34c4c4) that ran all 1320
  (passed 1057). The phenomenon predates the SDC — it is the same
  marginal datapath, rolled differently per build.

## The plan (sim-first — do NOT start with hardware builds)

1. **Baseline in Verilator** (CLAUDE.md has the exact WSL commands):
   regenerate the FPU .v (`rtl/mc68881/convert_to_verilog.sh`, OSS-CAD
   ghdl), `make` the SingleStepTests cpu_fpu bench, run
   `cpu_fpu_full_corpus.json` → record pass count + fail families.
   (Known: GHDL-version synth artifacts cause ~70 spurious FSQRT/FCMP+FDB/
   FSAVE fails in Verilator — compare families, not absolutes; hardware is
   the oracle for those. memory: project-fpu-corpus-fixes.)
2. **Add the pipeline beat** in `rtl/mc68881/vhdl/mc68881_top.vhd`
   `bus_frame_proc`: register the staging→operand conversion
   (fp80_from_single/double/packed) output one cycle earlier, and give the
   cir_move deferred copy its own registered stage — i.e., make every
   conversion cone segment ≤ 1 period BY CONSTRUCTION. The CIR dialog has
   µs of CPU-paced slack per transfer; one extra cycle is invisible to the
   protocol. **Diff against `../68881-fpga/` first** (authoritative
   upstream, memory: reference-upstream-68881-fpga) — if upstream already
   pipelines this, port theirs.
3. Re-run sim corpus → must be ≥ baseline with no new fail families.
4. Build (SDC may then SIMPLIFY: the operand_hi16/operand_reg/-setup 2
   rules and the residual-cone comment can go once the cones are
   pipelined; keep the big trunc-cone -setup 7 unless that's pipelined
   too). Verify STA fully clean = first ever.
5. HW: corpus bench run (mount cpufpubench.hda on SC0, boot, journals at
   `dd if=... bs=512 skip=992 count=800`, parser scripts/extract_results.py
   / scratch/cir_bisect/). Expect: full 1320 completion, deterministic
   across rebuilds. Then 7.1 browsing soak (the F-line repro).
6. Remaining known kernel items AFTER the datapath is sound (they're
   pre-existing, root-caused, documented): FDBcc registered-condition fix
   (~43 fails), FBcc vec-4 illegal (~37) — see
   docs/handoff_fpu_timing_closure_2026-06-10.md table.

## Practical state

- **Deployed RBF:** `LBMacTwo.rbf` = 9d7db2c6 (0cc933d: SDC + dbg_coldinit
  instrument). Fixtures on SD `_Unstable/`: `LBMacTwo_a9d6_sdc.rbf`,
  `LBMacTwo_Unstable_20260611_af3682.rbf` (=66ba190f),
  `LBMacTwo_bad_c8e8.rbf` (over-relaxed SDC reference).
- **Instrument:** every boot self-reports via JTAG ISSP —
  `quartus_stp_tcl -t scripts/read_coldinit.tcl` (one-shot, zero HPS
  load). Healthy baseline: sum 0x013FFEF5/131072 words, unlocks 0, s0
  mount ~250ms, rom ~775ms, clear ~1040ms, release 2999ms (3s imageless
  backstop).
- **Configs:** `.s0` restored to `games/LBMacTwo/MacLC_7-1.hda`. `.s1` is
  byte-corrupted (silently never mounts — fix by re-mounting via OSD
  someday). `.s2` (PRAM) deliberately absent.
- **Bench disk:** cpufpubench.hda md5 now 0d98dd12 (journals written by
  runs; expected baseline was 33b6fc9c). Pristine copies on SD:
  `_save_cpufpubench_a21bcdd1.hda`, `cpufpubench_baseline.hda`.
- **Two-agent rule:** the MiSTer is shared with the MacLC sessions — see
  memory feedback-shared-mister-protocol + the advisory dropped in
  `../MacLC_MiSTer/docs/advisory_shared_mister_hps_2026-06-12.md`.
- Smaller open items: PRAM load-back roundtrip test (task #4), parked
  post-shutdown disk diff (#7), MacsBug FPU-context work resumes after the
  datapath is sound (memory: macsbug-fpu-context).
