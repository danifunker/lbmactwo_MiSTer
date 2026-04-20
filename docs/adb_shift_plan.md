# Plan: Fix VIA1 SR ↔ ADB byte transfer for Mac II

## Context

After the HMMU fix (commit cc07b8c), the Mac II ROM now reaches
$40806DD8 and hangs in `BTST #5, (A3+$15D) / BNE.S -6`, waiting on the
ADB probe to complete. The level-1 autovector handler at $40806080
fires continuously — VIA1 IFR[2] (SR shift-register complete) keeps
re-asserting but the ADB device probe at $40806E16 never advances past
some step, so `BCLR #5, (A3+$15D)` (at $40806EDA) never executes.

This is not the result of a missing ADB implementation — the
Mac II-style ADB was rewritten per Snow's `transceiver.rs` in commit
`58bcec3`, plus refinements in `6dc436d` and `b082082`. The current
bug is in the VIA1 SR timing/byte-delivery glue between the ADB
transceiver and `via6522.sv`.

## Root cause

`rtl/dataController_top.sv` implements **two concurrent byte-delivery
mechanisms** for VIA1 SR in Mac II mode, racing each other:

1. **Snow-style 3 ms timer (path A)** — lines 421-497:
   - ACR write of `3'b011` (shift-in) or SR write in mode `3'b111`
     (shift-out) arms `via1_shift_timer = 100000` clocks (~3 ms @
     32.5 MHz)
   - On expiry, pulses `via1_sr_ext_complete` → `via6522.sv`
     (lines 787-793) clears `shift_active`, sets IFR[2], loads
     `shift_reg` from `sr_ext_data = kbd_to_mac`
   - Matches Snow exactly

2. **Legacy Mac-Plus CB1 bit-bang (path B)** — lines 521-539, 599-636:
   - `kbdclk_count` toggles `kbdclk` every ~80 clocks (~2.5 µs)
     whenever `kbd_transmitting || kbd_receiving`
   - Each kbdclk rising edge shifts a bit through CB1/CB2
   - After 8 bits (bit_cnt==7), pulses `adb_din_strobe` (TX) or
     completes RX
   - Inside `via6522.sv` the internal 6522 shifter (lines 765-784)
     also counts down `bit_cnt` on shift_pulse edges and clears
     `shift_active` when `bit_cnt==0`, setting IFR[2]

### Failure sequence (shift-in / ADB Talk response)

1. ROM writes ACR = `$0C` (shift-in mode `011`) → path A arms 3 ms timer.
2. ROM writes VIA1 Port B cycling ST0/ST1 to Data1. `adb.sv` returns
   first response byte via `adb_dout_strobe`, stored in `kbd_to_mac`.
3. Path B logic at line 601: `!via1_sr_active_d && via1_sr_active && cb2_t`
   sets `kbd_transmitting <= 1` (note: on shift-IN, `cb2_t=0`, so this
   shouldn't fire) — but `kbd_receiving` has its own trigger at line
   567-571 when `adb_recv_pending && via1_sr_active`.
4. `kbd_receiving=1` starts `kbdclk` toggling; CB1 pulses VIA1.
5. VIA1's internal shifter consumes 8 CB1 edges in ~660 µs, clears
   `shift_active`, sets IFR[2]. But `shift_reg` now contains whatever
   `ser_cb2_c` latched — which is driven by `kbddata_o` shifted from
   `kbd_to_mac` *on our side*. This may actually produce a correct byte
   if the bit-bang loop is well-synchronized.
6. ~2.3 ms later, path A also completes, fires `sr_ext_complete` again:
   clears `shift_active` (already 0), sets IFR[2] (re-asserts),
   reloads `shift_reg` with `kbd_to_mac`.
7. ROM's SR handler: either sees two IRQs for one byte, or — if ROM
   already consumed byte 1, advanced state, and byte 2 arrives from
   path A's duplicate — the probe counter `(A3+$16C)` goes off by one.

Either way the dispatch loop at $40806E16 cannot maintain the 16-step
probe state machine, and `(A3+$14C)` never accumulates the "devices
found" bitmap properly, so `BCLR #5` at $40806EDA is never reached.

## Option A — Snow-style (pragmatic)

**Change:** gate path B completely off for `machineType=1`. Only path A
(3 ms timer → `via1_sr_ext_complete`) delivers bytes. Leave `via6522.sv`
internal shifter inert on Mac II because no CB1 edges arrive.

**Scope:**
- `rtl/dataController_top.sv` — wrap `kbd_transmitting`/`kbd_receiving`
  start conditions (lines 567, 588, 599-605) and the kbdclk generator
  (lines 521-539) in `!machineType` guards where missing. Remove lines
  578-582 (Snow-style `via1_sr_out_done` → `adb_din_strobe`) from the
  path-B always block and put it directly in path A, cleanly.
- `rtl/via6522.sv` — no change (internal shifter is already inert when
  no CB1 pulses arrive).
- `rtl/adb.sv` — no change.

**Complexity:** ~50 lines touched, all in one file. Low risk.

**Fidelity:** matches Snow (which boots Mac II successfully). Does not
reproduce the real PIC1654S timing; any ROM code that assumes sub-3ms
byte transfer would fail — but the Mac II ROM doesn't (Snow proves it).

**Mac SE compatibility:** if we ever target Mac SE, gate the same way
with `macModel == SE`. Same ADB modem PIC as Mac II.

## Option B — MAME-style (faithful)

**Change:** port MAME's `adbmodem` device — a real PIC1654S
microcontroller emulation running the 342S0440-B ROM — into our RTL,
wired so it drives VIA1 CB1 and CB2 like real hardware, and replace
our `rtl/adb.sv` transceiver-level state machine with device-level
ADB bus emulation (keyboard & mouse talking on the ADB bus, not
state-directly-to-VIA).

**Scope:**
- New Verilog PIC1654S CPU core. No open-source FPGA PIC1654 exists
  that I know of; closest is PIC16F-class cores. Would need to write
  or port from scratch. PIC1654S is a 12-bit instruction, 512-word
  ROM architecture — simpler than modern PICs but still ~500-1000
  lines of Verilog for the core.
- Load the 1 KB `342s0440-b.bin` into the core (ROM data is in MAME).
- Wire PIC port pins to VIA1 CB1/CB2/PB3/PB4/PB5 and ADB bus.
- Implement ADB bus at the bit level: devices see bit-serial ADB
  timing, not ST0/ST1 state transitions.
- Rewrite keyboard and mouse as real ADB devices responding to
  Talk/Listen commands over the bit-serial bus.

**Complexity:** very high. PIC emulator + ROM integration + bit-level
ADB device rework. Probably 1000+ lines across several files. Also
likely a Quartus synthesis challenge (nested CPU cores).

**Fidelity:** matches real Mac II (and Mac SE) exactly — passes every
edge case the ROM might probe, including future OS code that cares
about ADB timing sub-ms.

**Mac SE reuse:** yes, exactly the same PIC & ROM, so SE gets it "for
free" when we extend the core.

## Recommendation

**Start with Option A.** It is:

- Aligned with a working reference (Snow boots the ROM we're trying
  to boot), so we have a proof-of-viability
- A surgical change to one file, reversible, and unlikely to regress
  other parts of the core
- Unblocks us to see the *next* boot failure, which may be more
  important than debating ADB fidelity now

If some later boot stage (e.g. OS disk driver ADB code, or a ROM
self-test that measures PIC timing) reveals that Snow's atomic
delivery model is too coarse, then upgrade to Option B at that point.
The cost to revisit is low — the wiring through `dataController_top`
stays the same; only the byte-delivery path changes.

## Implementation steps for Option A

1. Read current state of `rtl/dataController_top.sv` lines 420-640
   and list every place where Mac-II code path B state changes
   (`kbd_transmitting`, `kbd_receiving`, `kbdclk`, `adb_recv_pending`,
   `kbd_bitcnt`, `kbd_out_data`, `kbddata_o`).
2. Add `machineType` guards so those registers stay at reset values
   when `machineType=1`.
3. Move the `via1_sr_out_done` → `adb_din_strobe` path from the
   keyboard always block into the SR-timer always block where
   `via1_sr_ext_complete` is generated. (Byte "shifted out" by the
   CPU goes directly to the ADB transceiver 3 ms later.)
4. Build verilator; run 400 frames.
5. Expected: `(A3+$15D)` bit 5 clears, loop at $40806DD8 exits,
   CPU advances past $4080018E into the code at $40800192 onward.
6. If fail: add instrumentation (VIA1 SR reads/writes, ADB state
   transitions, `(A3+$16C)` / `(A3+$15D)` watchpoints) and iterate.

## Concrete diff sketch (Option A)

All edits in `rtl/dataController_top.sv`. Line numbers reference current HEAD.

### 1. Gate the kbdclk generator (lines 520-539)

`kbd_clk_active` should stay false on Mac II. The cleanest gate is at the
`wire` itself:

```systemverilog
wire kbd_clk_active = !machineType &&
                      ((kbd_transmitting && !kbd_wait_receiving) || kbd_receiving);
```

With this, on Mac II `kbdclk_count` never advances, `kbdclk` stays 1,
and the shifter inside `via6522.sv` never sees a CB1 edge.

### 2. Gate the path-B start conditions (lines 563-605)

Remove Mac II entries from path B entirely. In the `clk8_en_p` always block:

- Line 563-571 (`adb_dout_strobe && machineType` → `adb_recv_pending` →
  `kbd_receiving`): delete. Path A delivers the byte directly via
  `sr_ext_data = kbd_to_mac`, so `kbd_to_mac` still needs to be loaded.
  Keep the first half (`kbd_to_mac <= adb_dout`) but drop the
  `adb_recv_pending` / `kbd_receiving` trigger.

  ```systemverilog
  if (adb_dout_strobe && machineType) begin
      kbd_to_mac <= adb_dout;        // path A reads this on timer expiry
      // adb_recv_pending <= 1;      // REMOVED — path A handles completion
  end
  // if (adb_recv_pending && via1_sr_active && ...)  // REMOVED entirely
  ```

- Line 599-605 (`machineType && ... kbd_transmitting <= 1`): delete the
  Mac II branch. The non-Mac-II branch at 588-591 stays.

### 3. Move `via1_sr_out_done` hook into path A (lines 578-582)

Currently in the keyboard always block; should fire alongside path A
timer completion. Either leave it where it is (it still works — it's
independent of kbdclk) or, for clarity, move it next to the
`via1_sr_ext_complete` pulse generator in the path A block (~line 440).
Either is fine; moving it reduces coupling between the two blocks.

### 4. Bit-counter loop (lines 617-636)

Untouched — `kbdclk` never toggles on Mac II, so this block is inert.
No guard needed, but adding `if (!machineType)` around the whole
`~kbdclk_d & kbdclk` block documents intent.

### Signals that become dead on Mac II

After the gates, these are unused when `machineType=1`:
`kbd_transmitting`, `kbd_receiving`, `kbd_wait_receiving`, `kbd_bitcnt`,
`kbd_out_data`, `kbdclk`, `kbdclk_count`, `adb_recv_pending`,
`via1_sr_active_d` (only needed by the deleted trigger),
`ADBListenD`. Leave them declared (keeps Mac Plus path intact); just
confirm they stay at reset values in sim waveforms.

## Files to change (Option A)

- `rtl/dataController_top.sv` (only)

## Files untouched

- `rtl/adb.sv` (Snow-faithful already)
- `rtl/via6522.sv` (correct — internal shifter stays idle without CB1 edges)
- `LBMacTwo.sv`, `verilator/sim.v` (wiring unchanged)

## Notes on verification

- `via_debug.log` already captures every VIA1 SR read/write with PC
  and value — inspect for: (a) only *one* IFR[2] fire per ACR-arm,
  (b) SR read value matches what `adb.sv` put in `kbd_to_mac`
- Level-1 IRQ handler at $40806080 should fire ~16 times total during
  ADB init, not thousands
- After fix: the `BCLR #5, (A3+$15D)` at $40806EDA should execute,
  then JSR $408077F4 and JSR $40807834 run, then RTS back to
  $40806DE0 → $40800192.
