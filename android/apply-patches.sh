#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 把 VeraDroid 的设备配置、覆盖文件和小补丁应用到 AOSP 7.1.1 源码树。可以重复运行。
# 用法：sh apply-patches.sh /path/to/aosp
set -e
SRC=${1:?usage: sh apply-patches.sh /path/to/aosp}
HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$SRC/device/veradroid"
# every device of ours (kindle = PW6 board; kindle_k49 / kindle_a7 / kindle32 = the per-class boards, docs/per-model-images.md)
for d in "$HERE"/device/veradroid/*/; do
    d=$(basename "$d"); rm -rf "$SRC/device/veradroid/$d"; cp -R "$HERE/device/veradroid/$d" "$SRC/device/veradroid/$d"
done
# 自己的应用（桌面）
rm -rf "$SRC/packages/apps/VeraHome"; cp -R "$HERE/packages/VeraHome" "$SRC/packages/apps/VeraHome"
# 整文件覆盖
(cd "$HERE/overlay" && find . -type f) | while read f; do
    mkdir -p "$SRC/$(dirname "$f")"
    cp "$HERE/overlay/$f" "$SRC/$f"
    echo "overlay: $f"
done
# 小补丁（用 python 做精确替换，已打过就跳过）
python3 "$HERE/small-patches.py" "$SRC"
# framework 项目（project/framework 分支，docs/framework-project.md）：框架源码改动，全部由 /dev/kfb 里的开关文件启用
python3 "$HERE/fw-patches.py" "$SRC"
