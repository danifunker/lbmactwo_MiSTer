# Mac II RAM Configuration

## Overview

The Mac II FPGA core supports 1MB, 2MB, 4MB, and 8MB RAM configurations,
selectable via the OSD menu (status[5:4]). The design matches real Mac II
hardware behavior: out-of-range RAM accesses produce bus errors (BERR)
rather than wrapping, and RAM takes priority over 24-bit peripheral
mappings for addresses within the configured range.

## configRAMSize Encoding

| status[5:4] | configRAMSize | RAM Size | selectRAM Range | VIA2 PA7:6 | Mirror |
|-------------|---------------|----------|-----------------|------------|--------|
| 00          | 2'b00         | 1MB      | $00_0000-$0F_FFFF | 00 (256K SIMMs) | No |
| 01          | 2'b01         | 2MB      | $00_0000-$3F_FFFF plus bank B at $80_0000-$8F_FFFF | 00 (256K SIMMs) | $00-$3F wraps at 2MB; $80-$8F maps bank B |
| 10          | 2'b10         | 4MB      | $00_0000-$3F_FFFF | 01 (1MB SIMMs)  | No |
| 11          | 2'b11         | 8MB      | $00_0000-$7F_FFFF | 01 (1MB SIMMs)  | No |

## Address Decode Priority

RAM takes priority over 24-bit peripheral mappings, matching real Mac II
hardware where the SIMM decoder responds before the peripheral decoder.

For configurations ≤4MB, RAM fits within the $00-$3F range and does not
conflict with 24-bit peripherals (ROM at $40xxxx, I/O at $50xxxx, etc.).

For 8MB, RAM extends into $40-$7F, overriding 24-bit ROM ($40xxxx) and
SCSI ($58xxxx) mappings. Those peripherals remain accessible via their
32-bit addresses:

| Peripheral | 24-bit address (overridden by 8MB RAM) | 32-bit address (always works) |
|------------|----------------------------------------|-------------------------------|
| ROM        | $40_0000-$4F_FFFF                      | $4000_0000-$40FF_FFFF         |
| SCSI       | $58_0000-$5F_FFFF                      | $50F1_0000-$50F1_3FFF         |

The Mac II ROM uses 32-bit addresses for hardware access after turning off
the overlay, so this works without PMMU.

## VIA2 PA7:6 — RAM Sizing Pins

On real Mac II hardware, VIA2 Port A bits 7:6 are connected to the SIMM
decoder and indicate the installed SIMM type. The ROM reads these during
boot to determine the expected memory layout, then probes RAM to find the
actual populated size.

Values (matching Snow emulator's `expected_sz`):

| PA7:6 | SIMM Type | Max RAM (4 banks × 2 SIMMs) |
|-------|-----------|-----------------------------|
| 00    | 256K      | 2MB (1MB without mirror)    |
| 01    | 1MB       | 8MB (4MB without mirror)    |
| 10    | 4MB       | 32MB (not supported on original Mac II ROM) |
| 11    | 16MB      | 128MB (not supported on original Mac II ROM) |

The FPGA sets PA7:6 as hardware input pins (active when VIA2 DDR is
input mode). When the ROM sets DDR to output, the output latch value
is returned instead (loopback).

## RAM Mirroring

The 2MB configuration uses address mirroring to fill the 4MB selectRAM
space. Bit 21 of the SDRAM address is forced to 0, so addresses
$20_0000-$3F_FFFF read/write the same physical RAM as $00_0000-$1F_FFFF.

MAME's default Mac II configuration is 2MB. When the ROM programs the GLUE RAM
bank location for this layout, MAME plants bank B at $0080_0000-$008F_FFFF.
The FPGA address path therefore also maps that 1MB window to the second 1MB RAM
bank. This is needed because the ROM/boot path executes code in the $0082_xxxx
window before reaching the desktop path.

The ROM's sizing algorithm detects this mirror pattern:
1. Write a test pattern at $00_0000
2. Read at $20_0000 — sees the same pattern (mirror)
3. Concludes: 2MB physical RAM with mirroring

Other configurations do not mirror — out-of-range accesses produce
bus errors, which the ROM's sizing algorithm also handles correctly.

## SDRAM Layout

The SDRAM (MT48LC16M16, 32MB) physical address map:

| Region       | SDRAM word address | Byte size | Source |
|--------------|--------------------|-----------|--------|
| RAM          | $000000-$3FFFFF    | Up to 8MB | CPU/video |
| ROM          | $200000-$21FFFF    | 256KB     | ioctl download, `{4'b0001, dio_a}` |
| Floppy Img 1 | via dskReadAck    | ~800KB    | IWM/SWIM |
| Floppy Img 2 | via dskReadAck    | ~800KB    | IWM/SWIM |
| NuBus VRAM   | arbiter vram port | 1MB       | NuBus video card |

Note: For 8MB RAM, the RAM region ($000000-$3FFFFF = 4M words = 8MB)
overlaps with the ROM region in SDRAM. The ROM download uses the
`{4'b0001, ...}` prefix which places ROM at SDRAM word $200000+.
CPU RAM access uses `{3'b000, 0, memoryAddr[21:1]}` which only
reaches SDRAM word $1FFFFF max with the current 22-bit memoryAddr.
This means 8MB RAM currently requires the SDRAM address path in
LBMacTwo.sv to be widened — this is a known limitation pending
verification on FPGA hardware.

## Snow Emulator Reference

The Snow emulator (`/Users/dani/repos/snow/core/src/mac/macii/bus.rs`)
limits Mac II to 8MB maximum, noting:

> Original Mac II ROM breaks > 8 MB; SCSI stops working.

Snow's valid Mac II RAM sizes: 1MB, 2MB, 4MB, 8MB.

Snow uses `ram_mask` for address wrapping and a `ram_mirror` flag per
config. During ROM detection, Snow cuts RAM to 1MB (Mac II only) until
the ROM writes the correct PA7:6 value, then expands to full size.

## Files Involved

- `LBMacTwo.sv` — OSD menu (`O45,Memory,...`), configRAMSize wiring, SDRAM address mux
- `rtl/addrDecoder.v` — selectRAM range gating by configRAMSize
- `rtl/addrController_top.v` — ROM address clamping, 2MB RAM mirror (bit 21)
- `rtl/dataController_top.sv` — VIA2 PA7:6 hardware RAM sizing pins
- `verilator/sim.v` — Verilator sim wrapper (mirrors FPGA changes)
- `verilator/sim_ram.v` — Verilator RAM model (independent range checking)
