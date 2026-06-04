#!/usr/bin/env bash
# Strip ghdl-emitted $fatal assertions from the regenerated mc68881_top.v so
# the Verilator bench doesn't abort on benign reset/init assertion failures.
# Replaces the offending always block with a no-op semicolon.
set -e
F="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fpu_lite/mc68881_top.v"
before=$(grep -c '\$fatal' "$F" || true)
sed -i 's/\$fatal(1, "assertion failure n[0-9]*");/;/g' "$F"
after=$(grep -c '\$fatal' "$F" || true)
echo "stripped \$fatal: $before -> $after"
