# Feature round: MIDI over SCC + BlueSCSI Toolbox + data-only CD-ROM

Resume prompt, written 2026-08-16. Branch `optimize-core`, HEAD `8900916`.

**Scope: exactly three features.** MIDI over SCC, the BlueSCSI file Toolbox,
and an **ISO/TOAST data-only** CD-ROM. Explicit non-goals for this round:

- **No CD audio (CD-DA).** Measured at ~+4,500 ALMs on top of what we
  already spend — it does not fit (see §2). The `cd_audio.sv` RTL is in the
  tree but must stay compiled out (`CD_AUDIO=0`).
- **No Ethernet.** The owner will issue a separate prompt for NuBus
  Ethernet. (For reference: MacLC's `pds_enet.sv` is only 441 ALMs / 0 M10K,
  but theirs is a PDS card and ours would be NuBus — different problem.)

---

## 1. Why this round is mostly plumbing

The 2026-08-08 SCSI transplant (`3d38e3b`) already brought MacLC's `scsi.v`,
`ncr5380.sv`, `scsi_vendor.vh`, `cd_audio.sv` and `cd_vol_lut.vh` into the
tree, and the CD target is **already instantiated and already answering**
(it is the ID-3 no-disc answerer, `CDROM_PRESENT=1`, `CDROM_AUDIO=0`,
`cd_enable=1'b1`). Likewise **Toolbox is already enabled in RTL** —
`rtl/ncr5380.sv:867` instantiates target 0 with `TOOLBOX_ENABLE(i == 0)`.

What is missing in both cases is the **HPS side**: `LBMacTwo.sv` still has
`localparam VDNUM = 3` (slots 0,1 = disks, 2 = PRAM), and
`rtl/dataController_top.sv` ties `tb_mounted`, `cdtb_mounted`,
`cd_img_mounted` to `1'b0` with the outputs left open. So most of this round
is wiring hps_io slots and CONF_STR entries, not writing datapath.

---

## 2. Budget (all measured, not estimated)

Current fit (`8900916` is untested — the last built fit was `1b1f1768`,
which still carried the ~200-ALM debug deck that `8900916` turns off):

| | used | free |
| --- | --- | --- |
| ALM | 38,207 / 41,910 (91%) | **~3,900** after the deck drops |
| M10K | 426 / 553 (77%) | **127** |
| DSP | 57 / 112 | 55 |

Costs, from MacLC's own fit report (2026-08-15, 29,563 ALM / 71%):

| item | ALM | M10K | DSP |
| --- | --- | --- | --- |
| MIDI over SCC | **~+36** (their scc 665.7 vs our 629.8) | 0 | +2 |
| Toolbox (TB_ADDRW=12) | **+590** | +8 | 0 |
| Data-only CD — *see §5* | **+300…600 (est, NOT measured)** | 0…+2 | 0 |
| *(CD audio — out of scope)* | *+4,500* | *+9* | *+8* |

Round total ≈ **+1,000–1,250 ALMs → ~94%**. Comfortable, but re-check the
fit after each item rather than at the end; at 94% the seed lottery bites.

Reserves if it lands tight, in order of preference: force the CD TOC planes
to M10K instead of MLAB (MacLC measured −1,228 ALM for +12 blocks — we are
memory-rich, so this is our best trade), the `lpm_divide`→double-dabble
rewrite in `scsi_bin2bcd` (~320 ALM of pure waste), then the framework
macros `MISTER_DISABLE_YC` (+225) / `MISTER_DISABLE_ALSA` (+262) — those
two cost real features (S-Video/composite, ALSA streaming), so ask first.

**The FPU is untouchable** (19,231 ALMs, 46% of the device; owner veto — the
Mac II will not boot without it). That single block is why MacLC sits at 71%
and we sit at 91%; do not re-derive this.

---

## 3. Work item — MIDI over SCC

MacLC ships it; our `rtl/scc.v` diverged (712 diff lines, 0 hits for
"midi"), so this is a **port with judgement**, not a cherry-pick — their
SCC also carries non-MIDI fixes from the same window.

Pieces on their side to study:
- `../MacLC_MiSTer/rtl/scc.v` — the TRxC/MIDI clause in the baud pipeline
  (~:728), the RR0 bit-0/2 forcing (~:985), and an RR2B interrupt fix
  (~:1063) that they added after a **hardware freeze** with cozyMIDI /
  Serial Driver open (2026-08-12). Read those comments before porting; the
  freeze is exactly the class we do not want to import.
- `../MacLC_MiSTer/verilator/tb_scc_midi.v` — their loopback bench. Bring
  it over; it is the cheap gate for this item.
- `../MacLC_MiSTer/MacLC.sv` — `"MACLC;UART57600:115200,MIDI;"` in CONF_STR,
  the `uart_mode` wire from hps_io (3 = MIDI), and the user-port MIDI-in
  merge at their `serialIn` assign. Their `USER_OUT` also drives an mt32pi
  instance (user-port MIDI + I²C) — decide whether that belongs here.

Our SCC is shared with MacLCii per a guard commit (`a388202`) — check
whether that constraint still applies before diverging.

---

## 4. Work item — BlueSCSI file Toolbox

RTL is already enabled on target 0. Remaining:

1. `LBMacTwo.sv`: `VDNUM` 3 → 4, add `localparam VD_TOOLBOX = 3`.
2. Wire hps_io slot 3 to the `tb_*` ports of `ncr5380` (currently tied off
   in `rtl/dataController_top.sv` — search `tb_mounted`).
3. **No CONF_STR entry.** The family convention is that the Toolbox slot is
   hidden and mounted by the Main fork; a stock Main simply never sets
   `tb_mounted`, `tb_ready` stays 0, and every Toolbox opcode degrades to
   plain-disk behaviour. Preserve that graceful degradation.
4. Confirm `TB_ADDRW` on target 0 is 12 (8 KB buffer) — that is what allows
   advertising `CAP_LARGE_SEND` (`TB_SEND_CAP` gates on `>= 12`).

**Dependency:** needs the owner's Main fork (`add-bluescsi-toolbox-for-MacLC`
lineage, `dda65f18+` for caps `0x82`). Verify which Main is on `.143` before
concluding a Toolbox test failed.

---

## 5. Work item — ISO/TOAST data-only CD-ROM  ⚠ the one real design task

Everything for **data** reads already exists under `CDROM=1`: 2048-byte
logical blocks served as 4×512-byte HPS blocks (`lba`/`tlen << 2`), READ(10),
READ CAPACITY, the mode pages, AppleCD INQUIRY and no-disc sense. Wiring is
the same shape as Toolbox: `VD_CDROM = 4`, `VDNUM` → 5, connect
`cd_img_mounted` / `cd_io_lba` / `cd_io_rd` / `cd_io_wr` / `cd_io_ack` /
`cd_sd_buff_din`, and add the OSD entry
`"SC4,ISOTO*CUEBINCHD,Mount CD-ROM;"` (trim the extension list to ISO/TOAST
for this round) plus MacLC's `"OI,CD-ROM Drive,Enabled,Disabled;"` runtime
gate on `cd_enable`.

**The open question — resolve this first, it decides the cost.** `READ TOC`
is decoded whenever `CDROM != 0` (`rtl/scsi.v:2261`, `cmd_cd_toc43`), but
its *payload* comes from the `cd_audio` engine:

```verilog
wire [7:0] cd_toc_dout = ca_toc_ready ? ca_toc_q0 : 8'h00;   // scsi.v:855
```

With `CD_AUDIO=0` the `g_no_cd_audio` arm ties `ca_toc_ready = 0`, so **a
mounted ISO would answer READ TOC with all zeros.** The existing comment in
`scsi.v` (~:122) claims the TOC paths are unreachable — that is true only
for the *no-disc* answerer we ship today, and stops being true the moment a
disc is actually mounted. So:

- Determine empirically what the Apple CD-ROM driver / Foreign File Access
  actually requires to mount a data ISO — does it need a valid TOC (track 1
  start LBA + lead-out), or does READ CAPACITY suffice? MAME's
  `nscsi_cdrom_apple_device` is the byte-for-byte oracle the family uses.
- If a TOC is required, the cheap answer is a **synthetic single-track
  TOC** (track 1, data, start LBA 0, lead-out = capacity) generated
  combinationally — tens of ALMs — *not* enabling `cd_audio`, whose TOC
  planes exist to describe multi-track audio discs and whose blob is
  supplied by the HPS (`cd_audio.sv` `blob_ram`, the MCDA blob). Check
  whether the Main fork even provides a blob for a plain ISO.
- Keep it behind the existing `CD_AUDIO` seam so the family sync stays
  one-hunk; if you add a synthetic TOC, put it in the `g_no_cd_audio` arm.

Also: `CD_RING_LOG` is currently 3 in `ncr5380.sv` (8 sectors / 4 KB = two
2048-byte CD blocks). MacLC uses 3 too; leave it unless reads stall.

---

## 6. Laws and gates (non-negotiable, learned the hard way)

- **Marginality anchor** (`LBMacTwo.sv`, search `marginality anchor`): the
  9 `(* preserve, noprune *)` words are load-bearing, not debug. Never
  remove, ifdef, or fold them. **If you make any `dbg_*` net live, anchor it
  in the same commit** — violating this on 2026-08-08 produced a
  black-screen wedge with STA fully met.
- **Family sync:** `scsi.v`, `cd_audio.sv`, `cd_vol_lut.vh`,
  `scsi_vendor.vh` are kept byte-identical to MacLC where possible. Our only
  sanctioned divergences are the documented seams (`o_drq_lvl`,
  `CDROM_PRESENT`, `CDROM_AUDIO`/`CD_AUDIO`). Add new seams the same way:
  parameterised, defaulting to MacLC behaviour, with a comment saying why.
- **Guard bench:** `verilator/tb_scsi_pf.v` must stay 79/79 after any
  `scsi_dpram` edit.
- **Verilator harness drift:** every SCSI netlist change renames Verilator's
  internal aliases; expect to fix `verilator/sim_main.cpp` pokes (happened
  three times: `scsiDREQ`→`dreq_r`, `target[0].ack`/`din` folded away).
- **Hardware gate per fit:** boot-rate loop (≥75 s settle between
  `load_core`; screenshot byte-size classifies outcome — 5031 featureless,
  ~6676 `?` disk, ~7900 Welcome, ~8200+ desktop) plus Finder colour-icon
  integrity. STA alone is not sufficient on this core.
- **Seed re-rolls per netlist change.** Sweep if any domain goes negative.
- Build with `bash scripts/build.sh` (courtesy wait is bounded now). The
  Quartus host is **shared** with sibling agent sessions — check whose
  compile is running before killing anything.

---

## 7. Starting state

- Branch `optimize-core`, HEAD `8900916` (debug deck OFF, not yet built).
- Last built + hardware-validated: `releases/LBMacTwo_Unstable_20260814.rbf`
  (md5 `1b1f1768`, ALM 91% / M10K 77%, all timing positive), deployed on
  `.143` as `_Unstable/LBMacTwo_pffix.rbf`. That build carries the FPCS/PRST
  probe deck; `8900916` removes it.
- **Known-open, unrelated:** a residual ~1/11 featureless-screen boot hang,
  documented in `docs/residual_boot_hang.md`. It predates all of this and is
  not a blocker for these features — but if you see it during testing, do
  not mistake it for a regression from your work.
- Recently fixed and hardware-validated: the `scsi_dpram` prefetch
  invalidate bug (`9b78a0b`, 6/11 → 0/11 corruption). Any *data corruption*
  you see now is new and yours.
- Read `CLAUDE.md` first; `AGENTS.md` for repo conventions.

## 8. Suggested order

MIDI first (smallest, self-contained, has its own bench), then Toolbox
(pure plumbing, and it proves the hps-slot pattern), then the CD — resolve
the §5 TOC question before writing any RTL for it. Build and fit-check
between items so a surprise is attributable.
