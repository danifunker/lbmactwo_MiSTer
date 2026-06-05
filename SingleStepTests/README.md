# SingleStepTests benches

Per-instruction verification benches for the computational cores in
this repo, modeled on the
[iigs_simulation/SingleStepTests](https://github.com/SingleStepTests/65816)
pattern.

## Layout

| Dir | What it tests | Status |
|---|---|---|
| `tg68k/` | Raw `TG68KdotC_Kernel` (68020 mode) via per-cycle bus driver | 711/718 against MAME oracle |
| `cpu_fpu/` | Integrated `tg68k` + `mc68881_top` end-to-end via JSONL corpus | HW: 1319/1320 on a real Mac II (see below); Verilator number predates the 2026-06-05 corpus fixes |
| `fpu/` | Standalone `mc68881_top` (verilog `fpu_lite` build) via coprocessor CIR | scaffold; smoke only |
| `gen/` | Test corpus generators (Musashi + MAME) + Mac OS hardware bench + diff tool | 696-test CPU corpus, 1328-test FPU corpus |
| `results/` | Committed JSON / markdown snapshots for tracking accuracy over time | |

## Quick start: run the simulator benches

Each verilator bench is a self-contained build. From the bench's
directory:

```
make
./obj_dir/V<bench> <corpus.json>
```

### CPU bench (`tg68k/`)

696 user-mode + 22 privileged instruction tests captured from MAME's
`maciihmu` driver as the oracle. The corpus is vendored in
`results/cpu/mame_baseline_2026-05-16.json`.

```
cd SingleStepTests/tg68k
make
./obj_dir/Vtg68k_tests ../results/cpu/mame_baseline_2026-05-16.json
```

Expected: **711 passed, 7 failed, 0 skipped**. The 7 failures are
documented TG68K bugs — see [test-blockers.md](test-blockers.md). The
verilator bench runs in supervisor mode so privileged tests work; the
only tests it skips are those flagged `hw_unsafe` (none yet exist).

### Integrated CPU + FPU bench (`cpu_fpu/`)

The FPU corpus is a different schema (`program`/`result_reg`/`expected`)
rather than the CPU schema. Snapshot of the baseline corpus lives in
`cpu_fpu/fpu_corpus_baseline.json`; you can also regenerate live with
`make -C ../gen gen_fpu && ../gen/gen_fpu /tmp/fpu_corpus.json`.

```
cd SingleStepTests/cpu_fpu
make
./obj_dir/Vcpu_fpu_tests fpu_corpus_baseline.json   # math baseline only
./obj_dir/Vcpu_fpu_tests cpu_fpu_full_corpus.json   # FSAVE/FRESTORE FIRST, then baseline
```

`cpu_fpu_full_corpus.json` is the **front-loaded full corpus**: the 8
FSAVE/FRESTORE tests run as rows 1–8, then the 1328 math tests. Rebuild
it (and the supervisor bench's `cpu_fpu_full_tests.h`) after regenerating
the baseline:

```
python3 combine_corpus.py                                  # -> cpu_fpu_full_corpus.json
python3 ../macos_bench/gen_cpu_fpu_header.py \
    cpu_fpu_full_corpus.json ../macos_bench/cpu_fpu_full_tests.h
```

Front-loading matters: the full run aborts ~test 1248 under MAME (an
unrelated FMOVEM gap), so save/restore tests at the tail would never
execute. (They're privileged, so the combined corpus is supervisor-only —
the user-mode Mac OS app keeps using the baseline-only `cpu_fpu_tests.h`.)

Expected (Verilator, **pre-2026-06-05**): 1148 passed, 180 failed — a
diagnostic signal pointing at TG68K coprocessor microcode gaps (FMOVE
control regs, FMOVEM, FMOVE.D memory, and some FDBcc condition codes).
**This number predates the 2026-06-05 corpus fixes below and needs a
Verilator re-run to refresh.**

#### Real-hardware oracle (2026-06-05) and the FDBcc timing quirk

The corpus was run on a **real Macintosh II (68020 + 68881)** via BlueSCSI
to serve as the ground-truth oracle for tuning the FPGA cores. Baseline:
**1319/1320 pass** (`results/cpu_fpu/hw_2026-06-05.jsonl`). Fixes landed
this session, all hardware-confirmed:

- **FDBcc operand-swap** — `gen_fcmp_fdbcc` loaded operands into the wrong
  FP registers vs FScc/FBcc, inverting the condition for every `a≠b`.
  Predicate logic itself is validated against the FPU core's own RTL truth
  table (`68881-fpga/src/mc68881_top.vhd::eval_fcc_condition`, 0 mismatches).
- **FMOVEM.X** — load ext word was `$C040` (predec list-mode) under an
  `(A7)+` postinc EA; corrected to the canonical `$D040`.
- **FPIAR round-trip tests retired** — FPIAR is the FP *instruction-address*
  register; a real 68881 returns that address, not the written data, so the
  round-trip can never match silicon (the FPGA core stores it as plain data
  and would pass). 16 non-faithful tests removed.
- **Per-test FPU reset** — the harness (`cpu_fpu_bench_main.c`) now issues a
  **null-frame `FRESTORE`** before each test so results don't depend on
  prior-test FPU state. (An earlier `FMOVE.L #0,FPCR/FPSR` reset changed the
  register values but not the coprocessor *state machine*, which made the
  next FDBcc take a Line-1111 trap — `FRESTORE` is the correct reset.)
- **Per-test result flush** — `jw_commit_line` after each line, so a hard
  lock localizes to a single test post-mortem.

**Known quirk — the single remaining "failure" (#074):**
`FCMP+FDBULE FP1,FP7 (5,47)` intermittently takes a **Line-1111 (F-line)
trap** in the full-run context (`vec=11`, `actual=0`), but its expected
value `99` is correct (RTL- and byte-verified) and the *same test passes in
isolation*. As the per-test reset changed cycle timing, the trap roved
within the #073–#074 pair (FMOVE-reset → #073; FRESTORE-reset → #074),
which is the signature of a **real 68881 coprocessor-dialog timing
marginality on this specific aging chip — not a corpus error.** Do **not**
"correct" #074's expected to the trap residue (0): that would bake a
non-deterministic hardware glitch into the spec and make a correct FPGA
core (which should produce 99) fail. The FPGA should match the corpus
expected value, which is more correct than the flaky silicon here.

Full write-up: [`docs/cpu_fpu_fdbcc_analysis_2026-06-05.md`](../docs/cpu_fpu_fdbcc_analysis_2026-06-05.md).

For a per-cycle trace of FPU dialog on a single test, run with `--trace`:

```
./obj_dir/Vcpu_fpu_tests --trace      # smoke test only, no JSON arg
```

There's also a small **F-line trap regression corpus** that verifies
unsupported FPU ops raise a 1111 (F-line) trap:

```
./obj_dir/Vcpu_fpu_tests fline_trap_regression.json
```

And a **FSAVE / FRESTORE (cpSAVE / cpRESTORE) corpus** that exercises the
CIR state-frame save/restore dialog — the one path neither the math
baseline nor the F-line set touches:

```
./obj_dir/Vcpu_fpu_tests save_restore_corpus.json
```

8 vectors, goldens captured from MAME `maciihmu` (the oracle) via
`gen/mame_save_restore_capture.lua`. Regenerate with:

```
cd ~/repos/mame
SDL_VIDEODRIVER=offscreen ./mame maciihmu -skip_gameinfo -ramsize 8M \
    -nothrottle -seconds_to_run 90 -window -autoboot_delay 1 \
    -autoboot_script <repo>/SingleStepTests/gen/mame_save_restore_capture.lua
# -> /tmp/save_restore_corpus.jsonl (rows) + /tmp/save_restore_frames.txt (frame dumps)
# convert the JSONL to the JSON-array form this bench consumes.
```

**What these vectors actually test (read before extending).** `FSAVE` /
`FRESTORE` move the coprocessor's *internal* (microcode) state via the
IDLE/BUSY/NULL frame — **not** the programmer-visible FP data registers
FP0..FP7 / FPCR / FPSR (those move with `FMOVEM`). So a
save → clobber FP3 → restore does **not** bring the clobbered register
back: correct 68881 behavior leaves the clobber in place. Two vectors
assert exactly that (`expected = 99`, the clobbered value); the others
assert the FPU is still *usable* after a full save/restore cycle
(`FMOVE.L FPn,D1` reads the expected value back). The frame-shape probes
captured the format words a real 68881 emits: **IDLE = `0x1F18`**
(version `0x1F`, 24 data bytes), **NULL = `0x0000`** — see
`/tmp/save_restore_frames.txt`.

**Why this corpus is the diagnostic.** A core that wedges the CIR
`SAVE_FRAME` dialog never retires the `FSAVE`, so the program never
reaches its result move — every row fails as a **timeout / stale
D-register** rather than a wrong value. On MAME (correct) all 8 pass;
divergence localizes the save/restore protocol bug. The same vectors
also run on real hardware through the supervisor CPU/FPU bench
(`preboot/supervisor_bench/`), which is where the actual FPGA wedge
shows up.

### FPU-only bench (`fpu/`)

Standalone scaffold for the `fpu_lite` Verilog build of `mc68881_top` —
runs the FPU in isolation without a CPU. Useful for diagnostics; not
currently driven by a JSONL corpus.

```
cd SingleStepTests/fpu
make
./obj_dir/Vfpu_tests
```

## Test categories and what they cover

The 718-test CPU corpus is built from `gen/mame_cpu_capture.lua`. Each
entry in `gen/cpu_tests.h` carries metadata flags that control which
environments run it:

| Flag | Verilator bench | MAME (supervisor) | Mac OS bench |
|---|---|---|---|
| (none) | runs | runs | runs |
| `privileged` | runs | runs | **skips** (Mac app is user-mode → traps) |
| `raises_exception` | runs | runs | **skips** (trap handlers OS-side) |
| `hw_unsafe` | **skips** | runs | **skips** (would hang/reboot real HW) |

Today the corpus contains: 696 non-privileged tests, 22 privileged
tests, ~10 exception-raising tests, and zero `hw_unsafe`. Adding
something like RESET or STOP later should set `hw_unsafe = true`.

## Regenerating corpora

### CPU corpus from MAME

```
cd /Users/dani/repos/mame
./maciihmu maciihmu -bios original -skip_gameinfo -debug \
    -debugger none -window -nothrottle -autoboot_delay 1 \
    -autoboot_script /Users/dani/repos/lbmactwo_MiSTer/SingleStepTests/gen/mame_cpu_capture.lua
```

Writes `/tmp/cpu_corpus.json` (the JSONL oracle) and `/tmp/cpu_tests.h`
(the test bytes header used by the Mac bench and verilator). Copy them
in:

```
cp /tmp/cpu_corpus.json /Users/dani/repos/lbmactwo_MiSTer/SingleStepTests/results/cpu/mame_baseline_2026-05-16.json
cp /tmp/cpu_tests.h     /Users/dani/repos/lbmactwo_MiSTer/SingleStepTests/gen/cpu_tests.h
```

### FPU corpus from the Musashi-based generator

```
cd SingleStepTests/gen
make gen_fpu
./gen_fpu /tmp/fpu_corpus.json
cp /tmp/fpu_corpus.json ../cpu_fpu/fpu_corpus_baseline.json
```

Edit `gen_fpu.c` to add new test categories; the generators are
self-contained per op.

## Running on a real Mac

**Short answer: yes — but only the user-mode tests.** Out of the 718
tests in the CPU corpus, **696 run on Mac hardware** (the Mac bench
skips the 22 privileged tests + ~10 exception-raising ones because a
Mac OS application runs in user mode and any privileged instruction
would trap).

### What you need

- A 68020-equipped Macintosh (Mac II, IIx, IIcx, …) running System 6/7
- THINK C 5+ or Symantec C++
- The `-sys7.c` / `-sys7.h` variants of the bench (CR line endings for
  classic Mac OS)

### Build & run the CPU hardware bench

1. Copy these two files to the Mac:
   - `SingleStepTests/gen/cpu_test_macii-sys7.c`
   - `SingleStepTests/gen/cpu_tests-sys7.h`
2. In THINK C:
   - New Project → Application
   - Add the `.c` file plus `ANSI.π` + `MacTraps`
   - Place the `.h` file in the same folder as the `.c` (not in the
     project picker)
   - Project → Build Application
3. Run it. The app prints each test name and writes the results to
   `"CPU Results.jsonl"` in its working directory, in the same JSONL
   schema MAME emits.
4. Pull the JSONL back to a host and diff against the MAME oracle:
   ```
   python3 SingleStepTests/gen/cpu_diff_corpus.py \
       SingleStepTests/results/cpu/mame_baseline_2026-05-16.json \
       /path/to/CPU\ Results.jsonl --markdown
   ```

### FPU hardware bench

Same workflow, but with these files (1328-test corpus):

- `SingleStepTests/gen/fpu_test_macii_full-sys7.c`
- `SingleStepTests/gen/fpu_tests-sys7.h`

The app produces `"FPU Results Full.jsonl"`. See
**[gen/README.md](gen/README.md)** for the full FPU pipeline,
hardware-vs-MAME divergence categories, and the THINK C 32-bit globals
caveat.

### Why privileged tests don't run on Mac

The Mac bench is a normal Mac OS application running at user-mode
(supervisor bit = 0 in SR). Privileged instructions — MOVES, MOVE to/from
SR, ANDI/ORI/EORI to SR, MOVEC, MOVE An,USP, RTE — all trap to vector
8 (Privilege Violation) when executed in user mode. The bench skips
them by checking `t->privileged` and recording a zero snapshot instead
of attempting to run.

To run privileged tests on real hardware you'd need either:

- A boot-time driver (INIT/extension) that runs in supervisor mode and
  exposes a test interface, or
- A standalone disk-resident program that takes over the machine

Neither exists today. The MAME oracle and the verilator bench (both
supervisor-mode by default) cover all 718 tests including the
privileged ones — that's our authoritative cross-check for those.

## What's documented elsewhere

- **[gen/README.md](gen/README.md)** — FPU oracle pipeline, the Mac OS
  bench in detail, hardware-vs-MAME divergence categories, diff tool
  output formats
- **[test-blockers.md](test-blockers.md)** — confirmed bugs to fix and
  what's blocking further progress
- **[results/cpu/](results/cpu/)** — historical CPU bench result
  snapshots
- **[results/fpu/](results/fpu/)** — historical FPU bench result
  snapshots
