# Resume handoff — FPU is DONE; now testing the memory-corruption (open-bus) fix

**Date:** 2026-06-15 · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Read first:** memory `project_residual_read_corruption.md`. **You are MID-TEST** — a fix is staged and
awaiting HW results (see "RIGHT NOW").

## RIGHT NOW (what to do first)
A build is **staged in `/media/fat/_Unstable/LBMacTwo.rbf`** (md5 `2066eeb5`, HEAD `0b1d268`) and the
user is testing it. **It is NOT yet loaded by you — the user loads it.** Awaiting 3 results:
1. **7.5.5 boot** — does it get past the **MacTCP "illegal instruction"** (extension parade) to desktop?
2. **SimpleText launch** — does the **"bad F-Line" / hard lock** clear?
3. **7.1.2 boot** — regression check (must still reach Finder).

**The FPU probe is still in this build.** If anything bombs, have the user **leave it frozen** and run:
```
export PATH=/c/intelFPGA_lite/17.0/quartus/bin64:$PATH; quartus_stp_tcl -t scripts/read_fpu.tcl
```
It reads the FPU CIR state over JTAG **while frozen** (non-disruptive). `cir_state=CIR_EXECUTE`(5) = a
stuck arith op; `CIR_RESTORE_FRAME`(19)/`SAVE_FRAME`(17) = stuck FSAVE/FRESTORE; `CIR_IDLE`(0) + `EXCEPT=0`
= **FPU innocent → it's the memory corruption, not the FPU** (this is what we saw twice).

## The two big results this session (do not re-litigate)

### 1. The FPU is RESOLVED and HEALTHY (probe-proven). Stop chasing FPU timing.
The multi-session "F-line = FPU timing lottery" framing was a **red herring**. Board-free STA census
showed the FPU meets setup+hold timing (the −slack cones are FSM/bus/clkena-paced false-positives). The
**real** root cause: the **lite FPU disabled FDIV/FSQRT** (divrem unit cut in `2ffd682` to fit Cyclone V)
+ all transcendentals; OS 7.1 has **no software FPSP** and expects a full HW 68881 → any inline FDIV
F-line-bombed. **Fix shipped:** re-enabled the **divrem + sgl_ops** units = a **68040-class subset**
(`fpu_lite_g=true` + new `enable_divrem_g=true`, `mc68881_fpu_lite.vhd`). The **full 68881 does NOT fit**
(measured: 5385 LABs vs 4191, 28% over — the **trig unit is ~17.6k ALUTs**), so trig stays out.
- Fits 99% ALMs. Corpus 1261/1320 (FDIV/etc compute), save_restore 8/8, double 3/3.
- Also fixed a divrem post-divide setup cone (`ST_POST_DIV_PRE` wait state + scoped multicycle, `6b7062c`)
  that produced a wrong FDIV mantissa → an earlier hard lock.
- **JTAG probe (`p_fpcs` + `read_fpu.tcl`) PROVED the FPU innocent at BOTH the 7.5.5 MacTCP-illegal AND
  the app-launch bad-F-Line** (IDLE, clean FSAVE/FRESTORE, `EXCEPT=0`). The FPU did NOT issue those.
- **Still-trapped gaps (documented `docs/FPU_INSTRUCTION_COVERAGE.md`):** transcendentals (FSIN/FCOS/
  FLOGN/…) + FGETEXP/FGETMAN. Rare; usually go through SANE software. **Do NOT try to add trig — it
  cannot fit.** Abandoning for a Quadra is also a dead end (no FPGA 68040 core exists).

### 2. The remaining instability is RESIDUAL MEMORY CORRUPTION, not the FPU.
"illegal instruction" (MacTCP, 7.5.5 extension parade) + "bad F-Line" (app launch) + the hangs are all
the **same** corruption — a corrupted instruction fetch / bus read — surfaced by 7.5.5's heavy extension
load + app launch (7.1.2 dodges it). **This is the session's current work.**

## The fix under test (open-bus `$FFFF`, port of MacLC `f9fbf56`)
**Mechanism (agent-verified, file:line):** LBMacTwo's CPU read mux fell through to the **stale last-
latched SDRAM word** (`dataController_top.sv:228` `cpu_data`) on an **undecoded** read, not `$FFFF` open-
bus. TG68KdotC saves `din`(=`cpu_data_in`) on BERR and **re-feeds it as the opcode on its `berr_inhibit`
retry** (`LBMacTwo.sv:1123-1129`). So a hardware probe of an undecoded address — **exactly what MacTCP
does at startup** — gets a stale neighbour word **re-executed as an instruction** → illegal / bad-F-Line.
**Fix (`LBMacTwo.sv:1091`):** `cpu_data_in` returns `$FFFF` for undecoded reads, gated
`(~any_select & ~is_cpu_space)` — the EXACT set the ~8µs BERR already targets, so it **cannot** affect any
decoded RAM/ROM/peripheral/FPU read (low risk), and it propagates to the retry data via the TG68 `din`.

**MacLC reference** (`C:\Temp\mistercore\MacLC_MiSTer`, the sibling core): agent compared both cores. The
other 4 MacLC corruption fixes are **NOT applicable** (`72c5f99`/`0b57f5e` = V8 RAM-sizing phantom-bank,
LBMacTwo's `$0` is a fold + sizes from physical config; `5c3c94f` = VRAM-on-SDRAM, ours is BRAM + already
has the SDRAM address-tag coherency fix; `23facf9` = PDS slot, LBMacTwo is the *origin* of the empty-slot
open-bus mechanism). `f9fbf56` was the one genuine gap.

### If the open-bus fix does NOT fully fix it
- **Re-read the FPU probe first** to re-confirm FPU-innocent (expect yes).
- **P2 (agent's #2):** widen open-bus to the `$F1-$F8` cardless slots *below* `$9` and undecoded `$F0`
  offsets (`addrDecoder.v:140-157,294-316`) — but the P1 `cpu_data_in` default likely already subsumes
  this (it's address-range-agnostic). Verify with a probe of the failing PC.
- **The deeper residual SDRAM read/write corruption** (`project_residual_read_corruption`): leading
  suspect = the **un-gated write DTACK** (`LBMacTwo.sv:873` `ram_or_rom_dtack_raw`, the read-fix's
  untouched twin) → a marginal write stores garbage → garbage opcode later. The read side already has the
  slot-owned address-match fix (`5eaa86b`, `cpu_rd_take`).
- **P3 (deferred, HIGH risk):** TG68's BERR stack frame is not reliably handler-recoverable
  (`TG68KdotC_Kernel.vhd:3785-3823`); MacLC hit the same. Not load-bearing once open-bus avoids needing
  recoverable BERR. Needs VHDL→Verilog regen + full SingleStepTests + boot re-validation.
- **MacsBug** (user has it) FROZE on the bomb earlier (its exception-path FSAVE) — not a reliable oracle
  here; the `read_fpu.tcl` probe is.

## Key commits this session (branch `7-1-2-boot-working`)
- `44302c2` fpu/timing+build: close cir_conv_src_reg cone (proven multicycle) + probe-free build
- `75201d7` fpu: re-enable divrem+sgl_ops (68040 subset) to fix the Finder FDIV bomb
- `6b7062c` fpu/divrem: fix ST_POST_DIV setup-timing fail (wrong FDIV result -> hard lock)
- `0b1d268` fix(bus): open-bus $FFFF on undecoded reads (port MacLC f9fbf56) + FPU CIR probe ← **HEAD**

## Build artifacts / revert points (`output_files/`)
- `LBMacTwo_openbus_fix.rbf` = `2066eeb5` = **currently staged** (HEAD `0b1d268`).
- `LBMacTwo_e102e0f9_divremfix.rbf` = lite+divrem+divrem-fix (no open-bus). 
- `LBMacTwo_dbgfpu_probe.rbf` = the probe build (e102e0f9 + probe).
- `LBMacTwo_4db7a3f5_known_good.rbf` = original lite, known-good boot (ultimate revert).

## Config / how to change the FPU scope
- `rtl/mc68881/vhdl/mc68881_fpu_lite.vhd`: `fpu_lite_g=>true, enable_divrem_g=>true` (68040 subset).
- `enable_divrem_g` (new generic) gates divrem+sgl_ops in `mc68881_alu.vhd` (gen_divrem_full/sglops_full,
  the dispatch) and `op_disabled_by_lite(op, enable_divrem)` in `mc68881_top.vhd`.
- `DBG_FPU=1` (`LBMacTwo.qsf`) gates the `p_fpcs` FPU probe. Strip for a clean release build.

## Procedures (all confirmed working this session)
- **Build:** `bash scripts/build.sh` (run_in_background; ~20-30 min; fits 98-99% — TIGHT). Confirm md5
  changed + `Worst-case hold slack` positive + worst setup is the boot-irrelevant `move_packed` cone.
- **Stage (NO load):** `scp -i $MISTER_SSH_KEY output_files/LBMacTwo.rbf root@$MISTER_HOST:/media/fat/_Unstable/LBMacTwo.rbf`
  then `ssh ... md5sum` to verify. Creds in `scripts/local.env` (HOST 192.168.99.143). **Shared board** —
  scp only, never `/api/launch`; the user loads.
- **FPU probe read:** `quartus_stp_tcl -t scripts/read_fpu.tcl` (JTAG, non-disruptive, reads while frozen).
- **Screenshot:** `bash scratch/cir_bisect/shot.sh scratch/<name>.png` (Remote API; the bomb dialog names
  the faulting process — that's how we IDed MacTCP).
- **FPU corpus (after FPU VHDL edits only):** `wsl -d Ubuntu-24.04 ... rtl/mc68881/convert_to_verilog.sh`
  (now passes `-genable_divrem_g=true` so the bench matches the shipped FPU), then
  `wsl -e bash -lc 'cd SingleStepTests/cpu_fpu && make clean && make && ./obj_dir/Vcpu_fpu_tests <corpus>.json | tail -1'`.
- **Timing (board-free):** `quartus_sta -t scratch/{diag_timing2,fpu_fail,wp}.tcl`.

## Parked (don't conflate)
- FPU transcendentals/GETEXP/GETMAN (can't fit — `FPU_INSTRUCTION_COVERAGE.md`).
- `fline_trap_regression` corpus housekeeping: 4 now-enabled ops (FSGLMUL etc.) should leave its
  expect-trap list (they run in HW now; 20/24 is expected, not a regression).
- The earlier session's F-line-timing handoffs (`docs/handoff_fline_*_2026-06-14.md`) — superseded by
  result #1 above (it was never timing).
