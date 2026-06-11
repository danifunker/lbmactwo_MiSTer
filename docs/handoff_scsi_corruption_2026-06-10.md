# Handoff — SCSI hard-disk corruption (TOP PRIORITY)

*2026-06-10, branch `fpu-bus-adapter-dani` @ `1127811` (RBF `af34c4c4` on the
MiSTer). User report: hard disks still end up corrupted after Mac OS
sessions on the core, even after today's fixes. This outranks the FPU
handoff (`docs/handoff_fpu_timing_closure_2026-06-10.md`).*

---

## 2026-06-11 — RESOLVED: round 6 (`2d025c5`) HW-validated; SCSI hang + corruption CLOSED

PVIA proved VIA2 SCSI IER bits DISABLED (IER=0x02): no ISR exists — the
polled settle loop is the only continuation. Full decode (PIFD pairs +
disk-image byte-anchor): `(a4)` = BSR (`lea $50(a3),a4`); the loop spins
while (CSR.REQ==1 && BSR.pmatch==1) and exits ONLY when a CSR read
returns REQ=0. Snow's `set_req` deferral provides that window; ours
never did. Fix `2d025c5`: defer bus-visible REQ from CSR until one full
CSR read completes (BSR.DRQ undeferred = Snow get_drq). VALIDATION
(RBF `e24964bf`): boot passed Welcome into the INIT parade (first time
ever for this disk lineage; 471 I/O completions vs the eternal 147);
post-session byte-diff vs pristine = ONE sector changed, LBA 98 = HFS
MDB clean-bit mount write (2 bytes). ZERO copy-class runs.

REMAINING (separate, non-SCSI): an INIT spins at RAM ~0xA44C4
(`tst.b d(a2) / bne` on a RAM flag), IWM-register churn, SCSI idle,
first INIT icon drawn. This System-Picker disk never booted past
Welcome before, so its INIT chain (TattleTech-style hardware probers)
is unexplored — suspect floppy-poll or FPU/MMU-probe class (see
docs/handoff_fpu_timing_closure_2026-06-10.md). Use the PIFD remote
disassembler (scripts/sample_loop.tcl + loop_disasm.py, anchor with a
disk-image byte search) on the new loop.

---

## 2026-06-10 session 3 (cont.) — the wedge loop DECODED via JTAG remote disassembly; waiting on PVIA

Rounds 4 (VIA2 level overlays `1ee80e8`) and 5 (bus-visible REQ
continuity `5adc2e1`, audit-driven — see `docs/scsi_audit_2026-06-10.md`)
did NOT clear the Welcome wedge (same `data_cnt=512/tlen=35` freeze).
Round 5's RBF carries the live PIFD {PC,opcode} pair probe; 120 JTAG
samples + `scripts/loop_disasm.py` reconstructed the ACTUAL wait loop
(driver RAM @ 0x1120A):

```
120A: btst.b #5, $40(a3)   ; CSR — test REQ
1210: beq.b  $1218          ; REQ dropped -> exit forward
1212: btst.b #3, (a4)       ; RAM completion-flag byte, bit 3
1216: bne.b  $120A          ; still set -> keep spinning
```

Facts established: (a4) is a DRIVER RAM FLAG (PADR caught RAM data reads
0x003FE656/66E in-loop; across 5 rounds of sampling the loop never read
a VIA2 address), cleared by the driver's SCSI completion ISR. The IF-PC
bursts NEVER show that ISR running (only ROM 60Hz/ADB excursions). So:
completion interrupt never taken -> flag never clears -> loop spins ->
no DACK reads -> transfer never finishes -> no phase change -> no new
IRQ. Deadlock. irq_latch=1 sits unconsumed in PSWL.

Three candidate causes, all inside VIA2 registers we couldn't see:
IER bits 3/0 (CB2=SCSI IRQ, CA2=DRQ) never enabled; PCR edge polarity
mismatch vs our active-low wiring; or delivery broken past irq_out.
**Next RBF (commit `59bc6c6`, building at handoff) adds PVIA:
{irq_out, IER, IFR_eff, PCR, ACR} live.** Read it AT THE WEDGE:
- IER bit3/bit0 = 0 => the polled driver masks VIA2 SCSI ints; the flag
  must be cleared another way — next step: write-snoop (a4)≈0x3FE656
  (PMEM-style probe) to find who's supposed to clear bit 3.
- IER set + irq_out=1 + no ISR => CPU-side delivery broken (IPL cascade
  /TG68 level-2/SR mask) — compare PSTA FC + add IPL visibility.
- IFR bit3=0 while irq_latch=1 => our overlay/edge plumbing bug.

Caveat for interpreting IFR: the level overlays (`1ee80e8`) FORCE IFR
bits 0/3 while DREQ/irq_latch are high — if the driver POLLS IFR and
treats bit3=1 as 'IRQ still pending / not done', the overlay itself
keeps the loop spinning; reading PVIA decides whether to revert the
overlays in favor of pure edges + reg-7-read discipline.

Probe deck: PIFD pair + PVIA (replaced mis-gated PDRD: mac_dout_valid
only covers SDRAM reads — it never saw I/O polls). Tools:
`scripts/sample_loop.tcl N` + `scripts/loop_disasm.py` = remote
disassembler for any stable RAM loop. cpu_state.tcl TCL trap fixed
('PC[15:0]' in a quoted format string is command substitution).

---

## 2026-06-10 session 3 — TWO more stacked wedges found on HW; the big one is the missing VIA2 SCSI IRQ/DRQ wiring (commits `4f9506b`, `b760944`)

HW validation of `4376c8f` un-stacked two FURTHER wedges. Each fix moved
the wedge exactly as predicted; the probes named each next culprit.

### Round 2 (`4f9506b`) — response length-field consistency

With the CD fixed (probes: EMPTY-CD IDLE/req=0 ✓), the boot re-wedged at
Welcome with the **disk target (t0)** in DATA_OUT. Cause: our responses'
own length fields disagreed with the bytes served — INQUIRY claimed 37
bytes (additional-length 32; the standard response is 36/addl=31, which is
what real drives and Snow return) and MODE SENSE's mode-data-length header
byte was 0 while serving raw alloc. Drivers that trust those fields
under-read and the target holds REQ. Fixed: INQUIRY 36, MODE SENSE
clamped to 12 with header 11. Enforced invariant: **a response serves
exactly what its own length fields promise, clamped by alloc**.

### Round 3 (`b760944`) — the HD SC 4.3 driver wedge: 5380 IRQ/DRQ never reached VIA2

Round-2 retest wedged again at Welcome — **new, sharper signature**
(upgraded probes: PSCW now routes DATA_OUT, PSC6 = last opcode):

- t0 parked in DATA_OUT at **data_cnt=512 of a tlen=35 READ(10)** —
  exactly the first HPS 512-byte block boundary (REQ pause while the
  next sector is fetched from SD).
- `dreq=1` re-asserted and **ignored**; zero DACK reads in any PADR
  sample; I/O completions frozen; CPU free-running in a RAM poll loop at
  0x1120A-0x11218 reading CSR/BSR.
- The RAM loop is the **on-disk HD SC 4.3 driver** (Apple_Driver43
  partition, DDM: ddBlock=64 ddSize=19). Extracted blocks 64-82 and
  disassembled with capstone (M68K): the driver's ISR/event machinery
  (+11ca) and its wait loop (+13e0) sleep on **VIA2 IFR flags** between
  pseudo-DMA chunks, re-reading SCSI status only after the flag sets.
- Mac II wiring (ground truth Snow `macii/via2.rs`): **VIA2 CA2 = IFR
  bit 0 = SCSI DRQ; VIA2 CB2 = IFR bit 3 = SCSI IRQ.** Our
  dataController_top had `ca2_i(1'b1)` / `cb2_i(1'b1)` and ncr5380 had
  NO IRQ latch at all (`bsr_irq` combinational, `bsr_eodma` constant 0).
  The driver slept on flags that could never set. Wedge at the first REQ
  pause, forever. **This also explains the disk-dependence**: minimal
  bench .hda images carry no Driver43 partition, so they run the ROM's
  polled driver and never hit this; real Apple-formatted disks load the
  async HD SC driver at boot and wedge at Welcome.
- MAME macii note: its `scsi_irq` handler is EMPTY — MAME instead
  implements the *other* real-HW mechanism (DACK access without DRQ →
  bus error → driver's retry handler). Both are hardware-faithful paths;
  we implemented Snow's (IRQ/DRQ flags), keeping our indefinite DACK
  stall (`c616bf3`).

Fixes in `b760944` (ncr5380.sv + dataController_top.sv):
`dma_armed` on Start-DMA-Send/Initiator-Receive writes; `irq_latch` on
phase-match falling edge while `MR.DMA & armed` (cleared by reg-7 read /
bus reset); `BSR.IRQ` = latch; `BSR.EODMA` = bus-not-in-data-phase
(Snow semantics); `ca2_i = ~scsiDREQ`, `cb2_i = ~scsiIRQ` (VIA2 PCR=0 →
negative-edge inputs, flags latch on assertion).

Probe deck for validation (20/20 slots): PSCS re-enabled (last SCSI reg
read + value, decoded name), PSWL re-enabled carrying the IRQ-machine
live state in [13:8] (irq_latch/armed/eodma/dreq/pmatch/dma_en), PSNC
count now counts BOTH DACK directions, PSCW routes DATA_OUT targets,
PSC6 last-opcode.

### Validation state

Round-3 RBF building at session end. Protocol unchanged (fresh
HD20SC_scsifix_test.vhd from scratch/, boot, Welcome→Finder, clean
shutdown, `hda_match_sources.py` → zero COPY runs). **Launch the bare
.rbf via Remote API** (`POST /api/launch {"path":".../LBMacTwo.rbf"}`) —
the core auto-remounts the test disk from saved config; the user has
forbidden .mgl launches. Re-scp the pristine image after every wedged
attempt (each wedge dirties it).

---

## 2026-06-10 session 2 — ROOT CAUSE FOUND + FIXED (commit `4376c8f`, HW validation pending)

User symptom: most Mac OS disks hang at "Welcome to Macintosh"; once a disk
hangs it never boots again. Caught LIVE on a frozen image (HD20SC-755.vhd, a
multi-System "System Picker" disk booting System 6.0.8) with RBF `af34c4c4`.

### The hang (live-probed, smoking gun)

- CPU not frozen: spinning in a supervisor RAM loop at 0x11AC2-0x11AD0
  polling **0x50F10050 = NCR5380 reg 5 (Bus & Status)**.
- Bus state: `dreq=1 scsi_req=1 dma_en=1 tcr=1(DATA-IN) pmatch=1`, no ACKs —
  the Mac finished its transfer count and waits for the end-of-data phase
  change; a target still holds REQ with leftover bytes. Deadlock.
- PSCW showed `cmd_write=1 tlen=32 phase=IDLE` — **note the ncr5380 PSCW mux
  defaults to t1 (ID5), not t0**; t1 is the OSD-mounted disk, proving the
  disk was IDLE. t0 unmounted. By elimination the REQ holder was
  **`scsi_empty_cd` (fake Sony CD-ROM at ID3, zero probe visibility)**: its
  `data_len` for INQUIRY/REQUEST SENSE was the RAW allocation length, never
  clamped to the actual response size like a real device — when the Mac's
  boot-time SCSI mount scan transfers fewer bytes than alloc, the CD holds
  REQ forever.

### The corruption (byte-level disk forensics)

Pulled the hung image and diffed against its pristine parent
(`scripts/hda_diff.py`, `scripts/hda_match_sources.py`,
`scripts/hfs_forensics.py` — written this session):

- Misdirected whole-sector writes, e.g. **MultiFinder rsrc fork content
  (pristine LBA 1849-1874) written over General + Startup Device rsrc forks
  (LBA 22693-22723)** — exactly covering those files' extents; Finder's
  rsrc fork rewritten with itself shifted +10 sectors (212 sectors);
  System file clobbered (=> unbootable). ~3200 sectors zeroed.
- **Signature: every corrupted run = ONE part-garbage sector followed by
  EXACT sector-aligned copies of an earlier boot-time READ.** That is a
  wedged DATA_IN target being walked by stray shared-bus ACKs: garbage
  trickles into the start of its 2-sector buffer until a 512-byte boundary
  fires the HPS flush, which writes the STALE previous-read content to the
  command's LBA (with `lba++` per flush).
- `dma_wr_count` (all pseudo-DMA write beats since core load) was **256 =
  512 bytes total** — the Mac's own data barely flowed; the megabytes of
  disk damage were HPS flushes of stale read-buffer content.
- Gateway for the chaos: with a target wedged BUSY, its dout stays
  wired-ORed onto the data bus and it consumes every shared ACK. Selection
  has no bus-free check, so dialogs interleave; a target parked in
  STATUS_OUT drives CHECK CONDITION 0x02 which ORs a READ6 opcode 0x08
  into WRITE6 0x0A on the next command's first ACK.

### Fixes (commit `4376c8f`)

1. `scsi.v` + `scsi_empty_cd`: `data_len = min(allocation, actual)` for
   INQUIRY (37 disk / 54 CD) and REQUEST SENSE (18; alloc 0 -> 4); undo the
   0->256 block-count mapping for allocation lengths (it's a READ/WRITE(6)
   convention only).
2. Zero-length data phases complete immediately (`data_done`); `req_wr`
   guarded so a tlen=0 WRITE can't flush a stale buffer block in STATUS_OUT.
3. **Selection requires a free bus** (`sel && din[ID] && !bus_busy`) in both
   target modules — real SCSI cannot select while BSY is asserted; this
   closes the spurious-selection / shared-ACK corruption class.
4. Probes: empty-CD live phase+REQ in `dbg_scsi2[15:14]/[7:6]`, surfaced via
   re-enabled PSC3 (PSWL disabled — its question is answered:
   blind_wr_count==0). `cpu_state.tcl` decodes it and PSCW is relabeled.

### Validation protocol (pending)

1. Fresh pristine copy staged on the MiSTer:
   `/media/fat/games/LBMacTwo/HD20SC_scsifix_test.vhd`
   (md5 `b393de428b25c9680d378a27ee4a48d2`, recorded in
   `scratch/HD20SC_scsifix_test.md5`).
2. Load new RBF from the MiSTer menu (NOT JTAG — boot0.rom must load),
   mount the test disk, boot to Finder, browse, clean shutdown.
3. During boot run `bash scripts/read_probes.sh`: EMPTY-CD(ID3) phase should
   return to IDLE after the mount scan; no BSR-poll wedge.
4. `scp` the image back, `python scripts/hda_match_sources.py <pristine>
   <after>`: expect ONLY NOVEL-class changes in catalog/Desktop/MDB regions
   (legit HFS metadata) — **zero COPY-class runs** (sector-aligned copies of
   other disk regions = misdirected writes).
5. Post-crash artifact preserved at `scratch/HD20SC-755_postcrash.vhd` for
   re-analysis.

### Open follow-ups

- The corrupted HD20SC-755.vhd on the MiSTer is dead (System file + catalog
  damage) — restore from a backup; do not reuse as a test oracle.
- An F-line/coprocessor trap from RAM PC 0x629AC -> 0x40FAA was captured in
  the runaway ring during the hang — System-file code, NOT the ROM
  self-probe red herring. Belongs to the FPU handoff
  (`docs/handoff_fpu_timing_closure_2026-06-10.md`), noted there-adjacent.
- MODE SENSE still serves the raw allocation length (deliberately untouched
  — working path, no evidence of under-read); revisit if a wedge recurs
  with PSC3 showing a disk target parked in DATA_OUT.

---

## What is ALREADY fixed and validated — don't re-chase these

1. **CPU-side read corruption (`fefc429`, today)** — the slot-owned SDRAM
   read handshake. Before it, CPU reads/fetches could latch a neighbor
   transaction's word; the CPU then *wrote that garbage to disk* (journal
   showed `0x51C9`/`0x0000` clobbers). Validated: 2× full 1320-test corpus
   runs, every 16 KB journal commit byte-clean (~42 MB of pseudo-DMA
   writes total). Raw proof: `docs/bench_results/2026-06-10_af34c4c4_*.jsonl.gz`.
2. **scsi.v word-mode write byte-duplication** (`384bc37`): late `din`
   sampling in word-mode pseudo-DMA duplicated the even byte into the odd
   slot; fixed by latching the odd byte at beat-1 `stb_ack`.
3. **Warm-boot bus-error on stalled DMA** (`c616bf3`): the 8 µs undecoded
   -address timeout no longer fires on DREQ-stalled DACK cycles.
4. **Selection hang** (`5f147a4`), **dbg_scsi2 phase decode** (`8465259`).
5. SCSI is NOT generally broken: the bench .hda boots from SCSI every
   time, System 6 mounts and browses it in the Finder, and the corpus
   read every test program off it correctly.

## Scope of today's validation — and the gaps (= the suspects)

The corpus validation exercised ONE traffic pattern: **word-mode**
(`PSNC: word_l=1 long_l=0`) sequential-LBA 16 KB writes to a single fixed
region, plus sequential reads at boot. Mac OS does much more, and each gap
is a candidate for the remaining corruption:

### Suspect 1 — LONGWORD pseudo-DMA mode (UNVALIDATED, prime suspect)
`scsi.v`/`ncr5380.sv` implement a longword DACK path (`dma_longword`,
`long2nd_pending`, `cpuLongword` from `LBMacTwo.sv`). The Mac II ROM SCSI
Manager's blind-transfer loops use `MOVE.L` — the 8× unrolled
`MOVE.L (A2)+,(A1)` loop at ROM `0x40026BC2` is exactly that — so real
Mac OS I/O runs the LONG path. The `384bc37` odd-byte fix was proven for
WORD mode; verify the equivalent late-`din` hazard on the long path's
2nd/3rd/4th byte beats (same class of bug, different beats). Read
`scsi.v` around the beat-1 stb_ack latch and check whether long-mode
beats have the same protection.

### Suspect 2 — scattered-LBA writes / block addressing
The bench always rewrote the same 32-block region from offset 0. Mac OS
writes catalog/extents/bitmap/data scattered across the disk with seeks
between. An LBA-computation or flush-ordering bug (stale sector index,
sd_buff handoff across block boundaries, `io_busy` overlap between
back-to-back writes at different LBAs) would corrupt *unrelated* parts of
the volume — which is what "disk gets corrupted over a session" looks
like. Check `scsi.v` block/LBA bookkeeping and the HPS `sd_lba`/`sd_wr`
handshake in `LBMacTwo.sv` for multi-write sequences.

### Suspect 3 — interrupt-interleaved transfers
The bench ran with a simple IRQ environment. Mac OS takes VBL/VIA/SCC
interrupts mid-transfer; the driver suspends/resumes pseudo-DMA. If the
NCR dma engine or the target buffer pointer mishandles a paused-resumed
transfer (REQ pauses: `req_drop_count` was 17–22k even in the clean bench
runs — normal HPS flush throttling, but the resume path under *CPU-side*
pauses is different), bytes could slip. PSCW/PSNC/PSWL probes are still
in the bitstream for exactly this.

### Suspect 4 — phantom/spurious writes, not data corruption
"Corrupted disk" after a session can also be HFS-level: volume not
unmounted cleanly (the core has NO SCSI eject — `eject.c` is .Sony-only;
MiSTer remounts the image per-core), bench auto-boot re-running and
REWRITING /Results.jsonl on every restart while the bench disk is
mounted, or writes lost at power-off. Rule this in/out FIRST (Step 0) —
it's cheap and changes everything downstream.

## Step 0 — establish a reproducible case (do this before any RTL work)

We have a unique advantage: **host-side byte-exact access to the disk
image**. Protocol:

1. Build a test image: copy a known-good bootable System 6/7 .hda; md5 it.
   Keep a pristine copy.
2. `scp` to the MiSTer, mount, run a CONTROLLED session script by hand:
   boot to Finder → copy a folder → restart → boot → verify → shut down
   cleanly. (Vary one factor per run: with/without restart, with/without
   writes, word of what was done each time.)
3. After each session: `md5sum` on the MiSTer, `scp` back, and **binary
   diff against pristine** (`cmp -l` / python) — classify every changed
   byte range: expected HFS metadata (MDB/alternate MDB at fixed offsets,
   catalog B-tree, allocation bitmap, file data you intentionally wrote)
   vs UNEXPLAINED ranges. Unexplained ranges = real corruption; their
   content tells the mechanism (look for the `0x51C9`-style neighbor-word
   signature, byte-duplication signature from the old scsi.v bug,
   512-byte-aligned blocks of foreign data = LBA addressing bug,
   all-zeros = dropped/lost write).
4. If corruption appears: bisect the session (which op introduces it) and
   note whether ranges are word-, long-, or block-aligned — that aligns
   1:1 with suspects 1/3 vs 2.

The user has likely already seen a corrupting case — **ask what
disk/operations produced it** and start from that repro if available.

## Step 1 — targeted bench (parallel track, needs Retro68 machine)

Extend the supervisor bench (`SingleStepTests/preboot/supervisor_bench/`,
`variant_cpu_scsi.s` lineage — same machinery that nailed today's bug)
with a SCSI exerciser payload:
- write a per-LBA pseudo-random pattern across a WIDE scattered LBA set,
  read back and verify, journal mismatches with {lba, offset, expected,
  actual} — distinguishes data-path vs addressing instantly;
- a `MOVE.L`-based transfer loop variant to exercise long mode
  (suspect 1) — the ROM driver path does this, but a bench version gives
  controlled patterns + the existing recovery/journal infrastructure.

## Tools you already have

- Probes (RBF `af34c4c4`, 20 instances): PSCW (target write state), PSNC
  (NCR DMA: dreq/dma_en/word_l/long_l/`dma_wr_count`), PSWL
  (blind_wr/req_drop counters), PADR/PSTA/PACT, PIFA/PIFC (IF-PC), PRNG/
  PRWF/PIFD (bench-payload-tied; repurposable). `bash scripts/read_probes.sh`.
  Budget is at the ~20 ceiling — trade bench-specific rings for SCSI
  probes if needed.
- Deploy/observe loop: `scratch/cir_bisect/deploy_and_run.sh`, `shot.sh`;
  journal extraction recipe in the FPU handoff.
- Prior art: `docs/SCSI_IOTEST_INVESTIGATION.md` (the word-mode write bug
  hunt — methodology template), `docs/MISTER_HARDWARE_DEBUGGING.md`.

## Open adjacent items (related, not this handoff's core)

- **Cold-boot SCSI** (memory `project_scsi_iotest_investigation`): CPU
  released before SCSI/HPS ready on power-on — boot availability, not
  corruption; retest now that the read-path fix is in (old evidence was
  gathered with the read bug live).
- **No SCSI eject/unmount**: bench skips eject on SCSI boots by design;
  consider implementing SCSI START/STOP UNIT → MiSTer unmount, or at
  least document the OSD-replace workflow.

## Don'ts

- Don't re-debug the NCR selection/arbitration or the word-mode odd-byte
  path — proven healthy/fixed (see top).
- Don't trust Verilator for this (no SDRAM arbiter, no HPS latency, and
  feedback memory says sim SCSI is broken anyway).
- Don't run `read_probes.sh` during a Quartus compile.
- Don't let the bench .hda stay mounted during Mac OS experiments — every
  restart boots it and writes the journal (md5 churn that looks like
  corruption).
