# Handoff — INIT-parade wedge (post-SCSI-fix), 2026-06-11

*Branch `fpu-bus-adapter-dani` @ `218606b`, RBF `e24964bf` deployed on the
MiSTer (`/media/fat/_Unstable/LBMacTwo.rbf`). This is the NEW top boot
blocker, discovered the moment the SCSI Welcome wedge was resolved
(`docs/handoff_scsi_corruption_2026-06-10.md`, round 6 `2d025c5`). It is
NOT a SCSI bug — the SCSI bus is provably idle and byte-clean at the
wedge.*

## Symptom

Booting `HD20SC_scsifix_test.vhd` (the System-Picker disk, System 6.0.8
blessed) now gets past "Welcome to Macintosh" into the **INIT parade**:
mouse cursor appears, the **first INIT icon** draws in the bottom-left
corner — then the boot parks forever. Screenshots:
`scratch/validate_r6.png` / `validate_r6b.png` (identical 75 s apart).

**Important context: this disk lineage has NEVER booted past Welcome on
this core before** (the SCSI wedge always killed it first), so the
entire INIT chain is unexplored territory. The minimal bench `.hda`
boots System 6 to Finder fine — its System Folder has no third-party
INITs. So the wedge is specific to something this disk's INIT chain
does (or to any code path the bench System never exercises).

## Hard evidence captured (probe deck of RBF `e24964bf`)

- **The spin** (live PIFD pairs): PC alternates `0xA44C4` / `0xA44C8`,
  opcodes `4A2A` and `66FA`:

  ```
  A44C4: tst.b  $xxxx(a2)    ; 4A2A — displacement word NOT yet captured
  A44C8: bne.b  $A44C4       ; 66FA — spin while the byte is NON-ZERO
  ```

  i.e. waiting for a RAM byte to go ZERO. `(a2)` and the displacement
  are unknown — capturing the word at `0xA44C6` is the first task (see
  "next steps").
- **SCSI is idle and healthy**: target phase IDLE, `eodma=1, pmatch=0,
  dma_en=0`; I/O completions ($3B4 writes) parked at **471** after
  climbing steadily through the boot (367→383→471). The post-session
  byte-diff of the disk shows exactly one legitimate sector changed
  (MDB clean-bit) — no I/O is pending or lost.
- **IWM/floppy register churn**: `PER-IO` `iwm(wrap8)` climbs steadily
  during the spin (e.g. 117→128 between samples) while `asc` is static
  — something (the spin loop's interrupt context, a VBL task, or the
  loop owner itself between flag polls) is hammering IWM registers.
  There is **no floppy mounted**.
- **Resource Manager activity stopped**: `$A60` write count froze at
  1519 once the spin began (was climbing during INIT load). Last value
  noErr. So the wedge is mid-INIT-execution, not mid-resource-load.
- **Interrupts are alive**: VIA1 (Ticks/60Hz) and VIA2 access counters
  keep cycling; cursor remains responsive-looking (drawn, not frozen
  pixels). The CPU is NOT hung — `AS_cycles` advances normally.
- Earlier PADR samples while the system was still progressing caught
  transient PCs `0x000134A4` and data touches at `0x003FE8AA` (probably
  stack/globals — top of 4 MB RAM).

## Suspects, ranked

1. **A hardware-prober INIT (TattleTech is known to be on this disk).**
   These INITs probe FPU/MMU/IWM/SCC aggressively. Two known-weak
   subsystems they would poke:
   - **FPU**: 257 deterministic corpus failures outstanding
     (`docs/handoff_fpu_timing_closure_2026-06-10.md` — FDIV/FSQRT
     vec-11 misdecodes, FDBcc, FBcc vec-4, FMOVEM.X). An INIT that
     executes one of the broken ops could leave a completion flag unset
     or spin on an FPU-side condition. The bomb-history of this class
     is in memory `project_bug6_*`.
   - **IWM/floppy**: the live IWM churn fits an INIT (or the .Sony
     driver on its behalf) polling drive status on the empty internal
     drive. Prior floppy work proved the data path byte-correct but
     **24× slower than Snow** (memory `project_bug6_floppy_pivot`) —
     a status-poll protocol gap (e.g. a register the driver expects to
     change that never does: disk-in-place, tach, motor-on ack) would
     look exactly like this. PFLP/PIWM probes exist for this but are
     currently DISABLED in `rtl/dbg_min.sv` (re-enable costs slots).
2. **A VBL-task handshake**: the loop waits for a flag a VBL task
   should clear; if that task needs something our core never delivers
   (a status edge, a timer), the flag stays set. VBL itself IS running
   (cursor drew; VIA1 active).
3. Plain software bug exposed by config (least likely — this System
   boots in Snow; verify, see below).

## Next steps (in order)

1. **Capture the missing displacement word**: run the sampler longer —
   `quartus_stp_tcl -t scripts/sample_loop.tcl 300 > s.txt` then
   `python scripts/loop_disasm.py s.txt`. The word at `0xA44C6`
   appears as the prefetch completes; 300 samples should catch it.
   (PIFD = live `{PC[15:0], opcode}` pair, atomic.)
2. **Anchor the loop in the disk image** (the method that cracked the
   SCSI wedge): search `HD20SC_scsifix_test.vhd` for the byte pattern
   `4A 2A <disp16> 66 FA` (python `re.finditer`). Five System copies
   exist on this Picker disk — any hit gives the surrounding routine;
   disassemble ±0x300 with capstone (`CS_ARCH_M68K`, skipdata,
   RAM-anchor = `0xA44C4 - (hit_offset - pattern_offset)`). The
   surrounding code names the flag owner, who sets it, and who is
   supposed to clear it.
3. **Map the file owning those blocks**: `python scripts/hfs_forensics.py
   <image> <lba>` resolves an LBA to its HFS file — directly names the
   INIT. (LBA = file_offset // 512.)
4. **Identify the INIT visually**: the single icon in
   `scratch/validate_r6b.png` (bottom-left) — compare against the
   System Folder contents from step 3.
5. **Snow cross-check (oracle)**: boot the same image in Snow
   (`C:\Temp\mistercore\snow`, assets `C:\temp\mistercore\MacII.rom`).
   If Snow boots it to Finder, diff behavior at the same routine
   (Snow has full debugger + `SNOW_SCSI_TRACE_*`-style logging; for
   IWM there are equivalent trace env vars — check `snow --help`).
   If Snow ALSO wedges, it's a software/config issue — stop chasing
   RTL.
6. If it's the floppy-status theory: re-enable PFLP/PIWM in
   `rtl/dbg_min.sv` (slots are at 20/20 — retire PSCS and/or PSC6,
   which have served their purpose) and compare IWM register traffic
   against MAME `applefdintf`/Snow's SWIM model for the unmounted-drive
   status protocol.
7. If it's the FPU theory: this merges with the FPU timing-closure
   handoff — don't fork the effort; the corpus work fixes it at the
   root.

## Reproduction (fast, ~2 min)

1. MiSTer is at the main menu with RBF `e24964bf` deployed. The test
   disk currently differs from pristine only by the MDB clean-bit — it
   boots fine as-is. (To restore pristine:
   `scp scratch/HD20SC_scsifix_test.vhd root@192.168.99.143:/media/fat/games/LBMacTwo/`
   while at the menu — md5 `b393de428b25c9680d378a27ee4a48d2`.)
2. Launch: `curl -X POST http://192.168.99.143:8182/api/launch -H
   "Content-Type: application/json" -d
   '{"path":"/media/fat/_Unstable/LBMacTwo.rbf"}'` — the core
   auto-remounts the disk from saved config. **No .mgl files — ever**
   (user rule; bare-RBF launch + saved config or manual OSD only).
3. Wedge is reached ~90–120 s after launch (Welcome → INIT icon →
   parked). Probes: `bash scripts/read_probes.sh` (never during a
   Quartus compile). Screenshot: `POST :8182/api/screenshots`, fetch
   newest from `GET /api/screenshots`.

## Current probe deck (20/20 slots, RBF `e24964bf`)

PADR PSTA PACT (CPU) · PSC3 PSCW PSNC PSC6 PSCS PSWL (SCSI; PSWL[15:14]
= req_deferred/req_bus, [13:8] = IRQ machine) · PVIA (VIA2
irq_out/IER/IFR/PCR/ACR) · PIFD (live {PC,opcode} pair) · PIRB PIRE
PRSR PRSF PFLO PIOH PIFA PIFC (misc). The runaway ring (PRNG/PRWF) and
PDRD are retired. `scripts/cpu_state.tcl` decodes everything;
`scripts/sample_loop.tcl` + `scripts/loop_disasm.py` are the remote
disassembler.

## Do nots

- Don't suspect SCSI — it is validated byte-clean through this exact
  boot (one MDB sector, zero copy-runs). Don't re-open
  `handoff_scsi_corruption_2026-06-10.md` items.
- Don't use the Verilator sim for this (floppy/IWM timing and boot are
  not faithful; memory `feedback_no_sim_for_scsi` applies broadly).
- Don't launch via .mgl; don't read probes during a compile; deploy
  RBFs to `/media/fat/_Unstable/` and launch the bare .rbf via the
  Remote API or let the user use the OSD.
- Don't burn FPGA builds guessing: this investigation starts with
  steps 1–5, which need NO rebuild.
