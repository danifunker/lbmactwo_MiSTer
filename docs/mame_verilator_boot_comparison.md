# MAME vs. Verilator Mac II Boot Comparison

This note captures the current boot comparison between the local MAME `macii`
run and the Verilator simulation. The goal is to keep the remaining boot work
focused on the first real divergence instead of chasing earlier devices that
are no longer blocking progress.

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

Expected matched-card probe summary at 1200 frames:

```text
MAME_SCC_SUMMARY frames=1200 reads=1159 writes=71 poll_hits=0 pc=408061F2
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

Verilator, by contrast, was still at `PC=40805F2A` at frame 80 and
`PC=4080DE3E` at frame 120 in the current run. That means the useful comparison
point is no longer just "wait longer"; the boot path is already behind MAME
before the NuBus card should be initialized.

## Current Observations

| Checkpoint | MAME `macii` | Verilator |
| --- | --- | --- |
| 1200-frame progress | Default `mdc824`: reaches `PC=40826CC6`; matched `nbe m2hires`: reaches `PC=408061F2` | Reaches frame 1200; final PCs seen around `40812E98`/`40812F5E` in the prior quiet run |
| ASC | Passes ROM ASC probing | No longer appears to be the current blocker after the ASC byte-lane/register fixes |
| SCC | Early SCC status loop reads `0x54` at `PC=408005D2`; no long `408032xx` poll | The previous `408032AC` SCC-style stall is not present in the latest quiet run |
| Video | Default `macii` uses `mdc824` in slot 9; matched run uses `m2hires` in slot E with the same `341-0660.bin` ROM | Verilator models an `m2hires`-like card in slot E; screenshot at frame 1000 is still flat gray, with no cursor |
| MAME SCC poll window | `40803280-40803310` was never entered in the 1200-frame MAME probe | If Verilator returns to this window, that is a real divergence from the MAME boot path |

The current evidence says we are not dying at ASC. SCC also does not look like
the current terminal failure in the latest run. The matched-card MAME run still
does not enter the `408032xx` SCC poll window, which makes that old Verilator
stall a real divergence if it reappears. The remaining visible symptom is that
the Verilator machine gets far enough into ROM initialization / Slot Manager
activity but still does not produce the expected initialized display or cursor.

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
  the original tight `btst #6,$50F10010` loop. It still spends too long retrying
  the SCSI probe, so target selection/no-device timeout behavior is the next
  focus.

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

The boot has moved past the earlier ASC failure and the old SCC diagnostic/BERR
path. The latest evidence points at NCR5380/SCSI behavior: Verilator reaches the
ROM probe at `$408268D8`, MAME with the matched NuBus video card does not, and
Verilator spends excessive simulated time in the SCSI retry sequence before a
cursor would appear.

The next debugging step should be a tighter matched SCSI trace:

1. In MAME, keep using `tools/mame/macii_scsi_probe.lua` with the matched
   `-nb9 "" -nbe m2hires` command so future comparisons use the same video card.
2. In Verilator, log NCR5380 ODR/ICR/MR/TCR/CSR/BSR plus target `phase`,
   `mounted`, `sel`, `bsy`, `req`, `ack`, and `din` around
   `$40826932-$40826986`.
3. Compare MAME's NCR5380 arbitration timing from
   `mame/src/devices/machine/ncr5380.cpp` with `rtl/ncr5380.sv`, especially
   when AIP clears, when BSY is asserted, and whether no-device selection should
   return quickly or depend on a bus-error timeout.
4. Re-run the frame/cursor check only after the SCSI probe stops dominating the
   headless run.
