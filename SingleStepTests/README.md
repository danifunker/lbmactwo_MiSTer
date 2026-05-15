# SingleStepTests benches

Per-instruction verification benches for the two main computational cores in
this repo, modeled on the
[iigs_simulation/SingleStepTests](https://github.com/SingleStepTests/65816)
pattern:

- `tg68k/` — drives `TG68KdotC_Kernel` (raw, 68020 mode) through one bus
  cycle at a time and compares architectural state against a JSON corpus.
- `fpu/` — drives `mc68881_top` (Verilog `fpu_lite` build) through the
  coprocessor CIR interface.

Each bench is a self-contained Verilator build. From inside a bench dir:

```
make        # build the bench
./test.sh   # run all JSON tests in the configured corpus dir
```

Test data is not vendored; benches expect a sibling clone of the relevant
SingleStepTests corpus (see each Makefile's `TESTDATA_*` variables).
