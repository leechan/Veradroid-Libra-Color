#!/bin/sh
# Native test of input/vinput.c (veradroid-input): gestures and pass-through for multitouch protocol B, protocol A
# (with / without tracking ids) and single-touch sources, fed through an LD_PRELOAD fake evdev/uinput
# (tests/vinput/fakeevdev.c, driver tests/vinput/run.py). Needs Linux with gcc, the kernel uapi headers and python3
# (needs a Linux host; macOS has no linux/input.h).
#   sh tests/vinput-test.sh            # also compares protocol B output with input/vinput.c at $VINPUT_BASE (git rev,
#                                      # default b5f37b3 = main before fix/corner-in-edge), event for event;
#                                      # cases whose behaviour changed on purpose are listed in run.py CHANGED
#   VINPUT_BASE= sh tests/vinput-test.sh   # skip the comparison
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
[ "$(uname -s)" = Linux ] || { echo "SKIP vinput-test: needs a Linux host (linux/input.h, LD_PRELOAD)"; exit 0; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
gcc -O2 -Wall -o "$T/vinput" "$R/input/vinput.c"
gcc -O2 -shared -fPIC -o "$T/fakeevdev.so" "$R/tests/vinput/fakeevdev.c" -ldl
BASE=${VINPUT_BASE-b5f37b3}
if [ -n "$BASE" ]; then
    if [ -f "$BASE" ]; then cp "$BASE" "$T/base.c"
    elif ! git -C "$R" show "$BASE:input/vinput.c" > "$T/base.c" 2>/dev/null; then
        # a checkout without that revision (e.g. the public repository's history starts later): no comparison
        echo "note: base revision $BASE not in this checkout, skipping the comparison (set VINPUT_BASE to a file or rev)"
        BASE=
    fi
fi
if [ -n "$BASE" ]; then
    gcc -O2 -o "$T/vinput-base" "$T/base.c"
    exec python3 "$R/tests/vinput/run.py" "$T/vinput" "$T/fakeevdev.so" --base "$T/vinput-base"
fi
exec python3 "$R/tests/vinput/run.py" "$T/vinput" "$T/fakeevdev.so"
