#!/usr/bin/env bash
# Wait for the .sof to be (re)written, program the FPGA, then capture ISSP
# probes repeatedly to see how the system state evolves over real time.
set -u
cd "C:/Users/Alan/Documents/GitHub/lbmactwo_MiSTer"
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"
mkdir -p output_files captures

SOF="output_files/LBMacTwo.sof"
PRIOR=""

# Watch for a .sof newer than the last one we processed.  The first iteration
# uses the existing .sof if it exists; subsequent iterations only act on
# fresh builds.
while true; do
    # Skip if a quartus compile is still running (avoids racing a fresh build)
    while tasklist 2>/dev/null | grep -qiE "quartus_(map|fit|asm|sta|sh)\.exe"; do
        sleep 30
    done

    if [ ! -f "$SOF" ]; then
        echo "[$(date +%H:%M:%S)] No .sof yet"
        sleep 30
        continue
    fi

    cur=$(stat -c '%Y' "$SOF" 2>/dev/null)
    if [ "$cur" = "$PRIOR" ]; then
        sleep 60
        continue
    fi
    PRIOR=$cur

    TS=$(date +%Y%m%d_%H%M%S)
    LOG="captures/run_${TS}.log"
    echo "[$(date)] New .sof detected, programming FPGA" | tee -a "$LOG"

    if ! quartus_pgm -m JTAG -c "DE-SoC [USB-1]" -o "P;$SOF@2" 2>&1 | tee -a "$LOG"; then
        echo "[$(date)] quartus_pgm failed" | tee -a "$LOG"
        sleep 60
        continue
    fi

    echo "[$(date)] Waiting 8s for boot then capturing 60 ISSP samples" | tee -a "$LOG"
    sleep 8

    quartus_stp_tcl -t scripts/issp_read.tcl 60 200 2>&1 \
        | tee "captures/probes_${TS}.txt" | tail -200 | tee -a "$LOG"

    echo "[$(date)] Capture done -> captures/probes_${TS}.txt" | tee -a "$LOG"
done
