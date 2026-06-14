# Handoff — ASC sound-FIFO hang (Prince of Persia, System 6.0.8) — PARKED

**Date:** 2026-06-13 · **Branch:** `7-1-2-boot-working` · **Repo:** `C:\Temp\mistercore\lbmactwo_MiSTer`
**Status:** **PARKED** by user request after first-pass analysis. Capture this, resume later.
**Sibling thread (do not conflate):** the SDRAM read-path corruption hunt —
docs/handoff_sdram_fix_residual_2026-06-13.md and the in-progress coherency-detector probe.
**This is a DIFFERENT, independent bug** (the ASC, a peripheral; not the SDRAM read path).

## TL;DR

Prince of Persia on 6.0.8 boots and runs fine (title screen renders perfectly), then **hangs
the moment it plays sound**. The CPU is **livelocked** in a tight loop in the game/sound-driver
code, **polling the ASC FIFO-IRQ-status register (`$50F14804`) for a status bit that never
asserts**, while it streams samples into FIFO A (`$50F14000`). Root cause is in `rtl/asc.sv`'s
FIFO status/drain logic, **not** the read-path corruption. Not yet pinned to a single line; the
decisive next step is to capture *which* `$804` bit the driver is waiting on.

## Symptom & repro

- **Build deployed:** the IF-ring probe build (`25f57ad8`, `DBG_WEDGE=1`). The bug is the core's,
  not the probe's — it's a peripheral handshake, unaffected by the debug probes.
- **Repro:** boot System 6.0.8 (the user's hand-test; not the default `.s0`), launch Prince of
  Persia, let it reach the title screen with music/sound. It hangs during sound playback.
- **Screen:** clean PoP title screen, **frozen** (graphics pristine — rules out video/framebuffer
  corruption). Screenshot: `scratch/fline_capture/pop_crash_213523.png` (gitignored scratch).

## Hardware evidence (JTAG probes, `bash scripts/read_probes.sh`)

CPU state across 6 samples (~440k bus cycles apart), `AS_cycles` **incrementing** (561.9M→564.3M)
⇒ a **livelock** (tight loop), not a halt:

| sample | cpuAddr | FC | notes |
|--------|---------|----|-------|
| 1 | `0x0078A57E` | 6 (prog) | selRAM — loop body |
| 2 | `0x50F14804` | 5 (data) | **ASC + $804 = FIFO_IRQ_STATUS read** |
| 3 | `0x0078A576` | 6 | selRAM — loop body |
| 4 | `0x0078A574` | 5 | selRAM |
| 5 | `0x50F14000` | — | **ASC + $000 = FIFO A data (sample write)** |
| 6 | `0x0078A57A` | 6 | selRAM — loop body |

The CPU oscillates in `0x0078A574..0x0078A57E` (a ~10-byte loop, RAM = game/driver code loaded
from disk) and touches the ASC: **writes FIFO A** (`$50F14000`) and **reads FIFO-IRQ status**
(`$50F14804`). Classic "fill the FIFO, poll status, never get the expected flag → spin forever."

- `rtl/asc.sv:3` confirms ASC address space = **`$50F14000–$50F15FFF`**.
- IF-ring was frozen on the `0x0000C0Cx illegal(4)` **decoy** (see sibling handoff) — irrelevant here.
- FPU FSM idle the whole time — not involved.

## Why this is NOT the read-path corruption

- ASC registers are read via `selectASC` (peripheral path), **not** `selectRAM/ROM` → the
  `cpu_data`/`sdram_slot_cpu_rd` neighbor-word mechanism cannot touch them.
- Graphics are clean; the loop is *coherent* (sensible fill/poll), not a runaway into garbage.
- It's a **runtime** hang under heavy sound use, vs the read-corruption which clusters at boot.
  Consistent with the user's "stable once booted" — this is a sound-subsystem-specific defect.

## Code analysis — `rtl/asc.sv` (the suspect logic)

Register map (offset within `$50F14000`): `$000-$3FF` FIFO A, `$400-$7FF` FIFO B, `$800+` regs.
- `$801 asc_mode` (asc.sv:64): 0=off, **1=FIFO**, 2=wavetable.
- `$804 asc_fifo_irq` (asc.sv:67): FIFO IRQ status, **read-clears** (asc.sv:191 read, 362-363 clear).
- `irq_n = ~(|asc_fifo_irq)` (asc.sv:124) → VIA2 CB1.

**FIFO playback engine** (asc.sv:444-465), runs only when `asc_mode==1 && sample_tick`
(`sample_tick` ≈ every 1408 `clk_sys` at 22 kHz, asc.sv:99-103):
```verilog
if (asc_mode == 8'h01 && sample_tick) begin
    if (fifo_a_count > 0) begin ... fifo_a_count <= fifo_a_count - 1'd1; end   // drain 1/tick
    ...
    // Per-channel FIFO IRQ status (Snow/MAME layout):
    if (fifo_a_count == 11'd512) asc_fifo_irq[0] <= 1'b1;   // A half-empty  <-- EXACT-EQUALITY
    if (fifo_a_count == 11'd1)   asc_fifo_irq[1] <= 1'b1;   // A empty       <-- EXACT-EQUALITY
    if (ctrl_stereo && fifo_b_count == 11'd512) asc_fifo_irq[2] <= 1'b1;
    if (ctrl_stereo && fifo_b_count == 11'd1)   asc_fifo_irq[3] <= 1'b1;
end
```

### Leads (ranked; none yet confirmed as THE cause — needs the driver's poll condition)

1. **Exact-equality status flags** (asc.sv:461-464). Real ASC flags on a *level*
   (`count <= half`), not `count == 512`. The flag asserts for the single tick where count is
   *exactly* 512 (or 1), then is read-cleared. If the driver's poll/read-clear cadence misses that
   one tick, or if count skips the value (see #3), the awaited bit may effectively never be seen as
   set when polled. **Fix candidate:** level semantics + the right empty point (`==0`, not `==1`).
2. **FIFO not draining at all.** The drain is gated on `asc_mode == 8'h01`. If the driver expects
   FIFO playback but `asc_mode` isn't 1 at that moment (mode-write path asc.sv:386-399 resets the
   FIFO on a mode *change*; verify the value actually latched to 1), `fifo_a_count` stays at its
   filled value and neither flag ever sets → permanent spin. **Verify `asc_mode==1` live.**
3. **Simultaneous CPU-write + drain race** (asc.sv:373-375 vs 446-449). Both assign
   `fifo_a_count` in the same `always @(posedge clk)` block; the later (drain, −1) wins, so a
   coincident FIFO-A write **loses its +1** while `fifo_a_wr_ptr` still advances → count/ptr
   **desync**. Rare (CPU writes are sparse vs the 1408-clk tick) but it drifts `count`, which can
   make it skip the exact 512/1 thresholds in #1. **Fix candidate:** combine write/drain into one
   net `±` update of `fifo_a_count`.
4. **Driver may poll a bit this ASC doesn't implement** (e.g. a FIFO-full / FIFO-not-full status).
   `asc_fifo_irq` only has half-empty/empty bits. If PoP's driver throttles writes on a "full"
   status this core never provides, it spins. **Confirm against the real ASC $804 bit definitions.**

## Next steps to RESUME

1. **Pin the poll condition.** The loop is at `0x0078A574..0x0078A57E` in RAM (game code) and the
   wait is on `$50F14804`. Either:
   - dump that RAM window (need a memory-read path — none in the current probe) and disassemble it
     (capstone m68k-020, see `scripts/loop_disasm.py`) to see exactly which `$804` bit + polarity it
     waits on; **or**
   - add a small **ASC-trace probe**: latch `{addr[12:0], data, rw, asc_mode, fifo_a_count,
     asc_fifo_irq}` on each `selectASC` access into a ring → read it via JTAG to watch the
     fill/poll/drain handshake live. (Cheaper to reason about than a RAM dump.)
2. **Cross-check `asc.sv` against the references:** Snow's ASC model (the project's audio oracle —
   see memory `reference_snow_emulator_oracle`, source at `C:\Temp\mistercore\snow`) and MAME's
   `asc.cpp`. Confirm the real `$804` bit layout, the half-/empty thresholds (level vs exact), and
   the FIFO-full semantics.
3. **Apply the most-likely fix** (level-threshold flags + write/drain count merge), rebuild, retest
   PoP. Sound regression-test a couple of other 6.0.8/7.x apps that use sampled sound.

## Pointers

- RTL: `rtl/asc.sv` (engine), instantiated + `selectASC` decode in `LBMacTwo.sv`
  (asc.sv data mux at `rtl/dataController_top.sv:219`), decode in `rtl/addrDecoder.v:185,311`.
- Build/deploy/probe procedures: see docs/handoff_sdram_fix_residual_2026-06-13.md “MiSTer / procedures”.
- The read-path corruption (separate, primary thread) and its coherency-detector probe design are
  in that same sibling handoff — **keep the two investigations separate.**
