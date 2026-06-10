# Handoff — TG68 wild-PC runaway (unifies the SCSI "write wedge" + FRESTORE trap)

*2026-06-10, branch `fpu-bus-adapter-dani` @ `23f5bbd`.*

> ## ✅ RESOLVED — 2026-06-10, same day (commits `065d08d`..`fefc429`)
>
> This handoff's unification instinct was right but the suspect was wrong:
> it was **never a TG68 bug**. The probe loop it prescribed (PC-history
> ring → recovery-stub freeze → PIFD fetch-data capture) traced the
> cascade to a **top-level SDRAM read-path bug**: the DTACK coherency
> gate blinked with the busCycle interleave and `cpu_data` latched
> neighbor transactions' words, so DREQ-randomized cycles after pseudo-DMA
> DACK writes could fetch/read a stale word (PIFD caught `0x1ED8` in
> place of the ROM write loop's `DBF D5` opcode `0x51CD`, whose orphaned
> `$FFFA` displacement then executed as an F-line ⇒ vector 11; journal
> reads got `0x51C9`/`0x0000` neighbor words ⇒ the disk corruption). The
> visible runaway/IOWait symptoms below were the **bench's own recovery
> cascade** (SR=$2700 leak + stale longjmp), fixed in `recovery.s`
> (`dea2cfd`, hda `33b6fc9c`). Core fix: slot-owned AS-scoped read
> handshake (`fefc429`, RBF `af34c4c4`). Validation: full corpus runs
> (was wedged at run=1), journal byte-clean. Memory:
> `project_tg68_runaway_unification`. The text below is kept for the
> diagnostic record.

## TL;DR — the big realization

Two symptoms we were chasing as separate bugs are **the same TG68 CPU bug**:

1. **Supervisor cpu/fpu bench test #1 FRESTORE trap** (on `fpu-cir-fixes`): the
   CPU runs away to a wild PC (`0x50FFFFA2`, I/O space) after `FRESTORE`, and it
   **flips ok=1 ↔ trap=1 boot-to-boot** (timing-marginal).
2. **SCSI cpufpu-bench result-write "wedge"** (on `fpu-bus-adapter-dani`): the
   16 KB multi-block write freezes — but the SCSI controller is **healthy**
   (target REQ=1, NCR DREQ=1, `dma_en=1`, `blind_wr_count=0` so the Mac honors
   DREQ). The freeze is because **the CPU runs away mid-write**: its PC climbs
   **monotonically across ~720 KB of RAM** (`0x00295ACA → 0x002BE23C →
   0x002DB880 → 0x0031FB9E → 0x00345716`), `vbl_irq_count` frozen — classic
   runaway plowing forward through memory, abandoning the transfer.

**There is no SCSI bug to fix** (proven this session — see "SCSI is exonerated").
The root cause is a **TG68 prefetch/PC-restore/timing runaway** that trips during
(a) `FRESTORE` and (b) the bench's tight pseudo-DMA write loop. Both are
non-deterministic / timing-marginal. **Fix the TG68 CPU and both symptoms go.**

## RESUME HERE

State right now:
- Branch `fpu-bus-adapter-dani` @ `23f5bbd` (all SCSI diagnostic probes committed).
- On the MiSTer: RBF `feec7115` (the PSWL build) at `/media/fat/_Unstable/LBMacTwo.rbf`;
  bench disk `a21bcdd1` at `/media/fat/games/LBMacTwo/cpufpubench.hda`
  (pristine copy extracted at `/tmp/cfb_extract/cpufputestbench.hda`).
- Active JTAG probes (19): includes **PSCW** (target write state), **PSNC**
  (NCR5380 host DMA), **PSWL** (blind_wr/req_drop). PSC3, PFLA, PFLT disabled.

**Next step — build a "runaway-entry" probe** to catch the *transition* from
healthy execution into the runaway (this is the missing piece):
1. A **PC-history ring** in `dbg_min` (or via a TG68 dbg export): the last N
   instruction-fetch PCs (FC=6/2), captured continuously, frozen on a trigger.
2. A **trigger + classifier**: freeze the ring when the runaway starts — detect
   it as e.g. "PC left the bench/driver code window" or "an exception/trap fired"
   or "IF address jumped by a large delta." Capture alongside: was a `trap_*`
   (berr/addr/illegal/priv/1111) or an interrupt (`IPL`, VBR fetch) taken in the
   cycles before the PC went wild? That tells us whether the runaway is a wild
   BRANCH (stale-opcode, like the FRESTORE `cp_op_pc` story) vs a bad exception
   vector vs a corrupted return address.
3. Read it with `bash scripts/read_probes.sh` after reproducing on either path
   (SCSI write OR FRESTORE). Then trace the entry PC + mechanism into the TG68
   microcode.

The TG68 dbg-export path is known and easy (we used it for the FPU work): kernel
`TG68KdotC_Kernel.vhd` already exports `dbg_fline_trap`; add `dbg_*` outputs the
same way (entity port → `rtl/tg68k/tg68k.v` wrapper → `LBMacTwo.sv` → `dbg_min`).
**Caveat:** export only `std_logic`/`std_logic_vector` signals (no enum/int —
`numeric_std` vs `std_logic_unsigned` conflict); `TG68_PC`, `opcode`, `last_opc_read`,
`micro_state`-as-slv etc. are fine if already slv.

## SCSI is exonerated (do NOT re-debug it)

Proven via PSCW/PSNC/PSWL on the wedge:
- `tlen=32` (16 KB / 32-block write), `cmd_write=1`, `phase=DATA_IN`.
- target `req=1`, NCR `dreq=1`, `dma_en=1`, `pmatch=1`, `dma_ack_busy=0`,
  `holdoff=0` — everything is "go".
- **`blind_wr_count=0`** — the Mac never wrote while DREQ was low; it honors flow
  control. So it is NOT overrunning the target. (This killed the
  "deeper-buffer/blind-write" fix hypothesis.)
- The freeze point is **non-deterministic** (block 3, 4, 10 across boots) and
  the CPU PC climbs monotonically through RAM afterward = runaway.

The `dbg_scsi2` phase-decode bug (14-bit concat right-justified into 16 bits,
shifting the phase fields) was a real bug, fixed at `8465259`. The earlier
"phase 6/7" reading was that decode bug, not a real SCSI state.

## What we know about the runaway (from both paths)

- **FRESTORE path** (`fpu-cir-fixes` branch): the bench test #1 trap is a wild PC
  at `0x50FFFFA2` (FC=6 instruction fetch from I/O space). The kernel has
  machinery (`cp_op_pc` / `cp_pc_restore_pending` / `cp_mem_refetch`,
  `TG68KdotC_Kernel.vhd` ~`:405 :890 :1546 :4941`) meant to restore the PC after
  the FSAVE/FRESTORE bus dialog so `setopcode` doesn't load a stale word
  (the comment literally cites "sndOPC of FMOVE.L FP3,D1 = $6180 → BSR -128
  runaway"). On HW it's insufficient — a stale opcode → runaway branch.
  A `cp_op_pc` bisection probe was built there (commit `29929fa`, RBF `f1b8e023`,
  preserved in `output_files_fpu-cir-fixes/`) but never read — see
  `docs/fpu-cir-fixes.md`.
- **SCSI-write path** (this branch): the tight pseudo-DMA write loop
  (`MOVE.x` to the NCR DACK register, gated by DREQ) trips the same runaway at a
  variable point. Possibly the same prefetch/stale-opcode mechanism, or an
  interrupt taken mid-loop with a bad return, or a `MOVE`-loop prefetch hazard.
- Both are **timing-marginal / non-deterministic** — strongly implies a TG68
  prefetch/pipeline/PC-handling race, not a logic constant.

Leading hypotheses to test with the runaway-entry probe:
1. **Stale-opcode wild branch** (same as the FRESTORE `cp_op_pc` story) — a
   prefetched/refetched opcode is wrong, decodes as a branch, PC goes wild.
2. **Exception with a bad vector/return** — a trap or interrupt mid-loop returns
   to a corrupted address.
3. **Prefetch overrun on a specific instruction/timing** in the write loop.

## Build / deploy / observe mechanics

**Build** (~30–40 min): always structural —
```
rm -rf db incremental_db output_files/.compile_in_progress
nohup bash scripts/auto_recompile.sh > output_files/auto_compile_X.log 2>&1 &
```
Watch `output_files/.compile_in_progress`; verify `Full Compilation was
successful` + md5 changed. Incremental builds intermittently crash the fitter
(`Fatal Error: Access Violation at 0x0`) — always clean first.

**Deploy — use `POST /api/launch`, NOT the OSD launcher** (the OSD launcher
`tools/misterdeploy/launch_unstable_core.py` is unreliable: MiSTer persists the
menu cursor, no cursor feedback; it lands on the wrong core). `/api/launch` of a
bare `.rbf` is NOT MGL and loads `boot0.rom` + auto-mounts the bench `.hda`:
```
. scripts/local.env
scp -q -i "$MISTER_SSH_KEY" -o StrictHostKeyChecking=no \
    output_files/LBMacTwo.rbf "root@$MISTER_HOST:/media/fat/_Unstable/LBMacTwo.rbf"
# (md5-verify both sides)
# restore pristine bench disk before each run (the bench writes to it):
scp -q -i "$MISTER_SSH_KEY" -o StrictHostKeyChecking=no \
    /tmp/cfb_extract/cpufputestbench.hda "root@$MISTER_HOST:/media/fat/games/LBMacTwo/cpufpubench.hda"
curl -s -X POST "http://$MISTER_HOST:$MISTER_HTTP_PORT/api/launch" \
    -H "Content-Type: application/json" -d '{"path":"_Unstable/LBMacTwo.rbf"}'
```
`scripts/local.env`: `MISTER_HOST=192.168.99.143`, port 8182, key
`/c/Users/spam/.ssh/mister_only`.

**Observe**:
- Screenshot (no JTAG): `curl -s -X POST .../api/screenshots` then scp the latest
  `/media/fat/screenshots/LBMacTwo/*.png`. Bench shows `run/ok/bad/trap`.
- JTAG probes: `bash scripts/read_probes.sh` (decodes via `scripts/cpu_state.tcl`).
  **Must NOT run during a Quartus compile** (JTAG contends).
- The CPU/PC probe is decoded as `PC/addr=...` in read_probes output.

**Reproducing the runaway**: launch the SCSI bench (above) → it wedges at `run=1`
(test 1 painted, then the result-write loop runs away). The PC then climbs
monotonically (read PC a few times to confirm). The FRESTORE path is on the
`fpu-cir-fixes` branch (different RBF).

## Useful control: cpubench passes (CPU-only, no FPU)

`cpubench_fix.hda` (on the MiSTer) ran to `run=58 ok=58 trap=0` — BUT it uses
`jw_flush` (batched), so its first 16 KB SCSI write doesn't happen until ~run 234
(each record ~70 B, `JW_BATCH_BYTES`=16 KB). cpufpubench uses `jw_commit_line`
(per-record → 16 KB write after test 1) which is why it trips immediately. So
cpubench "passing" early is NOT proof SCSI writes work — it just hadn't written
yet. (Useful to know; not load-bearing now that SCSI is exonerated.)

## Branches / commits

- `fpu-bus-adapter-dani` (current): FPU bus-adapter line + this session's SCSI
  diagnostics. HEAD `23f5bbd`.
  - `23f5bbd` PSNC/PSWL NCR5380 probes (SCSI healthy).
  - `8465259` dbg_scsi2 phase fix + PSCW write-stall probe.
  - `1700f52` adopt cpufputestbench.hda.zip fixture.
- `fpu-cir-fixes`: the FRESTORE/`cp_op_pc` bisection line. `29929fa` (RBF
  `f1b8e023`, in `output_files_fpu-cir-fixes/`). Full thread in
  `docs/fpu-cir-fixes.md` — the `cp_op_pc` bisection probe was built but never
  read; reading it answers "is the restored PC wrong vs a stale fetched word".

## Key files

- `rtl/tg68k/TG68KdotC_Kernel.vhd` — the CPU. `cp_op_pc`/`cp_pc_restore_pending`
  (`:405 :890 :1546`), `cp_mem_refetch`/`_wait` (`:4941`), prefetch, `dbg_fline_trap`
  export (`:5414`). 4 `trap_1111` sites (`:3726 :3731 :4761 :5008`).
- `rtl/tg68k/tg68k.v` — bus wrapper (dbg ports pass through here).
- `LBMacTwo.sv` — tg68k_inst (`:721`), dbg_min inst, SCSI/dataController wiring.
- `rtl/dbg_min.sv` — all JTAG probes; `scripts/cpu_state.tcl` decodes;
  `scripts/read_probes.sh` runs it.
- `rtl/scsi.v`, `rtl/ncr5380.sv`, `rtl/dataController_top.sv` — SCSI (healthy;
  PSCW/PSNC/PSWL exports live here).

## Don't

- Don't re-debug the SCSI controller — it's healthy (proven).
- Don't use the OSD launcher — use `POST /api/launch`.
- Don't run `read_probes.sh` during a Quartus compile (JTAG contention).
- Don't trust the unit Verilator bench for this — it has idealized timing and
  won't reproduce the HW-timing runaway.
- Junk in the tree to ignore / not commit: `cr_ie_info.json` (Quartus crash
  dump), `output_files_fpu-cir-fixes/` (preserved build), `verilator/boot2.hex`
  (branch artifact, M).
