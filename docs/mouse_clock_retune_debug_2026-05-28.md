# ADB Mouse Regression After 31.3344 MHz Clock Retune — Debug Session Log

**Date:** 2026-05-27 → 2026-05-28
**Branch:** `new-clocks-for-floppy`
**Status:** Working build exists (`24d8953`, RBF md5 `334f089d`) but is
**placement-marginal**. Root cause is **timing closure**, not ADB logic.
Robust fix still open.

---

## 1. Symptom

After the clocking-accuracy commits retuned the master PLL from 32.5 MHz to
**31.3344 MHz** (= 2 × C15M), the ADB **mouse cursor appears but does not move**
on the real DE10-Nano. Keyboard/boot otherwise fine. Reverting the clocks
restores the mouse, but the correct clocks must stay for accuracy.

Regression window: worked at `2829793` (May 25, MDC824 video, old 32.5 MHz),
broke somewhere in `54748cc..518dc58` (May 26 clock retune). The SR-shim and
ADB RTL were **not** changed in those commits — only clock frequency + derived
constants (`SYS_CLK_HZ` 32500000→31334400, IWM re-clock, ASC dividers).

---

## 2. How we diagnosed it (JTAG ISSP probes)

All via `scripts/read_probes.sh` → `scripts/cpu_state.tcl` (quartus_stp_tcl),
reading `altsource_probe` instances added to `rtl/dbg_min.sv`. RBF deployed to
`/media/fat/_Unstable/LBMacTwo.rbf`; core (re)loaded with
`echo 'load_core /media/fat/_Unstable/LBMacTwo.rbf' > /dev/MiSTer_cmd` over SSH
(`ssh -i ~/.ssh/mister_only root@192.168.99.143`). Screenshots via the mrext
Remote API (`POST/GET http://192.168.99.143:8182/api/screenshots`).

Probes built for this hunt:
- **PMSE** — counts `ps2_mouse[24]` toggles vs `mouse_has_event` rising edges.
- **PADP** — counts ADB command bytes: `0x3C` (addr 3 Talk reg0 = mouse poll)
  vs `0x2C` (addr 2 = keyboard), + last two distinct command bytes.
- **PSRR / PSRL** — last 4 bytes the CPU **read** from the VIA1 SR vs the last 4
  bytes the shim **loaded** into it (needs `dbg_adb3/4` plumbing from
  dataController_top). Filterable to ACR=011 (shift-in) reads only.
- **Forced-response trick** — hardcode mouse Talk reg0 = a fixed delta
  (`response[0]=0x83`, `response[1]=0x85`) to exercise the byte-delivery path
  independent of real HPS mouse input.

### Findings, in order

1. **HPS delivers + adb.sv latches.** With the mouse moving, PMSE showed
   `ps2m24_toggles` climbing ~30 Hz and `mouse_has_event_pulses` ~10 Hz. So the
   HPS→FPGA path and `adb.sv` event latch both work.
2. **The ps2_mouse strobe sync theory was a RED HERRING.** `hps_io` runs on the
   same `clk_sys` as `adb`, so `ps2_mouse[24:0]` is already synchronous — no real
   CDC. The 2-FF/3-FF synchronizer commits (`e90a2bb`, `518dc58`, +3rd stage)
   are harmless but do nothing for this bug.
3. **ROM polls the mouse.** PADP showed `mouse_polls(0x3C)` saturating, FSM
   cycling COMMAND→DATA1→DATA2→IDLE, `dout_strobe` ~50 Hz (2 response bytes per
   poll). But ROM stayed **stuck re-polling 0x3C only** (never advancing to the
   keyboard 0x2C) — the classic signature of ROM **rejecting** each response and
   retrying.
4. **The actual corruption (PSRR/PSRL, forced 0x83/0x85 response).** The shim
   *loaded* `00, 00, 83, 85` but the CPU *read* `3C, 00, 83, 85`:
   - The shim fired shift-in completions on a blind ~3 ms timer, decoupled from
     when `adb.sv` actually produced each response byte (`adb_dout_strobe`, which
     only pulses on ROM's ST_DATA1/ST_DATA2 transition). So it completed 1-2
     times with **stale `kbd_to_mac` (0x00)** before the real bytes.
   - ROM's first shift-in read even grabbed the leftover **command-byte echo
     `0x3C`** sitting in `via6522` `shift_reg` from the cmd shift-out.
   - ROM framed `{3C,00}` (or similar leading garbage) as the 2-byte mouse
     packet, rejected it, and re-polled forever → cursor frozen.
   - The PLL retune (CPU ~3.6 % slower) slid the ROM-ISR timing just past the
     3 ms window, exposing a latent race the old clock happened to dodge.

---

## 3. The fix that WORKED (commit 24d8953, RBF md5 334f089d)

`rtl/dataController_top.sv` — "fresh-byte" completion: track
`via1_kbd_to_mac_fresh` (set on `adb_dout_strobe`, cleared on load). Complete the
shift-in the instant the chip produces a fresh byte; fall back to the timer only
when safe (`!adb_resp_pending` or ADB bus IDLE) so the idle-autopoll heartbeat
keeps firing and it never deadlocks.

**Verified on hardware:** cursor tracks physical mouse movement at the boot "?"
screen with the correct 31.3344 MHz clocks. Confirmed by the user
("mouse is actually working!!!").

This RBF is preserved on the MiSTer as
`/media/fat/_Unstable/LBMacTwo_KNOWNGOOD_334f089d.rbf`.

---

## 4. THE CATCH: it's placement-marginal (real root cause = timing closure)

Stripping the JTAG diagnostic probes — commit `7f5d10da`, which is **the
identical fresh-byte logic, only the probes removed** — **re-broke the mouse** on
hardware (ROM back to re-polling 0x3C). Same RTL logic, different FPGA
placement, different result. **The probes were accidental timing ballast.**

`output_files/LBMacTwo.sta.rpt`:
- **Worst-case setup slack = -174.8 ns**, on the FPU path
  `mc68881_fpu_lite:fpu_inst|mc68881_top:u_fpu|fp80_to_int_trunc~... ->
  result_ex_reg[...]` (a huge unpipelined fp80→int combinational chain).
- **No failing timing paths in the ADB/VIA/SR logic itself.**

So the ADB logic meets timing; the design as a whole does not. There are
near-threshold paths that flip negative when placement shifts (e.g. when the
probes are added/removed), and *that* is what makes the mouse work-or-not. The
byte-delivery logic was never the problem in the no-probe builds.

---

## 5. Dead ends (do NOT repeat)

| Attempt | Commit/Build | Result |
|---|---|---|
| ps2_mouse[24] 2-FF then 3-FF strobe synchronizer | e90a2bb / 518dc58 / +3rd | Harmless no-op; hps_io is already clk_sys-synchronous. Not the bug. |
| Gate ALL shift-in completion on fresh byte | 467785a | **Deadlock** — ROM waits for IFR before transitioning state; chip produces the byte on that transition; gate waited for the byte before the IFR. Circular. |
| Fresh-byte fix + probes | 24d8953 / `334f089d` | **WORKS** (but placement-lucky). |
| Cleanup: same fix, probes removed | 7f5d10da | **FAILS** — proves placement-marginality. |
| Index-driven SR shim v1 (+ via6522 load on `sr_ext_load` alone) | eff40c39 | **FAILS** — decoupling load from `sr_ext_complete` lost the `shift_active` clear, so via6522's internal shifter corrupted the loaded byte. |
| Index-driven SR shim v2 (via6522 reverted, `response[0]` delivered immediately on shift-in entry) | 2166c9d9 | **FAILS** — index logic is sound but irrelevant; the no-probe placement is the real problem. |

Key lesson: **the bytes were never the issue in the failing builds.** Multiple
SR-shim rewrites all failed without probes because they don't touch timing
closure. Stop iterating on the SR shim.

---

## 6. Other observations

- **`load_core` (soft) reloads can wedge HPS mouse delivery.** After loading a
  broken build, even reloading the known-good build via `load_core` sometimes
  left `ps2_mouse[24]` not toggling until a full power cycle. Conversely the user
  once saw it come alive only *after* a soft core reset. Partly the **2.4 GHz
  wireless mouse** (`XING WEI 2.4G USB`) / HPS USB state; a Keychron M3 8K
  Bluetooth mouse is now also connected. Mouse-input flakiness confounds testing
  — prefer a known mouse + cold boot when validating.
- **Audio "weird at start" + VBL IRQ count stuck at 1** seen in probes are
  **expected pre-boot** (Sound Manager / video-card ISR not installed yet at the
  "?" screen). Not part of this regression.
- **White screen on OSD soft-reset** is a known quirk (HPS doesn't re-push
  `boot0.rom` on `status[0]` reset) — see `feedback-test-via-rbf`.

---

## 7. Where things stand / next steps

- Working tree reverted to `24d8953` (known-good fresh-byte fix + probes).
- The index-driven SR-shim rework was reverted (not a fix).
- MiSTer SD holds only `334f089d` (active `LBMacTwo.rbf` + `LBMacTwo_KNOWNGOOD_334f089d.rbf`).

**Real robust fix = close timing**, not more SR-shim work. Candidate directions:
1. **Pipeline / retime the FPU `fp80_to_int_trunc` chain** (the -174.8 ns path).
   This is the worst violation by far and the most likely lever.
2. **Add SDC constraints** — multicycle / false-path on genuinely non-critical
   paths so the fitter stops sacrificing the near-threshold paths that decide the
   mouse. (Design is currently "not fully constrained for setup/hold" per STA.)
3. **Bisect the specific near-threshold path** in the CPU/VIA region that flips
   when probes are removed (detailed `report_timing` with/without probes), then
   fix/constrain just that one.
4. Once timing closes, re-verify the probe-free build tracks the mouse, then
   strip probes for good and commit the clean fix.

Decisions deferred to next session: which timing-closure approach; whether to
keep the fresh-byte fix or the (cleaner, deterministic) index-driven shim once
timing is no longer the gating factor.
