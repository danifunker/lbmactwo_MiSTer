# Handoff — SDRAM-init fix landed (boots to Finder); chasing the residual read corruption

**Date:** 2026-06-13 evening · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Predecessor context:** docs/handoff_fpu_pipeline_2026-06-13.md (superseded for the boot blocker), the round-1/2/3 FPU prompts/results, memory [[project_tg68_runaway_unification]].

## TL;DR — resume in 3 steps

1. A capture-probe build is **in flight: task `bram3m41n`** (`bash scripts/build.sh`). When it finishes, confirm exit 0 + RBF md5 changed.
2. Deploy it and reproduce a real-system crash (boot `MacLC_7-1.hda`, run TeachText or any app → F-line / illegal-instruction bomb), then read the **IF-fetch ring**:
   `bash scripts/read_probes.sh` → look for the `IF-RING:` block (8 `{PC, word}` fetches frozen at the trap).
3. Find the corrupted fetch (word ≠ what the code should be / word == a *neighbor* fetch's word = the read-path leak signature, exactly how `fefc429` was nailed). That pins the residual mechanism → the fix.

## THE WIN this session (committed, HW-validated)

**Root cause of the boot corruption = broken SDRAM init.** LBMacTwo's `rtl/sdram.v` had the
old ladder (31 chipset cycles ~4µs, ZERO refreshes, bogus "wait 1ms" comment) that set the
SDR-SDRAM MODE register (CAS latency / burst) by **per-load luck** — it relied on the chip state
the *previous* core left behind. A wrong/marginal mode register → corrupted reads → garbage
opcodes → the "Finder illegal instruction" bomb on real boot and the F-line wedge on the cpu_fpu
bench. It also explains "**ONLY core reload corrupts the following load**" and "clears after
loading a different core first."

**Fix (commit `71ce6ba`):** ported MacLC `0bbe6bd`'s proper JEDEC ladder into `rtl/sdram.v`:
10-bit `reset` `0x3FF` (~126µs NOP wait) → PRECHARGE ALL @64 → 8× AUTO_REFRESH @56..28 →
LOAD_MODE @2. Content-preserving. LBMacTwo's `sdram.init = !sys_locked` fires only at cold config
before the ROM download, so the longer ladder is safe; the rest of `0bbe6bd`'s bundle (PLL-lock
sync `lock_sync`, `rom_loaded`, `clear_done` RAM pre-clear) was already present.

**HW-validated** (RBF `2503ecf7`, the probe-free SDRAM-fix build, currently deployed):
`dbg_coldinit` ROM sum `0x013FFEF5` OK, **0 PLL unlocks**, boots to a full **System 7.1 Finder
desktop** (Mac7-1 disk, Applications/System Folder/TeachText/etc.), runs apps. **Core reload now
comes up clean** — the case the memory said corrupts.

## THE RESIDUAL (what's left to chase)

ONE smaller, **intermittent** read corruption remains. Unified diagnosis (high confidence):
a stray bad fetch → **garbage opcode** → traps as:
- **F-line (vec 11)** if the garbage is `0xFxxx` — e.g. TeachText (NON-FPU! proves it's corruption,
  not the FPU), TattleTech.
- **illegal instruction (vec 4)** otherwise — MacTCP, Foreign File Access (7.5.5 extension parade).
- **error type 41 (dsFinderErr)** if it corrupts data/resources instead of code (Finder load).

Signature = **each boot gets further and dies at a different place with a different error** →
non-deterministic, **load-dependent** (heavy app/extension/file access). NOT a fixed
missing-instruction bug; NOT the FPU (FPU FSM idle through every hang).

Ruled out:
- **Refresh starvation** — NuBus video lives in BRAM, so the SDRAM busCycle-0 video slot is a
  permanent no-access `AUTO_REFRESH` slot; refresh is adequate even under heavy CPU load. (This is
  also why MacLC `90c7696` "reclaim video slot" does NOT port — it'd remove a refresh opportunity.)
- **Pure SDRAM init** — that's the fixed layer; the ROM checksum is now perfect.

Suspected: the `fefc429` read-path coherency (slot-owned SDRAM read handshake, `LBMacTwo.sv:903-919`
+ `dataController_top` `cpuSlotOwned` cpu_data latch) still marginal under bursty access. It is
STA-**clean** and "looks correct" on inspection — so the mechanism needs the HW capture below.

## The capture probe (build `bram3m41n`, UNCOMMITTED working tree)

`rtl/dbg_wedge.sv` now has an **IF-fetch ring (PRGR)**: 8-deep `{IF addr, fetched word}`, FROZEN
when the F-line(`0x2C`)/illegal(`0x10`) exception vector is fetched (FC=5 supervisor-data read;
classic Mac OS keeps VBR=0). A **RAM-region guard** (`last IF addr < 0x4000_0000`) skips the
boot-time ROM FPU self-test (which faults from ROM at `0x40xx_xxxx`) so the ring stays armed for a
real System/app corruption. 5 probes total (PADR/PSTA/PACT/PFST/PRGR) — lean for timing.
`scripts/cpu_state.tcl` decodes it (the `IF-RING:` block: prints `frozen`, `trap=F-line/illegal`,
and the 8 slots oldest→newest). Read via `bash scripts/read_probes.sh`.

**Readout caveat:** the corrupted fetch is identified by comparing each ring word to what the code
*should* be. For RAM (System/app) code that's loaded from the disk — easiest tell is the
**neighbor-word match** (a fetched word that equals an adjacent/recent fetch's word = the slot
leaked a neighbor's SDRAM data, the `fefc429` mechanism). If ambiguous, also note the faulting PC
and read that RAM longword back (or re-run — transient corruption re-reads clean).

**Uncommitted files (commit after the ring readout is validated on HW):**
`rtl/dbg_wedge.sv` (ring), `scripts/cpu_state.tcl` (PRGR decoder), `LBMacTwo.qsf` (`DBG_WEDGE=1`).
For a shippable build, comment out the `DBG_WEDGE=1` line (`LBMacTwo.qsf:71`).

## Commits this session (`7-1-2-boot-working`, local only — do NOT push)

- `71ce6ba` — sdram JEDEC init ladder (THE boot fix).
- `9d236e6` — sdc multicycle the round-2/3 `move_*_reg` FPU staging regs. NOTE
  `move_packed_encode_reg` is still **-107 ns** even multicycled — the `fp80_to_packed96_fast` BCD
  cone (~200 ns) is too deep for one register stage; round-3's packed staging needs reverting-to-
  inline or true pipelining. **Boot-irrelevant** (no FMOVE.P at boot). See
  docs/macbook_fpu_pipeline_round3_results.md.

## Other open items

1. **Residual read corruption** (above) — the main hunt. Capture via the IF ring → fix.
2. **Round-3 packed regression** — `move_packed_encode_reg` -107 ns. Revert-to-inline (the inline
   form was SDC-covered via `packed_result_*` at -1.9) or pipeline the BCD properly. The MacBook
   does the sim-first RTL; the FPGA session does build + slow-corner STA
   (`quartus_sta -t scripts/report_fpu_cones.tcl`).
3. **PRAM persistence** — spawned task `task_560f6415` (chip showing). `pram.NVR` exists on the
   MiSTer but SC2 isn't auto-mounting (`dbg_coldinit` shows `s2=0`); save path proven, load-back
   roundtrip unverified. See the spawned-task prompt.
4. **Warm-restart SCSI nugget** (MacLC `cae8a2c`): post-internal-reset the scsi.v *targets* have no
   module reset and can go "deaf" (blinking `?`). Separate from the cold-boot residual; relevant if
   restart-after-Shutdown misbehaves.

## MiSTer / procedures

- Host `192.168.99.143`, creds in `scripts/local.env`. **One agent on HW at a time** (shared with
  MacLC sessions); no ssh polling loops.
- **Deployed RBF:** `2503ecf7` (probe-free SDRAM-fix). `.s0 = games/LBMacTwo/MacLC_7-1.hda` (7.1
  boot disk; user also tests `MacLC_7-5-5.hda`). Pristine bench `cpufpubench.hda` = `33b6fc9c`.
- **Build:** `bash scripts/build.sh` via `run_in_background:true` (NOT `&` — a `&` leaves an orphan
  `quartus_sh`→`quartus_fit` that overwrites the RBF; if you see stray quartus with no
  `.compile_in_progress` lock, `taskkill //F` it first). ~20 min. Confirm md5 changed.
- **Deploy:** `scp` RBF → `/media/fat/_Unstable/LBMacTwo.rbf`, then
  `curl -s -X POST http://$MISTER_HOST:8182/api/launch -d '{"path":"_Unstable/LBMacTwo.rbf"}'`
  (reloads core, boots `.s0`). Deploying reloads the core (interrupts any live testing).
- **Screenshot:** `bash scratch/cir_bisect/shot.sh scratch/<name>.png`.
- **Probes (JTAG, NOT during a Quartus build):** `bash scripts/read_probes.sh` (decodes via
  `scripts/cpu_state.tcl`). Cold-load health: `quartus_stp_tcl -t scripts/read_coldinit.tcl`.

## Dead ends / don't re-tread

- The bench `PFLA`/`0x40042` "H1 read corruption" finding was a **red herring** — `0x40042` is the
  bench's `MOVE.L #$FFFFFFFF,(A0)+` fill loop; its `0xFFFF`/`0xFFF8` immediates are cpID-7 and the
  cpID-filter mis-fired. The bench F-line was the SDRAM-init corruption all along.
- Don't chase the FPU CIR for the app crashes — TeachText (no FPU) F-lines prove it's read
  corruption, not the coprocessor.
- Refresh starvation is ruled out (above). The MacLC `90c7696` arbiter change does not port.
