# Session 2026-05-18 — Continued ISSP diagnosis with live screenshots

## TL;DR

Arbiter v3→v4.1 made things meaningfully better.  v5 (forced dskAck
remap off) made things worse and was reverted.  Mac boot on hardware
**now consistently lands in the documented SCSI-timeout loop at
$40826CC6** — the project's pre-existing "no SCSI media" problem, not
an arbiter issue.  Beyond this point requires SCSI/SCC peripheral
work, not arbiter work.

## What the hardware is doing

Live ISSP capture pattern (consistent across many runs after the
arbiter v4.2 build):

| Region | Hits / 200 samples | Identification |
|---|---|---|
| `0x40F10040` / `0x50F10040` | 79 (40%) | A3=0x50F10000 (SCC base), reading offset 0x40 |
| `0x40026CC0-A` (6 PCs) | 71 (36%) | SCSI timeout loop body |
| other | 50 (24%) | scattered IRQ / Time Manager paths |

`A3=0x50F10000` is the SCC channel-A base address (per
`docs/macii_clock_bus_audit.md`).  Per the same doc, MAME with the
matched configuration reaches `$408061F2` (Slot VBL queue walker / idle)
instead — which means on hardware we are timing out a SCSI operation
that MAME never even starts.

`video_en = 1` in 198 / 200 samples — the NuBus card slot driver IS
loading correctly.  arbiter `mac_stall` is firing in 30-50% of samples,
which is the expected pattern when video is contending with Mac for
SDRAM.

## Hardware screenshots taken via mrext API

The MiSTer Remote API ([http://10.3.89.233:8182/api/screenshots]())
gives us live framebuffer captures synchronized with the ISSP probes.

- `captures/screen_v42_first.png` — first v4.2 screen, dense red noise
- `captures/screen_v42_steady.png` — yellow column / gray stripe field
  later in the same boot.  Different CLUT programming, still not the
  Mac desktop pattern.

These match the underlying ISSP signal: Mac CPU spins in the SCSI
timeout loop, occasionally writing something to VRAM through the
NuBus card, but never converging on the proper boot framebuffer.

## Arbiter iteration summary

| Ver | Commit | Change | Mac stuck point | Visual |
|---|---|---|---|---|
| v0 | (orig) | combinational grant, no protection | 0x40826CCx | cyan noise |
| v1 | 42da7cf | + video_clean tracking, registered vram_din | mixed | varies |
| v2 | e8c8d5c | + mac_quiescent gate | 0x40802EDC area (Test Manager) | wavy moving palette |
| v3 | 8b23420 | drop mac_quiescent | further in boot | progress! |
| v4 | 4d69374 | + mac_stall on _cpuDTACK | Test Manager | progress |
| v4.1 | 9635998 | + POST_VIDEO_HOLD=8 cycles | Test Manager (yesterday) | red stripes |
| v5 | (reverted) | force dskAck=0 | back to 0x40826CCx | green noise |
| v4.2 | 4a581f9 | revert v5 → back to v4.1 logic | 0x40826CCx today | red→yellow noise |

The interesting takeaway: **v4.1 yesterday vs v4.2 today both have the
same RTL, but Mac landed at different stuck points** (Test Manager
yesterday, SCSI timeout today).  Boot is non-deterministic on this
hardware due to SDRAM/SCSI/clock timing interactions — sometimes Mac
hits the BERR → Test Manager path, sometimes hangs earlier in SCSI
timeout.

## What works now

1. The MiSTer Remote API integration is live in
   [scripts/auto_capture.sh](../scripts/auto_capture.sh) — every
   JTAG-program + ISSP capture also produces a `captures/screen_*.png`
   snapshot for visual correlation.
2. The arbiter v4.2 is the best we have:
   - Mac priority preserved (mac_active blocks video grant)
   - video_clean tracking prevents Mac garbage from being latched as video
   - registered vram_din (no combinational sdram_dout coupling)
   - mac_stall on `_cpuDTACK` for Mac's RAM/ROM reads when video has SDRAM
   - POST_VIDEO_HOLD=8 cycles extends the stall past the SDRAM tail
3. ISSP probe layout exposes CPU bus, arbiter state, and full PC bits

## What remains — out of arbiter scope

Per existing project docs (`docs/macii_clock_bus_audit.md`,
`docs/new-scc.md`, `docs/mame_verilator_boot_comparison.md`), the
remaining boot issues are:

1. **SCSI timeout** at `$40826CC6` — Mac waits for SCSI to respond.
   MAME's setup uses `-nbe m2hires -scsi:6 ""` (no SCSI device on
   target 6) and never enters this code path.
2. **BERR at `$40806A0E`** reading `$A082D72C` — bad pointer
   dereference in low memory.  Likely a downstream effect of SCSI/SCC
   timing.
3. **VIA1 SR handler / Snow bypass** — already in
   `rtl/dataController_top.sv` from prior work.  Should be working
   but timing on hardware may differ from sim.
4. **SCC** — recent integration per `docs/new-scc.md`; behavior is
   documented but the BNE/BEQ flag-mismatch hasn't been chased
   through.

These all live in `rtl/scc.v`, `rtl/scsi.v`, `rtl/dataController_top.sv`,
or peripheral wiring — not in `rtl/sdram_arbiter.v`.

## Files / artifacts

- [rtl/sdram_arbiter.v](../rtl/sdram_arbiter.v) — current v4.2 arbiter
- [rtl/debug_probes.sv](../rtl/debug_probes.sv) — 5 altsource_probe instances
- [scripts/auto_capture.sh](../scripts/auto_capture.sh) — JTAG program + ISSP + screenshot orchestrator
- [scripts/auto_recompile.sh](../scripts/auto_recompile.sh) — auto rebuild on source change
- [scripts/auto_analyze.sh](../scripts/auto_analyze.sh) — runs analyzer on new captures
- [scripts/analyze_capture.py](../scripts/analyze_capture.py) — probe decoder + heuristic interpretation
- [scripts/status.sh](../scripts/status.sh) — pipeline overview
- [captures/](../captures/) — saved probe data + screenshots

## Suggested next moves

1. **Test with no SCSI media configured** (mimic MAME's `-scsi:6 ""`).
   If Mac progresses past SCSI timeout without media, the SCSI module
   needs a "no media" pathway that the ROM handles cleanly.
2. **Add probes for SCSI registers** (CSR, status bits) so we can see
   what SCC at `$50F10040` is returning.  A 30-min recompile gets us
   that visibility.
3. **Compare SCC behavior MAME vs hardware** with the same boot
   timing.  The `tools/snow_trace/` rust tool may be useful.
4. **Consider whether arbiter v4.1's POST_VIDEO_HOLD is interacting
   with bus timing** in a way that affects Mac's SCSI probe.  Could
   try POST_VIDEO_HOLD=0 (v4 without the tail) to see if Mac progress
   improves.
