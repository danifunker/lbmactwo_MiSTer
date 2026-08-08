#!/bin/bash
#
# Convert MC68881 FPU VHDL files to Verilog using ghdl
#
# The VHDL files are the canonical source (kept for easy updates from 68881-fpga).
# The generated Verilog files are used by verilator (which cannot read VHDL).
# For Quartus/FPGA synthesis, use the VHDL files directly via mc68881.qip.
#
# Usage: ./convert_to_verilog.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# VHDL sources live in the vhdl/ subdirectory of the script's location.
cd "$SCRIPT_DIR/vhdl"

echo "=== MC68881 FPU VHDL to Verilog Converter ==="
echo ""

# Check for ghdl
if ! command -v ghdl > /dev/null 2>&1; then
    echo "Error: ghdl not found in PATH"
    echo "Install: brew install ghdl  (macOS)"
    exit 1
fi

echo "Using: $(ghdl --version | head -1)"
echo ""

# Package file (analyzed first, not synthesized standalone)
PACKAGE_FILE="mc68881_pkg.vhd"

# Top-level entity (synthesized with generics)
TOP_FILE="mc68881_top.vhd"

# All other source files (leaf units, no special handling)
UNIT_FILES=(
    mc68881_fp80_mul_unit.vhd
    mc68881_fp80_addsub_unit.vhd
    mc68881_modrem_post_unit.vhd
    mc68881_divrem_unit.vhd
    mc68881_sgl_ops_unit.vhd
    mc68881_trig_unit.vhd
    mc68881_packed_decimal_unit.vhd
    mc68881_alu.vhd
)

# Clean previous ghdl work library
rm -rf work-obj93.cf work-obj08.cf 2>/dev/null || true

# ============================================================
# Step 1: Analyze all VHDL files in dependency order
# ============================================================
echo "=== Step 1: Analyzing VHDL files ==="

# Package first (all other files depend on it)
echo "  Analyzing package: $PACKAGE_FILE"
ghdl -a --std=08 -fsynopsys -fexplicit "$PACKAGE_FILE"

# Unit files (order doesn't matter — they only depend on the package)
for f in "${UNIT_FILES[@]}"; do
    echo "  Analyzing: $f"
    ghdl -a --std=08 -fsynopsys -fexplicit "$f"
done

# Top-level last (depends on ALU and packed_decimal_unit)
echo "  Analyzing: $TOP_FILE"
ghdl -a --std=08 -fsynopsys -fexplicit "$TOP_FILE"

echo ""

# ============================================================
# Step 2: Synthesize each entity to Verilog
# ============================================================
echo "=== Step 2: Converting to Verilog ==="

convert_count=0

# Output dir = parent of vhdl/. Unit .v files land in $OUT_DIR, the
# fpu_lite top in $OUT_DIR/fpu_lite/.
OUT_DIR="$SCRIPT_DIR"

# Production build flavor = 68040-class subset: fpu_lite_g=true (no trig) PLUS
# enable_divrem_g=true (FDIV/FSQRT/FMOD/FREM/FSCALE/SGLDIV/SGLMUL in hardware).
# These MUST match mc68881_fpu_lite.vhd's generic map so the Verilator bench
# exercises the same FPU the FPGA build ships. Still NO trig/getexp/getman.
# Only regen the lite top — the per-unit .v files and the full-mode top are
# unused by the Verilator bench (it instantiates mc68881_top in fpu_lite/).
entity="${TOP_FILE%.vhd}"
mkdir -p "$OUT_DIR/fpu_lite"
out="$OUT_DIR/fpu_lite/${entity}.v"
echo "  Converting: $TOP_FILE -> $out (fpu_lite_g=true, enable_divrem_g=true)"
ghdl synth --std=08 -fsynopsys -fexplicit --latches \
    --out=verilog -gfpu_lite_g=true -genable_divrem_g=true "$entity" > "$out"
convert_count=$((convert_count + 1))  # `set -e` + post-inc returns 0 = bail

echo ""

# Strip ghdl-emitted $fatal assertions so the Verilator bench doesn't abort
# on benign reset/init checks (per the README workflow).
echo "=== Stripping \$fatal asserts ==="
sed -i.bak 's/\$fatal(1, "assertion failure n[0-9]*");/;/g' "$out"
rm "$out.bak"

# Clean up ghdl work library
rm -rf work-obj93.cf work-obj08.cf 2>/dev/null || true

echo ""
echo "=== Conversion Complete ==="
echo "Wrote $out ($(wc -l < "$out") lines)"
