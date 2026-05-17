# SingleStepTests benches

Per-instruction verification benches for the computational cores in
this repo, modeled on the
[iigs_simulation/SingleStepTests](https://github.com/SingleStepTests/65816)
pattern.

## Layout

| Dir | What it tests | Status |
|---|---|---|
| `tg68k/` | Raw `TG68KdotC_Kernel` (68020 mode) via per-cycle bus driver | ✅ 10/10 ADD.l, needs corpus expansion |
| `fpu/` | `mc68881_top` (verilog `fpu_lite` build) via coprocessor CIR | scaffold; no tests yet — blocked on B-1 |
| `cpu_fpu/` | Integrated `tg68k` + `mc68881_top` end-to-end | hangs on CIR Response read; see [test-blockers.md](test-blockers.md) |
| `gen/` | Test corpus generators + the Mac OS hardware bench + diff tool | ✅ 270-test FPU corpus, 170/270 baseline vs real hardware |
| `results/` | Committed run snapshots (markdown + JSON) for tracking accuracy over time | |

## Verilator benches

Each verilator bench is a self-contained build. From inside a bench dir:

```
make        # build the bench
./test.sh   # run all JSON tests in the configured corpus dir
```

Test data is not vendored; benches expect a sibling clone of the relevant
SingleStepTests corpus (see each Makefile's `TESTDATA_*` variables).

## FPU oracle + Mac OS hardware bench

The FPU test pipeline (MAME oracle, real-hardware Mac OS application,
diff tool) is documented in detail in **[gen/README.md](gen/README.md)**.
That subsystem can verify any FPU implementation that emits results in
the shared JSONL schema — currently used for MAME ↔ real Mac II, will
extend to Snow and to `cpu_fpu/` once the CIR Response bug is fixed.

Current baseline: see **[results/hw_vs_mame_2026-05-16.md](results/hw_vs_mame_2026-05-16.md)**.

## What's blocked

See **[test-blockers.md](test-blockers.md)** for the live list. Key
items: the CIR Response read bug in `mc68881_top.vhd` (blocks all
verilator-FPU testing), and the per-test FPSR.AEXC reset that would
tighten hardware↔MAME comparison.
