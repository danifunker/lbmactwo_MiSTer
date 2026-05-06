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
  -nb9 "" -nbe m2hires -scsi:6 "" -flop ../releases/Disk605.dsk \
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

For the low-memory delay calibration setup, use:

```sh
MAME_STOP_FRAME=120 MAME_FRAME_INTERVAL=20 MAME_MAX_PRINT=300 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -scsi:6 "" -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_calib_probe.lua
```

The local MAME ROM setup expected for the matched card is:

- Mac II system ROM in `mame/roms/macii.zip`.
- High Resolution Video Card declaration ROM at `mame/roms/nb_m2hr/341-0660.bin`.
- `releases/341-0660.bin` / `releases/boot1.rom` should match SHA1
  `37c59f38ae34021d0cb86c2e76a598b7e6077c0d`.

## Current Debug Focus

RAM sizing, early ASC, and the initial IWM probe now match the matched-card MAME
run closely enough that they are not the current blocker.

For the current no-media baseline, run MAME without a floppy image and with the
same slot-E card:

```sh
MAME_STOP_FRAME=800 MAME_FRAME_INTERVAL=80 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -scsi:6 "" \
  -autoboot_script ../tools/mame/macii_bootvars_probe.lua
```

MAME stays in the no-media drive-queue loop at `PC=$408061F2` with
`$030A=$2F70` and `$2F70.next=0`. Verilator now matches that queue after fixing
the external floppy connector to report no installed drive by default. MAME's
`add_35_nc` external connector uses a `nullptr` default device.

The active no-media failure is after that corrected queue state. Verilator still
leaves the no-media loop and enters the ROM SCSI selection/timeout helper around
`PC=$408268DC-$40826CC6`, while MAME has no SCSI register accesses after the
early frame-67 CSR polling window and remains at `PC=$408061F2` through frame
800. Treat ASC, the fake AppleCD target, and the old phantom external-floppy
queue node as ruled out unless a new trace contradicts that.

The ROM delay calibration mismatch is still real: MAME stores `$0D00=$0A3B` and
`$0DA6=$0417`, while Verilator has been around `$054B/$0196`. Forcing the MAME
constants changes the timing shape but has not made no-media boot match MAME, so
continue comparing the ROM branch state after the drive-queue loop and the
CPU/VIA/bus timing that feeds that decision.
