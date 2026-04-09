# Mac II Boot Sequence — Current Analysis (2026-03-30)

## NuBus Video Card Status: Working Correctly

The NuBus High Resolution Video Card (TFB 2.2 / 341-0660) declaration ROM handling is functional:

- **Declaration ROM**: Fully read by Slot Manager (8210 byte reads on lane 3)
- **Byte-lane format**: De-inverted (XOR $FF) + format byte overridden to `$78` (lane 3, non-inverted). This matches MAME's `install_declaration_rom()` behavior.
- **sResource directory**: Parses correctly. First 16 de-inverted bytes = `01 00 00 2C 80 00 04 58 81 00 04 F4 83 00 04 A4` — valid sResource IDs ($01=board, $80-$83=functional resources).
- **Monitor ID**: Vblank status register at `$x9_0010` returns `(vblank<<16) | (1<<17)` — correct for Hi-Res 640x480 color monitor.
- **No built-in video**: Confirmed. Mac II has no built-in framebuffer. All video output is NuBus-only (`VGA_R/G/B` driven exclusively from `nubus_video_highres`). The gray screenshot is from the default CLUT grayscale ramp with uninitialized VRAM.
- **Slot E**: Card configured at slot $E. Standard slot `$E000_0000-$EEFF_FFFF`, super slot `$FE00_0000-$FEFF_FFFF`.
- **Empty slot handling**: Empty slots now generate proper bus errors via the NuBus arbiter + system BERR counter (see below). The Slot Manager's BERR handler catches these and marks slots as empty.

## ADB Controller: FIXED (2026-03-28)

The original `adb.sv` was a Mac Plus "plus_too" ADB implementation with wrong protocol for Mac II:

- **INT line logic was wrong**: Used `!adbValid` which asserted INT at `respCnt=0` before any response byte was sent. Mac II needs state-dependent INT per Snow's transceiver.rs.
- **Response timing broken**: `adbValid=0` at `respCnt=0` made Talk Reg 3 (device detection) fail — ROM saw "no device" immediately.
- **No Listen deferral**: Mac II defers Listen execution until state transitions back to Command.

### Fix applied
Rewrote `rtl/adb.sv` to match Snow emulator's Mac II ADB Modem PIC protocol (`transceiver.rs`):

- 4-state machine: Command(0,0), Data1(1,0), Data2(0,1), Idle(1,1)
- State-dependent INT: Command→false, Data1→(cmd_empty && resp_empty), Data2/Idle→any_srq
- Response bytes returned one per Data1/Data2 transition
- Listen commands deferred until `finish=true` (transition back to Command)
- Keyboard at addr 2 (handler ID 2, Extended Keyboard), Mouse at addr 3 (handler ID 1)
- Preserved PS2 scan code table and mouse handler from original

### Result
Boot progressed from SCC idle loop (PC=$40803296, cycle 417M) to the BTST #5 polling loop (PC=$40806DD8, cycle ~80M). ROM checksum passes. ADB init completes successfully. Boot now reaches a much later phase.

## VIA1 Shift Register / ADB Data Transfer: FIXED (2026-03-28)

After ADB init, the ROM entered a tight BTST #5 polling loop at PC=$40806DD8, waiting for VIA1 SR completion interrupt (IFR bit 2) to fire. Three issues prevented it:

### Root causes

1. **VIA SR not armed on ACR write** — The Mac II ROM sets the shift mode by writing VIA1 ACR ($50F01600) *without* accessing the SR register. Our `via6522.sv` only armed the shift register on SR read/write (`trigger_serial`), matching the 6522 datasheet but not how the Mac II ROM uses it. Snow's VIA emulation starts shifting on ACR write.

2. **Keyboard clock generator not running** — Even after arming the SR, no CB1 clock edges were generated. The `kbd_clk_active` signal in `dataController_top.sv` only ran during `kbd_transmitting` or `kbd_receiving`, but VIA1 SR activation alone didn't trigger either state.

3. **ADB response bytes not buffered** — The ADB controller (`adb.sv`) strobed response bytes immediately, but `kbd_receiving` wasn't set because VIA1 SR wasn't armed yet. The response data was lost.

### Fixes applied

- **`via6522.sv`**: Added `trigger_acr_shift` — arms shift register when ACR is written with a non-disabled shift mode (bits 4:2 ≠ 000). Added `sr_active` output port exposing internal `shift_active` state. Fixed `serial_event` to use falling-edge detection of `shift_active` for reliable completion.

- **`dataController_top.sv`**:
  - `kbd_clk_active` now includes `via1_sr_active` — clock generator runs whenever VIA1 SR is armed
  - Added `adb_recv_pending` register — buffers ADB response bytes until VIA1 SR is ready to receive
  - Auto-starts `kbd_transmitting` on VIA1 SR activation edge (for shift-out to ADB)

### Result
854 SR completion events fired in 300-frame sim. BTST #5 loop hit only 18 times (brief waits, all resolved). Boot progressed well past ADB init into NuBus slot scanning and declaration ROM reading.

## TG68K Bus Error Frame / NuBus Empty Slots: FIXED (2026-03-29)

After ADB/SR fixes, the boot reached NuBus slot re-scanning but stalled due to broken bus error handling. The Mac II Slot Manager probes empty NuBus slots and relies on bus errors (BERR) to detect them. Two problems prevented this from working:

### Root causes

1. **Wrong BERR exception frame for 68010+ mode** — TG68K's trap2 state unconditionally routed BERR exceptions through trap4→trap5→trap6, which pushes 3 extra words (68000-style extended frame). But the format/vector word said format `$0` (8-byte frame). On RTE, only 8 bytes were popped, leaving 6 bytes of garbage on the stack. This corrupted the return address, causing wild jumps (PC=`$40803214` in NuBus space).

2. **trap1 didn't push PC for BERR** — The trap1 state only set `writePC` for interrupts and trace exceptions, not for BERR. This meant the PC value pushed to the stack came from `writePC_add` (next instruction) rather than the faulting instruction's actual PC.

3. **No double bus fault → HALT** — If BERR fired during BERR exception processing (e.g., stack in unmapped memory), the CPU would infinite-loop instead of halting. Real 68020 enters HALT state on double bus fault.

4. **Fake DTACK workaround was fragile** — The previous approach returned `$FFFF` with fake DTACK after 4 clocks for empty NuBus slots. This caused the Slot Manager's sResource directory scan to interpret `$FFFF` as a count word of 65535, looping 65536 times per slot.

### Fixes applied

- **`TG68KdotC_Kernel.vhd`** (trap2): Changed `IF trap_berr='1'` to `IF trap_berr='1' AND use_VBR_Stackframe='0'` — only push the extended 68000 frame when actually in 68000 mode. For 68010+, the format `$0` frame (SR + PC + format/vector = 8 bytes) is now complete and self-consistent with RTE.

- **`TG68KdotC_Kernel.vhd`** (trap1): Added `OR trap_berr='1'` to the writePC condition, so BERR pushes the actual PC.

- **`TG68KdotC_Kernel.vhd`** (HALT): Added `halted` and `berr_seen_low` signals. During BERR exception processing (`trap_berr='1'`), if `berr` goes low then re-asserts, `halted` is set. When halted: `clkena_lw` is gated off (freezes microcode), `busstate` forced to `"01"` (no bus activity). New `cpu_halted` output port. Only reset clears halt.

- **`rtl/nubus/nubus_arbiter.sv`** (new): Replaced inline fake-DTACK logic in sim.v. Empty NuBus slots now get no DTACK — the system BERR counter fires after 260 clocks (~8us), matching real hardware. Card responses pass through directly.

- **`tg68k.v`**: Added `cpu_halted` output port, wired to kernel.

### Result
In 2000-frame sim: 5 BERR events (all at PC=`$40807580`, probing addr `$A0830E80`), correctly caught by Slot Manager's BERR handler. 17 unique PCs install BERR handlers throughout boot — the ROM progresses through multiple boot stages. Boot reaches PC=`$40812Fxx` (deep into ROM init) and enters VIA1 ORA polling — likely ADB communication for device enumeration.

## Boot Sequence Timeline (from 2000-frame sim)

1. **ROM load + reset** — System ROM and NuBus video ROM loaded. Reset sequence completes.
2. **VIA polling** — Initial VIA ORA reads (port A = $82, DDRA = $3D). Dongle checks at `$40802A7C`.
3. **ROM checksum** — Passes at cycle ~14M.
4. **Debug monitor entry** — At cycle ~14M, ROM initializes debug monitor.
5. **BERR vector setup** — Multiple writes to bus error vector ($000004-$000005) from 17 different PCs throughout boot.
6. **VIA1/VIA2 setup** — VIA2 configured: ACR=$C0, T1=$196E (60.15 Hz PB7). VIA1 IER=$87 (CA1/CA2/SR).
7. **ADB init** — ADB controller communicates successfully (Talk Reg 3 returns device IDs).
8. **ADB SR transfers** — VIA1 shift register completes many transfers (BTST #5 loop passes through).
9. **IPL interrupts begin** — VIA interrupts (IPL 6→7 transitions) at cycle ~65M, PC around `$408005xx`–`$40807008`.
10. **NuBus slot scanning with BERR** — At cycle ~71M, ROM probes NuBus slots. Empty slot at `$A0830E80` triggers BERR, caught by Slot Manager handler. Slot E card found and initialized.
11. **Late ROM init** — BERR handlers reinstalled at PCs `$4080E5xx`–`$4080E60E`. Write to `$0B9A` (low memory global) at PC=`$40812F5E`.
12. **Current state** — VIA1 ORA polling loop (ADB communication). Port A reads cycling through ira=$81→$83 with DDRA=$3F/$3D. Writes to ORA driving ADB data lines. Boot appears to be in ADB device enumeration or waiting for ADB response.

## ADB Response Timing / Device Enumeration: FIXED (2026-03-30)

After the VIA SR fixes, ADB device enumeration failed because response bytes arrived one state transition late. The ROM scanned all 16 ADB addresses with Talk R3, but the first response byte was always `$00` instead of the actual device data.

### Root causes

1. **Non-blocking assignment race in `adb.sv`** — `process_command` was called during Data1/Data2 state transitions. It set `resp_len` and `response[]` via non-blocking assignments (`<=`), but `resp_empty` was checked in the same cycle, seeing the OLD `resp_len=0`. Result: first Data1 always returned `$00`, and `response[0]` appeared on Data2 (one transition late).

2. **`kbd_bitcnt` not reset on receive start** — When `kbd_receiving` started, `kbd_bitcnt` wasn't explicitly reset to 0. While it happened to be 0 in most cases (from the previous transmit ending), this was fragile.

### Fixes applied

- **`rtl/adb.sv`**: Moved `process_command(1'b0)` from the Data1/Data2 state transition handler to a standalone check: `if (cmd_valid && !cmd_processed && st == ST_COMMAND)`. This runs one cycle after the command byte is received (when `cmd_byte` has settled via non-blocking assignment), ensuring `resp_len` and `response[]` are ready long before the Data1 transition reads them.

- **`rtl/dataController_top.sv`**: Added `kbd_bitcnt <= 0` when `kbd_receiving` starts from `adb_recv_pending`.

### Result

ADB device enumeration now completes successfully:
- Reset ($00) → all devices reset
- Talk R3 addr 0–15 → keyboard found at addr 2 (`$62,$02`), mouse at addr 3 (`$63,$01`)
- Talk R0 addr 3 → mouse event poll
- Boot progresses past ADB init into VIA1 CA1 interrupt handling

## VIA1 CA1 Interrupt Loop: RESOLVED (2026-04-08)

The CA1 loop documented here previously was fixed incidentally by earlier
branch work (likely the ADB response-timing fix in `6dc436d` and/or the
SCC refactor). Verified this session by:

1. Temporarily bypassing the `via2_pb_o[7] → via1_ca1` chain with a clean
   60 Hz pulse (Snow-style, see `../snow/core/src/mac/macii/bus.rs:747`).
   Boot reached `TMENTRY1` (Time Manager entry) and advanced to a new
   blocker. Committed as `3be3972`.
2. Instrumented `via2_pb_o[7]` edge rate. Measured **124 Hz post-init**
   — correct for a 60 Hz VBL chain (PB7 toggles twice per period).
3. Restored the real PB7 chain and re-ran: **identical** progress
   (same `TMENTRY1`, same 48 writes to `$0B9A`, same next-blocker landing
   point at `$40805F4A`). Bypass reverted in `0fcf8c5`.

The PB7→CA1 chain is functionally correct. No action needed here.

## Current Blocker: VIA1 ORA Polling + Delay Loop at $40805F48 (2026-04-08)

After TMENTRY1 at cycle 79.8M, boot lands in an outer loop that:
- Calls a delay routine at `$40805F48` (SUBQ.W #1,D4 / BPL.S -4) — a
  simple register-decrement spin that completes and exits to `$40805F4C`
  (TST.W D3). The delay loop is not itself a hang.
- Repeatedly reads VIA1 Port A via the **no-handshake** register
  (address `$F`, `ORA_NH`), seeing `ira=$81` every time:
  - bit 0 = 1 (model sense, correct for Mac II: Snow returns
    `RegisterA(0).with_model(1)` = `0x01`)
  - bit 7 = 1 (SCC WReq — "no data ready", our `scc.v` hardcodes
    `wreq=1` at line 1656)

### Snow reference (`../snow/core/src/mac/via.rs:368-378`)

```rust
0x01 | 0x0F => {
    // Set sccwrreq on every port A read
    self.a_in.set_sccwrreq(true);
    // Clear CA1/CA2 IFR bits on port A reads (both handshake AND no-handshake)
    self.ifr.set_vblank(false);
    self.ifr.set_onesec(false);
    ...
}
```

Snow clears IFR bits 0 and 1 on **both** ORA (`$01`) and ORA no-handshake
(`$0F`) reads. Real 6522 only clears on `$01`. Our `via6522.sv` matches
the real 6522 (only clears at `addr == 4'h1`, not `4'hF`, in the read
action block at line 438). If the Mac II ROM relies on Snow's extended
behavior, the CA1 interrupt flag can stay latched after a no-handshake
read, causing spurious re-entry into the VBL interrupt servicer.

### Resolution (2026-04-08)

Applied Snow's IFR clear behavior to `via6522.sv`: now clears `irq_flags[1]`
(CA1/VBL) and `irq_flags[0]` (CA2/onesec) on reads of **both** `$01` and
`$0F` (ORA handshake and no-handshake). The `$40805F48` ORA polling loop
now exits cleanly. Boot advances past Time Manager init, sets up a new
exception vector table (VBR=`$40802806`), and reaches SCC initialization.

## SCC Channel A RR0 Polling at $408032AC: RESOLVED (2026-04-08)

Same class of hang as the MacLC_MiSTer LocalTalk self-test wedge
(see `../MacLC_MiSTer` commit `83c226c`). The Mac II ROM boots with
AppleTalk active by default and runs a LocalTalk self-test that polls
SCC channel A RR0 for Rx char available.

MacLC's fix: set XPRAM `0x13=0x22` (SPConfig: both ports useAsync), which
makes `SPConfig & 0x0F != 0` → ROM sets `emAppleTalkInactiveOnBoot` and
skips LocalTalk init entirely.

Our `rtl/rtc.v` already had `pram[0x13]=0x22`, but the **SPValid magic
bytes at 0x0E/0x0F/0x10 were wrong** (`0x63 00 03` instead of
`0x4D 63 A8` = `'M' 'c' 0xA8`), so the ROM discarded the SPConfig as
invalid and ran AppleTalk anyway. Fixed the validity bytes; boot now
advances past the `$408032AC` loop.

## Current Blocker (DEPRECATED): SCC Channel A RR0 Polling at $408032AC (2026-04-08)

After VBR setup, boot lands in a tight SCC Channel A status-register
polling loop:

- PC: `$408032AC`, opcode `674C` (BEQ.S +76)
- Reads SCC RR0 on channel A repeatedly, getting `$2C` every time
  - bit 5 = CTS = 1
  - bit 3 = Sync/Hunt = 1
  - bit 2 = Tx Buffer Empty = 1
  - **bit 0 = Rx Character Available = 0** (ROM is waiting for this)
- ROM is presumably waiting for an SCC Rx character that never arrives.
  This is AppleTalk/LocalTalk init, serial port probing, or an Egret/ADB
  response via the SCC.

### Snow reference

`../snow/core/src/mac/scc.rs` and `../snow/core/src/mac/macii/bus.rs`
initialize the SCC and drive Rx events from the Mac II bus tick loop.
Worth checking how Snow handles the initial SCC config sequence, and
whether the Mac II ROM expects a loopback/probe response on channel A
during this phase.

### Next steps (RESOLVED — see SPValid fix above)

## Current Blocker: Interrupt Handler SCC Poll at $40802EEA (2026-04-08)

After the SPValid fix unblocks AppleTalk, boot advances past the LLAP
self-test and reaches a new resting point in an **interrupt handler in
RAM** at PC `$40802EEA` (reached via VBR=`$40802806`). The handler is
still polling SCC channel A RR0, seeing the same `$2C` value, and
apparently never exiting.

Opcode at `$40802EEA` is `0205` (ANDI.B #imm,D5) — not itself a poll,
but an instruction in a tight service routine that keeps reading SCC.

Preceding PCs observed on the way here: `$408036FE` (Op `3018`),
`$4080DE3E` (Op `51CD` DBRA D5 loop), `$40805F44` (Op `1087` write).

### Next steps

1. Identify what interrupt is firing by looking at the vector table at
   `$40802806` — which SCC interrupt bit is installed where?
2. Check if WR9 (interrupt vector enable) or WR1/WR15 config is causing
   the SCC to assert IRQ continuously with no clearable condition.
3. Compare against Snow's SCC interrupt generation logic
   (`../snow/core/src/mac/scc.rs`).

## Reference Implementations

- **MAME**: `src/devices/bus/nubus/nubus_m2hires.cpp` — canonical reference for register map, RAMDAC, timing
- **Snow**: `core/src/mac/adb/transceiver.rs` — reference for ADB protocol (used for adb.sv rewrite)
- **Snow**: `core/src/mac/nubus/mdc12.rs` — different card (Display Card 8-24 / 341-0868), NOT the High Resolution card

## Key Files

- `rtl/adb.sv` — ADB Modem PIC transceiver (Mac II protocol, response timing fix 2026-03-30)
- `rtl/tg68k/TG68KdotC_Kernel.vhd` — CPU core (BERR frame fix, HALT support)
- `rtl/tg68k/tg68k.v` — CPU bus wrapper (cpu_halted port)
- `rtl/nubus/nubus_arbiter.sv` — NuBus empty-slot BERR handler (new 2026-03-29)
- `rtl/nubus/nubus_video_highres.sv` — NuBus video card implementation
- `rtl/addrDecoder.v` — address decoder (NuBus slot space at lines 139-154)
- `rtl/dataController_top.sv` — peripheral controller, VIA/SCC/ADB connections, kbd_bitcnt fix
- `verilator/sim.v` — sim wrapper (NuBus arbiter instantiation, BERR counter)
- `verilator/sim_main.cpp` — sim harness (screenshot capture)
- `releases/boot1.rom` — declaration ROM file (8KB, 341-0660)

## Next Steps

1. **Debug VIA1 CA1 interrupt loop** — determine what drives CA1 (VBL from VIA2? RTC?), check if the source is properly connected and generating correct timing
2. **Check VIA1 CA1 edge/level sensitivity** — CA1 may be configured for edge-triggered but receiving a stuck level
3. **Monitor for further blockers** — SCSI init, IWM/floppy, or memory manager init may follow
