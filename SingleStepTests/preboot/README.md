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

**Read-only vs full mode (`IOTEST_MODE`).** Each size test has two
phases:

1. **READ** — `_Read` `s->length` bytes from `/Read_<label>` into the
   I/O buffer at `IOBUF_BASE` ($200000). Timed via VIA1 T2.
2. **WRITE + READBACK-VERIFY** — fill the buffer with a pattern,
   `_Write` it to `/Write_<label>`, clear the buffer, `_Read` it back,
   memcmp. Three trap invocations per size, two of them timed.

`IOTEST_MODE` selects which phases get compiled in:

| Value | Phases | When to use |
|---|---|---|
| `read` (default) | READ only | Isolate the SCSI/Sony read path before introducing write complexity. The bench loops over the size table doing just one `_Read` per size. |
| `full` | READ + WRITE + VERIFY | After read is verified working. Emits a `"write"` JSONL record per size with `verified:0/1`. |

```bash
# Read-only (default):
make
./build_hda.sh

# Full:
rm -rf build         # IOTEST_MODE isn't a Make dependency, so clean first
make IOTEST_MODE=full
./build_hda.sh
```

Make rejects any other `IOTEST_MODE` value with a clear error. The
build is **single-binary** — there's no separate read-only/full
output filename; rebuild whichever variant you want and run the
build script again.

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

Everything paints in **1 bpp** through the Mac II built-in ScrnBase
(`$0824`). The kernel (`common/display/display_1bpp.c`) handles every
Mac II display path the FPGA core supports — what differs between
cards is the **row stride**, which each card's declaration ROM
programs into the TFB / CRTC at boot.

| Card | Row stride (1 bpp) | Notes |
|---|---:|---|
| **Toby** (Mac II Video Card, 342-0008-a) | 80 | 1 bpp only, exact 640-px buffer |
| **Apple Macintosh II High Resolution Card (m2hires)** | **128** | 1024-px-wide buffer, only first 640 visible; supports 1/2/4/8 bpp but powers up in 1 bpp |
| **Apple Macintosh Display Card 8•24 (mdc824)** | 80 | Powers up in 1 bpp via its 68008 coprocessor; supports up to 24 bpp |

The stride is **not derivable at runtime** from low-mem — we have to
match what the card's declaration ROM picked. Mismatched stride is
the easiest-to-misdiagnose bug in this tree: text fragments across
the top of the screen with characters spread horizontally because
each row of an 8-row glyph lands on a different physical scanline.

**Select the target card at build time via `VIDEO_VARIANT`:**

```bash
make                              # m2hires (default — matches current FPGA core)
make VIDEO_VARIANT=mdc824
make VIDEO_VARIANT=toby
```

`common/make/common.mk` translates the variant into `-DROW_BYTES=N`
(for C) and `--defsym ROW_BYTES=N` (for gas). Each `.s` file gates
its fallback default behind `.ifndef ROW_BYTES / ... / .endif` so
direct AS invocations without the Makefile still assemble. Adding a
new card means appending a case to the `ifeq` cascade in `common.mk`.

Higher color depths (2/4/8 bpp) require writing the card's control
registers first (m2hires: TFB MISC; mdc824: 68008 mailbox command).
The 8 bpp paint kernel + matching boot stub are parked under
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

## MAME integration

MAME's `macii` machine emulates the exact NuBus video cards our FPGA
core targets, and can run headlessly to take screenshots of the
emulated Mac display — so you can diagnose display issues, dump VRAM,
and trace device-register writes without needing access to physical
hardware. This is the workflow that found the m2hires `ROW_BYTES=128`
stride bug above.

### Prerequisites

- **MAME built locally** at `~/repos/mame/mame` (sibling checkout of
  this repo). Any recent MAME version with the macii driver works;
  `mame0287` is what was used for the m2hires diagnosis.
- **Mac II ROMs** at `~/repos/mame/roms/macii.zip`. The `-listroms macii`
  command lists what's expected.
- **m2hires declaration ROM** at `~/repos/mame/roms/nb_m2hr/341-0660.bin`.
  A copy is in this repo:
  ```bash
  mkdir -p ~/repos/mame/roms/nb_m2hr
  cp ~/repos/lbmactwo_MiSTer/releases/341-0660.bin ~/repos/mame/roms/nb_m2hr/
  ```
  Without this, the `-nb9 m2hires` invocation fails with
  `341-0660.bin NOT FOUND`.

### Headless invocation

MAME normally needs an X display. With SDL2 we can use the **offscreen
video driver** to run without any host display, while still rendering
the emulated Mac screen and saving snapshots to PNG:

```bash
cd ~/repos/mame
SDL_VIDEODRIVER=offscreen ./mame macii \
    -skip_gameinfo \
    -nb9 m2hires \
    -hard1 /tmp/iotest.hda \
    -snapname iotest_%i \
    -snapsize 640x480 \
    -snapshot_directory /tmp/mame_snap \
    -nothrottle \
    -seconds_to_run 30 \
    -window
```

Flags worth knowing:

| Flag | What it does |
|---|---|
| `SDL_VIDEODRIVER=offscreen` | renders to an in-memory framebuffer; no X needed |
| `-skip_gameinfo` | skip MAME's "press OK" warning screen; otherwise the autosnapshot captures it instead of the emulated display |
| `-nb9 <card>` | install card in NuBus slot 9 (default is `mdc824`; use `m2hires` to match our FPGA core) |
| `-hard1 path/to.hda` | SCSI HDD on the first channel |
| `-flop1 path/to.dsk` | Floppy disk in the internal drive (use for `iotest.dsk` etc.) |
| `-snapsize 640x480` | match the visible area exactly so the output PNG isn't padded |
| `-snapshot_directory dir` | where to write the PNG. Default `snap/` is relative to CWD. |
| `-nothrottle` | run as fast as host CPU allows (~4× real-time on a modern laptop) |
| `-seconds_to_run N` | exit after N **emulated** seconds; the auto-snapshot fires at exit |
| `-window` | required even with offscreen driver |
| `-autoboot_script foo.lua` | inject a Lua script that runs once emulation starts |

### Which card to test against

The MAME `macii` machine **defaults to mdc824 in slot 9** — not what
the FPGA core has. Always pass `-nb9 m2hires` to match the FPGA's
actual card (or `-nb9 mdc824` explicitly if you want to test the
mdc824 path).

`./mame macii -listslots` shows the full list of cards installable
in any slot if you need to experiment with others.

### Probing device internals via Lua

MAME's Lua API can:
- Read CPU memory at any address (`prog:read_u8/u16/u32`).
- Install **write taps** to log every CPU write to a memory range —
  including writes to memory-mapped device registers like the m2hires
  TFB at `$F9080000-$F908FFFF`.
- Schedule actions at specific emulated times (`emu.register_periodic`
  with an `emu.time()` check).

Example: trace what the m2hires declaration ROM programs into the
TFB registers during boot. Save as `/tmp/snoop_m2hires.lua`:

```lua
local prog = manager.machine.devices[":maincpu"].spaces["program"]

prog:install_write_tap(0xF9080000, 0xF9080FFF, "m2hires_reg_w",
    function(offset, data, mask)
        local reg_idx = (offset & 0xFF) >> 2
        print(string.format("[t=%.2f] m2hires reg %d <= 0x%08X (mask 0x%08X)",
                            emu.time(), reg_idx, data, mask))
    end)
print("m2hires register-write tap installed")
```

Run with `-autoboot_script /tmp/snoop_m2hires.lua` and grep stdout
for `reg write`. The captured values are the **CPU-side** writes;
MAME's `m2hires::registers_w` applies `data ^= 0xFFFFFFFF; data =
swapendian_int32(data)` before storing, so e.g. CPU `0xDFFFFFFF` →
`m_registers[LENGTH] = 32` → stride = 32 × 4 = **128 bytes**.

Example: dump VRAM at the current `ScrnBase` to verify your paint
code wrote the bytes you expected. Save as `/tmp/dump_vram.lua`:

```lua
local prog = manager.machine.devices[":maincpu"].spaces["program"]
local fired = false
emu.register_periodic(function()
    if fired or emu.time() < 25 then return end
    fired = true
    local sb = prog:read_u32(0x0824)
    print(string.format("ScrnBase=0x%08X", sb))
    for r = 0, 7 do
        local row = {}
        for i = 0, 31 do
            row[i+1] = string.format("%02X", prog:read_u8(sb + r * 80 + i))
        end
        print(string.format("row %d:", r), table.concat(row, " "))
    end
end)
```

Reading via the CPU side gets the XOR'd-back view of VRAM, so the
bytes you see are the bytes your paint code wrote.

### Worked example: the m2hires ROW_BYTES discovery

The whole story is preserved in commit `4a3a75c`. Summary:

1. User reported garbled iotest display on FPGA m2hires hardware.
2. Reproduced the same garbled output in MAME with `-nb9 m2hires`.
3. Same `/tmp/iotest.hda` rendered correctly with default MAME (mdc824) —
   so the payload bytes are fine, the bug is per-card.
4. VRAM dump at `ScrnBase` showed our paint bytes were exactly where
   we wrote them (correct content at offsets `row * 80`), so the paint
   code wasn't writing wrong bytes — the scanout was reading at a
   different stride.
5. Tested several plausible strides (80, 128, 144, 160) against the
   VRAM dump by re-indexing the same memory at different strides;
   stride 128 produced consistent 8-row glyph patterns.
6. Confirmed by snooping TFB register writes — declaration ROM
   wrote `LENGTH=32`, MAME's formula gives 32 × 4 = 128 bytes.
7. Patched ROW_BYTES → 128 → reran in MAME → text renders cleanly.

The `SDL_VIDEODRIVER=offscreen` headless trick made this iteration
cycle ~10 seconds per attempt instead of "boot on physical hardware,
photograph screen, repeat."

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
