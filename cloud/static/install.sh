#!/bin/sh
# VeraDroid online APK installer / updater.
# Run on a Kindle that already has VeraDroid + SSH:
#   curl -fsSL https://veradroid.wenjin.jp/install.sh | sh
set -eu
BASE="${VD_BASE:-https://veradroid.wenjin.jp}"
W=/dev/shm/veradroid
P=$(cat "$W/pid" 2>/dev/null || true)
[ -n "$P" ] && kill -0 "$P" 2>/dev/null || { echo "VeraDroid 没有运行，请先启动系统。"; exit 1; }
TMP=/mnt/base-us/system/veradroid/data/local/tmp
mkdir -p "$TMP"

install_apk() {
    pkg="$1"; label="$2"
    json=$(curl -fsSL "$BASE/api/latest?package=$pkg") || { echo "$label: 查询失败"; return 1; }
    url=$(printf '%s' "$json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
    ver=$(printf '%s' "$json" | sed -n 's/.*"version_name":"\([^"]*\)".*/\1/p')
    [ -n "$url" ] || { echo "$label: 没有发布版本"; return 1; }
    echo "下载 $label $ver ..."
    curl -fL --retry 3 -o "$TMP/online.apk" "$url" || { echo "$label: 下载失败"; return 1; }
    echo "安装 $label ..."
    nsenter -t "$P" -m -u -i -n -p -r -w/ /system/bin/sh -c \
      "export PATH=/system/bin:/system/xbin ANDROID_ROOT=/system ANDROID_DATA=/data; pm install -r -d /data/local/tmp/online.apk" || return 1
    if [ "$pkg" = "com.veradroid.ime" ]; then
        nsenter -t "$P" -m -u -i -n -p -r -w/ /system/bin/sh -c \
          "export PATH=/system/bin:/system/xbin ANDROID_ROOT=/system ANDROID_DATA=/data; ime enable com.veradroid.ime/.VeraImeService; ime set com.veradroid.ime/.VeraImeService" >/dev/null 2>&1 || true
    fi
}

install_apk com.veradroid.ime VeraIME
install_apk com.veradroid.home VeraHome
rm -f "$TMP/online.apk"
echo "完成。VeraHome 会被重启；如果画面没有变化，等几秒或按 Home。"
