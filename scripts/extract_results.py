#!/usr/bin/env python3
"""Extract /Results.jsonl from a cpufpubench .hda without rb-cli.

The build script patches the partition-relative byte offset of the
pre-allocated /Results.jsonl extent right after the RJSNLTAG marker.
HFS partition start comes from the APM (Apple_HFS entry).
"""
import struct, sys

img = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "-"
data = open(img, "rb").read()

part_start = None
blk = 1
while True:
    off = blk * 512
    if data[off:off+2] != b"PM":
        break
    start, _cnt = struct.unpack_from(">II", data, off + 8)
    ptype = data[off+48:off+80].rstrip(b"\0")
    if ptype == b"Apple_HFS":
        part_start = start * 512
        break
    blk += 1
assert part_start is not None, "no Apple_HFS partition found"

p = data.find(b"RJSNLTAG")
assert p >= 0, "RJSNLTAG marker not found"
roff, = struct.unpack_from(">I", data, p + 8)

abs_off = part_start + roff
blob = data[abs_off:abs_off + 409600]
text = blob.split(b"\0", 1)[0].decode("ascii", "replace")
sys.stderr.write(f"results @ abs 0x{abs_off:X}, {len(text)} bytes of JSONL\n")
if out == "-":
    sys.stdout.write(text)
else:
    open(out, "w").write(text)
