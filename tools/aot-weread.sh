#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 设备侧：强制停止微信读书，做一次 speed AOT 编译，日志写 $S/aot.log。
# 由电脑经 SSH 推到 Kindle 上、脱离 SSH 启动；不要直接在前台跑（编译要几分钟）。
PKG=com.tencent.weread.eink
S=/mnt/base-us/system/veradroid
P=$(cat /dev/shm/veradroid/pid 2>/dev/null)
[ -n "$P" ] || { echo "== $(date) no container" >> $S/aot.log; exit 1; }
echo "== $(date) aot start (pid=$P)" >> $S/aot.log
nsenter -t $P -m -p /system/bin/sh -c "PATH=/system/bin; am force-stop $PKG; sleep 2; cmd package compile -m speed -f $PKG; echo rc=\$?; dumpsys package $PKG | grep -A3 Dexopt" >> $S/aot.log 2>&1
echo "== $(date) aot done" >> $S/aot.log
