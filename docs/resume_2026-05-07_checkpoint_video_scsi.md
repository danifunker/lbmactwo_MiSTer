# Resume: Checkpointing, Boot Progress, Video Next

Timestamp: 2026-05-07 16:49 EDT

## Repo State

Branch:

```text
new-scc-latest...origin/new-scc [ahead 1]
```

Dirty/uncommitted files at handoff:

```text
 M .gitignore
 M AGENTS.md
 M releases/Disk605.dsk
 M verilator/Makefile
 M verilator/sim/sim_clock.cpp
 M verilator/sim/sim_clock.h
 M verilator/sim_main.cpp
?? docs/verilator_checkpointing.md
?? docs/resume_2026-05-07_checkpoint_video_scsi.md
?? releases/boot.vhd
```

Important: `releases/Disk605.dsk` was already modified before the checkpointing
work. Do not accidentally revert or stage it without deciding whether it belongs
in the next commit.

`releases/boot.vhd` was extracted from `releases/empty_hdd.zip` for testing. It
is a 20 MB Apple-partitioned disk image and is currently untracked.

## Native Verilator Checkpointing

Implemented but not committed.

Files changed:

- `verilator/Makefile`
- `verilator/sim_main.cpp`
- `verilator/sim/sim_clock.h`
- `verilator/sim/sim_clock.cpp`
- `.gitignore`
- `AGENTS.md`
- `docs/verilator_checkpointing.md`

Key details:

- `verilator/Makefile` now uses `--savable`.
- `--timing` was removed because Verilator 5.044 rejects `--savable` together
  with `--timing`.
- The default build succeeds with `make` from `verilator/`.
- `sim_main.cpp` now supports:
  - `--save-state <file>`
  - `--save-at-frame <frame>`
  - `--save-at-pc <hex|dec>`
  - `--load-state <file>`
- Checkpoint contents currently include:
  - Verilator model state via `os << *top` / `is >> *top`.
  - `main_time`.
  - `SimClock` current clock, previous clock, and divider count.
  - `SimVideo` frame, line, pixel counters, and framebuffer contents.

Validation performed:

```sh
cd verilator
make
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --save-state ../checkpoints/test_f1.vlt --save-at-frame 1
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --load-state ../checkpoints/test_f1.vlt \
  --save-state ../checkpoints/test_f2_restored.vlt --save-at-frame 2
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --save-state ../checkpoints/test_f2_direct.vlt --save-at-frame 2
```

The restored frame-2 run matched the fresh frame-2 run for time, PC, opcode,
registers, and VIA timer state after adding video line/pixel/framebuffer state.

Temporary checkpoint artifacts were removed. `.gitignore` now ignores
`checkpoints/`, `*.vlt`, and `*.vlt.meta`.

Known checkpoint limitation: C++ block-device helper state is not serialized
yet. No-media checkpoints are reliable. SCSI/floppy checkpoints should only be
trusted when not taken in the middle of an active media transfer.

## Current Boot Status

The user ran the simulator and saw the floppy icon. This is a major milestone:
the ROM is getting through the earlier init/no-media path far enough to display
the normal no-boot-media UI.

That means the previous blockers around ASC/no-media/early hardware init are no
longer the immediate symptom. The current visible problem is that video output
is wrong enough that later boot, Finder, and cursor behavior are hard to judge.

## `boot.vhd` SCSI Test

`boot.vhd` was extracted:

```sh
unzip -o releases/empty_hdd.zip -d releases
```

Sanity checks:

```sh
file releases/boot.vhd
```

Output identifies it as:

```text
Apple Driver Map, blocksize 512, blockcount 41056
contains Apple Partition Map
contains Mac_Volume, type Apple_HFS
```

So it is not a dynamic VHD wrapper for this harness; it looks like raw sector
data with an Apple partition map.

Run performed:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --scsi0 ../releases/boot.vhd \
  --frame-probe --frame-interval 50 --stop-at-frame 700
```

Important output:

```text
disk 0 inserted (../releases/boot.vhd)
Image mounted on target 6, size:      41056
New command on target 6: 08 00 00 00 01 00 00 00 00 00
New command on target 6: 08 00 00 00 01 00 00 00 00 00
New command on target 6: 08 00 00 00 01 00 00 00 00 00
```

That command is SCSI `READ(6)`, LBA 0, length 1 block. The ROM sees the disk and
tries to read it.

At frame 700 the run was still in the ROM SCSI timeout/probe area:

```text
PC=40826CC6 Op=56C9
SCSI state: mr=00 icr=05 tcr=00 odr=82 busdin=00 req=0 tbsy=00 treq=00
t0_phase=0 t0_mnt=1 t0_cnt=0 t0_done=0 t0_ack=0 t0_cmd=0 t0_din=82
```

Interpretation at handoff:

- The image is mounted and target 6 is selected.
- The ROM issues READ(6).
- By the frame-700 stop, target 6 is idle (`t0_phase=0`, `tbsy=00`), while the
  ROM is still in a SCSI probe/timeout path.
- The user later reported seeing the floppy icon even with `boot.vhd`, so the
  ROM did not accept the disk as a bootable startup volume.

Open question:

- Is `boot.vhd` actually blessed/bootable for Mac II System/Finder?
- Or is our SCSI target returning bad/incomplete sector data/status for the
  reads even though the disk mounts?

Quick local string scan did not show obvious `System` or `Finder` strings:

```sh
strings -a releases/boot.vhd | rg -i "System|Finder|Macintosh|Bless|HFS|Apple|Driver|Partition|Desktop"
```

Only driver/partition strings were obvious in the short scan. This suggests the
image might be empty or not a full bootable System volume, but this is not yet
proved.

## Video Is The Recommended Next Focus

The user asked whether to clean up video because it is not drawing correctly.
Current recommendation: yes, fix video next before deeper SCSI boot debugging.

Reason:

- The flashing floppy icon means the ROM has reached a normal UI milestone.
- Bad video makes it hard to determine whether Finder is drawing, whether the
  floppy prompt is truly final, and whether the cursor moves.
- The no-media flashing floppy state is a stable visual regression target.

Suggested next sequence:

1. Use no-media flashing floppy as the baseline.
2. Generate headless screenshots from Verilator at known frames.
3. Generate matched-card MAME screenshots/reference state if possible:
   `-nb9 "" -nbe m2hires -scsi:6 ""`.
4. Compare NuBus video-card register writes, VRAM address/stride, CLUT/RAMDAC,
   pixel packing, and blanking/timing.
5. Fix screenshots first, then SDL display.
6. Once the cursor is visibly correct, test mouse injection:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --send-mouse 520:40,0 --screenshot 500,540 --stop-at-frame 560
```

If the cursor visibly moves between screenshots, the mouse path is probably
working. If not, debug ADB/mouse after video is trustworthy.

## Useful Commands For Resume

Build:

```sh
cd verilator
make
```

No-media visual baseline:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --screenshot 500,540,580 --stop-at-frame 600
```

SCSI `boot.vhd` run:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --scsi0 ../releases/boot.vhd \
  --frame-probe --frame-interval 50 --stop-at-frame 1200
```

Checkpoint at the visible no-media state once a good frame is known:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --save-state ../checkpoints/floppy_icon.vlt --save-at-frame 600
```

Restore and iterate:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --load-state ../checkpoints/floppy_icon.vlt --stop-at-frame 620
```
