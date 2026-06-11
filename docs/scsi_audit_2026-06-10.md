# SCSI three-way audit — LBMacTwo vs MAME vs Snow (2026-06-10)

*Why: after fixing the alloc-length deadlocks (`4376c8f`), response length
fields (`4f9506b`), and wiring the 5380 IRQ/DRQ to VIA2 (`b760944` +
level overlays `1ee80e8`), real Apple-formatted disks STILL wedged at
"Welcome to Macintosh" — every time at `data_cnt=512` of a 35-block
READ(10), with DREQ re-asserted and ignored. Three parallel audits
(our RTL, MAME's 5380+Mac glue, Snow's controller) were run to find
every remaining behavioral divergence.*

## The decisive finding — bus-visible REQ/DRQ continuity

All three sources agree on one observable that ours violated:

| | Mid-command REQ/DRQ visibility |
|---|---|
| **Real Mac II** | Drive streams; REQ toggles per byte (µs). A polling driver never sees a dead bus mid-command. Pauses are hidden behind hardware wait-states. |
| **Snow** | Pre-buffers the ENTIRE response before asserting REQ (`controller.rs` ~593): REQ literally cannot pause mid-command. Its own comment: *"System 7.1 during bulk transfers will read blocks of 512 bytes at a time from the DMA region and then use PIO momentarily"* — the driver polls registers between chunks. |
| **MAME** | `mac_scsi_helper` synthesizes the BSR DRQ bit from its FIFO state (macscsi.cpp ~205) — the driver sees "data available" even between hardware handshakes; CPU-halt hides fill latency. |
| **Ours (pre-fix)** | At every 512-byte boundary the target dropped REQ (and so CSR.REQ + BSR.DRQ) for the full HPS sector-fetch latency — tens to hundreds of µs, ms under load. |

The HD SC 4.3 driver's between-chunk register poll hit that window, read
a dead bus mid-data-phase (CSR=0x44: BSY, no REQ), concluded the
transfer had died, and fell into a terminal wait. By the time the fetch
finished and DREQ re-asserted, nothing was listening — the exact
probe-captured wedge (zero further DACK reads, I/O completions frozen).

**Fix (`5adc2e1`): split REQ into flow vs visibility.** `scsi.v` gains
`req_bus`, asserted across `io_busy` in the data phases; `ncr5380.sv`
feeds CSR.REQ and BSR.DRQ from it. The DACK/DTACK stall (`dreq`, flow
REQ) is unchanged — a data access during a fetch stalls the CPU until
the buffer half is valid (the `c616bf3` mechanism), so correctness is
preserved while the driver-visible bus never dies mid-command.

## Divergence matrix — everything else found

Ranked by suspicion for current/future symptoms. ✔ = we now match.

1. **REQ continuity (above)** — fixed in `5adc2e1`. THE wedge candidate.
2. **Data→Status REQ race (Snow-only workaround, NOT implemented by us):**
   Snow defers REQ assertion on every phase entry until the next CSR
   read (`set_req` latch, controller.rs ~410/~763) because *"MacII has a
   race condition where it will get stuck if REQ is immediately set on a
   Data -> Status transition."* MAME has no equivalent (its timing
   differs). If a wedge appears at TRANSFER END (target in STATUS_OUT,
   driver polling), implement: suppress REQ in STATUS_OUT until the
   first CSR/BSR/DACK access after phase entry. Note Snow's
   `get_drq()` includes the *pending* latch — DRQ must not glitch low
   during the deferral.
3. **Loss-of-BSY / Busy-error IRQ (MAME: BAS bit 2 + IRQ when
   MODE.MONBSY set):** we hardwire `bsr_berr=0` and never IRQ on
   disconnect. Mac OS uses MONBSY around disconnect/reselect; matters
   only if a driver enables it (System 7 async Manager may). Follow-up.
4. **Bus-reset IRQ:** MAME sets IRQ when S_RST asserts (incl. ICR
   RST write); we only CLEAR state on reset. A driver that issues a
   reset and waits for the reset interrupt would hang. The Mac II ROM
   driver doesn't (boots fine), but note for System 7.5+/A.UX.
5. **Reg-7 (RPI) read clear scope:** MAME clears PARITYERROR +
   BUSYERROR + IRQ; we clear only `irq_latch` (we never set the other
   two — consistent for now; revisit with #3).
6. **Snow's auto-ACK on plain data-register reads** when
   `MR.DMA_MODE && phase_match` even if NOT armed (A/UX enumeration
   quirk, controller.rs ~659). Ours never ACKs on register reads —
   pseudo-DMA only. Matters for A/UX, not Mac OS. Follow-up if A/UX
   is ever a target.
7. **Selection IRQ when SELEN matches (Snow ~450):** we ignore SELEN
   (so does MAME). Mac OS polls selection; fine.
8. **EODMA:** ours/Snow = phase-based ("bus not in data phase"); MAME =
   latched EOP pin + MODE.EOPIRQ. Ours matches the proven oracle. ✔
9. **Phase-mismatch IRQ:** ours = latched, falling-pmatch while
   `MR.DMA & armed`, cleared by reg-7 read — matches Snow exactly;
   MAME additionally raises DRQ alongside (BAS bit 6) on mismatch. ✔
   (minor: we leave DRQ to the flow path).
10. **dma_armed lifecycle:** ours matches Snow (armed by Start-DMA
    writes while MR.DMA; cleared on MR.DMA clear / mismatch / reset). ✔
11. **VIA2 delivery:** CA2=DRQ (IFR bit 0), CB2=IRQ (IFR bit 3), plus
    level overlays (Snow drives the flags level-wise every tick). ✔
    Note: round-4 proved the HD SC 4.3 boot path doesn't actually
    consume these — but System 7 async paths may; keep.
12. **MAME glue details for reference:** 16 µs pseudo-DMA timeout
    releases the CPU halt (no bus error); bus error fires only on
    FIFO underflow/overflow (a MAME artifact, documented as such);
    `MODE.DMA=0` write force-stops DMA and clears bus ACK (ours clears
    `dma_en`/`dma_armed`; we don't force-release a stuck ACK — only
    matters after an aborted transfer; candidate hardening).

## Validation state

RBF with `5adc2e1` (fix) + `a838ec2` (live PIFD/PDRD instrumentation)
building at write time. Protocol: fresh `HD20SC_scsifix_test.vhd`
(pristine md5 `b393de42...`), launch bare RBF via Remote API, watch
Welcome→Finder, clean shutdown, `hda_match_sources.py` → zero
COPY-class runs. If it wedges again: `scripts/sample_loop.tcl` +
`scripts/loop_disasm.py` reconstruct the wait loop's actual
instructions and polled register values from the live PIFD/PDRD pairs —
no more inference.

## Audit sources

Parallel sub-agent reports, 2026-06-10 (session 3): MAME
`src/devices/machine/ncr5380.cpp` + `src/mame/apple/macscsi.cpp` +
`macii.cpp`; Snow `core/src/mac/scsi/controller.rs` + `macii/bus.rs` +
`macii/via2.rs`; ours `rtl/ncr5380.sv` + `rtl/scsi.v` + glue. Raw
reports in the session transcript; key line citations inline above.
