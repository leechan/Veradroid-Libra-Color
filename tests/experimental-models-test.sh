#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline model-matrix: all non-PW6 profiles are EXPERIMENTAL, never VERIFIED.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
PRE=$REPO/diagnostics/compat/veradroid_preflight.sh
FIX=$HERE/fixtures/input-devices.pt_mt-comment
SB=/tmp/vd-experimental-models
rm -rf "$SB"; mkdir -p "$SB/etc" "$SB/sys/class/graphics/fb0" "$SB/dev" "$SB/proc/device-tree"
printf 'Kindle 5.19.2 (~~otaVersion~~)\n' > "$SB/etc/prettyversion.txt"
printf '8\n' > "$SB/sys/class/graphics/fb0/bits_per_pixel"
: > "$SB/dev/uinput"; : > "$SB/dev/binder"; : > "$SB/dev/vndbinder"; : > "$SB/dev/ashmem"
printf '123 binder\n58 ashmem\n' > "$SB/proc/misc"
sed -e "s|/etc/prettyversion.txt|$SB/etc/prettyversion.txt|g" \
    -e "s|/etc/version.txt|$SB/etc/version.txt|g" \
    -e "s|/sys/class/graphics/|$SB/sys/class/graphics/|g" \
    -e "s|/dev/uinput|$SB/dev/uinput|g" \
    -e "s|/dev/input/uinput|$SB/dev/input/uinput|g" \
    -e "s|/dev/binder|$SB/dev/binder|g" \
    -e "s|/dev/vndbinder|$SB/dev/vndbinder|g" \
    -e "s|/dev/ashmem|$SB/dev/ashmem|g" \
    -e "s|/proc/misc|$SB/proc/misc|g" \
    -e "s|/proc/device-tree/compatible|$SB/proc/device-tree/compatible|g" \
    "$PRE" > "$SB/preflight.sh"
run() { # model fb want
    printf '%s\0' "$1" > "$SB/proc/device-tree/compatible"
    printf '%s\n' "$2" > "$SB/sys/class/graphics/fb0/virtual_size"
    VERADROID_INPUT_DEVICES=$FIX VERADROID_BPL=32 sh "$SB/preflight.sh" --report 2>&1 | sed -n 's/^RESULT=//p'
}
fail=0
check() { got=$(run "$1" "$2"); [ "$got" = "$3" ] && echo "ok $1 $2 -> $got" || { echo "FAIL $1 $2 got=$got want=$3"; fail=1; }; }
check amazon,malbec 1236,3296 EXPERIMENTAL
check amazon,seabreeze 1272,3392 EXPERIMENTAL
check amazon,rossini 1072,2896 EXPERIMENTAL
check amazon,cava 1072,2896 EXPERIMENTAL
check amazon,barolo 1860,2480 EXPERIMENTAL
check amazon,pisco 1860,2480 REFUSE
exit "$fail"
