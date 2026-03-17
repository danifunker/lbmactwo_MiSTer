# VIA2 Implementation Plan for Mac II

## Background

The Mac II has two VIA 6522 chips. VIA1 handles keyboard/ADB, RTC, sound volume,
overlay control, and the 1-second timer. VIA2 handles NuBus slot interrupts, RAM
sizing (glue logic), ASC sound chip IRQ, and chains a 60.15 Hz clock to VIA1.

This core (forked from MacPlus) only implements VIA1. VIA2 address space
(`$50F02000`) is currently **aliased to VIA1** in the address decoder, meaning ROM
reads of VIA2 return VIA1 register data. This likely causes boot failures — the ROM
reads VIA2 Port A for RAM size and NuBus IRQ state during early initialization.

## Current State (What Exists)

- **VIA1**: Fully instantiated in `dataController_top.sv` using `via6522.sv`
- **Address decode**: VIA2 space (`$50F02000-$50F03FFF` and `$F02000-$F03FFF`)
  is decoded but routes to the same `selectVIA` signal as VIA1
- **NuBus IRQ**: `nubus_irq_n` is routed directly into the `_cpuIPL` priority
  encoder, bypassing VIA2 entirely
- **No `selectVIA2` signal exists** anywhere in the RTL

## Why VIA2 Matters for Boot

MAME's Mac II boot sequence shows:

1. ROM reads VIA2 Port A (`$50F02001`) to get RAM size bits [7:6] and NuBus IRQ
   state [5:0]
2. ROM writes VIA2 Port A [7:6] to configure RAM bank mapping (glue chip)
3. ROM configures VIA2 timers and interrupt enables
4. NuBus VBL interrupts flow through VIA2 CA1 → VIA2 IRQ → CPU IPL 2
5. Without VIA2, the ROM may hang during RAM sizing or enter an unexpected state

## VIA2 Port A Assignments

| Bit | Direction | Function |
|-----|-----------|----------|
| 7-6 | Output | RAM size / glue chip config (bank B location) |
| 5 | Input | Slot E IRQ (active-low, directly our video card) |
| 4 | Input | Slot D IRQ (active-low) |
| 3 | Input | Slot C IRQ (active-low) |
| 2 | Input | Slot B IRQ (active-low) |
| 1 | Input | Slot A IRQ (active-low) |
| 0 | Input | Slot 9 IRQ (active-low) |

**Read returns**: `{ram_size[1:0], nubus_irq_state[5:0]}`

Initial state: `nubus_irq_state = 6'b111111` (all deasserted, active-low)

### RAM Size Encoding (PA[7:6])

| Value | Bank B Start Address |
|-------|---------------------|
| 00 | $100000 (1 MB) |
| 01 | $200000 (2 MB) |
| 10 | $800000 (8 MB) |
| 11 | $2000000 (32 MB) |

For our 4MB configuration, the ROM will write the appropriate value during
memory sizing. This may need to feed into the address decoder / RAM controller.

## VIA2 Port B Assignments

| Bit | Direction | Value | Function |
|-----|-----------|-------|----------|
| 7 | Output | — | Directly drives VIA1 CA1 input (60.15 Hz chain) |
| 6-0 | Input | 0x4F | Hardwired: `{0, 1, 0, 0, 1, 1, 1, 1}` = $4F |

Note: MAME returns `0xCF` for Mac II `via2_in_b()`, but bit 7 is the output
latch readback, so the input value is `0x4F`. The exact value should be verified.

## VIA2 Handshake Lines

| Line | Direction | Source | Function |
|------|-----------|--------|----------|
| CA1 | Input | NuBus IRQ aggregator | Pulses low when any slot asserts IRQ |
| CA2 | — | Not used | Leave unconnected |
| CB1 | Input | ASC sound chip IRQ | Sound interrupt (active-low, inverted) |
| CB2 | — | Not used | Leave unconnected |

### CA1 NuBus IRQ Logic (from MAME `nubus_slot_interrupt`)

```
When any slot asserts IRQ:
  - Clear corresponding bit in nubus_irq_state (active-low)
  - If CA1 is currently high, drive it low (falling edge triggers VIA2 IFR)

When a slot deasserts IRQ:
  - Set corresponding bit in nubus_irq_state
  - If all slots deasserted (nubus_irq_state == 6'b111111), drive CA1 high
  - If other slots still active, pulse CA1 high then low (re-trigger)
```

MAME has a `m_via2_ca1_hack` flag to manage the pulse/re-trigger behavior.
This prevents missed interrupts when multiple slots are active.

## Interrupt Priority (CPU IPL)

Current (wrong for Mac II):
```verilog
assign _cpuIPL =
    !_viaIrq    ? 3'b110 :  // VIA → level 1
    (!_sccIrq || !nubus_irq_n) ? 3'b101 :  // SCC/NuBus → level 2
    3'b111;
```

Correct Mac II scheme (from MAME `field_interrupts`):
```verilog
assign _cpuIPL =
    !_sccIrq    ? 3'b011 :  // SCC → IPL 4 (highest)
    !_via2Irq   ? 3'b101 :  // VIA2 → IPL 2 (NuBus/SCSI/ASC)
    !_via1Irq   ? 3'b110 :  // VIA1 → IPL 1 (keyboard/RTC)
    3'b111;                   // no interrupt
```

NuBus IRQ no longer goes directly to the CPU — it flows through VIA2.

## Timer Usage

**Timer A**: Can generate 60.15 Hz output. The PB7 output bit is toggled by
Timer A overflow and chains to VIA1 CA1 (1-second interrupt generation).
The ROM configures this during VIA setup.

**Timer B**: Available for general timing. Not critical for boot.

## Implementation Phases

### Phase 1: Stub VIA2 (Minimum for Boot)

Goal: Make the ROM happy enough to continue past VIA2 initialization.

1. **Add `selectVIA2` signal** to address decoder (`addrDecoder.v`)
   - Separate VIA2 address range from VIA1
   - Both 32-bit (`$50F02000`) and 24-bit (`$F02000`) paths

2. **Instantiate second `via6522`** in `dataController_top.sv`
   - Wire `selectVIA2` for read/write enable
   - Data on `cpuDataIn[15:8]` / `cpuDataOut[15:8]` (same byte lane as VIA1)
   - Same `E_rising`/`E_falling` clocking as VIA1

3. **Wire Port A inputs**:
   - `pa_i[5:0]` = `6'b111111` (all NuBus IRQs deasserted initially)
   - `pa_i[7:6]` = readback of `pa_o[7:6]` (RAM size output loopback)
   - Only our video card slot (E) needs the real IRQ wired

4. **Wire Port B inputs**:
   - `pb_i` = `8'hCF` (Mac II hardwired value)

5. **Wire handshake lines**:
   - `ca1_i` = `1'b1` (no NuBus IRQ pending)
   - `cb1_i` = `1'b1` (no ASC IRQ — we don't have ASC yet)

6. **Update `_cpuIPL`** to use VIA2 IRQ output:
   ```verilog
   assign _cpuIPL =
       !_sccIrq  ? 3'b011 :  // SCC → IPL 4
       !_via2Irq ? 3'b101 :  // VIA2 → IPL 2
       !_viaIrq  ? 3'b110 :  // VIA1 → IPL 1
       3'b111;
   ```

7. **Wire VIA2 PB7 output → VIA1 CA1 input** for timer chain

8. **Update `sim.v`** (verilator wrapper) to match

### Phase 2: NuBus Interrupt Routing

Goal: Video card VBL interrupts work properly.

1. **Wire video card IRQ** to VIA2 Port A bit 5 (slot E)
2. **Implement CA1 edge logic**: Drive CA1 low when any slot IRQ asserts
3. **ROM reads VIA2 PA** to identify which slot is interrupting
4. **Interrupt acknowledge** clears the slot bit, CA1 returns high

### Phase 3: RAM Size Glue Logic

Goal: ROM can configure RAM bank mapping via VIA2 PA[7:6].

1. **Capture PA[7:6] writes** as RAM configuration register
2. **Feed into address decoder** to control bank B placement
3. This may require changes to `addrController_top.v` and `addrDecoder.v`
4. For initial implementation, can hardcode 4MB config and ignore writes

### Phase 4: ASC Sound Integration (Future)

1. Wire ASC IRQ to VIA2 CB1 (inverted)
2. Requires ASC implementation (separate project)

## Files to Modify

| File | Changes |
|------|---------|
| `rtl/addrDecoder.v` | Add `selectVIA2` output, separate from `selectVIA` |
| `rtl/addrController_top.v` | Pass `selectVIA2` through to `dataController_top` |
| `rtl/dataController_top.sv` | Add VIA2 instance, update IPL, wire ports |
| `verilator/sim.v` | Mirror all `dataController_top` port changes |
| `LBMacTwo.sv` | Mirror all port changes for FPGA build |

## MAME Reference

Key functions in `mame/src/mame/apple/macii.cpp`:
- `via2_in_a()` (line ~557): Returns `m_glue_ram_size | m_nubus_irq_state`
- `via2_in_b()` (line ~563): Returns `0xcf` for Mac II
- `via2_out_a()` (line ~543): Writes RAM size, reconfigures memory map
- `via2_out_b()` (line ~567): PB7 → VIA1 CA1 chain
- `nubus_slot_interrupt()` (line ~800): NuBus IRQ → CA1 edge management
- `field_interrupts()` (line ~235): IPL priority: SCC(4) > VIA2(2) > VIA1(1)
- `machine_reset()`: Sets CA1=1, CB1=1, nubus_irq_state=0xFF
