# SCSI iotest investigation — progress log & handoff

Branch: `clocks-clean-rebased`. Last shipped RBF: **md5 `192c52ed`** (WRITE-fix build,
2026-05-29 — verified iotest WRITE column all `pass` 1B..1MB+ on warm-boot run).
Prior RBF: `9fb6970f` (commit `5f147a4`, selection-fix only).

## Goal
Get the `SingleStepTests/preboot/iotest` disk-I/O bench passing on the FPGA core.
**The iotest is a GOLDEN reference: it passes on real Macintosh II hardware AND on
MAME.** Therefore every failure here is a bug in OUR RTL (`rtl/scsi.v`,
`rtl/ncr5380.sv`), not in the test, the disk image, or the toolchain.

## The three distinct problems

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

### 2. SCSI selection / reset-retry hang (FIX SHIPPED in `9fb6970f`, verifying)
- Symptom: boot intermittently wedges. Probe showed target at `CMD_IN` with `SEL=1`
  AND `BSY=1`, REQ held low; target cycling `CMD_IN→IDLE→reselect` (the Mac issuing
  bus RESETs and retrying). Boot stub screen `A 0008 / D FFD9 / E FFDC` decodes as
  BootDrive=8, driver refnum=-39, `_Read` result = -36 (ioErr).
- ROOT CAUSE (found by comparing `scsi.v` to Snow `core/src/mac/scsi/controller.rs`):
  our REQ was gated on `!sel`:
  `assign req = (phase != PHASE_IDLE) && !sel && ...`
  So the target asserted BSY at CMD_IN but **withheld REQ until the initiator dropped
  SEL** — an extra handshake step the reference NCR5380s (Snow, MAME) do NOT require
  (they assert REQ on selection-complete, SEL-independent). The Mac ROM's SEL-release
  races our gate → command never starts → reset/retry loop. Only manifests on the FPGA.
- FIX (commit `5f147a4`): dropped the `!sel` term:
  `assign req = (phase != PHASE_IDLE) && !ack && !io_busy && !data_phase_complete;`
  (`phase != PHASE_IDLE` still prevents REQ during the IDLE→selection sampling window.)
- STATUS per user: "got a little further" with this build — so the fix helped.

### 3. Cold-boot vs warm-boot SCSI divergence (STILL OPEN)
- Symptom: on the FIRST (cold) boot, SCSI fails — **both reads and writes** (user
  built the read-only iotest variant; it failed on the READ portion on cold boot).
  After a **warm reboot**, the read suite runs correctly.
- Echoes the prior cold-boot RAM-clear fix (commit `dbedf90`: CPU ran POST against
  not-ready RAM; fixed by FPGA RAM pre-clear + holding CPU reset until boot0.rom).
- Likely the CPU is released from reset before the SCSI image / HPS / RAM is fully
  ready, so the first SCSI transaction races init. The reset gate
  (`LBMacTwo.sv:285`: `~pll_locked || osd_reset_req || buttons[1] || RESET ||
  !clear_done`) does NOT wait on `img_mounted`/SCSI-ready. A naive add would deadlock
  diskless boots — needs a guard (mount-arrived OR timeout).

## Probes added this session (read-only JTAG ISSP, in `ncr5380.sv`/`scsi.v`)
- **`PWR2`** (target 0 / ID6): first multi-block write capture — `byte0`, `byte1` the
  target latched, `dma_write_low_byte` intended, `dma_word_latched`, `dma_longword_latched`.
  NOTE: the `tlen>=2` gate meant to skip the 1B test appears NOT to take effect in the
  bitstream (see gotcha), so it keeps capturing the degenerate 1B write. **Probe gap to
  fix:** redesign so it reliably captures a multi-block, non-zero write (e.g. count
  write commands, or capture first word where byte0!=byte1, or make non-sticky).
- **`PSEL`** (target 0): selection/command observability — live `phase/sel/bsy/req/ack`
  + sticky `max_phase`, `reached_data`, `req_while_sel`, `cmd_bytes`.
- `dbg_min` (instantiated at `LBMacTwo.sv:1247`) already provides ~17 CPU/SCSI probes
  (PADR/PSTA/PACT/PSCS/PSC2/PSC3/PSCG/PSCH/PVBL/PASC/PAUD/PADB/PAD2/PAD3/PMSE/PADP).

### Reading probes (JTAG cable on this PC, FPGA = device @2)
- `bash scripts/read_probes.sh`  → dbg_min CPU/SCSI state (multi-sample).
- `quartus_stp_tcl -t scripts/read_pwr.tcl`  → decodes PWR2 + PSEL.
  (PATH needs `/c/intelFPGA_lite/17.0/quartus/bin64`.)
- JTAG read works on the HPS/menu-loaded bitstream; it does not reprogram.

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

## Other context
- The design is fit-marginal (82% ALMs, dominated by the ~21k-ALM mc68881 FPU). It only
  routes with the relaxed fitter settings committed in `3feb17f`
  (`FITTER_AGGRESSIVE_ROUTABILITY_OPTIMIZATION ALWAYS`, `OPTIMIZATION_MODE BALANCED`,
  `PHYSICAL_SYNTHESIS_REGISTER_DUPLICATION OFF`). FPU clk_sys is timing-violated
  (-175 ns) but FSM-driven so functionally OK for testing.
- Probe also flags: `boot1` (NuBus video declaration ROM, idx1) = 0 writes — separate
  "video decl ROM not loaded" issue, unrelated to SCSI.

## What to do NEXT (in order)
1. **Verify the selection fix** on `9fb6970f`: have the user load it, then
   `read_pwr.tcl` → expect `PSEL: reached_DATA=1`, `cmd_bytes>0`, `req_while_sel>0`.
   Confirm cold boot now reaches the bench more reliably.
2. **Cold-boot readiness (#3):** if first-boot SCSI still fails, gate CPU reset release
   on SCSI/RAM-ready with a timeout fallback (don't deadlock diskless boot). Add a probe
   for the reset-release vs img_mounted timing.
3. **Verify the WRITE fix** (#1, applied 2026-05-29): after this build deploys + a
   warm reboot, run the full iotest — the WRITE column should now read `pass` for all
   sizes (no more `@1 ..` mismatches, no `Mismatched byte` detail line). If it instead
   shows a real SWAP (offset0 now wrong too), the even/odd buffer mapping is inverted —
   revisit which buffer is even. If still duplication, the `dbg_dma_lowbyte` source
   isn't stable at buffer1's storage time — re-check `dma_write_low_byte` latching.
4. Commit often (local only — do NOT `git push`; "push" here means scp the RBF).
   Always re-verify md5 after edits.

## Reference implementations to diff against
- Snow: `../snow/core/src/mac/scsi/controller.rs` (selection, write_dma/read_dma,
  set_phase) and `../snow/core/src/mac/macii/bus.rs` (how the CPU bus dispatches
  SCSI DMA byte accesses). MAME NCR5380 (`nscsi`) — not checked out locally.
