# MAME vs. Verilator Mac II Boot Comparison

This note captures the current boot comparison between the local MAME `macii`
run and the Verilator simulation. The goal is to keep the remaining boot work
focused on the first real divergence instead of chasing earlier devices that
are no longer blocking progress.

## Current Status: 2026-05-04

The first confirmed divergence was the Mac II 2MB RAM GLUE mapping, not SCC.
MAME dynamically remaps RAM from VIA2 PA7:6 while the ROM probes `FF/BF/7F/3F`.
Before the first RAM fix, Verilator used a static 2MB wrap and falsely accepted
the `BF` layout; the ROM then read VIA2 as `$BF`, loaded `A2=$00800000`, wrote
`$00200000`, and aliased that write to address zero.

The second RAM-test divergence was subtler: the VIA data bus returned the real
8-bit VIA value on D15:8 but hardcoded D7:0 to `$EF`. MAME mirrors VIA reads
onto both 68000 byte lanes. The ROM does a wider VIA2 ORA read at `$4080071E`;
Verilator returned `$3FEF`, so the ROM wrote `$EF` back to VIA2 ORA at
`$40800726`. That drove PA7:6 to `11`, made the later RAM-test orchestrator
load the `$04000000` table entry, and sent the boot down the ASC diagnostic
path. The RTL now mirrors VIA and VIA2 reads onto both lanes.

After this fix, the focused RAM-test probe matches MAME at the important
checkpoint: VIA2 reads `$3F3F`, ORA stays `$3F`, the RAM-test orchestrator
loads `A2=$00100000`, `D7=4`, and the pattern test returns with `D6=0` instead
of entering `$40802CDC`.

ASC is not the current blocker. Verilator now takes the same normal ASC entry
path as MAME (`$408000D0 -> $40805E4A`, `D7=2`) and reaches later ROM code.
By the current frame probes, MAME is near `$40826CA8` around frame 280 and
Verilator is near `$40826CCA` at frame 300. The frame-300 Verilator screenshot
is still a vertical stripe pattern with no cursor, so the next debugging focus
should be the post-ASC video/NuBus/SCSI boot path rather than RAM or ASC.

## Runs Compared

MAME was first run from the local checkout with the working Mac II ROM and its
default NuBus card layout:

```sh
SDL_VIDEODRIVER=dummy ./mame macii -rompath roms -video none -sound none -nothrottle -skip_gameinfo -autoboot_script macii_scc_probe.lua
```

Verilator was run headless with CPU/VIA trace noise disabled:

```sh
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug --screenshot 1000 --stop-at-frame 1200
```

## Reproducing The Matched MAME Run

For future debugging, use the matched-card command. Do not use plain
`./mame macii` for video comparisons, because the default MAME machine installs
`mdc824` in slot 9 while the FPGA core currently models the Apple Macintosh II
High Resolution Video Card in slot E.

The matched setup is:

- Keep the Mac II system ROM in `mame/roms/macii.zip`.
- Put the High Resolution Video Card declaration ROM at
  `mame/roms/nb_m2hr/341-0660.bin`.
- Use `releases/341-0660.bin` or `releases/boot1.rom` for that file; both are
  the expected 8 KiB image with SHA1
  `37c59f38ae34021d0cb86c2e76a598b7e6077c0d`.
- Remove MAME's default slot-9 card with `-nb9 ""`.
- Install the matching card in slot E with `-nbe m2hires`.

From the repository root:

```sh
mkdir -p mame/roms/nb_m2hr
cp releases/341-0660.bin mame/roms/nb_m2hr/341-0660.bin
cd mame
SDL_VIDEODRIVER=dummy ./mame macii -rompath roms -video none -sound none -nothrottle -skip_gameinfo -nb9 "" -nbe m2hires -autoboot_script ../tools/mame/macii_scc_probe.lua
```

Expected matched-card SCC probe summary at 1200 frames:

```text
MAME_SCC_SUMMARY frames=1200 reads=1159 writes=71 poll_hits=0
```

The important part is `poll_hits=0`: the matched MAME run does not enter the
old Verilator `40803280-40803310` SCC poll window.

After confirming that `releases/341-0660.bin` / `releases/boot1.rom` has the
same SHA1 that MAME expects for `nb_m2hr`:

```text
37c59f38ae34021d0cb86c2e76a598b7e6077c0d
```

the ROM was installed locally for MAME at:

```text
mame/roms/nb_m2hr/341-0660.bin
```

Then MAME was re-run with the default slot-9 `mdc824` removed and the same
High Resolution Video Card placed in slot E:

```sh
SDL_VIDEODRIVER=dummy ./mame macii -rompath roms -video none -sound none -nothrottle -skip_gameinfo -nb9 "" -nbe m2hires -autoboot_script macii_scc_probe.lua
```

For frame-to-frame comparison, use the generic frame probe. It prints the
current ROM PC at a fixed interval and exits at the selected frame:

```sh
MAME_FRAME_INTERVAL=20 MAME_STOP_FRAME=120 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -seconds_to_run 999 -nb9 "" -nbe m2hires \
  -autoboot_script ../tools/mame/macii_frame_probe.lua
```

Current matched-card frame landmarks:

```text
MAME frame 9:   PC=40805F48  ASC self-test
MAME frame 40:  PC=40805F44  ASC self-test
MAME frame 60:  PC=40803778  ASC test completed
MAME frame 70:  PC=40804340  NuBus declaration ROM scan
MAME frame 80:  PC=40806DDE
MAME frame 120: PC=40806DD8
```

After the VIA read-lane fix, Verilator leaves the ASC region. At frame 180,
`+asc_entry_debug` reports the normal path:

```text
[ASC_ENTRY] hit=0 pc=408000d0 ... d7=00000002 ...
[ASC_ENTRY] hit=1 pc=40805e4a ... d7=00000002 ...
[ASC_ENTRY] hit=2 pc=40805e70 ... a4=40805f78 ...
```

At frame 300, Verilator stops at `PC=$40826CCA`; matched MAME reaches the same
ROM neighborhood around frame 280 (`PC=$40826CA8`) and then enters slot/video
declaration code again by frame 296.

## Current Observations

| Checkpoint | MAME `macii` | Verilator |
| --- | --- | --- |
| 300-frame progress | Matched `nbe m2hires`: reaches `PC=40826CA8` around frame 280 and `PC=00004606` by frame 300 | Reaches `PC=40826CCA` at frame 300 |
| RAM test | VIA2 reads `$3F3F`, `A2=$00100000`, `D7=4`, `D6=0` | Matches after VIA read-lane fix |
| ASC | Normal path `$408000D0 -> $40805E4A`, `D7=2`, `A4=$40805F78` | Matches normal path; no longer enters `$40802CDC -> $40805E66` diagnostic path |
| SCC | Early SCC status loop reads `0x54` at `PC=408005D2`; no long `408032xx` poll | The previous `408032AC` SCC-style stall was a downstream symptom of earlier error paths |
| Video | Matched run uses `m2hires` in slot E with the same `341-0660.bin` ROM | Verilator models an `m2hires`-like card in slot E; screenshot at frame 300 is vertical stripes, with no cursor |
| MAME SCC poll window | `40803280-40803310` was never entered in the 1200-frame MAME probe | If Verilator returns to this window, that is a real divergence from the MAME boot path |

The current evidence says SCC, RAM sizing, and ASC are not the first remaining
blockers. The active question is why the visible boot has not reached a cursor
despite the ROM reaching the same later neighborhood as matched MAME.

## Important Comparison Mismatch

The default MAME Mac II configuration is not using the same video card that this
FPGA core is currently modeling.

In `mame/src/mame/apple/macii.cpp`, MAME installs:

```cpp
NUBUS_SLOT(config, "nb9", "nubus", mac_nubus_cards, "mdc824");
```

That is the Macintosh Display Card 8/24 in slot 9. Our core currently models an
Apple Macintosh II High Resolution Video Card-like device in slot E
(`rtl/nubus/nubus_video_highres.sv`) with declaration ROM `boot1.rom`.

That means a normal MAME boot proves the ROM can boot with MAME's default machine
model, but it is not an apples-to-apples video-card comparison. The matched run
using `-nb9 "" -nbe m2hires` fixes that layout mismatch enough for SCC/ROM
milestone comparison.

## Device Model Gaps That Still Matter

### VIA1 / ADB Port B Divergence

This is the strongest current suspect for "no cursor yet".

With the matched MAME run using the `nbe:m2hires` card, MAME reaches its first
slot-E declaration ROM access at frame 69, PC `$408043F4`, address
`$FEFFFFFC`. The current Verilator run to frame 120 does not issue NuBus video
accesses and stops at PC `$4080DE3E`, in the ADB/VIA1 bit-bang loop.

The generic `via6522.sv` port-B read path matches MAME's important behavior:
external input bits are selected where DDRB=0, ORB output bits are selected
where DDRB=1, and PB7 is overridden by Timer 1 when ACR enables it. The mismatch
was in Mac II VIA1 glue:

- MAME `macii_state::via_in_b()` only supplies PB3 (`!m_adb_irq_pending`) and
  PB0 (RTC data); other external PB bits are zero.
- The old FPGA glue forced PB7 high and forced PB6-PB4 high for `machineType`,
  so ORB reads in the ADB loop returned high-nibble values around `$70`.
- The corrected FPGA glue supplies only PB3 and PB0 as external inputs for
  Mac II. Output pins PB1/PB2/PB4/PB5 still read back through the VIA DDR/ORB
  mux, which is the FPGA equivalent of the real pin-level behavior.

After that fix, the high-nibble mismatch is gone, but the boot still stops at
`$4080DE3E`. That leaves the ADB HLE/PIC semantics, not the generic VIA core, as
the next likely source of divergence. A test that removed the Data1 completion
assertion from the ADB HLE did not improve the final PC and was reverted.

### NuBus Video Card

This remains important once the boot reaches the Slot Manager probe path, but it
is no longer the first blocker.

MAME's `nubus_m2hires.cpp` maps the High Resolution Video Card like this:

| Local card offset | MAME behavior |
| --- | --- |
| `0x00_0000-0x07_FFFF` | VRAM, mirrored every `0x100000` through the slot |
| `0x08_0000-0x08_FFFF` | TFB registers, write-only |
| `0x09_0000-0x09_FFFF` | VBL status reads and Bt453 RAMDAC writes |
| `0x0A_0000-0x0A_FFFF` | VBL interrupt control writes |
| declaration ROM | `install_declaration_rom("declrom", true)` mirrors the ROM across the slot |

Our `nubus_video_highres.sv` is close to that map, but this is still the highest
risk area because the boot symptom is video-specific. Things to validate next:

- Use the matched MAME command above for comparisons instead of the default
  `mdc824` run.
- Log Verilator NuBus video writes by category: declaration ROM reads, TFB
  register writes, RAMDAC writes, VBL status reads, VBL control writes, and VRAM
  writes.
- Confirm the 16-bit bus adaptation of MAME's 32-bit inverted/swap-endian TFB
  register writes. A halfword ordering mistake could leave `SOFTRESET` clear,
  choose the wrong mode, set the wrong stride, or point display fetches at blank
  VRAM.
- Confirm RAMDAC byte lane selection. MAME writes a 32-bit inverted value and
  uses `offset & 1`; our 16-bit path currently consumes `data_in[15:8]`.
- Confirm VBL IRQ clear/enable behavior. MAME lowers the slot IRQ when the
  enable/ack offset is written.

### NuBus IRQ / VIA2 CA1 Edge Behavior

MAME has an explicit `m_via2_ca1_hack` in `macii_state::nubus_slot_interrupt()`
to re-trigger VIA2 CA1 when NuBus IRQ state changes. Our FPGA path is a direct
separate signal path, not a tri-state bus, so the implementation does not need
to look structurally like MAME. It does still need equivalent edge/level
semantics at VIA2 CA1. A missed video VBL IRQ acknowledge could keep the ROM's
video/card initialization from advancing cleanly.

### SCSI and ADB

MAME has complete device models for NCR53C80 SCSI with the Mac SCSI helper,
ADB modem/microcontroller behavior, and RTC/IWM details. Our models are simpler.

The current Verilator divergence is in the ROM's NCR5380 probe around
`$408268D8-$40826920`. The matched-card MAME run did not enter this ROM path in
the same frame window, while Verilator repeatedly arbitrates on the NCR5380:

- `move.b #$01,$50F10020` must be a high-byte write to NCR5380 mode register 2.
  The FPGA bus adapter was incorrectly using `_cpuLDS` for SCSI writes, so the
  ROM's MR.ARB write was ignored.
- SCSI byte reads are high-lane reads like MAME's `scsi_r() << 8`; mirroring the
  returned byte on both 68000 lanes avoids stale low-lane filler confusing TG68K
  byte read timing.
- MAME's NCR5380 only drives the SCSI data bus when DBUS is asserted or
  arbitration is active. The Verilog now models the current data register as an
  OR of active initiator and target drivers instead of a default `0x55` value.
- With those fixes, the ROM sees ICR `0x40/0x48` instead of `0x00` and gets past
  the original tight `btst #6,$50F10010` loop.

Headless Verilator can now mount a SCSI image explicitly:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --scsi0 ../releases/Disk605.dsk --stop-at-frame 760
```

Target index 0 is SCSI ID 6, matching MAME's default Mac II hard disk connector
(`scsi:6`). `Disk605.dsk` is an 800 KiB image and MAME does not accept `.dsk`
as a SCSI hard disk image, so this is useful for exercising the RTL SCSI target
but is not yet a perfect MAME hard-disk comparison.

With `--scsi0 ../releases/Disk605.dsk`, the ROM selects target 6 and issues:

```text
New command on target 6: 08 00 00 00 01 00 00 00 00 00
```

That is READ(6), LBA 0, length 1 block. By frame 650 the target has completed
and released BSY (`t0_phase=0`, `tbsy=00`); by frame 760 the CPU has left the
SCSI path and is at `PC=40801652`. This rules out SCSI as the current terminal
blocker in the mounted-image run.

By frame 1200, Verilator is back in the SCSI selection helper at
`PC=40826CC6`, but it is selecting `odr=81`, which is initiator ID 7 plus target
ID 0. No RTL target exists at ID 0, so this is the ROM paying a no-device
timeout, not target 6 holding BSY. The SCSI state at that stop is idle:
`t0_phase=0`, `tbsy=00`, `req=0`.

MAME with the same video card and `Disk605.dsk` mounted as a floppy:

```sh
MAME_FRAME_INTERVAL=100 MAME_STOP_FRAME=1200 SDL_VIDEODRIVER=dummy ./mame macii \
  -rompath roms -video none -sound none -nothrottle -skip_gameinfo \
  -nb9 "" -nbe m2hires -flop ../releases/Disk605.dsk \
  -autoboot_script ../tools/mame/macii_frame_probe.lua
```

reaches NuBus declaration ROM access around frames 70 and 296, then alternates
through `PC=408061F2` and `PC=4080DE3E` by frame 1200. That is still ahead of
the current Verilator run, but it is not an exact disk-path match because MAME
is using the `.dsk` through IWM/floppy while Verilator is exercising it as a
temporary SCSI target.

The Verilator wrapper now supports the same floppy path:

```sh
cd verilator
./obj_dir/Vemu --headless --no-cpu-trace --no-via-debug \
  --floppy0 ../releases/Disk605.dsk --stop-at-frame 1200
```

The index mapping is important: index 1 is the NuBus declaration ROM, while
indexes 2 and 3 are the internal and external floppy images. This matches
`LBMacTwo.sv`; the older Verilator wrapper treated index 1 as the internal
floppy and could not do a clean same-disk comparison with MAME.

The ADB/VIA work is still relevant, but it is no longer the most recent observed
terminal blocker.

### RAM Size / GLU Behavior

MAME exposes RAM size and NuBus IRQ state through VIA2/GLU behavior. Our core has
flat RAM plus simplified RAM-size signaling. If the boot later fails around heap,
MMU, or Slot Manager allocation, this should be revisited. It is not the leading
explanation for the current no-cursor symptom.

### I/O Mirror Semantics

MAME maps Mac II I/O at `0x500xxxxx` with a `0x00f00000` mirror. The current FPGA
decoder uses the `0x50Fxxxxx` path produced by the HMMU for 24-bit ROM I/O. That
matches the current observed boot path, but any future full-MMU or alternate ROM
path should verify whether `0x500xxxxx` aliases also need to be accepted.

## Current Conclusion

The boot has moved past the earlier ASC failure, the old SCC diagnostic/BERR
path, and the first mounted-image SCSI READ(6). SCSI was a real blocker while
the ROM could not write/read the NCR5380 correctly and while the headless sim
could not mount a target, but the latest mounted run no longer dies there.

The next debugging step is to use `--floppy0 ../releases/Disk605.dsk` for the
direct MAME comparison. A real MAME-compatible SCSI hard disk image would still
be useful later for validating the SCSI target path.

## 2026-05-04 Direct-Floppy Update

The direct MAME/Verilator floppy comparison now uses the same slot-E `m2hires`
card and `Disk605.dsk` as a floppy in both emulators.

Early IWM behavior matches closely. Both runs perform the same ROM IWM probe:
reads from `$50F17C00/$50F17A00`, write IWM mode `$17` at `$50F17E00`, then
read encoded floppy byte `$97`. Earlier notes below describe intermediate
failures from before the NuBus lane, RAM banking, and VIA read-lane fixes.

The SCSI-looking MAME frame-280 PC is misleading. A focused MAME SCSI tap shows
no SCSI register accesses after the early frame-67 polling window; the ROM PCs
around `$40826Cxx` are delay/helper code, not live NCR5380 traffic. Verilator's
frame-300 stop at `$40801656` is also in ROM delay code that compares against
the low-memory tick counter at `$016A`.

Old low-memory timing at frame 300 before later fixes:

| Run | PC | long `$016A` | word `$0D00` | word `$0DA6` |
| --- | --- | --- | --- | --- |
| MAME | `$00004606` | `$00000075` | `$0A3B` | `$0417` |
| Verilator | `$40801656` | `$000000AA` | `$051B` | `$0188` |

This timing mismatch was useful for that debug stage but is no longer the
current failure shape.

There is also a frame-counter caveat: Verilator's stop frame currently follows
the internal `videoTimer` path, which is roughly 60 Hz. The matched MAME run's
active screen is the NuBus `m2hires` card at `30.24 MHz / 896 / 525`, roughly
64.29 Hz. Direct frame numbers are useful landmarks, but they are not exact time
alignment.

## 2026-05-04 NuBus Lane Update

The matched MAME `m2hires` run proved that the declaration ROM is still exposed
on NuBus lane 0. The first MAME accesses are:

```text
MAME_VIDEO_ROM_R frame=69 pc=408043F4 addr=FEFFFFFC data=E1FFFFFF mask=000000FF
MAME_VIDEO_ROM_R frame=69 pc=40804336 addr=FEFF8000 data=01FFFFFF mask=FF000000
MAME_VIDEO_ROM_R frame=69 pc=40804336 addr=FEFF8004 data=00FFFFFF mask=FF000000
```

The RTL had been remapping the same ROM to lane 3 and advertising format byte
`$78`, causing the ROM to probe `$FEFFFFFF` and then walk `$FEFF8003`,
`$FEFF8007`, etc. That was not actually the same card layout as MAME. The card
now keeps MAME's lane-0 format byte `$E1`; on the 16-bit CPU bus, lane 0 is
presented as the upper byte of the even word. A `+nubus_debug` run confirmed the
first Verilator reads now align with MAME:

```text
NUBUS: RD ROM addr=fefffffc ... out=e1 lane=0 data_out=e1ff
NUBUS: RD ROM addr=feff8000 ... out=01 lane=0 data_out=01ff
NUBUS: RD ROM addr=feff8004 ... out=00 lane=0 data_out=00ff
```

This changes the current failure shape. Verilator no longer lands at
`$40801656` by frame 300; with lane 0 it reaches `$40826CC6` at frame 300 and
`$40801658` by frame 450:

| Run | PC | long `$016A` | word `$0D00` | word `$0DA6` |
| --- | --- | --- | --- | --- |
| Verilator frame 300 after lane fix | `$40826CC6` | `$000000A3` | `$051B` | `$0188` |
| Verilator frame 450 after lane fix | `$40801658` | `$00000134` | `$051B` | `$0188` |

The long `+nubus_debug` run also showed that the card's primary init code
enables video and then performs repeated reads from `$FE090010/$FE090012`, the
video VBL/RAMDAC status area. That makes NuBus video VBL status/interrupt
behavior the current highest-value target. The declaration ROM lane mismatch was
real and is fixed, but the boot still has not reached MAME's low-memory code
handoff.

## 2026-05-04 VBL And RAM-Bank Update

Focused VBL probes show the NuBus video status path is not the current blocker.
MAME and Verilator both enter the same low-memory VBL polling path:

```text
MAME:      pc=00002C6E/00002D88/00003F16/00004384/00004606
Verilator: pc=00002C72/00002D8A/00003F1A/00004386/00004608
```

Both read `$FE090010/$FE090012` and see the expected non-vblank status outside
VBL. Verilator then fell back through the ROM SCSI/no-device probe while MAME
continued into ROM code around `$0082E8xx`.

The real divergence was RAM banking. MAME's default `macii` RAM option is 2MB,
and MAME's GLUE model maps bank B into `$00800000-$008FFFFF`; the boot path
executes code in that window. The RTL only mirrored 2MB RAM through `$00000000-
$003FFFFF`, so the `$0082xxxx` ROM/RAM path was not available. The RTL now
selects RAM for the 2MB bank-B window and maps it to the second 1MB RAM bank;
the Verilator wrapper now uses 2MB RAM to match MAME's default.

After this fix, Verilator gets past the SCSI fallback and reaches later SCC
initialization by frame 500:

```text
PC=40803288 Op=062A VBR=40802806
SCC_RX_FIFO_EMPTY: ch=A read from empty FIFO
```

That put the blocker back in the SCC receive/status path at that time, not ASC,
NuBus VBL, or the SCSI no-target timeout. This section is superseded by the VIA
read-lane update below.

## 2026-05-04 VIA Read-Lane Update

The latest focused comparison found that the SCC/ASC-looking failure was caused
by byte-lane behavior on VIA reads. MAME's Mac II handlers return the same
8-bit VIA register value on both 68000 byte lanes:

```cpp
return (data & 0xff) | (data << 8);
```

The RTL returned the VIA byte on D15:8 but hardcoded D7:0 to `$EF`. That made a
wide ROM read of VIA2 ORA return `$3FEF` instead of `$3F3F`; the ROM then wrote
`$EF` back to ORA, leaving VIA2 PA7:6 at `11`. The later RAM-test orchestrator
read that as index `$0C`, loaded the `$04000000` table entry, failed the pattern
test, and entered the ASC diagnostic path.

After mirroring VIA/VIA2 reads onto both lanes, Verilator matches the MAME RAM
test checkpoint:

```text
VIA2 ORA read: $3F3F
VIA2 ORA latch: $3F
RAM test: A2=$00100000 D7=4 D6=0
ASC entry: $408000D0 -> $40805E4A, D7=2
```

Frame probes are now close again around the later ROM delay/helper region:

```text
MAME frame 280:      PC=40826CA8
Verilator frame 300: PC=40826CCA
```

The visible frame-300 Verilator screenshot is still vertical stripes with no
cursor. The next comparison should start after the fixed RAM and ASC milestones
and focus on why the post-ASC video/NuBus/SCSI path has not produced the normal
cursor screen yet.

## 2026-05-04 NCR5380 BSY Release Update

A focused SCSI trace found a real NCR5380 model bug in the early ROM probe.
Before the fix, the ROM wrote the mode register back to zero at `$40800688`,
but the simplified arbitration path left `ICR_A_BSY` asserted. The next ROM
poll at `$40800690` therefore read CSR `$40` (`BSY`) in Verilator. The matched
MAME run reads CSR `$00` in the same early register-4 polling window.

The RTL now clears the initiator-owned BSY latch when the host clears
`MR.ARB`. A short `--scsi-debug --stop-at-frame 40` run confirms the same early
sequence now returns CSR/data `$00` at `$40800690`, and frame 120 stops with the
NCR idle:

```text
PC=4080DE3E
SCSI state: mr=00 icr=00 tcr=00 odr=00 req=0 tbsy=00 treq=00
LowMem: long[$016A]=00000000 word[$0D00]=051B word[$0DA6]=0188
```

This removes the earlier stuck-BSY divergence; ASC, VIA RAM sizing, NuBus VBL,
and the early SCSI idle probe now all pass the focused comparisons.

The remaining post-ASC mismatch is not that the ROM enters the wrong helper.
MAME also samples the same SCSI helper with `A3=$50F10000`:

```text
MAME frame 280: pc=40826CA8 tick=00000063 A3=50F10000 A4=00002C60
```

The current difference is how long Verilator spends in the no-target timeout.
MAME has left that path by frame 500 and is executing copied low-memory code:

```text
MAME frame 500: pc=0082E80C tick=0000012A A4=50F17800
```

Verilator is still in the DBNE timeout at frame 500:

```text
Verilator frame 500: pc=40826CCA tick=00000165
SCSI state: mr=00 icr=05 tcr=00 odr=81 req=0 tbsy=00 treq=00
LowMem: word[$0D00]=051B word[$0DA6]=0188
```

The SCSI state there is internally idle/no-target, so the next likely blocker is
CPU/timer calibration or instruction throughput rather than ASC or an asserted
SCSI bus signal. The ROM delay constants still differ substantially from MAME
(`$0D00/$0DA6`: Verilator `$051B/$0188`, MAME `$0A3B/$0417`), and the no-target
DBNE loop is consuming too much frame time even with the smaller Verilator
timeout constant.

## 2026-05-05 IWM and VIA Timer Update

A focused IWM comparison found an early low-memory floppy mismatch. In MAME,
when the ROM enables the IWM motor/active bit, the controller enters active read
mode and clears `m_data`, so the second access in this sequence returns zero:

```text
MAME frame 294:
  pc=0082E1F8 addr=50017400 data=FFFF
  pc=0082E1FC addr=50017200 data=0000
```

Before the fix, Verilator could return stale idle-drive `$FF` on the
`$50F17200` motor-on access. The IWM model now returns `$FF` only while no drive
is enabled, returns `$00` on the inactive-to-active read transition, and clears
the read latch when the controller becomes active. A focused `--iwm-debug`
run confirms the first low-memory sequence now matches MAME:

```text
Verilator frame 158:
  pc=0082E1FC addr=50F17400 dout=FFFF
  pc=0082E200 addr=50F17200 dout=0000
```

This did not by itself boot to the cursor. The remaining SCSI-looking stall was
then traced to ROM delay timing, not to an asserted SCSI bus signal. The helper
at `$40826CB6` multiplies a timeout argument by low-memory word `$0DA6`, swaps
the high word into `D5`, and uses nested `DBcc` loops. With the bad calibration,
the outer loop can hit zero and underflow to `$FFFF`, stretching the no-target
timeout path.

MAME clocks the Mac II VIAs at `C7M/10` (about 783.36 kHz) and synchronizes CPU
VIA accesses to that slower device clock. The FPGA core had the VIA timers
counting on the faster CPU/E-side timing. The VIA core now has a separate
average-rate `timer_tick` for Timer 1/Timer 2 countdowns while keeping register
accesses on the existing CPU/E strobes.

After the VIA timer tick change, Verilator no longer stops in the SCSI timeout
at frame 320:

```text
Verilator frame 320:
  pc=40801658
  SCSI state: mr=00 icr=00 tcr=00 odr=81 req=0 tbsy=00 treq=00
  LowMem: long[$016A]=000000AF word[$0D00]=054D word[$0DA6]=0196
```

A longer frame-820 run still has not reached MAME's low-memory floppy loop. It
is spending most time in the ROM tick-wait helper at `$40801656` with
`D5=$000004B0`, while matched MAME has already returned to the floppy driver:

```text
MAME frame 820:      pc=0082E7F8 tick=00000242 A4=50F17800
Verilator frame 820: pc=40801656 tick=00000283 A3=40801800 A4=00000032
```

So the current blocker has moved: it is no longer ASC, early SCSI BSY, or the
first IWM motor-on value. The next suspect is the ROM wait/VBL scheduling path
around `$40801610-$40801658` and why Verilator keeps taking the longer wait
path after the SCSI helper returns.

## 2026-05-05 Wait Path / Calibration Update

The latest focused probes narrow the divergence again. Verilator reaches the
ROM wait helper at `$408015EA` around frame 299 and then enters the long
absolute-tick timeout path at `$40801600`. The ROM itself sets up the long
timeout there:

```text
WAIT_DBG frame=299 tick=0000009C pc=40801600 op=303C D5=0000012C
WAIT_DBG frame=299 tick=0000009C pc=4080160A op=41F8 D0=000004B0
WAIT_DBG frame=299 tick=0000009C pc=4080160C op=2A00 D5=0000012C
WAIT_DBG frame=299 tick=0000009C pc=40801610 op=A07F D5=000004B0
```

So the observed `D5=$000004B0` spin is not a corrupted caller register. It is
the 20 second ROM timeout path:

```text
move.w  #$0014,d0
mulu.w  #$003c,d0
move.l  d0,d5
```

Matched MAME, using `-nb9 "" -nbe m2hires -scsi:6 ""` and the same floppy
image, does not hit the `$408015EA/$408016xx` wait path in the same window. A
debugger trace command that starts tracing at `$408015EA` produced no trace file
by frame 360, and the Lua wait probe reported zero hits by frame 900:

```text
MAME_WAIT_FRAME frame=300 pc=00004606 tick016A=00000074 D5=0000012C W0D24=0000 W0D28=4080
MAME_WAIT_FRAME frame=320 pc=408061F2 tick016A=00000088 D5=0000012C W0D24=0000 W0D28=4080
MAME_WAIT_SUMMARY frames=900 hits=0 pc=408061F2 tick016A=00000289 D5=0000002D W0D24=0000 W0D28=4080
```

The frame counters are not an exact timebase match, but the low-memory
calibration words still show a large real difference:

| Run | Approx frame | long `$016A` | word `$0D00` | word `$0DA6` |
| --- | --- | --- | --- | --- |
| MAME matched card | 320 | `$00000088` | `$0A3B` | `$0417` |
| Verilator current | 330 | `$000000B8` | `$054D` | `$0196` |

`$0DA6` is the ROM's calibrated DBNE/SCSI delay constant. Verilator's value is
still much lower than MAME's even after moving VIA timer countdowns to the
Mac II `C7M/10` rate. That points at CPU/VIA timing calibration or effective
instruction throughput, not ASC.

The current SCSI stop state also does not look like a stuck target or asserted
BSY problem:

```text
SCSI state: mr=00 icr=05 tcr=00 odr=81 busdin=00 req=0 tbsy=00 treq=00
```

The ROM is still paying no-target timeout costs, but the bus itself is idle.
The leading theory is now that the ROM's calibrated delay constants and tick
wait scheduling do not match MAME closely enough. Next useful probes should
log the VIA Timer 1 count/latch/ACR/PB7 state and the writes that establish
low-memory `$0D00` and `$0DA6`, then compare those values against MAME's
`via6522_device` behavior.

## 2026-05-05 Calibration Probe Update

The next probe confirms that MAME and Verilator program the same VIA2 Timer 1
setup, but they do not compute the same delay constants before that setup.
This makes the divergence earlier than the later SCSI/no-target wait.

MAME reaches the calibration setup at frame 67:

```text
MAME_CALIB_VIA_W frame=67 pc=40800626 VIA1 reg=E data=20202020 W0D00=0A3B W0DA6=0417
MAME_CALIB_VIA_W frame=67 pc=40800752 VIA2 reg=B data=C0C0C0C0 W0D00=0A3B W0DA6=0417
MAME_CALIB_VIA_W frame=67 pc=40800762 VIA2 reg=4 data=6E6E6E6E W0D00=0A3B W0DA6=0417
MAME_CALIB_VIA_W frame=67 pc=40800768 VIA2 reg=5 data=19191919 W0D00=0A3B W0DA6=0417
```

Verilator executes the equivalent sequence, but the low-memory constants are
already much smaller:

```text
CALIB_LM_WR frame=115 pc=408005AE addr=00000D00 data=054D
CALIB_LM_WR frame=115 pc=40800624 addr=00000DA6 data=0196
CALIB_VIA frame=115 pc=40800758 VIA2 WR reg=B din=C0C0 W0D00=054D W0DA6=0196
CALIB_VIA frame=115 pc=40800766 VIA2 WR reg=4 din=6E6E W0D00=054D W0DA6=0196
CALIB_VIA frame=115 pc=4080076C VIA2 WR reg=5 din=1919 W0D00=054D W0DA6=0196
```

So VIA2 Timer 1 is not being programmed with the wrong latch. Both runs use
`ACR=$C0` and latch `$196E`. The problem is the earlier ROM calibration loop
around `$40800572-$40800624`: Verilator completes about half as many iterations
before the VIA event as MAME. That stores `$054D/$0196` instead of
`$0A3B/$0417`.

Changing the simulator's TG68K CPU mode input from `2'b10` to the documented
68020 mode `2'b11` did not change the measured constants. The remaining likely
cause is effective timing of the VIA-heavy calibration loop, especially the
TG68K VPA/VMA/E-cycle handshake and its interaction with repeated VIA accesses,
rather than a wrong ASC state, SCSI target state, NuBus card selection, or VIA2
T1 latch value.
