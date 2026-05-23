#!/bin/sh
# patch_rom_nomemtest.sh
#
# Patch the Macintosh II ROM (boot0.rom, checksum 0x9779D2C4) to skip the
# destructive power-on memory test, the same way the Snow emulator does it.
#
# The ROM gates its slow pattern-walk RAM test behind a warm-start flag check:
#
#     cmpi.l #$574C5343, $0CFC.w   ; "WLSC" warm-start flag
#     beq.s  <skip>                ; flag present -> skip the test
#     jsr    $2BBC                 ; cold path: destructive memory test
#
# This happens at two sites. We turn both beq.s ($67) into bra.s ($60) so the
# test is always skipped regardless of RAM contents, then fix up the Mac ROM
# checksum stored in the first longword (only one byte changes).
#
# Pure POSIX sh + busybox tools (dd, od, printf) so it runs on MiSTer's Linux.
#
# Usage: ./patch_rom_nomemtest.sh [rom-file]            # patch IN PLACE (default boot0.rom)
#        ./patch_rom_nomemtest.sh <input> <output>      # write a separate output file
#
# In-place mode keeps a one-time backup at <rom-file>.bak and is idempotent
# (re-running on an already-patched ROM is detected and does nothing).

set -e

IN="${1:-boot0.rom}"
if [ -n "$2" ]; then
    OUT="$2"          # explicit separate output
else
    OUT="$IN"         # in-place
fi

# Byte patches: offset(dec)  expected-original(hex)  new(hex)  description
#   0x002 = 2   : checksum byte    0xD2 -> 0xC4  (0x9779D2C4 -> 0x9779C4C4)
#   0x0EC = 236 : beq.s -> bra.s   0x67 -> 0x60  (first warm-start gateway)
#   0x1A8 = 424 : beq.s -> bra.s   0x67 -> 0x60  (second warm-start gateway)
PATCHES="2:d2:c4 236:67:60 424:67:60"

[ -f "$IN" ] || { echo "error: input ROM '$IN' not found" >&2; exit 1; }

SIZE=$(wc -c < "$IN")
if [ "$SIZE" -ne 262144 ]; then
    echo "error: '$IN' is $SIZE bytes, expected 262144 (256K Mac II ROM)" >&2
    exit 1
fi

# read one byte at decimal offset $1 of file $2, print as two lowercase hex digits
readbyte() {
    dd if="$2" bs=1 skip="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

# Verify originals; also detect an already-patched ROM (idempotency).
already=1
for p in $PATCHES; do
    off=${p%%:*}; rest=${p#*:}; exp=${rest%%:*}; new=${rest#*:}
    got=$(readbyte "$off" "$IN")
    if [ "$got" = "$exp" ]; then
        already=0
    elif [ "$got" != "$new" ]; then
        echo "error: byte at offset $off is 0x$got, expected 0x$exp (orig) or 0x$new (patched)." >&2
        echo "       This script only supports the original Mac II ROM (checksum 0x9779D2C4)." >&2
        exit 1
    fi
done

if [ "$already" -eq 1 ]; then
    echo "'$IN' is already patched (memory test disabled); nothing to do."
    exit 0
fi

if [ "$OUT" = "$IN" ]; then
    # In-place: keep a one-time pristine backup.
    if [ ! -f "$IN.bak" ]; then
        cp "$IN" "$IN.bak"
        echo "backed up original to '$IN.bak'"
    fi
else
    cp "$IN" "$OUT"
fi

for p in $PATCHES; do
    off=${p%%:*}; rest=${p#*:}; new=${rest#*:}
    printf "$(printf '\\x%s' "$new")" | dd of="$OUT" bs=1 seek="$off" count=1 conv=notrunc 2>/dev/null
    echo "patched offset $off -> 0x$new"
done

echo "wrote '$OUT' (memory test disabled, checksum 0x9779C4C4)"
