#!/usr/bin/env bash
# Wait for any in-progress Quartus compile to exit, then kick off a fresh
# one after a short settle delay.  Touches a flag file the orchestrator
# uses to know we're building, so it doesn't try to grab JTAG mid-compile.
# Designed to be run unattended.
set -u
# Resolve the repo root relative to this script's location so it works on any
# machine regardless of where the repo is checked out.
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

LOG="output_files/auto_compile_$(date +%Y%m%d_%H%M%S).log"
mkdir -p output_files
echo "[$(date)] Waiting for existing Quartus to finish..." | tee -a "$LOG"
while tasklist 2>/dev/null | grep -qiE "quartus_(map|fit|asm|sta|sh|pgm)\.exe"; do
    sleep 30
done
# Hold the flag from BEFORE we kick off the build until AFTER it returns,
# so the orchestrator never thinks the build is done while we're still in
# the gap between "old quartus exited" and "new quartus started".
touch output_files/.compile_in_progress
echo "[$(date)] Starting compile" | tee -a "$LOG"
quartus_sh --flow compile LBMacTwo 2>&1 | tee -a "$LOG"
RC=$?
rm -f output_files/.compile_in_progress
echo "[$(date)] Compile exit=$RC at $(date)" | tee -a "$LOG"
ls -la output_files/LBMacTwo.{sof,rbf,done} 2>&1 | tee -a "$LOG"
