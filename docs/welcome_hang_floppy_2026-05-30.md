# "Welcome to Macintosh" hang — floppy boot (Boot712.dsk) investigation

*Branch: `fix-floppy-again`. Last shipped RBF: `output_files/LBMacTwo.rbf`
md5 `fa81bd24...` (commit `ac44312`, 2026-05-30 22:02).*

## Reproduction (hardware, OSD)
1. Cold-load core: `POST /api/launch {"path":"_Unstable/LBMacTwo.rbf"}` after
   removing `/media/fat/config/LBMacTwo.s0` so no images are pre-mounted.
2. Open OSD once (`kbd:osd`), `kbd:confirm` on F1 ("Mount Pri Floppy"),
   `kbd:left` (top of file picker = `..`), `kbd:down` (Boot712.dsk),
   `kbd:confirm` (mount). OSD auto-closes.
3. Chime sounds, the gray box appears, "Welcome to Macintosh." renders, then
   the screen freezes — no progress to desktop after >2 minutes.
   Screenshot md5 of the frozen frame: `fe97a2de21b27882926dfb14ea907b90`.

This matches the user's prior runs (`20260530_220951-Boot712.png` and
`20260530_221319-Boot712.png` from the same RBF, both byte-identical).

The same hang happens booting from a SCSI HDD alone (per user) — the floppy fix
commit (`ac44312`) explicitly notes:

> Mac OS boot from Disk Tools.dsk now passes chime + Welcome but hangs in the
> same place as SCSI Mac OS boot — that hang is pre-existing and not
> floppy-related.

## What the JTAG probes show

`quartus_stp_tcl -t scripts/cpu_state.tcl` while hung (60+ s into Welcome):

- `vbl_irq_count` keeps climbing (~60 Hz). VBL interrupts are firing,
  the OS is dispatching them, ADB mouse + keyboard polls are saturated
  (`last_cmd` alternates 0x2C/0x3C — Talk Reg 0 on the keyboard and mouse).
  **The OS is alive, not crashed.**
- `selROM=1` and ROM PC oscillates among several ROM hot spots. The two
  loops we hit repeatedly:
  - `0x40006C36-3A` — `move.w $10(a0),d0 ; bgt.b $-4` — Mac OS **`IOWait`**
    (Device Manager waiting on `ioResult` of an IORB to drop to ≤ 0).
  - `0x4002E936-38` — `move.b (a4),d3 ; bpl.b $-4` — **IWM byte-ready poll**:
    the Sony/IWM driver reads the IWM data register and waits for bit 7
    (high byte) to indicate a fresh decoded GCR byte. The ROM also has
    the same shape at `0x4002E906-08` (the second-half nibble loop).
- `SCSI: NCR@ID6/5 sel: out_en=1 SEL=1 ICR.ADB=1 data_bus=0xA0
  target_mounted=0x0` — the host has SEL asserted, data lines driving the
  ID 5/7 select pattern, no FPGA target mounted (we only mounted floppy).
  `target_bsy=0x0`, `phase=IDLE` on both targets, `BERR count` not advancing.
  Selection is in flight but uneventful; this is not the spinning loop.

## Localization

These two PCs alone fingerprint the hang as a **floppy read that never
completes after Welcome**:

1. The .Sony driver issued a sector read via `_Read`, returned `ioPosted`,
   and the trap dispatcher fell into `IOWait` at `0x40006C36` polling the
   IORB at register `a0`.
2. Meanwhile, the actual byte-pump (`0x4002E936`) is spinning waiting for
   the IWM to deliver another byte. If the IWM stops asserting bit 7 of
   its data register, the GCR decoder cannot make progress and the
   sector read never completes.

The IORB lives somewhere in the `0x00021FF0` / `0x007FE9F0` neighborhood
(those addresses dominated the PADR histogram during the hang as the
likely `a0+0x10` data fetches). We did not dump the IORB contents — that
would need an additional JTAG probe of register `a0` and an SDRAM read
path (one option: add a new probe to `rtl/dbg_min.sv` that captures
`a_reg[0]` of the TG68 when `PADR == 0x40006C36`).

## Why the floppy stops feeding bytes — the suspect

`rtl/floppy.v` byte-delivery handshake (lines 193–251) uses
`diskImageData != 0` as the "fresh byte" sentinel:

```verilog
if (diskDataByteTimer == 0 && readyToAdvanceHead && diskImageData != 0 &&
    driveReadDataSelected && _enable == 1'b0) begin
    diskDataIn       <= diskImageData;
    newByteReady     <= 1;
    diskDataByteTimer<= 1;
    diskImageData    <= 0;                 // mark as consumed
    readyToAdvanceHead <= 1'b1;
end else begin
    diskDataByteTimer <= diskDataByteTimer + 1'b1;
    newByteReady      <= 1'b0;
    if (dskReadAck) diskImageData <= dskReadDataEnc;
    if (advanceDriveHead) readyToAdvanceHead <= 1'b1;
end
```

In normal operation that is fine — `floppy_track_encoder` emits only GCR
codewords in the range `$96..$FF` (all with bit 7 set), so a value of
zero unambiguously means "byte already consumed, not yet refilled by
SDRAM". The handshake breaks only if **`dskReadAck` does not arrive
inside the 128-cep byte slot**, which leaves `diskImageData = 0` when the
timer wraps. The Mac OS sees no fresh byte (bit 7 still 0), and the
`bpl $-4` loop at `0x4002E938` spins.

This is consistent with the floppy fix commit's iotest evidence: small
reads pass at real-time rate, but **`Mac OS boot ... hangs in the same
place as SCSI Mac OS boot`** — that is, the same kind of pacing race
the SCSI multi-block path also tripped over (see
`docs/scsi-multiblock-handshake.md`).

Plausible reasons `dskReadAck` would skip a slot:

- SDRAM arbiter starves the IWM read port behind a video VRAM fetch or
  HPS sd_buff cycle, especially when video, ASC, and CPU are all
  fighting for the bus during INIT-load.
- `cep` / `cen` phase relative to the busPhase boundary — floppy fix #3
  retuned `ce_p_div2` to land at T3 to fix the *stale-byte* race, but a
  slow grant from the arbiter can still leave a slot unrefilled even
  with correct phases.
- The track encoder enters `STATE_WAIT` between sectors and stops
  requesting bytes — but its output during WAIT defaults to `$FF`, which
  *should* still satisfy the `!= 0` sentinel; worth confirming on the
  scope.

## What was tried while debugging

- Mounted Boot712.dsk via MGL `type="f" index="1"`: hung at the
  question-mark "no disk" icon (different bug — likely cold-boot SCSI
  scan timing, the floppy may not be visible yet to the driver when
  it's hot-mounted right after RBF load). OSD mount works; MGL-only
  mount does not.
- Mounted Boot712 + HDD via MGL: also failed (question mark). Per user
  guidance, the proper workflow is **OSD mount only** for this core.
- Disassembled the boot ROM at the hot PCs with capstone (m68k 020 mode)
  to identify the two spin loops above.
- Did **not** rebuild the bitstream. A targeted next probe would be
  worth a build:
  - Add `PIOA` to `rtl/dbg_min.sv` — capture TG68K `A0` register when
    `cpu_addr == 0x40006C36`. Reveals which IORB is being waited on.
  - Add a 16-bit `wr_strobes` / `rd_grants` counter to floppy.v so we
    can see if `dskReadAck` is missing slots on hardware.

## Quick next steps

1. **Hypothesis-testing build** — add a `diskImageValid` register to
   `rtl/floppy.v` (separate the "fresh byte" flag from the data value)
   and treat any byte (including 0) as valid once `dskReadAck` arrives.
   This narrows the variable: if the hang persists, it's not the
   sentinel, it's missed `dskReadAck` grants.
2. **Arbiter starvation probe** — add a counter to the SDRAM arbiter
   that increments every time a floppy read is **deferred** more than
   one busCycle. Read via JTAG to confirm/deny starvation.
3. **Compare with macplus-og** — macplus_MiSTer boots fine from the
   same Boot712.dsk in MAME. Diff the IWM/floppy SDRAM read pacing
   against ours.

## Repro script

```bash
# 1. Clean state on the MiSTer
ssh -i ~/.ssh/mister_only root@192.168.99.143 \
    "rm -f /media/fat/config/LBMacTwo.s0"

# 2. Cold-load the core
curl -s -X POST -H 'Content-Type: application/json' \
    -d '{"path":"_Unstable/LBMacTwo.rbf"}' \
    http://192.168.99.143:8182/api/launch
sleep 4

# 3. Mount Boot712.dsk via OSD (one osd press, then confirm/left/down/confirm)
python scripts/mister_ws.py --delay 0.5 \
    osd sleep:1 confirm sleep:1 left sleep:0.4 down sleep:0.4 confirm

# 4. Wait, then read JTAG state at the hang
sleep 30
quartus_stp_tcl -t scripts/cpu_state.tcl
```
