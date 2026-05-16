# SingleStepTests — Status & Blockers

Snapshot taken 2026-05-15. See `git log SingleStepTests/` for commits.

## What works end-to-end

### CPU bench (`tg68k/`)
- Verilator builds clean.
- Runs JSON tests against the raw `TG68KdotC_Kernel` (68020 mode).
- Per-test flow: plant SSP/PC at reset vectors → reset → inject D0–D7/A0–A7
  into the kernel's regfile arrays → run until prefetch reaches `final_pc + 4`
  → compare regfile + RAM diffs.
- **10/10 Musashi-generated ADD.l Dn,Dn tests pass** as of commit `1ef0a1e`.

### CPU corpus generator (`gen/`)
- Links the standalone Musashi at `/Users/dani/repos/Musashi`.
- Emits state-only JSON (schema in `SCHEMA.md`): initial regs+RAM, final
  regs+RAM, no cycle traces.
- Uses `m68k_end_timeslice()` from the memory-read callback to stop
  exactly after one instruction. Normalizes Musashi's prefetch-lookahead
  PC back to the architectural post-instruction PC.
- Currently only emits `ADD.l Dn,Dn`. Adding more opcodes is straight
  copy-paste from `gen_add_l()`.

### FPU bench scaffolding (`fpu/`)
- Builds clean against the `fpu_lite` Verilog build of `mc68881_top`.
- Has a hand-written F-line pretty-printer in `fline_disasm.h` covering
  cpGEN/cpBcc/cpScc/cpDBcc/cpTRAPcc/cpSAVE/cpRESTORE for nicer failure logs.
- Smoke-tests reset OK but **runs no real tests** — see blocker below.

### Integrated CPU+FPU bench (`cpu_fpu/`)
- Builds clean. Wires `tg68k.v` (bus wrapper, so DTACK handshaking is real)
  + `mc68881_top` with address decode + DSACK→DTACK arbitration mirroring
  `verilator/sim.v`.
- Hand-crafted test program in `sim_main.cpp` exercises MOVEQ → FMOVE.L
  D0,FP0 → FMOVE.X FP0,$200 → STOP.
- Trace shows TG68K correctly dispatches OpWord+Command to the FPU CIR.
- **Hangs forever** polling Response — see blocker below.

## Blockers

### FPU integration: end-to-end FMOVE.L Dn↔FPn round-trip working  ✅ (2026-05-16)

**Summary:** End-to-end `MOVEQ #1,D0; FMOVE.L D0,FP0; FMOVE.L FP0,D1`
runs cleanly through the integrated TG68K + mc68881_top Verilator
bench. D1 = 0x00000001 — full round-trip via the M68881 CIR
coprocessor dialog with correct operand data flowing both directions.
First time any F-line FPU instruction has actually completed against
this FPU integration.

**Design summary** for the new TG68K FPU operand-transfer microcode:
each direction uses a 3-microstate pipeline (CPU→FPU) or 4-microstate
pipeline (FPU→CPU) to account for the 1-cycle lag between `setstate`
and `state`. Each microstate owns the muxin/capture logic for the bus
access that physically runs during *its* cycle (driven by `setstate`
from the previous microstate).

- **CPU→FPU**: `cp_xfer_to_load` (latch reg_QB, setstate=11) →
  `cp_xfer_to_hi` (HIGH word write, muxin=cp_xfer_data[31:16]) →
  `cp_xfer_to_lo` (LOW word write, setstate=01 to release bus) →
  `cp_read_resp`.
- **FPU→CPU**: `cp_xfer_from_hi` (setstate=10 setup) →
  `cp_xfer_from_lo` (HIGH word read) →
  `cp_xfer_from_store` (LOW word read, capture HIGH from
  `last_data_read`) →
  `cp_xfer_from_done` (capture LOW, pulse `cp_dn_writeback` to commit
  to regfile) → `cp_read_resp`.

The 1-cycle state lag means the capture for a read in microstate N
happens in microstate N+1, when `last_data_read` has settled with N's
result. `set(update_ld) <= '1'` is asserted in all read states so
`last_data_read` actually updates.

**Fixed in this session:**

1. **Stale FPU source files** — `rtl/mc68881/vhdl/mc68881_pkg.vhd` had
   custom internal opcodes (FADD=0x01, FMOVE=0x05) instead of the
   M68881 native cpGEN opmodes (FADD=0x22, FMOVE=0x00). The .v was
   ghdl-synth'd from the stale .vhd so the bug was baked in. Regen
   from `68881-fpga/src/` (current canonical) gives correct opcode
   decode. README updated with synced regen recipe.

2. **Bench-side CIR address remap missing** — `cpu_fpu_tests.v` and
   `fpu_tests.v` now apply the 3-line remap (CIR std 0/2/3 → fpu
   13/12/28) that `LBMacTwo.sv` already has.

3. **TG68K Response-Primary decoder rewritten** — original CASE on
   bits 15-13 was incompatible with M68881 AN-944/AN-947 encoding.
   New decoder reads bit 12 (transfer primary indicator), bit 13
   (direction), bits 11-8 (TYPE), bits 7-0 (byte count). Verified
   against 68881-fpga's own `tb_mc68881_cir_dialog.vhd` expected
   values (`0x9604`, `0xB204`).

4. **\$fatal assertions stripped from generated FPU .v** — VHDL
   `assert severity failure` becomes `$fatal` after ghdl-synth and
   fires on benign reset transitions in Verilator. Sed step added
   to the regen recipe.

5. **TG68K coprocessor operand-transfer microcode added** — new
   states `cp_xfer_to_load` / `cp_xfer_from_store`, new `cp_xfer_data`
   shift register, new `cp_dn_writeback` control signal mirroring
   the existing `cp_an_writeback` pattern. `rf_source_addr` is
   overridden during cp_idle_resp→cp_xfer_to_load transition to
   pre-stage reg_QB. Combinational `data_write_muxin` bypass for
   cp_xfer_to to avoid data_write_tmp pipeline pitfalls.

**Observable progress:**

- Before: FPU returns Response=0x0000 immediately, decode treats
  FMOVE as NOP, no operand transfer attempted.
- After: FPU returns `0x9604` (Transfer CPU→FPU), TG68K enters
  cp_xfer_to, drives the operand register twice (.L = 2 word
  transfers), reads next Response, dispatches second instruction,
  enters cp_xfer_from for FPU→CPU.

**Files touched:** `rtl/tg68k/TG68KdotC_Kernel.vhd` (Response decoder,
cp_xfer_data buffer, cp_dn_writeback, rf_source_addr override,
data_write_muxin combinational bypass, 7 new microstate bodies),
`rtl/tg68k/TG68K_Pack.vhd` (7 new microstate enum values),
`rtl/mc68881/vhdl/*.vhd` (synced with canonical 68881-fpga/src),
`rtl/mc68881/fpu_lite/mc68881_top.v` (regenerated), `rtl/mc68881/README.md`
(regen recipe), bench wrappers (CIR address remap) and sim_main.

**CPU regression check:** 360/360 of the existing CPU corpus
(ADD/SUB/AND/OR/EOR/CMP/NEG/NOT/CLR/TST/ASL/ASR/LSL/LSR/ROL/ROR/
ROXL/ROXR .L) still passes after all TG68K patches.

**Next steps:** scope is now `FMOVE.L Dn↔FPn` only. To expand:
- Other FMOVE size variants (.B/.W/.S/.D/.X/.P): same pipeline,
  different byte counts per transfer (FPU's Response Primary
  carries the byte count in bits 7-0, which the bus needs to use
  to size the access).
- Other EA modes (memory, immediate): need `cp_xfer_to_load` /
  `cp_xfer_from_done` variants that route to/from memory address
  instead of regfile.
- ALU ops (FADD, FMUL, etc.): same operand transfer mechanism, the
  FPU just sequences differently in its CIR FSM. Should work
  without further TG68K changes once we send a non-FMOVE opcode.
- Build a Musashi-oracled FPU test corpus (gen_fpu.c) mirroring
  the CPU pipeline once the above are in place.

### B-1: FPU CIR Response read returns $0000 forever  ✅ RESOLVED (bench fix)

**Original diagnosis was wrong.** The FPU's VHDL read path is correct.
The bug was in the **bench wrappers**, which drove `mc68881_top.a_in`
with raw `cpu_addr[5:1]` and omitted the address remap that the real
integration in `LBMacTwo.sv:480-488` applies. `mc68881_top` uses
non-standard CIR register addresses to avoid collision with
peripheral-mode regs (0/2/3 → 13/12/28); without the remap, CPU reads
of CIR Response (addr 0) hit the peripheral OPSEL register and always
return 0 = BUSY.

**Fix:** added the 4-line remap to both bench wrappers:
- `cpu_fpu/cpu_fpu_tests.v` — now drives `fpu_addr_remapped`.
- `fpu/fpu_tests.v` — same remap on the C++ driver's `a_in`.

**Verified:** the `cpu_fpu` bench's MOVEQ→FMOVE.L D0,FP0→FMOVE.X FP0,$200
sequence no longer hangs. FMOVE.L D0,FP0 completes cleanly (Response
cycles 0x0000→0x7004→0x0000, operand transfer succeeds). FMOVE.X
FP0,$200 dispatches (Response 0x2001 then 0x0000) but doesn't write
to memory — needs follow-up to distinguish whether fpu_lite supports
FMOVE.X-to-EA, or whether the bench mishandles the operand-out
roundtrip. Try `FMOVE.L FP0,Dn` next to disambiguate.

**File reference:** `rtl/mc68881/fpu_lite/mc68881_top.v` is the
ghdl-synth'd "lite" variant of the FPU (MC68040 subset: 11 core ALU
ops — FADD, FSUB, FMUL, FDIV, FABS, FNEG, FSQRT, FCMP, FTST, FINT,
FINTRZ). Canonical VHDL sources live in `68881-fpga/src/`; regen via
`68881-fpga/scripts/convert_to_verilog.sh` and copy
`verilog/fpu_lite/mc68881_top.v` back into `rtl/mc68881/fpu_lite/`.
For the full 37-op MC68881, copy `verilog/mc68881_top.v` instead.

---

### B-1 (historical, before bench fix): FPU CIR Response read returns $0000 forever

**Where:** `/Users/dani/repos/68881-fpga/.../mc68881_top.vhd` ~lines 3153–3275.

**Symptom:** CPU reads CIR byte $00 (Response) and always sees $0000 (=BUSY).
FSM never appears to advance past DECODE from the host's view, so no FPU
instruction can complete.

**Root cause:** The read path's case statement is keyed on the
**peripheral-mode** `ADDR_*` constants. Byte $00 maps to `ADDR_OPSEL`,
which has no `when` clause — falls through to `when others => 0`.
There's no parallel CIR-mode read remap.

- The standard M68020 CIR layout (and TG68K's coprocessor dispatcher)
  expects Response at byte $00.
- The FPU's *write* side gates correctly via `if cir_mode_reg = '1'`
  (lines 3463+). Only the read side is missing the CIR-mode dispatch.
- The peripheral-mode `ADDR_CIR_RESPONSE` constant is byte $1A — reading
  there does return `cir_response_reg`, but TG68K never reads $1A.

**Why this wasn't caught earlier:** `verilator/sim.v` instantiates
`sim_fpu_cir_stub` (defined inline at line 1646), not `mc68881_top`.
The integrated bench in `cpu_fpu/` is the first simulation to put
TG68K and `mc68881_top` together end-to-end.

**Fix lives in:** `/Users/dani/repos/68881-fpga`, not this repo. The
fix is a read-side CIR-mode address remap parallel to the existing
write-side gating. After patching, re-run `SingleStepTests/cpu_fpu/`
to confirm.

### B-2: No FPU test corpus exists  ✅ RESOLVED (270 tests)

**Status:** `gen/mame_fpu_capture.lua` now produces a 270-test corpus
in `/tmp/fpu_corpus.json` (JSON Lines format — one entry per line so
partial runs survive MAME crashes). Coverage:

- 10 dyadic ops × 12 operand pairs = 120 tests
  (FADD, FSUB, FMUL, FDIV, FCMP, FMOD, FREM, FSCALE, FSGLDIV, FSGLMUL)
- 8 monadic ops × 11 operand values = 88 tests
  (FABS, FNEG, FSQRT, FINT, FINTRZ, FGETEXP, FGETMAN, FTST)
- 12 transcendental ops × 5 values = 60 tests
  (FSIN, FCOS, FTAN, FATAN, FETOX, FETOXM1, FLOGN, FLOG10, FLOG2,
   FLOGNP1, FTENTOX, FTWOTOX)
- 2 smoke tests

Operand pool: pos/neg zero, ±1, ±2, ±½, π, π/2, π/4, e, 10, 2^65, 2^-63,
±∞, qNaN. Loaded via `FMOVE.X #imm,FPn` so no conversion is folded in.

**Known MAME m68kfpu gaps** (these ops crash MAME hard with
"unimplemented opmode"; skipped from corpus, must verify directly on
hardware once Mac-side bench scales up):

- FASIN  (0x0C), FACOS  (0x1C), FATANH (0x0D)
- FSINH  (0x02), FCOSH  (0x19), FTANH  (0x09)

**Real Mac II hardware validation:** verified for the 9 bring-up tests
on a physical Mac II (System 7.1.2 + Symantec C++ via
`gen/fpu_test_macii.c`). All 8 arithmetic tests produced byte-identical
extended-precision results vs MAME. One bona-fide MAME divergence
found: reset state of unused FP registers is `7FFF_0000_FFFF...` on
real 68881 (signaling NaN) but `0000_..._00` (or random) in MAME.
Tracked separately as a MAME bug — does not affect tests that preload
their operands.

## Hardware baseline (2026-05-16)

`gen/fpu_test_macii_full.c` + auto-generated `gen/fpu_tests.h` now run
the full 270-test corpus on a real Mac II + System 7.1.2. Output to
"FPU Results Full.jsonl" matches MAME's `/tmp/fpu_corpus.json` schema
exactly. Diff against MAME via `gen/diff_corpus.py`.

**Current pass rate vs MAME oracle:** 170 / 270 (63.0%).

Divergence categories (from `diff_corpus.py`):

| Category         | Count | Cause |
|------------------|------:|-------|
| `trailing_bits`  |    29 | Transcendentals: MAME softfloat ≠ real 68881 algorithm in last 1-3 mantissa bytes. (FATAN, FCOS, FSIN, FETOX, FETOXM1, FLOG*, FTAN, FTENTOX, FTWOTOX) |
| `nan_encoding`   |    14 | MAME produces non-canonical NaN `ffff_0000_c000_..._0000`; real 68881 produces `7fff_0000_ffff_..._ffff` |
| `inf_handling`   |     7 | FINT/FINTRZ/FSCALE/FSGLDIV with ±∞ inputs: MAME returns 0 or finite garbage instead of the infinity |
| `special_value`  |    18 | Other ±∞/qNaN/±0 inputs that MAME mis-handles |
| `smoke_fpinit`   |     1 | Reset-state FP-reg pattern (the documented MAME init bug) |
| `unknown`        |    31 | Remaining gaps, mostly more transcendental precision plus the FLOGNP1 implementation (MAME appears to compute `ln(x)` instead of `ln(1+x)`) |

**Ops where HW matches MAME 100%:** FABS, FADD, FTST.

**Ops where HW matches MAME ≥ 80%:** FCMP, FGETMAN, FMUL, FNEG, FSGLMUL,
FSCALE, FSQRT, FSUB.

**Ops with widespread divergence:** the transcendental block
(FATAN/FCOS/FSIN/FETOX/FLOG*/FTAN/FTENTOX/FTWOTOX) plus FMOD/FREM/FLOGNP1.

## Known bench-side issues to fix before tightening the comparison

1. **FPSR.AEXC accumulates on real HW, doesn't on MAME.** Once any test
   sets a sticky exception (e.g. INEX from FADD π+e), it persists on
   real hardware across all subsequent tests. Need to emit
   `FMOVE.L #0, FPSR` at the start of every test program so AEXC
   starts clean. Affects all 268 post-test FPSR readings in the HW
   corpus and prevents direct FPSR diffing.
2. **`diff_corpus.py` ignores FPSR.AEXC / FPSR.EXC / Quotient and
   only diffs FPSR.CC** until item (1) is fixed.

## TODO (future)

- Add tests for FMOVE size variants (.L/.S/.D/.W/.B from immediate
  and Dn EA), FMOVEM, FSAVE/FRESTORE, FBcc/FScc/FDBcc.
- Add rounding-mode sweep: same test set repeated with FPCR set to
  round-to-nearest / round-to-zero / round-up / round-down.
- File MAME issues for the categorized bugs above (nan_encoding,
  inf_handling, FLOGNP1, FNEG-of-NaN sign flip).

Plan: start with MAME (option 1) since the corpus needs to match real
68881 semantics, not just IEEE 754, and MAME's FPU is closer to the
canonical implementation than Musashi's standalone build.

**First draft of the MAME capture path:** `gen/mame_fpu_capture.lua`.
Targets `maciihmu` (which uses M68020HMMU — verified to include FPU via
`m_has_fpu = 1` in `m68kcpu.cpp:2187`). The script builds a small
asm program per test that preloads FP regs, dumps state to a RAM
window, runs the test instruction, dumps state again, halts at STOP.
Lua then reads the RAM windows back and emits JSON. This is a first
cut and will need iteration once we actually run it — particularly:
- FPCR/FPSR dumps are not yet wired (control-register FMOVE forms).
- The current preload/test bytes are hand-encoded; should validate
  with MAME's disassembler in the debugger window.
- May need to handle the boot ROM still running between
  autoboot-script load and `capture_run()` — script halts the CPU
  before each test but assumes RAM at $1000..$13FF is writable.

### CPU coverage as of 2026-05-16

`gen/gen.c` now emits 18 opcode families × 20 random tests each = 360
SCHEMA.md-format JSON files. **360/360 pass** against the TG68K
Verilator bench with full PC + SR + USP verification. Families:

- Arithmetic / logic Dn,Dn: ADD, SUB, AND, OR, EOR, CMP (all .L)
- Unary Dn: NEG, NOT, CLR, TST (.L)
- Shift / rotate #imm,Dn: ASL, ASR, LSL, LSR, ROL, ROR, ROXL, ROXR (.L)

To regenerate: `make -C SingleStepTests/Musashi`, then
`make -C SingleStepTests/gen MUSASHI_DIR=../Musashi && cd SingleStepTests/gen && ./gen .`,
then run any `./obj_dir/Vtg68k_tests ../gen/<OP>.l.json` in `tg68k/`.

Generated `.json` corpora are gitignored. Add new opcode families by
extending the `g_alu_ops` / `g_unary_ops` / `g_shift_ops` tables in
`gen/gen.c`, or by adding a new per-family generator + main() loop
entry for multi-word ops (immediates, displacements, EA modes).

### B-3: SR/PC architectural state not verified in CPU bench  ✅ RESOLVED

**Status (2026-05-16):** `tg68k_tests.v` now exposes `pc_out`, `sr_out`
(FlagsSR<<8 | Flags), and `usp_out` as wrapper-level outputs via
hierarchical refs (`cpu.tg68_pc`, `cpu.flagssr`, `cpu.flags`, `cpu.usp`).
VBR was already exposed via the kernel's `VBR_out` port. `sim_main.cpp`
diffs PC + SR + USP after each test when the corpus carries those fields
(`final.sr`, `final.usp`). The signal names survive ghdl-synth (verified
in `rtl/tg68k/TG68KdotC_Kernel.v`); if `convert_to_verilog.sh` is rerun
with a different ghdl version that renames them, update the hierarchical
refs in `tg68k_tests.v`.

PC tap reads the prefetch-ahead PC; bench subtracts 4 to recover the
architectural post-instruction PC. SR comparison masks IPL bits 8-10:
TG68K resets with IPL=7, Musashi defaults to IPL=0, and no tests
generate interrupts so this field is setup convention rather than
divergence.

**Verified:** 10/10 ADD.l tests pass against a freshly-generated
Musashi corpus (`gen/ADD.l.json`) including PC + SR + USP checks. Build
Musashi locally with `make -C SingleStepTests/Musashi`, then
`make -C SingleStepTests/gen MUSASHI_DIR=../Musashi` and run `./gen`
to produce the corpus.

### MAME corpus replay (`results/cpu/mame_baseline_2026-05-16.json`)  ⚠ RETIRED

Investigated and abandoned as a Verilator oracle. Two findings:

1. **CCR-read bug in `mame_cpu_capture.lua` (fixed).** The dump emits
   `MOVE.L D0,(snap+0x40)` which writes big-endian `{00,00,00,ccr}`
   starting at offset 0x40, but `read_snap` was reading byte +0x40
   (the high zero byte) instead of +0x43 where CCR actually lands.
   Every `ccr` field in the pre-2026-05-16 corpus was effectively
   zero. Lua now reads +0x43; corpus regenerated and committed.
2. **Real TG68K-vs-MAME M68020 flag divergence in the dump epilogue.**
   Even with the CCR-read fixed, the captured `snap.d[0]` (which
   carries CCR from the prior `MOVE CCR,D0`) differs between MAME
   and TG68K on the same byte sequence (TG68K=0x08, MAME=0x04 for
   the NOP test). Either implementation could be wrong; the dump's
   sensitivity to per-instruction flag side-effects makes it a
   noisy oracle for byte-for-byte snap comparison.

The MAME-replay runner that briefly lived in `sim_main.cpp` has been
removed; the bench only consumes the SCHEMA.md / Musashi schema.
The MAME corpus remains useful for the **Mac II hardware bench**
(`gen/cpu_test_macii.c`) where MAME-vs-real-hardware comparison is
the actual signal of interest — those runs both go through the same
dump epilogue, so the divergence cancels.

---

### B-3 (historical, pre-fix): SR/PC architectural state not verified in CPU bench

**Symptom:** Final SR and PC are not compared post-instruction. Only
D0–D7 and A0–A7 (via the discovered `regfile_n1/n2` paths) plus RAM
diffs are checked.

**Why:** Verilator's flat-name dump of TG68K only exposes `regfile_n1`
and `regfile_n2` as named arrays. SR, PC, VBR, USP, SSP are buried in
the anonymous `n12345`-style signals generated by ghdl-synth.

**Impact:** Flag-sensitive instructions (ASL/ASR, ADDX, condition codes
in branches) cannot be meaningfully verified. The ADD.l tests pass
without verifying that V/C/N/Z were set correctly — only the result.

**Options:**
1. Run a "bootstrap" instruction after each test: `MOVE SR,Dn` to copy
   SR into a known D register, then read that.
2. Hunt down the SR signal in the verilator dump by tracing back from
   the kernel's `flagssr` signal (which I found at
   `tg68k_tests__DOT__cpu__DOT__srin` — but that's `srin`, the input
   to SR, not SR itself).
3. Patch the verilog wrapper `tg68k_tests.v` to expose SR/PC as outputs.
   This is the cleanest fix.

## What to do next, in order

1. **Patch FPU read-side CIR remap** in `68881-fpga`. Without this, no
   FPU testing happens. (B-1)
2. **Generate FPU corpus via MAME Lua** (see `gen/mame_fpu_capture.lua`).
   Even before B-1 is fixed, the corpus itself is independent work and
   can proceed. (B-2)
3. **Expose SR/PC in `tg68k_tests.v`** so the CPU bench can verify
   flags. (B-3)
4. **Expand CPU corpus** in `gen/gen.c` to cover all 68000 base ops and
   then 68020-specific ops.

## File map

```
SingleStepTests/
├── README.md            — entry-point doc
├── SCHEMA.md            — JSON test schema
├── test-blockers.md     — this file
├── json.hpp             — shared JSON parser
│
├── gen/                 — Musashi-based CPU corpus generator (works)
│   ├── gen.c
│   └── Makefile
│
├── tg68k/               — CPU bench (works, 10/10 green)
│   ├── tg68k_tests.v
│   ├── sim_main.cpp
│   ├── Makefile
│   ├── test.sh
│   └── 680x0/           — cloned upstream 68000 corpus (gitignored)
│
├── fpu/                 — FPU-only bench (scaffold; no tests yet)
│   ├── fpu_tests.v
│   ├── sim_main.cpp
│   ├── fline_disasm.h
│   ├── Makefile
│   └── test.sh
│
└── cpu_fpu/             — Integrated bench (BLOCKED on B-1)
    ├── cpu_fpu_tests.v
    ├── sim_main.cpp
    └── Makefile
```
