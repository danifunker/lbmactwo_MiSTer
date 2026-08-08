#!/usr/bin/env python3
"""Repair the 64-byte-periodic 'fossil opcode' MDB stamping in HFS disk images.

Damage signature (LBMacTwo hardware RAM-write-loss bug, 2026-07-17): the HFS
Master Directory Block (sector partition_start+2, normally 98) carries stale
68k code words (0x229A = move.l (A2)+,(A1)+, 0x51C9 = dbf D1) at four fixed
slots per 64-byte group ({+0x14,+0x1C,+0x30,+0x38}, plus 0x0C in group 0),
because writes zeroing the writeback buffer were silently dropped on hardware.
Everything outside the MDB sector is intact (verified by full-image diff of a
before/after capture).

Repairs, from first principles / unstamped neighbors:
  drAlBlkSiz high word <- 0            (block sizes are < 64K)
  drAlBlSt             <- drVBMSt + ceil(drNmAlBlks / 4096)   (bitmap sectors)
  drNmFls              <- 7 placeholder (cosmetic; Finder rebuilds the count)
  drCTFlSize low word  <- CTExt[0].count * drAlBlkSiz (& 0xFFFF)
  every other stamped slot <- 0        (name tail / FndrInfo / reserved)

Validated 2026-07-17: MacLC_7-1-POP.hda repaired copy boots System 7.1 in the
Verilator sim (previously deterministic blinking-'?' park).

Usage: repair_hfs_mdb_stamps.py <image.hda> [--out repaired.hda] [--hfs-start 96]
"""
import argparse, shutil, struct, sys

STAMP_WORDS = (0x229A, 0x51C9)

def slots():
    yield 0x0C
    for base in range(0x00, 0x200, 0x40):
        for off in (0x14, 0x1C, 0x30, 0x38):
            s = base + off
            if s < 0x200:
                yield s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--out", help="write repaired copy here (default: <image>.repaired)")
    ap.add_argument("--hfs-start", type=int, default=96, help="HFS partition start LBA")
    ap.add_argument("--in-place", action="store_true", help="patch the file directly")
    a = ap.parse_args()

    out = a.image if a.in_place else (a.out or a.image + ".repaired")
    if not a.in_place:
        shutil.copyfile(a.image, out)

    f = open(out, "r+b")
    mdb_lba = a.hfs_start + 2
    f.seek(mdb_lba * 512)
    mdb = bytearray(f.read(512))

    if mdb[0:2] != b"BD":
        sys.exit(f"no HFS MDB signature at lba {mdb_lba} (got {mdb[0:2].hex()})")

    stamped = [s for s in slots() if struct.unpack(">H", mdb[s:s+2])[0] in STAMP_WORDS]
    if not stamped:
        print("no stamp words found at known slots — nothing to do")
        return

    def W(off, val):
        mdb[off], mdb[off+1] = val >> 8, val & 0xFF

    for s in stamped:
        W(s, 0x0000)

    nm_al_blks = struct.unpack(">H", mdb[0x12:0x14])[0]
    vbm_st     = struct.unpack(">H", mdb[0x0E:0x10])[0]
    al_blk_siz = struct.unpack(">I", mdb[0x14:0x18])[0]
    if 0x1C in stamped or struct.unpack(">H", mdb[0x1C:0x1E])[0] == 0:
        W(0x1C, vbm_st + -(-nm_al_blks // 4096))
    if 0x0C in stamped:
        W(0x0C, 0x0007)
    if 0x94 in stamped:
        ct0_cnt = struct.unpack(">H", mdb[0x98:0x9A])[0]
        W(0x94, (ct0_cnt * al_blk_siz) & 0xFFFF)

    f.seek(mdb_lba * 512)
    f.write(mdb)
    f.close()
    al_bst = struct.unpack(">H", mdb[0x1C:0x1E])[0]
    print(f"repaired {len(stamped)} stamped words -> {out}")
    print(f"alBlkSiz={al_blk_siz} alBlSt={al_bst} (extents tree at lba {a.hfs_start + al_bst})")

if __name__ == "__main__":
    main()
