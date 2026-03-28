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

## Declaration ROM Byte Lane Remapping

### Problem

The 341-0660 declaration ROM file is stored **inverted** with format byte
`$1E`. After inversion the real format byte is `$E1`, which in the Apple
NuBus convention means **lane 0** (D31–D24 of the 32-bit NuBus). On a real
Mac II the EPROM physically sits on lane 0 of the 32-bit NuBus.

Our FPGA implementation uses TG68K with a **16-bit data bus** (D15–D0).
NuBus lanes 0 and 1 (D31–D16) are physically inaccessible. We must serve
the ROM on lane 3 (D7–D0) instead.

The Slot Manager computes a **ByteLanes** mask from the raw (potentially
inverted) format byte using this algorithm (disassembled from Mac II ROM at
`$408041E0`):

```
upper = format_byte >> 4
lower = (~format_byte) & 0x0F
if upper != lower → error
ByteLanes = ~upper & 0x0F
```

For the raw inverted byte `$1E`: ByteLanes = `~$1 & $F` = `$0E` = lanes 1,2,3.
The Slot Manager then tries to read the ROM using a 3-lane stride. Since our
16-bit bus only provides data on one lane, the reads are garbled and the test
pattern check (`$5A932BC7`) fails. The card is rejected.

Note: MAME's `install_declaration_rom()` does **not** support format byte
`$1E` at all — it triggers a `fatalerror()`. The only valid single-lane
format bytes are `$E1` (lane 0), `$D2` (lane 1), `$B4` (lane 2), `$78`
(lane 3).

### Fix

Remap the ROM from lane 0 to lane 3 on the fly in
`rtl/nubus/nubus_video_highres.sv`:

1. **De-invert all bytes**: `rom_byte_out = rom_byte_raw ^ 0xFF`
2. **Override format byte**: at the last ROM position, output `$78` (lane 3,
   non-inverted) instead of the de-inverted `$E1`
3. **Restrict lane response**: `rom_lane_valid = (addr[1:0] == 2'b11)` —
   only lane 3 returns ROM data

After remapping:

| Field | Raw file | De-inverted | Served |
|-------|----------|-------------|--------|
| Format byte | `$1E` | `$E1` | `$78` (overridden) |
| Inversion marker (pos −1) | `$FF` | `$00` | `$00` (non-inverted) |
| Test pattern (pos −2..−5) | `$38 D4 6C A5` | `$C7 2B 93 5A` | `$C7 2B 93 5A` = `$5A932BC7` |

The Slot Manager now reads `$78` → ByteLanes = `$08` = lane 3 only, reads
position −1 = `$00` → non-inverted ROM, verifies test pattern → success,
then parses the full sRsrc directory (8000+ bytes read vs 25 before the fix).

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
