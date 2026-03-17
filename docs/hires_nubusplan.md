# Mac II High-Resolution Video Card Implementation Plan

## Target Hardware

- **Card**: Apple Macintosh II High Resolution Video Card
- **ASIC**: TFB 2.2, Apple part number 344S0077
- **RAMDAC**: Bt453 (256-color palette, R/G/B sequential writes)
- **ROM**: `341-0660.bin` (8KB / 0x2000 bytes)
- **Pixel clock**: 30.24 MHz crystal
- **Resolution**: 640x480 @ 60Hz (default), programmable via TFB registers
- **Color depths**: 1bpp, 2bpp, 4bpp, 8bpp
- **VRAM**: 512KB
- **MAME reference**: `src/devices/bus/nubus/nubus_m2hires.cpp`

## Current State

- `rtl/nubus/nubus_video_toby.sv` — active, 1bpp monochrome only, on-chip block RAM, wrong card
- `rtl/nubus/nubus_video_highres.sv` — disabled, partially implemented, many bugs vs MAME
- SDRAM arbiter already has video port wired in `LBMacTwo.sv` (lines 907-967) but undriven

## MAME Address Map (m2hires `card_map`)

All regions mirrored at `$F00000` intervals within the slot's 16MB space:

| Region | Function | Access |
|--------|----------|--------|
| `$00_0000 - $07_FFFF` | VRAM (512KB) | R/W, data XOR `$FFFFFFFF` |
| `$08_0000 - $08_FFFF` | TFB 2.2 registers | W only, data XOR + byte-swap |
| `$09_0000 - $09_FFFF` | Bt453 RAMDAC + VBL status | W: RAMDAC, R: VBL status |
| `$0A_0000 - $0A_FFFF` | VBL interrupt control | W only |

Declaration ROM is installed by NuBus framework at top of slot space (not explicitly in card_map).

## MAME Register Details

### TFB 2.2 Registers (write at `$08_xxxx`)

Written as 32-bit words, inverted (`^= 0xFFFFFFFF`) then byte-swapped (`swapendian_int32`).

| Index | Name | Description |
|-------|------|-------------|
| 0 | BASE | VRAM offset to start drawing, in 32-bit words (masked to 17 bits) |
| 1 | LENGTH | Scanline stride in 32-bit words (masked to 10 bits), byte stride = LENGTH << 2 |
| 2 | MISC | Bits [10:8] = mode. Bt453: mode-4 gives depth (0=1bpp,1=2bpp,2=4bpp,3=8bpp) |
| 3 | SYNCINTERVAL | Vertical sync interval |
| 4 | VFRONTPORCH | V front porch - 1 |
| 5 | VBACKPORCH | V back porch - 8 |
| 6 | VLINES | Total visible half-lines - 1 |
| 7 | HFRONTPORCH | H front porch pixels - 2 |
| 8 | HSYNCPULSE | H sync pulse width pixels - 4 |
| 9 | HBACKPORCH | H back porch pixels - 4 |
| 10 | HFIRST | First section of visible area - 2 |
| 11 | HLAST | Second section of visible area - 2 |
| 12 | SOFTRESET | Bit 0 = 1 enables video generation |

Timing recalculation is triggered when BASE is written AND SOFTRESET bit 0 is set.

### MAME Timing Formulas

```
hmult = 16 >> mode
htotal = (HFRONTPORCH+2 + HSYNCPULSE+2 + HBACKPORCH+4 + HFIRST+2 + HLAST+2) * hmult
vtotal = (VFRONTPORCH+1 + VBACKPORCH+8 + VLINES+1) / 2 + 3
vres   = VLINES/2 + 1
hres   = (HFIRST+2 + HLAST+2) * hmult
```

### Bt453 RAMDAC (write at `$09_xxxx`)

MAME `ramdac_w`: data is inverted (`^= 0xFFFFFFFF`), then:
- `offset & 1 == 0`: `address_w(data)` — sets palette index, resets R/G/B counter
- `offset & 1 == 1`: `palette_w(data)` — writes R, G, B sequentially, auto-increments address after B

On 32-bit NuBus, `offset & 1` means 32-bit word offset. On our 16-bit bus, this maps to `addr[2]`.

The Bt453 `address_w` takes 8 bits. The `palette_w` takes 8 bits (R, G, B in sequence).
The Bt453 internally tracks which color component (R/G/B) to write next.

### VBL Status Read (read at `$09_xxxx`)

MAME `vblank_r`: at offset `0x10/4` (byte address `$09_0010`):
- Returns `(vblank << 16) | (1 << 17)` as 32-bit value
- Bit 16: 1 during vblank, 0 during active
- Bit 17: monitor sense ID bit (1 = Hi-Res RGB monitor)

### VBL Interrupt Control (write at `$0A_xxxx`)

- `offset & 4` set (byte addr bit 4): disable VBL interrupt
- `offset & 4` clear: enable VBL interrupt, clear pending IRQ

### VRAM Data Inversion

All VRAM reads and writes are XOR'd with `$FFFFFFFF`. CPU writes inverted data to VRAM;
CPU reads get inverted data back. Video scanout reads raw VRAM and uses RAMDAC pens
to convert pixel indices to colors.

### Screen Update (video scanout)

```
vram8 = base_of_vram + (BASE & 0x1ffff) * 4   // byte pointer
stride = (LENGTH & 0x3ff) * 4                   // bytes per scanline

For each scanline y, each byte x:
  pixel_byte = vram8[y * stride + x]

1bpp: each bit = 1 pixel, index 0 or 1        (stride typically 80 = 640/8)
2bpp: each 2 bits = 1 pixel, index 0-3        (stride typically 160 = 640/4)
4bpp: each nibble = 1 pixel, index 0-15       (stride typically 320 = 640/2)
8bpp: each byte = 1 pixel, index 0-255        (stride typically 640)
```

---

## Bugs in Current `nubus_video_highres.sv`

### Bug 1: Module name
Module is `nubus_video`, should be `nubus_video_highres`.

### Bug 2: ROM size
Allocates 32KB (`reg [7:0] rom [0:32767]`). Should be 8KB for m2hires ROM `341-0660.bin`.

### Bug 3: ROM download addressing
Uses `ioctl_addr[13:0]` (16KB byte range). Should be `ioctl_addr[12:0]` (8KB).

### Bug 4: ROM read address
Maps ROM at `addr[23:20] == 4'hF` (offset `$0F_xxxx`). NuBus declaration ROMs live at the
top of the slot address space. Need to verify where `341-0660.bin` expects to be. The toby
card maps ROM at `addr[23:16] == 8'h01` — we need to match whatever the ROM's internal
directory pointer says.

### Bug 5: RAMDAC address decode
Uses `addr[1]` to distinguish address vs palette writes. Should be `addr[2]` since MAME's
`offset & 1` refers to 32-bit word offset (4 bytes apart).

### Bug 6: RAMDAC write handling
Current code manually tracks R/G/B with `ramdac_color_index` and writes to a CLUT array.
MAME passes data directly to the Bt453 which internally tracks the R/G/B sequence.
Our implementation should match: write R/G/B sequentially to the CLUT, auto-increment
address after B. The current logic is close but the address decode (Bug 5) makes it wrong.

### Bug 7: Register write endianness
MAME does `data ^= 0xFFFFFFFF; data = swapendian_int32(data)`. The byte-swap means on a
16-bit bus: what the CPU writes to `addr[1]==0` (high word of 32-bit) should go into the
LOW 16 bits of the register, and `addr[1]==1` (low word) into the HIGH 16 bits.
Current code has this backwards.

### Bug 8: VBL status read
Returns same value regardless of which 16-bit half is read. Should return vblank/monitor
bits only on the high word (`addr[1]==0`), zero on low word.

### Bug 9: Missing `ce_pixel` output
MiSTer framework requires this. Need `output ce_pixel` assigned to `clk_video_en`.

### Bug 10: Missing `overlay_en` input
Toby card has this for MiSTer OSD. Not critical but needed for port compatibility.

### Bug 11: `vga_blank` polarity
Current code: `assign vga_blank = vga_blank_reg` where `vga_blank_reg` is 1 during blanking.
MiSTer expects active-high DE (1 = active display). Should be `~vga_blank_reg`.

### Bug 12: Pixel clock
Uses 25.175 MHz accumulator. MAME m2hires uses 30.24 MHz crystal. Need to change the
accumulator ratio to generate 30.24 MHz from clk_sys (32.5 MHz).

### Bug 13: Video timing parameters
Hard-coded H_TOTAL=864, V_TOTAL=525 etc. MAME defaults to H_TOTAL=896, V_TOTAL=525.
These should match MAME defaults (896x525) and be reconfigurable via TFB registers.

### Bug 14: VRAM fetch address calculation
The prefetch/stride math uses mixed units (32-bit words vs bytes). Needs careful
reconciliation with MAME's byte-addressed scanout.

---

## Implementation Phases

### Phase 1: Fix nubus_video_highres.sv core logic

Fix all bugs listed above against the MAME reference:
- Rename module
- Fix ROM size and addressing
- Fix register write endianness (byte-swap)
- Fix RAMDAC address decode (`addr[2]`)
- Fix VBL status read
- Fix `vga_blank` polarity
- Fix pixel clock to 30.24 MHz
- Fix default video timing (896x525)
- Add `ce_pixel` and `overlay_en` ports
- Fix VRAM fetch address math

### Phase 2: Wire up in LBMacTwo.sv

- Replace `nubus_video_toby` instantiation with `nubus_video_highres`
- Connect SDRAM arbiter VRAM ports (`arb_vram_*`)
- Connect all other ports (video, ioctl, irq, etc.)

### Phase 3: Update build files

- `files.qip`: swap toby for highres
- Verify Quartus can still synthesize

### Phase 4: Update verilator sim

- `verilator/sim.v`: switch to `nubus_video_highres`
- Add sim VRAM (simple synchronous RAM with ready handshake)
- Connect VRAM interface

### Phase 5: ROM and testing

- Obtain `341-0660.bin` ROM dump
- Verify ROM address mapping matches ROM's internal directory
- Test in verilator sim
- Test on FPGA hardware
