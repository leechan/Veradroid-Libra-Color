#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 把编译产物 root/（ramdisk 内容）和 system/ 合成一个根文件系统 tar.gz，所有文件属主统一为 root。
# 用法：sh mk-rootfs.sh [out目录]   输出：<out目录>/veradroid-rootfs.tar.gz
set -e
OUT=${1:?usage: sh mk-rootfs.sh <out/target/product/kindle>}
STAGE=$OUT/rootfs-stage
rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -a "$OUT/root/." "$STAGE/"
cp -a "$OUT/system/." "$STAGE/system/"
for d in data cache mnt storage sdcard dev proc sys; do [ -e "$STAGE/$d" ] || [ -L "$STAGE/$d" ] || mkdir "$STAGE/$d"; done
mkdir -p "$STAGE/storage/emulated/0"
# 2016 年的 AOSP 7.1 根证书太旧（没有 ISRG Root X1 等），很多网站 / 云盘 HTTPS 验证不过：把当前的 Mozilla 根证书补进去（不覆盖已有的）
CA=${CACERTS_EXTRA:-$(dirname "$0")/cacerts-extra}
if [ -d "$CA" ]; then
    for f in "$CA"/*.[0-9]; do
        b=$(basename "$f")
        [ -e "$STAGE/system/etc/security/cacerts/$b" ] || cp "$f" "$STAGE/system/etc/security/cacerts/$b"
    done
fi
tar --owner=0 --group=0 --numeric-owner -czf "$OUT/veradroid-rootfs.tar.gz" -C "$STAGE" .
rm -rf "$STAGE"
ls -la "$OUT/veradroid-rootfs.tar.gz"
