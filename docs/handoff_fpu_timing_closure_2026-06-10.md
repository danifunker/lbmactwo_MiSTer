# Handoff — FPU timing closure (multicycle constraints) + vec-11 corpus triage

*2026-06-10, branch `fpu-bus-adapter-dani` @ `31ebcf5`. Written after the
SDRAM read-path fix (`fefc429`) resolved the corruption/runaway saga — see
`docs/handoff_tg68_runaway_2026-06-10.md` (resolution banner) and memory
`project_tg68_runaway_unification`.*

## TL;DR

The mc68881 FPU datapath has **never met timing** and has **no multicycle
constraints**: worst-case setup slack is **-175.4 ns** (data delay ~206 ns
against the 31.9 ns clk_sys period), restricted Fmax 4.87 MHz, every worst
path inside `mc68881_top` (`fp80_to_int_trunc → result_ex_reg`). The design
only works because the FPU FSM happens to leave many cycles before sampling
results — an implicit multicycle the fitter knows nothing about. Every
rebuild therefore re-rolls FPU routing margins: a **build-to-build lottery**
for marginal FPU ops, which is the prime suspect for the corpus's residual
**165× vec-11 (F-line) failures** (FSQRT / FSAVE-(A0) / FDBcc class) and for
historical "same RTL, different behavior" confusion. Fix = constrain (or
pipeline) the FPU datapath so timing closes deterministically.

## Evidence

1. **This build (`af34c4c4`)**: `output_files/LBMacTwo.sta.rpt` —
   "Critical Warning (332148): Timing requirements not met"; setup summary
   shows clk_sys (`emu|pll…general[1]` = 31.3344 MHz; `rtl/pll.v` comments
   name the outputs) at slack **-175.395, TNS -76404**. Fmax panel:
   restricted Fmax **4.87 MHz** for that domain.
2. **Identical numbers in May-era preserved reports**:
   `output_files_fpu-cir-fixes/all_violated.txt` top paths are the same
   `fp80_to_int_trunc~50 → result_ex_reg[*]` at **-175.285**, data delay
   205.754 ns. So this is a standing condition across months of builds.
3. **Same-bitstream state dependence (separate but related clue)**: on RBF
   `af34c4c4`, a **cold core load** ran the full corpus to
   `passed=1057/1320` with 165 vec-11s (FSQRT block trapping en masse); a
   **warm restart** re-run on the same bitstream was at `run=292 ok=287
   trap=5` through the same FSQRT region (~98% pass). So the vec-11 class
   has BOTH a routing-lottery axis (across builds) and a state axis (cold
   vs warm on one build). Disentangle them with the protocol below.
4. Corpus ground truth: 1320 per-test JSONL records (name/vec/pass) extract
   cleanly from the bench disk — `dd if=/media/fat/games/LBMacTwo/cpufpubench.hda
   bs=512 skip=992 count=800` (results at partition offset 0x70000; HFS
   partition starts at block 96). Fail distribution on the cold run:
   165× vec=11, 34× vec=4, 64× vec=0-wrong-result.

## The work

### Phase 1 — constrain (low risk, high value)

1. Read the FPU FSM timing in `rtl/mc68881/vhdl/*.vhd`: how many clk_sys
   cycles elapse between operand/command issue and the first sample of
   `result_ex_reg` (and the other violated endpoints — get the full list
   from the STA report, `report_timing`-style; `all_violated.txt` shows the
   shape). **Diff against `../68881-fpga/` first** (authoritative upstream —
   memory `reference_upstream_68881_fpga`) — if upstream has pipelining or
   constraints we dropped, port theirs.
2. Add `set_multicycle_path` constraints matching (conservatively
   under-shooting) the FSM's actual allowance, e.g.
   `set_multicycle_path -setup N -from … mc68881 datapath regs … -to …`
   with the matching `-hold N-1`. There is currently NO core-level SDC —
   only the framework `sys/sys_top.sdc` (which shows the pattern, e.g. the
   osd_vcnt multicycle). Either extend that file (it's framework-shared —
   prefer not) or add a core SDC and reference it from `LBMacTwo.qsf`
   (`set_global_assignment -name SDC_FILE …`). NOTE Quartus rewrites the
   qsf at compile start — edit between builds only.
3. Goal: `Timing requirements not met` GONE for the clk_sys domain (or
   reduced to known-benign cross-domain paths), so STA becomes a meaningful
   sign-off and the fitter stops wasting effort on fake 1-cycle FPU paths.

### Phase 2 — validate determinism

Per build: cold-load corpus run + warm-restart corpus run (the bench
auto-reboots into the corpus while `cpufpubench.hda` is the mounted SCSI
disk; deploy loop = `scratch/cir_bisect/deploy_and_run.sh`, results via the
dd above, tally script shape in the session transcript /
`scratch/cir_bisect/`). Do this for 2–3 rebuilds (touch a comment to force
re-fit). Success = the vec-11 set is IDENTICAL across builds (lottery
gone). Whatever residue remains cold-vs-warm is the **state axis**:

### Phase 3 — the cold-vs-warm state axis

Candidates to probe once builds are deterministic: FPU power-on state vs
post-restart state (FPCR/FPSR/FPIAR, internal FSM), RAM-content effects,
PLL/clock settle, or bench-side ordering (the corpus FPU-reset preamble
`CLR.L -(A7); FRESTORE (A7)+; FNOP` resets per-test, so suspicion falls on
deeper machine state). A cheap first experiment: cold-load, let the corpus
trap through FSQRT, then warm-restart WITHOUT redeploying and compare the
exact per-test vec sets from the two journals (rename/save the .hda between
runs — each run overwrites /Results.jsonl).

### Overlapping known item

The TG68-side FDBcc/FTRAPcc combinational-condition bug (memory
`project_fpu_corpus_fixes`, §2 of `docs/cpu_fpu_fdbcc_analysis_2026-06-05.md`)
is a separate, real kernel issue inside the same vec-11 class — mirror
FBcc's registered `cp_cond_true` path. Also still unported to this branch:
`3c68a27` (`cp_read_resp_wait`, on `fpu-cir-fixes`) — proven-correct
response-decode hygiene; port it during this work.

## Don'ts / gotchas

- Don't "fix" oracle test #074 (FDBULE) — real 68881 dialog timing
  (memory `project_fpu_corpus_fixes`).
- Don't trust the Verilator unit bench for HW-timing questions (ideal
  timing; and GHDL version drift produces ~70 spurious FSQRT/FCMP fails —
  memory + CLAUDE.md).
- Hardware build ~35–65 min; always `rm -rf db incremental_db` first;
  verify md5 changed; don't run `read_probes.sh` during a compile.
- The bench .hda (md5 `33b6fc9c`, stray-trap-fixed) ejects only on FLOPPY
  boots by design (`eject.c` is .Sony-only, gated to drives 1/2) — on SCSI
  boots the disk stays mounted and MiSTer re-mounts it per its per-core
  persistence; mount a different image over the OSD slot to switch.
- Current JTAG probe set (20 instances incl. PRNG/PRWF/PIFD rings tied to
  bench payload addresses of hda `33b6fc9c`) is bench-specific
  instrumentation — fine to strip for timing work; freeing them also eases
  fit pressure.
