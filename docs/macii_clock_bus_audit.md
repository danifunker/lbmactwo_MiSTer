# Mac II Clock and Bus Audit

This note captures the current audit against MAME's Mac II model while debugging
the no-floppy boot path.

## Reference Clocks

MAME's `macii` machine config uses:

- CPU: 68020 PMMU at `C15M = 15.6672 MHz`.
- ASC: `C15M`.
- IWM: `C15M`.
- SCC: `C7M = C15M / 2 = 7.8336 MHz`, with 3.6864 MHz channel clocks.
- VIA1 and VIA2: `C7M / 10 = 783.36 kHz`.
- Matched NuBus `m2hires` video card: 30.24 MHz pixel clock, 896x525 timing.

The FPGA/sim top still has Mac Plus/SE-era clock structure:

- PLL/sys clock is 32.5 MHz.
- `status_turbo` is forced on for Mac II; TG68K gets `clk16_en_*`, so the
  nominal CPU enable rate is 16.25 MHz, not 15.6672 MHz.
- VIA timer countdowns are separately rate-gated to 783.36 kHz.
- The old internal compact-Mac `videoTimer` still exists for memory arbitration
  and legacy signals, while visible output and frame probes use the NuBus
  high-resolution card.

The 16.25 MHz vs 15.6672 MHz difference is only about 3.7%, so it does not
explain the ROM delay calibration mismatch by itself. MAME stores `$0D00=$0A3B`
and `$0DA6=$0417`; this core naturally stores about `$054D/$0196`. That says
the ROM's VIA-heavy calibration loop sees a much different effective
CPU/VIA/bus-access ratio than MAME.

## Mac Plus/SE Assumptions Still Present

The design still has several inherited compact-Mac assumptions that are valid
only if they have been deliberately adapted:

- A 68000-style 16-bit CPU bus wraps TG68K in 68020 mode. This can be
  functionally adequate, but it is not a real 68020 DSACK/SIZ bus.
- The VPA/DTACK wrapper still treats the broad low-24-bit `$Fxxxxx` region as a
  synchronous bus region. After HMMU translation, Mac II I/O lands at
  `$50Fxxxxx`, so this broad rule also catches SCC/SCSI/IWM/ASC, not just VIA.
- MAME only applies special CPU/VIA synchronization to VIA accesses. SCC, SCSI,
  IWM, and ASC are normal device handlers in the Mac II map.
- There are two Mac II VIAs, VIA2 controls RAM-size/GLUE state and NuBus IRQ
  routing, and VIA2 PB7 chains timer output into VIA1 CA1. This is
  fundamentally different from Plus/SE VIA usage.
- Mac II video is not the compact-Mac framebuffer. The active boot comparison
  uses a NuBus video card in slot E, and its VBL interrupt path goes through
  NuBus/VIA2 rather than the old onboard video path.

## Experiment: Narrowing VPA

I tested narrowing VPA to only autovectors and VIA/VIA2, with DTACK for selected
RAM/ROM/SCC/SCSI/IWM/ASC. That is closer to the high-level MAME model, but the
simple change was not safe: Verilator fell into a corrupted exception/vector
path around frame 160, before the no-floppy boot path. The source was restored.

This means the broad VPA rule is either masking another bus/error-frame
dependency or the DTACK replacement needs finer handling than a direct swap.
Treat it as a real suspect, not a validated fix.

## Current No-Floppy Baseline

Matched-card MAME with no floppy media reaches the no-media ROM loop by about
frame 320:

```text
PC=408061F2 D0=00000014 A3=50F10000
```

Verilator, with no floppy media and MAME delay constants forced after
calibration, still reaches the SCSI timeout path instead:

```text
PC=40826CC6 D0=00000000 A3=50F10000
```

The external floppy mechanism-present fix is still considered correct: MAME
configures `add_35_nc` for the external connector, meaning the connector exists
but no external drive mechanism is installed by default.

## Working Hypothesis

This does not currently look like a bad 68020 opcode implementation. The ROM is
executing deep, repeatable Mac II code and reaches the same broad subsystems as
MAME. The stronger evidence is for an effective clock/bus handshake mismatch:
the ROM delay calibration is wrong, non-VIA I/O is still entangled with a
Plus/SE-style synchronous bus rule, and no-floppy boot spends too much time in
timeout paths instead of reaching MAME's no-media loop.

Next useful audit target: isolate the VPA/DTACK rule by adding a debug mode that
logs every VPA-completed non-VIA access, then convert one device class at a time
instead of changing the whole `$Fxxxxx` region at once.
