# NuBus Video Upgrade Plan

## Recommendation

Model the Mac II NuBus video card as a semantic NuBus device with card-local
VRAM behavior, not as cycle-perfect physical NuBus timing. The real NuBus is a
10 MHz bus; without block transfers, a 32-bit transfer needs at least two bus
cycles, so the theoretical ceiling is 20 MB/s. The original Mac II does not use
NuBus block transfers, and practical CPU-to-NuBus throughput is much lower.

The important compatibility point for the ROM and Slot Manager is transaction
semantics:

- Standard and super slot decode must match the selected slot.
- 32-bit NuBus accesses arriving through the 16-bit TG68K interface must be
  accepted as two halfword subcycles when address/data/strobes change even if
  AS/select has not dropped yet.
- VRAM writes are inverted on the card, matching MAME's `data ^= 0xffffffff`.
- TFB register writes are inverted and byte-swapped, matching MAME's
  `swapendian_int32`.
- Scanout should read the card's VRAM image using base/stride/mode registers.

MAME is the best behavioral reference for the Apple Macintosh II High
Resolution Video Card (`m2hires`). Snow is useful for bus decomposition because
it models NuBus devices as byte-addressed local devices, but it does not include
this exact `m2hires` card and is not a cycle-accurate bus reference.

## Current Upgrade

- Expose TG68K longword state at the NuBus card boundary for debug and future
  transfer handling.
- Re-arm card ACK when a new halfword subcycle appears under the same select.
  This fixes the missing second half of longword VRAM writes.
- Remove the old mirrored-write heuristic. Each 16-bit subcycle now writes only
  the addressed VRAM word.
- Add a runtime MiSTer menu switch for color versus monochrome output. This is
  currently a display-mode switch on the high-resolution card, not a separate
  monochrome declaration ROM.

## Next Phases

1. Finish the scanout model.
   The current SDRAM-backed on-demand scanout is still a bottleneck. Replace it
   with deterministic card-local scanout state: either a blanking-time line
   buffer or a true dual-port/local VRAM image that CPU writes update.

2. Split card identities.
   Keep `m2hires`/Apple High Resolution Video Card as the color card in slot E.
   Add a separate monochrome NuBus card once a compatible declaration ROM and
   address map are selected from the video/monitor matrix references.

3. Make slot selection explicit.
   Instantiate one card at a time from the MiSTer menu first. Once stable, allow
   two populated slots if the ROM/card combination matches real Mac II behavior.

4. Compare against references.
   Use MAME with `-nb9 "" -nbe m2hires -scsi:6 ""` for the color card. Use Snow
   for byte-lane and device-local access structure, not as a direct pixel
   reference for `m2hires`.

5. Re-test visual milestones.
   Use no-media boot screenshots at frame 162 and later frames, then test the
   floppy icon/cursor path once the screen is readable.
