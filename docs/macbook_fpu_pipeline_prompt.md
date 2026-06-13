# Task: pipeline the mc68881 FPU conversion datapath (sim-first), so it closes timing

You are working in the **LBMacTwo_MiSTer** repo (Macintosh II MiSTer core). Your job is a
**sim-validated VHDL change** to the mc68881 FPU. You do NOT have Quartus/hardware — your
deliverable is a VHDL diff that the `cpu_fpu` Verilator corpus accepts without regression.
A separate session on the Windows/FPGA machine will regen + HW-build + timing-close your diff.

## Why (confirmed diagnosis — don't re-investigate, just fix)

On real Mac II hardware the core intermittently crashes (hangs, "illegal instruction",
"coprocessor not installed", "stack collision", disk/PRAM corruption), clustering on
**application launch** (FPU/SANE-heavy) and rare during Finder navigation (FPU-light).

A Quartus `report_timing` slow-corner audit found the **single root cause**: the FPU
conversion datapath is the ONLY part of the design violating setup timing — **all 500 worst
setup paths are inside `mc68881_top:u_fpu`**, worst slack **−1.633 ns**; the CPU, SDRAM read
path, fetch path, arbiter and DTACK coherency ALL close timing. The failing paths are:
- `operand_reg[*] → fp_reg_file_reg[*]`  (the fp80 conversion → register-file write)
- `cir_dst_reg_idx → exc_event_force_inexact_reg`
- `cir_operand_staging → operand_reg`

Under the slow corner / back-to-back dialogs these latch wrong values → the FPU returns a
corrupted result/state → the CPU consumes it and runs away. The fix is to **break the long
single-edge combinational conversion into pipelined stages** so each closes timing. (No
honest multicycle exists — they are genuine next-edge captures; do NOT touch `LBMacTwo.sdc`.)

## The locus

`rtl/mc68881/vhdl/mc68881_top.vhd`, process `bus_frame_proc` (~lines 2145–2192 and the
MC68882 pending-launch mirror ~2196–2240):

```vhdl
cir_source_val := fp80_from_single(cir_operand_staging(31 downto 0));  -- big comb. conversion
... (CIR_SRC_DOUBLE/EXTENDED/PACKED/LONG/WORD/BYTE cases) ...
operand_reg(1) <= cir_source_val;
operand_reg(0) <= cir_source_val;                       -- monadic
operand_reg(0) <= fp_reg_file_reg(cir_dst_reg_idx);     -- dyadic
```

The `fp80_from_single`/`fp80_from_double`/`packed96_to_fp80_fast` conversions (in
`mc68881_pkg.vhd` / this file ~1241–1330) are deep combinational logic captured in ONE clock
edge from `cir_operand_staging`/`operand_reg` into the next register. Also see the
`cir_move_pending_reg` deferred FMOVE copy (signal ~line 283) and the `operand_reg →
fp_reg_file_reg` move path (`fp_reg_file_reg(dst_idx) <= move_result` ~2925–3077, and
`fp_reg_file_reg(launch_dst_reg_idx_reg) <= result` ~3295).

## The change (approach — adapt as the bench demands)

Insert an intermediate **conversion-stage register** so the flow becomes two edges:
1. Edge 1: `cir_operand_staging`/`operand_reg → [fp80 convert] → conv_stage_reg`
2. Edge 2: `conv_stage_reg → operand_reg` / `→ fp_reg_file_reg`

i.e. register the conversion *output* instead of letting it fan straight into the next
sequential register through the full combinational cone. Add one pipeline cycle of latency
and make the consuming FSM step (the state that reads back the converted operand / advances
the dialog) wait that extra cycle. Functional behavior must be IDENTICAL (same numeric
results, same CIR dialog sequence) — only +1 cycle latency. The `cir_dst_reg_idx →
exc_event_force_inexact_reg` path likely needs the same treatment (register the exception
flag derivation).

Keep both the normal path AND the MC68882 `pending_launch` mirror in sync — they have
identical conversion code.

## Validate (this is the whole point — iterate until clean)

Toolchain per repo `CLAUDE.md`: regenerate Verilog from the VHDL, then build+run the corpus.
On the MacBook you likely have ghdl/yosys/verilator natively (or via the same oss-cad-suite).

1. **Baseline first** (UNMODIFIED tree) so you know what "no regression" means — absolute pass
   counts are noisy due to GHDL-version synth drift:
   ```
   (cd rtl/mc68881 && ./convert_to_verilog.sh)
   (cd SingleStepTests/cpu_fpu && make clean >/dev/null 2>&1 && make)
   (cd SingleStepTests/cpu_fpu && ./obj_dir/Vcpu_fpu_tests cpu_fpu_full_corpus.json | tail -1)
   ```
   Record pass/fail. KNOWN ARTIFACT (do NOT chase): ~70 spurious FSQRT / FCMP+FDBcc / FSAVE
   failures come from GHDL-version drift in the truth tables, not VHDL bugs — hardware is the
   authoritative oracle for those. Note which tests fail at baseline.

2. Make the pipeline change, regen, rebuild, re-run. **Pass criterion:** no NEW failures
   beyond the baseline set — especially the conversion ops: `FMOVE`/`FADD`/`FSUB`/`FMUL`/`FDIV`
   with `.S` / `.D` / `.X` / `.L` / `.W` / `.B` / packed source formats, plus `FSAVE`/`FRESTORE`
   and the CIR dialog tests. If a conversion test newly fails, the FSM read-back cycle is off —
   fix the wait and re-run.

3. Iterate in sim until clean.

## Deliverables

- The final `git diff rtl/mc68881/vhdl/mc68881_top.vhd` (and any `mc68881_pkg.vhd` edits).
- Baseline vs. after corpus numbers + the list of any newly-failing tests (should be none).
- Commit locally with a clear message (do NOT `git push`).
- A one-paragraph summary of the pipeline stage(s) you added and the FSM cycle adjustment, so
  the FPGA-side session can confirm the regen + HW build matches.

## References
- Upstream truth: `../68881-fpga/` (diff before changing FPU constants/state machines).
- Handoff context: `docs/handoff_fpu_pipeline_2026-06-13.md` (this is "the bus_frame_proc
  pipeline beat" it describes).
- Repo build/sim notes: `CLAUDE.md` (WSL section — adapt paths for macOS).
