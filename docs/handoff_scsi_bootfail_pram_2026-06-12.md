# Handoff: "SCSI corruption" (really a boot failure) + PRAM verification

**Date:** 2026-06-12 · **Branch:** `7-1-2-boot-working`
**Predecessor doc:** `docs/handoff_pram_video_scsi_2026-06-11.md` (feature batch,
LAB overflow fix, 3s PRAM gate). This doc covers the two issues left open at
the end of the 2026-06-12 session, for a fresh session to pick up.

## Build/deploy state

| RBF md5 | Commit | Notes |
|---|---|---|
| `8262e433` | 26ae82e | first good fit; 60s PRAM-gate black screen on imageless start |
| `def2129f` | d506940 | 3s gate + reboot-on-late-load; **deployed + field-tested 2026-06-12** |
| (build 3) | 2ed32a1 | "Mount PRAM (reboots)" label + slot-2 size guard; launched end of session — check `output_files/auto_compile_*.log`, deploy `output_files/LBMacTwo.rbf` to `/media/fat/_Unstable/` |

All commits local-only (never `git push`). Fit headroom after the M10K fix:
LABs 4125/4191, ALMs 85%, RAM 491/553.

---

## Issue A: "SCSI disks corrupted at shutdown" — **disproven; it's a boot failure**

User report: System 7.1 disk (`MacLC_7-1.hda`) "stops booting" after a
shutdown cycle; restoring the disk image "fixes" it. Impeded all testing.

### Hard evidence (2026-06-12 ~09:45, scripts + data in `scratch/scsi_corruption_20260612/`)

Four-way md5 over the user's own snapshots — **all identical**, `5ef0deb2…`:
pristine zip (`MacLC_7-1.hda.zip`, made 08:22) == loose `MacLC_7-1.hda`
== `MacLC_7-1_at_shutdown.hda` == `MacLC_7-1_after_corruption.hda`.
`analyze.py` (three-way sector diff + partition/HFS mapping + wrong-LBA /
even-byte-dup / PRAM-clobber signature checks): **0 sectors differ** in any
pair. Partition map and MDB pristine (HFS at sector 96, MDB sig `BD`).

Decisive mtimes (`/media/fat/games/LBMacTwo/`):
- `MacLC_7-1.hda` mtime **Jun 11 19:18** — *never written during the whole
  2026-06-12 "corruption" session.* A System 7 volume that actually mounts
  ALWAYS takes MDB writes (dirty/clean bit) — zero writes ⇒ **the Mac never
  attached that volume during the failing boots**.
- `MacLC_6-0-8.hda` mtime **Jun 12 09:37:56** — this disk (the SC0 mount
  MiSTer had saved since 08:35, see `config/LBMacTwo.s0`) WAS written today;
  the write path works.
- Restore "fixing" it is an illusion: the restored bytes were identical; the
  **remount + core reload** that accompanies a restore is what fixed it.

### Correlated timeline of the failing window

- 09:30 — `config/LBMacTwo.s2` created: the PRAM mount succeeded.
- ~09:30 — **reboot-on-late-load fired** (by design in `d506940`): the Mac
  restarted on its own right after the PRAM image loaded.
- 09:32:59 — OSD opened → PRAM flush wrote `pram.NVR` (save path works).
- 09:37–09:38 — user snapshotted the 7-1 disk states (identical, see above).

### Working hypothesis for the next session

The "stopped booting" is a **device-visibility / boot-flow failure**, likely
one (or an interaction) of:
1. **Mount confusion**: MiSTer auto-remounts the SAVED images at core load
   (`.s0` = `MacLC_6-0-8.hda` since 08:35). If the user believed 7-1 was on
   SC0, the machine was actually booting/running 6-0-8. Check which disk the
   user *intends* vs what `config/LBMacTwo.s0/.s1` actually say at repro time.
2. **PRAM-load reboot mid-boot**: the late-load reboot restarting the Mac
   during driver load / early boot. Harmless in theory (full system reset),
   unverified in practice.
3. Zero-PRAM load effects: first mount loaded an all-zeros NVR (the blank I
   created), wiping the `NuMc` validity signature → ROM reinitializes PRAM →
   boot-device entry reset. Should fall back to SCSI scan; verify.

### Next-session plan

1. Pin the repro: have the user state exactly which images are mounted
   (read `config/LBMacTwo.s0/.s1/.s2` + `/tmp/CORENAME` over SSH at that
   moment) and reproduce the failed boot **with SC2 unmounted** (no PRAM
   image). If 7-1 then boots repeatedly → PRAM interaction confirmed; bisect
   (a) mount-without-reboot vs (b) reboot timing.
2. If it still fails with no PRAM mounted: screenshot the failure
   (`POST http://192.168.99.143:8182/api/screenshots` ~30 s after boot —
   blinking-?, sad Mac, or hang tells which stage), and md5-watch the disk
   file live from SSH during the cycle.
3. Mind the residual hazards: `iotest.mgl`/`iotest_prev.mgl` still mount a
   disk at `type="s" index="2"` (= PRAM slot). Build 3's size guard makes
   that harmless core-side (oversized slot-2 images ignored), but the mgls
   should be fixed/renamed anyway.
4. Diff tooling ready to reuse: `scratch/scsi_corruption_20260612/analyze.py`
   (sector diff + HFS mapping + wrong-LBA content-matching). Clean baselines
   of the mounted disks are on the SD in `games/LBMacTwo/_diag/`.

---

## Issue B: PRAM "doesn't seem to be working correctly" — save path PROVEN, rest to verify

### What is now proven on hardware (2026-06-12)

- Mount works (`.s2` exists), the menu entry shows ("Mount PRAM", renamed
  "(reboots)" in build 3).
- **Save path works end-to-end**: `pram.NVR` (was all zeros) now contains the
  rtc defaults (`80 4F 48` @0x01, `NuMc` @0x0C…) **plus Mac-written deltas**
  (0x67–0x80 region differs from the defaults) — i.e. serial-protocol write →
  dirty flag → OSD-open flush → HPS file write all function.
- 3s gate works (no more 60s black screen; user got into the core promptly).
- 8bpp color display confirmed working.

### Still unverified / user-reported "not working"

- **Load-back roundtrip**: does a core reload restore the saved values into
  the Mac? Test: boot, change a *visible* PRAM setting (e.g. mouse tracking
  speed or Monitors 256-color depth; NOT the clock — see below), open OSD
  (flush), reload core, verify the setting survived. Verify file-side with
  `xxd /media/fat/games/LBMacTwo/pram.NVR | head` before/after.
- **The clock is NOT expected to persist via PRAM**: rtc.v re-seeds the
  seconds counter from the MiSTer HPS TIMESTAMP on every core load (real-world
  time wins). If the user judged "PRAM not working" by the Mac's clock, that
  may be this by-design behavior (or a TIMESTAMP bug — check what time the
  Mac shows vs real time).
- Get specifics from the user: WHICH setting failed to persist, and was the
  OSD opened (flush trigger) before reloading?
- Watch the reboot-on-late-load UX during testing: every fresh mount of a
  PRAM image while the Mac runs = one automatic restart (now labeled in OSD).

### Mechanism summary (for whoever picks this up cold)

256-byte XPRAM lives in the 343-0042 clock chip model `rtl/rtc.v` (M10K TDP:
port A = serial engine, port B = host). `LBMacTwo.sv` PRAM FSM (slot 2,
`.NVR`, 512-byte sector at LBA 0): load on mount (≤4KB images only, size
guard from 2ed32a1), autosave on OSD-open when dirty, `RF` = Reset PRAM &
Core (status[15]), `pram_ready` gates n_reset ≤3s, late loads reboot the Mac
(`pram_late_load` → P_RST). Staging = `pram_buf16` 128×16 M10K. Details and
LAB-overflow history: `docs/handoff_pram_video_scsi_2026-06-11.md` §1b/§2.
