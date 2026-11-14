#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid 3.0.b：暂停 → 画一屏 → 验证没人重画 → 恢复。
# 必须在用户在场、能看屏幕时运行。整个流程脱离 SSH 会话在后台跑，并带保底恢复。
#
# 用法（在 Kindle 上）：sh smoke-3.0b.sh <保持暂停的秒数，默认 12>

D=/mnt/base-us/veradroid/fw
W=/var/tmp/vdfw
FW="sh $D/framework.sh"
FBINK=/mnt/us/koreader/fbink
KFONT=/usr/java/lib/fonts/STHeitiMedium.ttf
HOLD=${1:-12}
OUT=$D/smoke-3.0b.out
mkdir -p $D

# 保底：不管怎么退出（信号、出错），都把界面恢复回来
trap '$FW start >> $OUT 2>&1; echo "trap: restored" >> $OUT' EXIT INT TERM HUP

fbhash() { dd if=/dev/fb0 bs=1272 count=1696 2>/dev/null | md5sum | cut -c1-12; }

exec > $OUT 2>&1
echo "== 3.0.b start $(date)"
echo "before: $(DISPLAY=:0 xinput list 2>&1 | grep -c kindle-input-pt) kindle-input-pt; awesome=$(pidof awesome) volumd=$(pidof volumd) kppmainapp=$(initctl status kppmainapp | head -1)"
echo "activeApp before: $(lipc-get-prop com.lab126.appmgrd activeApp)"
echo "mem before: $(awk '/MemAvailable/{print int($2/1024)" MiB"}' /proc/meminfo)"

echo; echo "== pause"
$FW stop
sleep 3
echo "after pause: awesome state=$(grep ^State /proc/$(pidof awesome | cut -d' ' -f1)/status) volumd state=$(grep ^State /proc/$(pidof volumd | cut -d' ' -f1)/status)"
echo "mem paused: $(awk '/MemAvailable/{print int($2/1024)" MiB"}' /proc/meminfo)"

echo; echo "== draw our screen"
$FBINK -q -c -m -M -t regular=$KFONT,px=48 "VeraDroid 3.0.b：Kindle 界面已暂停"
$FBINK -q -y 30 -t regular=$KFONT,px=32 "${HOLD} 秒后自动恢复"
sleep 3
H1=$(fbhash)
echo "fb hash after draw: $H1"
sleep $((HOLD - 3))
H2=$(fbhash)
echo "fb hash before resume: $H2  (same=$([ "$H1" = "$H2" ] && echo yes || echo NO))"

echo; echo "== resume"
$FW start
trap - EXIT
sleep 20
echo; echo "== after resume (+20s)"
$FW status
echo "mem after: $(awk '/MemAvailable/{print int($2/1024)" MiB"}' /proc/meminfo)"
echo "xinput: $(DISPLAY=:0 xinput list 2>&1 | grep kindle-input-pt)"
echo "== done $(date)"
