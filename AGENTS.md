# Repository Instructions

## Scope

These instructions apply to the whole repository.

## Workflow

- Keep work on the newest active branch for this effort. Check `git status --short --branch` before committing.
- Do not check in the local MAME checkout, ROM zips, disk images, generated simulator logs, screenshots, or build outputs.
- Use `rg`/`rg --files` for code search.
- Prefer small commits that leave the boot-debug state reproducible.

## Verilator

Build from `verilator/`:

```sh
make
```

Run the current direct floppy comparison from `verilator/`:

```sh
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --floppy0 ../releases/Disk605.dsk --stop-at-frame 300
```

Use `--periph-debug` only for short focused runs; it writes `verilator/periph_debug.log`.
Generated logs such as `cpu_trace.log`, `via_debug.log`, `periph_debug.log`,
`ram_debug.log`, and temporary `sim_*.log` files should stay untracked.
Use `--scsi-debug` for focused NCR5380 transaction traces and
`--nubus-video-full-debug` only when the VRAM/register/RAMDAC write stream is
needed; both write to stderr and can be noisy on long runs.

## MAME Reference Runs

Use the local ignored checkout at `mame/`. Do not use plain `./mame macii` for
video-card comparisons: MAME's default slot layout installs `mdc824` in slot 9,
while this core models the Apple Macintosh II High Resolution Video Card in slot
E. Match the core by removing slot 9 and installing `m2hires` in slot E:

```sh
cd mame
SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_frame_probe.lua
```

For frame-limited probes, pass `MAME_STOP_FRAME` and related probe environment
variables before the command, for example:

```sh
MAME_FRAME_INTERVAL=20 MAME_STOP_FRAME=120 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_frame_probe.lua
```

For register snapshots around a ROM PC range, use:

```sh
MAME_MIN_FRAME=260 MAME_FRAME_INTERVAL=20 MAME_STOP_FRAME=520 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -scsi:6 "" -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_pc_region_probe.lua
```

For the current ROM wait-helper comparison, use the same card and no default
SCSI hard disk:

```sh
MAME_STOP_FRAME=900 MAME_FRAME_INTERVAL=80 MAME_MAX_PRINT=160 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -scsi:6 "" -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_wait_probe.lua
```

The local MAME ROM setup expected for the matched card is:

- Mac II system ROM in `mame/roms/macii.zip`.
- High Resolution Video Card declaration ROM at `mame/roms/nb_m2hr/341-0660.bin`.
- `releases/341-0660.bin` / `releases/boot1.rom` should match SHA1
  `37c59f38ae34021d0cb86c2e76a598b7e6077c0d`.

## Current Debug Focus

The latest fixed divergence is VIA read-lane mirroring during the Mac II RAM
banking probe. MAME mirrors byte-wide VIA/VIA2 reads onto both 68000 byte lanes.
The FPGA now does the same; otherwise the ROM reads VIA2 ORA as `$3FEF`, writes
`$EF` back, drives PA7:6 to `11`, and later selects the invalid `$04000000`
RAM-test table entry.

The RAM sizing probe should now read VIA2 as `$3F3F`, leave ORA at `$3F`, load
`A2=$00100000`, set `D7=4`, and return from the pattern test with `D6=0`.
Verilator also takes the normal ASC path (`$408000D0 -> $40805E4A`, `D7=2`),
so ASC is not the current blocker.

The current focus is post-ASC visible boot progress. Matched MAME reaches the
`$40826Cxx` neighborhood around frame 280; Verilator reaches `$40826CCA` at
frame 300, but the screenshot is still vertical stripes with no cursor. Next
comparisons should focus on the video/NuBus/SCSI path after the fixed RAM and
ASC milestones.
