#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Whole-image auto updater.  Runs detached from veradroid.sh; checks every 6h.
# Set /mnt/base-us/veradroid/autoupdate to 0 to disable.
VD=/mnt/base-us/veradroid
BASE=https://veradroid.wenjin.jp
[ -f "$VD/network.conf" ] && . "$VD/network.conf"
CURL_OPTS=
[ -n "${VD_PROXY:-}" ] && CURL_OPTS="$CURL_OPTS -x $VD_PROXY"
[ -n "${VD_IP:-}" ] && CURL_OPTS="$CURL_OPTS --resolve veradroid.wenjin.jp:443:$VD_IP --resolve veradroid.wenjin.jp:80:$VD_IP"
[ -n "${VD_DNS:-}" ] && CURL_OPTS="$CURL_OPTS --dns-servers $VD_DNS"
curl_do() { curl $CURL_OPTS "$@"; }
LOG=/mnt/base-us/veradroid-autoupdate.log
PID=/dev/shm/veradroid/autoupdate.pid
LOCK=/mnt/base-us/veradroid-autoupdate.lock
[ -f "$VD/autoupdate" ] && [ "$(cat "$VD/autoupdate")" = "0" ] && exit 0
if [ -d "$LOCK" ]; then
    old=$(cat "$LOCK/pid" 2>/dev/null)
    if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then exit 0; fi
    rm -rf "$LOCK"
fi
mkdir "$LOCK" 2>/dev/null || exit 0
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT
echo $$ > "$PID"
# 点分版本号比较：$1 比 $2 新时返回 0（0.25 > 0.24，0.21.41 > 0.21.9）
ver_gt() {
    [ "$1" = "$2" ] && return 1
    printf '%s\n%s\n' "$1" "$2" | awk -F. '
        NR == 1 { n1 = split($0, a, ".") } NR == 2 { n2 = split($0, b, ".") }
        END { n = n1 > n2 ? n1 : n2
              for (i = 1; i <= n; i++) { x = a[i] + 0; y = b[i] + 0; if (x > y) exit 0; if (x < y) exit 1 }
              exit 1 }'
}
# 当前装的版本：bootstrap 写 $VD/version 和 system/veradroid/version（很早以前写 /mnt/base-us/veradroid-version）
cur_version() {
    cat "$VD/version" 2>/dev/null || cat /mnt/base-us/system/veradroid/version 2>/dev/null || cat /mnt/base-us/veradroid-version 2>/dev/null || echo 0
}
sleep 120
while :; do
    [ -f "$VD/autoupdate" ] && [ "$(cat "$VD/autoupdate")" = "0" ] && exit 0
    cur=$(cur_version)
    # Old installs may not have a version file at all. Treat them as 0 so
    # auto-update can still bring them forward instead of silently skipping.
    [ -n "$cur" ] || cur=0
    # 与 bootstrap.sh 一致：4.9 内核机型（PW5/KT5/KT6）跟随 k49 包的版本，不跟 PW6 的 /api/bootstrap
    case "$(uname -r)" in
        4.*) meta="$BASE/static/bootstrap-k49.json?t=$(date +%s)" ;;
        *) meta="$BASE/api/bootstrap" ;;
    esac
    json=$(curl_do -fsSL --max-time 20 "$meta" 2>/dev/null) || { sleep 3600; continue; }
    # 版本号有 "version":"x" 和 "version": "x" 两种写法
    new=$(printf '%s' "$json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
    # 安装时记录的实验机型：更新时沿用，否则 bootstrap 会拒绝（要求 VD_EXPERIMENTAL=1）
    m=$(cat /mnt/base-us/system/veradroid/model 2>/dev/null)
    case "$m" in ''|pw6|cs) ;; *) export VD_MODEL="$m" VD_EXPERIMENTAL=1 ;; esac
    [ -n "$new" ] || { sleep 3600; continue; }
    # 只往新版本更新：本地版本更新（比如用离线包装了新版）时绝不降级（KT6 模拟器实测 0.25 被拉回 0.24）
    if ! ver_gt "$new" "$cur"; then
        sleep 21600
        continue
    fi
    # 不打断正在用的人：Android 在前台运行（没冻结）时，过半小时再看。冻结（回到 Kindle）或没在运行时才更新。
    P=$(cat /dev/shm/veradroid/pid 2>/dev/null)
    if [ -n "$P" ] && kill -0 "$P" 2>/dev/null && [ ! -f /dev/shm/veradroid/frozen ]; then
        sleep 1800
        continue
    fi
    echo "$(date) auto update $cur -> $new" >> "$LOG"
    # BH081-1：走到这里时用户在用 Kindle（Android 冻结或没开）。更新完不要把 Android 弹到前台盖住正在读的书：
    # VD_NO_START=1 让 bootstrap 装完不启动；冻结的旧 Android 已被 bootstrap 停掉，下次点“VeraDroid 启动”冷启动新版。
    # 日志只留最近 256 KB（下载进度行很多）。
    [ -f "$LOG" ] && [ "$(wc -c < "$LOG" 2>/dev/null || echo 0)" -gt 262144 ] && { tail -c 131072 "$LOG" > "$LOG.tmp" && mv -f "$LOG.tmp" "$LOG"; }
    # BH081-7：不要 `curl | sh`——下载中途断网/超时，sh 会执行半截脚本。先完整下载到文件，curl 成功且语法检查通过才执行。
    BS=/mnt/base-us/veradroid-autoupdate-bootstrap.sh
    rm -f "$BS.part"
    if curl_do -fsSL --max-time 120 -o "$BS.part" "$BASE/bootstrap.sh" && [ -s "$BS.part" ] && sh -n "$BS.part" 2>>"$LOG"; then
        mv -f "$BS.part" "$BS"
        # VD_AUTOUPDATE=1：下载期间用户又打开了 Android 时，安装器等用户离开再替换，不把正在用的 Android 关掉；
        # 等太久（2 小时）它以 75 退出，什么都没动，过半小时再来
        VD_AUTOUPDATE=1 VD_NO_START=1 sh "$BS" < /dev/null >> "$LOG" 2>&1
        rc=$?
        if [ $rc = 75 ]; then echo "$(date) auto update deferred: android in use" >> "$LOG"; sleep 1800; continue; fi
    else
        echo "$(date) auto update: bootstrap download incomplete/invalid, retry in 1h" >> "$LOG"
        rm -f "$BS.part"; sleep 3600; continue
    fi
    after=$(cur_version)
    if [ "$after" != "$new" ]; then
        echo "$(date) auto update stopped: version state $after != $new" >> "$LOG"
        exit 1
    fi
    sleep 21600
done
