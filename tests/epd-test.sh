#!/bin/sh
# Native test of display/epd.c (veradroid-epd) against an FBInk stand-in (tests/epd/fbinkstub.c, no panel): touch scroll
# mode, page counting after input, FAST / FREEZE / H / NEWWIN / GCN (driver tests/epd/run.py). Needs Linux with gcc,
# python3 and the FBInk sources (FBINK_DIR, default ${VD_BUILD:-$HOME/veradroid-build}/rot/FBInk: only fbink.h is used).
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
FB=${FBINK_DIR:-${VD_BUILD:-$HOME/veradroid-build}/rot/FBInk}
[ "$(uname -s)" = Linux ] && [ -f "$FB/fbink.h" ] || { echo "SKIP epd-test: needs Linux and fbink.h in $FB (set FBINK_DIR)"; exit 0; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gcc -O2 -pthread -I "$FB" "$R/display/epd.c" "$R/tests/epd/fbinkstub.c" -lm -o "$T/epd"
exec python3 "$R/tests/epd/run.py" "$T/epd"
