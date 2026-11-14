#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Compare modversion CRCs from our mainline build (Module.symvers) with the real ones
# harvested from the device's own modules (pw4.crcs: "0xCRC<TAB>symbol" lines).
#   sh crccheck.sh <Module.symvers> <device.crcs> [needed-symbols-file]
# Prints: how many shared symbols agree / disagree, and for the needed list, which ones
# would be loaded with an unverified (mainline-only) CRC.
set -eu
export LC_ALL=C
SV=$1; DEV=$2; NEED=${3:-}
awk '{printf "%s %s\n", $2, $1}' "$SV" | sort > /tmp/vd_sv.$$
awk '{printf "%s %s\n", $2, $1}' "$DEV" | sort > /tmp/vd_dev.$$
join /tmp/vd_sv.$$ /tmp/vd_dev.$$ > /tmp/vd_join.$$
total=$(wc -l < /tmp/vd_join.$$)
bad=$(awk '{a=tolower($2); b=tolower($3); sub(/^0x0*/, "", a); sub(/^0x0*/, "", b); if (a != b) print}' /tmp/vd_join.$$ | tee /tmp/vd_bad.$$ | wc -l)
echo "shared=$total mismatched=$bad"
head -20 /tmp/vd_bad.$$
if [ -n "$NEED" ]; then
    sort -u "$NEED" > /tmp/vd_need.$$
    echo "needed=$(wc -l < /tmp/vd_need.$$) verified=$(join /tmp/vd_need.$$ /tmp/vd_dev.$$ | wc -l)"
    echo "unverified (mainline CRC only):"
    join -v1 /tmp/vd_need.$$ /tmp/vd_dev.$$ | tr '\n' ' '; echo
fi
rm -f /tmp/vd_sv.$$ /tmp/vd_dev.$$ /tmp/vd_join.$$ /tmp/vd_bad.$$ /tmp/vd_need.$$
