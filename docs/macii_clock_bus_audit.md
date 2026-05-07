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

A later no-media recheck narrowed the mismatch. The drive queue now matches
MAME at the queue-loop PC:

```text
MAME frame 350:      PC=408061F2 $030A=00002F70 next=00000000 +06=0001 +08=FFFB
Verilator frame 429: PC=408061F2 $030A=00002F70 next=00000000 +06=0001 +08=FFFB
```

The first apparent divergence in adjacent low memory was not the root cause.
`$09FA` is `TempRect` and `$0A02` is `OneOne`; the low-memory table used for
that identification has been saved at `docs/external/mac_lowmem_osdata.html`.
A short Verilator sample saw `TempRect` before QuickDraw finished updating it,
but the later SCSI-timeout run settles to the same values as MAME:

```text
$09FA=0800 $09FC=0000 $09FE=0100 $0A00=0283 $0A02=0001
```

At the timeout frame the better comparison is:

```text
Verilator frame 459: $09FA=0800 $09FC=0000 $09FE=0100 $0A00=0283 $0A02=0001
                     $0B22=FC $0B2E=80 $0C2F=00 queue=2F70 A4_60=8001 A4_61=01
MAME frame 450:      same low-memory bytes, queue, and SCSI driver table
```

The SCSI-trap evidence has been narrowed further. Verilator's first
`$408266A4` hit is not yet proof of a late no-media failure; it is the ROM's
early SCSI-manager/PRAM setup path:

```text
frame 390 pc=408266A4 caller path=40826660 -> A815
PRAM boot word=4F48  B0C2F=00  B0B2E=80
```

MAME's persistent RTC image has the same bytes (`mame/nvram/macii/rtc` starts
`00 80 4F 48`). The existing MAME Lua taps are installed by
`-autoboot_script`, which is too late to observe that early ROM setup. Their
zero-hit result through frame 450 therefore only says that MAME does not
re-enter `$408266A4-$40826990` after the Lua script starts. The next focused
trace should compare post-initialization control flow: does Verilator return
from the early SCSI-manager timeout and reach the same no-media Time Manager
queue loop, or does it remain delayed enough that we are comparing different
boot phases?

A frame-502 Verilator trace answers part of that question: Verilator does reach
the Time Manager interrupt service path after early SCSI setup. That path is
`$4080622E-$40806282`, returns through `RTE` at `$40806282`, and resumes
foreground execution at `$40826CC6`, the SCSI timeout loop. MAME's sampled
`$408061F2` is a different Slot VBL path: the queue walker subroutine
`$408061E4-$4080622C`, with stack return `$4080649A` back to the caller at
`$40806486`. Low memory identifies `$0D0C/$0D10/$0D14/$0D28` as
`SlotVBLQ`/`ScrnVBLPtr`/`SlotTICKS`/`JVBLTask`, and MAME is servicing slot `$E`
(`D0=14`) for the matched `m2hires` card. The card model had a real one-scanline
timing mismatch: MAME raises the m2hires slot IRQ at `(m_vres - 1, 0)`, while
the RTL raised it at `v_cnt == V_RES`. The RTL now pulses the slot VBL IRQ at
`V_RES - 1`; after rebuilding, recheck whether Verilator enters `$408061E4`
with return `$4080649A`, or whether its foreground has already diverged into
the SCSI timeout loop. `make` passed after this change, but the first
post-change `--stop-at-frame 520` verification run timed out after 300 seconds.

## Working Hypothesis

This does not currently look like a bad 68020 opcode implementation. The ROM is
executing deep, repeatable Mac II code and reaches the same broad subsystems as
MAME. The stronger evidence is for an effective clock/bus handshake problem
that changes which foreground or Time Manager callback runs: the ROM delay
calibration is wrong, non-VIA I/O is still entangled with a Plus/SE-style
synchronous bus rule, and no-floppy boot reaches the SCSI trap path even though
the settled low-memory boot state matches MAME.

Next useful audit targets: compare the Time Manager node/callback path around
`$408061E4-$4080622C`, get an earlier MAME debugger-side trace that starts at
reset rather than `-autoboot_script`, and isolate the VPA/DTACK rule by adding a
debug mode that logs every VPA-completed non-VIA access.
