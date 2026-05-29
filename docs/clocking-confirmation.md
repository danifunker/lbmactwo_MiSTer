# Mac II Core Clocking — Verification and Implementation Plan

This document captures the **historically-accurate clock topology** for the
Macintosh II (HMMU, Rev B ROM) FPGA core, verified against MAME's
`src/mame/apple/macii.cpp` and the Snow emulator (`core/src/mac/macii/bus.rs`),
and lays out the implementation order requested by the maintainer.

The current core uses `clk_sys = 32.5 MHz` with `clk16_en = 16.25 MHz` and
`clk8_en = 8.125 MHz` — these are off by ~+3.6 % from the real machine. The
goal is to retune the master PLL to **31.3344 MHz** (= 2 × C15M) so every
existing clock-enable lands on the correct historical rate with no logic
change, then fix the small number of blocks (ASC, IWM) that need explicit
re-clocking.

## 1. Verified clock topology (MAME + Snow)

From `src/mame/apple/macii.cpp`:

```
#define C15M (15.6672_MHz_XTAL)
#define C7M  (C15M/2)                  // 7.8336 MHz

M68020HMMU  ... C15M                   // CPU 15.6672 MHz
ASC         ... C15M                   // ASC 15.6672 MHz   (NOT 22.5792)
IWM/SWIM1   ... C15M                   // IWM 15.6672 MHz, /2 internal for GCR
SCC85C30    ... C7M                    // SCC 7.8336 MHz    (NOT 3.6864 on PCLK)
R65NC22 VIA1/VIA2 ... C7M/10           // 783.36 kHz
ADBMODEM    ... C7M                    // ADB μC at 7.8336 MHz; ADB is via VIA1
```

Snow (`core/src/mac/macii/bus.rs`) uses `CLOCK_SPEED = 16_000_000` as a nominal
and ticks VIA at `/20` (= 800 kHz nominal) — same ratios.

Authoritative target rates:

| Block | Rate | Source of clock |
|---|---|---|
| CPU (TG68K, 68020 mode) | 15.6672 MHz | C15M |
| FPU (MC68881) | 15.6672 MHz | C15M, synchronous with CPU |
| IWM (floppy) | 15.6672 MHz in, /2 internal → 7.8336 MHz GCR phase | C15M |
| SCC (Z8530) PCLK | 7.8336 MHz | C7M |
| VIA1 / VIA2 | 783.36 kHz | C7M / 10 |
| ASC (Apple Sound Chip) | 15.6672 MHz | C15M |
| SCSI 5380 | asynchronous | CPU bus strobes |
| ADB | no separate clock | VIA1 SR / CB1+CB2 |
| NuBus slot | ~10 MHz nominal | not modelled cycle-accurately today |

### Corrections to the third-party prompt that motivated this work

The prompt that triggered the audit had three factual errors. They are
documented here so we don't reintroduce them:

1. **ASC is NOT 22.5792 MHz on the Mac II.** That oscillator belongs to the
   Mac IIfx and later (Curio-era). MAME instantiates the Mac II ASC at C15M.
2. **SCC PCLK is 7.8336 MHz, not 3.6864 MHz.** The 3.6864 MHz reference is the
   `RTxCA / RTxCB` baud-rate generator input used by some Macs for LocalTalk
   (`230.4 kbps = 3.6864 MHz / 16`), not the chip's PCLK. The PCLK pin gets C7M.
3. **NuBus at master/3 (10.4448 MHz) is a fine *nominal*** but the Mac II
   doesn't synchronize NuBus cards to a dedicated slot clock in MAME, and the
   in-core NuBus video cards already run synchronously off `clk_sys`. No change
   needed for emulation fidelity.

CPU, FPU, IWM-input, VIA, ADB, and SCSI guidance from the prompt were correct.

## 2. Current core (baseline)

PLL (`rtl/pll/pll_0002.v`):
- `outclk_0 = clk_mem = 65 MHz` (SDRAM)
- `outclk_1 = clk_sys = 32.5 MHz` (180°)

Bus phase divider (`rtl/addrController_top.v:73–83`) from `clk_sys`:
- `clk16_en_p/n` = 16.25 MHz (CPU/FPU)
- `clk8_en_p/n`  = 8.125 MHz (SCC, IWM, VIA register strobes)

Where each block currently lives:

| Block | Clock today | After PLL → 31.3344 MHz (no logic change) |
|---|---|---|
| TG68K CPU | `clk16_en` (16.25 MHz) | **15.6672 MHz** ✅ |
| FPU | `clk16_en` (16.25 MHz) | **15.6672 MHz** ✅ |
| SCC | `clk8_en` (8.125 MHz) | **7.8336 MHz** ✅ |
| IWM | `clk8_en` (8.125 MHz) | **7.8336 MHz** — matches MAME's *internal* GCR rate, but spec input is C15M |
| VIA timer | 783360 Hz accumulator vs `SYS_CLK_HZ=32500000` (`rtl/dataController_top.sv:308–331`) | Need to update `SYS_CLK_HZ` to `31334400` |
| ASC | raw `clk_sys` (32.5 MHz) | becomes 31.3344 MHz — still ~2× too fast vs spec |
| SCSI 5380 | async on CPU strobes | unchanged ✅ |
| ADB | inside VIA1 | unchanged ✅ |

So the PLL change alone fixes CPU, FPU, SCC, VIA register strobes, and VIA
timer (after one constant update). IWM and ASC need an explicit decision.

## 2a. Verilator regression harness (used after every step)

Run the sim from the `verilator/` directory so ROM/disk paths resolve
(see `feedback_sim_cwd`). Redirect once and grep the log; don't re-run for
each different grep (`feedback_sim_output`). Use `--stop-at-frame N`, not
`--frames N` (`feedback_verilator_flags`).

Known-good boot milestones on the current (32.5 MHz) baseline:

| Frame | Milestone |
|---|---|
| ~150 | Checkerboard startup screen draws |
| ~430 | Mouse cursor appears |
| ~620 | Floppy disk icon appears (IWM probe succeeded) |

A clocking change passes the regression if all three milestones still land
within ~10 frames of these targets. Because the boot logic is driven by VBL
count (VIA timer), not wall-clock, frame numbers should stay stable across
the PLL retune; large drift means something was implicitly tuned to 32.5 MHz.

## 3. Implementation plan (in the requested order)

### Step 1 — Re-tune master PLL to 31.3344 MHz

**Goal:** make `clk_sys` exactly 2 × C15M so all existing clock-enables become
historically correct without any logic edits.

Files:
- `rtl/pll/pll_0002.v` (and `rtl/pll.v` / `rtl/pll.qip` / `rtl/pll/pll_0002.qip`):
  - `output_clock_frequency1`: `32.500000 MHz` → `31.334400 MHz`
  - `output_clock_frequency0`: `65.000000 MHz` → `62.668800 MHz` (keep the
    existing 2:1 ratio with `clk_sys` so SDRAM phase relationship is preserved;
    well within IS42S16160 spec).
  - Regenerate the PLL through Qsys / megawizard rather than hand-editing.
    Hand-edit only if Qsys is unavailable, and confirm the resulting fractional
    M/N/C dividers in Quartus's PLL summary.
- `rtl/dataController_top.sv:309`: `SYS_CLK_HZ = 32'd32500000` → `32'd31334400`.
- `LBMacTwo.sv`:
  - line ~239 comment "Mac II always runs at 16MHz" → "15.6672 MHz".
  - line ~252 comment "32.5MHz, 180°" → "31.3344 MHz, 180°".
  - line ~546 `~8 seconds at 32.5MHz` watchdog — recompute: at 31.3344 MHz,
    8 s = 250,675,200 ticks; the existing `28'hFFFFFFF` (~268 M) becomes ~8.57 s,
    acceptable.
  - line ~616 `~8us at 32.5 MHz`: `260` ticks → `251` ticks for 8 µs at the new
    rate. Update the comparator constant.
- `rtl/asc.sv:9` comment "32.5 MHz system clock" → "31.3344 MHz" (no logic
  change yet — Step 3 handles ASC properly).
- `rtl/dataController_top.sv:3` comment "32.5 MHz pixel clock" → "31.3344 MHz".

Verilator side:
- `verilator/sim_main.cpp:1178`: `clk_sys_freq = 32500000` → `31334400`.
- `verilator/sim/sim_serial.cpp:224, 325`: same constant in two baud-rate
  approximators.
- Adjust the clock-toggle period in `sim_main.cpp` so simulated wall-clock
  matches the new rate (half-period ≈ 15.96 ns).
- `verilator/sim.v`: any literal `32.5`/`16.25`/`8.125 MHz` comments.

**Verification after Step 1 — verilator boot regression (mandatory):**

Run the sim from `verilator/` (see `feedback_sim_cwd`) with `--stop-at-frame`
and screenshot at the known good milestones:

| Frame | Expected on baseline 32.5 MHz | Must still be true after Step 1 |
|---|---|---|
| ~150 | Checkerboard startup screen drawn | Screen draws by frame ~150 (±a few) |
| ~430 | Mouse cursor appears | Cursor appears by frame ~430 |
| ~620 | Floppy disk icon appears | Floppy appears by frame ~620 |

Because Step 1 only changes the *rate* of `clk_sys`, the per-frame boot
progress (which is driven by VBL count from VIA, not wall-clock) should land
on the same frame numbers. A noticeable drift here means something downstream
was implicitly tuned to 32.5 MHz — investigate before moving on.

Additional checks:
- Quartus: confirm timing closes on `clk_sys` (relaxes from 30.77 ns → 31.92 ns,
  should be easier).
- Serial-baud reports from `verilator/sim/sim_serial.cpp` should sit at exact
  rates (e.g. 9600 → ~9600.0 instead of slightly fast).
- VIA 60 Hz VBL interrupt drift: target is 0; previously was ~3.6 % fast.

### Step 2 — Re-clock IWM to true C15M input (15.6672 MHz)

**Goal:** drive the IWM at the spec input rate so its own /2 GCR phase divider
runs at 7.8336 MHz, matching real hardware and MAME's `IWM(config, m_fdc, C15M)`.

Today IWM rides `clk8_en` (post-Step-1: 7.8336 MHz — the *already-divided* rate).
We want IWM's `cep/cen` to ride `clk16_en` (15.6672 MHz) and let the IWM's
internal state machine do the /2.

Files:
- `rtl/dataController_top.sv` (IWM instantiation, around line 838):
  ```
  .cep(clk8_en_p),    →   .cep(clk16_en_p),
  .cen(clk8_en_n),    →   .cen(clk16_en_n),
  ```
- `rtl/iwm.v`: audit the internal state machine. If it currently treats one
  `cen` pulse as one 7.8336 MHz GCR phase, add a divide-by-2 toggle gated on
  `cen` so the GCR phase rate stays at 7.8336 MHz. Otherwise floppy timing
  doubles and 800K GCR streams will fail.
  - Look at the bit-cell counters around `rtl/iwm.v:273` and `:299` (the two
    `if(cen)` blocks). The simplest fix is a `reg phase` flipped on every `cen`
    and gating the existing logic with `cen & phase`.

**Verification after Step 2 — verilator boot regression (mandatory):**

IWM is on the critical boot path for the floppy-icon milestone. Re-run the
same checkpoint table:

| Frame | Check |
|---|---|
| ~150 | Screen still draws |
| ~430 | Mouse still appears |
| ~620 | **Floppy icon still appears** (this is the IWM-sensitive milestone) |

If the floppy icon stops appearing, or appears much later than frame ~620, the
internal /2 GCR divider added to `rtl/iwm.v` is wrong — bit cells are doubled
and the ROM's "is there a disk?" probe is timing out. Roll back the `cep/cen`
move and re-audit the IWM state machine before retrying.

Additional checks:
- Mount `Disk605.dsk`; observe IWM bit-cell timing in `sim_main.cpp` trace —
  bit cells should remain ~2 µs (500 kbit/s outer zone) after the change.
- Hardware: boot from floppy; confirm 800K GCR read still works (System 6
  install floppy is a good torture test).

### Step 3 — Re-clock ASC to C15M (15.6672 MHz)

**Goal:** match MAME's `ASC(config, m_asc, C15M)`. Today ASC clocks off raw
`clk_sys`, which is ~2× too fast and skews the internal sample-rate dividers
that produce 22.257 kHz / 11.127 kHz.

Two viable approaches:

**Option A — add a clock-enable input to `rtl/asc.sv` (preferred).**
- New port `input clk_en`. Gate every `always @(posedge clk)` body with
  `if (clk_en) ...`.
- Wire `.clk_en(clk16_en_p)` at the instantiation in
  `rtl/dataController_top.sv:214`.
- Audit ASC's internal sample-rate divider math. The register at $807
  (`asc_clock_rate`) selects 22.257 kHz vs 11.127 kHz. With a 15.6672 MHz
  effective clock the divider becomes 15667200 / 22257 ≈ 704. Confirm the
  existing constant against this and adjust if it was tuned for 32.5 MHz.

**Option B — derive `clk_asc` as a true gated clock.** Not recommended — adds
a derived clock domain and complicates timing closure.

**Option C (chosen for this step) — leave `clk` ungated at 31.3344 MHz; just
retune the SAMPLE_DIV constants.** See deviation note immediately below.

Files (Option C — what we actually did):
- `rtl/asc.sv`: SAMPLE_DIV_22K 1460 → 1408, SAMPLE_DIV_11K 2921 → 2817,
  comment block updated; `clk` port comment updated.

#### Deviation note — chose Option C over Option A

When implementation began, a closer read of `rtl/asc.sv` exposed two hazards
in Option A that the plan above had not accounted for:

1. **M10K block-RAM inference at risk.** The four `always @(posedge clk)`
   blocks at lines 37/43/53/57 are simple-read-write patterns that Quartus
   recognises as M10K inference templates. Wrapping them in
   `if (clk_en) begin ... end` typically pushes synthesis to LE/flop-array
   storage instead — silent breakage that only shows up on hardware.

2. **CPU read pipeline latency.** Lines 161–165 implement a 2-cycle read
   pipeline (`cpu_read_d → cpu_read_d2 → addr_d`) sized against `clk_sys`.
   Halving the effective rate via `clk_en` doubles that latency to 4
   sys-clocks, which is roughly the length of a single CPU bus cycle on
   this core — CPU register reads risk landing just after data goes invalid.

Option C avoids both risks. External behavior is observationally identical:

| | Option A (spec) | Option C (chosen) |
|---|---|---|
| ASC internal clock | C15M = 15.6672 MHz | 2 × C15M = 31.3344 MHz |
| Audio sample rate (22 kHz mode) | 22,257 Hz exact | 22,254 Hz (0.01 % low) |
| Audio sample rate (11 kHz mode) | 11,127 Hz exact | 11,123 Hz (0.03 % low) |
| M10K block-RAM inference | At risk | Preserved |
| CPU read pipeline timing | At risk | Preserved |
| Lines changed | ~10–15 | 2 + comment |

**Revisit later if any of these become true:**
- We add cycle-accurate ASC FIFO IRQ timing tests that demand strict C15M
  internal pacing.
- We see audio pitch drift complaints traceable to the 0.01 % residual.
- We need ASC behavior identical to a MAME trace at sub-sample granularity
  for regression diffing.

Files (Option A — kept here for future reference if we revisit):
- `rtl/asc.sv` (add `clk_en` port, gate all FSM/edge logic, resize the
  CPU read pipeline, verify M10K inference after the change).
- `rtl/dataController_top.sv` ASC instantiation (add `.clk_en(clk16_en_p)`).
- `verilator/sim.v` mirror.

**Verification after Step 3 — verilator boot regression (mandatory):**

ASC isn't on the boot-icon critical path, but the boot beep + ADB-vs-ASC
interaction means we still re-run the full checkpoint table:

| Frame | Check |
|---|---|
| ~150 | Screen still draws |
| ~430 | Mouse still appears (ADB SR not starved by ASC FIFO) |
| ~620 | Floppy icon still appears |

If the mouse milestone slips, suspect the ASC `clk_en` gating is starving the
SR shift-in path again (see commit `ccc7624`); the fix is in the ASC FIFO IRQ
timing, not in re-clocking back up.

Additional checks:
- ASC FIFO playback at 22.257 kHz: feed a known WAV via Sound Manager, capture
  `ascAudioLeft/Right`, confirm sample rate is exact (not ~3.6 % off).
- Boot chime pitch should be correct, not high.

### Step 4 — Mirror everything in verilator

Already touched in Steps 1–3, but consolidate here:
- `verilator/sim.v`: copy `LBMacTwo.sv` clocking and ASC port additions.
- `verilator/sim_main.cpp`: `clk_sys_freq`, half-period, any literal Hz values.
- `verilator/sim/sim_serial.cpp`: the two `32500000` baud-rate constants.
- Re-run the sim regression set (boot to Finder, run the FPU corpus, run the
  serial/MIDI tests) and confirm reported rates match the spec table above.

### Step 5 — Documentation / comment sweep

- Update `CLAUDE.md` if it mentions 32.5 MHz / 16 MHz anywhere (it currently
  does in the "CPU Architecture" memory note — that lives in `MEMORY.md`, not
  the repo, but flag it).
- Update inline comments referencing the old rates in `rtl/addrController_top.v`,
  `rtl/asc.sv`, `rtl/dataController_top.sv`, `LBMacTwo.sv`.

## 4. Explicit non-goals

- **Do not** add a 22.5792 MHz secondary oscillator for ASC — wrong machine.
- **Do not** drive SCC PCLK from a /8.5 fractional divider — PCLK is C7M.
- **Do not** restructure NuBus slot clocking — current synchronous-to-`clk_sys`
  approach is sufficient for emulation; the real machine's 10 MHz slot clock
  isn't modelled cycle-accurately in MAME either.
- **Do not** move ADB onto its own clock domain — it's a VIA1 SR peripheral.

## 5. Risks & roll-back

- **SDRAM timing:** dropping `clk_mem` from 65 MHz to 62.6688 MHz only *relaxes*
  the controller's setup/hold budget. If timing fails to close it's almost
  certainly an unrelated logic change, not the clock.
- **IWM /2 divider in Step 2** is the highest-risk edit. Keep the change behind
  a short branch and have a known-good 800K image (`Disk605.dsk`) ready as
  smoke test.
- **ASC rate constants in Step 3** — if the sample-rate divider was implicitly
  tuned for 32.5 MHz instead of 31.3344 MHz, audio will pitch up/down ~3.6 %
  until corrected.

Roll-back at any step is a one-commit revert; PLL, IWM, and ASC changes are in
separate files and can be reverted independently.
