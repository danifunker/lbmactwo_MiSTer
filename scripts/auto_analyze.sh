#!/usr/bin/env bash
# Watch the captures/ directory for new probes_*.txt files and run the
# analyzer on each one, appending to captures/analysis.log.
set -u
cd "C:/Users/Alan/Documents/GitHub/lbmactwo_MiSTer"
mkdir -p captures
echo "[$(date +%H:%M:%S)] auto_analyze starting" >> captures/analysis.log
declare -A SEEN
while true; do
    for f in captures/probes_*.txt; do
        [ -f "$f" ] || continue
        if [ -z "${SEEN[$f]:-}" ]; then
            echo "================================================================" >> captures/analysis.log
            echo "[$(date)] new capture: $f" >> captures/analysis.log
            python scripts/analyze_capture.py "$f" >> captures/analysis.log 2>&1 || \
              python3 scripts/analyze_capture.py "$f" >> captures/analysis.log 2>&1 || \
              echo "  (python analyzer unavailable)" >> captures/analysis.log
            SEEN[$f]=1
        fi
    done
    sleep 30
done
