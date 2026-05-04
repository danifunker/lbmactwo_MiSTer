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

ASC and the first IWM/floppy handshake are not the leading suspects. With the
matched `m2hires` card, MAME reaches low-memory/OS code by its frame 300, while
Verilator is still in ROM delay/probe code at its frame 300. Direct frame numbers
are only landmarks because the Verilator stop frame follows the internal video
timer and MAME's visible screen is the NuBus card.

The current leading suspect is CPU progress versus VIA/video time: clock enables,
DTACK/wait-state behavior, or bus-slot timing. Prefer comparing PC and low-memory
tick `$016A` at the same tick value instead of only at the same nominal frame.
