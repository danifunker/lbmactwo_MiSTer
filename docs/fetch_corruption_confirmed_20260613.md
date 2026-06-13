# CONFIRMED: instruction-fetch corruption (CPU/SDRAM read path), NOT the FPU

Date: 2026-06-13. Build: 23655a97 (focused 5-probe dbg_wedge, worst slack
**-1.633ns = representative** of the real probe-free build, NOT the -2.981
8-probe artifact). System 7.1 + 6.0.8, fresh disks.

## Evidence chain
1. Every hang/bomb (6.0.8 + 7.1): **FPU FSM IDLE** after completing clean
   Response-CIR dialogs (prim_rd_cnt = 10 -> 42 -> 84 across sessions). The FPU
   works and finishes; the CPU dies elsewhere. PFST idle every capture.
2. **Deterministic ROM address returns different wrong words** = read-path
   corruption (a fixed ROM word cannot vary):
   - ROM off 0x607E real = **0xF0F0**, fetched as 0xF0D0 / 0xFFFC / 0xFE18
     (across 6.0.8 0x4000607E and 7.1 0x4080607E aliases).
   - Single-bit flip F0F0->F0D0 = setup-time violation; gross 0xFFFC/0xFE18 =
     wrong-cycle / neighbor-word latch.
3. **Illegal-instruction bomb (vector 4, NON-FPU) reproduced at -1.633ns** ->
   real, not probe-amplified. CPU looping in ROM SysError handler ~0x40002434.
4. 6.0.8 = runaway (AS_cycles racing, fetch_cnt exploding 6500+/sample, phantom
   F-lines, FPU idle). 7.1 = tighter wait-loop at RAM ~0x22000 + VIA poll
   0x50F02000, FPU idle. Same family.

## Unifies ALL symptoms (one root cause)
hangs, "illegal instruction", "coprocessor not installed" (= phantom F-line from
a bad fetch, NOT a real FPU trap), "stack collision with heap", disk corruption
(MacLC_7-1.hda: catalog B-tree + MDB dirty bit = interrupted write), PRAM loss.
All downstream of corrupted instruction fetches -> crash -> collateral damage.

## Root cause locus + fix direction (NEXT PHASE)
SDRAM-read -> cpu_din -> TG68K data path + its DTACK/coherency handshake, under
marginal clk_sys timing (-1.633ns worst, -171ns TNS). Matches prior
project_tg68_runaway_unification (neighbor-word fetch, fixed fefc429
"slot-owned AS-scoped read handshake") -> that fix is timing-marginal now or has
a hole.
1. Audit cpu_sdram_rd_done / DTACK gating in LBMacTwo.sv + sdram_arbiter:
   is the correct word guaranteed latched at the correct cycle?
2. Pull detailed STA path report: is SDRAM-data->CPU-latch among the failing
   paths? If so it's a closure problem.

## NOT the cause (ruled in/out this session)
- Init-sequencer rework (full RAM clear, sys_locked, PRAM gate): DONE+validated
  (PRAM persistence worked on this build; dbg_coldinit clean: clear_done@2921ms,
  0 unlocks, ROM sum OK).
- FPU datapath: innocent (idle, 84 clean dialogs). The weeks-long "FPU fault"
  chase was mostly this read-path corruption manifesting as phantom F-lines.

## Tooling notes
- Build: bash scripts/build.sh (MacLC-style, PIPESTATUS) run directly as bg task.
- Read focused 5 probes: scripts/read_wedge.tcl (PADR/PSTA/PACT/PFLO/PFST;
  standalone, no PFLA dependency). NOTE: read_wedge.tcl PFST state/max decode is
  wrong (resp_prim [31:16] is right); trust cpu_state.tcl's PFST decode. cpu_state.tcl's
  F-line block needs BOTH PFLO+PFLA so it stays silent on the 5-probe build.
