#!/usr/bin/env python3
"""Byte-diff two .vhd/.hda images; classify changed ranges by 512-byte LBA."""
import sys

A, B = sys.argv[1], sys.argv[2]  # pristine, post-crash
with open(A, 'rb') as f: a = f.read()
with open(B, 'rb') as f: b = f.read()
print(f"sizes: pristine={len(a)} post={len(b)}")
n = min(len(a), len(b))

# find changed 512-byte sectors
changed = []
for lba in range(n // 512):
    o = lba * 512
    if a[o:o+512] != b[o:o+512]:
        changed.append(lba)
print(f"changed sectors: {len(changed)}")

# group into contiguous runs
runs = []
for lba in changed:
    if runs and lba == runs[-1][1] + 1:
        runs[-1][1] = lba
    else:
        runs.append([lba, lba])
print(f"contiguous runs: {len(runs)}")
for r in runs:
    lo, hi = r
    nsec = hi - lo + 1
    # per-run byte-level detail for small runs
    detail = ""
    o0, o1 = lo*512, (hi+1)*512
    # count differing bytes
    diffbytes = sum(1 for i in range(o0, o1) if a[i] != b[i])
    # first 32 bytes of old vs new at first differing offset
    first = next(i for i in range(o0, o1) if a[i] != b[i])
    last = next(i for i in range(o1-1, o0-1, -1) if a[i] != b[i])
    print(f"  LBA {lo}..{hi} ({nsec} sect, bytes@0x{o0:08X}-0x{o1:08X}) diffbytes={diffbytes} "
          f"firstdiff=0x{first:08X} lastdiff=0x{last:08X}")
    print(f"    old[first-4:first+28]: {a[max(first-4,0):first+28].hex(' ')}")
    print(f"    new[first-4:first+28]: {b[max(first-4,0):first+28].hex(' ')}")
