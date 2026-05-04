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

The local MAME ROM setup expected for the matched card is:

- Mac II system ROM in `mame/roms/macii.zip`.
- High Resolution Video Card declaration ROM at `mame/roms/nb_m2hr/341-0660.bin`.
- `releases/341-0660.bin` / `releases/boot1.rom` should match SHA1
  `37c59f38ae34021d0cb86c2e76a598b7e6077c0d`.

## Current Debug Focus

ASC, early IWM/floppy, and live SCSI are not the leading suspects. The current
NuBus declaration ROM path has been changed back to MAME's lane-0 layout: MAME
and Verilator should both probe `$FEFFFFFC` and read declaration bytes from
`$FEFF8000`, `$FEFF8004`, etc.

After that lane fix, Verilator reaches the slot/video init path and is still in
ROM Slot Manager delay code by frame 450 (`PC=$40801658`, `$016A=$00000134`).
The noisy probe showed heavy reads of the video card VBL status registers
`$FE090010/$FE090012`, so the next suspect is NuBus video VBL/status/IRQ
behavior rather than ASC, IWM, or SCSI.
