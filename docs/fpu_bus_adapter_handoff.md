# FPU bus-adapter / FSAVE-FRESTORE handoff (2026-06-10)

Session handoff for continuing on the FPGA-connected machine. Branch:
**`fpu-bus-adapter`** (pushed to origin; 5 commits on top of
`origin/boot-investigation`).

## What this branch contains

| Commit | Change |
|---|---|
| `abe6056` | 16↔32-bit FPU Operand-CIR bus adapter ported from the unit bench (`SingleStepTests/cpu_fpu/cpu_fpu_tests.v`) into **`verilator/sim.v`** and **`LBMacTwo.sv`**. TG68K splits `.L` into two word beats; `mc68881_top` (since `2dfbafc`) expects ONE 32-bit transfer per Operand-CIR long word. The adapter latches the high half, fakes a DSACK on the inactive phase, and presents `{hi,lo}` as a single transfer. Also derives `size_n` from `longword`+UDS/LDS instead of hardcoding word size. |
| `0b66b67` | **TG68K kernel fix: NULL-frame FRESTORE must pop the full 4-byte format long.** `cp_restore_decode`'s null branch wrote An back after consuming only the 2-byte format word. Every cpufpubench test runs a `CLR.L -(A7); FRESTORE (A7)+` preamble, so A7 came back −2 and the test's RTS jumped to garbage → 100% of tests trapped. Fix: null path now routes through `cp_restore_skip_fmtlo` (reads + discards the reserved low word) and writes An back from a new `cp_restore_null_done` micro-state one cycle later. `TG68KdotC_Kernel.v` regenerated via `rtl/tg68k/convert_to_verilog.sh` (ghdl). |
| `9099a66` | Verilator debug: `** CIRRD` logging (FPU CIR reads, `$22000-$2203F`, post-adapter data) alongside the existing `** CIRWR`, gated by new `--cpu-trace-min-frame N` flag. This is what made the FSAVE frame dialog visible. |
| `1d526d8` | `verilator/boot2.hex` → `../boot2.hex` symlink (decl ROM is `$readmemh`-loaded relative to CWD; without it the Slot Manager finds no video card, ScrnBase stays unset, and SCSI boot stubs halt before painting). Plus `scripts/extract_results.py` (rb-cli-free `/Results.jsonl` extractor; parses APM + RJSNLTAG offset). |

History context: `main` lacks all of `boot-investigation`'s cpSAVE/cpRESTORE
fixes (`f1cac38`→`2dfbafc`→`34fbad3`→`e5895c5`) — on main the bench wedges
mid-FSAVE on test 1 (prefetch overrun: FSAVE opword issued, FRESTORE never
reaches the FPU, next F-line dialog hangs forever).

## Verification status

| Environment | Result |
|---|---|
| Real Mac II (corpus oracle) | 1319/1320 |
| Unit bench (`SingleStepTests/cpu_fpu`), this branch | save_restore **8/8**; full corpus **1102/1320** — failure set byte-identical to pre-fix baseline (all FMOVEM-class known gaps, zero regressions) |
| Full-system Verilator, this branch | **1100/1320**, "ALL CPU/FPU TESTS DONE", ioResult=0 (was: 0 passing, every test trapped) |
| FPGA (bitstream built from this branch) | Test 1 **passes** (`run=1 ok=1 bad=0 trap=0`) — first hardware pass of the FSAVE/FRESTORE roundtrip — **then hangs before painting test 2** ← open issue #1 |
| Mac OS 7.1.2 boot on FPGA | "coprocessor not installed" bomb ← open issue #2 (believed expected, see below) |

## Open issue #1: FPGA bench hang after test 1

Symptom: `run=1 ok=1 bad=0 trap=0` painted, test 2's number/name never
painted, machine wedged. Sim runs the identical sequence 1320× cleanly, so
this is hardware-only (SDRAM arbiter / timing / VPA-E-clock territory).

The hang window is narrow. Bench loop order per test (see
`SingleStepTests/preboot/supervisor_bench/cpu_fpu_bench_main.c`):
paint number/name → build_program → invoke → paint counters → emit JSONL
record (RAM buffer only, no I/O until 16 KB) → next iteration repaints the
number. Counters for test 1 are on screen; test 2's number isn't — so it
stopped in the JSONL emit (plain RAM code) or the first instructions of
iteration 2 (which start with the NULL-FRESTORE preamble).

**Next step: JTAG probes before SignalTap** (zero rebuild cost):
`scripts/read_probes.sh` / `scripts/cpu_state.tcl` per
`docs/MISTER_HARDWARE_DEBUGGING.md`. Read the wedged PC and map it:

- `~0x00040Bxx-0x000409xx` (JSONL writer / runner loop) → RAM access stall →
  SDRAM-arbiter suspicion.
- `~0x000628Exx` (prog_buffer; the test preamble `42A7 F35F F280 0000` =
  `CLR.L -(A7); FRESTORE (A7)+; FNOP`) → suspect the **new
  `cp_restore_skip_fmtlo` read in the NULL path**: it issues a discarded
  word read of the reserved format-low word. NOTE: `cp_fc_override` is
  asserted for `next_micro_state = cp_restore_skip_fmtlo`
  (TG68KdotC_Kernel.vhd ~line 868), so that stack read runs with **FC=7**;
  FC=7 non-FPU addresses resolve via the `_cpuVPA`/E-clock autovector path
  (`LBMacTwo.sv` ~line 515, `tg68k.v` `auto_iack`). Sim tolerates this;
  real E-clock timing may not. If the probe lands here, either remove the
  FC override for skip_fmtlo's memory read (it should be a normal FC=5
  data read — arguably a pre-existing bug for the non-null path too) or
  skip the bus read entirely and just advance `cp_ea_addr` by 2.
- FPU CIR region / AS held low at `$0002xxxx` → adapter handshake timing →
  SignalTap on `fpuAddrMatch`, `fpu_xfer_phase`, DSACKs, `_cpuAS`.

Also run the bench 2-3 times with power cycles: always-stops-at-test-1 ⇒
deterministic protocol bug (SignalTap will catch it in one capture);
varies ⇒ timing/arbiter flakiness.

Useful payload addresses (from the sim trace; payload loads at 0x40000,
prog_buffer at ~0x628E6, final_snap at ~0x62A26):
runner `invoke_test_with_recovery` at `0x410E8`, its `jsr (A0)` at
`0x41138`, JSONL putc loop around `0x40B44-0x40B86`.

## Open issue #2: 7.1.2 "coprocessor not installed" — believed EXPECTED

That dialog = an F-line exception reached the system error handler. Chain:
ROM FPU detection (Response-CIR read) now **succeeds** → Gestalt reports a
68881 → 7.1.2's FP context-switch code uses **FMOVEM.X** alongside
FSAVE/FRESTORE → FMOVEM is the lite FPU's main unimplemented class (the 218
known corpus failures; even MAME aborts on some) → take-exception primitive
→ F-line → bomb. Before these fixes the OS instead wedged silently at the
first FSAVE, so this is forward progress, not a regression.

Remedy is **implementing FMOVEM in mc68881 lite** (RTL feature work), not
SignalTap. Quick confirmations if desired: (a) the bench's trap counter on
this branch only climbs in the FMOVEM section of the corpus; (b) a no-FPU /
stub configuration boots 7.1.2 fine via SANE fallback.

## Practical notes

- **Verilator sim**: run from `verilator/`; build `make USE_FPU_STUB=0` for
  the real FPU (slow, ~0.4 fps) or plain `make` for the fast CIR stub
  (~1.3 fps, every FPU op F-line traps by design). `rm -rf obj_dir` when
  switching branches or stub/real — dependency tracking can't be trusted.
  Useful flags: `--no-memtest --frame-probe --frame-interval 20`,
  `--cpu-trace-min-frame N` (window the cpu_trace.log; CIRWR/CIRRD lines
  show the full coprocessor dialogs), `--screenshot f1,f2,... --stop-at-frame N`.
- **Known sim gap**: guest SCSI *writes* never persist to the host `.hda`
  (Mac driver reports ioResult=0 but data is dropped; reads work). So
  `/Results.jsonl` can't be extracted from sim runs — use the painted
  counters, or MAME/hardware images with `scripts/extract_results.py`.
- **Regenerated kernel netlist**: structurally different from the previous
  generation (newer ghdl emits different RTL style, 42k vs 76k lines) but
  corpus-verified identical behavior. `TG68K_ALU.v` deliberately left at the
  committed version (kernel netlist embeds its own specialized ALU).
- The unit bench is the fast regression loop (~minutes):
  `cd SingleStepTests/cpu_fpu && make && ./obj_dir/Vcpu_fpu_tests save_restore_corpus.json`
  (also `cpu_fpu_full_corpus.json`; expect 1102/218 with identical FAIL set).
- Fixture: `SingleStepTests/preboot/supervisor_bench/fixtures/` —
  `cpufpubench.hda.zip` on main and `.hda.gz` on this branch are
  byte-identical images; both validated on real Mac II.
