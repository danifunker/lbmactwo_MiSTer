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
3. **Cold vs warm runs are nearly identical** (correcting an earlier
   in-session over-read from a progress screenshot): a per-test diff of a
   cold-core-load run vs a warm-restart run on the SAME bitstream
   (`af34c4c4`) shows **257 fails common to both** (254 with identical
   vectors), **6 cold-only** (all `FMOVE.X` register-chain tests,
   #994–#1033), **0 warm-only**. So the fail set is ~98% deterministic on
   one placement; the lottery/state question applies mainly to the small
   FMOVE.X class and to ACROSS-build variation (untested — the protocol
   below measures it).
4. Corpus ground truth: 1320 per-test JSONL records (name/vec/pass) extract
   cleanly from the bench disk — `dd if=/media/fat/games/LBMacTwo/cpufpubench.hda
   bs=512 skip=992 count=800` (results at partition offset 0x70000; HFS
   partition starts at block 96). Both runs' raw journals are committed:
   `docs/bench_results/2026-06-10_af34c4c4_{cold,warm}.jsonl.gz`.

## Failure analysis (cold run, RBF af34c4c4, bench hda 33b6fc9c)

`passed=1057 of 1320` → 263 fails (257 deterministic). By family:

| Family (test idx range) | n | vectors | signature | reading |
|---|---|---|---|---|
| FDIV (#328–#631) | 80 | all vec=11 | `exp=N act=0`, F-line | **Slow-op Response-CIR misdecode.** FDIV/FSQRT are the FPU's long-latency ops: the kernel polls Response through many NULL-BUSY cycles, and `cp_idle_resp` decodes the combinational `data_in` — the exact bug `3c68a27` (`cp_read_resp_wait`, on `fpu-cir-fixes`, unported here) fixes. Fast ops (FADD/FSUB/FMUL: ZERO fails) answer on the first read and never enter the window. **Port `3c68a27` first — it plausibly clears all 160 FDIV/FSQRT fails (62% of total).** |
| FSQRT.X (#288–#327) | 40 | all vec=11 | same | same as FDIV |
| FSQRT+FINTRZ (#632–#671) | 40 | all vec=11 | same | same as FDIV |
| FCMP+FDBcc (#1098–#1174) | 43 | 42× vec=0, 1× vec=11 | `exp=99 act=42` | **The documented FDBcc kernel bug** (docs/cpu_fpu_fdbcc_analysis_2026-06-05.md §2; memory `project_fpu_corpus_fixes`): combinational condition apply — mirror FBcc's registered `cp_cond_true`. The act=42 signature matches exactly. |
| FCMP+FBcc (#834–#991) | 37 | 34× vec=4 (!), 3× vec=0 | `exp=1 act=0`, ILLEGAL instruction | **New, well-localized item**: FBcc dialogs taking vector 4 (illegal) — kernel cpBcc decode path rejects something (condition predicate? displacement word handling?). Examples: FBNE, FBLT, FBNLE. Investigate `cp_cond_eval`/cpBcc dispatch. |
| FMOVEM.X push/pop (#1304–#1319) | 16 | vec=0 | `act=18` constant | The known pre-existing FMOVEM class (unit bench had 218): `FMOVEM.X FP0,-(A7); (A7)+,FP1` doesn't round-trip — FP1 keeps a stale value. |
| FMOVE.X chains (#994–#1033) | 6 | mixed 11/0, **non-deterministic** | one `act=65491` (=0xFFD3, a truncation artifact) | The only run-to-run variable class — prime candidate for the timing-lottery/multicycle work in this handoff. |
| FSAVE/FRESTORE (A0) (#6) | 1 | vec=11 | clobber-reload test | FSAVE with (A0) addressing mode — single known test. |

**Recommended order of attack:** (1) port `3c68a27` → re-run corpus
(expect ~160 fails to clear); (2) FDBcc registered-condition fix (43);
(3) FBcc vec-4 illegal investigation (37); (4) FMOVEM.X round-trip (16);
(5) multicycle constraints (this doc's main subject) for determinism +
the FMOVE.X class. Items 1+2 alone would take the corpus to ~96%.

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

### Phase 3 — the residual non-deterministic class

(Scoped down by the cold/warm diff in "Failure analysis" above: only the
6 `FMOVE.X` chain tests vary run-to-run on one bitstream; everything else
is deterministic.) Once multicycle constraints are in and builds are
deterministic, re-measure this class across cold/warm runs and across
rebuilds — if it stabilizes, the constraints fixed it; if it still
flickers on one placement, look at the FMOVE.X register-chain datapath
specifically (its `act=0xFFD3` artifact suggests a truncation/latch-window
issue in fp80 register-to-register transfers).

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
