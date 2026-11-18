#!/bin/sh
# Name: VeraDroid 上传测试结果
# Author: ajie / wenjin.jp
# Icon: data:image/png;base64,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
# DontUseFBInk
# 只在模拟器上验证过的机型（实验机型安装时自动放进书库）。第一次点：整理一份去掉书名 / 文件名的测试结果，屏幕上说明要上传什么；
# 10 秒到 2 分钟内再点一次才真正上传（这就是用户的同意）。不点就什么都不发。结果文件本身一直在 USB 里的 veradroid/TEST-RESULT.txt。
{
trap '' PIPE
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH
VD=/mnt/base-us/veradroid; SYS=/mnt/base-us/system/veradroid; W=/dev/shm/veradroid; LOG=$SYS/veradroid.log
LOGF=/tmp/veradroid-report.log; exec >>$LOGF 2>&1
t() { echo "[$(date +%H:%M:%S)] $*"; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }
vd_in() { return 1; }
screen() { # 多行文字整屏显示：fbink + Kindle 自带中文字体，没有就逐行 eips
    eips -c >/dev/null 2>&1 || true
    fb=; for c in "$VD/bin/fbink" "$(command -v fbink 2>/dev/null)" /var/local/kmc/bin/fbink /mnt/us/libkh/bin/fbink; do [ -n "$c" ] && [ -x "$c" ] && "$c" -h >/dev/null 2>&1 && fb=$c && break; done
    ft=; for c in /usr/java/lib/fonts/STHeitiMedium.ttf /usr/java/lib/fonts/STSongMedium.ttf "$VD/fonts/DroidSansFallback.ttf"; do [ -f "$c" ] && ft=$c && break; done
    txt=$(printf '%s\n' "$@")
    if [ -n "$fb" ] && [ -n "$ft" ] && "$fb" -q -c -t regular="$ft",px=26,top=40,left=30,right=30 "$txt" >/dev/null 2>&1; then return 0; fi
    r=1; for l in "$@"; do eips 1 $r "$l" >/dev/null 2>&1 || true; r=$((r + 2)); done
}
[ -f $VD/boot/lib/tester.sh ] || { screen "VeraDroid 没有安装（或已经卸载），没有测试结果可传。"; sleep 8; exit 0; }
. $VD/boot/lib/tester.sh
test_on || { screen "这台 Kindle 不是“只在模拟器上验证过”的机型，不需要上传测试结果。"; sleep 8; exit 0; }
CF=/mnt/base-us/veradroid/state/confirm; OUT=/tmp/veradroid-report
mkdir -p /mnt/base-us/veradroid/state 2>/dev/null
bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); now=$(cut -d. -f1 /proc/uptime)
set -- $(cat "$CF" 2>/dev/null); cw=${1:-}; cb=${2:-}; cu=${3:-0}
rm -f "$CF"
if [ "$cw" = report ] && [ "$cb" = "$bid" ] && [ $((now - cu)) -ge 10 ] && [ $((now - cu)) -le 120 ] && [ -d $OUT ]; then
    screen "正在上传测试结果…"
    tgz=/tmp/veradroid-report.tgz; rm -f $tgz
    tar -czf $tgz -C $OUT . || { screen "打包失败，没有上传。"; sleep 8; exit 1; }
    mkdir -p $TDIR; id=$(cat $TDIR/id 2>/dev/null)
    if [ -z "$id" ]; then   # 匿名编号：T-<序列号前 4 位（机型代码）>-<随机 8 位>，不用完整序列号
        id="T-$(tr -cd '0-9A-Za-z' </proc/usid 2>/dev/null | cut -c1-4)-$(tr -cd '0-9a-f' </proc/sys/kernel/random/uuid | cut -c1-8)"; echo "$id" > $TDIR/id
    fi
    model=$(cat $VD/model 2>/dev/null | tr -cd '0-9A-Za-z_.-'); ver=$(cat $VD/version 2>/dev/null | tr -cd '0-9A-Za-z_.-')
    r=$(curl -sS --max-time 120 -F "device_id=$id" -F "model=$model" -F "version=$ver" -F "file=@$tgz" https://veradroid.wenjin.jp/api/diag/upload 2>&1)
    rm -f $tgz
    f=$(printf '%s' "$r" | sed -n 's/.*"file" *: *"\([A-Za-z0-9._-]\{1,80\}\)".*/\1/p' | head -n 1)
    if [ -n "$f" ]; then tset upload.id "$f"; test_report; rm -rf $OUT; screen "上传成功。编号：$f" "把这个编号告诉我们就能找到你的结果。谢谢！"
    else screen "上传失败（请检查 Wi-Fi 后重试）：" "$(printf '%s' "$r" | tr -cd 'A-Za-z0-9 .:=,_/()-' | cut -c1-80)" "也可以用 USB 把 veradroid/TEST-RESULT.txt 发给我们。"; fi
    sleep 12; exit 0
fi
test_bundle $OUT || { screen "整理测试结果失败。"; sleep 8; exit 1; }
kb=$(du -sk $OUT 2>/dev/null | cut -f1)
echo "report $bid $now" > "$CF"; sync
i=0; while [ $i -lt 3 ]; do
    screen "VeraDroid：上传测试结果？" "-------------------------------" \
        "要上传的内容（约 ${kb} KB，打包后更小）：" "· TEST-RESULT.txt（机型、固件、内核、各项结果）" \
        "· VeraDroid 的运行日志、内核日志、内存信息" "所有日志都已去掉书名和文件路径；" "不含书、照片、账号、Wi-Fi 密码，序列号只有前 4 位。" \
        "上传到 veradroid.wenjin.jp，只有开发者能看。" "-------------------------------" \
        "同意上传：10 秒后、2 分钟内再点一次本项。" "不同意：什么都不用做，不会上传。"
    sleep 10; i=$((i + 1))
done
exit 0
}
