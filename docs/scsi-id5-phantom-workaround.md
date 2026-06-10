# SCSI ID5 Phantom-Mount Workaround

**Status:** Temporary workaround. The second SCSI device (ID5 / SC1) is
**disabled** on this branch — only ID6 / SC0 works. A real fix to the two-disk
mount path is needed before re-enabling ID5.

## Where the workaround lives

`rtl/dataController_top.sv`, on the `ncr5380` instantiation:

```systemverilog
// connections to io controller
// Single-disk workaround: force device 1 (SCSI ID5) to never mount. ...
.img_mounted( {1'b0, img_mounted[0]} ),
```

That mask makes target 1 see `img_mounted[1] = 0` forever, so its internal
`mounted` register stays 0 and the target refuses selection (just like a real
absent device). The Mac's bus scan times it out and proceeds with ID6.

## What goes wrong without the mask

This session captured the smoking gun on real hardware via a new JTAG probe
(**PSCJ** in `rtl/dbg_min.sv`) that counts each slot's `img_mounted` pulses and
latches the `img_size` value present at the moment of each pulse. With the user
having mounted **only** SC0 in the OSD, the probe read:

```
MOUNT: slot0 pulses=1 (sz!=0:1) | slot1 pulses=1 (sz!=0:1 sz[19:0]=0x6B800)
       | mounted t0(ID6)=1 t1(ID5)=1
```

Both slots received exactly one `img_mounted` pulse, **both with nonzero
`img_size`** (slot 1's pulse captured `0x6B800` in the low 20 bits). The target's
mount logic in `rtl/scsi.v` says:

```systemverilog
if (img_mounted) begin
    if (|img_blocks) mounted <= 1;
    else             mounted <= 0;
end
```

… so target 1 correctly latched `mounted = 1` based on the nonzero size it saw
during its pulse. Then the Mac selected ID5 during its SCSI scan and wedged in
the data phase — the "Welcome to Macintosh" hang debugged earlier this session.

## Mechanism (most likely)

`img_size` in `LBMacTwo.sv` is a **single shared wire**:

```systemverilog
wire [63:0] img_size;
```

… but `img_mounted` is per-device (`[SCSI_DEVS-1:0]`). The framework convention
is that `img_size` is valid in the cycle `img_mounted[i]` asserts, *for slot i*.
The probe data is consistent with the HPS pulsing `img_mounted[1]` on core init
(or after some mount-table replay) while the shared `img_size` still holds the
value from a prior slot 0 pulse, so target 1 latches mounted=1 off slot 0's
size.

Whether this is:

- the HPS replaying a mount-table entry for SC1 that the OSD eject didn't
  fully clear, **or**
- a per-pulse vs. shared-`img_size` timing race in the integration, **or**
- a stale-state behavior unique to how this core uses `hps_io` with
  `VDNUM = 2`,

was not nailed down before the workaround landed — the Verilator sim may
not replicate the real HPS pulse pattern exactly (§8 of
`docs/MISTER_HARDWARE_DEBUGGING.md`), so the trace was done on hardware.

## Path to a real fix

Any of these would let us drop the mask:

1. **Latch a per-target `img_size`** strictly when each target's own
   `img_mounted[i]` pulses, and gate the target's `mounted` on that
   per-target captured size — so a spurious slot-1 pulse with a stale shared
   size can't phantom-mount.
2. **Investigate why `img_mounted[1]` pulses** for the empty slot at all
   (probe earlier in the chain, between `hps_io` and the slot bookkeeping) —
   if it's an HPS-side bug, fix or suppress it upstream of the core.
3. **Cold-reset the `mounted` register** on `_cpuReset` and require a
   subsequent legitimate mount pulse (with size > 0 *and* a fresh-mount flag,
   if such a thing exists). Reduces the surface but doesn't kill the race.

Approach (1) is the cleanest and most local to this repo. It's the standard
MiSTer multi-disk pattern and would let SC1 work correctly when actually used.

## Reverting the workaround

When the real fix lands, change the `dataController_top.sv` line back to:

```systemverilog
.img_mounted( img_mounted ),
```

and remove the surrounding workaround comment. Re-test with **both** slots
populated (target_mounted should read `0x3` only when both genuinely have
images) and with only SC0 populated (must read `0x1`).

## Related diagnostics in this branch

- **PSCJ** (`rtl/dbg_min.sv` — *retired before commit, but the design lives in
  this branch's history*) — captured per-slot pulse counts + size-at-pulse; that
  data is what proved this is a real phantom mount, not a stale latch.
- **PSCK / PSCL** (`rtl/dbg_min.sv`, committed) — CPU exception capture
  (`trapmake` + `trap_vector` + opcode + faulting PC), independent of the
  SCSI work but added in the same session. Decodes any Sad Mac to its CPU
  exception vector — handy when chasing the next hang after this workaround.
