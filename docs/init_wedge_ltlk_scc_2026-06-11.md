# INIT-parade wedge RESOLVED: LocalTalk (ltlk) vs SCC status bits — 2026-06-11

*Follow-up to `docs/handoff_init_parade_wedge_2026-06-11.md`. Root cause
found and fixed in one session with NO test builds burned — steps 1-3 of
the handoff (JTAG displacement capture, disk-image byte-anchor, HFS
forensics) plus a Snow/MAME cross-check were sufficient.*

## TL;DR

The spin at `0xA44C4` is the **.MPP LocalTalk driver's lapENQ
transmit-complete wait**, inside the `ltlk 0` resource of the **System
7.1.2** suitcase (the blessed folder is 'System 7.1.2', CNID 27 — not
System 6.0.8 as previously assumed). At boot, AppleTalk node acquisition
transmits 20 lapENQ frames over **SCC channel B**. Two RR0 status bits in
`rtl/scc.v` made that impossible:

1. **Sync/Hunt (RR0 bit 4) was hardcoded 0** = "receiver synced = line
   busy". ltlk's carrier sense always read busy, deferred the transmit,
   armed WR15=$88 (DCD/Break-Abort ext-status IRQs) and parked waiting
   for an SCC interrupt — which this core never generates (PIRQ build #9:
   `scc_irq_cnt = 0` across the whole boot). The retry counter only
   decrements per ISR-driven retry, so it never reached the give-up path.
2. **Tx Underrun/EOM (RR0 bit 6)** latch was cleared by WR0=$C0 and never
   set again. ltlk's end-of-frame sequence (`$A497E`: write $C0, then
   spin **with no timeout** until bit 6 sets) would have wedged the
   transmit even with #1 fixed.

Fix (commit `c3cb7d3`): real hunt latch (set on reset / WR3 Enter-Hunt /
WR3 RX-disable, cleared on WR0 Reset-Ext/Status) + EOM latch sets
whenever the transmitter underruns (TX shifter and buffer both empty).
With both, the entire 20-ENQ dialog completes **synchronously through
the polled byte-pump** — no SCC interrupts needed — the continuation
fires, the flag clears, boot proceeds.

## The mechanism (from the ltlk 0 disassembly)

Spin site (RAM `0xA44C4` = ltlk0+`0x5F4`, resource loaded at `0xA3ED0`):

```
A44BA: movem.l d1-d4/a0-a3,-(a7)
A44BE: bsr.b   $a44e0          ; st.b $63E(a2); bsr $A4540; clr.b $63E(a2)
A44C0: movem.l (a7)+,d1-d4/a0-a3
A44C4: tst.b   $63e(a2)        ; <<< the spin (PIFD: 4A2A 063E 66FA)
A44C8: bne.b   $a44c4
A44CA: cmpi.w  #$8001,(a1)     ; per-request status, $8001 = pending
A44CE: dbeq    d4,$a44ba       ; retry (d4 = 20 lapENQs)
```

The helper LOOKS synchronous, but `$A4540` **pops its return address
into `$634(a2)`** — a stored continuation. `bsr $A4540` returns to the
spin with the flag still set; the continuation (which lands on the
`clr.b` at `A44E6`) is invoked by the transmit FSM's completion path
(`A46BE: movea.l $634(a2),a0 / jmp (a0)`), either synchronously at the
end of a successful polled transmit or from the SCC ISR if deferred.

Carrier sense / transmit gates (all in ltlk 0, channel B via low-mem
`$1D8`/`$1DC` = SCCRd/SCCWr):

- `A4580/A4660: btst #4,(a0)` — RR0 Sync/Hunt. 1 = hunting = line idle.
  Hardcoded 0 → always "busy" → `A46F6` busy path → `A471A`: WR15←$88,
  return WITHOUT completing → eternal spin. **Wedge #1 (the one
  observed).**
- `A45CC: tst.b (a0)` after selecting RR10 — bit 7 (One Clock Missing)
  set = traffic. Ours reads 0 = idle. OK as-is.
- `A48A2`: poll RR0 bit 2 (TX empty) with timeout, write data byte to
  ch B data. Our `tx_empty_latch_b` serves this. OK as-is.
- `A497E`: WR0←$C0 (reset EOM), then `btst #6,(a0); beq .-4` — **no
  timeout** — waits for the underrun that signals frame end. Our latch
  never set → **wedge #2 (latent, would appear after fixing #1).**

## Evidence chain (the "remote disassembler" method, round 2)

1. `scripts/sample_loop.tcl` (300 PIFD samples at the wedge) captured the
   missing displacement word: `A44C6 = 063E`, plus `A44CA = 0C51`
   (`cmpi.w #$8001,(a1)`) as a cross-check.
2. Byte-anchor search for `4A 2A 06 3E 66 FA` in
   `HD20SC_scsifix_test.vhd`: 6 hits, ALL inside System suitcase
   resource forks (2× System 7.1.2 cnid 66, 4× System 7.5.5 cnid 115) —
   `scripts/hfs_forensics.py` named the files; a resource-map walk
   (`scratch/wedge_resource_id.py`) named the resource: **`ltlk` ids
   0/2 (7.1.2) and 0/2/4/5 (7.5.5)**.
3. MDB FndrInfo[0] (blessed dir) = CNID 27 = **'System 7.1.2'** — the
   actual booted System on this Picker disk.
4. Full capstone disassembly of ltlk 0 anchored at `0xA3ED0`
   (`scratch/wedge_ltlk_disasm.py` → `scratch/ltlk0_disasm.txt`) matched
   every sampled opcode word and exposed the whole transmit FSM.
5. **Snow** (boots this disk to Finder) models exactly the fixed
   semantics in `core/src/mac/scc.rs`: `sync_hunt` = hunt latch (set on
   reset/Enter-Hunt/RX-disable/frame-end, cleared on Reset-Ext/Status or
   SDLC frame start), `tx_underrun` constant 1, RR10 = 0.
   **MAME** `macii.cpp` models neither bit specially (and no
   programmer's switch); its IRQ encoder (SCC=4 > VIA2=2 > VIA1=1,
   autovectored) matches our dataController.

## Loose ends / notes

- The handoff's "IWM churn" during the spin is NOT the wedge — the spin
  loop runs with interrupts enabled and the sampler caught a VBL-context
  routine around `0xD69C-0xD8E4` (plus the VIA1 ISR at `0x6080-0x60CE`,
  RTE seen). Likely the .Sony/disk-poll VBL task on the empty internal
  drive. Revisit only if something else stalls.
- `CONF_STR` "O13,NuBus Video,Color,B&W" vs `status[13]` in LBMacTwo.sv
  looks mismatched (O13 = bits 1-3 in MiSTer syntax, code reads bit 13).
  Dormant; not touched in this session.
- The other disp groups from the byte-anchor search (0x00A6 = a
  different ltlk build, 0x02C8 = ELAP-style variant, etc.) are the same
  driver in other System versions — all would hit the same SCC bits.
- AppleTalk is evidently "active" in this image's PRAM/Chooser state, so
  every boot of this disk runs node acquisition. With the fix it
  completes harmlessly into the void (no LocalTalk peers, ENQ never
  answered → address free → done).

## Also in this build: programmer's-switch NMI (ported from MacLC)

`"RE,Interrupt (NMI / MacsBug);"` OSD trigger (status[14], free bit) →
one-shot level-7 IPL into TG68K, cleared on the level-7 IACK
(`FC=7, addr[19:16]=$F, addr[3:1]=7` — TG68K emits the faithful
`$FFFFFFFE` IACK address, verified in TG68KdotC_Kernel.vhd lines
1343-1364) with a ~2 ms timeout backstop. NOTE: TG68K's level 7 is
level-sensitive (`IPL_nr="111"` bypasses the mask check), so the
IACK-clear is what guarantees exactly one NMI per press. With MacsBug
loaded (this disk's boot blocks name it), the button should break into
a hung system — built precisely so future wedges like this one can be
inspected from the Mac side.

Commits: `c3cb7d3` (scc fix), `8ed0efd` (NMI button).

## Post-validation: NMI button works; MacsBug blocked by FPU FSAVE bug

Field test (RBF `66ba190f`, `MacLC_6-0-8-macsbug.hda`, System 6.0.8 with
MacsBug installed): pressing the OSD NMI "hung" the core. Diagnosis —
**the NMI is fine; MacsBug entered and then wedged on our FPU**:

- Live PIFD samples: CPU running flat-out, 100% supervisor, in
  MacsBug's body at top-of-RAM (`0x7E8C12-0x7ECB48`) plus the ROM
  debugger glue (`0x400020A6-0x400020FA` save/restore + the 13-rung
  `bsr.b` vector ladder; rung k = vector k+1).
- Byte-anchor of the hot code in the disk image → 'MacsBug' (System
  Folder, cnid 65) data fork; disassembly shows the debugger entry
  saves FPU context when an FPU is present:
  `FSAVE -$AF0(a5)` / `FMOVE.L fpcr,-$25A(a5)` /
  `FMOVEM fp0-fp7,-$24E(a5)` (and the mirror restore on exit).
- The sampled ladder fetches (`0x210C/0x210E`) = the **vector 11**
  rung: the FPU save F-line-faults, re-vectors into MacsBug, which
  runs the FPU save again — infinite recursive debugger entry. It
  never reaches its screen-draw or keyboard loop (VIA1 counters
  static), hence the frozen desktop and dead keys (verified: raw
  `g`+Return via `POST /api/controls/keyboard-raw/{34,28}` did
  nothing).
- The existing corpus (scratch/cir_bisect/results_final.jsonl) already
  contains both bugs: `FSAVE/FRESTORE (A0)` → **vec=11** (memory-EA
  FSAVE faults; only `-(A7)` variants pass), and all 16 `FMOVEM.X`
  roundtrips corrupt data.

**Conclusion:** MacsBug is unusable until the FPU FSAVE-memory-EA
vec-11 fault (and then FMOVEM.X data corruption) are fixed — items in
`docs/handoff_fpu_timing_closure_2026-06-10.md`. The NMI button needs
no further work; on a no-FPU config (or post-FPU-fix) it should drop
into MacsBug normally. Keyboard-injection note for future remote
MacsBug driving: the remote API route is
`POST /api/controls/keyboard-raw/<linux keycode>`.
