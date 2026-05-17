#!/usr/bin/env bash
# Wait for any in-progress Quartus compile to exit, then kick off a fresh one.
# Designed to be run unattended.
set -u
cd "C:/Users/Alan/Documents/GitHub/lbmactwo_MiSTer"
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

LOG="output_files/auto_compile_$(date +%Y%m%d_%H%M%S).log"
mkdir -p output_files
echo "[$(date)] Waiting for existing Quartus to finish..." | tee -a "$LOG"
while tasklist 2>/dev/null | grep -qiE "quartus_(map|fit|asm|sta|sh|pgm)\.exe"; do
    sleep 30
done
echo "[$(date)] Starting compile" | tee -a "$LOG"
quartus_sh --flow compile LBMacTwo 2>&1 | tee -a "$LOG"
echo "[$(date)] Compile exit=$? at $(date)" | tee -a "$LOG"
ls -la output_files/LBMacTwo.{sof,rbf,done} 2>&1 | tee -a "$LOG"
