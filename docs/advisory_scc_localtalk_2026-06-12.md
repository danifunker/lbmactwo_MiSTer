# ADVISORY: your SCC Sync/Hunt + EOM modeling is load-bearing for 7.x boot (LocalTalk LAP)

*2026-06-12, from the MacLC_MiSTer investigation (branch
`scsi-fixes-from-lbmactwo`). Full evidence:
`../MacLC_MiSTer/docs/findings_welcome_wedge_mame_2026-06-12.md` + the MAME
trace bundle in `../MacLC_MiSTer/docs/welcome_wedge_2026-06-12/mame/`.*

## Why you're getting this

MacLC's System 7.x boot wedged forever at "Welcome to Macintosh". MAME
ground-truth tracing root-caused it to **LocalTalk, not SCSI**: when
AppleTalk opens during early extension loading, the LAP Manager (.MPP)
transmit worker gates every LLAP send on **SCC RR0 bit 4 (Sync/Hunt) == 1**
("receiver hunting" = line idle). If that reads 0, the worker takes its
defer path — "line busy, retry on SCC ext/status interrupt" — and parks the
boot on an interrupt that never comes (neither core generates SCC ExtSts
interrupts). The transmit tail additionally needs **RR0 bit 6 (Tx
Underrun/EOM)** to set after `WR0=$C0`, and **RR0 bit 2 (TxEmpty)** to be
truthful, or the per-byte polls deadlock the same way.

## Your status: GOOD — and that's exactly why your 7.1.2 boots

`rtl/scc.v` on `7-1-2-boot-working` already models all three correctly:

- `sync_hunt_a/b` latch → RR0 bit 4 (set on reset + WR3 "Enter Hunt"; stays
  hunting on a silent line) — `scc.v:147-149, 801, 822, 1222+`.
- `eom_latch_*` **set on transmit underrun** (shifter+buffer empty) —
  `scc.v:1193-1217`.
- No post-loopback TxEmpty gating — RR0 bit 2 is truthful.

This is the difference that let LBMacTwo boot the same 7.1.2 image to the
desktop while MacLC wedged: MacLC's `scc.v` had diverged — an "async purity"
cleanup hardwired Sync/Hunt to 0, the EOM underrun set was commented out,
and a post-loopback hack forced TxEmpty=0 (added to make the boot-ROM 'atlk'
self-test "stall and give up" — itself a compensation for the missing hunt
bit). MacLC re-converged to your semantics on 2026-06-12 (sync-mode-scoped).

## Asks

1. **Regression-protect these three behaviors.** They look like obscure
   status-bit trivia; they are the 7.x AppleTalk boot path. A cleanup that
   "fixes" RR0 to be datasheet-async-pure (exactly what happened on MacLC,
   commit a89c671 era) reintroduces an unbounded Welcome-screen hang on any
   image with AppleTalk enabled in PRAM. Suggested cheap guard: a comment
   block at the RR0 assembly pointing here, plus a 7.x-boot smoke test
   before SCC changes ship.
2. **Treat your `scc.v` as canonical going forward.** The cores' SCC files
   share lineage and drift silently; MacLC now matches your behavior for
   hunt/EOM/TxEmpty (scoped to sync mode). If you touch SCC, consider
   porting both ways deliberately rather than letting them diverge again.

## Known shared residual (not boot-blocking, single-node)

Neither core generates **SCC external/status interrupts** (WR15 ext IRQ
enables are stored but never fire). The LAP defer path arms `WR15=$88` and
sleeps on the Break/Abort ExtSts interrupt; on a quiet single-node line the
defer path is never taken (MAME boots both OSes with zero SCC interrupts),
so booting is safe. But a **busy line** — i.e. future real multi-node
LocalTalk bridging, or anything that makes RR0 bit 4 read 0 mid-probe —
would defer and hang exactly like MacLC did. If LocalTalk networking ever
becomes a feature, ExtSts interrupt generation (and the V8/Mac-II IRQ
routing for it) is the missing piece. Same applies to MacLC.

## Verification recipe (if you want to re-prove it on your side)

MAME tracer: `../MacLC_MiSTer/verilator/mame/wedge_trace.lua` — RAM pattern
scan for the spin (`tst.b d16(A2); bne.s -6`, wildcard `4A 2[8-F] xx xx 66
FA`), flag write taps, full SCC write/read-transition log (`SCCTAP=1`). The
healthy choreography it must reproduce (per lapENQ node-ID probe, all
polled): WR14=$41 ×4 → RR10 must read $00 → WR5 $62/$60/$6B → WR3=$D0
(enter hunt) → WR0=$80 → per byte: poll RR0.2 then write data → WR0=$C0 →
poll RR0.6 → poll RR0.2 → WR5 $62/$60 → WR14=$41, WR3=$DD. Gate at worker
entry: `btst #4` on RR0.
