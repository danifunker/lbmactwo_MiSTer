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

### B-1: FPU CIR Response read returns $0000 forever  ⚠ ARCHITECTURAL

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

**TODO (future):**
- Scale the Mac-side bench to consume the same 270 tests (currently
  hand-listed 9). Likely needs a binary loader or generated `.c` so
  the Mac doesn't need 270 hand-encoded test functions.
- Add tests for FMOVE size variants (.L/.S/.D/.W/.B from immediate
  and Dn EA), FMOVEM, FSAVE/FRESTORE, FBcc/FScc/FDBcc.

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

### B-3: SR/PC architectural state not verified in CPU bench  ⚠ COVERAGE

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
