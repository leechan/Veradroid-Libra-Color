#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Static checks for old-Kindle support (3.0.35 "legacy" chroot mode, 4.1.15 gate, kernel modules,
# signal freezing, Android-side safety patches).
set -eu
cd "$(dirname "$0")/.."
# 3.0-kernel models run the legacy host
L=host/legacy/boot
fail() { echo "FAIL: $*"; exit 1; }
B=cloud/static/bootstrap.sh
grep -q 'guessed=legacy' $B || fail "bootstrap: 3.x kernels not classified as legacy"
# 0.92+: emulator-only models (legacy / imx41) are refused by the shared installer and go through VeraDroid-Legacy.sh
# (its confirm step and installer routing are checked in emulator-only-test.sh)
grep -q 'imx41) echo "这台是老机型' $B || fail "bootstrap: PW4 / Oasis 3 not refused"
grep -q 'legacy) \[ "${VD_LEGACY_TEST:-0}" = 1 \]' $B || fail "bootstrap: legacy installable without VD_LEGACY_TEST"
grep -q '\[ "$MODEL" != legacy \] && \[ "$fwn" -lt "$fwmin" \]' $B || fail "bootstrap: firmware gate not relaxed for legacy"
grep -q 'IMGFS=ext3' $B || fail "bootstrap: no ext3 system disk for 3.x"
grep -q 'bootstrap-legacy.json' $B || fail "bootstrap: no legacy bundle meta"
grep -q 'veradroid-pw6/kmod' $B || fail "bootstrap: kmod not copied"
for f in $B $L/lib/common.sh; do grep -q 'mount -t ext3' $f || fail "$f: loop_mount has no ext3 fallback"; done
grep -q ' kmod ' $L/veradroid.sh || fail "veradroid.sh: kmod.sh not sourced"
grep -q '^kmod_load$' $L/veradroid.sh || fail "veradroid.sh: kmod_load not called"
grep -q -- '--in-chroot' $L/veradroid.sh || fail "veradroid.sh: no --in-chroot entry"
grep -q "setsid unshare -m sh" $L/lib/container.sh || fail "container: no mount-namespace start for kernels without pid namespaces"
grep -q 'touch $R/dev/vdchroot' $L/lib/container.sh || fail "container: /dev/vdchroot marker missing"
grep -q 'chmod 1777 $R/dev/vdshm' $L/lib/container.sh || fail "container: /dev/vdshm missing"
grep -q '\[ -z "$HOSTNS" \] && mount --bind $R/proc/sys/net' $L/lib/container.sh || fail "container: host /proc/sys/net writable in chroot mode"
grep -q 'chroot_pids' $L/stop.sh || fail "stop.sh: chroot processes not killed"
grep -q "index(\$2, r) == 1" $L/stop.sh || fail "stop.sh: chroot mounts not unmounted"
grep -q 'echo signal > $W/fzmode' $L/lib/freeze.sh || fail "freeze.sh: no signal mode"
grep -q 'chroot ] || hostns; then hostnet_fix_rules; hostnet_write; return 0; fi' $L/lib/network.sh || fail "network.sh: slirp started in chroot mode"
P=android/small-patches.py
grep -q '/dev/vdchroot' $P || fail "small-patches: android_reboot not guarded"
grep -q 'kernel < 4.5 has no such knob' $P || fail "small-patches: mmap_rnd_bits not tolerated"
grep -q 'vd_tmpfs_region' android/overlay/system/core/libcutils/ashmem-dev.c || fail "ashmem: no tmpfs fallback"
grep -q '/dev/vdshm/s' android/device/veradroid/kindle/shim/vdshim.c || fail "vdshim: no tmpfs fallback"
grep -q 'TARGET_CPU_VARIANT := cortex-a9' android/device/veradroid/kindle32/BoardConfig.mk || fail "kindle32 not built for Cortex-A9"
grep -q 'TARGET_USES_64_BIT_BINDER := false' android/device/veradroid/kindle32/BoardConfig.mk || fail "kindle32 not 32-bit binder"
grep -q 'vd_uaccess.h' tools/kmod/build-binder.sh || fail "binder module: put_user not routed through copy_to_user"
grep -q 'module_exit' tools/kmod/build-binder.sh || fail "binder module: not unloadable"
grep -q '^vd_in()' $L/lib/common.sh || fail "common.sh: no vd_in (nsenter fails without namespaces)"
for f in $L/lib/bootwatch.sh $L/lib/afterboot.sh $L/lib/diagboot.sh $L/lib/settings.sh; do
    grep -q 'nsenter -t' $f && fail "$f still calls nsenter directly (breaks chroot mode)"
    grep -q 'vd_in' $f || fail "$f does not use vd_in"
done
grep -q "exec chroot /proc/\$P/root /system/bin/sh" $L/ashell.sh || fail "ashell.sh has no chroot path"
grep -q 'mkdir $W/starting' $L/veradroid.sh || fail "veradroid.sh: no start lock (double tap starts two Androids)"
grep -q 'mknod /dev/input/$n' $L/lib/input.sh || fail "input.sh: uinput nodes not created on kernels without devtmpfs"
grep -q 'while ! umount "$SYS"' $L/lib/common.sh || fail "storage_umount does not retry (image stays mounted, fsck skipped)"
grep -q 'pid=$(cat $W/pid' $L/lib/settings.sh || fail "settings.sh reads the container pid from the wrong place (DNS choice ignored)"
grep -q 'binder_context_mgr_uid = -1;   /\* VeraDroid' tools/kmod/build-binder.sh || fail "binder module keeps the first context-manager uid forever"
# hostnet: Android shares the Kindle's network on kernels without net namespaces; it must never change it
grep -q '^hostnet_write()' $L/lib/network.sh || fail "network.sh: no hostnet_write"
grep -q 'chroot ] || hostns; then hostnet_fix_rules; hostnet_write' $L/lib/network.sh || fail "net_setup does not write hostnet info"
grep -q 'androidboot.vdhostnet=1' $L/veradroid.sh || fail "veradroid.sh: hostnet flag not passed to Android"
P=android/small-patches.py
for want in 'never touch the Kindle.s firewall' 'leave the Kindle.s routing alone' 'interface left unchanged' 'VdHostNet.linkProperties' 'VdHostNet.iface'; do
    grep -q "$want" $P || fail "small-patches: hostnet patch missing ($want)"
done
[ -f android/overlay/frameworks/opt/net/ethernet/java/com/android/server/ethernet/VdHostNet.java ] || fail "VdHostNet.java missing"
grep -q 'include packages/apps/PackageInstaller/Android.mk' android/device/veradroid/kindle32/Android.mk || fail "kindle32 lacks PackageInstaller (system_server dies)"
for f in $L/lib/kmod.sh $L/lib/freeze.sh $L/lib/container.sh $L/stop.sh $B; do sh -n $f || fail "syntax $f"; done
echo "legacy-models-test OK"
