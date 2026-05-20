# Video "red/yellow screen" root-cause — 2026-05-20

## TL;DR

**The video pipeline is correct.** The wrong screen colors are a *downstream
symptom* of the Mac CPU crashing/behaving non-deterministically very early in
boot, which leaves the hardware CLUT loaded with a partial/garbage palette.
The root cause is SDRAM arbiter contention (`rtl/sdram_arbiter.v`) corrupting
the Mac CPU's SDRAM reads — i.e. the boot instability, not the display logic.

## Hard evidence

### 1. Forcing the CLUT proves the pipeline is correct
Forcing `clut[0]=white, clut[1]=black` over JTAG (`scripts/force_clut.tcl on`)
produces a **clean, stable gray Mac desktop stipple**
(`captures/screen_20260520_144310_forced.png`). Therefore:
- VRAM reads from SDRAM are correct.
- The video scan / addressing / stride / 1bpp lookup are correct.
- The Mac *did* draw a real desktop framebuffer.

### 2. The natural screen is the SAME stipple, wrong palette
With the natural (Mac-written) palette, the screen shows the identical desktop
stipple but tinted: red (`screen_20260520_144009_v8.png`) or yellow
(`screen_20260520_153747_v9_natural.png`) depending on the boot. The framebuffer
content is right; only the palette colors are wrong.

### 3. The RAMDAC write history shows a partial, boot-dependent palette
Added a JTAG-readable RAMDAC write-history ring (`RHIX`/`RHDT` probes,
`scripts/ramdac_hist.tcl`). Captures across boots:

| boot | # RAMDAC writes (wptr) | clut[0] | clut[1] | screen |
|------|------------------------|---------|---------|--------|
| v8   | 10                     | `FFFFFF` white | `FF0000` red | red stipple |
| v9   | 3                      | `FFFF00` yellow | (unwritten) | yellow stipple |

The count and contents differ **every boot** — the Mac never completes a full
256-entry palette load. It writes 3–10 bytes, then stops (crash/stall).
In the v9 case clut[0] is *almost* white: R=FF, G=FF, **B=00** — a single
corrupted byte (data bus carried `0x0000` for the third write).

### 4. Non-determinism ⇒ corrupted CPU execution
Different palette every boot, stalling after a handful of instructions, is the
signature of the CPU fetching corrupted data and executing garbage.

## Why the CPU reads are corrupted (the arbiter)

`rtl/sdram_arbiter.v`:
- `assign mac_dout = sdram_dout;` — Mac sees the raw SDRAM bus combinationally.
- `grant_video = !mac_active & (vram_rd | vram_wr)` gives Mac mux priority, but
  when a **video transaction is already in flight** (`VRAM_WAIT`) and the Mac
  asserts a read, the Mac can latch `sdram_dout` while it still holds the
  *video's* word → corrupted CPU read. This is the `BERR @ PC=$40806A0E`
  scenario the in-file comments describe.
- The `mac_stall` signal exists to delay Mac DTACK until its own data is ready,
  but it is currently **reverted / not wired to DTACK** (stalling the CPU broke
  boot a different way). So nothing protects Mac reads from video contention.

This is consistent with the user's report that the core *used to* boot to a
happy Mac and now does not: the arbiter changes on the `video-arbiter-fixes`
branch traded the old framebuffer-noise race for a Mac-read-coherency race.

## Why sim works but hardware doesn't
Verilator wires the video card to a private `sim_vram` and never exercises the
arbiter, so the Mac/video SDRAM contention simply does not exist in sim. The
same RTL boots cleanly in sim and crashes on hardware.

## Recommended fix (next step)
Make the Mac's SDRAM reads coherent without over-stalling the CPU. Options, in
rough order of safety:
1. Register `mac_dout` and only update it on the cycle the SDRAM controller
   completes a *Mac* read (needs a read-valid/strobe from `sdram.v`), so Mac
   never latches a video word.
2. Re-introduce a *minimal* DTACK hold (a refined `mac_stall`) that only extends
   the Mac cycle by the exact number of clocks needed for a fresh post-video
   SDRAM read — the previous attempt over-held and wedged boot.
3. Gate video transaction *start* so a video read is never in flight when Mac is
   about to need the bus (previously starved video; would need the prefetch/
   cache to absorb it).

All three are arbiter-side and bridge the video & boot domains. The video
display logic itself needs no further changes.

## RESOLUTION (v11 -- commit on video-arbiter-fixes)

Verified the race with JTAG counters (MRDT/MRDW in debug_probes): **~50% of
Mac reads begin while video holds the SDRAM** (vram_state==VRAM_WAIT), so the
combinational `mac_dout = sdram_dout` + immediate "turbo" DTACK handed the CPU
the video word half the time -> corrupted data -> wrong palette + unstable boot.

Fix (v11):
- `sdram_arbiter.v` exports `mac_dout_valid`, derived by counting `clk8_en_p`
  (SDRAM t=0) edges while a Mac read is asserted. Because
  `grant_video = !mac_active`, the Mac wins the next SDRAM slot the instant it
  asserts: the 1st edge latches the Mac command, by the 2nd edge `sdram_dout`
  holds the Mac word. Always releases within ~1-2 SDRAM cycles, so it cannot
  wedge the CPU the way the old blanket `mac_stall` did.
- `LBMacTwo.sv` defers the RAM/ROM **read** DTACK until `mac_dout_valid`.
  Writes and the turbo fast path are unchanged.

Result on hardware:
- CPU stays alive (MRDT keeps incrementing ~2.16M reads/s -- no wedge).
- Behaviour is now (mostly) deterministic; the corruption is gone.
- On a boot that progresses far enough the Mac writes the correct B&W palette
  (clut[0]=FFFFFF white, clut[1]=000000 black) **by itself**, and the NATURAL
  scanout renders a clean, stable gray desktop stipple -- no forced CLUT, no
  red/yellow noise.  See captures/screen_v11_correct_181725.png.

Remaining (boot domain, not video/arbiter):
- Boots still vary in how far they get before parking in the SCSI boot-device
  wait (no bootable disk). Some reach the full white/black palette; others
  hang mid palette-load (clut[0] shows red = only the R byte landed). This is
  boot stability / SCSI, owned by the boot effort -- the coherency fix should
  *help* it since the CPU now executes on uncorrupted data.

## Probe / script reference
- `RHIX` (source, idx) + `RHDT` (probe, 32-bit) — RAMDAC write history.
  Entry = `{addr[4:0], uds_lds[1:0], ramdac_rgb[1:0], data_in[15:0]}`.
- `scripts/ramdac_hist.tcl` — dump + decode the ring.
- `scripts/force_clut.tcl on|off` — JTAG CLUT override (proves pipeline).
- `CLU0`/`CLU1` probes: `CLU0={clut0[23:0],clut1[23:16]}`, `CLU1={clut1[15:0],16'b0}`.
