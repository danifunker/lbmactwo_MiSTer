# Macintosh II Hardware Implementation Status

Comparison of real Mac II hardware against what is implemented in this FPGA core.
Reference: `docs/My Mac II specs.md`, `docs/mame_boot_sequence.md`, MAME `macii.cpp`.

## Status Legend

- **DONE** — Implemented and believed functional
- **PARTIAL** — Instantiated but incomplete or has known issues
- **STUB** — Decoded in address space but no real logic behind it
- **MISSING** — Not implemented, may cause issues
- **N/A** — Not needed for this core's scope

---

## CPU & Coprocessor

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| MC68020 CPU | 15.6672 MHz | **DONE** | TG68K in 68020 mode, 16 MHz (clk_sys/2). Turbo 32 MHz option. |
| MC68881 FPU | External coprocessor | **DONE** | `mc68881_fpu_lite` via CIR dialog protocol. CIR register remapping applied. |
| MC68851 PMMU | Address Management Unit | **MISSING** | Real Mac II has PMMU. ROM detects it. Core has no MMU — ROM must be no-MMU patched. Not needed for basic operation since we use a no-MMU ROM. |

### Gaps
- **PMMU**: The core uses a no-MMU ROM (`MacII-NoMMU`), so this is acceptable. A standard Mac II ROM would hang trying to initialize the MMU.

---

## Memory

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| RAM | Up to 128 MB (8 MB typical) | **PARTIAL** | 1 MB or 4 MB selectable. SDRAM-backed. No bank B remapping (GLU logic). |
| ROM | 256 KB at $40800000 | **DONE** | Loaded via ioctl index 0. Mapped at $40000000 (32-bit) and $400000 (24-bit). Overlay at $000000 on reset. |
| Memory Overlay | VIA1 PA4 controls | **DONE** | ROM appears at $000000 on reset, cleared by writing VIA1 PA4. |
| RAM Size GLU | VIA2 PA[7:6] → bank config | **MISSING** | ROM writes VIA2 PA[7:6] to configure bank B placement. Core ignores these writes — RAM is flat 4 MB. See VIA2 Phase 3 in `via2_plan.md`. |

### Gaps
- **RAM Size GLU**: ROM writes VIA2 PA[7:6] expecting to move bank B. Core hardcodes flat 4 MB so this is likely benign — ROM memory sizing will probe and find contiguous RAM. But if ROM relies on specific bank placement, it may miscount.
- **Max RAM**: Real Mac II supports up to 128 MB via SIMM slots. Core supports 4 MB max (SDRAM constraint).

---

## VIA Chips

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| VIA1 (SY6522) | $50F00000 | **DONE** | Keyboard/ADB, RTC, sound volume, overlay, mouse (Mac Plus mode). Full timer and shift register support. |
| VIA2 (SY6522) | $50F02000 | **DONE** | Just implemented. Separate address decode, own via6522 instance. |
| VIA2 Port A | PA[7:6]=RAM size, PA[5:0]=NuBus IRQ | **PARTIAL** | PA[7:6] output loopback works. PA[5]=slot E IRQ wired. PA[4:0] hardwired high (no other slots). |
| VIA2 Port B | PB7=timer chain, PB[6:0]=hardwired | **DONE** | PB7 → VIA1 CA1 chain connected. PB input = $CF. |
| VIA2 CA1 | NuBus IRQ aggregator | **PARTIAL** | Directly wired to `nubus_irq_n` from slot E. No re-trigger pulse logic (MAME's `ca1_hack`). |
| VIA2 CB1 | ASC IRQ | **STUB** | Tied high (1'b1). No ASC exists yet. |
| VIA2 Timer A | 60.15 Hz generator | **DONE** | via6522 handles Timer A free-run mode internally. PB7 output toggles and chains to VIA1 CA1. ROM configures the timer latch values. |
| IPL Priority | SCC=4, VIA2=2, VIA1=1 | **DONE** | Corrected from old Mac Plus scheme. NuBus IRQ now flows through VIA2, not directly to CPU. |

### Gaps
- **CA1 re-trigger logic**: MAME has a `via2_ca1_hack` that pulses CA1 high→low when a new slot IRQ fires while others are still active. Without this, multi-slot interrupt scenarios could miss edges. Single-slot (our case) is fine.
- **NuBus slot IRQ routing**: Only slot E is wired. Slots 9-D hardwired inactive. Fine for single video card.

---

## Peripheral I/O

| Component | Real Hardware | Address | Core Status | Notes |
|-----------|-------------|---------|-------------|-------|
| SCC (Z8530) | Serial communications | $50F04000 | **DONE** | Two channels. Mouse quadrature on DCD lines. Serial TX/RX functional. |
| NCR 5380 SCSI | SCSI bus controller | $50F10000 | **DONE** | Two SCSI devices supported. Block device interface to MiSTer SD card. |
| ASC | Apple Sound Chip | $50F14000 | **MISSING** | **Not decoded in address space.** No select signal, no stub. Accesses get default DTACK with garbage data. ROM initializes ASC during boot. |
| IWM | Floppy controller | $50F16000 | **DONE** | IWM floppy controller with two drives. 400K/800K disk images. |
| SWIM | Enhanced floppy (replaces IWM on later Mac II) | $50F16000 | **N/A** | Core targets IWM only per project scope. SWIM mode not needed. |
| RTC (RTC3430042) | Real-time clock + PRAM | via VIA1 PB | **DONE** | 32-byte PRAM with serial protocol. Unix timestamp conversion. Pre-initialized defaults. |
| ADB | Apple Desktop Bus | via VIA1 PB | **DONE** | ADB controller with keyboard/mouse support. ST0/ST1 state machine via VIA1 PB4-PB5. |

### Gaps
- **ASC is the biggest gap.** The address $50F14000-$50F15FFF is not decoded at all. During boot, the ROM:
  1. Writes ASC control registers to initialize sound hardware
  2. May read ASC version register to identify the chip
  3. These accesses won't hang (DTACK is generated by default logic) but will read garbage and writes are silently dropped
  - **Risk**: If ROM loops waiting for an ASC status bit, it will hang. If it just writes config and moves on, it's benign. A stub that returns zeros on read and absorbs writes would be safer.
  - VIA2 CB1 (ASC IRQ line) is tied high, which is correct for "no interrupt pending."

---

## NuBus

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| NuBus bus | 6 slots ($9-$E), 10 MHz | **PARTIAL** | Address decoding for all 6 slots (standard + super slot space). Only slot E has a card. |
| Slot E Video Card | Apple Mac II High-Res | **DONE** | TFB 2.2 ASIC + Bt453 RAMDAC emulation. 640x480, 1/2/4/8 bpp. 512KB VRAM. Declaration ROM loaded via ioctl index 1. |
| Slot E IRQ | VBL interrupt | **PARTIAL** | `nubus_irq_n` wired to VIA2 PA[5] and CA1. No multi-slot aggregation logic. |
| Slots 9-D | Empty | **DONE** | No cards. IRQ bits hardwired inactive (PA[4:0] = 5'b11111). |
| NuBus Arbitration | Bus grant/request | **N/A** | Single master (CPU only). No DMA. |
| Declaration ROM | Per-slot config ROM | **DONE** | Slot E declaration ROM in super slot space ($FE000000+). Byte lane handling for NuBus. |

### Gaps
- **Multi-slot support**: Only one NuBus card (slot E) is supported. The NuBus address decoder handles all 6 slots but only slot E has actual hardware behind it. Adding more cards would require SDRAM arbiter expansion.

---

## Video

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| Built-in video | Mac II has NO built-in video | **DONE** (correct) | No internal framebuffer. All video via NuBus card. |
| NuBus video (TFB 2.2) | 640x480 @ 67 Hz | **DONE** | Pixel clock 30.24 MHz synthesized from 32.5 MHz. VBL interrupt to NuBus IRQ. |
| Bt453 RAMDAC | 256-entry CLUT | **DONE** | On-chip 256x24-bit color LUT. Palette write protocol (addr→R→G→B sequential). |
| Legacy video timer | Mac Plus 512x342 | **DONE** (legacy) | Still runs in `addrController_top` for `_vblank`/`_hblank` timing. Not used for display output. Drives the `onesec` counter for VIA1 CA2. |

### Gaps
- **Video timing source**: The `onesec` counter in `dataController_top` counts `_vblank` edges from the legacy Mac Plus video timer, not from the actual NuBus display. This works because the timer runs regardless, but the frequency may not match the NuBus card's actual VBL rate (67 Hz vs ~60 Hz).
- **Known video bugs**: `docs/hires_nubusplan.md` lists 13 bugs in `nubus_video_highres.sv` (pixel clock accuracy, CLUT auto-increment, VBL timing, VRAM offset, etc.)

---

## Audio

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| ASC (Apple Sound Chip) | 4-voice wavetable + sample playback | **MISSING** | No ASC implementation. See Peripheral I/O section above. |
| Legacy PWM audio | Mac Plus compatible | **DONE** (legacy) | 8-bit sample playback from RAM at VBL rate. 3-bit volume via VIA1 PA[2:0]. Sound enable via VIA1 PB7. |
| Audio output | 22 kHz sample rate | **DONE** | 11-bit signed output (8-bit sample + 3-bit binary volume scaling). Drives MiSTer audio. |

### Gaps
- **ASC**: The Mac II uses the ASC for all sound, not the Mac Plus PWM audio circuit. The legacy audio engine in `addrController_top` reads from Mac Plus sound buffer addresses ($3FFD00 or $3FA100), which is incorrect for Mac II — the ASC has its own address space and wavetable RAM.
- **Practical impact**: The legacy audio may produce noise or silence. Mac II software expects ASC at $50F14000. Without it, system sounds won't work, but boot should not be blocked (sound init failure is typically non-fatal).

---

## Clock & Reset

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| CPU Clock | 15.6672 MHz | **DONE** | 16 MHz (clk_sys/2). Close enough. Turbo mode at 32 MHz. |
| E Clock | CPU/10 (~1.6 MHz) | **DONE** | Generated by TG68K. Drives VIA synchronous bus protocol. |
| PLL | — | **DONE** | 50 MHz → 32.5 MHz (system) + 65 MHz (SDRAM) + 65 MHz phase-shifted (SDRAM chip). |
| System Reset | Power-on + button | **DONE** | 20-bit countdown (~100ms at 8 MHz). OSD reset button. CPU RESET instruction resets peripherals only (not CPU). |

---

## Bus Protocol

| Component | Real Hardware | Core Status | Notes |
|-----------|-------------|-------------|-------|
| DTACK | Active-low data acknowledge | **PARTIAL** | Default DTACK for most peripherals. NuBus has separate ack. FPU uses DSACK. **No bus error timeout** — undecoded addresses get instant DTACK with garbage data instead of bus error. |
| VPA/BERR | Autovector / Bus Error | **PARTIAL** | VPA asserted for FC=7 (autovector interrupts). BERR tied to 0 (never asserted). |
| Bus Arbitration | DMA, NuBus masters | **N/A** | Single master only. BR/BG/BGACK tied off. |

### Gaps
- **No bus error generation**: On a real Mac II, accessing an undecoded address eventually generates a bus error (BERR) after a timeout. This core has BERR permanently deasserted. Accesses to undecoded space (like ASC at $50F14000) silently succeed with garbage data. This could mask ROM bugs or cause subtle issues if the ROM relies on bus error traps for hardware detection.

---

## Address Decoder Coverage

Comparing documented Mac II I/O map against `addrDecoder.v`:

| Address | Device | 32-bit Decode | 24-bit Decode | Status |
|---------|--------|--------------|---------------|--------|
| $50F00000 | VIA1 | $50F0_0000 | $F0_0000 | **DONE** |
| $50F02000 | VIA2 | $50F0_2000 | $F0_2000 | **DONE** |
| $50F04000 | SCC | $50F0_4000 | $F0_4000 | **DONE** |
| $50F10000 | SCSI (NCR5380) | $50F1_0000 | $F1_0000 | **DONE** |
| $50F14000 | ASC | — | — | **MISSING** |
| $50F16000 | IWM/SWIM | $50F1_6000 | $F1_6000 | **DONE** |
| $50F40000 | VIA1 alt (mirror) | $50F4_0000 | $F4_0000 | **DONE** |

---

## Summary of Critical Gaps

### High Priority (may block boot or cause hangs)

1. **ASC not in address decoder** — ROM accesses $50F14000 during init. Currently gets DTACK with garbage data. Could loop if ROM waits for ASC status bits. Minimum fix: add `selectASC` decode and return zeros on read.

### Medium Priority (functional gaps)

2. **RAM Size GLU** — VIA2 PA[7:6] writes ignored. ROM memory sizing may not configure bank B correctly. Likely benign with flat 4 MB but untested.
3. **VIA2 CA1 re-trigger** — No pulse logic for multi-slot NuBus IRQ. Fine with single slot E video card. Would need fixing for additional NuBus cards.
4. **Bus error timeout** — No BERR generation for undecoded addresses. ROM hardware detection probes may silently succeed instead of trapping.

### Low Priority (cosmetic or future)

5. **ASC sound** — No Mac II sound synthesis. Legacy Mac Plus audio engine runs but addresses wrong buffer locations for Mac II.
6. **Video onesec counter** — Uses legacy video timer VBL rate, not NuBus card VBL.
7. **PMMU** — Not implemented, but no-MMU ROM avoids the issue.
8. **Max RAM** — 4 MB vs real 128 MB max. Sufficient for most Mac II software.
