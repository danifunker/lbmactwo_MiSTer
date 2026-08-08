# Handoff — fix the IF-ring fault-capture probe + resume read-leak-fix validation

**Date:** 2026-06-14 · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Predecessors:** docs/handoff_sdram_fix_residual_2026-06-13.md (residual hunt), memory
`project_residual_read_corruption.md` (current unified picture — READ IT FIRST).
**Parked, do not conflate:** docs/handoff_asc_sound_fifo_hang_2026-06-13.md (ASC sound bug),
68020 256-byte I-cache eval (spawned task).

## TL;DR — two jobs

1. **Fix the IF-ring fault-capture probe** (Task A). It has two bugs that stop it capturing the
   faulting opcode of the illegal/F-line crashes. Both are understood; fixes below.
2. **Then run the originally-intended test: validate the read-leak fix** (Task B). That validation
   is still owed — the leak never recurred this session, so we never confirmed `DELIVERED=0`.

## STATUS — Task A APPLIED + DEPLOYED (2026-06-14, awaiting HW repro)

Both probe bugs fixed in `rtl/dbg_wedge.sv`, built, timing-checked, deployed:
- **BUG 1 fixed:** IF-ring captures `rd_word` (raw SDRAM dout), not `cpu_din` (stale/0 under the
  `cpu_rd_take` gate). One line at the fetch-complete log.
- **BUG 2 fixed:** asymmetric freeze — illegal (vec 4 @ `0x10`) freezes in ANY region (catches the
  ROM-execution Sad Mac); F-line (vec 11 @ `0x2C`) stays RAM-only (filters the benign ROM FPU
  self-test). Kept VBR=0 exact-addr match (the "try first" path).
- **Build `62f39bbf`** (was `b3cf8414`): exit 0; `scratch/wp.tcl` confirms worst path is still the
  boot-irrelevant FPU `move_packed_encode_reg` cone (−109.8 ns, expected) and NO `ifr_/ifp_/prgr`
  setup path failed (IF-ring meets timing). `scp`-deployed to `_Unstable`, on-target md5 verified;
  **NOT reloaded** (shared board — user loads it).
- **WORKING TREE STILL UNCOMMITTED** (read-leak fix + IF-ring + `cpu_state.tcl` always-dump hack) —
  commit only after Task B validates.
- **Remaining = HW, needs the user to run the core:** (A) reproduce the Sad Mac on core-reload →
  read `IF-FAULT:` (expect `frozen=1 trap=illegal(4)` + a real NEWEST opcode). If `frozen=0` it's the
  non-zero-VBR case → next build matches the ROM-VBR vectors (~`0x2816` illegal / ~`0x2832` F-line).
  (B) Task B read-leak validation below.

## ROUND 2 — round-1 probe MISSED; reframed + rebuilt (2026-06-14)

Loaded `62f39bbf`, hit the Sad Mac, read probes. **Both round-1 fixes failed, but the read was
diagnostic:**
- `frozen=0`, `raw_leaks=0`. Ring's live PCs = `0x4080377C/74/76/78`, all `word=0x0000`.
- `0x40803778` is NOT a runaway: `addrDecoder.v:160` selects ROM for all `0x40xx_xxxx`, and the SDRAM
  fetch (`LBMacTwo.sv:1642`) uses only `memoryAddr[18:1]` ⇒ maps to **ROM byte offset `0x3778`**. The
  ROM there (`boot0.rom`) is a real **memory-scan/checksum loop**: `241A MOVE.L (A2)+,D2 / B592 /
  5383 SUBQ.L #1,D3 / 66F8 BNE.S 3774`. So the opcodes are `0x241A/B592/5383` — **not** `0x0000`.
- **BUG 1 was the wrong fix** — `rd_word` vs `cpu_din` was never the issue; the **capture EDGE** is.
  The ring logged at `mac_dout_valid` (`cpu_sdram_rd_done`), a cycle too late — `sdram_do` had moved
  on, reading `0x0000`. It ALSO silently dropped fetches off that edge (ring stopped recording at
  `0x377C`), so the ring contents weren't even the true last-pre-fault fetches.
- **`frozen=0` reframed:** a `MOVE.L (A2)+` scan loop faults with a **bus error (vec 2) / address
  error (vec 3)**, NOT illegal (4) / F-line (11) — which is all the freeze watched. (So the earlier
  `0F/03` "illegal" Sad-Mac decode is suspect; `0x03` may literally = vector 3 = address error.)

**Round-2 fix (built; this is the deploy in progress):** `rtl/dbg_wedge.sv` +
`scripts/cpu_state.tcl`:
1. **Capture-edge fix:** log the fetch at `ifp_pending && rd_latch && cpu_rd_take` — the EXACT
   `cpu_data` latch edge (`cpuSlotOwned==sdram_slot_cpu_rd`, `LBMacTwo.sv:1322` +
   `dataController_top.sv:218`), where `rd_word` is valid. Fixes real opcodes AND recording
   continuity.
2. **Free-running fault-vector recorder (PRGR src 13/14/15, last-wins):** on any FC=5 read of a
   processor-fault vector (offset `0x08..0x2C`, skip `0x28`=A-line) latch `last_vec_addr` (vector
   offset), `last_vec_pc` (faulting PC = `last_if_addr`), `vec_seen_count`. Overwrites ⇒ benign early
   boot-probe bus-errors get replaced; at the Sad Mac it holds the **FATAL vector + PC**, no
   false-freeze risk. `cpu_state.tcl` prints `VEC-RECORDER: last=BUS-ERROR(2)…  faulting_PC=0x…`.
   Assumes VBR=0 (`count=0` on a fault ⇒ VBR≠0, escalate to a VBR tap). Ring freeze unchanged
   (illegal/F-line only) — will be widened to the real vector next round once the recorder IDs it.

**Next HW step:** reproduce the Sad Mac → `read_probes.sh` → read `VEC-RECORDER:` (the fatal vector +
faulting PC) and the now-valid `IF-FAULT:` ring words. Then look up `faulting_PC` in the ROM/disk
image to see the faulting instruction.

## Current deployed state (READ before touching)

- **Deployed RBF: `62f39bbf`** (was `b3cf8414`) in `/media/fat/_Unstable/LBMacTwo.rbf` (NOT
  auto-loaded — the user loads it). Contains: the **read-leak fix** + the **coherency detector** +
  the **FIXED IF-ring** (both probe bugs above resolved).
- **The working tree is UNCOMMITTED** (validate, then commit): the read-leak fix
  (`LBMacTwo.sv` ~918 `cpu_rd_take`, `dataController_top.sv:218,228`, `sdram.v` dout_addr tag) +
  the IF-ring + a **diagnostic hack in `scripts/cpu_state.tcl`** (the `IF-FAULT` block was edited to
  ALWAYS dump the ring even when `frozen=0` — keep it, it's useful, but know it's there).
- **SHARED BOARD:** the DE10 is shared with MacLC sessions. **One agent on HW at a time.**
  Deploy = `scp` only; **do NOT `/api/launch` (reload)** unless the user says so — a reload steals
  the board from their MacLC session (this burned us once). The user runs/reloads the core himself.

## Task A — fix the IF-ring probe (`rtl/dbg_wedge.sv` + `scripts/cpu_state.tcl`)

The probe (PRGR, sources 6-12) is supposed to freeze on an illegal/F-line and record the faulting
opcode + PC + 3 lead-up fetches. Live test on the Sad Mac showed:
- **PCs record correctly** (e.g. `0x40007BB0`, `0x00004D52`) → the ring's recording works.
- **BUG 1 — every captured word reads `0x0000`.** The ring stores `cpu_din` for the fetched word,
  but the read-leak fix's `cpu_rd_take` gating changed `cpu_din` (=`cpu_data_in`) timing so it's not
  valid at the `mac_dout_valid` capture edge. **FIX:** store **`rd_word`** instead (the raw SDRAM
  `dout`, already a dbg_wedge input, valid at the read regardless of the gate). One line:
  `ifr_word[ifr_head] <= rd_word;` (was `cpu_din`).
- **BUG 2 — the ring never freezes on the Sad Mac** (`frozen=0`). It freezes on
  `vecfetch (cpuAddr==0x10 illegal / 0x2C F-line, FC=5) && last_if_addr < 0x40000000`. The Sad Mac
  isn't caught — most likely the **RAM-region guard skips it because the illegal is taken during
  ROM execution** (`last_if_addr >= 0x40000000`); possibly also a **non-zero VBR** (the ROM debugger
  sets VBR≈`0x00002806`, so the vector could be fetched at `0x00002816`, not `0x10`).
  **FIX (try first):** drop the region guard for ILLEGAL only (catch ROM-execution illegals), keep
  it for F-line (so the benign ROM FPU self-test — an F-line from ROM — stays skipped):
  ```
  if (!ifr_frozen && !cpuAS_n && cpuRW && cpuFC==3'b101) begin
      if      (cpuAddr==32'h10)                               begin ifr_frozen<=1; ifr_vec<=4;  end // illegal: any region
      else if (cpuAddr==32'h2C && last_if_addr<32'h40000000)  begin ifr_frozen<=1; ifr_vec<=11; end // F-line: RAM only
  end
  ```
  **If that still misses** (`frozen=0`), it's the VBR case — also match the ROM-VBR vectors
  (`cpuAddr==0x00002816` illegal / `0x00002832` F-line, and/or the `0x4080xxxx` mirror). NOTE the
  old IF-ring build `25f57ad8` DID catch a VBR=0 illegal at `0x10` from RAM, so VBR=0/RAM illegals
  work — the Sad Mac differs by being ROM-execution and/or ROM-VBR.

Keep the probe at 5 instances (PADR/PSTA/PACT/PFST/PRGR) — adding probes worsens timing and amplifies
the corruption. The IF-ring lives inside PRGR (no new probe). After the fix: `bash scripts/build.sh`,
confirm exit 0 + md5 changed + worst path still the boot-irrelevant FPU `move_packed_encode_reg` cone
(`scratch/wp.tcl` pattern), then `scp` to `_Unstable` (no reload).

**How to use it once fixed:** reproduce any illegal/F-line crash → `bash scripts/read_probes.sh` →
the `IF-FAULT:` block shows the NEWEST word = the faulting opcode. **Garbage opcode = data
corruption (write-path suspect); a real F-line/FPU opcode = coprocessor/feature issue.** The ring
freezes on the FIRST illegal/F-line per FPGA-config (the core-reload Sad Mac), so to catch MacTCP/
Finder later you'll need a guard to skip the Sad Mac's PC once known, or capture it per-core-reload.

**Alternative / faster confirmation (recommended in parallel):** the Sad Mac (illegal during ROM
execution, core-reload first boot) most likely = **corrupted ROM/data in SDRAM on core-reload**. Build
the **`dbg_coldinit`** variant (ROM byte-sum probe, `scripts/read_coldinit.tcl`) and check the ROM
checksum on a Sad Mac boot. A mismatch *directly confirms* the write/download-path theory without
chasing the opcode.

## Task B — the ORIGINAL test plan: validate the read-leak fix

This is what the hardware testing was for before the crash-chasing detour. **Still unverified.**

- **The read leak (real, caught once):** the `cpuSlotOwned`/`cpu_data` handshake latched a NEIGHBOR
  slot's SDRAM word. Detector caught it once: **CPU read RAM word `0x013660` but got data from
  `0x413660`** (differ only in bit 22 = RAM vs ROM/disk region; `0x413660` was the CPU's own adjacent
  ROM instruction-fetch, PC `0x40826CC0`).
- **The fix (deployed, UNVALIDATED):** `cpu_rd_take = (dout_addr==arb_mac_addr) || bounded-timeout`
  gates both `cpu_sdram_rd_done` and the `cpu_data` latch/mux. Timeout ⇒ cannot hang.
- **VALIDATION PROCEDURE:** warm-reboot **7.5.5** repeatedly (7.1 boots too cleanly; 7.5.5's heavier
  load + boot-looping gives more leak-prone bursts). **Do NOT core-reload** — the `raw_leaks`/
  `DELIVERED` counters accumulate across warm resets and only clear on a core-reload (AS_cycles
  monotonic = no reload). After a batch, `bash scripts/read_probes.sh` → the `COHERENCY:` line:
  - **`raw_leaks>0` with `DELIVERED=0` = FIX VALIDATED** (leak condition recurred, gate suppressed
    every one before it reached the CPU). **This is the goal.**
  - `raw_leaks=0` = leak didn't recur this session (inconclusive — keep stressing).
  - `DELIVERED>0` = the fix has a hole (timeout fallback let one through) — investigate.
- Once validated: **commit** the read-leak fix (it's been uncommitted pending this).

## The bigger picture (why the crashes ≠ the read leak)

A full 2026-06-14 session showed **`raw_leaks=0` on every crash** (Sad Mac, TattleTech hang, Finder
F-line, MacTCP illegal) — so the read-address leak is NOT what's crashing the system. The build
**boots to a usable Finder + runs apps** (big step up). The crashes are SEPARATE bugs and/or
**data-VALUE corruption the detector is blind to** (it catches wrong-ADDRESS reads, not right-address-
wrong-VALUE):
- **Sad Mac `0000000F/00000003`** = exception type 3 = **illegal instruction** (decoded via the SE/II
  Sad Mac code format; `0F`=exception, second line=type; ref umich sadmaccodes.txt). Core-reload
  first boot, from ROM execution. **Leading hypothesis: corrupted ROM/data in SDRAM on core-reload.**
- **MacTCP "illegal instruction"** — 7.5.5 extension parade.
- **Finder "bad F-Line"** at runtime, FPU `RESTORE_FRAME` active = the known **FPU conversion-datapath
  / Finder-F-line bomb** (separate open item, see [[project_pram_video_scsi]] memory).
- **Leading root-cause theory: the WRITE path.** Writes use the immediate raw DTACK
  (`ram_or_rom_dtack_raw`, `LBMacTwo.sv:873`) with **NO slot-ownership gate** — the read fix's
  untouched twin. A marginal write ⇒ corrupted stored data ⇒ garbage opcode ⇒ illegal, with
  `raw_leaks=0`. Candidate fix = an analogous write-slot-ownership gate (bounded). DO NOT deploy
  blind — confirm first (the fixed probe's opcode, or the `dbg_coldinit` ROM checksum).

## Procedures

- Host/creds: `scripts/local.env` (`MISTER_HOST` 192.168.99.143, `MISTER_HTTP_PORT` 8182,
  `MISTER_SSH_KEY`). Build: `bash scripts/build.sh` (run_in_background; ~20 min; confirm md5 changed).
  Deploy: `scp` RBF → `/media/fat/_Unstable/LBMacTwo.rbf` (**no reload on a shared board**).
  Probe read: `bash scripts/read_probes.sh` (decodes via `scripts/cpu_state.tcl`). Screenshot:
  `bash scratch/cir_bisect/shot.sh scratch/<name>.png`.
- Quartus rewrites `LBMacTwo.qsf` mid-build; don't edit during a build. `DBG_WEDGE=1` (qsf:71) gates
  the probes; comment it out for a shippable build.

## Key files

- `rtl/dbg_wedge.sv` — the probe (coherency detector PRGR src 0-5; IF-ring src 6-12). **Both bugs here.**
- `scripts/cpu_state.tcl` — probe decoder (`COHERENCY:` + `IF-FAULT:` blocks; has the always-dump hack).
- `LBMacTwo.sv` ~903-933 (read-leak fix handshake + `cpu_rd_take`), :873 (`ram_or_rom_dtack_raw`,
  the un-gated write DTACK), ~1640-1710 (arb/sdram), dbg_wedge instantiation ~1778.
- `rtl/dataController_top.sv:218,228` (cpu_data latch+mux, gated on `cpu_rd_take`).
- `rtl/sdram.v:185` (dout tagged with `dout_addr`).
