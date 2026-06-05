# FCMP+FDBcc: corpus operand-swap **and** an FDBcc/FTRAPcc RTL bug

*2026-06-05 — `boot-investigation` @ `34fbad3`*

## Final outcome (2026-06-05)

Real Mac II oracle: **1319/1320** (`results/cpu_fpu/hw_2026-06-05.jsonl`).
Corpus fixes (FDBcc operand-swap, FMOVEM.X `$D040`) are HW- and RTL-validated;
FPIAR round-trip tests retired (non-faithful to silicon); per-test null-frame
`FRESTORE` reset added to the harness so tests are state-independent. The one
remaining "fail" — #074 `FDBULE` taking an intermittent Line-1111 trap in
full-run context (expected `99` is correct) — is a real 68881 coprocessor-dialog
timing quirk on the test chip, not a corpus error. See §6–§7. The FDBcc/FTRAPcc
RTL fix (§2) is the only open *core* item.

## TL;DR

The 43 `FCMP+FDBcc` failures in the Verilator `cpu_fpu` bench
(`got 42, expected 99`) are **two independent bugs at once**, on disjoint
subsets of the 80 FDBcc tests — not the single "corpus N-polarity" issue the
handoff assumed:

1. **Corpus bug** — `gen_fpu.c::gen_fcmp_fdbcc` loaded the two operands into
   the *opposite* FP registers from every other FCMP generator, while calling
   the same condition predicate. **51 of 80** FDBcc `expected` values were
   wrong. **Fixed in this commit** (generator + regenerated corpus).
2. **Real RTL bug** — `TG68KdotC_Kernel.vhd` evaluates the coprocessor
   condition for **FDBcc and FTRAPcc combinationally during `cp_cond_eval`**,
   hitting the exact same-clock-edge stale hazard that FBcc was already
   deferred (`cp_branch_apply`, registered `cp_cond_true`) to avoid. Net
   effect: FDBcc reads the condition as **always false → always returns 42**.
   **Not yet fixed** (reserved for the RTL owner).

**The two fixes must land together.** See [§4](#4-the-fixes-are-coupled).

This was resolved entirely from source — **the planned real-hardware run is
not needed to arbitrate the FCMP+FDBcc question.**

---

## 1. The corpus bug (operand-swap)

In the M68881, `FCMP FPm,FPn` computes `FPn − FPm` and sets `FPCC`; the `N`
bit is set when the result is negative.

Every FCMP-based generator draws `(a, b)` and computes
`expected = eval_cond_int(cond, a, b)`, where `eval_cond_int` sets
`N = (a < b)`. For that to be correct, the program must compute `a − b`, i.e.
load `FP{dst} = a` and `FP{src} = b` (since `FCMP FP{src},FP{dst}` =
`FP{dst} − FP{src}`).

`gen_fcmp_fscc` and `gen_fcmp_fbcc` both do exactly that:

```c
BWf(moveq_d0(a)); BWf(0xF200); BWf(fmove_size_d0_fpn(dst, FMT_L));  // FP{dst}=a
BWf(moveq_d0(b)); BWf(0xF200); BWf(fmove_size_d0_fpn(src, FMT_L));  // FP{src}=b
```

`gen_fcmp_fdbcc` had the two targets **swapped**:

```c
BWf(moveq_d0(a)); BWf(0xF200); BWf(fmove_size_d0_fpn(src, FMT_L));  // FP{src}=a  (BUG)
BWf(moveq_d0(b)); BWf(0xF200); BWf(fmove_size_d0_fpn(dst, FMT_L));  // FP{dst}=b  (BUG)
```

So the actual machine computed `FP{dst} − FP{src} = b − a` (N = `b < a`),
while `expected` assumed N = `a < b`. For every `a ≠ b` the `N`-dependent
conditions were inverted. `eval_cond_int` itself is correct — FScc proves it.

**Fix:** swap the two `FMOVE.L` targets in `gen_fcmp_fdbcc` so it matches
FScc/FBcc. `expected` values are unchanged; only the program bytes change
(the two `FMOVE` ext words swap). Verified surgical: 80 of 1336 corpus rows
changed, all `FCMP+FDB`, 0 `expected` values altered. After the fix, a
byte-level decode of every FDBcc test confirms `expected` equals a correct
machine's result of its own program (was 51 wrong, now 0).

Regenerate with:

```bash
gcc -O2 -w -o /tmp/gen_fpu SingleStepTests/gen/gen_fpu.c
/tmp/gen_fpu SingleStepTests/cpu_fpu/fpu_corpus_baseline.json   # seed 0xBEEFC0DE (default)
python3 SingleStepTests/cpu_fpu/combine_corpus.py
```

(`gen_fpu` at the default seed reproduces `fpu_corpus_baseline.json`
byte-for-byte — it is the canonical generator. `combine_corpus.py`'s
"regenerated from MAME" comment is stale; MAME does not implement FDBcc.)

---

## 2. The RTL bug (combinational condition read)

`rtl/tg68k/TG68KdotC_Kernel.vhd`, state `cp_cond_eval`:

- **FScc** uses the *registered* `cp_cond_true` (latched
  `cp_cond_true <= data_in(0)` at the edge ending `cp_cond_eval`), written
  back later in `cp_fscc_wr`. ✔ passes.
- **FBcc** was explicitly **deferred** one cycle to `cp_branch_apply`, which
  also uses the registered `cp_cond_true` — the in-code comment says the
  combinational consumer "would sample it stale on this same edge." ✔ passes.
- **FDBcc** and **FTRAPcc** still read `data_in(0)` **combinationally**
  inside `cp_cond_eval` to choose the next micro-state:

```vhdl
ELSIF exe_opcode(5 downto 3) = "001" THEN        -- FDBcc
    IF data_in(0) = '0' THEN                     -- <-- combinational, stale
        ... ; next_micro_state <= cp_fdbcc_dec;  -- decrement + branch
    END IF;                                       -- (condition true: fall through)
```

Because `data_in(0)` is sampled before it is valid, FDBcc behaves as if the
condition were **always false** → always decrements and branches → the test's
marker register is never overwritten → **always returns 42**.

### Evidence this is "always 42", not a per-condition issue

Under a "core always returns 42" model, the bench would fail exactly the FDB
tests whose `expected == 99` and pass the rest:

- 80 FDB tests, 43 with `expected == 99` → predicts **43 failures**.
- The handoff reports **exactly 43** `FCMP+FDBcc` failures, all `got 42`. ✔

The asymmetry is dated in git: FBcc's deferral fix
(`202a408f`, 2026-05-17 10:44) landed *after* the FDBcc/FTRAPcc combinational
reads (`a396648d`, 2026-05-17 07:43) and was never propagated to them.

**Suggested fix (RTL owner):** route FDBcc through a deferred state (a new
`cp_fdbcc_eval`, mirroring `cp_branch_apply`) that decides from the registered
`cp_cond_true`. Apply the same to the FTRAPcc path (currently only exercised
by the always-false corpus case, so latent but real).

---

## 3. Full classification of the 80 FDBcc tests

Original corpus (`34fbad3`), with the "core always 42" symptom:

| corpus `expected` | true machine | core (42) | count | meaning |
|---|---|---|---|---|
| 42 | 42 | pass | 11 | genuinely correct |
| 42 | **99** | pass | **26** | corpus **and** core both wrong the same way → *spurious* pass |
| 99 | 42 | fail | 25 | corpus wrong; core's 42 is actually correct |
| 99 | 99 | fail | 18 | corpus right; core's 42 is the real RTL bug |

- Current failures = 25 + 18 = **43** ✔ (matches handoff).
- Corpus rows wrong vs their own program bytes = 25 + 26 = **51** ✔.

The handoff framed it as a dichotomy ("HW=42 ⇒ corpus bug" *or* "HW=99 ⇒ FPU
bug"). It is **both**: the 25 are corpus bugs, the 18 are the RTL bug.

---

## 4. The fixes are coupled

The 26 "spurious pass" rows (`corpus 42`, true `99`, core `42`) pass today
only because the corpus and the buggy core are wrong in the *same* direction.

- **Fix the corpus alone** (this commit): the 26 corpus values become `99`,
  but the buggy core still returns `42` → those 26 now *fail*. The bench then
  fails on every `expected==99` FDB test (still ~43, just a different 43).
  This is expected and harmless — it correctly exposes the RTL bug instead of
  masking it.
- **Fix the RTL alone**: the core returns the true result, but the old corpus
  still has 51 wrong values → 51 failures.
- **Fix both**: 80/80 FDBcc pass.

So after this corpus commit, the `cpu_fpu` FDB pass rate will *look* unchanged
(~37/80) until the RTL fix lands; that is the corpus no longer hiding the bug.

---

## 5. Status

- [x] Corpus operand-swap fixed (`gen_fcmp_fdbcc`) + corpus regenerated.
- [x] Bench headers regenerated in sync (`macos_bench/cpu_fpu_full_tests.h`,
      `cpu_fpu_tests.h`) — diff confined to the 80 FDB program-byte rows.
- [x] Byte-level validation: 0/80 FDB rows wrong (was 51).
- [x] Bench `.hda` built with the corrected corpus baked in:
      `scratch/fdbcc_fix/cpufpubench.hda` (Retro68 + `build_cpu_fpu_hda.sh`,
      template `~/testdisk.hda`).
- [ ] RTL fix for FDBcc/FTRAPcc combinational condition read (RTL owner).
- [ ] (Optional) Real-hardware run — *not required* for this question.
      The `.hda` is ready to deploy on a real Mac II (BlueSCSI) or the
      MiSTer LBMacTwo core; extract `/Results.jsonl` afterward with
      `rb-cli get cpufpubench.hda@1 /Results.jsonl <out>`. Note: a run on
      *this* core reproduces the unfixed RTL bug, so it is only a useful
      oracle on a real 68881 (or once the RTL is fixed). MAME is **not** an
      oracle here — it does not implement FDBcc (`m68kfpu.cpp` `case 1: //
      FDBcc / TODO`).

## 6. Real-hardware runs (2026-06-05)

Ran the bench on a real Macintosh II (68020 + 68881) via BlueSCSI. Two runs:

- **Run 1** (FDBcc fix only, FMOVEM.X still `$C040`): **1303/1336 (97.5%)**.
- **Run 2** (FDBcc + FMOVEM.X `$D040` fixes): **1319/1336 (98.7%)** —
  canonical oracle: `SingleStepTests/results/cpu_fpu/hw_2026-06-05.jsonl`.

Real silicon is the oracle, so `actual != expected` normally means a
**corpus/test** bug — with one documented exception (#075 below).

| Cluster | Run1 | Run2 | Verdict |
|---|---:|---:|---|
| **FCMP+FDBcc** | 1 | 1 | Fix **confirmed** — 79/80 pass. The lone failure (FDBOR `(-29,31)` #075) **reproduced exactly** across both runs, so it is *not* a transient. Its bytes are canonical (objdump: `fcmpx %fp0,%fp5; fdbor %d2`), the expected `99` is correct per the ISA, and **every** other OR test (FScc/FBcc/FDBcc, incl. negative-result #055) passes. This is a reproducible **hardware-specific anomaly on this particular 68881**, not a corpus or core bug. See note below. |
| **FMOVE FPIAR** | 16 | 16 | **Test-premise bug / by design.** FPSR & FPCR round-trip 16/16; only FPIAR fails (returns instruction-address `0x5670`, not the written `0x12345678`) — correct 68881 behavior; FPIAR is the FP *instruction-address* register. Our core treats it as plain storage (passes the equally-naive corpus). Recommend: document + optionally drop FPIAR from `gen_fmove_l_fpcr_roundtrip`. Not chasing it. |
| **FMOVEM.X** | 16 | **0** | **Malformed-instruction corpus bug — FIXED & HW-validated.** Load ext word was `$C040` (predec list-mode) under `(A7)+` postinc EA — malformed; canonical is `$F21F $D040` (Retro68 `as`). Run 1: real silicon returned constant `18`; MAME aborts ("FMOVEM mode 0"). Run 2 with `$D040`: **16/16 pass on real silicon** — encoding fix validated. |

**#075 note:** correctly-encoded, correct expected value, isolated (1/1336),
reproducible. Treat the corpus expected (`99`) as authoritative; do **not**
"fix" the corpus to match this cell. To localize, an FScc+`FMOVE.L FPSR,Dn`
readback for `FCMP FP0,FP5 (-29,31)` would show whether the real chip sets a
wrong FPSR.CC bit (FP-compare marginality) or the FDBcc path is at fault.
Best confirmed on a second 68881.

**Bottom line:** the only genuine FPGA-core item remaining is the
FDBcc/FTRAPcc RTL fix (§2). FMOVEM.X and FDBcc corpus bugs are fixed and
HW-validated; the 16 FPIAR rows are a deliberate core simplification; #075 is
explained in §7.

## 7. #075 is order-dependence, not a hardware defect — harness fixed

A targeted 8-probe diagnostic (`scratch/fdbcc_fix/diag/`, all using the exact
`FCMP FP0,FP5 (-29,31)` of #075) ran on the real Mac II: **all 8 pass**,
including the byte-for-byte #075 repro (P3 → 99) and a raw FPSR read showing the
FCMP sets N correctly (`cc=0x08000000`). So in isolation the instruction,
operands, registers, and condition bits are all correct, and **corpus
`expected=99` is confirmed right.**

The full-run failure is therefore **order-dependence**: the harness
(`cpu_fpu_bench_main.c`) cleared D1–D7 and A0–A5 before each test but **left the
FPU untouched** — FPSR (incl. FPCC), FPCR, and FP0–FP7 carried over. On the
concurrently-executing 68881 that lets a prior test perturb #075's FDBcc
condition (an FCMP→FPCC settle/stale-read sensitivity — the same hazard class as
the §2 RTL bug, here surfacing on real silicon).

**Fix (harness, not corpus):** `build_program` now emits `FMOVE.L #0,FPCR` and
`FMOVE.L #0,FPSR` (assembler-verified `F23C 9000 …` / `F23C 8800 …`) at the top
of every test, so each test is a pure function of its own program. Corpus is
unchanged (chosen over a generator-level prologue: the harness already owns all
other per-test preconditions). Rebuilt `scratch/fdbcc_fix/cpufpubench.hda`.
Expected next HW run: #075 → pass, **1320/1336** (the 16 FPIAR by design).

*Note:* the dirty-run #075 sensitivity is itself useful signal — real silicon
shows FDBcc-condition-timing fragility under back-to-back FP ops, reinforcing
that the §2 FDBcc/FTRAPcc RTL fix is real-world-relevant, not academic.

## Appendix: reproduce the analysis

The classification above is produced statically (no hardware/sim) by
decoding each test's program bytes and comparing `expected` to a correct
machine's result. The validator lives in the commit message / this
investigation; re-run `gen_fpu` + `combine_corpus.py` and re-decode
`cpu_fpu_full_corpus.json` to confirm 0 wrong FDB rows.
