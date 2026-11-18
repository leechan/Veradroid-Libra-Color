#!/bin/sh
# VeraHome side of the bottom edge in thirds (host branch feat/edge-thirds, docs/host-settings.md): HostService opens the
# foreground app's "应用优化" page (or the panel) for ctl/act.appopt, and the gesture settings offer every thirds key with
# the same defaults as the host (G_EDGE_THIRDS=0, appopt / home / back / switch, 500 ms), in the reset list too.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
J=android/packages/VeraHome/src/com/veradroid/home
grep -q 'act.equals("appopt")) appOpt();' $J/HostService.java || fail "HostService does not handle act.appopt"
sed -n '/private void appOpt() {/,/^    }/p' $J/HostService.java > /tmp/vd-appopt.$$
grep -q 'AppDisplayActivity.class' /tmp/vd-appopt.$$ && grep -q 'Panel.open(this)' /tmp/vd-appopt.$$ && grep -q 'putExtra("pkg"' /tmp/vd-appopt.$$ || { rm -f /tmp/vd-appopt.$$; fail "appOpt: app page / panel fallback missing"; }
rm -f /tmp/vd-appopt.$$
H=$J/HomeActivity.java
grep -q '"G_EDGE_THIRDS", ONOFF_L, ONOFF_V, "0")' $H || fail "no G_EDGE_THIRDS switch (default 0)"
for kv in G_EB_L:appopt G_EB_M:home G_EB_R:back G_EB_HOLD:switch; do
    grep -q "\"${kv%%:*}\", ACT_L, ACT_V, \"${kv#*:}\")" $H || fail "no ${kv%%:*} choice with default ${kv#*:}"
done
grep -q '"G_EB_HOLD_MS", HOLD_MS_L, HOLD_MS_V, "500")' $H || fail "no G_EB_HOLD_MS choice"
grep -q 'ACT_V = {.*"appopt" }' $H || fail "appopt not in the action list"
for k in G_EDGE_THIRDS G_EB_L G_EB_M G_EB_R G_EB_HOLD G_EB_HOLD_MS; do
    sed -n '/RESET_KEYS = {/,/};/p' $H | grep -q "\"$k\"" || fail "$k not in RESET_KEYS"
done
# labels and values line up
nl=$(sed -n 's/.*ACT_L = {\(.*\)};/\1/p' $H | tr ',' '\n' | wc -l); nv=$(sed -n 's/.*ACT_V = {\(.*\)};/\1/p' $H | tr ',' '\n' | wc -l)
[ "$nl" = "$nv" ] || fail "ACT_L ($nl) and ACT_V ($nv) differ in length"
echo "edge-thirds-home: ok"
