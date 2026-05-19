#!/bin/bash
# build_m2hires_probe.sh — assemble a SCSI boot image with the M2Hires probe.
# Boot it on real Mac II with M2Hires, then describe what you see:
#  - leftmost stripe ($00) — what color?
#  - second stripe ($55) — what color?
#  - third stripe ($AA) — what color?
#  - rightmost stripe ($FF) — what color?
# That tells us pixel polarity + whether the framebuffer layout matches.
set -euo pipefail

RB="${RB:-$HOME/repos/rusty-backup/target/release/rusty-backup-cli}"
TEMPLATE="${1:-$HOME/testdisk.hda}"
OUT="${2:-/tmp/m2hires_probe.hda}"

BOOT=build/boot_stub_m2hires_probe.bin

[[ -x "$RB" ]]    || { echo "rusty-backup-cli not found"; exit 1; }
[[ -f "$BOOT" ]]  || { echo "missing $BOOT — run 'make m2hires_probe'"; exit 1; }

cp "$TEMPLATE" "$OUT"
PART=/tmp/m2hires_probe_part.dsk
dd if="$OUT" of="$PART" bs=512 skip=96 count=40960 status=none
"$RB" api hfs put-boot "$PART" "$BOOT" >/dev/null
"$RB" api hfs validate "$PART"
dd if="$PART" of="$OUT" bs=512 seek=96 count=40960 conv=notrunc status=none

echo "wrote $OUT ($(stat -c%s $BOOT) byte boot block)"
