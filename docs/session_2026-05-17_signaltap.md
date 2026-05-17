# Session 2026-05-17 — JTAG ISSP diagnosis of hardware Mac boot

## TL;DR

Set up JTAG-readable ISSP probes on the FPGA, captured live Mac CPU
state on real hardware, and confirmed:

1. **`video_en` IS being set** by the slot driver — the Hi-Res card
   is enabled correctly on hardware (we just couldn't see it before
   because the display path was downstream-broken).

2. **Arbiter v3 unblocks the early stuck point.** With the
   `mac_quiescent` gate removed, Mac CPU progressed from 8 fixed PCs
   in the `0x40826CCx` area (visible only as low-24 bits 0x026CCx in
   our first probes) to **43 distinct PCs across the documented Test
   Manager loop region 0x40802EDC-0x408032FA**.

3. **Hardware is now at the same place sim was at 2026-04-09**, per
   the project's [`docs/new-scc.md`](new-scc.md): Mac caught a BERR
   at PC=$40806A0E reading `$A082D72C` (bad pointer dereference) →
   exception handler → Test Manager poll loop forever.

4. **The bad pointer is almost certainly garbage Mac latched from
   `sdram_dout` while video had the SDRAM committed** at the previous
   T0 -- the unprotected `mac_dout = sdram_dout` race I identified
   weeks ago.  Tried latching `mac_dout` (broke Mac with stale data).
   Now trying the proper fix: **stall `_cpuDTACK` so Mac waits for
   the SDRAM cycle that actually belongs to its request**.

## Hardware Setup

- DE-SoC (DE10-Nano) with `LBMacTwo.rbf` programmed via JTAG.
- Quartus 17.0.2 Lite + USB Blaster.
- User opened SignalTap in the GUI, which seeded `stp1.stp` (empty,
  just an SLD instance reference) into the project — this turned on
  the `auto_signaltap_0` instance in the bitstream but with no
  signals tapped.

Tried to add SignalTap signals via CLI; the `.stp` XML format isn't
documented well enough to hand-craft reliably.  Pivoted to ISSP
(In-System Sources & Probes) via `altsource_probe`, which is a normal
Verilog megafunction with clean TCL access.

## ISSP Probes

Added [rtl/debug_probes.sv](../rtl/debug_probes.sv) instantiating
five 32-bit `altsource_probe` instances:

| Probe | Name | Contents |
|---|---|---|
| 0 | CP0_ | cpuAddr[23:0], _cpuAS, cpuRW, _cpuUDS, _cpuLDS, _cpuDTACK, video_en |
| 1 | DATA | memoryDataOut[15:0], arb_mac_dout[15:0] |
| 2 | MAC_ | arb_mac_addr[23:0], arb_mac_we, arb_mac_oe, grant_video, video_clean, mac_stall |
| 3 | VID_ | arb_vram_addr[23:0], arb_vram_rd, arb_vram_wr, arb_vram_ready, vram_state[2:0] |
| 4 | SDRA | sdram_out[15:0], mac_idle_cnt[3:0], cpuAddr[31:24] |

Read via [scripts/issp_read.tcl](../scripts/issp_read.tcl).  The
critical session-management dance discovered: `get_info` MUST be
called BEFORE `start`; `read_probe_data` does NOT take `-device_name`
or `-hardware_name`.

## Capture Results

| Capture | Distinct PCs | Notes |
|---|---|---|
| `probes_20260517_190544.txt` | 8 in `0x026CCx` | Arbiter v2 (mac_quiescent), Mac stuck early |
| `probes_20260517_194344.txt` | 40 in `0x40003xxx` | Arbiter v3 (no quiescence), Mac in SCC poll |
| `probes_20260517_194551_long.txt` | 43 in `0x40003xxx` | 100s capture, confirms steady-state at SCC poll |

In every capture, `video_en=1` and `mac_active`+`arb_mac_oe` show
Mac CPU actively running.  Arbiter `vram_ready` rate is 1-2%, but
that's mostly a sampling-rate artifact (READY state is held for ~1
clk_sys before the video card drops vram_rd).

## Arbiter Iteration Log

| Version | Commit | Change | Result on screen |
|---|---|---|---|
| v0 | (before) | combinational grant, `vram_din=sdram_dout` | cyan/black noise |
| v1 | 42da7cf | + video_clean tracking, registered vram_din | (regressed to noise) |
| v2 | e8c8d5c | + mac_quiescent (≥3 idle cycles) gate | wavy moving palette |
| v3 | 8b23420 | DROP mac_quiescent gate | (above + Mac unblocks!) |
| v4 | this commit | + mac_stall gating _cpuDTACK | pending |

v3 was the breakthrough: removing the quiescence requirement let
video transactions attempt more often, AND apparently let Mac's bus
cycles resolve correctly enough to advance past the early POST loop.

v4 (current) closes the remaining hole: even with Mac priority, the
short window where Mac asserts mid-video-transaction could let Mac
latch the in-flight video word.  Now Mac DTACK is held high during
that window, forcing Mac to wait for its own SDRAM data.

## What to Try If v4 Doesn't Fix Boot

If the next capture still shows Mac stuck in the 0x40802EDC area:

1. **Confirm `mac_stall` is actually firing** — probe 2 bit 3 must
   show non-zero in captures during Mac+video overlap.
2. **Look for OTHER sources of bad data to Mac CPU**:
   - cpuDataIn (the data the CPU latches) isn't probed; add it.
   - Disk DMA path overlap with VRAM region (arb_mac_addr=0x300000+
     when dskAck=1 maps to memoryAddr=0x200000+, which is also where
     VRAM lives at SDRAM offset 0x300000+).  Floppy reads could
     corrupt VRAM, but unlikely the cause of the early BERR.
3. **Add a counter** for vram_ready pulses so we know actual video
   read success rate (not just JTAG-sample rate).
4. **Dig into Mac CPU at PC=$40806A0E** — disassemble the bad
   pointer load.  Could narrow which prior store corrupted what.

## Files

- [rtl/debug_probes.sv](../rtl/debug_probes.sv) — ISSP wrapper
- [rtl/sdram_arbiter.v](../rtl/sdram_arbiter.v) — main arbiter (v4)
- [scripts/issp_read.tcl](../scripts/issp_read.tcl) — JTAG capture
- [scripts/analyze_capture.py](../scripts/analyze_capture.py) — decode
- [scripts/auto_recompile.sh](../scripts/auto_recompile.sh) — re-build
- [scripts/auto_capture.sh](../scripts/auto_capture.sh) — auto-program + capture
- [scripts/auto_analyze.sh](../scripts/auto_analyze.sh) — auto-analyze captures
- [scripts/status.sh](../scripts/status.sh) — pipeline status
- [captures/](../captures/) — saved probe data + analysis logs
