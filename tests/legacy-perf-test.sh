#!/bin/sh
# Legacy performance wiring (docs/legacy-perf.md "0.8.12 候选：跟手"): the host passes the touch scroll / priority settings
# to veradroid-epd and veradroid-input, the settings are published / accepted, the gesture file carries the drag hints,
# and the bridge / input sources know the options. Static: no device. The behaviour itself: tests/legacy-epd-test.sh
# (bridge, native) and tests/vinput-test.sh (input front end, native).
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
L=host/legacy/boot/lib
for f in $L/settings.sh $L/container.sh $L/input.sh $L/cmd.sh $L/appprof.sh; do sh -n $f || fail "syntax $f"; done
grep -q -- '--scroll-delay ${KFB_SCROLLDELAY:-500} --scroll-style ${KFB_SCROLLSTYLE:-1} --scroll-wfm ${KFB_SCROLLWFM:-a2} --nice ${KFB_EPD_NICE:--8}' $L/container.sh \
    || fail "container.sh does not pass the scroll / nice options to veradroid-epd"
grep -q -- '--rt ${INPUT_RT:-5}' $L/input.sh || fail "input.sh does not pass --rt to veradroid-input"
for k in KFB_SCROLLDELAY=500 KFB_SCROLLSTYLE=1 KFB_SCROLLWFM=a2 FAST_DRAG=1 KFB_EPD_NICE=-8 INPUT_RT=5 BOOST_MS=150; do
    grep -q "^    $k " $L/settings.sh || fail "settings.sh default $k missing"
done
n=$(grep -c 'BOOST_KHZ KFB_SCROLLDELAY KFB_SCROLLSTYLE KFB_SCROLLWFM FAST_DRAG[ A-Z_]*; do' $L/settings.sh)
[ "$n" = 2 ] || fail "settings_publish / settings_apply do not both carry the scroll keys ($n)"
grep -q 'type epd_send_scroll >/dev/null 2>&1 && epd_send_scroll' $L/cmd.sh || fail "cmd.sh apply does not send the scroll lines"
grep -q 'elif type epd_scroll_lines >/dev/null 2>&1; then' $L/appprof.sh || fail "appprof.sh does not send the scroll lines on legacy"
# the gesture file and the scroll lines, from the real functions
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
out=$(W=$T X=$T sh -c '
    t() { :; }; rot_deg() { echo 0; }
    . host/legacy/boot/lib/settings.sh
    settings_defaults
    gestures_write; cat $W/gestures
    epd_scroll_lines
    KFB_SCROLLDELAY=0 KFB_SCROLLWFM=du epd_scroll_lines' 2>&1)
for want in 'SCROLL_PX=20' 'FAST_DRAG=1' 'BOOST_MS=150' 'SCROLLDELAY 500' 'SCROLLSTYLE 1' 'SCROLLWFM a2' 'MAXDEFER 1200' 'FLIPINPUT 1000' 'SCROLLDELAY 0' 'SCROLLWFM du'; do
    printf '%s\n' "$out" | grep -qx "$want" || fail "expected '$want' in: $out"
done
# sources
for o in '"SCROLLWFM"' '"--scroll-wfm"' '"--nice"' '"SCROLL "' '"FLIPINPUT"' '"MAXDEFER"' 'WFM_A2' 'n_scroll_paced'; do
    grep -q -- "$o" display/legacy/epd.c || fail "display/legacy/epd.c: $o missing"
done
for o in '"--rt"' 'SCHED_FIFO' '"FAST_DRAG"' 'pending_moved' '"--cpufreq"' 'SCROLL 1'; do
    grep -q -- "$o" input/legacy/vinput.c || fail "input/legacy/vinput.c: $o missing"
done
# installer: dalvik-cache (the relocated boot image + app code) is kept when the system image did not change
B=cloud/static/bootstrap-legacy.sh
grep -q 'OLD_IMG=$(img_key "$SYS/rootfs")' $B && grep -q 'NEW_IMG=$(img_key "$SYS/rootfs")' $B || fail "installer: no image identity before / after the rootfs"
[ "$(grep -n 'OLD_IMG=$(img_key' $B | cut -d: -f1)" -lt "$(grep -n 'mv "$SYS/rootfs" "$SYS/rootfs.bak.$stamp"' $B | cut -d: -f1)" ] || fail "installer: OLD_IMG taken after the old rootfs is moved away"
grep -q 'vlog "dalvik-cache kept: same system image' $B || fail "installer: dalvik-cache is always cleared"
eval "$(sed -n '/^img_key() {/,/^}/p' $B)"
mkdir -p $T/r1/system/framework/arm $T/r2/system/framework/arm
for r in r1 r2; do echo ro.build.date.utc=1795000000 > $T/$r/system/build.prop; head -c 100 /dev/zero > $T/$r/system/framework/arm/boot.oat; head -c 50 /dev/zero > $T/$r/system/framework/arm/boot.art; done
[ -n "$(img_key $T/r1)" ] && [ "$(img_key $T/r1)" = "$(img_key $T/r2)" ] || fail "img_key: same image not recognised"
head -c 101 /dev/zero > $T/r2/system/framework/arm/boot.oat
[ "$(img_key $T/r1)" != "$(img_key $T/r2)" ] || fail "img_key: a different boot.oat looks the same"
[ -z "$(img_key $T/none)" ] || fail "img_key: no rootfs gives an identity"
echo "legacy-perf: ok"
