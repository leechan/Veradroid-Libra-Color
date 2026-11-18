#!/bin/sh
# Name: VeraDroid 卸载
# Author: ajie / wenjin.jp
# Icon: data:image/png;base64,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
# DontUseFBInk
# 不放进书库（0.97 / 老机型 0.8.9 起）：老机型上它和“VeraDroid 启动”封面一样，用户点错过。安装器把它放在 veradroid/VeraDroid-Uninstall.sh，
# 平时在 Android 里 设置 → 设备与更新 → 卸载 VeraDroid；Android 起不来时用 USB 把这个文件拷进 documents，在书库里点它。
# 点一下只说明；10 秒后 2 分钟内再点一次才卸。只在模拟器上验证过的机型（veradroid/tested = emulator-only）：删掉 VeraDroid 放在
# Kindle 上的所有东西（程序、Android 系统盘和里面的数据、安装日志、书库入口），安装前的书库备份只在核对过书一本没少之后才删；
# 其他机型和 Android 里的“卸载 VeraDroid”一样（Android 里的书和账号 token 留着）。Kindle 自己的书和设置都不动。
{
trap '' PIPE
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH
VD=/mnt/base-us/veradroid
screen() { # 多行文字整屏显示：fbink + Kindle 自带中文字体，没有就逐行 eips
    eips -c >/dev/null 2>&1 || true
    fb=; for c in "$VD/bin/fbink" "$(command -v fbink 2>/dev/null)" /var/local/kmc/bin/fbink /mnt/us/libkh/bin/fbink; do [ -n "$c" ] && [ -x "$c" ] && "$c" -h >/dev/null 2>&1 && fb=$c && break; done
    ft=; for c in /usr/java/lib/fonts/STHeitiMedium.ttf /usr/java/lib/fonts/STSongMedium.ttf "$VD/fonts/DroidSansFallback.ttf"; do [ -f "$c" ] && ft=$c && break; done
    txt=$(printf '%s\n' "$@")
    if [ -n "$fb" ] && [ -n "$ft" ] && "$fb" -q -c -t regular="$ft",px=26,top=40,left=30,right=30 "$txt" >/dev/null 2>&1; then return 0; fi
    r=1; for l in "$@"; do eips 1 $r "$l" >/dev/null 2>&1 || true; r=$((r + 2)); done
}
if [ ! -f $VD/boot/uninstall.sh ]; then screen "VeraDroid 已经卸载了。"; sleep 6; exit 0; fi
# 一点就卸太危险（Oasis 3 用户：装完回到书库，这个入口排在最前面，点了第一个就被卸掉了）。第一次点只说明；
# 10 秒以后、2 分钟以内（同一次开机）再点一次才真的卸载，和“上传测试结果”一样。
CF=/mnt/base-us/veradroid/state/confirm
mkdir -p /mnt/base-us/veradroid/state 2>/dev/null
bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); now=$(cut -d. -f1 /proc/uptime)
set -- $(cat "$CF" 2>/dev/null); cw=${1:-}; cb=${2:-}; cu=${3:-0}
rm -f "$CF"
if ! { [ "$cw" = uninstall ] && [ "$cb" = "$bid" ] && [ $((now - cu)) -ge 10 ] && [ $((now - cu)) -le 120 ]; }; then
    echo "uninstall $bid $now" > "$CF"; sync
    screen "要卸载 VeraDroid 吗？ / Uninstall VeraDroid?" "" \
        "卸载会删掉 VeraDroid 和 Android 里的应用、数据（Kindle 的书和设置不动）。" \
        "确定要卸载：等 10 秒，在 2 分钟内再点一次“VeraDroid 卸载”。" \
        "不想卸载：什么都不用做，过 2 分钟这次请求就作废。" "" \
        "To uninstall: wait 10 s, then tap this entry again within 2 minutes." \
        "To keep VeraDroid: do nothing."
    sleep 10
    exit 0
fi
screen "正在卸载 VeraDroid（约 1–3 分钟），请稍候…" "Kindle 的书和设置不会动。"
cp $VD/boot/uninstall.sh /tmp/veradroid-uninstall.sh || { screen "卸载失败：无法复制卸载脚本"; sleep 8; exit 1; }
PG=0; [ "$(cat $VD/tested 2>/dev/null)" = emulator-only ] && PG=1
cd / && VD_PURGE=$PG sh /tmp/veradroid-uninstall.sh </dev/null >/dev/null 2>&1
rm -f /tmp/veradroid-uninstall.sh
sleep 8
# 卸载脚本把本入口也删了；书库刷新一下
lipc-set-prop com.lab126.scanner doFullScan 1 >/dev/null 2>&1 || true
exit 0
}
