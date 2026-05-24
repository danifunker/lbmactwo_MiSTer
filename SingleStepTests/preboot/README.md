# preboot/ — Mac II pre-OS test kit

Benches that run **before Mac OS boots**. Each bench produces a flat
boot block + freestanding payload pair that the Mac II ROM loads from
disk (floppy or SCSI HDA) and executes in supervisor mode. No Toolbox,
no Memory Manager, no Finder — just a payload that drives the hardware
directly and writes JSONL results back to disk for the host to read.

For Mac OS apps (CpuBench, FpuBench, CpuFpuBench), see
`SingleStepTests/macos_bench/`. Those run **on top of** Mac OS via
Retro68 and use Toolbox APIs.

## Directory layout

```
preboot/
├── common/                  shared across benches
│   ├── runtime/             freestanding C runtime + linker scripts
│   │   ├── bench_types.h    u8/u16/u32 typedefs
│   │   ├── freestanding.{c,h}
│   │   ├── jsonl_writer.{c,h}
│   │   ├── recovery.s       longjmp-style exception recovery
│   │   ├── exception_handlers.s
│   │   ├── payload.ld       linker script: payload @ 0x40000
│   │   └── boot_stub.ld     linker script: boot block ≤ 1024 bytes
│   ├── boot/
│   │   ├── boot_stub_scsi.s             canonical (PAYLDOFF-patchable)
│   │   ├── boot_stub_scsi_fixed_offset.s historical (hardcoded 0x51600)
│   │   └── boot_stub_floppy.s           floppy boot block
│   ├── display/             paint kernels + framebuffer tools
│   │   ├── display_1bpp.c   active 1 bpp paint (was: font_ascii.c)
│   │   ├── diagnostics/     hardware-probe boot stubs
│   │   │   ├── boot_stub_minimal.s      "is boot path alive" probe
│   │   │   ├── boot_stub_probe.s        4-stripe polarity probe
│   │   │   ├── boot_stub_calibrate.s    200x200 stride ruler
│   │   │   ├── boot_stub_strides.s      4-stride bracket
│   │   │   └── build_probe.sh           one-shot probe disk builder
│   │   └── old/             deferred 8 bpp scaffolding (needs depth-switch init)
│   ├── tools/
│   │   ├── patch_offsets.py             writes file offsets into binaries
│   │   ├── raw_to_dc42.py               wrap raw disk image as Disk Copy 4.2
│   │   └── old/patch_results_offset.py  legacy single-offset patcher
│   └── make/common.mk        toolchain + paths included by every bench Makefile
├── supervisor_bench/         CPU / FPU instruction-correctness tests
│   ├── bench_main.c          test runner + JSONL emitter
│   (test corpora cpu_tests.h / fpu_tests.h are included
│    via relative path from gen/ — see bench_main.c)
│   ├── variant_cpu_scsi.s    SCSI-medium glue
│   ├── payload_entry_cpu.s   bench-specific entry shim
│   ├── build_cpu_scsi.sh     image build (uses legacy api hfs verbs)
│   ├── build_image*.sh       skeleton image builders
│   └── Makefile              includes ../common/make/common.mk
└── iotest/                   disk-I/O timing bench
    ├── diskio_main.c         per-size read/write/verify loop
    ├── sizes.{c,h}           size table (HDA: 12 sizes, DSK: 8 sizes)
    ├── timing.{c,h}          VIA1 T2 microsecond timer
    ├── payload_entry.s       bench-specific entry shim
    ├── build_hda.sh          image build (uses flat rb-cli verbs)
    ├── build_dsk.sh          image build (uses flat rb-cli verbs)
    └── Makefile              includes ../common/make/common.mk
```

## Toolchain

Builds use the **Retro68 cross-compiler**. Install location is set in
`common/make/common.mk`; override from the environment if yours is
elsewhere:

```bash
export RETRO68=/path/to/Retro68-build/toolchain
```

Required binaries: `m68k-apple-macos-gcc`, `as`, `ld`, `objcopy`. The
default path is `$HOME/repos/Retro68-build/toolchain/bin/`.

Disk-image manipulation uses **rb-cli** (rusty-backup):

```bash
export RB=$HOME/repos/rusty-backup/target/release/rb-cli
```

iotest scripts use the flat verbs (`put`, `locate`, `--print-offset`).
supervisor_bench scripts still use the deprecated `api hfs *` namespace
— migrating is a follow-up task.

## Building

### iotest (disk-I/O timing)

```bash
cd preboot/iotest
make hda             # produces build/payload_iotest_hda.bin + boot_stub.bin
make dsk             # produces build/payload_iotest_dsk.bin + boot_stub.bin
./build_hda.sh       # assembles /tmp/iotest.hda (APM, 12 sizes 1B..4MB)
./build_dsk.sh       # assembles /tmp/iotest.dsk (800 KB HFS, 8 sizes 1B..128KB)
```

`build_hda.sh` accepts a template HDA as its first arg (default
`~/testdisk.hda`). The output HDA is APM-wrapped with Apple_HFS at
partition 1. `build_dsk.sh` creates a fresh 800 KB HFS floppy from
scratch.

### supervisor_bench (CPU / FPU correctness)

```bash
cd preboot/supervisor_bench
make cpu_scsi        # production: boot_stub_scsi.bin + payload_cpu_scsi.bin
make all             # skeleton boot + payload
make scsi            # skeleton SCSI variant
make minimal         # diagnostic: "is boot path alive"
make probe           # diagnostic: framebuffer polarity (4 stripes)
make calibrate       # diagnostic: stride ruler (200×200 square)
make strides         # diagnostic: 4 strides bracketed
./build_cpu_scsi.sh  # assembles the SCSI CPU bench HDA
```

The `make cpu_scsi_8bpp` target also exists but is **deferred** — it
compiles successfully but the resulting payload won't render on
hardware until depth-switch init code is written (see
`common/display/old/` headers for details).

## Display modes

Today everything paints in **1 bpp** through the Mac II built-in
ScrnBase (`$0824`). The default kernel
(`common/display/display_1bpp.c`) works on every Mac II display path
the FPGA core supports:

- **Toby** (Mac II Video Card, 342-0008-a) — 1 bpp only, exact match.
- **Apple Macintosh II High Resolution Card (m2hires)** — supports
  1/2/4/8 bpp; powers up in 1 bpp.
- **Apple Macintosh Display Card 8•24 (mdc824)** — supports
  1/2/4/8/24 bpp; powers up in 1 bpp via its 68008 coprocessor.

None of those require card-specific code in our paint path because
we read `ScrnBase` from low-mem rather than poking the card directly.
Higher color depths require writing the card's control registers
(m2hires: TFB MISC; mdc824: 68008 mailbox command). The 8 bpp paint
kernel and matching boot stub are parked under
`common/display/old/` until that init code is written; they assemble
fine but produce garbage on hardware until paired with depth-switch.

The **diagnostic boot stubs** under `common/display/diagnostics/`
exist to characterize an unfamiliar card or to confirm a card change
didn't break things. Workflow:

1. `make probe` from supervisor_bench/ — boot the resulting disk.
   Stripes should render dark-to-light L→R (`$00`=black, `$FF`=white)
   in standard polarity, or inverted on Mac-default ScrnBase polarity.
2. `make calibrate` — boot the resulting disk. A clean 200×200 square
   means stride is right; a parallelogram with N pixels of drift per
   row means real stride = assumed (640) + N.
3. `make strides` — paints 4 small squares at strides 640/832/1024/1280.
   The clean one tells you the actual stride in one shot.

## Patching offsets into built artifacts

The boot stub and payload both contain offsets that aren't known
until the image is assembled (`/Payload` byte offset in the boot
stub, `/Results.jsonl` byte offset and per-size read/write offsets
in the payload). Build scripts patch them post-link using
`common/tools/patch_offsets.py`:

```bash
common/tools/patch_offsets.py IMAGE \
    --payload-offset 0xXXXX \
    --results-offset 0xXXXX \
    --reads  1B=0x..,512B=0x.. \
    --writes 1B=0x..,512B=0x.. \
    --labels-order 1B,512B,...
```

iotest's build scripts handle this automatically via `rb-cli locate
IMG[@N] /Path | jq`. The supervisor_bench scripts still use the
older `patch_results_offset.py` (single-offset only) — they'll move
to the unified script when they migrate to flat rb-cli verbs.

## Reading results back

Both benches write JSONL records to `/Results.jsonl` on the booted
disk. After running, extract it host-side with:

```bash
rb-cli get /tmp/iotest.hda@1 /Results.jsonl /tmp/iotest_results.jsonl
```

(or `rb-cli get /tmp/iotest.dsk /Results.jsonl ...` for the floppy
variant — no @N selector for raw HFS).

iotest output format, one line per read or write:

```json
{"size":"1KB","len":1024,"op":"read","us":NNN,"err":0}
{"size":"1KB","len":1024,"op":"write","us":NNN,"err":0,"verified":1,"readback_us":NNN,"readback_err":0}
{"size":"4MB","len":4194304,"op":"skip","reason":"insufficient_ram","mem_top":0xN,"iobuf_base":0x200000}
```

supervisor_bench output: see `bench_main.c`'s emitter and
`SingleStepTests/results/` for the field schema.

## File reorg history

This directory was reorganized on 2026-05-24 from two top-level
directories (`SingleStepTests/supervisor_bench/` and
`SingleStepTests/IOTest/`) into the current `preboot/` tree. The
shared bits (paint kernels, runtime, linker scripts, boot stubs,
diagnostic tools) moved into `common/`. Each moved file's header
comment includes its previous name so a grep against the old layout
still finds the right file.

If you came in looking for any of these old names, here's where to
find them:

| Old path | New path |
|---|---|
| supervisor_bench/font_ascii.c               | common/display/display_1bpp.c |
| supervisor_bench/font_ascii_m2hires.c       | common/display/old/font_ascii_m2hires.c |
| supervisor_bench/boot_stub.s                | common/boot/boot_stub_floppy.s |
| supervisor_bench/boot_stub_scsi.s           | common/boot/boot_stub_scsi_fixed_offset.s |
| supervisor_bench/boot_stub_scsi_m2hires.s   | common/display/old/boot_stub_scsi_m2hires.s |
| supervisor_bench/boot_stub_m2hires_probe.s  | common/display/diagnostics/boot_stub_probe.s |
| supervisor_bench/boot_stub_m2hires_calibrate.s | common/display/diagnostics/boot_stub_calibrate.s |
| supervisor_bench/boot_stub_m2hires_v3.s     | common/display/diagnostics/boot_stub_strides.s |
| supervisor_bench/boot_stub_minimal.s        | common/display/diagnostics/boot_stub_minimal.s |
| supervisor_bench/payload_entry_cpu_m2hires.s | common/display/old/payload_entry_cpu_m2hires.s |
| supervisor_bench/build_cpu_scsi_m2hires.sh  | common/display/old/build_cpu_scsi_m2hires.sh |
| supervisor_bench/build_m2hires_probe.sh     | common/display/diagnostics/build_probe.sh |
| supervisor_bench/{bench_types,freestanding,jsonl_writer}.{c,h} | common/runtime/ |
| supervisor_bench/{recovery,exception_handlers}.s | common/runtime/ |
| supervisor_bench/{payload,boot_stub}.ld     | common/runtime/ |
| supervisor_bench/patch_results_offset.py    | common/tools/old/patch_results_offset.py |
| supervisor_bench/raw_to_dc42.py             | common/tools/raw_to_dc42.py |
| IOTest/boot_stub.s                          | common/boot/boot_stub_scsi.s |
| IOTest/patch_offsets.py                     | common/tools/patch_offsets.py |
| IOTest/{diskio_main,sizes,timing}.{c,h}     | iotest/ |
| IOTest/{build_hda,build_dsk}.sh             | iotest/ |
