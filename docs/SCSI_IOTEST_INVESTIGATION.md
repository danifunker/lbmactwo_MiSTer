# SCSI iotest investigation — progress log & handoff

Branch: `clocks-clean-rebased`. Last shipped RBF: **md5 `7f3bddf4`** (commit
`c616bf3`, 2026-05-29 — warm-boot iotest now ~100% reliable). Prior RBFs:
`8e97e125` (commit `384bc37`, race-free buffer1 odd-byte latch refinement),
`192c52ed` (commit `b945d3f`, WRITE-corruption fix), `9fb6970f` (commit `5f147a4`,
selection fix).

## Status at a glance
| # | Bug                                                          | Status                                |
|---|--------------------------------------------------------------|---------------------------------------|
| 1 | Multi-byte WRITE corruption (even-byte duplication @ off 1)  | ✅ RESOLVED (`b945d3f` → `384bc37`)   |
| 2 | Selection / reset-retry hang (REQ gated on `!sel`)           | ✅ RESOLVED (`5f147a4`)               |
| 3 | Cold-boot first-SCSI-access Sad Mac                          | ⏳ OPEN — see next-steps              |
| 4 | Warm-boot first-WRITE Sad Mac (~1/4 reliability)             | ✅ RESOLVED (`c616bf3`)               |

On a warm-boot run, `SingleStepTests/preboot/iotest` now goes end-to-end with the
full READ + WRITE column reading `pass` at every size (1B..4MB). The only remaining
open issue is the cold-boot Sad Mac on the first SCSI access (a warm reboot
recovers and runs the bench cleanly).

## Goal
Get the `SingleStepTests/preboot/iotest` disk-I/O bench passing on the FPGA core,
including from a cold first boot. **The iotest is a GOLDEN reference: it passes on
real Macintosh II hardware AND on MAME.** Therefore every failure here is a bug
in OUR RTL, not in the test, the disk image, or the toolchain.

## Problems and fixes

### 1. Multi-byte SCSI WRITE corruption (RESOLVED 2026-05-29, md5 `192c52ed`)
**Verified:** on a warm-boot iotest run, the WRITE column reads `pass` for every
size 1B..1MB+ — no more `@1 ..` mismatches, no `Mismatched byte` detail line.

- It is **EVEN-BYTE DUPLICATION, not a swap.** The bench's `verify_pattern` reports
  only the FIRST mismatch; it always lands at **offset 1**, which means offset 0 (the
  even byte) is CORRECT and the even byte is being duplicated into the odd slot. The
  pattern is `byte[j] = (j ^ (j>>8) ^ seed)` with `seed = test index`. Screenshot
  proof (4MB, i=11, seed=0x0B): detail line `ex:0A ac:0B`; expected[1]=0x0B^1=0x0A,
  actual[1]=0x0B=seed=expected[0] → the even byte landed in the odd slot. The old
  "swap" framing was wrong; the original "actual==byte[0]" note was right.
- ROOT CAUSE: in word-mode pseudo-DMA the target (`scsi.v`) latches `din` into its
  sector buffer a few cycles AFTER the ACK pulse (the `stb_ack`→`buffer_wr`→dpram
  pipeline). By the storage cycle `din` has reverted to `dout` = the EVEN byte
  (`wdata[15:8]`). The odd byte (`dma_write_low_byte` = `wdata[7:0]`) is muxed onto
  the bus only for one cycle at `dma_ack_holdoff==1`, which is an ACK-**low** cycle —
  the target never samples it. So both buffer0 (even slot) and buffer1 (odd slot)
  capture the even byte. (Writes ARE word-mode; the earlier `PWR2 dma_word_latched=0`
  was a bad capture. Even the "1B" test issues a full 512B word-mode sector write —
  it only "passes" because verify checks offset 0 only.)
- FIX (in `rtl/scsi.v`, `buffer1.data_b`): store the odd byte into buffer1 directly
  from the already-plumbed, already-stable `dbg_dma_lowbyte` (= ncr5380
  `dma_write_low_byte`), gated by `dbg_dma_word`; buffer0 (even) is unchanged.
  `.data_b(dbg_dma_word ? dbg_dma_lowbyte : din)`. This mirrors the proven READ path:
  the target selects the correct byte by its OWN `data_cnt[0]` from a stable source,
  so it is **timing-independent** (no holdoff/ACK cycle-counting). Crucially it
  changes ONLY the internal sector-buffer write data, NOT the SCSI bus-drive mux —
  so unlike the reverted `2d44706` it cannot leak a stale byte into selection.
- WHY NOT the obvious "swap the two emitted bytes": the non-`holdoff==1` (default)
  path also drives `dout`, which is the SCSI ID byte during selection; and
  `dma_word_latched` is only cleared on reset (can be stale at selection). Any fix on
  the bus-drive side risks the `2d44706` selection-corruption regression. The
  target-side buffer fix sidesteps that entirely.

### 2. SCSI selection / reset-retry hang (RESOLVED `5f147a4`, md5 `9fb6970f`)
- Symptom: boot intermittently wedged. Probe showed target at `CMD_IN` with `SEL=1`
  AND `BSY=1`, REQ held low; target cycling `CMD_IN→IDLE→reselect` (the Mac issuing
  bus RESETs and retrying). Boot stub screen `A 0008 / D FFD9 / E FFDC` decoded as
  BootDrive=8, driver refnum=-39, `_Read` result = -36 (ioErr).
- ROOT CAUSE (found by comparing `scsi.v` to Snow `core/src/mac/scsi/controller.rs`):
  our REQ was gated on `!sel`:
  `assign req = (phase != PHASE_IDLE) && !sel && ...`
  So the target asserted BSY at CMD_IN but **withheld REQ until the initiator dropped
  SEL** — an extra handshake step the reference NCR5380s (Snow, MAME) do NOT require
  (they assert REQ on selection-complete, SEL-independent). The Mac ROM's SEL-release
  raced our gate → command never started → reset/retry loop. Only manifested on FPGA.
- FIX (commit `5f147a4`): dropped the `!sel` term:
  `assign req = (phase != PHASE_IDLE) && !ack && !io_busy && !data_phase_complete;`
  (`phase != PHASE_IDLE` still prevents REQ during the IDLE→selection sampling
  window.) Verified: the `CMD_IN→IDLE→reselect` loop no longer reproduces.

### 3. Cold-boot SCSI failure (STILL OPEN)
- Symptom (cold boot only): gray checkerboard → mouse cursor → IOTest banner →
  Read `....` Write `....` → Sad Mac, before the first test runs.
- Warm reboot still recovers (and now warm-boot iotest runs to completion every
  time — see #4, the warm-boot reliability fix shipped 2026-05-29).
- Echoes the prior cold-boot RAM-clear fix (commit `dbedf90`: CPU ran POST against
  not-ready RAM; fixed by FPGA RAM pre-clear + holding CPU reset until boot0.rom).
- Hypothesis: the CPU is released from reset before the SCSI image / HPS / RAM is
  fully ready, so the first SCSI transaction races init. The reset gate
  (`LBMacTwo.sv:285`: `~pll_locked || osd_reset_req || buttons[1] || RESET ||
  !clear_done`) does NOT wait on `img_mounted`/SCSI-ready. A naive add would
  deadlock diskless boots — needs a guard (mount-arrived OR timeout).

### 4. Warm-boot first-WRITE intermittent Sad Mac (RESOLVED 2026-05-29, md5 `7f3bddf4`)
- Symptom (warm boot only, ~3/4 of runs on prior builds): boot reached iotest
  banner, reads all passed, first WRITE test triggered Sad Mac. The other 1/4 of
  warm-boot runs completed the full bench cleanly.
- ROOT CAUSE: the generic undecoded-address bus-error timeout in `LBMacTwo.sv`
  (251 cycles ≈ 8 µs at 31.3344 MHz) was catching legitimate slow SCSI DMA
  handshakes. The pre-fix `any_select` expression included
  `(selectSCSI && !scsi_dma_wait)` — so any SCSI DACK cycle where `scsiDREQ`
  took more than 8 µs to assert was treated as an undecoded address and
  bus-errored, even though the SCSI controller was operating normally.
- WHY INTERMITTENT: between the driver's BSR poll (which sees DMARQ=1 →
  green light) and the subsequent `MOVE.W (buf)+, DACK`, `scsiDREQ` could
  momentarily drop — most plausibly because `io_busy` was still gated by the
  PREVIOUS READ's HPS `io_ack` handshake (Linux-side latency on the HPS varies
  run-to-run). When the linger was <8 µs the cycle completed; when >8 µs, BERR.
- DIAGNOSIS via JTAG probes after a Sad Mac:
  - `PSCS` (dbg_min): CPU PC oscillating in ROM Sad Mac handler (0x40003xxx),
    last SCSI register read = BSR offset 0x50 = 0x4848 (DMARQ=1, PMATCH=1) —
    the driver saw the green light immediately before the Sad Mac.
  - `PSEL` (scsi.v): target in DATA_IN, REQ=1, ACK=0 — bus side healthy.
  - Combined: the `MOVE.W` to DACK was the failing cycle.
- WHY NOT VISIBLE ON `9fb6970f`: the prior build's synthesis fit happened to
  route `scsiDREQ` slightly faster, so it more often beat the 8 µs threshold.
- FIX (commit `c616bf3`): drop the `&& !scsi_dma_wait` gate so SCSI cycles
  count in `any_select` unconditionally. CPU stalls indefinitely on
  `scsiDREQ` like the real Mac II BBU glue — no glue-level timeout for SCSI.
  Driver-level watchdogs (in Mac OS) handle truly-hung SCSI; in our case,
  user reloads the core. Snow's bus dispatch does the same ("infinite
  patience") so this matches both the real hardware and the reference emu.
- VERIFIED: warm-boot iotest now ~100% reliable per user.

## Probes in the current bitstream (read-only JTAG ISSP)
Still present and useful for the open cold-boot bug:
- **`PSEL`** (`scsi.v`, target 0 / ID6): selection/command observability — live
  `phase/sel/bsy/req/ack` + sticky `max_phase`, `reached_data`, `req_while_sel`,
  `cmd_bytes`. Was the diagnostic for #2 and is also the right read after a
  cold-boot Sad Mac to see whether the first transfer ever reached DATA phase.
- **`dbg_min`** (`LBMacTwo.sv:1247`): ~17 CPU/SCSI probes
  (PADR/PSTA/PACT/PSCS/PSC2/PSC3/PSCG/PSCH/PVBL/PASC/PAUD/PADB/PAD2/PAD3/PMSE/PADP).
  **PSCS** captures the CPU's last SCSI register read + value + the current PC;
  it was the smoking gun for the #4 warm-boot diagnosis (showed CPU stuck in ROM
  Sad Mac handler with BSR=0x48 as the last read) and is the right first probe to
  read after any future SCSI-related Sad Mac.

Obsolete but still in the bitstream:
- **`PWR2`** (`ncr5380.sv`): first multi-block write capture. Was meant to settle
  word-vs-byte-mode for the WRITE bug. Never gave a clean capture (the `tlen>=2`
  gate didn't take effect). Now moot — #1 is fixed via a different mechanism.
  Candidate to remove next time we want fit budget back, but harmless otherwise.

### Reading probes (JTAG cable on dev PC, FPGA = device @2)
- `bash scripts/read_probes.sh`  → multi-sample dbg_min CPU/SCSI state.
- `quartus_stp_tcl -t scripts/read_pwr.tcl`  → decodes PWR2 + PSEL.
  (PATH needs `/c/intelFPGA_lite/17.0/quartus/bin64`.)
- JTAG reads work on the HPS/menu-loaded bitstream; reading does not reprogram.

## Build / deploy / test mechanics (and gotchas)
- Build: `bash scripts/auto_recompile.sh` (background; ~18–50 min). Output
  `output_files/LBMacTwo.rbf`.
- **VERIFY md5 CHANGES after any RTL edit** — once a debug-only edit produced a
  byte-identical RBF. If unchanged, `rm -rf db incremental_db` and rebuild; confirm.
- Deploy: `scp` the rbf to `root@192.168.99.143:/media/fat/_Unstable/LBMacTwo.rbf`
  (SSH key `~/.ssh/mister_only`, `-o BatchMode=yes`). md5-verify on the board.
- **The `.mgl`/Remote-API launch does NOT reconfigure the FPGA if LBMacTwo is already
  loaded** (same-core skip). The USER must MANUALLY load LBMacTwo from the OSD menu to
  flash a new RBF. (This silently cost us: an early scsi-fix build was never actually
  tested because the .mgl kept the old core.)
- Cold-boot issue (#3) means a fresh load often needs a manual WARM REBOOT before the
  bench runs.
- Screenshot: `POST http://192.168.99.143:8182/api/screenshots`, newest under
  `/media/fat/Screenshots/LBMacTwo/`, scp to a `C:\` path to view.
- iotest disk image already on board: `/media/fat/games/LBMacTwo/iotest.hda`.
  Rebuilding it needs `rb-cli` (rusty-backup) + a template — only on the user's machine.
- **Commit locally; do NOT `git push`.** In this project "push" means scp the RBF
  to the MiSTer, not git push to a remote.

## Other context
- The design is fit-marginal (82% ALMs, dominated by the ~21k-ALM mc68881 FPU). It only
  routes with the relaxed fitter settings committed in `3feb17f`
  (`FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS`, `OPTIMIZATION_MODE BALANCED`,
  `PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF`). FPU clk_sys is timing-violated
  (-175 ns) but FSM-driven so functionally OK for testing.
- Probe also flags: `boot1` (NuBus video declaration ROM, idx1) = 0 writes — separate
  "video decl ROM not loaded" issue, unrelated to SCSI.

## What to do NEXT — cold-boot fix (#3)
Only open item. Suggested order:

1. **Diagnose first, fix second.** After the next cold-boot Sad Mac, before doing
   anything else (no power-cycle, no reload), run:
   - `bash scripts/read_probes.sh` — grab **PSCS** (`last_reg_off` + `last_read` +
     PC). Expect to see what register the driver last touched and where the CPU
     ended up in ROM. Compare against the warm-boot baseline (BSR=0x48 →
     `MOVE.W` BERR pattern). A different `last_reg_off` would mean cold-boot
     fails earlier (e.g. during selection or REQ-poll), pointing somewhere else.
   - `quartus_stp_tcl -t scripts/read_pwr.tcl` — grab **PSEL**. `max_phase` tells
     us whether the cold-boot transfer ever reached DATA; `cmd_bytes` and
     `req_while_sel` give the per-transfer history.
   - Compare to the warm-boot probe values captured in 2026-05-29's session
     (now-fixed warm-boot: PSCS=BSR-0x4848, PSEL=DATA_IN/REQ=1/ACK=0). If
     cold-boot probes look DIFFERENT (e.g. transfer never reached CMD_IN), the
     bug is earlier in the bring-up.

2. **Hypothesis to test first: reset-gate race** (echoes the `dbedf90` cold-boot
   RAM-clear fix). The reset gate at `LBMacTwo.sv:285`
   (`~pll_locked || osd_reset_req || buttons[1] || RESET || !clear_done`) does
   NOT wait on `img_mounted`/SCSI-ready, so the CPU runs POST against a
   not-yet-mounted disk and the first SCSI access fails. Candidate fix: extend
   the gate with `!cold_boot_scsi_ready`, where `cold_boot_scsi_ready` is a
   sticky flag set by `img_mounted` OR a timeout (so diskless boots still
   come up). Use a generous timeout (~500 ms) so we don't false-positive.

3. **Useful new probe** if step 1's data is ambiguous: capture, at the moment of
   the very first `selectSCSI` rising edge, the values of `img_mounted`,
   `clear_done`, `_cpuReset`, and a free-running uptime counter. That tells us
   exactly how the first SCSI access compares to readiness. A small `dbg_min`
   addition (one more ISSP probe) is cheaper than another full diagnostic pass.

4. **Verify** after a candidate fix: cold boot from a fully powered-off MiSTer
   (or whatever simulates that for the user — `init 0` + reboot, OSD-load is
   not enough) and confirm the iotest bench reaches `pass` on the first try.
   Then re-run a few cold boots to confirm reliability.

## Reference implementations to diff against
- Snow: `../snow/core/src/mac/scsi/controller.rs` (selection, write_dma/read_dma,
  set_phase) and `../snow/core/src/mac/macii/bus.rs` (how the CPU bus dispatches
  SCSI DMA byte accesses). MAME NCR5380 (`nscsi`) — not checked out locally.
