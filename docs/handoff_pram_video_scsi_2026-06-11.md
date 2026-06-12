# Handoff: PRAM persistence, MDC824 8bpp + 512x384, SCSI inquiry strings

**Date:** 2026-06-11 (updated 2026-06-12) · **Branch:** `7-1-2-boot-working`
**Status:** RTL complete; **built clean 2026-06-12 (RBF md5 `8262e433`,
LABs 4125/4191, ALMs 85%, RAM 491/553) and deployed to
`/media/fat/_Unstable/LBMacTwo.rbf`**. A blank 512-byte
`/media/fat/games/LBMacTwo/pram.NVR` was pre-created for the PRAM mount.
**Boot/feature validation on the DE10-Nano still pending** — this doc is the
test plan + the things to watch. (The first 2026-06-12 build failed to fit by
18 LABs; see the UPDATE in §2 for the root cause and fix, commit `26ae82e`.)

---

## 1. What changed

### 1a. SCSI INQUIRY strings (`rtl/scsi.v`)

* Vendor (bytes 8–15): `" SEAGATE"` → `"MiSTer  "` (8 chars, space-padded).
* Product (bytes 16–31): `"...ST225N+ID"` → `"VIRTUAL DISKx   "` where
  `x = '0' + SCSI ID` (the `ID` module parameter, so SCSI-6 shows
  `VIRTUAL DISK0` / `VIRTUAL DISK1` per target instance numbering in
  `ncr5380.sv` — verify which digit each OSD slot shows on HW and that the
  driver is happy).
* The four parallel copies (`inquiry_dout`, `_next`, `_next2`, `_next3`) were
  collapsed into one `inquiry_byte(cnt)` function — the string now lives in
  exactly one place. Response stays the standard 36-byte INQUIRY
  (additional-length = 31; do NOT change, see the 2026-06-10c wedge comment).

### 1b. PRAM persistence (MacLC-style `.NVR` mount)

The Mac II has **no Egret** (verified: MAME `macii.cpp` uses `RTC3430042`,
Snow `macii/bus.rs` hangs `rtc.rs` off VIA1) — its 256-byte XPRAM lives in the
discrete 343-0042 clock chip, which `rtl/rtc.v` already modeled. Only the
MiSTer-side *persistence plumbing* was ported from MacLC_MiSTer:

* `rtl/rtc.v`: new host-side ports — `pram_load_wr/addr/data` (write port,
  works during system reset), `pram_save_addr/data` (async read),
  `pram_wr_stb` (pulses when the Mac writes a PRAM byte → dirty flag).
  **Also an oracle-conformance fix:** extended (XPRAM) writes are now gated on
  the write-protect register, matching MAME `macrtc.cpp` and Snow `rtc.rs`
  (previously they bypassed WP).
* `rtl/dataController_top.sv`: pure passthrough of the six signals.
* `LBMacTwo.sv`: `"SC2,NVR,Mount PRAM;"` (hps_io slot 2, `VDNUM` 2→3, SCSI
  buses stitched into slots 0–1), the MacLC P_* load/save FSM (512-byte sector
  at LBA 0, PRAM in bytes 0–255), `"RF,Reset PRAM & Core;"` button
  (status[15]), and `!pram_ready` added to the n_reset gate — the machine is
  held in reset until the slot-2 mount status is known (load done / no-image
  report / 60 s backstop), because the ROM reads the clock chip early in boot.
* Semantics: **load** on image mount, **autosave** on OSD-open when dirty,
  **RF** zeroes PRAM + flushes + reboots. No image mounted = current behavior
  (volatile PRAM seeded from the MAME-baseline defaults in rtc.v).
* `verilator/sim.v`: ports tied off (no HPS in sim).

### 1c. MDC824: 8bpp unlocked + 512x384 monitor + 384 KB VRAM

The card (`rtl/nubus/nubus_video_mdc824.sv`) already had the full 1/2/4/8 bpp
pixel pipeline and 256-entry CLUT; 8bpp was deferred **only** because VRAM was
128 KB (640x480@8bpp needs 300 KB). Changes:

* `rtl/nubus/vram_ram.sv`: parameter is now `WORDS` (count of 16-bit words);
  instance grown 65536 → **196608 words = 384 KB**.
* `nubus_video_mdc824.sv`: `VRAM_WORDS` parameter (bound check unchanged:
  beyond-limit writes acked-and-dropped, reads $FFFF — that is what the
  declaration ROM's VRAM size probe sees); new `monitor_512` input selecting
  the advertised monitor sense + scan timing:
  * 0 = Macintosh 14" hi-res, sense **[6,2,4,6]**, 640x480, 896x525 total
    @ 30.24 MHz (unchanged existing mode);
  * 1 = Macintosh 12" RGB, sense **[2,2,0,2]** (Snow `MacMonitor::RGB12`),
    512x384, 640x407 total @ 15.6672 MHz (exactly clk_sys/2; Apple 12" RGB
    scan rates 24.48 kHz / 60.15 Hz).
* `LBMacTwo.sv`: `"OG,Monitor,640x480 13in,512x384 12in;"` (status[16]),
  `localparam VRAM_WORDS = 196608` is the single source of truth for the card
  bound check and the BRAM instance.
* Monitor switch takes effect on the next **Mac reboot** (Slot Manager probes
  sense at boot). Timing/sense switch instantly; the Mac just won't re-layout
  until reboot.

**Why 384 KB and not 512 KB:** 16-bit-wide M10K = 512 words/block. The device
has 553 blocks; the 2026-06-11 fit uses 233 (128 of those = the old 128 KB
VRAM). 512 KB VRAM alone = 512 blocks → 617 total, doesn't fit. 384 KB → 384
blocks → ~489/553 (88%). Moving the 32 KB declaration ROM to SDRAM would only
buy 32 more blocks (still < 512 KB) at the cost of an SDRAM arbitration path —
not done. The main Mac ROM is **already in SDRAM** (word 0x400000+), nothing
to move there. 24bpp (RAMDAC mode 0xD) stays deferred: 640x480 direct colour
is a 1.2 MB framebuffer — that needs the SDRAM framebuffer path back.

---

## 2. Build-time checks (do these on the next Quartus compile)

**2026-06-12 UPDATE — first build FAILED to fit: 4209 LABs needed / 4191 in
the device.** Root cause (from the map report, not the features themselves):
`rtc:pram` never inferred as RAM — 2347 ALUTs + 2145 registers of fabric for
the 256-byte array (reads/writes scattered through the protocol case + the
async save port), and the new `pram_buf[0:255]` byte staging array (async
readback muxes) had the same disease, while 64 M10K blocks sat free. Fixed in
commit `26ae82e`: both arrays restructured into canonical BRAM templates —
rtc `pram[]` is a true-dual-port M10K (port A = serial engine with a 2-clock
read-commit pipeline + 1-clock `ser_we` write pulse; port B = host load
write / save read on one shared address), and the staging buffer is now
`pram_buf16[0:127]` (128x16, single write port + single registered read port,
scsi_dpram's proven 1-cycle hps_io readback latency). `pram_save_data` is now
**registered (valid 2 clocks after the address)** — the save FSM is a 3-state
issue/wait/capture loop per byte. No Mac-visible protocol or .NVR format
change.

1. **RBF md5 changed** vs `af36828` baseline (see
   `project_incremental_compile_drops_changes` memory — confirm the build
   picked the edits up).
2. **fit.rpt: `vram_ram:vram_inst` must show 3,145,728 bits / 384 M10K.**
   (The 2026-06-12 map confirmed exactly 3,145,728 bits, no duplication.)
3. **map/fit.rpt: `rtc:pram` must show 2,048 block memory bits** (one M10K)
   and a few-dozen ALUTs, NOT ~2347 ALUTs / 2145 regs. Likewise the
   `pram_buf16` staging RAM (2,048 bits) at the `emu` level. If either falls
   back to logic again, the LAB overflow returns.
4. **Fitter LABs ≤ 4191.** The M10K conversion frees roughly 300+ LABs of
   register/mux pressure, so there should now be real headroom.
5. Total M10K should land ≈ 490/553; watch routing/timing — if the fit
   degrades the FPU paths further, that interacts with the **paused FPU
   timing-closure work** (`docs/handoff_fpu_timing_closure_2026-06-10.md`).
6. Future LAB headroom if ever needed again: the MDC824 CLUT (256x24,
   ~6K registers + async read mux in `nubus_video_mdc824.sv`) could move to
   M10K the same way, BUT its read is in the per-pixel path — it needs a
   pipeline stage added to the video output (and matched sync/DE delay), so
   it is NOT a mechanical change. Also `dbg_min` probes (~633 ALUTs/1621
   regs) can be trimmed if debugging is done.

## 3. Hardware test plan

Deploy per usual (`scp output_files/LBMacTwo.rbf` → `/media/fat/_Unstable/`,
load from menu — NOT JTAG SOF, NOT .mgl).

* **SCSI strings:** boot 7.1.2 from SCSI; run SCSIProbe (or Apple HD SC
  Setup). Vendor must read `MiSTer`, product `VIRTUAL DISKx`. Boot itself is
  the regression test — the INQUIRY length/shape didn't change, only bytes
  8–31.
* **PRAM, no image (regression):** boot WITHOUT mounting anything on SC2.
  Boot must start promptly (MiSTer reports "no image" for the slot at core
  load; if boot instead stalls ~60 s, that report never came — see the
  backstop in the PRAM FSM, and re-check how this MiSTer build reports
  unmounted S-slots).
* **PRAM, with image:** create a blank image once:
  `ssh -i ~/.ssh/mister_only root@192.168.99.143 "dd if=/dev/zero of=/media/fat/games/MacII/pram.NVR bs=512 count=1"`
  Mount it via OSD → core reboots the Mac (mount = img_mounted pulse → load →
  ready). Set something persistent (Control Panel: clock, mouse tracking,
  Monitors depth = 256 colors). Open the OSD once (triggers the flush). Power
  -cycle / reload the core; the settings and clock must survive. Then test
  "Reset PRAM & Core" → settings revert to defaults.
* **8bpp:** with the image mounted and 384 KB VRAM, Monitors control panel
  should offer **256 Colors at 640x480**. Select it; desktop should render in
  colour (this also exercises the CLUT write path 0x0200/0x0207 for real for
  the first time — watch for wrong/swapped colours = {B,G,R} packing bug, or
  a shifted palette = pal_cnt phase bug).
* **512x384:** OSD Monitor → "512x384 12in", then Mac reboot (OSD Reset).
  Boot should come up 512x384, Monitors offering up to 256 colors. Check the
  MiSTer scaler locks to the 15.6672 MHz / 24.48 kHz / 60.15 Hz mode.
* Screenshots via Remote API (`POST http://192.168.99.143:8182/api/screenshots`)
  at ~30 s post-boot per the OSD-mount-verify rule.

## 4. Known limitations / deferred

* **24bpp** ("Millions"): not implemented (RAMDAC mode 0xD currently renders
  as 8bpp). Needs an SDRAM framebuffer. The declaration ROM may still offer
  "Millions" in Monitors if it keys off the ROM alone — if users pick it
  they'll get garbage; acceptable for now, fix = either SDRAM framebuffer or
  filtering the mode in the card's probe responses (VRAM bound already limits
  what the driver's RAM test finds, which on the real card is what gates
  Millions).
* **CRTC timing registers** (0x0100–0x01FF) are still ignored (except VBL
  enable 0x013C / IRQ clear 0x0148) — output timing is fixed per monitor_512.
  Same simplification Snow uses.
* Pre-existing oddity, untouched: CONF_STR has `"O13,NuBus Video,Color,B&W;"`
  while the code reads `status[13]` — two-char `O13` historically means bits
  1–3 to the OSD parser. Worth auditing someday; not part of this change.
* FPU timing-closure work remains **paused** (user decision 2026-06-11);
  resume via the 2026-06-11 UPDATE section of
  `docs/handoff_fpu_timing_closure_2026-06-10.md`.

## 5. File inventory

| File | Change |
|---|---|
| `rtl/scsi.v` | INQUIRY strings → MiSTer / VIRTUAL DISKx, 4 copies → 1 function |
| `rtl/rtc.v` | host load/save/dirty ports; WP now gates extended writes |
| `rtl/dataController_top.sv` | PRAM port passthrough |
| `LBMacTwo.sv` | SC2 NVR slot, VDNUM=3, PRAM FSM, RF button, reset gate, OG monitor option, VRAM_WORDS=196608 |
| `rtl/nubus/nubus_video_mdc824.sv` | VRAM_WORDS param, monitor_512 sense+timing mux |
| `rtl/nubus/vram_ram.sv` | WORDS param (384 KB) |
| `verilator/sim.v` | tie-offs + matching VRAM size |
