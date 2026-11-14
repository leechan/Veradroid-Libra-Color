#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline test of overcommit_on / overcommit_restore in boot/lib/memory.sh. No Kindle access.
# Background: on 512 MB Kindles (lab126 4.9 kernel) the heuristic overcommit rejects the ART heap
# mapping and zygote crash-loops; VeraDroid sets overcommit_memory=1 while running and restores it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
SB=/tmp/vd-lowram-test
rm -rf /tmp/vd-lowram-test; mkdir -p "$SB/w" "$SB/vm"
sed -e "s|/proc/meminfo|$SB/meminfo|g" -e "s|/proc/sys/vm/|$SB/vm/|g" \
    "$REPO/host/${VARIANT:-k49}/boot/lib/memory.sh" > "$SB/memory.sh"
fail=0
run() { # memtotal_kb initial expect_running expect_after
    printf 'MemTotal:       %s kB\n' "$1" > "$SB/meminfo"
    echo "$2" > "$SB/vm/overcommit_memory"
    rm -f "$SB/w/overcommit.state"
    W=$SB/w sh -c ". '$SB/memory.sh'; t() { :; }; overcommit_on"
    r=$(cat "$SB/vm/overcommit_memory")
    W=$SB/w sh -c ". '$SB/memory.sh'; overcommit_restore"
    a=$(cat "$SB/vm/overcommit_memory")
    if [ "$r" = "$3" ] && [ "$a" = "$4" ]; then echo "ok mem=$1 init=$2 running=$r after=$a"
    else echo "FAIL mem=$1 init=$2 running=$r(want $3) after=$a(want $4)"; fail=1; fi
}
run 485604 0 1 0   # PW5 / KT5 / KT6 (512 MB)
run 485604 2 1 2   # restores whatever was there before
run 980000 0 0 0   # PW6 (957 MB): untouched
exit $fail
