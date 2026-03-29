# Mac II Boot Sequence — Current Analysis (2026-03-29)

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

## Current Blocker: ADB Communication (polling VIA1 ORA)

The boot is stuck polling VIA1 port A (ORA no-handshake reads). The pattern suggests ADB bit-banging:
- Writes to ORA: `$82`→`$FF`→`$BF`→`$7F`→`$3F`→`$01`→`$EF`→`$83` (driving ADB data/clock)
- Reads from ORA: ira cycling through `$81`, `$83` (waiting for ADB response bits)

This is likely the ROM's ADB device enumeration phase, which requires proper ADB transceiver timing and response byte delivery. The ADB controller may need timing adjustments or the VIA↔ADB handshake may need work.

## Reference Implementations

- **MAME**: `src/devices/bus/nubus/nubus_m2hires.cpp` — canonical reference for register map, RAMDAC, timing
- **Snow**: `core/src/mac/adb/transceiver.rs` — reference for ADB protocol (used for adb.sv rewrite)
- **Snow**: `core/src/mac/nubus/mdc12.rs` — different card (Display Card 8-24 / 341-0868), NOT the High Resolution card

## Key Files

- `rtl/adb.sv` — ADB Modem PIC transceiver (Mac II protocol, rewritten 2026-03-28)
- `rtl/tg68k/TG68KdotC_Kernel.vhd` — CPU core (BERR frame fix, HALT support)
- `rtl/tg68k/tg68k.v` — CPU bus wrapper (cpu_halted port)
- `rtl/nubus/nubus_arbiter.sv` — NuBus empty-slot BERR handler (new 2026-03-29)
- `rtl/nubus/nubus_video_highres.sv` — NuBus video card implementation
- `rtl/addrDecoder.v` — address decoder (NuBus slot space at lines 139-154)
- `rtl/dataController_top.sv` — peripheral controller, VIA/SCC/ADB connections
- `verilator/sim.v` — sim wrapper (NuBus arbiter instantiation, BERR counter)
- `verilator/sim_main.cpp` — sim harness (screenshot capture)
- `releases/boot1.rom` — declaration ROM file (8KB, 341-0660)

## Next Steps

1. **Debug ADB VIA1 ORA polling** — determine what ADB response the ROM expects; cross-reference ORA bit patterns with Snow's transceiver.rs state machine
2. **Check ADB timing** — the bit-bang sequence suggests low-level ADB bus signaling; verify clock/data timing matches real hardware
3. **Monitor for further blockers** — SCSI init, IWM/floppy, or memory manager init may follow ADB
