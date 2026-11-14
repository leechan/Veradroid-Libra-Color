#!/bin/sh
# KUAL menu: install or update VeraDroid, for jailbreaks whose library does not run .sh "books"
# (KUAL / MRPI only, older Universal jailbreaks). Same steps as the library scripts
# cloud/static/VeraDroid.sh / VeraDroid-Experimental.sh / VeraDroid-Offline.sh.
#   install.sh online | experimental | offline
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH
trap '' PIPE
LOG=/mnt/us/veradroid-install.log
say() { echo "$1"; eips 1 2 "$1                              " >/dev/null 2>&1 || true; }
fail() { say "$1"; eips 1 4 "日志：veradroid-install.log" >/dev/null 2>&1 || true; sleep 10; exit 1; }
[ "$(id -u)" = 0 ] || fail "需要越狱后的 root 权限"
mode=${1:-online}
echo "[$(date)] KUAL install.sh $mode" >> $LOG
case "$mode" in
    offline)
        for d in /mnt/us/documents /mnt/base-us/documents; do
            [ -f "$d/VeraDroid-Offline.sh" ] && exec sh "$d/VeraDroid-Offline.sh" >> $LOG 2>&1
        done
        fail "documents 里没有离线包（VeraDroid-Offline.sh）"
        ;;
    experimental) export VD_EXPERIMENTAL=1 ;;
esac
say "正在下载安装程序…"
curl -fsSL --retry 3 -o /tmp/vd-bootstrap.sh "https://veradroid.wenjin.jp/bootstrap.sh?t=$(date +%s)" >> $LOG 2>&1 \
    || fail "连不上服务器，请检查 Wi-Fi"
sh /tmp/vd-bootstrap.sh >> $LOG 2>&1 || fail "安装失败"
