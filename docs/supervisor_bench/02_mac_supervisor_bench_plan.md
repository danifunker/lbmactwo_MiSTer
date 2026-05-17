# Mac II Supervisor Bench — Implementation Plan

**Audience:** the next Claude Code session, picking up on a Linux x64 box.
This document is self-contained. You will not have the prior conversation.

---

## 1. Goal

Produce one or more bootable 800 KB Macintosh HFS floppy images that, when
booted on a Mac II (real silicon, Snow emulator, our `lbmactwo_MiSTer`
FPGA core, or our verilator sim of the core), run the SingleStepTests CPU
+ FPU + integration suites *in supervisor mode* and write JSONL results
back to the same floppy for offline diff against the MAME oracle.

The existing `SingleStepTests/gen/cpu_test_macii.c` runs as a normal Mac
OS app in user mode, so it skips every test flagged `privileged`,
`raises_exception`, or `hw_unsafe`. This bench takes over the machine
at boot before Mac OS loads, so it stays in supervisor mode for the
whole run and can execute the privileged and exception-raising tests
that the user-mode bench cannot.

## 2. What's already done (don't redo these)

### 2.1 rusty-backup HFS CLI

A sibling repo at `~/repos/rusty-backup` (branch `rusty-cli-hfs`,
commit `6c07039`) provides a headless CLI binary `rusty-backup-cli`
with all the HFS image-construction verbs we need. Build it on the
Linux box with:

```
cd ~/repos/rusty-backup
cargo build --release --bin rusty-backup-cli
# binary lands at target/release/rusty-backup-cli
```

Verb reference (every verb is namespaced under `api hfs` — the `api`
prefix is explicitly unstable and may be reorganised later):

```
rusty-backup-cli api hfs new      <image> [--size 800K] [--name MacIIBench] [--block-size N]
rusty-backup-cli api hfs info     <image>
rusty-backup-cli api hfs ls       <image> [path]
rusty-backup-cli api hfs put      <image> <host-file> <mac-path> [--type BINA] [--creator ????] [--force]
rusty-backup-cli api hfs put-zero <image> <mac-path> <size-bytes> [--type ...] [--creator ...] [--force]
rusty-backup-cli api hfs get      <image> <mac-path> <host-file>
rusty-backup-cli api hfs rm       <image> <mac-path>
rusty-backup-cli api hfs put-boot <image> <bb-file>    # raw write, offset 0, ≤1024 bytes
rusty-backup-cli api hfs validate <image>
```

Mac paths use `/` separators (illegal in HFS file names, so unambiguous).
`--size` accepts `800K`, `5M`, `1G`. `put-zero` pre-allocates a file of
zero bytes — used for the Results.jsonl output buffer the bench writes
into. Confirmed working in macOS-side smoke test (this session) on a
fresh 800K image: round-trip put/get is byte-exact, boot blocks land at
offset 0, `validate` passes after every write.

### 2.2 Test corpora

These are already generated and checked in. The next agent does *not*
need to regenerate them.

| File | Size | Tests | Source |
|---|---|---|---|
| `SingleStepTests/gen/cpu_tests.h` | 177 KB src / ~100 KB packed | 718 | MAME `mame_cpu_capture.lua` |
| `SingleStepTests/gen/fpu_tests.h` | 53 KB src / ~30 KB packed | ~270 | MAME `mame_fpu_capture.lua` |
| `SingleStepTests/cpu_fpu/cpu_fpu_tests.v` | 15 KB | 664 integration cases | derived |

Output JSONL is ~487 bytes/line, measured from
`SingleStepTests/results/cpu/hw_2026-05-16.jsonl`.

### 2.3 Existing user-mode bench

`SingleStepTests/gen/cpu_test_macii.c` is the canonical *user-mode* Mac
OS implementation. Read it before writing the supervisor variant — same
`build_program` / `invoke_program` design, same `Snapshot` struct, same
JSONL emission. The supervisor bench should mirror it line-for-line
except for:

- Removed: `printf` / `fopen` / `fprintf` (no stdio at boot).
- Removed: `if (t->privileged) skip_reason = …` (we run those now).
- Added: a minimal `_Write`-based JSONL emitter targeting a
  pre-opened file refnum.
- Added: VBR setup so the bench's own vector table catches the
  exceptions raised by `t->raises_exception` tests.

See also `SingleStepTests/gen/fpu_test_macii.c` (FPU user-mode bench) for
the FPU oracle dump format. Pair the integration tests with whatever
shape `cpu_fpu` currently uses.

## 3. Architectural decisions already made

- **Boot media:** 800 KB HFS floppy(s). Universally bootable on Mac II
  hardware, Snow, FPGA core, and verilator. No SCSI hardware needed.
- **Output channel:** write JSONL back to the *same* floppy via the
  ROM's `_Write` A-trap. The Sony driver and File Manager are alive at
  boot-block entry, so this works without loading the System file.
- **Output split:** three floppy images — `cpu.dsk`, `fpu.dsk`,
  `cpu_fpu.dsk` — one per suite. Reasoning: full CPU output alone is
  ~350 KB; FPU ~130 KB; integration ~325 KB. Three floppies × ~400 KB
  each fits cleanly under the 780 KB usable HFS budget. Avoids needing
  an on-board RLE compressor.
- **Toolchain:** Retro68 (m68k-apple-macos GCC) on Linux x64.
- **Iteration target order:** Snow → verilator → FPGA → real Mac II.
  Snow is fastest; real hardware is the final cross-check.
- **Source of truth for bytes-under-test:** `cpu_tests.h` / `fpu_tests.h`
  must not be touched. Bench reads them; MAME oracle reads them too;
  any divergence is a bench bug.

## 4. Deliverables for the next session

Work in order. Each step has a verification gate before the next.

### Step A — Retro68 toolchain on Linux x64

Build or install Retro68 (https://github.com/autc04/Retro68). On Linux
x64 this is well-trodden; the README's "Quick Start" usually works
verbatim. Expected output: a `Retro68-build/toolchain/bin/` directory
with `m68k-apple-macos-gcc`, `-as`, `-ld`, `Rez`, `MakeAPPL`, etc., on
PATH.

**Gate:** compile and link Retro68's `hello.c` sample, run it under
Snow / Mini vMac, "Hello, world!" appears.

### Step B — `supervisor_bench/` skeleton in lbmactwo_MiSTer

Create a new directory `SingleStepTests/supervisor_bench/` containing:

```
supervisor_bench/
├── Makefile                 # builds boot-stub.bin + payload.bin + final .dsk
├── boot_stub.s              # 68k asm: 'LK' header + bbEntry → loads payload
├── payload_entry.s          # asm shim: sets VBR, supervisor stack, jumps to C
├── bench_main.c             # forked from cpu_test_macii.c, supervisor-aware
├── jsonl_writer.c           # _Open/_Write/_Close wrapper, no stdio
├── exception_handlers.s     # vector handlers that dump CPU state into Snapshot
├── tests_cpu.h              # symlink or include of ../gen/cpu_tests.h
├── tests_fpu.h              # symlink or include of ../gen/fpu_tests.h
├── tests_cpu_fpu.h          # converted form of cpu_fpu/cpu_fpu_tests.v
└── build_image.sh           # drives rusty-backup-cli to assemble the .dsk
```

**Gate:** `make` succeeds with empty stub bodies (link succeeds; sizes
sensible). Then incrementally fill.

### Step C — Boot block stub (boot_stub.s, ≤1024 bytes)

Layout (from Inside Macintosh: Files, "Boot Blocks"):

```
+0x00  bbID         'LK'     (0x4C4B)
+0x02  bbEntry      6 bytes  68k instructions, typically BRA.S to real code
+0x08  bbVersion    word
+0x0A  bbPageFlags  word
+0x0C  bbSysName    pascal str (15 bytes)  "System"
+0x1B  bbShellName  pascal str (15 bytes)  "Finder"
... (more name fields, see Inside Macintosh)
+0x8A  startup code (we live here)
```

The `bbEntry` field must contain a real branch into our code. The
standard System-file boot uses these fields to chain-load; we ignore
them and just jump into our own code.

What our stub must do:

1. Disable interrupts (`MOVE #$2700, SR`) — keep them off until our
   vector table is installed.
2. Locate the boot disk's volume refnum. On entry to `bbEntry`, the
   ROM has already mounted the boot volume; its refnum is stored in
   low-mem global `BootDrive` ($210) as a *drive number*. Convert via
   `_GetVolInfo` if you need the vRefNum.
3. `_Open` the payload file (e.g. `/Payload`) → get a file refnum.
4. `_Read` the payload into a known RAM region (suggest `$00040000`,
   above the system heap and below typical Mac II RAM ceiling).
5. `_Close` the refnum.
6. `JMP $00040000` to payload entry.

A-trap calling convention: parameters in a ParamBlockRec on A0,
trap number in the instruction. See Inside Macintosh: Files for
exact PB layouts.

**Gate:** stand-alone test — build a payload that just writes a
known byte pattern to `$00041000` and infinite-loops. Boot in Snow,
verify via Snow's memory inspector that the pattern is present.

### Step D — Payload entry + supervisor setup (payload_entry.s)

1. Confirm S=1 in SR (we entered from boot blocks, should be true).
2. Allocate a private supervisor stack (8 KB, in our payload BSS).
3. Save the old VBR (`MOVEC VBR,A0`) — we restore it before returning,
   if we ever return.
4. Build our own 256-entry vector table in RAM. Default every vector
   to `dump_and_resume` (defined in exception_handlers.s). Vectors
   we care about specifically — reset, bus error, address error,
   illegal instr, divide-by-zero, CHK, TRAPV, privilege, line-A,
   line-F, trace, F-line — all land in dispatchers that record the
   exception class into the current test's `final_snap.exception_taken`
   and `final_snap.exception_vector` fields, then resume the harness.
5. Install via `MOVEC A_NEW_VBR, VBR`.
6. Jump into `bench_main()` (C, ABI-compatible).

### Step E — bench_main.c

Fork of `cpu_test_macii.c`. Differences:

- Remove `#include <stdio.h>` and replace `printf` / `fopen` etc. with
  `jsonl_writer.c`'s API (`jw_open(path) → refnum`, `jw_write(refnum, fmt, …)`,
  `jw_close(refnum)`).
- Remove the `privileged` skip — drop the `t->privileged` branch on
  `cpu_test_macii.c:259`. Keep `t->hw_unsafe` skip (those genuinely
  hang the CPU even in supervisor: `RESET`, `STOP #$2700`, etc.).
- Handle `t->raises_exception`: don't skip; instead set up so the
  installed exception handlers record the vector taken into the
  snapshot, then return through `RTE` back to the harness so we can
  emit the JSONL line.
- Drop progress prints. Optionally render a heartbeat to `ScrnBase`
  ($0824) — flip a pixel every N tests — so the operator sees the
  bench is alive.

A separate `bench_main_fpu.c` and `bench_main_cpu_fpu.c` follow the
same pattern. Each builds its own `.dsk` (cpu.dsk / fpu.dsk /
cpu_fpu.dsk) with the right corpus header and the right output path
on the floppy.

### Step F — JSONL writer (jsonl_writer.c)

Minimal `_Open` + `_Write` + `_Close` wrapper. The output file
(`/Results.jsonl`) is *pre-allocated* by `build_image.sh` via
`rusty-backup-cli api hfs put-zero` to a known size (400 KB). The
bench `_Open`s it, writes N bytes via repeated `_Write` calls
tracking a running offset, then `_SetEOF` to truncate to the actual
written length, then `_Close`. No filesystem growth needed.

Number formatting: write a tiny `u32_to_dec` / `i32_to_dec` /
`hex_byte` helper set. No `printf` needed; JSON is structurally
trivial.

### Step G — build_image.sh

Drives `rusty-backup-cli` to assemble each floppy:

```bash
#!/bin/bash
set -euo pipefail
RB="$HOME/repos/rusty-backup/target/release/rusty-backup-cli"
TEMPLATE="$HOME/Downloads/800KB_Disk_Image.dsk"   # or just `new` fresh each time
OUT=${1:-cpu.dsk}
SUITE=${2:-cpu}                                   # cpu | fpu | cpu_fpu

cp "$TEMPLATE" "$OUT"   # or: $RB api hfs new "$OUT" --size 800K --name MacIIBench
$RB api hfs put-boot "$OUT" build/boot_stub.bin
$RB api hfs put      "$OUT" build/${SUITE}_payload.bin /Payload
$RB api hfs put-zero "$OUT" /Results.jsonl 409600
$RB api hfs validate "$OUT"
$RB api hfs info     "$OUT"
```

### Step H — Host-side result extraction

```bash
$RB api hfs get cpu.dsk /Results.jsonl results/cpu/super_$(date +%F).jsonl
python3 SingleStepTests/gen/cpu_diff_corpus.py \
    SingleStepTests/results/cpu/mame_oracle.jsonl \
    results/cpu/super_*.jsonl
```

### Step I — Iteration loop in Snow

The Snow emulator (`~/repos/snow`) supports Mac II and 800K floppies.
Mount `cpu.dsk` as boot floppy, run, halt when the bench loops at
"DONE" pattern on screen, extract Results.jsonl, diff, iterate. Snow
has a CLI mode suitable for scripting.

## 5. Known unknowns / risks the next session will hit

1. **Exception-resumption from arbitrary vector.** Standard 68020
   exception frames have format codes; the resume path needs to
   patch SR and PC to skip the faulting instruction, then `RTE`. This
   is fiddly. Reference: 68020 PRM §6.4 and the format-0 / format-2
   stack frame layouts.

2. **F-line vs FPU-present.** Tests that exercise FPU instructions
   will F-line on a Mac II without an FPU. Our target *is* the Mac II
   (no built-in FPU). For FPU tests, the boot stub or payload must
   first probe for a NuBus FPU card or skip the FPU suite. On the
   FPGA core, the FPU is integrated and always present; that path
   does not need probing. The Snow / real-hardware path does.

3. **HFS file write growth.** The pre-allocated `Results.jsonl` is
   400 KB; if a corpus is larger than that, `_Write` past EOF
   succeeds and the file grows, but allocation block extension
   competes for the same volume space as our payload. Keep the
   payload small (target < 50 KB) so the volume has headroom.

4. **MAME oracle hasn't been re-captured against the integration
   corpus's exact bytes.** Verify `cpu_fpu_tests.v` has a matching
   oracle file under `SingleStepTests/results/` before treating its
   diffs as authoritative.

5. **64K segment limit (CODE resources).** Retro68 by default builds
   apps with the classic 32K-per-segment limit; with `-mlong-jump` /
   `-fno-segment` you can produce a single flat binary. We want a
   flat binary (the boot stub just slurps bytes and jumps), not an
   APPL with CODE-0/CODE-1 segmentation.

## 6. References

In this repo:
- `SingleStepTests/gen/cpu_test_macii.c` — user-mode oracle, mirror it
- `SingleStepTests/gen/cpu_tests.h` / `fpu_tests.h` — test corpora
- `SingleStepTests/gen/cpu_diff_corpus.py` — diff tool
- `SingleStepTests/results/cpu/hw_2026-05-16.jsonl` — sample output size baseline
- `docs/supervisor_bench/01_rusty_backup_cli_prompt.md` — prompt that
  produced the CLI (for backstory only)

External:
- Inside Macintosh: Files (boot blocks, _Open/_Read/_Write/_Close, ParamBlockRec)
- Inside Macintosh: Operating System Utilities (Start Manager, low-mem globals)
- 68020 PRM (Motorola MC68020 User's Manual), Chapter 6 exception model
- Retro68 README: https://github.com/autc04/Retro68

## 7. Definition of done

For the CPU floppy (the FPU and integration floppies follow the same
template once CPU is green):

1. `make cpu.dsk` produces an 800 KB HFS image.
2. Snow boots `cpu.dsk`, runs to completion (no hangs, no triple
   fault), writes `/Results.jsonl`.
3. `rusty-backup-cli api hfs get cpu.dsk /Results.jsonl …` retrieves
   a JSONL file with 718 lines.
4. `cpu_diff_corpus.py` reports zero unexpected diffs against the MAME
   oracle. Privileged tests now have non-skipped entries; their state
   transitions match MAME byte-for-byte.
5. Same image boots on the FPGA core (or verilator) and on real Mac II
   hardware. (Real hardware is the final gate but can be deferred.)

Update `memory/project_mac_supervisor_bench.md` when the CPU floppy
ships, and again when each subsequent floppy lands.
