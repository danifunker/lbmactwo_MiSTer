# FPU instruction coverage (LBMacTwo mc68881)

**What this core's FPU implements in hardware, what it traps, and why.**

The DE10-Nano's Cyclone V (5CSEBA6, 4191 LABs) **cannot fit a complete hardware
68881** — measured 2026-06-15, the full build needs **5385 LABs (28% over)**, and
the transcendental (`mc68881_trig_unit`) block alone is **~17,633 ALUTs (~69% of
the overage)**. So the FPU ships as a **68040-class hardware subset**: the common
ops in silicon, the expensive/rare ones trapped.

This is the same split a real **MC68040** uses (hardware subset + a software FPSP
for the rest). On a real Mac II the OS assumes a *complete* 68881 and ships **no
FPSP**, so a trapped op becomes a vector-11 "bad F-Line" bomb. We therefore put
**as much as fits** in hardware to minimize what can trap.

## Build configuration

`rtl/mc68881/vhdl/mc68881_fpu_lite.vhd` sets the tier via two generics on
`mc68881_top`:

| Generic | Value | Effect |
|---|---|---|
| `fpu_lite_g` | `true` | base lite subset; **keeps the trig unit OUT** (doesn't fit) |
| `enable_divrem_g` | `true` | adds the **divrem + sgl_ops** hardware units |
| `packed_decimal_full_g` | `false` | fast packed path (full BCD engine violates timing; FMOVE.P is rare) |

Setting `fpu_lite_g=false` would enable the full 68881 (incl. trig) — **but it
does not fit** (see above). There is intentionally no way to fit trig on this
device.

## Coverage table

✅ = hardware · ⛔ = F-line trap (no handler on Mac II → bomb if executed)

| Instruction(s) | 68881 | 68040 HW | lite (old) | **lite + divrem (this build)** |
|---|:--:|:--:|:--:|:--:|
| FADD FSUB FMUL | ✅ | ✅ | ✅ | ✅ |
| FABS FNEG FCMP FTST | ✅ | ✅ | ✅ | ✅ |
| FMOVE FMOVEM FMOVECR | ✅ | ✅ | ✅ | ✅ |
| FINT FINTRZ | ✅ | ✅ | ✅ | ✅ |
| **FDIV FSQRT** | ✅ | ✅ | ⛔ | **✅** |
| FMOD FREM FSCALE | ✅ | ⚙️FPSP | ⛔ | **✅** |
| FSGLDIV FSGLMUL | ✅ | ⚙️FPSP | ⛔ | **✅** |
| FGETEXP FGETMAN | ✅ | ⚙️FPSP | ⛔ | ⛔ |
| **Transcendentals** — FSIN FCOS FTAN FSINCOS, FASIN FACOS FATAN FATANH, FSINH FCOSH FTANH, FETOX FETOXM1 FTWOTOX FTENTOX, FLOGN FLOGNP1 FLOG10 FLOG2 | ✅ | ⚙️FPSP | ⛔ | ⛔ |

⚙️FPSP = the 68040 traps these to its software package; a real 68040 Mac runs
them via the FPSP that ships in its System.

## What still traps on this build (the gaps)

These F-line-trap (`op_disabled_by_lite` in `mc68881_top.vhd`). With no FPSP on
the Mac II, an app that executes one **inline** will bomb:

1. **Transcendentals** (the 19 ops above). The `mc68881_trig_unit` is too big to
   fit. **Practical impact: low** — the OS, Finder, and most apps reach
   transcendentals through **SANE's software routines**, not inline 68881
   `FSIN`/`FLOGN`. Mainly FPU-optimized scientific/graphics apps inline them.
2. **FGETEXP / FGETMAN**. Small ops on the `fpu_lite`-gated "simple" path; left
   disabled for now (would need their own enable). Rarely used directly.

## Closing the gaps later (optional)

The only complete-coverage routes, none of which is in scope here:

- **A 68040-style partial FPSP** — a custom vector-11 handler that emulates *just*
  the trapped ops, syncing FPU state via FSAVE/FRESTORE. (The stock 68040 FPSP
  checks for a 68040 CPU and won't load on this 68020-class core.) NOT the
  "all-software" route (rejected): hardware still does the bulk.
- **Re-enable `FGETEXP`/`FGETMAN`** in hardware — cheap, if a real app needs them;
  add a simple-path enable analogous to `enable_divrem`.
- **Trig in hardware** — impossible on this device (capacity).

## History / rationale

- `2ffd682` (2026-05-22) cut divrem to fit Cyclone V → FDIV/FSQRT started
  trapping → the "Finder bad F-Line" bomb on app launch (an inline FDIV with no
  FPSP). Root-caused 2026-06-15; see `docs/handoff_fline_timing_census_2026-06-14.md`.
- `enable_divrem_g` (2026-06-15) restores FDIV/FSQRT/FMOD/FREM/FSCALE/SGLDIV/SGLMUL
  in hardware while keeping trig out — fixing the bomb within the fit budget.
