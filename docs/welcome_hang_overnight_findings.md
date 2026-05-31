# Welcome-hang overnight diagnostic — findings & handoff

*Branch: `fix-floppy-again`. Run: 2026-05-31 ~01:00-09:15. RBFs:
build #1 `5aeb42b6`, #2 `1ef8d810`, #3 `6e0cc307`, #4 `276ee692`,
#5 (latest) `fd618b80`.*

## TL;DR

The "Welcome to Macintosh" hang is **NOT** a floppy bug. After the
floppy fix (`ac44312`), the IWM byte-stream, the SDRAM read pipeline,
the Sony driver state machine, the track-encoder, and the GCR address
calculation all work correctly on real hardware. byte_cnt grows
steadily, slot_miss_cnt stays at 0, driveTrack steps cleanly through
the disk, and `_Read` calls on the system Params IORB (Mac low-mem
`$3A4`) repeatedly complete with `ioResult = 0` (success).

The hang shows up in **TWO phases**:

| Phase | Duration after Welcome | What's happening | Where it stops |
|------:|-----------------------:|------------------|----------------|
|  1    | ~7 min                 | ~225 disk I/Os via Params ($3A4), driveTrack 34 -> 62, all complete cleanly | When OS transitions to a different IORB |
|  2    | ≥10 min (then HALTED)  | A different IORB at `$0002_1FF6` in low RAM is being polled; no further I/Os, no floppy activity, no screen change | Truly stopped — needs further investigation |

So whatever is at the post-floppy phase (likely an INIT-load step, a
SCSI Manager bus scan, or a System-extension init) is the real
blocker. The floppy diagnostics built tonight prove this conclusively.

## What was built tonight (5 RBFs)

Every build was a probe-only change. The user RTL behaviour is unchanged.

### Build #1 — PFLP / PIWM (saturating counters)
- `rtl/floppy.v`: `dbg_byte_cnt`, `dbg_miss_cnt`, `dbg_disk_image_data` outputs.
- `rtl/iwm.v`: `dbg_dsk_ack_cnt`, `dbg_read_data_latch`, `dbg_arm_delay_high` outputs + pass-throughs.
- `rtl/dbg_min.sv`: PFLP probe (byte_cnt + miss_cnt), PIWM probe (ack_cnt + live latch + arm-delay-hi + staged flag). PMSE disabled to keep ALM budget.

**Result.** byte_cnt saturated at `0xFFFF` within 1 s — diagnostic
limited. But confirmed `slot_miss_cnt = 0`, `staged = 1`, and the
latch occasionally shows `0xFC` (bit7=1 = byte-available). Floppy
delivery pipeline is HEALTHY.

### Build #2 — wrapping counters + PIOA (IORB address capture)
- Counters changed to wrap on overflow.
- New PIOA probe: captures the first bus address after `cpuAddr == 0x40006C36` (the IOWait poll instruction).

**Result.** PIOA captured `0x40006C38` — wrong; that's the IF of the
*following* `bgt`. The 68020's prefetcher inserts extra IFs before
the DF at `(a0+0x10)`.

### Build #3 — fixed PIOA filter (skip ROM) + PIOC iter counter
- PIOA now captures only non-ROM addresses (`cpuAddr[31:28] != 4'h4`).
- New PIOC probe: counts entries into PC=`0x40006C36` (IOWait iterations).

**Result.** PIOA reliably captured `0x000003B4` -> IORB at
`0x000003A4` = Mac low-mem `Params` (per
`docs/external/mac_lowmem_osdata.html`). PIOC showed iter_cnt
wrapping 16-bit between samples (~1 M iterations/sec — IOWait
actively spinning).

### Build #4 — PFLT (driveTrack, driveSide, step_cnt)
- `rtl/floppy.v`: new `dbg_drive_track`, `dbg_drive_side`, `dbg_step_cnt` outputs.
- Wired through iwm.v, dataController_top.sv, LBMacTwo.sv.
- `rtl/dbg_min.sv`: PFLT probe.

**Result.** Across captures: driveTrack 34 -> 47 -> 58 over 70 s,
step_cnt 108 -> 225 -> 260 (152 step writes), driveSide toggling
0/1. Sony driver IS progressing through the disk, not stuck on one
track. Floppy emulation works.

### Build #5 — PIR1 (writes to $3B4 ioResult)
- `LBMacTwo.sv`: wire `cpuDataOut` into dbg_min.
- `rtl/dbg_min.sv`: PIR1 probe — counts writes to address `$0000_03B4`, captures the last-written value.

**Result — DEFINITIVE.** 
- 6 min after boot: `write_cnt = 165`, `last_value = 0x0001`. The OS
  is repeatedly writing `ioResult` — driver IS completing I/Os.
- After 7 min: `write_cnt = 449`, `last_value = 0x0000` (success).
  PIOA now shows IORB at `0x21FF6` (different IORB!). The Params
  IORB phase is OVER — OS moved on. 
- 3 minutes later AND 4 minutes later: write_cnt **frozen at 449**,
  IORB still at `0x21FF6`, driveTrack frozen at 22, step_cnt frozen
  at 596, byte_cnt frozen at 43316. **Hard halt.**

CPU is still executing (PCs vary across 0x007FEA00, 0x00022006,
0x007CC970, 0x002F3A30) but no disk activity and no progress on the
IORB at `$21FF6`.

## Static facts now known

- Mac II ROM `IOWait` body: `move.w $10(a0),d0 ; bgt.b $-4` at
  `0x40006C36`. The IOWait spins as expected — it's the OS's
  synchronous I/O completion polling primitive.
- `0x4002DF00-0x4002DF7F` is the Sony driver IWM-register poke
  routine. Reads `$200(a0)`, `$600(a0)`, `$800(a0)`, `$A00(a0)`,
  `$0(a0)`, `$400(a0)` — all IWM registers at `$200` spacing —
  plus `bset/bclr` at `$1E00(a2) = VIA1 ORA bit 5` (PA5).
- `$3A4 = Params` (system parameter block, lowmem.html)
- `$1D4 = VIA`, `$1E0 = IWM`, `$134 = SonyVars`
- The "Welcome" hang is INDEPENDENT of floppy: the floppy works,
  the OS reads it, completes 200+ I/Os, then moves on.

## What's open

**The OS hangs at IORB `$21FF6` after the boot-loader phase.** This
IORB is in low RAM (allocated by System file or a driver). It is
NOT the Params IORB. The driver this IORB targets never sets its
`ioResult`.

Probable candidates (based on the call-out from prior work, see
`docs/bootproblems.md`):

1. **AppleTalk / SCC init.** Mac II ROM runs LocalTalk self-test if
   XPRAM SPConfig says async on both ports. We supposedly fixed the
   SPValid bytes (per `docs/bootproblems.md`), but maybe a fresh
   regression with Boot712.dsk's System.
2. **SCSI Manager bus scan.** The SCSI ICR remained sticky at
   `out_en=1 SEL=1 data=0xA0` (selecting ID5) the entire test —
   that is the SCSI driver mid-selection of a non-existent target.
   If the SCSI driver's selection-timeout depends on something
   (VIA timer? cycle count?) that doesn't fire correctly on our
   FPGA, the scan never returns.
3. **ASC Sound Manager.** `asc_irq_cnt = 0` and `cpu_writes = 56565`
   — the ASC never asserts its refill IRQ on our chip
   (`rtl/asc.sv` only sets `asc_fifo_irq` when `asc_mode == 8'h01`).
   If the Sound Manager polls `$50F14804` waiting for non-zero, it
   could hang.
4. **A System INIT** — Boot712.dsk's System Folder contains INITs
   that run after Welcome. One of them hits hardware that doesn't
   respond on our emulation.

## Suggested next steps (when user resumes)

### Highest-leverage probe (build #6 candidate)

Add a probe that captures the **dynamic IORB**. PIR1 only watches
the fixed Params address; the OS is now polling a different IORB.
A generalized "IORB ioResult write watcher" would:

- Track `a0+0x10` from the C36 fetch (PIOA already does this).
- Watch for *any* write to that exact captured address.
- Count writes + capture last value.

That tells us whether the `$21FF6` IORB ever completes.

### Probable fixes to try (any order)

- **ASC refill IRQ in any mode.** Modify `rtl/asc.sv` so
  `asc_fifo_irq[0]` reflects `fifo_a_count < 512` regardless of
  `asc_mode`. Safe-ish — read of `$804` already clears.
- **SCSI selection auto-timeout.** Modify `rtl/scsi.v` so the
  module presents a "no target" status after the host has held
  `ICR.SEL` and `ICR.OE` asserted with no `target_mounted` for
  ~250 ms equivalent in clk_sys. (Be careful — must NOT trip
  iotest with a real target.)
- **Verify XPRAM SPConfig** byte. Re-check `rtl/rtc.v` against
  `docs/bootproblems.md` "SCC Channel A RR0 Polling at $408032AC:
  RESOLVED" section — make sure the SPValid magic bytes are still
  `0x4D 63 A8` and that the Boot712 System actually honors them.

### Reproducing the captures

The raw probe captures + screenshots that produced the numbers
quoted above are NOT checked in (they live under the gitignored
`scratch/hang_capture/` and are trivial to regenerate). To reproduce
on the current RBF:

```bash
bash scripts/deploy_test_floppy.sh
ls -t scratch/hang_capture/ | head -1   # the freshest run
```

A 10-minute soak after Welcome appears (just `for i in {1..10}; do
sleep 60; curl -s -X POST "$HTTP/api/screenshots"; done`) showed
every screenshot byte-identical (md5
`fe97a2de21b27882926dfb14ea907b90`) — proof no visual progress
even given that much wall time.
