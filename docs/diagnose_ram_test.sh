#!/bin/bash
# diagnose_ram_test.sh — Diagnose why the Mac II ROM RAM test fails
#
# Background:
#   The Mac II ROM enters the test manager (serial diagnostic console) after
#   normal boot because the RAM test at ROM offset 0x2BBC fails. The test is
#   called from the normal boot path at 0x00B6 (jsr $2BBC). When it returns
#   with d6 != 0, the ROM branches to the error handler at 0x2CCC, which
#   eventually reaches Error1Handler (0x2C3C) and TMEntry1 (0x2E96).
#
# How the RAM test works (ROM offset 0x3714):
#   1. Fills memory from a0 to a1 with 12-byte pattern: 6DB6DB6D B6DB6DB6 DB6DB6DB
#   2. XOR-chain verify pass 1: starting from beginning, XOR each long with next
#   3. XOR-chain verify pass 2: same from beginning again
#   4. Reads back final 12 bytes, XORs with expected pattern
#   5. ORs any mismatches into d6 — if d6 != 0, test failed
#
# RAM configuration (verilator sim):
#   configRAMSize = 2'b10 (4MB)
#   VIA2 PA[7:6] returns 01 → ROM selects 4MB from size table at 0x36BA
#   Test range: a0=0x000000 to a1=0x400000 (or sp-based subset)
#
# The test runs in two phases:
#   Phase 1 (d7=3): Tests a0..min(a2, a1) where a2 = hole boundary
#   Phase 2 (d7=4): Tests a2..a1 (remaining RAM above hole)
#
# Usage:
#   cd verilator
#   ./docs/diagnose_ram_test.sh [--rebuild]

set -e
cd "$(dirname "$0")/.."
cd verilator

REBUILD=0
if [ "$1" = "--rebuild" ]; then
    REBUILD=1
fi

SIM=./obj_dir/Vemu
OUTPUT=sim_output_ramdiag.txt

# Check sim binary exists
if [ ! -x "$SIM" ] || [ $REBUILD -eq 1 ]; then
    echo "Building sim..."
    make clean && make
fi

echo "=== Mac II ROM RAM Test Diagnostic ==="
echo ""
echo "Running sim (800 frames, output to $OUTPUT)..."
$SIM --stop-at-frame 800 > "$OUTPUT" 2>&1

echo ""
echo "=== Key Boot Sequence Events ==="
grep -E "STARTINIT1|NORMAL BOOT|ERROR1HANDLER|TMENTRY1|BTST #26|ROM CHECKSUM" "$OUTPUT" || true

echo ""
echo "=== RAM Test Timeline ==="
echo "Looking for RAMTest entry (PC=40802BBC) and exit (PC=40802C28)..."
grep -E "PC=40802BB[C-F]|PC=40802C[0-3]" "$OUTPUT" | head -20 || true

echo ""
echo "=== Bus Errors During Boot ==="
grep "BERR" "$OUTPUT" | grep -v "BERR=0" | head -20 || true
grep "\*\*\* BERR" "$OUTPUT" | head -20 || true

echo ""
echo "=== RAM Write Activity Around Test (cycle 14184000-14234000) ==="
# The RAM test runs roughly cycles 14185000-14233000
# Look for any anomalous RAM access patterns
grep "PCTRACE 1418[5-9]\|PCTRACE 1419\|PCTRACE 142[0-3]" "$OUTPUT" \
    | grep -v "PC=4080378\|PC=408039[EF]\|PC=408036[C-F]\|PC=40803[7][0-5]" \
    | head -40 || true

echo ""
echo "=== RAM Test Failure Path ==="
echo "Looking for transition from RAM test to error handler..."
grep "PCTRACE" "$OUTPUT" \
    | grep -v "PC=4080378\|PC=408039[EF]\|PC=408036[C-F]\|PC=40803[7][0-5]" \
    | awk -F'[ :]' '{t=$2; if (t >= 14233000 && t <= 14234000) print}' \
    | head -20 || true

echo ""
echo "=== Analysis ==="
echo ""
echo "ROM RAM test details:"
echo "  - ROM offset: 0x3714 (called from 0x2BBC RAMTest wrapper)"
echo "  - Pattern: 6DB6DB6D B6DB6DB6 DB6DB6DB (12 bytes, repeating)"
echo "  - Method: Fill, XOR-chain verify, read-back compare"
echo "  - Config: 4MB RAM (configRAMSize=2'b10, VIA2 PA[7:6]=01)"
echo "  - Size table at ROM 0x36BA: [1MB, 4MB, 16MB, 64MB]"
echo ""
echo "If the RAM test fails (d6 != 0), the ROM enters the test manager."
echo "Common causes:"
echo "  1. RAM read-back doesn't match what was written (data corruption)"
echo "  2. Address decoding wraps/mirrors incorrectly"
echo "  3. RAM timing issue (write not committed before read)"
echo "  4. Wrong RAM size detected (VIA2 PA[7:6] misconfigured)"
echo ""
echo "To investigate further, add RAM bus logging in sim_main.cpp during"
echo "the test window (cycles ~14185000-14233000) to compare written vs"
echo "read data at specific addresses."
echo ""
echo "Full output saved to: $OUTPUT"
