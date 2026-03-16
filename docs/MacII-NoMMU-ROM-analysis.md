# MacII-NoMMU.ROM Disassembly Analysis

## ROM Identity
- **Macintosh II ROM, Rev 1.2** — dated September 1, 1987
- Identification string at the very end: `CPU_68020_\_MacII`
- 256KB (0x00000-0x3FFFF), which is the standard Mac II ROM size
- Built by Apple Computer

## Architecture & Memory Map
- **68020 code** — uses 32-bit addressing, long branches, and extended addressing modes
- **No MMU (PMMU) instructions** — this ROM variant has had 68851/68030 MMU code stripped out
- **VIA base address**: `0x50F00000` — heavily referenced for VIA register access (timers, interrupts, ADB)
- **Nubus slot space**: references to `0x50F10000`, `0x50F14000`, `0x50F18000`, `0x50F1C000` — standard Mac II Nubus slot configuration registers
- **ROM mapped at `0x40800000`** — several `jsr`/`jmp` calls target addresses like `0x40826636`, `0x4080CFAE`, `0x40801DF8`, which are the ROM's runtime base address in the Mac II memory map

## Boot Sequence (offset 0x0090)
1. Issues a `reset` instruction at `0x94`
2. Jumps to hardware initialization at `0x2A14`
3. Calls a series of `bsr` subroutines for early init (RAM test, VIA setup, etc.)
4. Tests for warm start via magic cookie `0x574C5343` ("WLSC") at low-memory location `0x0CFC`
5. Checks for `0xAA5555AA` signature at `0xF80080` (diagnostic ROM check)
6. Sets supervisor mode (`SR = 0x2700`), then transitions to user mode (`SR = 0x2000`) after init

## Trap Dispatch Table
- **~2,646 A-line trap calls** (`.short 0xAxxx`) — these are Macintosh Toolbox/OS trap invocations
- Trap table initialization at offset `0x0D0A`: fills vector table at `0x0E00` (OS traps) and `0x0400` (Toolbox traps) with default "unimplemented" handler, then patches in compressed dispatch entries
- Common traps seen: `_GetResource` (A9A0), `_OpenResFile` (A997), `_InitGraf` (A86E), `_InitWindows` (A851), `_SizeRsrc` (A9A3), etc.

## Device Drivers
- **.Sony** — floppy disk driver (referenced twice, for two driver variants)
- **.Sound** — sound driver (also loaded in two variants)
- **ADB** — Apple Desktop Bus initialization via resource loading
- **FONT** — font resource loading appears multiple times during init

## Interesting Details
- **Dithering/gamma tables** at the end of the ROM — large blocks of repeating 2-letter codes (like `GWNCSLEHBDAFFJLJ...`) which are dithering pattern data, plus gamma correction curves (ascending byte sequences around `0x35D00`)
- The ROM ends with a **checksum region** at `0x3FFE0`-`0x3FFFF`
- The boot code explicitly handles both **4-slot and 6-slot Nubus configurations** (checking `0x50F18000` vs `0x50F14000` for VIA presence)
- Low-memory globals are initialized extensively from `0x300` onward — classic Mac low-memory layout (`0x108` = MemTop, `0x10C` = BufPtr, `0x118` = SysZone, etc.)
