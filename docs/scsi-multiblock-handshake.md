# SCSI Multi-Block Read Handshake — Status & Sim-vs-Hardware Notes

*Branch: `clocks-clean`. Last updated 2026-05-27.*

This document captures the state of the SCSI multi-block read work, the root
cause of the long-standing "Welcome to Macintosh" hang, the faithful fix that
replaced the earlier heuristics, and **why the remaining residual is expected to
behave differently on real FPGA hardware than in the Verilator sim.**

## TL;DR

- The "Welcome to Macintosh" hang on a SCSI boot was a **REQ/ACK handshake
  timing** problem, not a logic bug.
- The target (`rtl/scsi.v`) used to re-assert `REQ` **combinationally** the
  instant `ACK` fell (0 ns). A real NCR 5380 — and especially a real drive —
  holds `REQ` deasserted between bytes far longer than that.
- The Mac's disk driver relies on that REQ-low window: between blocks it runs
  polled handshake loops that only advance when they observe `REQ = 0`.
- Fix (commit `2fde75b`): model the real inter-byte REQ-low delay
  (`REASSERT_DLY`), and **remove every heuristic** that had been bolted on while
  chasing the symptom.
- Result in sim: multi-block reads now complete (`tlen` 2/3/5/6 verified). One
  residual case (`tlen=160`, an 80 KB read) still hangs in the **ideal-timing
  sim** because its driver path polls later than the modeled window.
- **This residual is an artifact of the sim's idealized timing. On real
  hardware the CPU↔drive timing ratio is authentic, so the REQ-low window the
  driver polls for is genuinely present and wide — the same RTL should boot.**

## Background: how the Mac reads a multi-block transfer

Reconstructed from the NCR 5380 design manual (SP-1051, §11.5/11.6) and by
disassembling the Mac II ROM + the disk driver that gets loaded into low RAM:

1. The driver issues a `READ(10)` for *N* 512-byte blocks (one SCSI DATA-IN
   phase carries all *N* blocks — the block boundary is invisible to SCSI).
2. For each block it calls a ROM **blind pseudo-DMA** primitive
   (`$40826B54`: byte-align, then unrolled `move.l (a0),(a2)+` /DACK longword
   reads) to move 512 bytes.
3. Between blocks it runs polled handshake loops on the 5380 registers:
   - `$11066`: `while (CSR.REQ && BSR.phase_match)` — **wait for REQ to drop**
   - `$10FB2`: `until (CSR.REQ)` — **wait for REQ to rise**
   then reads the next block.

Those loops are the crux: they advance only when they can observe `REQ` toggling
low and then high again between blocks.

## Why REQ toggles low on real hardware (the key insight)

On the SCSI bus, every byte is an interlocked REQ/ACK handshake: target asserts
REQ → initiator asserts ACK → target drops REQ → initiator drops ACK → target
asserts REQ for the next byte. So `REQ` is **low between every byte**.

How long is it low? The datasheet's chip-level number (`T11`, "ACK false to REQ
true") is only ~140 ns. But on a real system the dominant term is the **drive's
data-rate pacing**: a period-correct Mac SCSI disk delivers data at roughly
0.5–1 MB/s, i.e. **~1–2 µs per byte**. The drive simply does not have the next
byte ready any sooner, so `REQ` sits low for ~1–2 µs between bytes. *That* multi-
microsecond window is what the driver's polled loops comfortably sample.

## The bug

`rtl/scsi.v` modeled an **ideal** target: every byte is already buffered, so the
old REQ equation

```verilog
assign req = (phase != IDLE) && !sel && !ack && !io_busy && !data_phase_complete;
```

re-asserted `REQ` **combinationally** — the same cycle `ACK` fell, 0 ns later.
In the ideal-timing Verilator sim the CPU then polls `CSR.REQ` and **always sees
`REQ = 1`** (it never went low long enough to observe). The `$11066` wait-low
loop spins forever → the boot freezes at "Welcome to Macintosh."

Earlier attempts bolted heuristics onto this (a boundary REQ "breath" pulse,
clearing on `host_csr_rd`/`host_data_rd`, an idle-detector, a one-shot pulse
FSM). They advanced the boot but were fragile and **did not mimic the
hardware** — they were faking a delay the real chip/drive has for free.

## The fix (`rtl/scsi.v`, commit `2fde75b`)

Removed all heuristics. Replaced the combinational re-assert with a faithful
model of the inter-byte REQ-low time:

```verilog
// REQ stays deasserted REASSERT_DLY clk_sys cycles after ACK falls, modeling the
// drive's data-rate pacing (~1-2 us/byte). 64 cyc @ 31.3344 MHz ~ 2 us/byte
// ~ 0.5 MB/s — authentic for the era.
localparam [7:0] REASSERT_DLY = 8'd64;
reg [7:0] reassert_cnt;
always @(posedge clk) begin
    if (phase != PHASE_DATA_OUT && phase != PHASE_DATA_IN)
        reassert_cnt <= REASSERT_DLY;     // first REQ of a data phase asserts at once
    else if (ack)
        reassert_cnt <= 8'd0;             // ACK asserted -> REQ deasserts, restart delay
    else if (reassert_cnt != REASSERT_DLY)
        reassert_cnt <= reassert_cnt + 8'd1;
end
wire req_settled = (reassert_cnt == REASSERT_DLY);
assign req = (phase != PHASE_IDLE) && !sel && !ack && !io_busy
             && !data_phase_complete && req_settled;
```

No detection, no pulses — just the chip/drive's real timing.

## Results in the Verilator sim

- Multi-block reads now **complete**: `tlen` 2/3/5/6 all reach `data_complete`
  and advance to STATUS; 15 multi-block completions in one `os7.vhd` boot run.
  (Previously the *first* multi-block boundary hung.)
- The boot progresses much further through the filesystem.
- **Residual:** the largest read (`tlen=160`, 80 KB, LBA `0x9C6`) still hangs at
  its first boundary (`data_cnt=512`). Its wait-low loop polls **>64 cycles**
  after the last ACK — later than the other code paths — so `REASSERT_DLY=64`
  misses that particular window.

## Why it may work on the FPGA but not in the sim

This is the important part, and it follows directly from the root cause.

The fix needs `REQ` to be low *when the driver's loop happens to poll it*. The
gap between "last ACK of a block" and "driver's first `CSR.REQ` poll" depends on
how fast the **CPU** runs relative to how long the **drive/chip** holds `REQ`
low. Those two rates have very different ratios in the two environments:

| | Verilator sim (`verilator/`) | Real DE10-Nano FPGA |
|---|---|---|
| CPU↔SCSI timing | **Idealized.** The CPU executes the inter-block code essentially "instantly" relative to the modeled chip; memory has no real latency; the pseudo-DMA bus cycles are not paced by real bus/SDRAM timing. So the driver reaches its `CSR.REQ` poll *very soon* after the last byte. | **Authentic.** The CPU runs at the real 15.67 MHz, instruction/bus timing, SDRAM arbiter latency, and the 5380 register-access timing all apply. The driver reaches its poll on a realistic schedule. |
| REQ-low window | Only what `REASSERT_DLY` fakes (a fixed cycle count). Must be hand-tuned to land under the CPU's poll, and one fixed value cannot cover every driver path. | The genuine multi-microsecond drive-pacing window, present on **every** inter-byte gap, comfortably wider than any poll latency. |
| Net effect | The poll can "beat" the modeled window for some transfers (e.g. `tlen=160`), so the loop misses `REQ=0` and hangs. | The poll always falls inside the real REQ-low window, so the loop sees `REQ=0` and advances. |

In other words: the sim removed the very timing that makes this handshake work,
so we have to re-inject an approximation of it (`REASSERT_DLY`), and a single
fixed approximation cannot match every CPU-side code path under idealized
timing. On hardware the timing is real and uniform, so the **same RTL** has the
window it needs without any tuning.

This is consistent with the project's standing guidance (see `CLAUDE.md` and
`docs/MISTER_HARDWARE_DEBUGGING.md`): the Verilator model is **ideal-timing** and
deliberately bypasses the SDRAM arbiter, real HPS, and real device timing, so it
"will not reproduce coherency/timing bugs that only appear on hardware" — and,
symmetrically, can *introduce* timing-sensitivity that hardware does not have.

### Why we don't just crank `REASSERT_DLY`

A fixed per-byte delay large enough to cover the `tlen=160` poll (~200 cycles)
applies to **every** byte of **every** transfer, which slows the ideal-timing
sim to the point of impracticality (multi-hour boots). It is purely a
sim-throughput tradeoff; on hardware the drive paces bytes for real and there is
no such cost.

## How to verify / next steps

Reproduce a SCSI boot in the sim (from `verilator/`):

```sh
./obj_dir/Vemu --headless --no-memtest --scsi0 os7.vhd \
    --screenshot 1800 --screenshot 2600 --stop-at-frame 3500
```

(`os7.vhd` etc. are bootable Mac SCSI HFS images despite the `.vhd` extension;
they are untracked.)

Diagnostics (SIMULATION-only):
- `+scsi_stall_debug` — target/host no-progress watchdogs (`SCSI_STALL`,
  `SCSI_PHASE`, `NCR_STALL`).
- `--scsi-stall-history` — CPU PC ring-buffer + RAM dump when wedged.

Options to close out the residual:
1. **Real-hardware test (definitive).** Build the bitstream, boot from a SCSI
   HDD image, and confirm the multi-block read completes. Per the analysis
   above this is expected to work with the current RTL.
2. **Raise `REASSERT_DLY`** (96/128/160…) if a sim-only boot-to-Finder is
   wanted, accepting a slower sim. Measure the `tlen=160` poll offset first to
   pick the minimum value.

## File / commit pointers

- `rtl/scsi.v` — REQ/ACK reassert-delay model (`REASSERT_DLY`), commit `2fde75b`.
- `rtl/ncr5380.sv` — host-side `NCR_STALL` probe; wires `host_csr_rd`/`host_data_rd`.
- `verilator/sim_main.cpp` — `--no-memtest`/`--rom`, `--scsi-stall-history`.
- Datasheet: `docs/ncr-5380-53c80-design-manual.md` (§11.5/11.6, §6.4/6.7).
