#!/bin/sh
# patch_rom_nomemtest.sh
#
# Fast-boot patch for the Macintosh II ROM (boot0.rom, checksum 0x9779D2C4).
#
# TWO patches are applied:
#
# (1) Skip the destructive power-on RAM test, the same way Snow does it.
#
#     The ROM gates its slow pattern-walk RAM test behind a warm-start flag:
#
#         cmpi.l #$574C5343, $0CFC.w   ; "WLSC" warm-start flag
#         beq.s  <skip>                ; flag present -> skip the test
#         jsr    $2BBC                 ; cold path: destructive memory test
#
#     This happens at two sites.  Turn both beq.s ($67) into bra.s ($60)
#     so the test is always skipped regardless of RAM contents.
#
# (2) NOP the back-branch of the wait loop at $40806DD8 that DEPENDS ON
#     the RAM test having run.
#
#     The loop:
#         $6DCC: bset.b #5, $15D(A3)
#         $6DD2: bsr.s  $6DEA           ; init a peripheral handler
#         $6DD4: andi   #$F8FF, SR
#         $6DD8: btst.b #5, $15D(A3)
#         $6DDE: bne.s  $6DD8           ; loop while bit set
#
#     A3 is set to $24B0 here, so the byte being polled is $0000260D.
#     In a full memtest boot, MAME shows that bit 5 of $260D is cleared
#     at frame 177 by the RAM-test code at PC $40803740 (the pattern-walk
#     overwrites that byte as a side effect).  With the memtest skipped
#     (patch (1)) the bit is never cleared and Verilator spins here
#     forever, never reaching Welcome let alone Finder.
#
#     Fix: turn `bne.s -8` ($66 $F8) into NOP ($4E $71) so the loop runs
#     at most one iteration and falls through to the next instruction
#     (JSR (d16,PC)) which doesn't depend on Z.  The BTST still runs but
#     its result is ignored.
#
# Together patches (1) and (2) let the ROM continue past $40806DC0 into
# the normal boot sequence without running the multi-second RAM test.
#
# The checksum byte(s) in the first longword are adjusted to keep
# `(stored_checksum_word) + sum_of_body_words` constant (the ROM's
# checksum word algorithm — verified by reproducing the existing
# 0xD2C4 -> 0xC4C4 delta).
#
# Pure POSIX sh + busybox tools (dd, od, printf) so it runs on MiSTer's Linux.
#
# Usage: ./patch_rom_nomemtest.sh [rom-file]            # patch IN PLACE (default boot0.rom)
#        ./patch_rom_nomemtest.sh <input> <output>      # write a separate output file
#
# In-place mode keeps a one-time backup at <rom-file>.bak and is idempotent
# (re-running on an already-patched ROM is detected and does nothing).
# Also detects the older "memtest-only" patched ROM and upgrades it.

set -e

IN="${1:-boot0.rom}"
if [ -n "$2" ]; then
    OUT="$2"          # explicit separate output
else
    OUT="$IN"         # in-place
fi

# Byte patches: offset(dec)  expected-original(hex)  new(hex)  description
#   0x002 =     2 : checksum byte 0xD2 -> 0xAC  (body word delta -0x2687)
#   0x003 =     3 : checksum byte 0xC4 -> 0x3D
#   0x0EC =   236 : beq.s -> bra.s   0x67 -> 0x60  (first warm-start gateway)
#   0x1A8 =   424 : beq.s -> bra.s   0x67 -> 0x60  (second warm-start gateway)
#   0x6DDE = 28126 : bne.s -> NOP    0x66 -> 0x4E  (wait-loop back-branch high)
#   0x6DDF = 28127 : bne.s -> NOP    0xF8 -> 0x71  (wait-loop back-branch low)
PATCHES="2:d2:ac 3:c4:3d 236:67:60 424:67:60 28126:66:4e 28127:f8:71"

# Older "memtest-only" intermediate patched values that the prior version
# of this script produced.  When the byte already matches one of these, we
# treat it as a partial upgrade — re-apply all NEW values so the ROM ends
# up fully patched.
OLD_PATCH="2:c4"

[ -f "$IN" ] || { echo "error: input ROM '$IN' not found" >&2; exit 1; }

SIZE=$(wc -c < "$IN")
if [ "$SIZE" -ne 262144 ]; then
    echo "error: '$IN' is $SIZE bytes, expected 262144 (256K Mac II ROM)" >&2
    exit 1
fi

# Read one byte at decimal offset $1 of file $2, print as two lowercase hex digits.
readbyte() {
    dd if="$2" bs=1 skip="$1" count=1 2>/dev/null | od -An -tx1 | tr -d ' \n'
}

# Verify originals; detect already-patched (idempotency) and partially-patched.
all_new=1
for p in $PATCHES; do
    off=${p%%:*}; rest=${p#*:}; exp=${rest%%:*}; new=${rest#*:}
    got=$(readbyte "$off" "$IN")
    if [ "$got" != "$new" ]; then
        all_new=0
    fi
    if [ "$got" != "$exp" ] && [ "$got" != "$new" ]; then
        # Accept intermediate / older-patched values explicitly.
        accept=0
        for op in $OLD_PATCH; do
            op_off=${op%%:*}; op_val=${op#*:}
            if [ "$off" = "$op_off" ] && [ "$got" = "$op_val" ]; then
                accept=1
                break
            fi
        done
        if [ "$accept" -eq 0 ]; then
            echo "error: byte at offset $off is 0x$got, expected 0x$exp (orig) or 0x$new (patched)." >&2
            echo "       This script only supports the original Mac II ROM (checksum 0x9779D2C4)." >&2
            exit 1
        fi
    fi
done

if [ "$all_new" -eq 1 ]; then
    echo "'$IN' is already fully patched (memtest skip + wait-loop fix); nothing to do."
    exit 0
fi

if [ "$OUT" = "$IN" ]; then
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

echo "wrote '$OUT' (memory test skipped + wait-loop NOP; checksum 0x9779AC3D)"
