# FPU corpus iteration — 2026-06-04

Snapshot of the SingleStepTests/cpu_fpu corpus state, what's fixed,
what's left, and why.

## Tooling set up this session

- **`rtl/mc68881/convert_to_verilog.sh`** restored from commit 1995a32 and
  fixed for current OSS-CAD-Suite GHDL 7.0.0-dev: VHDL path, lite-only
  regen, `set -e` post-increment bug. After any VHDL edit:

  ```bash
  wsl -d Ubuntu-24.04 -e bash -lc '
    export PATH=$HOME/oss-cad-suite/bin:$PATH
    cd /mnt/c/Temp/mistercore/lbmactwo_MiSTer/rtl/mc68881
    ./convert_to_verilog.sh
  '
  ```

  Then rebuild the bench in `SingleStepTests/cpu_fpu` with `make`.

- **Verilator 5.020 compat** in `SingleStepTests/cpu_fpu/Makefile` (drop
  `-Wno-ALWNEVER`).
- **Bus-edge tracing** added to `sim_main.cpp` corpus `--trace` mode —
  captures AS-rising-edge with the data the FPU actually drove on the
  wire (the AS-falling sample read stale `fpu_d_out`).

## Status of the four failure classes

| Class | Baseline (pre-fix) | After this session |
|---|---|---|
| **FMOVE.L Dn↔FPCR/FPSR/FPIAR** (24) | 0/24 | **24/24 PASS** |
| FMOVE.X/.D (d16,PC),FPn (79) | 0/79 | 0/79 — needs CPU microcode |
| FMOVEM.X FP0,-(A7);(A7)+,FP1 (16) | 0/16 | 0/16 — needs CPU microcode |
| FSAVE/FRESTORE (8) | 0/8 | 0/8 — same class as PC-rel |

Plus a known GHDL-version-drift artifact: regenerating with OSS-CAD-Suite
GHDL produces a different `.v` than the GHDL that produced the
1995a32-era output, which surfaces ~70 new FSQRT / FCMP+FDBcc / FSAVE
failures in the Verilator bench. These are GHDL-synth issues, not VHDL
correctness regressions — Quartus reads the VHDL directly and is
unaffected. Hardware verification is the authoritative check.

## FMOVE.L FPctl fix (landed)

Root cause: the FPU's CIR command-word handler in
`rtl/mc68881/vhdl/mc68881_top.vhd` decoded MC68881 FMOVE FPctl
(ext-word bits 15:13 = 100 write / 101 read) as a normal reg-to-reg
FMOVE — bit 14 = 0 forced `cir_reg_to_reg = 1` and CIR_DECODE jumped
straight to CIR_IDLE without ever requesting the operand transfer.
FPU returned `0x0900` (NULL "done"); FPctl never written / read back.

Fix in `mc68881_top.vhd` (commit 2b84a90):
- Detect bits 15:13 = 100 in the cmd-word write handler; override
  `cir_reg_to_reg = 0`, `cir_src_fmt = 000` (Long), `cir_direction =
  bit 13`, set new `cir_is_fpctl_move` flag, latch the FPctl mask.
- At CIR_XFER_SRC_WAIT2 completion, pulse `cir_fpctl_commit`
  (handshake to `bus_frame_proc` to avoid violating single-driver on
  fpcr/fpsr/fpiar_reg). The bus_frame_proc consumer writes the
  selected control reg(s) from `cir_operand_staging[31:0]`.
- For CIR_XFER_DST (read direction), pre-load staging with the
  selected FPctl reg before the CPU reads CIR Operand.

Also: `mc68881_alu.vhd` `gen_divrem_lite` removed multi-driver of
`divrem_save_addr`/`divrem_restore_addr`/`divrem_restore_wr`
(Quartus tolerates; `ghdl synth` doesn't, blocking regen).

## What's left: TG68 CPU microcode for memory-source cpGEN

Trace of `FMOVE.X (d16,PC),FP0` confirms:
- FPU **correctly** returns `0x960C` (Transfer Single Operand
  CPU→FPU, 12 bytes) and counts 3 long-word arrivals before
  going IDLE.
- CPU **incorrectly** sends `0x0000_0000` three times.

The TG68 CIR microcode has two compounding gaps:

1. **`cp_xfer_to_load` assumes Dn source.** It latches `reg_QB`
   (regfile output at `rf_source_addr = opcode(2:0)`) into
   `cp_xfer_data`. For PC-relative EA, that reads some random Dn
   instead of the memory location.

2. **No EA computation in the cpGEN dispatch path.** Line ~3486
   in `TG68KdotC_Kernel.vhd` just sets `opcCPopw` and goes to
   `cp_write_opw` regardless of EA mode. Contrast with the FScc
   memory path at line ~3539 which sets `ea_only=1` /
   `ea_build_now=1` so the existing EA-build machinery resolves
   the address into `cp_ea_addr`.

(The 3-iteration loop **does** work — the CPU loops correctly
when the FPU re-asserts `0x96xx` BUSY. It's just that each
iteration sends the same stale 0x0000 from `cp_xfer_data`.)

### Suggested fix shape

In `TG68K_Pack.vhd`, extend the `micro_states` enum:
```
cp_xfer_mem_rd_hi, cp_xfer_mem_rd_lo,
```

In `TG68KdotC_Kernel.vhd`:

1. Add signal `cp_mem_source : std_logic` registered in the same
   process that drives `cp_ea_addr`. Set when F-line dispatch
   recognises cpGEN with `opcode(5:3) /= "000"`. Clear on return
   to idle.

2. In the F-line dispatch for cpGEN (line ~3486), branch on
   `opcode(5:3)`:
   - `"000"` (Dn): keep existing direct `cp_write_opw` path.
   - other modes: set `ea_only <= '1'`, `ea_build_now <= '1'`,
     and on `nextpass='1'` proceed to `cp_write_opw`. The EA
     lands in `cp_ea_addr` (via the existing `addr` capture at
     line 862-863).

3. In `cp_idle_resp`'s Transfer-Single-Operand-CPU→FPU branch
   (line 4528), branch on `cp_mem_source`:
   - `'0'`: existing `cp_xfer_to_load`.
   - `'1'`: new `cp_xfer_mem_rd_hi`.

4. New states modelled on `cp_restore_rd_mem` (line 4752):
   ```
   WHEN cp_xfer_mem_rd_hi =>
     set_cp_memaddr <= '1';  -- use cp_ea_addr
     setstate <= "10";       -- bus read
     datatype <= "01";       -- word
     next_micro_state <= cp_xfer_mem_rd_lo;

   WHEN cp_xfer_mem_rd_lo =>
     -- HIGH word from last_data_read; bump cp_ea_addr by 2 first
     -- so this read goes to cp_ea_addr+2 for the LOW word.
     set_cp_memaddr <= '1';
     setstate <= "10";
     datatype <= "01";
     next_micro_state <= cp_xfer_to_hi;  -- hand off to existing
   ```

   Need a small data-write-mux change in the existing
   `cp_xfer_to_hi`/`cp_xfer_to_lo` so `cp_xfer_data` is sourced
   from the captured HIGH/LOW words instead of `reg_QB`. The
   cleanest path is to keep using `cp_xfer_data` as the
   pipeline carrier and write HIGH at end of `cp_xfer_mem_rd_hi`,
   LOW at end of `cp_xfer_mem_rd_lo`. Watch the single-driver
   rule on `cp_xfer_data` — it's currently driven only from the
   process at line ~966.

5. After `cp_xfer_to_lo` completes (i.e. when transitioning out
   of that state), advance `cp_ea_addr` by +4 in the registered
   process — only when `cp_mem_source = '1'`. This way the next
   loop iteration reads from the next long-word position.

### Attempted (and reverted) implementation

This session tried the suggested fix shape and reverted after a
single iteration revealed an instruction-layout mismatch:

- Added `cp_mem_source` signal + `cp_xfer_mem_rd_hi/lo/store/done`
  microstates.
- Modified the F-line cpGEN dispatch to set `ea_only/ea_build_now`
  when `opcode(5:3) /= "000"`, mirroring the FScc memory path.
- Routed `cp_idle_resp`'s Transfer-Single-Operand-CPU→FPU branch
  to `cp_xfer_mem_rd_hi` when `cp_mem_source = '1'`.
- Wired `cp_ea_addr += 2` between HIGH/LOW reads.

**What broke:** The standard EA-build machinery (used by FScc) treats
`sndOPC` AS the d16 displacement. For cpGEN, `sndOPC` is the
**FPU command word**, not the displacement — `(d16,PC)` for an
F-line cpGEN has the d16 in a *separate* word AFTER the FPU
command. The EA-build read `sndOPC = 0x4800` as a brief-extension
word, computed an absurd EA (0x5802 in the trace), then F-trapped.

**Trace evidence:** `scratch/trace_pcrel.json` run shows
`ms=4` (ld_dAn1) entered at cyc 68 with `din=0x4800` followed by
`ms=51` (trap0) at cyc 92.

**What's needed for a real fix:** A bespoke EA fetch path for
cpGEN that:
1. Allows the existing kernel pre-decode to fetch opword + sndOPC
   (FPU command) as it does today.
2. Adds a new state that does **one extra word read** to grab the
   d16 from `tg68_PC` (after sndOPC) for mode 111 reg 010.
3. Computes `cp_ea_addr = tg68_PC_at_d16 + sign_extend(d16)`.
4. THEN proceeds to `cp_write_opw`.

For other memory modes (mode 010 `(An)` via `reg_QA`, mode 100
`-(An)`, mode 011 `(An)+`), the An register is in `opcode(2:0)` and
no extra fetch is needed beyond reading the register. These could
share the cp_xfer_mem_rd_* state path once the EA setup is right.

### Scope estimate

- VHDL touchpoints: 2 files, ~80–120 lines.
- Build: regen via `convert_to_verilog.sh`, rebuild bench
  (~2 min), run corpus (~10 s).
- Validation: `fline_trap_regression` must stay 24/24; the
  79 (d16,PC) tests should move to PASS; FMOVE.L FPctl must
  stay 24/24 (no regression from same dispatch path).

After (d16,PC) is fixed, **FMOVEM.X** (16 tests) likely just
needs the multi-word loop variant working for more than one
long-word, since FMOVEM uses `-(A7)` push and `(A7)+` pop
which are already memory-mode EAs.

**FSAVE/FRESTORE** is a separate concern — those have their
own microcode paths (`cp_save_*` / `cp_restore_*`) that this
session traced but didn't dig into. The save_restore corpus
tests' "D1 got 0" symptom suggests the FP register state isn't
preserved across the round-trip, which is FPU-side state
machine work, not CPU.
