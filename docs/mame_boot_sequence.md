# MAME Mac II (maciihmu) Boot Sequence Reference

Source: MAME source code analysis, primarily `src/mame/apple/macii.cpp` and related files.

This documents the complete boot sequence as modeled by MAME for the `maciihmu` machine
(Macintosh II without 68851 MMU, using the M68020HMMU software MMU emulation).

---

## 1. Machine Configuration Overview

The `maciihmu` machine config is built on the base `macii` config with one change:
it replaces the M68020PMMU CPU with M68020HMMU (hardware-managed MMU emulation) and
uses `hmmu_via2_out_b` which can enable/disable the HMMU via VIA2 port B bit 3.

Key devices:
- **CPU**: M68020HMMU at 15.6672 MHz (C15M)
- **VIA1**: R65NC22 at C7M/10 (783.36 KHz) -- main system VIA
- **VIA2**: R65NC22 at C7M/10 -- NuBus/interrupt/RAM control VIA
- **SCC**: SCC85C30 at C7M (7.8336 MHz)
- **ASC**: Apple Sound Chip at C15M
- **SCSI**: NCR53C80
- **Floppy**: IWM controller
- **RTC**: RTC3430042 (343-0042-B, 256-byte PRAM)
- **ADB**: ADB Modem PIC (342S0440-B) + HLE ADB device
- **NuBus**: 6 slots ($9 through $E), slot $9 defaults to MDC 8*24 video card
- **RAM**: 2 MB default (options: 1M, 4M, 5M, 8M)
- **ROM**: 256 KB (0x40000 bytes), loaded at region "bootrom"

ROM checksums recognized:
- `0x9779d2c4` -- Mac II Rev B ROM (default)
- `0x97851db6` -- Mac II Rev A ROM

Source: `macii.cpp` lines 922-1046, 1136-1150.

---

## 2. Initialization Sequence (Before Reset)

### 2.1 macii_init() -- Driver Init

Called once at driver load time (`macii.cpp` line 780):

1. Set `m_overlay = 1`, clear all interrupt flags
2. Determine ROM size and pointer from the "bootrom" memory region
3. Force overlay on: set `m_overlay = -1`, then call `set_memory_overlay(1)`
   - This installs ROM at address `0x00000000` through `ROM_SIZE - 1`
4. Zero-fill all RAM
5. Register post-load callback for save states

### 2.2 machine_start() -- Device Start

Called after all devices are started (`macii.cpp` line 719):

1. Set up scanline timer (only if screen device exists -- not the case for maciihmu
   which has no built-in screen; video comes from NuBus card)
2. Register save state items
3. Read the first dword of address space to check ROM ID:
   - If `0x97851db6` or `0x9779d2c4`, set `m_is_original_ii = true`
   - This flag is used for RAM sizing compatibility

---

## 3. Reset Sequence

### 3.1 machine_reset()

Called on every reset (`macii.cpp` line 750):

1. `m_last_taken_interrupt = -1`
2. **Overlay ON**: `m_overlay = -1` (force mismatch), then `set_memory_overlay(1)`
   - Installs ROM at `0x00000000` through `0x0003FFFF`
3. `m_screen_buffer = 1`
4. VIA2 CA1 set high (no NuBus interrupt pending)
5. VIA2 CB1 set high (no ASC interrupt)
6. Clear SCSI interrupt flag
7. `m_via2_vbl = 0`, `m_se30_vbl_enable = 0`
8. **`m_nubus_irq_state = 0xff`** (all slot IRQs deasserted -- bits are active-low)
9. `m_last_taken_interrupt = 0`

### 3.2 CPU Reset Behavior

The M68020 reads the initial SSP from address `0x00000000` and the initial PC from
`0x00000004`. With overlay ON, these come from the ROM image.

For the Mac II Rev B ROM (`0x9779d2c4`):
- Address 0x00000000 (SSP): loaded from ROM offset 0x0
- Address 0x00000004 (PC): loaded from ROM offset 0x4

The CPU begins executing from the ROM entry point.

---

## 4. Memory Map

### 4.1 Static Address Map (macii_map)

Defined in `macii.cpp` line 892. These are always present regardless of overlay state:

| Address Range | Device | Notes |
|---|---|---|
| `$4000_0000 - $4003_FFFF` | Boot ROM | Mirrored across `$4000_0000 - $4FFF_FFFF` (mirror `$0FFC_0000`) |
| `$5000_0000 - $5000_1FFF` | VIA1 | Mirrored every 1 MB (`$00F0_0000` mirror) |
| `$5000_2000 - $5000_3FFF` | VIA2 | Mirrored every 1 MB |
| `$5000_4000 - $5000_5FFF` | SCC | Mirrored every 1 MB |
| `$5000_6000 - $5000_6003` | SCSI DRQ write | Mirrored every 1 MB |
| `$5000_6060 - $5000_6063` | SCSI DRQ read | Mirrored every 1 MB |
| `$5001_0000 - $5001_1FFF` | SCSI (NCR5380) | Mirrored every 1 MB |
| `$5001_2000 - $5001_3FFF` | SCSI DRQ r/w | Mirrored every 1 MB |
| `$5001_4000 - $5001_5FFF` | ASC | Mirrored every 1 MB |
| `$5001_6000 - $5001_7FFF` | IWM/Floppy | Mirrored every 1 MB |
| `$5004_0000 - $5004_1FFF` | VIA1 (duplicate) | Mirrored every 1 MB |
| `$9000_0000 - $EFFF_FFFF` | NuBus super slot space | Via NuBus bus device |
| `$F900_0000 - $FEFF_FFFF` | NuBus slot space | Via NuBus bus device |

Note: The comment "MMU remaps I/O without the F" at line 896 indicates that the
physical hardware has I/O at `$F0xx_xxxx` but the Mac II ROM's MMU tables map it
to `$50xx_xxxx`. In MAME, the address map directly uses `$50xx_xxxx`.

### 4.2 Overlay ON (Reset State)

ROM is installed at `$0000_0000` through `$0003_FFFF` (256 KB), overlaying RAM.
The permanent ROM mapping at `$4000_0000` is also still active.

### 4.3 Overlay OFF (Normal Operation)

When overlay is turned off (via VIA1 port A bit 4 = 0), the `set_memory_overlay()`
function calls `via2_out_a(0x3f)` which triggers the RAM configuration logic.

RAM is installed starting at `$0000_0000` based on the `m_glue_ram_size` value
(VIA2 port A bits 7:6), which controls Bank B placement:

| glue_ram_size bits | Bank B Location |
|---|---|
| `00` | 1 MB (`$0010_0000`) |
| `01` | 2 MB (`$0020_0000`) |
| `10` | 8 MB (`$0080_0000`) |
| `11` | 32 MB (`$0200_0000`) |

The ROM code iterates through these settings to size RAM. The `via2_out_a()` function
(line 573) handles the complex RAM mirroring logic needed to pass the ROM's RAM test.

For the original Mac II ROM, RAM is limited to 8 MB maximum. The ROM first unmaps
`$0000_0000 - $3FFF_FFFF`, then installs the RAM with appropriate mirroring.

### 4.4 NuBus Address Spaces

The NuBus device (`nubus.cpp` line 101, NORMAL mode) maps:

**CPU-visible (installed into CPU address space):**
- `$9000_0000 - $EFFF_FFFF` -- NuBus super slot space (256 MB per slot)
- `$F900_0000 - $FEFF_FFFF` -- NuBus standard slot space (16 MB per slot)

**NuBus card-visible (NuBus AS_DATA space, for cards to access host):**
- `$0000_0000 - $3FFF_FFFF` -- Host RAM
- `$F000_0000 - $F07F_FFFF` -- Host I/O (mapped to CPU's `$5000_0000`)
- `$F080_0000 - $F0FF_FFFF` -- Host ROM (mapped to CPU's `$4000_0000`)

Slot space formula:
- Standard slot space: `$Fs00_0000` where s = slot number ($9-$E)
- Super slot space: `$s000_0000` where s = slot number ($9-$E)

So for slot $9 (default video card): standard = `$F900_0000-$F9FF_FFFF`, super = `$9000_0000-$9FFF_FFFF`.

---

## 5. Overlay Handling

### 5.1 The Overlay Bit

**Location**: VIA1 Port A, bit 4

**Writer**: `via_out_a()` at line 436:
```cpp
void macii_state::via_out_a(u8 data)
{
    m_screen_buffer = BIT(data, 6);
    if (m_cur_floppy)
        m_cur_floppy->ss_w(BIT(data, 5));
    set_memory_overlay(BIT(data, 4));
}
```

**VIA1 Port A bit assignments:**
- Bit 7: read as 1 (via_in_a returns `0x81`)
- Bit 6: Screen buffer select (SE/30 only)
- Bit 5: Floppy side select (active on write)
- Bit 4: **Memory overlay** (1 = ROM at 0, 0 = RAM at 0)
- Bit 3-1: not used in output
- Bit 0: read as 1 (via_in_a returns `0x81`)

### 5.2 How Overlay Gets Turned Off

The Mac II ROM turns off overlay by writing to VIA1 register ORA (Output Register A,
offset 0x1 in the VIA) or DDRA with bit 4 = 0. The VIA device calls the `writepa`
handler, which calls `via_out_a()`, which calls `set_memory_overlay(0)`.

In `set_memory_overlay()` (line 288):
1. Check if overlay state actually changed
2. If turning ON: install ROM at address 0
3. If turning OFF: call `via2_out_a(0x3f)` to configure RAM

The ROM typically does this very early in the boot process, after it has copied
necessary code/data to RAM and is ready to run from RAM-based addresses or from
the permanent ROM mapping at `$4000_0000`.

---

## 6. VIA Configuration

### 6.1 VIA1 (System VIA)

Address: `$5000_0000` (with `$00F0_0000` mirror)

VIA register access uses offset bits [15:8] as the register number, so:
- ORA/IRA: `$5000_0200` (register 1, or `$5000_1E00` for register 15/IRA no handshake)
- DDRB: `$5000_0400`
- DDRA: `$5000_0600`
- etc.

**Port A connections:**
- PA0: reads as 1 (hardwired)
- PA4: overlay control (output)
- PA5: floppy side select (output)
- PA6: screen buffer select (output, SE/30)
- PA7: reads as 1 (hardwired)

**Port B connections:**
- PB0: RTC data
- PB1: RTC clock
- PB2: RTC chip enable
- PB3: ADB IRQ pending (input, active low -- 0 = IRQ pending)
- PB4-PB5: ADB modem "newaction" bits (output to ADB modem PIC)

**CA1**: RTC CKO (1 Hz clock from RTC)
**CA2**: RTC CKO (also connected)
**CB1**: ADB modem shift clock (input from PIC)
**CB2**: ADB modem shift data (bidirectional)

**IRQ**: Directly drives CPU IPL1 (interrupt level 1)

### 6.2 VIA2 (NuBus/System VIA)

Address: `$5000_2000` (with `$00F0_0000` mirror)

**Port A connections (active-low for IRQ bits):**
- PA0: NuBus slot $9 IRQ (active low)
- PA1: NuBus slot $A IRQ
- PA2: NuBus slot $B IRQ
- PA3: NuBus slot $C IRQ
- PA4: NuBus slot $D IRQ
- PA5: NuBus slot $E IRQ
- PA6-PA7: RAM size config (glue_ram_size), written by ROM during RAM sizing

**Port B connections:**
- PB3: HMMU enable (maciihmu only -- 0 = enable HMMU)
- PB7: chained to VIA1 CA1 for 60.15 Hz interrupt

**CA1**: NuBus IRQ (directly -- active low when any slot has pending IRQ)
**CB1**: ASC IRQ (active low)

**IRQ**: Directly drives CPU IPL2 (interrupt level 2)

---

## 7. Interrupt Architecture

### 7.1 Priority Levels

From `field_interrupts()` (line 235):

| CPU IPL | Source | MAME Priority |
|---|---|---|
| IPL4 (level 4) | SCC | Highest |
| IPL2 (level 2) | VIA2 | Medium |
| IPL1 (level 1) | VIA1 | Lowest |

Note: The Mac II "GLUE" chip on real hardware handles interrupt prioritization.
MAME models this directly in `field_interrupts()`.

### 7.2 NuBus Interrupt Flow

1. NuBus card asserts its slot IRQ line (e.g., video VBL)
2. `nubus_device::set_irq_line()` fires the appropriate callback
3. `macii_state::nubus_irq_w<Slot>()` is called
4. `nubus_slot_interrupt()` updates `m_nubus_irq_state` bitmask
5. If any slot IRQ is pending (any bit of lower 6 bits is 0), VIA2 CA1 is driven low
6. VIA2 generates IRQ, which drives CPU IPL2
7. ROM reads VIA2 port A to determine which slot(s) are interrupting

### 7.3 VBL Interrupt (60.15 Hz)

VIA2 Port B bit 7 is toggled and chained to VIA1 CA1:
```cpp
void macii_state::via2_out_b(u8 data)
{
    m_via1->write_ca1(data >> 7);
}
```

This provides the 60.15 Hz system VBL interrupt to VIA1. The NuBus video card
has its own separate VBL interrupt mechanism through the NuBus IRQ lines.

---

## 8. NuBus Slot Scanning

### 8.1 How the ROM Scans for Cards

The Mac II ROM performs NuBus slot scanning by reading the Declaration ROM area
at the top of each slot's standard slot space. For each slot $9 through $E:

1. **Probe address**: `$Fs00_0000` + `$00FF_FFFC` = `$FsFF_FFFC`
   (last 4 bytes of each slot's 16 MB space)

2. The ROM reads the last longword of the slot space. This contains the
   **byte lanes** marker and offset to the start of the Declaration ROM
   directory structure.

3. If a bus error occurs (no card present), the slot is skipped.

4. If valid data is found, the ROM follows the Declaration ROM format:
   - Byte at offset -1 from end: byte lanes indicator
   - Byte at offset -2: test pattern (0x00 normal, 0xFF inverted)
   - Longword at offset -4: CRC
   - Longword at offset -8: length of Declaration ROM
   - The ROM structure contains a directory (sResource list) describing
     the card's capabilities

### 8.2 Declaration ROM Installation (MAME Side)

Each NuBus card calls `install_declaration_rom()` during its `device_start()`.
This function (`nubus.cpp` line 399):

1. Reads the raw ROM data from the card's ROM region
2. Checks the byte lanes byte (last byte of ROM) to determine data layout:
   - `0x0F`: all 4 byte lanes (32-bit)
   - `0xE1`: lane 0 only (data in bytes 0, 4, 8, ...)
   - `0xD2`: lane 1 only
   - `0xB4`: lane 2 only
   - `0x78`: lane 3 only
   - `0xC3`: lanes 0,1
   - `0xA5`: lanes 0,2
   - `0x3C`: lanes 2,3
3. Handles inverted ROMs (second-to-last byte = 0xFF)
4. Installs the ROM at: `get_slotspace() + 0x01000000 - romlen`
   i.e., the ROM occupies the highest addresses of the slot's 16 MB space
5. If `mirror_all_mb` is true, mirrors the ROM across all 16 MB

For the MDC 8*24 in slot $9:
- Slot space: `$F900_0000`
- Declaration ROM: installed at top of `$F900_0000 - $F9FF_FFFF`

For the Mac II Hi-Res card (m2hires):
- 8 KB Declaration ROM (`0x2000` bytes)
- Installed with `mirror_all_mb = true`
- So ROM appears at `$Fs00_E000 - $Fs00_FFFF` and is mirrored every 8 KB across
  the entire 16 MB slot space

### 8.3 NuBus Card Memory Maps

Each card installs its own registers and VRAM using `nubus().install_map()`.

**MDC 8*24 (nubus_48gc.cpp, slot $9):**
- VRAM: `$F900_0000 - $F91F_FFFF` (up to 2 MB via memory view)
- Registers and RAMDAC: mapped via `card_map` within the slot space

**Mac II Hi-Res (nubus_m2hires.cpp, slot $9 example):**
- `$Fs00_0000 - $Fs07_FFFF`: VRAM (512 KB), mirrored every 1 MB
- `$Fs08_0000 - $Fs08_FFFF`: CRTC registers (write), mirrored
- `$Fs09_0000 - $Fs09_FFFF`: VBL status / RAMDAC (read/write), mirrored
- `$Fs0A_0000 - $Fs0A_FFFF`: VBL control (write), mirrored
- Declaration ROM: top of slot space, mirrored across all 16 MB

---

## 9. Boot Sequence Timeline

Based on the MAME model and Mac II ROM behavior:

### Phase 1: CPU Reset and Initial ROM Execution
1. CPU reads initial SSP from `$0000_0000` (ROM via overlay)
2. CPU reads initial PC from `$0000_0004` (ROM via overlay)
3. CPU begins executing ROM startup code
4. ROM has access to itself at both `$0000_0000` (overlay) and `$4000_0000` (permanent)

### Phase 2: Early Hardware Init
5. ROM initializes VIA1 and VIA2 (DDR, initial port values)
6. ROM accesses RTC to read PRAM (time, boot device, monitor settings)
   - RTC access is via VIA1 PB0 (data), PB1 (clock), PB2 (CE) -- bit-banged serial
7. ROM initializes the SCC (serial communications controller)
8. ROM initializes the ADB subsystem via the ADB Modem PIC
   - ADB modem is controlled via VIA1 PB4-PB5 (state), CB1/CB2 (shift register)

### Phase 3: Memory Sizing (Overlay Turn-Off)
9. ROM disables overlay by writing VIA1 Port A with bit 4 = 0
   - `via_out_a()` calls `set_memory_overlay(0)`
   - `set_memory_overlay(0)` calls `via2_out_a(0x3f)` to configure RAM
10. ROM performs RAM sizing by writing different values to VIA2 Port A bits 7:6
    - Tests each Bank B location (1M, 2M, 8M, 32M)
    - Reads/writes test patterns to determine actual RAM size
    - Each write to VIA2 ORA triggers `via2_out_a()` which reconfigures the
      RAM mapping with appropriate mirrors
11. After sizing, ROM knows total RAM and configures final memory map

### Phase 4: NuBus Slot Scanning
12. ROM scans NuBus slots $9 through $E (or $E down to $9)
    - For each slot, reads `$FsFF_FFFC` to check for Declaration ROM
    - Bus error (no response) means no card in slot -- ROM uses bus error
      exception handler to skip empty slots
13. For each card found, ROM reads the Declaration ROM directory:
    - Parses sResource entries
    - Identifies card type (video, network, etc.)
    - Records card capabilities

### Phase 5: Video Card Initialization
14. ROM selects primary video card (first/only video card found, or PRAM setting)
15. ROM executes the card's sPrimaryInit code from its Declaration ROM:
    - Configures CRTC timing registers
    - Sets pixel depth (1-bit initially for boot screen)
    - Configures RAMDAC/CLUT (loads gray ramp)
    - Enables video output
16. For MDC 8*24: ROM writes CRTC registers, sets up VRAM base/stride, enables display
17. For Mac II Hi-Res: ROM writes the 13 TFB registers, programs Bt453 CLUT, sets SOFTRESET bit 0

### Phase 6: Boot Screen and System Startup
18. ROM displays the "Happy Mac" or startup screen on the video card
19. ROM initializes SCSI bus, looks for boot device
20. ROM loads system file from boot device
21. System takes over, may reconfigure video depth/resolution via Monitors control panel

---

## 10. Key MAME Implementation Details

### 10.1 VIA Register Access Timing

VIA access includes cycle-accurate synchronization (`via_sync()`, line 473).
The VIA runs at 783.36 KHz while the CPU runs at 15.6672 MHz, a 20:1 ratio.
Each VIA access stalls the CPU to align with VIA clock edges.

### 10.2 SCSI Pseudo-DMA

SCSI uses pseudo-DMA at specific offsets:
- Read pseudo-DMA: register 6 at offset `$130` (byte read)
- Write pseudo-DMA: register 0 at offset `$100` (byte write)
- 32-bit DRQ read: `$5000_6060`
- 32-bit DRQ write: `$5000_6000`

SCSI timeout generates a bus error via `scsi_berr_w()`.

### 10.3 IWM/Floppy Access Penalty

Each IWM access costs 5 extra CPU cycles (`m_maincpu->adjust_icount(-5)`),
simulating the real hardware's slow floppy controller access.

### 10.4 HMMU (maciihmu specific)

The maciihmu machine uses VIA2 Port B bit 3 to control the HMMU:
```cpp
void macii_state::hmmu_via2_out_b(u8 data)
{
    m68000_musashi_device *m68k = downcast<m68000_musashi_device *>(m_maincpu.target());
    m68k->set_hmmu_enable((data & 0x8) ? M68K_HMMU_DISABLE : M68K_HMMU_ENABLE_II);
    via2_out_b(data);
}
```

When bit 3 = 0, HMMU is enabled (the ROM has set up HMMU tables).
When bit 3 = 1, HMMU is disabled (24-bit mode or early boot).

### 10.5 ROM Identification

MAME reads the first longword of ROM to identify it:
- `0x97851db6` -- Original Mac II ROM (Rev A)
- `0x9779d2c4` -- Mac II ROM Rev B (default for macii/maciihmu)
- `0x97221136` -- Mac II FDHD/IIx/IIcx/SE30 ROM

The `m_is_original_ii` flag (set for the first two) affects RAM sizing behavior:
the original II ROM cannot handle more than 8 MB of RAM.

---

## 11. NuBus Card VBL Interrupt Details

### 11.1 Video Card VBL Flow

Using the Mac II Hi-Res card as example:

1. Card has a timer that fires at the start of each vertical blank period
2. If VBL interrupts are enabled (`m_vbl_disable == 0`):
   - Card calls `raise_slot_irq()` which calls `nubus().set_irq_line(slot, ASSERT_LINE)`
3. NuBus device fires the slot's IRQ callback (e.g., `out_irq9_callback`)
4. `macii_state::nubus_irq_w<9>()` is called, which calls `nubus_slot_interrupt(9, 1)`
5. `nubus_slot_interrupt()`:
   - Clears bit 0 (slot 9-9=0) of `m_nubus_irq_state`
   - Since `(m_nubus_irq_state & 0x3f) != 0x3f`, drives VIA2 CA1 low
6. VIA2 generates an interrupt, which asserts CPU IPL2

### 11.2 VBL Acknowledge

The ROM's VBL interrupt handler:
1. Reads VIA2 Port A to see which slot(s) are interrupting
2. Accesses the card's VBL acknowledge register
3. For Mac II Hi-Res: writes to offset `$0A_0000` with bit pattern to clear VBL
   - `vbl_w()` calls `lower_slot_irq()` which deasserts the NuBus IRQ line
4. When all slot IRQs are cleared, VIA2 CA1 goes high

---

## 12. Address Summary Table

For quick reference when debugging the FPGA core:

| Address | What | Access |
|---|---|---|
| `$0000_0000` | RAM (or ROM if overlay on) | R/W |
| `$4000_0000` | Boot ROM (256 KB, mirrored to $4FFF_FFFF) | R |
| `$5000_0000` | VIA1 | R/W |
| `$5000_0200` | VIA1 ORA -- overlay bit 4 | R/W |
| `$5000_2000` | VIA2 | R/W |
| `$5000_2200` | VIA2 ORA -- NuBus IRQ + RAM size | R/W |
| `$5000_4000` | SCC | R/W |
| `$5000_6000` | SCSI DRQ | R/W |
| `$5001_0000` | SCSI (NCR5380) | R/W |
| `$5001_4000` | ASC | R/W |
| `$5001_6000` | IWM/Floppy | R/W |
| `$9000_0000-$9FFF_FFFF` | NuBus slot $9 super slot space | R/W |
| `$A000_0000-$AFFF_FFFF` | NuBus slot $A super slot space | R/W |
| `$B000_0000-$BFFF_FFFF` | NuBus slot $B super slot space | R/W |
| `$C000_0000-$CFFF_FFFF` | NuBus slot $C super slot space | R/W |
| `$D000_0000-$DFFF_FFFF` | NuBus slot $D super slot space | R/W |
| `$E000_0000-$EFFF_FFFF` | NuBus slot $E super slot space | R/W |
| `$F900_0000-$F9FF_FFFF` | NuBus slot $9 standard slot space | R/W |
| `$FA00_0000-$FAFF_FFFF` | NuBus slot $A standard slot space | R/W |
| `$FB00_0000-$FBFF_FFFF` | NuBus slot $B standard slot space | R/W |
| `$FC00_0000-$FCFF_FFFF` | NuBus slot $C standard slot space | R/W |
| `$FD00_0000-$FDFF_FFFF` | NuBus slot $D standard slot space | R/W |
| `$FE00_0000-$FEFF_FFFF` | NuBus slot $E standard slot space | R/W |
| `$FsFF_FFFC` | Declaration ROM probe address (per slot) | R |
