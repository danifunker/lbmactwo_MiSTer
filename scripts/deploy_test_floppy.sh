#!/usr/bin/env bash
# Deploy the freshly-built RBF to the MiSTer, reload the core, OSD-mount
# Boot712.dsk, wait for the Welcome-to-Macintosh freeze, and capture three
# rounds of JTAG probes (cpu_state.tcl). Output goes to scratch/hang_capture/.
#
#   bash scripts/deploy_test_floppy.sh
#
# Personal/local connection details (MiSTer IP, SSH key, Quartus path)
# come from scripts/local.env — copy scripts/local.env.example to
# scripts/local.env and fill in your own values. local.env is gitignored.
#
# Also requires: scripts/mister_ws.py + websockets pip package.
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
CAPDIR=scratch/hang_capture/$(date +%Y%m%d_%H%M%S)
mkdir -p "$CAPDIR"

echo "[$(date)] === Verify build artifact ==="
LOCAL_MD5=$(md5sum output_files/LBMacTwo.rbf | awk '{print $1}')
echo "local rbf md5 = $LOCAL_MD5"

echo "[$(date)] === SCP rbf to MiSTer ==="
scp -i "$SSHKEY" -o StrictHostKeyChecking=no -q \
    output_files/LBMacTwo.rbf \
    root@$MISTER:/media/fat/_Unstable/LBMacTwo.rbf
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no root@$MISTER \
    "md5sum /media/fat/_Unstable/LBMacTwo.rbf"

echo "[$(date)] === Clear stale mount state (.s0) ==="
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no root@$MISTER \
    "rm -f /media/fat/config/LBMacTwo.s0"

echo "[$(date)] === Cold-load LBMacTwo core ==="
curl -s -X POST -H 'Content-Type: application/json' \
     -d '{"path":"_Unstable/LBMacTwo.rbf"}' \
     "$HTTP/api/launch" -w "HTTP %{http_code}\n"
sleep 6

echo "[$(date)] === Pre-mount screenshot ==="
curl -s -X POST "$HTTP/api/screenshots" >/dev/null
sleep 2
P=$(curl -s "$HTTP/api/screenshots" \
    | python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
curl -s -o "$CAPDIR/pre_mount.png" "$HTTP/api/screenshots/$P"

echo "[$(date)] === Mount Boot712.dsk via OSD (one osd press, then nav) ==="
python scripts/mister_ws.py --delay 0.5 \
    osd sleep:1 confirm sleep:1 left sleep:0.4 down sleep:0.4 confirm

echo "[$(date)] === Wait 25s for boot to reach Welcome and hang ==="
sleep 25

echo "[$(date)] === Mid-boot screenshot ==="
curl -s -X POST "$HTTP/api/screenshots" >/dev/null
sleep 2
P=$(curl -s "$HTTP/api/screenshots" \
    | python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
curl -s -o "$CAPDIR/at_t25.png" "$HTTP/api/screenshots/$P"
md5sum "$CAPDIR/at_t25.png"

echo "[$(date)] === Round 1 JTAG probes ==="
quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
    | grep -vE "^Info|^    Info|^\\s*$" > "$CAPDIR/probes_r1.txt"
head -10 "$CAPDIR/probes_r1.txt"
echo "..."
grep -E "FLP:|IWM:" "$CAPDIR/probes_r1.txt"

echo "[$(date)] === Sleep 30s + Round 2 probes ==="
sleep 30
curl -s -X POST "$HTTP/api/screenshots" >/dev/null
sleep 2
P=$(curl -s "$HTTP/api/screenshots" \
    | python -c "import sys,json;d=json.load(sys.stdin);d.sort(key=lambda x:x['modified']);print(d[-1]['path'])")
curl -s -o "$CAPDIR/at_t60.png" "$HTTP/api/screenshots/$P"
md5sum "$CAPDIR/at_t60.png"

quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
    | grep -vE "^Info|^    Info|^\\s*$" > "$CAPDIR/probes_r2.txt"
grep -E "FLP:|IWM:" "$CAPDIR/probes_r2.txt"

echo "[$(date)] === Sleep 30s + Round 3 probes ==="
sleep 30
quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
    | grep -vE "^Info|^    Info|^\\s*$" > "$CAPDIR/probes_r3.txt"
grep -E "FLP:|IWM:" "$CAPDIR/probes_r3.txt"

echo "[$(date)] === PC histogram (300 samples) ==="
quartus_stp_tcl -t scripts/pc_histogram_long.tcl 2>&1 \
    | grep -vE "^Info|^    Info" > "$CAPDIR/pc_histogram.txt"
head -15 "$CAPDIR/pc_histogram.txt"

echo "[$(date)] === DONE — capture dir: $CAPDIR ==="
ls -la "$CAPDIR/"
