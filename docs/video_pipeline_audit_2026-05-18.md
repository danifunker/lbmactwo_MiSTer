# Video pipeline audit — 2026-05-18

## TL;DR

**The display pipeline is correct.** Proven by JTAG test patterns
(`captures/v7_tp1.png`: clean color bars) and CLUT-forced scanout
(`captures/v7_force_wb.png`: legible 1bpp read of VRAM contents).

The previous "noise" appearance came from two compounding issues we
fixed:

1. **Three layers of MAME-style `^= 0xFFFFFFFF` XOR inversions** in
   the video card's CPU bus paths (VRAM write, CLUT address, CLUT
   data, CPU read) that made Mac's slot-0/1 palette writes land in
   our clut[0xFF]/clut[0xFE] and rendered nonsense in 1bpp.

2. **Mac has not actually drawn anything** because it's stuck in the
   SCSI-timeout loop at `$40826CC6`.  Without VRAM writes from
   Mac, the framebuffer is whatever uninitialized SDRAM contains
   (~50/50 random bits).

After the fixes the screen renders **exactly what's in VRAM with
exactly the CLUT Mac actually programmed** — there's just nothing
useful for it to render until boot progresses.

## What we proved

### Display path is correct (`captures/v7_tp1.png`)

JTAG-driven test pattern 1 (8 vertical color bars, direct RGB,
bypassing VRAM and CLUT) renders crisp white/yellow/cyan/green/
magenta bars with no noise.

→ Sync, blanking, DE, pixel clock, RGB output wiring are all sound.
The 640×480 active area is correct (5 visible 128-px bars).

### CLUT lookup is correct (`captures/tp3_checker.png`)

Test pattern 3 (checkerboard, `pixel_idx ∈ {0, 1}` indexing the
real CLUT) renders a crisp checker.  Whatever colors are in
`clut[0]` and `clut[1]` show up correctly.

### Mac is writing the CLUT, but only the first two slots, both ≈ black

ISSP probes for the video card's internal state (`probes_20260518_*.txt`):

| Field | Value | Interpretation |
|---|---|---|
| video_en | 1 | slot driver wrote REG_SOFTRESET |
| mode_raw | 4 | 1bpp mode set |
| vram_base_offset | 8 | base = byte 32 |
| vram_stride | 32 | **128 bytes/line = 1024 px wide** at 1bpp |
| clut[0] | `0x000000` | black |
| clut[1] | `0x010000` | R=1 G=0 B=0 (near-black) |
| arb_vram_wr | 0% | **Mac has not written VRAM through the NuBus card** |

`clut[0]=clut[1]=~black` means all pixels render black regardless
of VRAM contents.  Combined with `arb_vram_wr=0` for the duration
of all our captures, this is consistent with Mac being in an early
"blank the screen" state before drawing the boot image.

### Forced-CLUT reveals VRAM is uninitialized (`captures/v7_force_wb.png`)

With JTAG-forced `clut[0] = white`, `clut[1] = black`, the scanout
shows ~50/50 random pixels — the kind of pattern you get from
unwritten SDRAM.  No happy-mac silhouette, no cursor, no
recognizable structure.  This conclusively shows Mac never drew
anything to VRAM through the NuBus card.

### Stride hint: Mac thinks the display is 1024 pixels wide

`vram_stride=32` (in 32-bit words) means **128 bytes per scanline**.
At 1bpp that's 1024 pixels wide.  Our display is hard-coded to
render 640.  If Mac were drawing a real framebuffer it would be
1024 wide; we'd see the left 640 pixels of it.  For boot screens
(happy mac centered) the visible window is fine, but this is
worth noting for future correctness.

## Fixes landed

### v6: drop all four MAME-style XOR inversions

Removed `~data_in` on:
- `cpu_write_data` (VRAM write)
- `vram_dout`, `cpu_write_merged` (longword VRAM stores)
- `ramdac_addr` (CLUT address pointer)
- `clut[][R/G/B]` (CLUT data writes)
- `data_out` (CPU VRAM read)

These XORs are present in MAME's m2hires model because the real
card has a bus-level inversion the Mac driver doesn't need to know
about.  Our FPGA implementation has no such external inverter, so
the XORs are literal flips that misroute Mac's writes.

### v7: JTAG override for clut[0]/[1] + test patterns

Added:
- `altsource_probe` source instances **CLUE / CLUF** that drive a
  `dbg_clut_override` flag and two 24-bit RGB values.  When the
  flag is high, scanout substitutes the forced RGB for slots 0/1.
- `altsource_probe` source **VTPN** that drives a `dbg_test_pattern[2:0]`
  selector inside the video card with 4 patterns (color bars,
  gradient, checker, solid).

Both are controllable from the host with:
- `scripts/set_test_pattern.tcl <0..4>`
- `scripts/force_clut.tcl on|off|c0=RRGGBB c1=RRGGBB`

The captures linked in this doc were taken using these tools.

## Out of scope (boot problem, being handled separately)

The remaining visual issue — "no happy mac, no cursor, no desktop"
— is **not** a display-pipeline bug.  It's a consequence of Mac
CPU being stuck in the SCSI-timeout loop at `$40826CC6` and never
reaching the framebuffer-drawing code.  Once the Mac CPU boots far
enough to write a proper palette and bitmap, the existing display
pipeline will render it correctly.

## Files

- [rtl/nubus/nubus_video_highres.sv](../rtl/nubus/nubus_video_highres.sv) — v6+v7 video card
- [rtl/debug_probes.sv](../rtl/debug_probes.sv) — ISSP probes + source probes
- [scripts/set_test_pattern.tcl](../scripts/set_test_pattern.tcl)
- [scripts/force_clut.tcl](../scripts/force_clut.tcl)
- [scripts/analyze_capture.py](../scripts/analyze_capture.py)
- [captures/v7_tp1.png](../captures/v7_tp1.png) — color bars (display OK)
- [captures/tp3_checker.png](../captures/tp3_checker.png) — CLUT checker (lookup OK)
- [captures/v7_force_wb.png](../captures/v7_force_wb.png) — VRAM with forced palette
- [captures/v7_unforce.png](../captures/v7_unforce.png) — actual scanout (all black)
