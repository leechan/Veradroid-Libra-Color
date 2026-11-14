#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 在 Kindle 上建一个“演示系统”（不是 Android）：只用来验证宿主程序整条链路
#（暂停 Kindle 界面 → 容器 → 画屏 → 读触摸 → 返回 → 冻结 / 解冻 → 关机恢复）。
# 它借宿主的 busybox 和 FBInk，所以建好只有几 KB。
SYS=/mnt/base-us/system/veradroid
R=$SYS/rootfs
rm -rf "$R.new"; mkdir -p "$R.new/proc" "$R.new/sys" "$R.new/dev" "$R.new/data" "$R.new/cache"
touch "$R.new/.demo"
cat > "$R.new/init" <<'EOF'
#!/bin/sh
# VeraDroid 演示系统的 init：画一屏，读触摸。点屏幕顶部 = 返回 Kindle，点底部 = 关机，点中间 = 计数。
export PATH=/bin:/usr/bin LD_LIBRARY_PATH=/lib:/usr/lib
FB="/opt/fbink -q"
FONT=/fonts/STHeitiMedium.ttf
read W H NAME < /dev/kfb/info
draw() { $FB -c -m -M -t regular=$FONT,px=44 "$1"; $FB -y 28 -t regular=$FONT,px=30 "$2"; $FB -y 33 -t regular=$FONT,px=30 "$3"; [ -n "$4" ] && $FB -y 36 -t regular=$FONT,px=26 "$4"; }
N=0
draw "VeraDroid 演示系统" "pid=$$  屏幕 ${W}x${H}  $NAME" "点上方=返回 Kindle   点下方=关机   点中间=计数"  "（别点最边缘一圈：那是全局手势区）"
X=0; Y=0
while :; do
    # 一个 input_event 是 16 字节：秒、微秒各 4 字节，type、code 各 2 字节，value 4 字节
    set -- $(dd if=/dev/input/event0 bs=16 count=1 2>/dev/null | od -An -tu2 -v)
    [ $# -ge 8 ] || { usleep 100000; continue; }
    type=$5 code=$6 val=$7
    # 休眠 / 刚解冻期间积压的触摸整段丢掉（宿主写 ctl/sleep），不然一解冻就被当成点击
    [ -f /dev/kfb/ctl/sleep ] && continue
    [ -f /dev/kfb/ctl/redraw ] && { rm -f /dev/kfb/ctl/redraw; draw "VeraDroid 演示系统（已恢复）" "pid=$$  计数 $N" "点上方=返回 Kindle   点下方=关机   点中间=计数"  "（别点最边缘一圈：那是全局手势区）"; }
    [ "$type" = 3 ] && [ "$code" = 53 ] && X=$val
    [ "$type" = 3 ] && [ "$code" = 54 ] && Y=$val
    rel=
    [ "$type" = 1 ] && [ "$code" = 330 ] && [ "$val" = 0 ] && rel=1
    [ "$type" = 3 ] && [ "$code" = 57 ] && [ "$val" = 65535 ] && rel=1
    [ -n "$rel" ] || continue
    if [ "$Y" -lt $((H / 6)) ]; then touch /dev/kfb/ctl/exit
    elif [ "$Y" -gt $((H * 3 / 4)) ]; then touch /dev/kfb/ctl/stop
    else N=$((N + 1)); draw "VeraDroid 演示系统" "触摸 #$N  x=$X y=$Y" "点上方=返回 Kindle   点下方=关机"
    fi
done
EOF
chmod 755 "$R.new/init"
rm -rf "$R"; mv "$R.new" "$R"
echo "demo rootfs ready: $R"
