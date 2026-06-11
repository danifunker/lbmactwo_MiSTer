#!/usr/bin/env python3
"""For each changed sector in post-crash image, classify its NEW content:
   - ZERO  (all zeros)
   - COPY  of pristine sector N (content-hash match elsewhere in pristine)
   - SHIFT (same data as pristine at the same place, byte-shifted by d —
            the MacLC 2026-06-10 pseudo-DMA write byte-slip signature: one
            byte inserted/dropped mid-command shifts the rest of the write)
   - NOVEL (content not found anywhere in pristine)
Group results into runs and print (dst <- src) mappings."""
import sys, hashlib
from collections import defaultdict

A, B = sys.argv[1], sys.argv[2]  # pristine, post
a = open(A, 'rb').read(); b = open(B, 'rb').read()
n = min(len(a), len(b)) // 512

# SHIFT detection: compare the post sector against the pristine image
# displaced by a few bytes (alignment carries across sector boundaries, so
# compare against the full image, not the sector in isolation). >=92% byte
# match at some nonzero d = SHIFT class.
def shift_match(lba):
    o = lba*512
    best = None
    for d in (1, -1, 2, -2, 3, -3, 4, -4):
        lo = max(o, d)
        hi = min(o+512, len(a)+d, len(b))
        if hi <= lo: continue
        sc = sum(1 for k in range(lo, hi) if b[k] == a[k-d])
        tot = hi - lo
        if sc/tot >= 0.92 and (best is None or sc > best[0]):
            best = (sc, d)
    return best[1] if best else None

# hash all pristine sectors
h2lba = defaultdict(list)
for lba in range(n):
    s = a[lba*512:(lba+1)*512]
    h2lba[hashlib.md5(s).digest()].append(lba)

ZERO = hashlib.md5(b'\0'*512).digest()

results = []  # (dst_lba, kind, srcs)
for lba in range(n):
    o = lba*512
    if a[o:o+512] == b[o:o+512]: continue
    s = b[o:o+512]
    hh = hashlib.md5(s).digest()
    if s == b'\0'*512:
        results.append((lba, 'ZERO', []))
    elif hh in h2lba:
        results.append((lba, 'COPY', h2lba[hh]))
    else:
        d = shift_match(lba)
        if d is not None:
            results.append((lba, f'SHIFT{d:+d}', []))
        else:
            results.append((lba, 'NOVEL', []))

# group into runs of same kind with consecutive dst (and consecutive src for COPY)
runs = []
for (dst, kind, srcs) in results:
    if runs:
        p = runs[-1]
        if (p['kind'] == kind and dst == p['dst1'] + 1 and
            (kind != 'COPY' or any(s == p['src1'] + 1 for s in srcs))):
            p['dst1'] = dst
            if kind == 'COPY':
                p['src1'] = p['src1'] + 1
            p['n'] += 1
            continue
    runs.append({'kind': kind, 'dst0': dst, 'dst1': dst,
                 'src0': srcs[0] if srcs else None,
                 'src1': srcs[0] if srcs else None,
                 'srcall': srcs, 'n': 1})

print(f"changed sectors: {len(results)}  runs: {len(runs)}")
print(f"{'kind':8} {'dst range':>17} {'n':>5}  src")
for r in runs:
    src = ''
    if r['kind'] == 'COPY':
        first_srcs = ','.join(str(s) for s in r['srcall'][:4])
        src = f"<- {first_srcs}..{r['src1']}  (delta {r['dst0']-r['src0']:+d})"
    print(f"{r['kind']:8} {r['dst0']:>8}..{r['dst1']:<8} {r['n']:>5}  {src}")
