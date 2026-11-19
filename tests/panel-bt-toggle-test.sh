#!/bin/sh
# Static check: the pull-down panel's Bluetooth tile is a switch (user feedback PW6 1.01, 2026-11-19: tapping it opened the
# Bluetooth page, which is not what a quick toggle should do). Tap = host "bt enable" / "bt disable", long press = the page.
set -u
R=$(cd "$(dirname "$0")/.." && pwd)
P=$R/android/packages/VeraHome/src/com/veradroid/home/Panel.java
fail=0
body=$(awk '/private void toggleBt\(\)/{p=1} p{print} p&&/^    }$/{exit}' "$P")
echo "$body" | grep -q 'HostLink.cmd(btOn == 1 ? "bt enable" : "bt disable")' || { echo "FAIL: tap does not switch Bluetooth"; fail=1; }
echo "$body" | grep -q 'BluetoothActivity' && { echo "FAIL: tap still opens the Bluetooth page"; fail=1; }
echo "$body" | grep -q 'finish()' && { echo "FAIL: tap still closes the panel"; fail=1; }
grep -q 'if ("bt".equals(id)) t.setOnLongClickListener' "$P" || { echo "FAIL: long press no longer opens the Bluetooth page"; fail=1; }
grep -q 'btOn = HostLink.num(st, "bton", 0)' "$P" || { echo "FAIL: tile state not read from the host status"; fail=1; }
# the host really takes these commands
for h in pw6 k49; do
    grep -q 'enable) bt_power 1' "$R/host/$h/boot/lib/bt.sh" && grep -q 'disable) bt_power 0' "$R/host/$h/boot/lib/bt.sh" ||
        { echo "FAIL: host/$h bt.sh has no bt enable / disable"; fail=1; }
done
[ $fail = 0 ] && echo "panel-bt-toggle-test: ok"
exit $fail
