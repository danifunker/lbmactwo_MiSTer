#!/usr/bin/env bash
# Floppy-rate investigation deploy + capture (bug #6, floppy-slow hypothesis).
#
# Compares LBMacTwo's PFLP/PIWM counters against Snow's healthy-boot baseline
# (scratch/snow_compare/baseline.md). Captures byte_cnt + miss_cnt + ack_cnt
# at points aligned with Snow's milestone timeline so we can spot exactly
# where LBMacTwo falls behind.
#
# Snow milestone reference:
#   t=0.8s   ROM_trap_dispatcher_write       (0 bytes — no disk yet)
#   t=28.3s  system_fsave_fpu_detect         (413,223 bytes total)
#   t=44.5s  rom_fpu_first_reset             (1,343,949 bytes total)
#   t=52.1s  end of trace, motor off         (1,789,952 bytes total = Finder ready)
#
# LBMacTwo capture schedule:
#   t=15s    pre-disk (Snow has 0 bytes, drive spinning up)
#   t=30s    Snow's heavy-load phase 1 start (~413k bytes)
#   t=45s    Snow's heavy-load phase 2 peak (~1.34M bytes)
#   t=60s    Snow done; LBMacTwo presumably mid-boot
#   t=120s   2 min — LBMacTwo continuing
#   t=240s   4 min — LBMacTwo continuing
#   t=360s   6 min — bomb time
#
# At each timepoint we run floppy_rate.tcl with a 5-second gap to compute
# instantaneous KB/s.
#
#   bash scripts/deploy_floppy_rate_test.sh

set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1

if [ -r scripts/local.env ]; then
    # shellcheck disable=SC1091
    . scripts/local.env
fi
: "${MISTER_HOST:?set MISTER_HOST in scripts/local.env}"
: "${MISTER_SSH_KEY:?set MISTER_SSH_KEY in scripts/local.env}"
: "${QUARTUS_BIN:?set QUARTUS_BIN in scripts/local.env}"
: "${MISTER_HTTP_PORT:=8182}"
export PATH="$QUARTUS_BIN:$PATH"

MISTER=$MISTER_HOST
SSHKEY=$MISTER_SSH_KEY
HTTP="http://$MISTER:$MISTER_HTTP_PORT"
CAPDIR=scratch/hang_capture/$(date +%Y%m%d_%H%M%S)_floppy_rate
mkdir -p "$CAPDIR"

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$CAPDIR/timeline.log"; }

shot() {
    local label="$1"
    curl -s -X POST "$HTTP/api/screenshots" >/dev/null
    sleep 2
    P=$(curl -s "$HTTP/api/screenshots" \
        | python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
    curl -s -o "$CAPDIR/$label.png" "$HTTP/api/screenshots/$P"
    log "  shot: $label.png md5=$(md5sum "$CAPDIR/$label.png" | awk '{print $1}')"
}

capture() {
    local label="$1"
    log "=== Capture round '$label' ==="
    shot "shot_$label"
    log "  cpu_state.tcl..."
    quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
        | grep -vE "^Info|^    Info|^\\s*$" > "$CAPDIR/cpu_${label}.txt"
    grep -E "FLP:|IWM:|FLT:" "$CAPDIR/cpu_${label}.txt" || echo "  (no FLP/IWM/FLT lines)"
    log "  floppy_rate.tcl (5s gap)..."
    quartus_stp_tcl -t scripts/floppy_rate.tcl 5 2>&1 \
        | grep -vE "^Info|^    Info|^\\s*$" > "$CAPDIR/rate_${label}.txt"
    grep -E "^elapsed|^delta|^byte rate|^SDRAM-grant|^miss rate|^VERDICT" "$CAPDIR/rate_${label}.txt"
}

log "=== Verify build artifact ==="
LOCAL_MD5=$(md5sum output_files/LBMacTwo.rbf | awk '{print $1}')
log "local rbf md5 = $LOCAL_MD5"

log "=== SCP rbf to MiSTer ==="
scp -i "$SSHKEY" -o StrictHostKeyChecking=no -q \
    output_files/LBMacTwo.rbf \
    root@$MISTER:/media/fat/_Unstable/LBMacTwo.rbf
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no root@$MISTER \
    "md5sum /media/fat/_Unstable/LBMacTwo.rbf"

log "=== Clear stale mount state ==="
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no root@$MISTER \
    "rm -f /media/fat/config/LBMacTwo.s0"

log "=== Cold-load LBMacTwo core ==="
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"path":"_Unstable/LBMacTwo.rbf"}' \
     "$HTTP/api/launch" -w "HTTP %{http_code}\n"
sleep 6

shot "pre_mount"

log "=== Mount Boot712.dsk via OSD ==="
python scripts/mister_ws.py --delay 0.5 \
    osd sleep:1 confirm sleep:1 left sleep:0.4 down sleep:0.4 confirm

MOUNT_TS=$(date +%s)
log "mount-issued at unixtime=$MOUNT_TS"

# Wait until t=15s post-mount, then capture.
log "=== Wait until t=15s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 15 ]; do sleep 1; done
capture "t015"

log "=== Wait until t=30s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 30 ]; do sleep 1; done
capture "t030"

log "=== Wait until t=45s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 45 ]; do sleep 1; done
capture "t045"

log "=== Wait until t=60s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 60 ]; do sleep 1; done
capture "t060"

log "=== Wait until t=120s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 120 ]; do sleep 1; done
capture "t120"

log "=== Wait until t=240s ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 240 ]; do sleep 1; done
capture "t240"

log "=== Wait until t=360s (bomb time) ==="
while [ $(($(date +%s) - MOUNT_TS)) -lt 360 ]; do sleep 1; done
capture "t360"

log "=== DONE — capture dir: $CAPDIR ==="
ls -la "$CAPDIR/"
echo ""
echo "Summary of floppy-rate readings across boot:"
for t in t015 t030 t045 t060 t120 t240 t360; do
    if [ -f "$CAPDIR/rate_${t}.txt" ]; then
        echo "--- $t ---"
        grep -E "^byte rate|^miss rate|^VERDICT" "$CAPDIR/rate_${t}.txt" | head -5
    fi
done
