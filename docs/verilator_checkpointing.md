# Verilator Checkpointing

The Verilator harness supports native save/restore checkpoints through
Verilator's `--savable` model serialization. The default `verilator/Makefile`
build enables this path and links `verilated_save.cpp`.

## Build

```sh
cd verilator
make
```

Verilator 5.044 does not allow `--savable` together with `--timing`, so the
checkpoint build does not pass `--timing`. The current Verilator target does not
use delay statements that require it.

## Save

Save at a frame boundary:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --save-state ../checkpoints/f120.vlt --save-at-frame 120
```

Save when the CPU fetches a specific debug PC:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --save-state ../checkpoints/pc_408061f2.vlt --save-at-pc 0x408061F2
```

`--save-state <file>` without `--save-at-frame` or `--save-at-pc` saves when an
existing stop condition fires, such as `--stop-at-frame`, `--stop-at-tick`, or a
one-shot debug probe.

Each checkpoint writes a binary `.vlt` file and a text `.vlt.meta` sidecar with
frame, time, PC, opcode, low-memory tick, clock state, and media paths.

## Restore

Restore with the same generated Verilator model/binary and matching media
arguments:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --load-state ../checkpoints/f120.vlt --stop-at-frame 130
```

On restore, the harness skips ROM/floppy ioctl downloads because ROM, NuBus ROM,
RAM, and RTL state come from the checkpoint.

## Current Coverage

The checkpoint stores:

- Verilator model state via `os << *top` / `is >> *top`.
- `main_time`.
- `SimClock` clock, previous-clock, and divider count.
- `SimVideo` frame, line, pixel counters, and framebuffer contents.

This is enough for deterministic no-media boot debug. A smoke test saved at
frame 1, restored, then saved at frame 2; the restored frame-2 snapshot matched
a fresh frame-2 save for time, PC, opcode, registers, and VIA timer state.

## Limits

The C++ block-device helper state is not serialized yet. No-media checkpoints
are safe, and checkpoints between active media transfers are expected to work if
the helper is idle, but SCSI/floppy checkpoints in the middle of an external
read/write transaction need more harness state before they should be treated as
authoritative.

Old checkpoint files are not forward-compatible across RTL changes, Verilator
regeneration, or checkpoint format changes. Recreate them after rebuilding.
