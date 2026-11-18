#!/bin/sh
# KPM install hook: download and run the official PW6 installer.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
set -eu
BASE="${VD_BASE:-https://veradroid.wenjin.jp}"
show() { command -v eips >/dev/null 2>&1 && eips 1 3 "$*" >/dev/null 2>&1 || true; echo "$*"; }
# Never factory-wipe on an upgrade. Use VeraDroid-Factory.sh explicitly if a
# machine is genuinely broken; this hook must preserve Android apps/plugins.
TMP=/tmp/vd-kpm-bootstrap.$$   # 不放 Kindle 根目录（根目录只留 veradroid/）
show "正在下载 VeraDroid 安装器…"
if ! curl -fsSL --retry 4 --retry-delay 3 --connect-timeout 20 --max-time 300 "$BASE/bootstrap.sh" -o "$TMP"; then
    show "下载失败：请检查 Wi-Fi 后重试"
    rm -f "$TMP"
    exit 1
fi
show "安装器已下载，正在开始安装…"
sh "$TMP"
rc=$?
rm -f "$TMP"
if [ "$rc" != 0 ]; then show "安装失败，请回到原生 Kindle 后重试"; fi
exit $rc
