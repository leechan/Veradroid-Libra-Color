#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression checks for the KT5/KT6 fixes found in eink-emulator (2026-11-07). No Kindle access.
# 1. PW5/KT5/KT6 device trees only say "mediatek,mt8110": bootstrap must guess the model from
#    framebuffer width (+ userstore fs) instead of falling back to pw6 and refusing.
# 2. KT6 (4.9 kernel) encrypts /mnt/base-us/system with fscrypt v1; uid 1000 cannot see the key,
#    so bootstrap must use the ext4 loop system disk there, but never on 5.x kernels (PW6).
# 3. KT6 only has /dev/loop/N nodes: loop mounting must not rely on `mount -o loop` alone.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
B=$REPO/cloud/static/bootstrap.sh
C=$REPO/host/k49/boot/lib/common.sh   # 4.9-kernel models (PW5 / KT5 / KT6) run the k49 host
fail=0
need() { grep -qE "$2" "$1" || { echo "FAIL missing in $(basename "$1"): $3"; fail=1; }; }

need "$B" '\*mt8110\*\)' 'mt8110 fallback detection'
need "$B" '1236\|1248\) guessed=pw5' 'pw5 guessed from 1236/1248 width'
need "$B" 'vfat\|msdos\) guessed=kt5' 'kt5 guessed from vfat userstore'
need "$B" 'guessed=kt6' 'kt6 guess'
need "$B" 'MODEL=\$\{VD_MODEL:-\$\{detected:-\$guessed\}\}' 'VD_MODEL still wins over guesses'
need "$B" "logon .\*fscrypt:" 'fscrypt v1 key detection'
need "$B" '4\.\*\) grep -q' 'fscrypt loop only on 4.x kernels'
need "$B" '/dev/loop/\[0-9\]\*' 'bootstrap /dev/loop/N fallback'
need "$B" '4\.\*\) meta="\$BASE/static/bootstrap-k49.json' 'online install on 4.x kernels uses the k49 bundle'
for m in pw5 kt5 kt6; do
    need "$REPO/kpm/pkg/veradroid-$m/install.sh" "export VD_MODEL=$m" "$m KPM sets VD_MODEL"
    grep -q 'veradroid-pw6-' "$REPO/kpm/pkg/veradroid-$m/install.sh" && { echo "FAIL $m KPM hardcodes the PW6 bundle"; fail=1; }
done
need "$C" '^loop_mount\(\)' 'runtime loop_mount helper'
need "$C" 'loop_mount "\$SYSTEM_IMG" "\$SYS"' 'storage_mount uses loop_mount'
need "$C" 'losetup -d "\$dev"' 'storage_umount releases the loop device'

# Functional: the guess block picks the right model for each emulator-measured device.
guess() { # compatible res fs
    model_tree=$1; res=$2; detected=
    stat() { echo "$FS"; }; FS=$3
    eval "$(sed -n '/^guessed=$/,/^fi$/p' "$B")"
    echo "$guessed"
}
check() { got=$(guess "$1" "$2" "$3"); [ "$got" = "$4" ] && echo "ok $2 $3 -> $got" || { echo "FAIL $2 $3 -> $got want $4"; fail=1; }; }
check 'mediatek,mt8110 mediatek,mt8512 ' 1248,3296 vfat pw5
check 'mediatek,mt8110 mediatek,mt8512 ' 1072,2896 vfat kt5
check 'mediatek,mt8110 mediatek,mt8512 ' 1072,2896 ext2/ext3 kt6
check 'mediatek,mt8113 ' 1272,3392 ext2/ext3 ''

[ "$fail" = 0 ] && echo "KT MODEL CHECKS OK" || echo "KT MODEL FAILURES"
exit "$fail"
