# NuBus Implementation Notes

## Empty Slot Handling (Open Bus)

### Problem

The Mac II Slot Manager probes all NuBus slots ($9-$E) during boot by reading
the declaration ROM header at the top of each slot's standard space
(`$Fs0F_FFFx`). On real hardware, an empty slot causes no device to assert
`/DTACK`, which triggers a bus error (BERR) after ~8 microseconds. The ROM
installs a BERR exception handler that catches this and moves to the next slot.

TG68K has a `berr` input and does take the vector-2 exception, but it pushes a
**68000-style** bus error stack frame. The Mac II ROM expects a **68020 format
$A** frame (16 words with a format/vector offset word). The mismatch causes
the ROM's `RTE` to read incorrect frame data, crashing into a double bus fault.
TG68K also lacks the 68020 HALT state for double bus faults, so the CPU loops
or resets instead of stopping.

### Solution

Instead of relying on BERR for empty slot detection, unoccupied NuBus
addresses now return `$FFFF` (open bus) with a normal DTACK after a short
timeout (~4 sys clocks). The Slot Manager reads the declaration ROM format
byte — `$FF` means "no card present" — and skips the slot without needing a
bus error exception.

This matches the Snow emulator's approach: all unimplemented/unmapped
addresses return `OPENBUS` (zero in Snow's case) with no bus error.

### Implementation

A 4-bit counter (`nubus_timeout`) starts when `selectNuBus` is asserted but
the video card has not responded (`nubusAck_card` still high). After 4 clocks
the open-bus logic takes over:

- `nubusDataOut` is forced to `$FFFF`
- `nubusAck` is forced low (DTACK asserted)

Once `_cpuAS` deasserts (bus cycle ends), the counter resets.

Applied in both `LBMacTwo.sv` (FPGA) and `verilator/sim.v` (simulation).

## Declaration ROM Byte Lane Mapping

### Current Behavior

The 341-0660 declaration ROM file is stored **inverted** with format byte
`$1E`. After inversion the real format byte is `$E1`, which in the Apple
NuBus convention means **lane 0** (D31–D24 of the 32-bit NuBus). On a real
Mac II the EPROM physically sits on lane 0 of the 32-bit NuBus.

The RTL now matches MAME and keeps the declaration ROM on lane 0. Our FPGA
implementation uses TG68K with a **16-bit data bus** (D15-D0), so NuBus lane 0
is represented as D15-D8 at even byte addresses. The first probe should read
format byte `$E1` at `$FEFFFFFC`, then ROM bytes at `$FEFF8000`,
`$FEFF8004`, etc.

The Slot Manager computes a **ByteLanes** mask from the raw (potentially
inverted) format byte using this algorithm (disassembled from Mac II ROM at
`$408041E0`):

```
upper = format_byte >> 4
lower = (~format_byte) & 0x0F
if upper != lower → error
ByteLanes = ~upper & 0x0F
```

For the de-inverted byte `$E1`, ByteLanes = `$01` = lane 0 only.

### Previous Remap

An earlier workaround remapped the ROM from lane 0 to lane 3 and overrode the
format byte to `$78`. That made the Slot Manager probe `$FEFFFFFF` and walk
`$FEFF8003`, `$FEFF8007`, etc. It was internally consistent, but it did not
match MAME's `m2hires` card and changed the Slot Manager path enough to confuse
boot comparisons.

The current implementation:

1. **De-inverts all bytes**: `rom_byte_out = rom_byte_raw ^ 0xFF`
2. **Keeps the format byte**: `$1E ^ $FF = $E1`
3. **Restricts lane response**: `rom_lane_valid = (addr[1:0] == 2'b00)`; ROM
   data is returned on D15-D8.

MAME reference output for the matched card:

```text
MAME_VIDEO_ROM_R frame=69 pc=408043F4 addr=FEFFFFFC data=E1FFFFFF
MAME_VIDEO_ROM_R frame=69 pc=40804336 addr=FEFF8000 data=01FFFFFF
```

File: `rtl/nubus/nubus_video_highres.sv`

### Remaining Issues

- **BERR stack frame**: TG68K still pushes a 68000-style frame for BERR
  exceptions. Any future use of BERR (e.g. unmapped I/O, write-protect faults)
  will hit the same frame-format crash. Fixing this requires modifying
  `TG68KdotC_Kernel.vhd` to push a format $A frame in 68020 mode.

- **HALT on double bus fault**: TG68K does not implement the 68020 processor
  HALT state. A double bus fault (BERR during BERR exception processing)
  should halt the CPU; currently it loops. This is a separate TG68K
  enhancement.

- **HMMU / AMU**: The Mac II Address Management Unit (controlled by VIA2 PB3)
  gates 24-bit vs 32-bit mode. Currently handled by `addrDecoder.v` with
  a `$80→$00` address mirror hack. A proper HMMU is not needed for basic
  boot but may be required for full System software compatibility.
