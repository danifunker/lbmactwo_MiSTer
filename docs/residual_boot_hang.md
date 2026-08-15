# Residual boot hang — JTAG probe hunt (handoff, 2026-08-14)

**Your job: find the root cause. This document deliberately contains
observations and pointers only — no diagnosis. Several plausible-sounding
theories have already been wrong this month, so form your own.**

The bitstream you need is already built and already carries the probes.

---

## 1. The symptom

On an otherwise healthy boot, the machine occasionally never gets anywhere:
the screen goes to a **uniform, featureless field** — no Happy Mac, no
blinking-`?` disk, no bomb dialog, no menu bar — and stays there
indefinitely. Two flavours have been seen and may or may not be the same
thing: **light grey (~#EEE)** and **black (~#222)**.

Measured rate, 2026-08-14, alternating A/B of 22 boots on `.143` with a
MacLC 7.x image on SCSI-0:

| build | corruption failures | featureless hang |
| --- | --- | --- |
| `id3fix2` (before the prefetch fix) | 6 / 11 | **1 / 11** |
| `pffix` (after the prefetch fix) | 0 / 11 | **1 / 11** |

The hang rate is **unchanged by the prefetch fix** — that fix eliminated a
different failure class (see §5). Roughly 1 boot in 11 in this sample; treat
that as an order of magnitude, not a precise rate.

### Owner's field description (predates this session's instrumentation)

- *"Happy Mac → spontaneous reboot → `?` disk screen."* The reboot is the
  event of interest; the `?` is what the following boot attempt shows.
- *"we are getting into this reset state DURING the boot process after the
  Happy Mac logo, it could be when we are first determining the hardware."*
- *"mostly consistently not booting, but every so often it will boot"* —
  said during the era when the (now-fixed) corruption bug was also active,
  so that severity figure is not a clean measure of this bug alone.
- *"it's even failing with 6.0.8"* — not confined to System 7.x.
- **This has never reproduced in the Verilator sim.** The owner is
  emphatic and it has held for months: *"we have never been able to isolate
  this issue via a sim run, it's always been hardware bound."*

### Age

Predates the 2026-08-08 MacLC SCSI transplant (`3d38e3b`); it survives every
build in this session's lineage. It is **not** a regression from the diet,
the aspect fix, the VRAM trim, or the prefetch fix.

---

## 2. The instrument (already in the shipped bitstream)

`releases/LBMacTwo_Unstable_20260814.rbf` (md5 `1b1f1768`) is built with
`DBG_FPU=1` and contains two ISSP probes. Read **both** with:

```bash
quartus_stp -t scripts/read_deck.tcl
```

(`scripts/read_fpu.tcl` predates the deck and only knows FPCS.)

- **`PRST` — reboot forensics.** `[31:24]` counts `n_reset` assertions since
  FPGA configuration (config + first boot = 1); `[22:16]` latches the cause
  bits at the last assertion; `[6:0]` is the live cause now. Cause bit
  order, MSB→LSB: `{!sys_locked, osd_reset_req, buttons[1], RESET,
  !clear_done, pram_force_reset, !pram_ready}`. The reader decodes these to
  names for you.
- **`FPCS` — live FPU CIR state.** `[15:11]` cir_state, `[10:6]` max state
  seen, `[2]` except-seen, `[1]` restore-frame-seen, `[0]` cir_active,
  `[31:16]` response primitive. Layout source of truth:
  `rtl/mc68881/vhdl/mc68881_top.vhd:46`.

**The probes were never successfully read** — `get_hardware_names` returned
*"The specified hardware is not found"*, i.e. the USB-Blaster cable was not
attached to the workstation. **Confirm JTAG works before anything else**
(`jtagconfig` should enumerate a DE-SoC chain; expect cable `USB-0`, the
5CSE device is @2). Everything below assumes you got that far.

The intended discriminator: catch the machine in the hung state and read
PRST. Whether the reset counter moved across the event tells you whether any
hardware reset fired at all. Draw your own conclusion from what you see;
also read FPCS in the same session, since it is free once you are attached.

---

## 3. Pointers worth checking (unverified leads, not conclusions)

Presented because each is a real property of this core that someone should
rule in or out — not because any of them is known to be the cause.

1. **The sim runs the FPU as a stub.** `verilator/Makefile:24` defaults
   `USE_FPU_STUB=1`, which swaps `mc68881_fpu_lite` for
   `rtl/mc68881/sim_fpu_cir_stub.v` (a CIR no-op responder). The real FPU
   has therefore never executed an instruction in simulation. If you want a
   sim run to have any bearing on FPU-path behaviour, build with
   `make USE_FPU_STUB=0` — expect it to be much slower.
2. **The 68020 `RESET` instruction's peripheral pulse goes nowhere.**
   `_cpuReset_o` is assigned at `LBMacTwo.sv:1100` and has no consumer (the
   comment at `:329` explains why it is deliberately kept out of the CPU
   reset term). On real hardware that instruction resets the VIAs, SCSI and
   floppy controller; here it resets nothing. Whether any state survives a
   warm restart that should not is unexamined.
3. **Boot-time hardware determination.** The owner's instinct points at the
   window after the Happy Mac where the ROM/System probes the machine.
   `scratch/snow_compare/` has a Snow (emulator) IO trace of that window
   captured with the same FDHD ROM — `fdhd_iotrace.jsonl` plus
   `analyze_fdhd_iotrace.py` and a decoded 5380 register script. It is a
   healthy-machine baseline you can diff against; note it was captured for a
   different question and nobody has yet compared it against a hung board.
4. **FPU standing constraints.** The owner's veto is absolute: the FPU is
   never to be disabled or altered behaviourally (the Mac II will not boot
   without it) — A/B only via observability. Its cones also carry SDC
   waivers (`cir_conv_src_reg` multicycle and the kernel waivers); if a
   waiver is wrong, STA would report clean while the path is not. Auditing
   those waivers against the RTL is a legitimate, veto-safe line of work.
5. **Per-fit marginality is a documented hazard here.** `CLAUDE.md` and the
   always-on anchor block in `LBMacTwo.sv` (search `marginality anchor`)
   record that probes-off fits of this lineage have corrupted hardware
   behaviour with STA fully met, and that probe-bearing fits historically
   pass. Consequence for you: **if a diagnostic build stops hanging, that is
   itself data**, not merely a failed repro. Do not remove or fold the
   anchor words; if you make a `dbg_*` net live, anchor it in the same
   commit (violating this produced a black-screen wedge on 2026-08-08).

---

## 4. Method notes (learned the hard way, will save you hours)

- **Boot-rate A/B, not anecdotes.** Single boots are meaningless at a ~1/11
  rate. Loop `load_core` over two builds alternately and score every boot.
- **Allow ≥75 s between `load_core` cycles.** Faster cycling produces
  spurious blinking-`?` results because the HPS has not re-attached the
  mounted image yet — that is a measurement artifact, not a boot failure.
- **Screenshot byte size classifies the outcome for free** (640×480 PNG,
  fetched from `/media/fat/screenshots/LBMacTwo/`): `5031` = featureless
  (this bug), `~6676` = blinking `?`, `~7900` = "Welcome to Macintosh",
  `~8200+` = desktop or a dialog. Verify by eye before trusting a run; the
  same size can cover a clean desktop and an error dialog.
- **Stale artifacts lie.** Check the mtime of any screenshot, log or report
  before believing it. A stale `fit.summary` reads exactly like success, and
  a stale screenshot reads exactly like a pass.
- **The Quartus host is shared** with sibling agent sessions
  (`MacIIvi_MiSTer`, `MacLC_MiSTer`, `MacLC_Pocket`). Before killing any
  `quartus_*` process, establish whose it is — `find /c/Temp/mistercore
  -maxdepth 4 -type f -newermt "<window>"` shows the active project. A live
  compile has a `quartus_sh` orchestrator and a stage process with a large
  working set; defunct entries are `quartus_map` with ~0 MB that `tasklist`
  reports forever and neither `Stop-Process` nor `taskkill` can remove.

---

## 5. What was recently fixed, so you do not re-chase it

`9b78a0b` ported MacLC's `scsi_dpram` prefetch-invalidate fix: a discarded
look-ahead fetch failed to clear `pf_valid`, so a poisoned capture could be
served as valid permanently. That produced **data corruption**, whose
signatures are distinct from this hang: *"application busy or damaged:
Finder"*, *"Memory Manager error"*, *"coprocessor not installed"*, *"Apple
Photo Access could not be installed"*, plain bombs. Hardware-validated 6/11
→ 0/11 on 2026-08-14. Guarded by `verilator/tb_scsi_pf.v` (79/79; run it
after any `scsi_dpram` edit).

That bug entered with the 2026-08-08 transplant and was active during much
of the owner's recent testing, so **treat pre-2026-08-14 hardware
observations as contaminated** — a mix of two failure classes. The clean
data starts with the `pffix` build.

---

## 6. Ground truth / starting state

- Branch `optimize-core`, HEAD `600ea7a`. Working tree clean (untracked
  `verilator/*.hda` test images are deliberate).
- `releases/LBMacTwo_Unstable_20260814.rbf` = md5 `1b1f1768` = what is
  deployed on `.143` as `_Unstable/LBMacTwo_pffix.rbf`, and it carries the
  probes. Older builds are on the board for A/B (`LBMacTwo_id3fix2.rbf`,
  `LBMacTwo_vram300_dbg.rbf`, `LBMacTwo_transplant_s2/s3/s4.rbf`).
- Fit: ALM 38,207 (91%), M10K 426 (77%), all six timing domains positive,
  SEED 5. Rebuilding re-rolls the seed — sweep if a domain goes negative,
  and re-gate on hardware per the marginality law.
- Hardware: `.143`, shared. `scripts/local.env` has the host and key.
  Screenshots via `POST :8182/api/screenshots` or `echo screenshot >
  /dev/MiSTer_cmd`. Core loading via `echo load_core <path> >
  /dev/MiSTer_cmd` is fine; **`.mgl` launches are banned** (owner rule).
- Read `CLAUDE.md` and `docs/MISTER_HARDWARE_DEBUGGING.md` first.

---

## 7. Suggested first moves (in this order, adjust freely)

1. Get JTAG enumerating; read the deck on a *healthy* booted machine first,
   so you know what normal looks like before you interpret a hang.
2. Reproduce the hang with a boot-rate loop on the shipped build, leaving
   the board **in the hung state** rather than reloading.
3. Read `PRST` + `FPCS` while it is hung. Record the raw words, not just the
   decode.
4. Only then form a hypothesis — and say plainly which observation supports
   it and which alternative it rules out. If the probes are silent or the
   hang stops happening on a probe-bearing build, that is a result worth
   reporting, not a failure.
