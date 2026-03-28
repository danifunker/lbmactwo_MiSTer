# Mac II Boot Sequence — Current Analysis (2026-03-28)

## NuBus Video Card Status: Working Correctly

The NuBus High Resolution Video Card (TFB 2.2 / 341-0660) declaration ROM handling is functional:

- **Declaration ROM**: Fully read by Slot Manager (8210 byte reads on lane 3)
- **Byte-lane format**: De-inverted (XOR $FF) + format byte overridden to `$78` (lane 3, non-inverted). This matches MAME's `install_declaration_rom()` behavior.
- **sResource directory**: Parses correctly. First 16 de-inverted bytes = `01 00 00 2C 80 00 04 58 81 00 04 F4 83 00 04 A4` — valid sResource IDs ($01=board, $80-$83=functional resources).
- **Monitor ID**: Vblank status register at `$x9_0010` returns `(vblank<<16) | (1<<17)` — correct for Hi-Res 640x480 color monitor.
- **No built-in video**: Confirmed. Mac II has no built-in framebuffer. All video output is NuBus-only (`VGA_R/G/B` driven exclusively from `nubus_video_highres`). The gray screenshot is from the default CLUT grayscale ramp with uninitialized VRAM.
- **Slot E**: Card configured at slot $E. Standard slot `$E000_0000-$EEFF_FFFF`, super slot `$FE00_0000-$FEFF_FFFF`.
- **Empty slot handling**: Slots 9-D return `$FFFF` via timeout (no bus error), which the Slot Manager interprets as "no card" (format byte $FF).

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

## Current Blocker: BTST #5, $015D(A3) Polling Loop

After ADB init, the ROM enters a tight loop at PC=$40806DD8:

```
$40806DD8: BTST #5, $015D(A3)    ; Test bit 5 of structure field
$40806DDE: BNE.S $40806DD8       ; Loop if bit 5 is set
$40806DE0: JSR   <subroutine>    ; Occasionally calls subroutine
```

This loop polls bit 5 of a data structure pointed to by A3, offset $015D. Per `docs/snow_boot_sequence.md`, this is **NOT** a VIA register — it's a ROM initialization structure field. The JSR at $40806DE0 periodically executes (the loop does eventually call it), but the bit 5 condition never fully clears.

### What we know about this loop
- It appears after ADB init completes and VIA2 Timer A is configured
- The structure at A3+$015D likely tracks initialization state
- Bit 5 may be cleared by an interrupt handler or callback from a peripheral init step
- No NuBus video writes occur — ROM hasn't reached video card initialization yet

## Boot Sequence Timeline (from sim output)

1. **ROM load + reset** — System ROM and NuBus video ROM loaded. Reset sequence completes.
2. **VIA polling** — Initial VIA ORA reads (port A = $82, DDRA = $3D). Dongle checks at `$40802A7C`.
3. **ROM checksum** — Passes at cycle ~14M.
4. **BERR vector setup** — Multiple writes to bus error vector ($000004-$000005) at various PCs.
5. **Slot scanning** — ROM probes slots 9-D (all empty, return $FFFF). Probes slot E — finds card.
6. **Declaration ROM read** — Full 8210-byte read of slot E declaration ROM.
7. **VIA setup** — VIA2 configured: ACR=$C0, T1=$196E (60.15 Hz PB7). VIA1 IER=$87 (CA1/CA2/SR).
8. **ADB init** — ADB controller communicates successfully (Talk Reg 3 returns device IDs).
9. **BTST #5 loop** — CPU enters polling loop at $40806DD8. **Currently stalls here.**

## Reference Implementations

- **MAME**: `src/devices/bus/nubus/nubus_m2hires.cpp` — canonical reference for register map, RAMDAC, timing
- **Snow**: `core/src/mac/adb/transceiver.rs` — reference for ADB protocol (used for adb.sv rewrite)
- **Snow**: `core/src/mac/nubus/mdc12.rs` — different card (Display Card 8-24 / 341-0868), NOT the High Resolution card

## Key Files

- `rtl/adb.sv` — ADB Modem PIC transceiver (Mac II protocol, rewritten 2026-03-28)
- `rtl/nubus/nubus_video_highres.sv` — NuBus video card implementation
- `rtl/addrDecoder.v` — address decoder (NuBus slot space at lines 139-154)
- `rtl/dataController_top.sv` — peripheral controller, VIA/SCC/ADB connections
- `verilator/sim.v` — sim wrapper (NuBus timeout/open-bus at lines 199-211)
- `verilator/sim_main.cpp` — sim harness (screenshot capture)
- `releases/boot1.rom` — declaration ROM file (8KB, 341-0660)

## Next Steps

Investigate the BTST #5 polling loop at PC=$40806DD8:
- Determine what A3 points to and what the structure at offset $015D represents
- Check if bit 5 is supposed to be cleared by an interrupt handler
- Check if this relates to Egret/PRAM/RTC initialization
- Try running Snow with instruction tracing to see how it gets past this point
- Add sim tracing for the memory address being polled (A3+$015D)
