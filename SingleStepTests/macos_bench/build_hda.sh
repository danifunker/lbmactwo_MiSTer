#!/bin/bash
# build_hda.sh — assemble /tmp/macos_bench.hda from scratch.
#
# Pipeline:
#   1. Start from ~/testdisk.hda (clean, formatted, hfsutils-incompatible
#      but rb-cli understands it just fine).
#   2. For each bench APPL:
#      a) extract its resource fork from Retro68's MacBinary `.bin`
#      b) `rb-cli put`  — create a 0-byte data fork with type/creator
#      c) `rb-cli setrsrc` — install the resource fork
#
# Why two-step put+setrsrc: Retro68 APPLs have an empty data fork; all
# the code/icon/BNDL resources live in the resource fork. rb-cli's `put`
# only writes one fork at a time, so we use --zero 0 for the data fork
# and then setrsrc for the resource fork.

set -euo pipefail

TEMPLATE="${TEMPLATE:-$HOME/testdisk.hda}"
HDA="${HDA:-/tmp/macos_bench.hda}"
BUILD="${BUILD:-$(dirname "$0")/build}"
RB="${RB:-$HOME/repos/rusty-backup/target/release/rb-cli}"

# rb-cli partition index of the Apple_HFS volume. rb-cli counts only
# data partitions (skipping the APM map + driver), so @1 is the HFS vol.
HFS_PART=1

# (mac_name, creator_code, source_bin)
BENCHES=(
    "CpuBench;CpuB;CpuBench.bin"
    "FpuBench;FpuB;FpuBench.bin"
    "CpuFpuBench;CFpB;CpuFpuBench.bin"
)

# ---- Sanity ---------------------------------------------------------------
[[ -f "$TEMPLATE" ]] || { echo "missing template $TEMPLATE"; exit 1; }
[[ -x "$RB" ]]       || { echo "missing $RB (cargo build --release --bin rb-cli first)"; exit 1; }
for b in "${BENCHES[@]}"; do
    bin="${b##*;}"
    [[ -f "$BUILD/$bin" ]] || { echo "missing $BUILD/$bin — cmake --build $BUILD first"; exit 1; }
done

# ---- Fresh image from template -------------------------------------------
cp -f "$TEMPLATE" "$HDA"
echo "seeded $HDA from $TEMPLATE"

# ---- Helper: extract resource fork from a MacBinary I file ----------------
# MacBinary I header is 128 bytes. Data fork follows (length at offset 83,
# big-endian u32; padded to 128-byte multiple). Resource fork follows
# (length at offset 87, big-endian u32). Retro68 APPLs always have a
# 0-byte data fork, so the resource fork begins at byte 128, but we honor
# the header lengths anyway so this works for non-empty data forks too.
extract_rsrc() {
    python3 - "$1" "$2" <<'PY'
import struct, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src, 'rb') as f:
    hdr = f.read(128)
data_len = struct.unpack('>I', hdr[83:87])[0]
rsrc_len = struct.unpack('>I', hdr[87:91])[0]
data_padded = (data_len + 127) & ~127
with open(src, 'rb') as f:
    f.seek(128 + data_padded)
    rsrc = f.read(rsrc_len)
if len(rsrc) != rsrc_len:
    sys.exit(f"short read: wanted {rsrc_len}, got {len(rsrc)}")
with open(dst, 'wb') as g:
    g.write(rsrc)
print(f"  {src}: rsrc fork {rsrc_len} bytes -> {dst}")
PY
}

# ---- Inject benches ------------------------------------------------------
for b in "${BENCHES[@]}"; do
    IFS=';' read -r name creator bin <<<"$b"
    rsrc=/tmp/${name}.rsrc.bin

    echo ""
    echo "=== $name ($creator) ==="
    extract_rsrc "$BUILD/$bin" "$rsrc"

    # Create file with empty data fork + correct type/creator. --force
    # so re-runs replace any prior entry.
    "$RB" put "$HDA@$HFS_PART" --dst "/$name" --zero 0 \
        --type APPL --creator "$creator" --force

    # Install the resource fork.
    "$RB" setrsrc "$HDA@$HFS_PART" "/$name" --from-file "$rsrc"

    rm -f "$rsrc"
done

# ---- Verify --------------------------------------------------------------
echo ""
echo "=== final volume contents ==="
"$RB" ls "$HDA@$HFS_PART" /
echo ""
"$RB" show fs-info "$HDA@$HFS_PART" 2>/dev/null || "$RB" inspect "$HDA" | sed -n '/Apple_HFS/,$p' | head -10

echo ""
echo "wrote $HDA ($(stat -c%s "$HDA") bytes) — ready for BlueSCSI"
