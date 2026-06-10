# TODO: Reset Coverage Audit (FPGA-level state survives `_cpuReset`)

**Status:** Known, deferred. Use the core-swap workaround (below) when
testing changes — don't trust a soft reset to give a clean slate. Worth
a dedicated session, not interleaved with feature work.

## Symptom

The same `.rbf` + same disk image can produce **meaningfully different
boot outcomes** depending on how the core was last reset on the MiSTer:

- **OSD core reset / hot menu re-enter**: stale-state path. Boot may
  wedge, Sad-Mac with codes that don't match a deterministic logic bug,
  or hit non-reproducible Resource Manager errors.
- **Load a different core in the OSD, then load this core again**: clean
  path. Full FPGA reconfig zeros every flip-flop's initial value, SDRAM
  contents are effectively scrambled at power-on (the ROM RAM walk then
  overwrites them legitimately), and the FPU starts in a known-NULL
  state. Boot proceeds further or hangs at a *different*, more
  diagnosable place.

The behavior difference between "soft reset" and "full reconfig" is the
diagnostic signature of **state that survives `_cpuReset`** when it
shouldn't.

## Why this happens

Three categories of state aren't covered by the project's reset wiring:

1. **Verilog `reg`s without an explicit reset clause.** Initial value at
   FPGA configuration is what `reg foo = 0;` (or default 0) sets. After
   that, only an explicit `if (reset) foo <= ...;` resets them. Many
   always-blocks across this codebase don't have it. One known concrete
   case is already documented:
   `docs/scsi-id5-phantom-workaround.md` — the `mounted` reg in
   `rtl/scsi.v` has no reset, so the phantom-mount state from a previous
   session can persist into a fresh boot attempt.
   Likely additional offenders (suspect, not confirmed):
   - SCSI target FSMs (data_cnt, blk_breath state, command buffer)
   - IWM/floppy state machines (`rtl/iwm.v`, `rtl/floppy.v`)
   - ADB transceiver state (`rtl/adb.sv`)
   - VIA shift-register / kbd_bitcnt counters in
     `rtl/dataController_top.sv`
   - FPU FSM state in `rtl/mc68881/`
   - Various "last-seen" / sticky probe latches in `rtl/dbg_min.sv`
     (those are *deliberately* sticky for diagnostics, but worth
     reviewing — some of them feed control paths, not just probes).
2. **SDRAM contents are never cleared.** A soft reset doesn't touch
   what's in SDRAM. Previous-boot residue can mask RAM-test
   discrepancies, or seed the System's low-RAM globals with non-zero
   values it expects to find as zero on cold boot.
3. **The lite FPU's internal state.** FPCR / FPSR / FPIAR / the FSAVE
   frame-state tag. If a previous boot stopped mid-FSAVE / mid-FRESTORE
   or left the FPU in a non-IDLE state, the next boot's first FSAVE may
   emit a non-NULL frame, and the ROM's `FRESTORE` follow-up may not
   match the lite FPU's supported response patterns.

## Workaround until a proper fix lands

**Before judging the result of any test on the FPGA on this branch:**

1. In the MiSTer OSD, **load a different core** (anything — Apple-II,
   Atari, whatever's installed).
2. Then **load LBMacTwo again**.
3. Now do the actual test (mount disks, set memory, reset, boot).

This forces a full FPGA reconfiguration and gives you a real cold start.
A JTAG reflash also does this (it reconfigures the FPGA), so that's
equivalent for our hardware debugging loop — but **a SoftRom / OSD
reset is not**.

## What the eventual fix looks like

Two-step approach, by priority:

1. **Audit and add `reset` clauses to RTL regs that survive `_cpuReset`
   but shouldn't.** Roughly:
   - `git grep -nE "always @\(posedge"` and look for blocks that lack a
     `reset` branch or rely on `initial`-only values for correctness.
   - For each suspect, decide: does this need to clear on `_cpuReset`?
     (Most data-path / FSM / counter regs: yes. Sticky JTAG probes for
     diagnostics: no.) Add the reset clause where needed.
   - Concrete TODO: start with `rtl/scsi.v`'s `mounted` (removes the
     need for the ID5-phantom mask workaround), then sweep the other
     suspect files listed above.
2. **Decide what SDRAM contents should be on cold reset.** Options:
   (a) leave random — explicit RAM-walk handles real cold start. (b) Add a
   reset-driven SDRAM scrubber that zero-fills on power-on. (a) matches
   real hardware and is probably right.
3. **Audit the FPU FSM state.** The handoff doc (`d40979f`) already
   touched FRESTORE NULL-frame handling (`0b66b67`); a sweep that
   guarantees `FPCR/FPSR/FPIAR/frame-state` start from a NULL/IDLE on
   `_cpuReset` would close this entire class.

## Related docs

- `docs/scsi-id5-phantom-workaround.md` — the most concrete instance of
  this class found so far (sticky `mounted` reg).
- `docs/fpu_bus_adapter_handoff.md` — open issues that may be partly
  reset-coverage related (especially Open issue #1's
  "bench hang after test 1").
- `docs/MISTER_HARDWARE_DEBUGGING.md` §8 — the canonical sim-vs-hardware
  list. Reset coverage belongs in spirit alongside the SDRAM-arbiter and
  HPS-latency caveats: things sim's ideal timing hides.
