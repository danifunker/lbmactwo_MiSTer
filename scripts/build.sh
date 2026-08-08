#!/usr/bin/env bash
# Build LBMacTwo.rbf via Quartus. Waits for any in-progress quartus to finish.
# Adopted from MacLC_MiSTer/scripts/build.sh: uses scripts/local.env for the
# Quartus path and PIPESTATUS so the real Quartus exit code survives the `tee`
# pipeline (the old auto_recompile.sh used `RC=$?`, which captured tee's exit,
# not quartus's). Run it directly as a background task so the harness tracks the
# build itself and notifies on completion — no separate polling watcher needed.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
if [ -r scripts/local.env ]; then . scripts/local.env; fi
export PATH="${QUARTUS_BIN:-/c/intelFPGA_lite/17.0/quartus/bin64}:$PATH"
PROJECT_NAME="${PROJECT_NAME:-LBMacTwo}"

LOG="output_files/auto_compile_$(date +%Y%m%d_%H%M%S).log"
mkdir -p output_files
echo "[$(date)] Waiting for any in-progress Quartus to finish..." | tee -a "$LOG"
while tasklist 2>/dev/null | grep -qiE "quartus_(map|fit|asm|sta|sh|pgm)\.exe"; do
    sleep 30
done
touch output_files/.compile_in_progress
echo "[$(date)] Starting compile $PROJECT_NAME" | tee -a "$LOG"
quartus_sh --flow compile "$PROJECT_NAME" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
rm -f output_files/.compile_in_progress
echo "[$(date)] Compile exit=$RC at $(date)" | tee -a "$LOG"
ls -la output_files/${PROJECT_NAME}.{sof,rbf} 2>&1 | tee -a "$LOG"
exit $RC
