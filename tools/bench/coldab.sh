#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# coldab.sh <component>...: cold start (am start -W) of each app with interpreted code (what an odex that no longer matches
# the boot image gives) and with speed-compiled code. Leaves every app speed-compiled.
A="sh /mnt/base-us/veradroid/boot/ashell.sh"
for act in "$@"; do
  p=${act%%/*}
  for mode in interpret-only speed; do
    t0=$(cut -d. -f1 /proc/uptime)
    r=$($A "cmd package compile -m $mode -f $p" </dev/null | tr -d '\r')
    echo "COMPILE $p $mode $r $(( $(cut -d. -f1 /proc/uptime) - t0 ))s"
    for i in 1 2 3 4; do
      $A "am force-stop $p; input keyevent 3" </dev/null >/dev/null 2>&1; sleep 3
      o=$($A "am start -W -n $act" </dev/null | tr -d '\r' | grep -E "ThisTime|TotalTime|WaitTime" | tr '\n' ' ')
      echo "COLD $p $mode $i $o"
      sleep 6
    done
  done
  $A "am force-stop $p; input keyevent 3" </dev/null >/dev/null 2>&1
done
echo DONE
