#!/usr/bin/env bash
cd C:/Users/Alan/Documents/GitHub/lbmactwo_MiSTer
echo "================================================================"
echo "PIPELINE STATUS  @ $(date)"
echo "================================================================"
echo ""
echo "-- background processes --"
ps -ef | grep -E "auto_(capture|recompile|analyze)" | grep -v grep | awk '{ print $2 "  " $NF }' | head -10
echo ""
echo "-- quartus running --"
tasklist 2>/dev/null | grep -i quartus | head -5 || echo "  none"
echo ""
echo "-- compile flag --"
if [ -f output_files/.compile_in_progress ]; then
    echo "  FLAG SET (build in progress)"
else
    echo "  no flag (build idle)"
fi
echo ""
echo "-- recent auto_compile logs --"
ls -lat output_files/auto_compile_*.log 2>/dev/null | head -3
echo ""
echo "-- newest .sof --"
ls -lat output_files/LBMacTwo.sof 2>/dev/null
echo ""
echo "-- recent capture files --"
ls -lat captures/probes_*.txt 2>/dev/null | head -3 || echo "  no captures yet"
echo ""
echo "-- last orchestrator log lines --"
tail -8 captures/orchestrator.log 2>/dev/null
echo ""
echo "-- last analysis log lines --"
tail -15 captures/analysis.log 2>/dev/null
echo ""
echo "-- latest auto_compile log tail --"
ls -t output_files/auto_compile_*.log 2>/dev/null | head -1 | xargs -r tail -10 2>/dev/null
