# Pass-off — rebuild `cpufpubench.hda` with the recovery.s stray-trap fixes

*2026-06-10, branch `fpu-bus-adapter-dani`. Run this on the machine that has
the Retro68 toolchain + rb-cli (NOT the MiSTer-debug Windows box — it has
neither). Everything to change is already committed; this is build + package
+ hand-back.*

## Why (1 paragraph of context)

The cpufpu supervisor bench wedges at `run=1` on real HW. A JTAG jump-ring
probe decoded the whole cascade: **test 1 actually passes** (its journal
record on disk says `"vec":0,"pass":1`), then a still-unidentified fault
fires during the 16 KB `_Write` of the results journal, and the bench's own
recovery machinery turns that one fault into both observed symptoms:

1. `recovery_core` longjmps with **SR left = $2700** → every later
   synchronous `_Write` IOWait-spins forever (its per-block SCSI completion
   IRQ is masked) — this is the "SCSI write wedge."
2. The longjmp goes through **stale `g_resume_pc`/`g_resume_sp`** (saved
   during a test invocation that already returned), so `.resume`'s final RTS
   pops a reused stack slot and launches the CPU into garbage — this is the
   "wild-PC runaway" (observed: RTS → `0xFFF7A` = into the stack, and RTS →
   `0x600010` = RAM sweep).

Full story: memory `project_tg68_runaway_unification` +
`docs/handoff_tg68_runaway_2026-06-10.md` + `scratch/cir_bisect/` on the
debug box.

## What is already committed (verify, don't redo)

`SingleStepTests/preboot/common/runtime/recovery.s` — three changes:

1. **New globals** (`.data`): `g_resume_sr`, `g_in_test`, and exported
   `g_stray_vec` / `g_stray_pc`.
2. **`invoke_test_with_recovery`**: saves SR at arm time, sets
   `g_in_test=1` only around the `jsr (a0)` test call, clears it at
   `.resume`.
3. **`recovery_core`**: split into a stray path and `recovery_longjmp`.
   - In-test trap (`g_in_test==1`): longjmp as before but **restore the
     arm-time SR** instead of leaving $2700.
   - Stray trap (`g_in_test==0`): record `g_stray_vec` + `g_stray_pc`
     (faulting PC from the 68020 frame at `2(%sp)`), paint a **stripe row
     (fb row 56)** plus **one block per vector number (row 58)**, then
     `stop #$2700` — freeze the crime scene instead of corrupting it.

⚠️ The asm was written blind on a machine with no m68k assembler. It follows
the file's existing syntax (same `move.l 0x0824, %aN` absolute form, numeric
local labels, `|` comments), but **expect possible minor assembler fixes** —
keep semantics identical if you touch it.

## Build steps

Per `SingleStepTests/preboot/common/make/common.mk` and
`supervisor_bench/build_cpu_fpu_hda.sh`:

- Toolchain: Retro68 at `$HOME/repos/Retro68-build/toolchain`
  (`m68k-apple-macos-*`); override `RETRO68` env if elsewhere.
- `rb-cli` at `$HOME/repos/rusty-backup/target/release/rb-cli` (override
  `RB`), template disk `$HOME/testdisk.hda`, `jq` installed.

```bash
cd SingleStepTests/preboot/supervisor_bench
bash build_cpu_fpu_hda.sh            # runs `make cpu_fpu`, emits /tmp/cpufpubench.hda
```

## Hand-back (all four items, please)

1. **The image**: zip `/tmp/cpufpubench.hda` as
   `SingleStepTests/preboot/supervisor_bench/fixtures/cpufputestbench.hda.zip`
   (replace the existing one, md5 of the old .hda was `a21bcdd1...`). Note
   the new .hda md5 in the commit message.
2. **A symbol/disasm dump** — the debug box's JTAG probes hardcode payload
   addresses that WILL shift with this rebuild. Save BOTH into `fixtures/`:
   ```bash
   PFX=$HOME/repos/Retro68-build/toolchain/bin/m68k-apple-macos-
   ${PFX}objdump -d build/payload_cpu_fpu_scsi.elf > fixtures/payload_cpu_fpu_scsi.dis.txt
   ${PFX}nm build/payload_cpu_fpu_scsi.elf | sort > fixtures/payload_cpu_fpu_scsi.nm.txt
   ```
   The probe retarget needs at minimum: `recovery_core`, `recovery_stub_v2`
   (first stub), `invoke_test_with_recovery`, `prog_buffer`, `vbr_table`,
   `g_stray_vec`, `g_stray_pc`.
3. **Commit** recovery.s tweaks (if any were needed to assemble) + fixture
   zip + dumps on `fpu-bus-adapter-dani`.
4. **Note the addresses that changed** in the commit message or a one-line
   file — old values for reference: payload base `0x40000`, stubs
   `0x40F3A..0x410CC` (14 bytes apart, order v2..v9,v11..v15,v32..v47),
   `recovery_core 0x410D0`, `.resume 0x4114A`, invoke's final RTS `0x4115C`,
   `prog_buffer ~0x62900`, stack top `0x100000`.

## What the fixed bench should do on the MiSTer (expected outcomes)

Deploy/run loop lives on the debug box (`scratch/cir_bisect/deploy_and_run.sh`).
With the fixed .hda, the primal fault becomes self-reporting — one of:

- **Stray-trap halt screen**: stripe row + N blocks (N = vector number,
  e.g. 11 blocks = F-line, 2 = bus error). CPU halted; `g_stray_vec` /
  `g_stray_pc` hold exact values (addresses from the nm dump). This names
  the primal fault with zero JTAG.
- **Tests proceed past run=1** (if the primal fault only ever bit via the
  SR/stale-longjmp amplification): counts climb; watch where/if it stops.
- Unchanged wedge would mean the fault fires *inside* a test window —
  ruled unlikely (test 1's record says pass) but then the JTAG stub-window
  ring (probe build #2, in flight on the debug box) catches it instead.
