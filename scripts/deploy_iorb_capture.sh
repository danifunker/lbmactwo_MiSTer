#!/usr/bin/env bash
# Build #68 IORB-header capture (PIRH/PIRB/PIRR/PIRP).
#
# Boots Boot712.dsk, captures the static $3A4 IORB fields multiple times
# during the Welcome hang. The probes hold OS-set values of csCode,
# ioBuffer, ioReqCount, ioPosOffset — telling us WHAT the .Sony driver
# was asked to do before getting stuck.
#
# Captures at the same t=15..360s schedule as deploy_floppy_rate_test.sh
# (Snow's milestone timeline) so we can correlate IORB content with the
# floppy delivery state.
#
#   bash scripts/deploy_iorb_capture.sh

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
CAPDIR=scratch/hang_capture/$(date +%Y%m%d_%H%M%S)_iorb_capture
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
    log "  -- IORB header probes --"
    grep -E "IOR-ERR|HPS-DL|Mac-ResErr|Mac-DskErr|IORB-CS|IORB-BUF|IORB-REQ|IORB-POS|IORB:|IORB Iter" \
         "$CAPDIR/cpu_${label}.txt" || echo "  (no IORB lines yet)"
    log "  -- Floppy negative-control probes --"
    grep -E "FLP:|IWM:|FLT:|FLT-track" "$CAPDIR/cpu_${label}.txt" \
         || echo "  (no floppy lines)"
}

log "=== Verify build artifact ==="
LOCAL_MD5=$(md5sum output_files/LBMacTwo.rbf | awk '{print $1}')
log "local rbf md5 = $LOCAL_MD5"

if [ "$LOCAL_MD5" = "d1285647935bfbe224879230dddb889d" ] || \
   [ "$LOCAL_MD5" = "62240d3ee11ffc582250105b618b6fde" ] || \
   [ "$LOCAL_MD5" = "58506cfcf541cfd87ad61a1dbcd1cb88" ] || \
   [ "$LOCAL_MD5" = "ecd837f5634e1f04ef77b6cf97427491" ]; then
    log "ERROR: rbf md5 matches prior build (#67/#68/#69/#70)"
    log "Possible incremental-compile drop. Run: rm -rf db incremental_db && bash scripts/auto_recompile.sh"
    exit 1
fi

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

# Capture schedule: pre-Welcome, at Welcome, during hang, near bomb.
for tm in 15 30 60 120 240 360; do
    log "=== Wait until t=${tm}s ==="
    while [ $(($(date +%s) - MOUNT_TS)) -lt $tm ]; do sleep 1; done
    capture "t$(printf %03d $tm)"
done

log "=== DONE — capture dir: $CAPDIR ==="
ls -la "$CAPDIR/"
echo ""
echo "=========================="
echo "IORB summary across boot:"
echo "=========================="
for t in t015 t030 t060 t120 t240 t360; do
    if [ -f "$CAPDIR/cpu_${t}.txt" ]; then
        echo "--- $t ---"
        grep -E "IOR3|IORB-CS|IORB-BUF|IORB-REQ|IORB-POS" "$CAPDIR/cpu_${t}.txt"
    fi
done
