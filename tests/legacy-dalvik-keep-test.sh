#!/bin/sh
# Legacy installer (cloud/static/bootstrap-legacy.sh): dalvik-cache (the relocated boot image + app code) is kept when the
# system image did not change; a different image (or none) clears it as before. Static: no device.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
T=$(mktemp -d); trap 'rm -rf $T' EXIT
B=cloud/static/bootstrap-legacy.sh
sh -n $B || fail "syntax $B"
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
echo "legacy-dalvik-keep: ok"
