# Handoff — timing closure: packed-decimal dividers + FSQRT split + honest SDC (2026-07-01)

**Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Question answered:** "are we meeting timing yet?" — **No.** The last build (Jun 16,
`LBMacTwo_795ba3b9_probe_ringwdtack.rbf`) fails clk_sys (31.34 MHz) setup by
**WNS −112.594 ns / TNS −43,632 ns** (restricted Fmax 6.92 MHz), plus −0.507 on the
148.5 MHz HDMI scaler clock. Hold/recovery/removal/min-pulse all clean.
This session fixed the causes in RTL + SDC, board-free. **No build was run here** —
the next build happens on another machine.

## What the census found (Jun-16 db, `scratch/sta_census_jun16db.log`)

55 failing setup endpoints, five classes:

1. **Packed-decimal fast ENCODER** (`fp80_to_packed96_fast`): `mag_n / 10` loop +
   `mag_n mod 10` compiled to **two chained combinational 32-bit lpm_divide arrays**
   (`Mod8`, `Mod9`, ~65 ns each — Quartus does not strength-reduce ÷10). Worst path
   −112.6, ×332 endpoints on `move_packed_encode_reg`. Path anatomy:
   `scratch/sta_cones_jul01.log`.
2. **Packed-decimal fast DECODER** (`packed96_to_fp80_fast`): serial nine-step
   `value_n * 10` chain, fanned through `fp80_from_int` into the FMOVE dispatch —
   collapsed onto `fp_reg_file_reg` (−12.5, **×821**), `result_hi/ex_reg`,
   `conv_fp_src` duplicates (−18.2 ×100).
3. **REAL FSQRT hazard**: divrem `result_reg ← rem_reg` −4.98 ×78. `ST_SQRT_POST`
   did sticky-OR + gradual-underflow shift + rounding + packing in the ONE cycle
   after `rem_reg`'s final `ST_SQRT_ITER` write — the same single-cycle shape as the
   FDIV bug that hard-locked Finder (fixed 6b7062c by `ST_POST_DIV_PRE`). Wrong
   FSQRT results on an unlucky placement.
4. **Bus-paced FPU captures** not in the SDC: `micro_*`, `fp_movem_shadow` ×503,
   `ctrl_move_*`, `result_lo/ex_hi`, exc_event data from `tg68k`/`fpu_wr_hi`
   launches (−0.9…−15.8).
5. **TG68 kernel-internal** (−2.3…−10.3, `regfile→regfile` ×520): honest 2-cycle
   paths — clkena = `phi1` = `clk16_en_p` = `!busPhase[0]` (strictly alternating,
   `addrController_top.v:82`, `tg68k.v:46`); **every** kernel + ALU register process
   is clkena_in/clkena_lw-gated (audited process-by-process; only ungated register
   is `use_VBR_Stackframe`, a static config decode).

## What was changed

### RTL (Quartus reads this VHDL directly via `rtl/mc68881/mc68881.qip`)

- `rtl/mc68881/vhdl/mc68881_top.vhd`
  - `fp80_to_packed96_fast`: divider-free. exp10 = 9 parallel compares vs 10^k;
    MSD = 8 compares vs d·10^exp10 (35-bit unsigned, POW10_N constant mux).
    **Bit-exact vs old loop** (brute-forced 200k boundary values, 0 mismatches).
  - `packed96_to_fp80_fast`: multiplier-chain-free. One 4×31 product
    `lead_digit × POW10_N(k)` + closed-form saturate (`> integer'high` — proven
    equal to the loop's progressive saturation; multiples of 10 can't land in the
    divergence window). Preserves the `exp10 > 9` saturate-even-when-lead=0 quirk.
    **Exhaustive-domain checked, 0 mismatches.**
- `rtl/mc68881/vhdl/mc68881_divrem_unit.vhd`
  - `ST_SQRT_POST` split: cycle 1 normalizes into the (idle-outside-divide)
    `post_*` registers; rounding/packing reuses `ST_POST_DIV_ROUND`.
    `div_sign_reg <= '0'` set at sqrt launch; ROUND's terminal condition now sends
    `FPU_OP_SQRT` to `ST_DONE` (not modrem). No state-enum change (FSAVE frame
    layout `state_t'pos` unchanged). +1 op-internal cycle, invisible through
    busy/done.

### SDC (`LBMacTwo.sdc`, new sections at the bottom, all heavily commented)

- extended the operand-cone `-setup 2` `-from` with `fpu_wr_hi` (2-beat adapter
  first-beat latch, LBMacTwo.sv:782).
- `exc_data_from` += `tg68k`, `fpu_wr_hi`.
- **new** decode-regs → conversion-loci `-setup 2` (`move_cfg*`, `cir_*idx/fmt`,
  `cir_command_reg`, FPctl — the rebuild-stable decode class; deliberately NOT
  loci→loci, the engines iterate).
- **new** bus-capture rule: `tg68k`/`fpu_wr_hi` → `micro_*`, `fp_movem_shadow`,
  `ctrl_move_*`, `result_lo/hi/ex/ex_hi`, `conv_fp_src*` dupes.
- **new** flush-through staging rule: `CIR_XFER_DST` state bit / `operand_reg` /
  `conv_fp_src*` dupes / `tg68k` → `move_exc_*`, `move_packed_encode_reg`,
  `cir_operand_staging`, `conv_fp_src*` (these recompute EVERY edge,
  mc68881_top.vhd:2889; consumers are CPU-paced ≥2 cycles after launch settles).
- **new** TG68 kernel-internal `-setup 2 -hold 1` (the clkena proof above; scope is
  kernel↔kernel ONLY so raw-clk consumers outside keep 1-cycle checks).
- **Deliberately NOT relaxed** (correctness): `cir_response_reg`,
  `exc_event_valid_reg`, `fpsr_reg ← valid`, alu `result_reg ← simple_a_reg`,
  `operand_reg → result_*/fp_reg_file` (deferred copy), `micro_* ← cir_command_reg`
  (captured AT dispatch), `result_lo ← CIR_XFER_DST` (window unproven),
  divrem `quot_reg ← iter_idx_reg` (real iteration path).

## Verified state on the OLD netlist with the new SDC (`scratch/sta_census_newsdc4.log`)

24 endpoints remain, of which everything ≥ −5 ns is one of the RTL-fixed cones
(encode/decode/sqrt — they will disappear with the new netlist). The honest-tight
residue is ~10 endpoints, all ≤ −3.5 ns (fpsr −3.5, micro←cmd −3.4,
result_lo←XFER_DST −3.35, VIA→loci −2.9, ascal ≤ −0.5, …) — placement-recoverable
once the fitter isn't thrashing on a −43 µs TNS swamp. Area also improves: two
lpm_divide arrays deleted, replaced by ~17 comparators + a 4×31 shift-add product.

## Expected next-build outcome + what to check

1. `quartus_sta` summary: clk_sys WNS should collapse from −112.6 to **roughly 0
   to −3 ns** (placement-dependent); TNS from −43,632 to a few hundred ns at worst.
   WNS ≥ 0 is possible but not promised on the first roll.
2. Run `scratch/diag_timing2.tcl` (report-only, ~20 s) and compare against
   `scratch/sta_census_newsdc4.log`'s residue list. New >|−5| ns endpoints = a
   renamed locus to add to the SDC name lists (see SDC header workflow).
3. If stragglers persist across builds: `fpsr_reg ← valid` and
   `micro_*/result_lo` dispatch captures are the next RTL-stage candidates
   (register the `total_cycles` decode / flag gather one edge earlier).
4. HW: boot 7.1.2, then the FDIV/FSQRT-heavy paths (the FDIV Finder lock class).
   FSQRT results now take one extra internal cycle — corpus-validated.

## Validation

- GHDL syntax: clean (`ghdl -a --std=08 -fsynopsys -fexplicit`, all units).
- Encoder/decoder equivalence: brute-force models, 0 mismatches (200k boundary
  values for the encoder incl. every d*10^k +/-2 and the saturate point;
  exhaustive lead x exp10 domain for the decoder).
- FPU corpus A/B (WSL Verilator, stash-based baseline vs after, both with
  OSS-CAD ghdl regeneration): **1261 passed / 59 failed in BOTH runs, failure
  sets byte-identical** (`scratch/fails_base.txt` == `scratch/fails_after.txt`).
  The 59 are the pre-existing OSS-CAD synth-artifact class — none involve the
  changed paths.
- Coverage note: the corpus has **80 FSQRT + 80 FDIV tests, all green in both
  runs** (validates the divrem split and the shared ROUND state), but **zero
  FMOVE.P / packed tests** — the packed encode/decode rewrites rest on the
  brute-force equivalence proof above (they are pure combinational functions;
  no protocol or timing semantics involved). First HW exercise of FMOVE.P will
  be the real-world check, same as it was for the old fallback encoder.

## Build notes for the other machine

- No qsf changes needed; `DBG_WEDGE=1` is ON (user re-enabled it 3e4f41b for SCSI
  probing) — it costs some timing headroom; the shippable config strips it.
- Quartus reads the FPU VHDL directly — no `.v` regeneration needed for the RBF.
  (`.v` regen is only for the Verilator bench; done here for the corpus A/B.)
- Confirm the RBF md5 CHANGED after the build (memory: incremental-compile gotcha).
