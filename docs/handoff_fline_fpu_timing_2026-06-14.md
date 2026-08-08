# Handoff — F-line bomb = FPU conversion-datapath TIMING; HW probe is runtime-blind

**Date:** 2026-06-14 (session 2) · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Supersedes the active thread of** `docs/handoff_probe_fix_2026-06-14.md` (that doc's Task A/B are now
re-scoped below). **Read the memory `project_residual_read_corruption.md` for the read-leak lineage.**

## TL;DR — what this session established (the pivot)

1. **The JTAG IF-ring/recorder probe is BLIND to runtime crashes.** Two more probe iterations
   (round-1 `62f39bbf`, round-2 `4db7a3f5`) both froze at early boot. Root cause: the ring, the
   vector recorder, *and* the coherency detector all key off the **SDRAM slot-owned handshake**
   (`rd_latch`/`cpu_rd_take`), which stops engaging once the boot ROM switches to **turbo**. So every
   runtime read shows the same stuck `0x4080377x` ring + `count=0` + `raw_leaks=0`. **`raw_leaks=0` is
   NOT trustworthy for a runtime crash.** → Stop iterating the JTAG probe for runtime bugs.
2. **Three DISTINCT crashes (do not conflate):**
   - **Sad Mac** (core-reload 1st boot): early-boot illegal/bus-error. **Won't reproduce on `4db7a3f5`
     across ~20 warm+cold reboots** → timing-lottery; this build's placement dodges it. Parked.
   - **F-line bomb** (launch *any* app, e.g. TeachText): **FPU `FRESTORE` bomb.** Confirmed via
     `PFST`: `max_seen=RESTORE_FRAME(19)`, `frame_seen=1`, `resp_prim=0x0900` (= `CIR_PRIM_NULL`
     release, [mc68881_pkg.vhd:348](../rtl/mc68881/vhdl/mc68881_pkg.vhd) — FSM *completed* the
     restore). Reproducible. **This is the focus.**
   - **256-color illegal** (switch to 8bpp/256 colors in 7.1, *intermittent*): 8bpp video-switch /
     write-path / timing. Distinct from the FPU. Separate track (below).
3. **The F-line is a TIMING bug, not logic.** The Verilator FPU bench (ideal-timing, committed `.v`)
   passes the whole restore path: `save_restore 8/8`, `double_saverestore 3/3`,
   `fline_trap_regression 24/24`. (Full corpus `1102/1320`; the 218 fails are the known
   `FMOVEM.X`/`FSQRT` backlog, unrelated.) So the logic is correct — the hardware bomb is the FPU
   conversion datapath **failing setup timing** on real silicon.

## Current state (READ before touching)

- **Deployed RBF: `4db7a3f5`** in `/media/fat/_Unstable/LBMacTwo.rbf` (round-2 probe build). Boots
  reliably (20/20). Its source is now committed (HEAD `24917df`) — rebuild from there to reproduce it.
- **HEAD = `24917df`** (this session) "dbg+osd: IF-ring round-2 (runtime-blind, shelved) + OSD 1MB
  removal", on top of `5eaa86b` (the committed **read-leak fix**: `cpu_rd_take` gate `LBMacTwo.sv`
  ~918, `dataController_top.sv:218,228`, `sdram.v` `dout_addr`, + the initial IF-ring). `24917df` adds:
  - `rtl/dbg_wedge.sv` — IF-ring **round-1** (`rd_word` capture; asymmetric illegal/F-line freeze)
    **+ round-2** (`rd_latch && cpu_rd_take` capture edge; fault-vector recorder PRGR src 13/14/15).
    **All proven runtime-blind — committed for reference, but the JTAG-probe approach is shelved.**
  - `scripts/cpu_state.tcl` — `VEC-RECORDER` decode + `IF-FAULT` always-dump hack.
  - `LBMacTwo.sv` — **OSD "Memory" 1MB removal** (line 227 `"O45,Memory,2MB,4MB,8MB;"`; line 693
    `configRAMSize` remap 0→2MB/1→4MB/2→8MB).
- **⚠️ The OSD 1MB removal is committed but NOT in any built RBF yet** — it rides along on the next
  build (the deployed `4db7a3f5` predates it).
- **Still uncommitted/untracked:** this handoff + `docs/handoff_probe_fix_2026-06-14.md` (prior,
  superseded); `scratch/{wp,fpu_fail,fpu_path}.tcl` (gitignored timing queries); `cr_ie_info.json` +
  `scripts/__pycache__/` (pre-existing junk — leave them).
- **SHARED BOARD:** DE10 shared with MacLC sessions. Deploy = `scp` only; never `/api/launch`
  (reload) — the user loads the core. One agent on HW at a time; no ssh polling loops.

## The F-line fix — FPU conversion-datapath timing closure (the main task)

**Scoped failing FPU setup cones** (`bash` + `quartus_sta -t scratch/fpu_fail.tcl` — FPU-only,
grouped by endpoint register; ≤500 paths, NOT the 6000-path firehose):

| Cone | Slack | Worst-path startpoint | Role |
|---|---|---|---|
| `move_packed_encode_reg` | −140.9 | `conv_fp_src` cone | FMOVE.P BCD encode — **NOT the F-line** (rare op; the lottery driver) |
| `move_exc_double_rt_pre_reg` | −12.9 | `cir_state_reg.CIR_XFER_DST` | FMOVE.D exception round-trip |
| `conv_fp_src` | −12.6 | `operand_reg` | **F-line target** (operand convert) |
| `micro_remaining_reg` | −11.0 | — | microcode counter |
| `cir_conv_src_reg` | −10.9 | `cir_operand_staging` | **F-line target** (CPU→FPU operand convert) |
| `move_exc_double_ovfl_reg` | −9.8 | — | FMOVE.D overflow |

(startpoints from `quartus_sta -t scratch/fpu_path.tcl`.)

**Why they fail:** the worst-path **startpoints aren't in the `-setup 7` `fpu_dp_from` set** in
[LBMacTwo.sdc](../LBMacTwo.sdc) (lines 80-117) — `conv_fp_src`, `cir_operand_staging`, `cir_state_reg`
are not listed. The design already pre-stages the converter *outputs* (rounds 1-3:
`move_packed_encode_reg`, `move_exc_*_rt_pre_reg`, `cir_conv_src_reg` are registers, see
[mc68881_top.vhd:378-418](../rtl/mc68881/vhdl/mc68881_top.vhd) + 2853-2918) — so the −140/−13/−11 ns is
the **converter combinational logic** (`fp80_to_packed96_fast`, `fp80_from_*`) sitting *between*
`conv_fp_src`/operand and those registers. Registering `conv_fp_src` would NOT split it.

**The F-line targets = the operand-conversion cones** `cir_conv_src_reg ← cir_operand_staging` and
`conv_fp_src ← operand_reg` — exactly the CPU→FPU operand path an `FRESTORE` runs through. Small
(−11 to −13 ns), so closeable.

**Two fix avenues:**
- **(A) Extend the multicycle `-from` sets** to cover those startpoints — SDC-only, cheap — **only if
  the source is provably stable across the window.** ⚠️ RISK: this is the exact "relaxation" that
  killed boot once (`c8e8c9ad`, see the SDC comments), and a multicycle that *lies* about stability
  could itself BE the intermittent F-line. **Do NOT do this blind.**
- **(B) RECOMMENDED — FSM-aware RTL pipeline beat** on the operand-conversion path: register the
  `fp80_from_*` conversion into `cir_conv_src_reg` as a 2-stage cone and make the CIR FSM
  (`cir_dialog_proc` `CIR_XFER_DST`/`CIR_XFER_SRC_WAIT`, `bus_frame_proc`) wait the extra cycle.
  +1 cycle latency, functionally identical. **Gate every step on the save/restore corpus** (must stay
  8/8 + 3/3 + 24/24) before any rebuild. `move_packed_encode` (−140, FMOVE.P) is a *separate, harder*
  problem (genuine converter-internal pipelining) — leave it unless FMOVE.P matters.

**Step plan for (B):** ① read `cir_conv_src_reg` consumers + the CIR FSM consume timing
([mc68881_top.vhd:2200-2282](../rtl/mc68881/vhdl/mc68881_top.vhd) `cir_conv_src_reg` assigns +
`operand_reg` writes); ② add the pre-stage register + FSM wait; ③ `convert_to_verilog.sh` (OSS-CAD)
then run save/restore + full corpus, confirm no regression vs this baseline; ④ `quartus_sta -t
scratch/fpu_fail.tcl` to confirm the conv cones closed; ⑤ `bash scripts/build.sh`, deploy, HW-retest
the TeachText F-line.

## Procedures

- **FPU sim (board-free, WSL — all confirmed working this session):**
  - Convert VHDL→Verilog *only after editing the FPU VHDL*: `wsl -d Ubuntu-24.04 -e bash -lc 'export
    PATH=$HOME/oss-cad-suite/bin:$PATH; cd rtl/mc68881 && ./convert_to_verilog.sh'`.
  - Build+run bench: `wsl -e bash -lc 'cd SingleStepTests/cpu_fpu && make clean >/dev/null && make'`
    then `./obj_dir/Vcpu_fpu_tests <corpus>.json | tail`. Corpora: `save_restore_corpus.json`,
    `double_saverestore_corpus.json`, `fline_trap_regression.json`, `cpu_fpu_full_corpus.json`.
  - ⚠️ **GHDL drift:** committed `.v` is apt-ghdl; OSS-CAD ghdl emits ~70 spurious FSAVE/FSQRT/FCMP
    "fails" (synth artifacts). **Judge by relative before/after on the same toolchain**, never
    absolute counts. HW is the authoritative oracle.
- **Timing queries (board-free):** `export PATH=/c/intelFPGA_lite/17.0/quartus/bin64:$PATH; quartus_sta
  -t scratch/<x>.tcl`. `wp.tcl` = worst path + IF-ring timing gate; `fpu_fail.tcl` = scoped failing FPU
  cones (grouped, capped); `fpu_path.tcl` = from/to per cone. **Keep timing queries FPU-scoped + capped
  — the full failing-path list is 6000+.**
- **Build/deploy:** `bash scripts/build.sh` (background, ~20 min, confirm md5 changed + `wp.tcl` worst
  path still the boot-irrelevant `move_packed_encode` cone + no `ifr_/ifp_/prgr` setup fail). Deploy:
  `scp` RBF → `_Unstable` (host/creds in `scripts/local.env`; no reload). Probe read (if ever needed):
  `bash scripts/read_probes.sh`. Screenshot: `bash scratch/cir_bisect/shot.sh`.

## Parked / re-scoped (do not lose)

- **Task B (read-leak validation) is now UNRELIABLE** as written: the coherency detector is
  runtime-blind (turbo), so `raw_leaks=0` after a warm-reboot stress run does NOT prove the fix. The
  read-leak fix stays committed (`5eaa86b`) but **still unvalidated**; revalidation needs a
  turbo-proof detector or a different method. Don't claim it validated on `raw_leaks=0`.
- **256-color illegal (NEW lead)** — switching 7.1 to 256 colors (8bpp) intermittently throws an
  illegal instruction. Distinct from the FPU. Read-coherency NOT confirmed clean (probe blind).
  Leading suspects: MDC824 8bpp path / the un-gated write DTACK (`LBMacTwo.sv:873`). Start with
  board-free RTL recon of the depth-switch + write path. (User switches to 256 colors every boot
  because PRAM doesn't persist video depth — a parked feature item.)
- **Sad Mac** — not reproducing on `4db7a3f5`; revisit only if a future build resurfaces it. Confirm
  the user was doing real **core reloads** (RBF re-select), not Mac restarts, if it's chased again.
- **OSD 1MB removal** — staged in `LBMacTwo.sv` (uncommitted), needs the next build to take effect.
- **Hardware runtime-crash capture** — if ever needed, requires a turbo-proof (DTACK-based) ring +
  a VBR tap or TG68 `trap_1111` exposure (`TG68KdotC_Kernel.vhd`); invasive, deferred.

## Key files

- `rtl/mc68881/vhdl/mc68881_top.vhd` — FPU CIR FSM + conversion datapath. `conv_fp_src` (108, comb @
  1906), `cir_conv_src_reg` (302, assigns 2212-2243, consume 2277-2282), pre-stage regs + rationale
  (378-418), `bus_frame_proc` (2038) move-exc/packed stage (2853-2918), `RESTORE_FRAME` frame consume
  (4082-4112).
- `rtl/mc68881/vhdl/mc68881_pkg.vhd` — `CIR_PRIM_NULL=0x0900` (348); converter functions.
- `LBMacTwo.sdc` — FPU multicycle (80-158): `fpu_dp_from`/`fpu_dp_to` + `-setup 7` (116), `-setup 2`s
  (125-141). **Read the comments before touching; over-relaxation killed boot (`c8e8c9ad`).**
- `scratch/{fpu_fail,fpu_path,wp}.tcl` — the timing queries used this session.
- `rtl/dbg_wedge.sv` + `scripts/cpu_state.tcl` — the (runtime-blind) probe; reference only.
