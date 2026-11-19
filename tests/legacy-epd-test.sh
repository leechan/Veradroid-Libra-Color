#!/bin/sh
# Native test of display/legacy/epd.c (veradroid-epd, legacy line) against an i.MX FBInk stand-in (tests/legacy-epd/fbinkstub.c,
# no panel): touch scroll mode with A2 and one update in flight, the cleanup after it, style 2, page counting after input,
# MAXDEFER, MONO (driver tests/legacy-epd/run.py). Needs Linux with gcc, python3 and the FBInk sources (FBINK_DIR, default
# ${VD_BUILD:-$HOME/veradroid-build}/legacy/build/FBInk: only fbink.h is used). Skipped (exit 0) where they are missing.
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
FB=${FBINK_DIR:-${VD_BUILD:-$HOME/veradroid-build}/legacy/build/FBInk}
[ -f "$FB/fbink.h" ] || { echo "legacy-epd-test: no fbink.h in $FB (set FBINK_DIR) - skipped"; exit 0; }
command -v gcc >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "legacy-epd-test: no gcc / python3 - skipped"; exit 0; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gcc -O2 -pthread -I "$FB" "$R/display/legacy/epd.c" "$R/tests/legacy-epd/fbinkstub.c" -lm -o "$T/epd"
exec python3 "$R/tests/legacy-epd/run.py" "$T/epd"
