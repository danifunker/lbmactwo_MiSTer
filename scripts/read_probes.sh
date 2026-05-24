#!/usr/bin/env bash
# Read the JTAG In-System probes (PADR/PSTA/PACT/.../PADB/PAD2) from the
# running FPGA. Portable: resolves the repo root from this script's location
# and adds Quartus to PATH, so it works on any machine.
set -u
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 1
export PATH="/c/intelFPGA_lite/17.0/quartus/bin64:$PATH"

quartus_stp_tcl -t scripts/cpu_state.tcl 2>&1 \
  | grep -ivE "copyright|license|agreement|partner|foregoing|associated|terms of|subscription|megacore|expressly subject|authorized distrib|including, without|applicable license|please refer|sole purpose|your use of"
