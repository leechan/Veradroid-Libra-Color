# SPDX-License-Identifier: GPL-3.0-or-later
# 休眠 / 屏保：电源键和闲置休眠仍归 Kindle 的 powerd（lab126_gui 没停）。powerd 进入 / 退出屏保时广播
# goingToScreenSaver / outOfScreenSaver：进入时让容器停止写屏（ctl/sleep），画屏保；退出时去掉标记并要求整屏重绘。
screensaver_show() {
    # 每次休眠轮换一张。用户自己放的图优先（有就只用它们）：
    #   Kindle 上的 veradroid/screensaver/（USB 可见），或 Android 里的 Screensaver 文件夹（传书网页可传）。
    # 没有用户图时用 Kindle 自带的屏保图；固件里找不到才用封面缓存 / 包里的 default.png。
    # 透明背景的 PNG 不清屏，直接叠在正在读的那一页上；JPG 和不透明 PNG 先清成白底再居中按比例铺满。
    list=$W/saver.list
    : > "$list"
    for f in "$VD"/screensaver/*.[pP][nN][gG] "$VD"/screensaver/*.[jJ][pP][gG] "$VD"/screensaver/*.[jJ][pP][eE][gG] \
             "$SYS"/data/media/0/Screensaver/*.[pP][nN][gG] "$SYS"/data/media/0/Screensaver/*.[jJ][pP][gG] "$SYS"/data/media/0/Screensaver/*.[jJ][pP][eE][gG]; do
        [ -f "$f" ] || continue
        case "$f" in */default.png|*/default.PNG) continue ;; esac
        echo "$f" >> "$list"
    done
    if [ ! -s "$list" ]; then
        # 用户没放图：用 Kindle 自带的屏保图（和原系统休眠时看到的一样）
        # 只要 bg_ss*（成人版的那组）：同一目录里还有儿童模式的 bg_kids_ss* 和一张纯黑的 bg_kcblackbackground.png
        # （PW6 5.19.5 实测），全收进来会轮到儿童图和整屏黑。固件没有 bg_ss* 时才退到这个目录里别的图（仍跳过 kids / 黑底）。
        for f in /usr/share/blanket/screensaver/bg_ss*.png; do
            [ -f "$f" ] && echo "$f" >> "$list"
        done
        if [ ! -s "$list" ]; then
            for f in /usr/share/blanket/screensaver/*.png; do
                case "${f##*/}" in *kids*|*black*) continue ;; esac
                [ -f "$f" ] && echo "$f" >> "$list"
            done
        fi
    fi
    if [ ! -s "$list" ]; then
        # 这个固件上没找到自带屏保图：退回最近的书封面缓存，再不行用包里的 default.png
        for f in $(ls -t /mnt/us/system/thumbnails/thumbnail_* /mnt/base-us/system/thumbnails/thumbnail_* 2>/dev/null | head -10); do
            [ -f "$f" ] && echo "$f" >> "$list"
        done
        [ -f "$VD/screensaver/default.png" ] && echo "$VD/screensaver/default.png" >> "$list"
    fi
    n=$(wc -l < "$list" 2>/dev/null | tr -d ' ')
    [ "${n:-0}" -gt 0 ] || return 0
    i=$(cat "$W/saver.index" 2>/dev/null || echo 0)
    case "$i" in ''|*[!0-9]*) i=0 ;; esac
    i=$(( (i % n) + 1 ))
    echo "$i" > "$W/saver.index"
    img=$(sed -n "${i}p" "$list")
    [ -n "$img" ] || return 0
    if [ -x "$FBINK" ]; then
        # PNG 文件头第 26 个字节是颜色类型：4 / 6 带透明通道
        ct=$(dd if="$img" bs=1 skip=25 count=1 2>/dev/null | od -An -tu1 2>/dev/null | tr -d ' ')
        case "$(dd if="$img" bs=1 skip=1 count=3 2>/dev/null)" in PNG) ;; *) ct= ;; esac
        if [ "$ct" = 4 ] || [ "$ct" = 6 ]; then
            "$FBINK" -q -f -i "$img" -g w=-2,h=-2,halign=CENTER,valign=CENTER >/dev/null 2>&1 && { t "screensaver: $img (transparent, over the page)"; return 0; }
        else
            "$FBINK" -q -c -f -i "$img" -g w=-2,h=-2,halign=CENTER,valign=CENTER >/dev/null 2>&1 && { t "screensaver: $img"; return 0; }
        fi
        t "screensaver: fbink could not draw $img"
    fi
    # 没有带图片支持的 fbink 时退回 Kindle 自带的 eips（PW6 上只认 PNG）
    case "$img" in *.[pP][nN][gG]) /usr/sbin/eips -g "$img" >/dev/null 2>&1 && return 0 ;; esac
    [ -f "$VD/screensaver/default.png" ] && /usr/sbin/eips -g "$VD/screensaver/default.png" >/dev/null 2>&1 || true
}
sleep_watch() {
    # Do not subscribe to lipc-wait-event: on PW6/5.19 it writes its monitor
    # lines to the console even with stdout redirected, and those lines were
    # visible over VeraHome (outOfScreenSaver/goingToScreenSaver columns).
    # powerd exposes a read-only "state" property (active / screenSaver /
    # suspended), so poll it once a second. No event output can leak.
    cur=$(lipc-get-prop -s com.lab126.powerd state 2>/dev/null)
    while :; do
        st=$(lipc-get-prop -s com.lab126.powerd state 2>/dev/null)
        case "$st" in
        screenSaver|screenSaverOn|suspended|sleeping)
            if [ "$cur" != saver ]; then
                touch $X/ctl/sleep
                usleep 300000
                # Freeze Android first; otherwise its last frame can overwrite
                # the screensaver image right after eips draws it.
                # 正在装 APK（afterboot.sh 写 $W/installing）时不冻结：冻在 dex2oat 中间、几小时后解冻，PackageManager
                # 线程还卡着，system_server 会被自己的 Watchdog 杀掉（用户诊断 092A03）。ctl/sleep 已经挡住显示桥；
                # 机器真睡下去（suspended）时整个系统一起停，uptime 也停，不会触发 Watchdog。
                if alive $W/installing; then
                    touch $W/saver_nofreeze; t "screensaver: an apk is being installed, android left running"
                else
                    android_freeze && touch $W/saver_frozen
                fi
                type wifi_ps_restore >/dev/null 2>&1 && wifi_ps_restore
                screensaver_show
                cur=saver
                t "screensaver on, android frozen"
                type tset >/dev/null 2>&1 && [ -f $W/saver_frozen ] && tset sleep.ok "$(date +%H:%M:%S)"
            fi ;;
        active|charging)
            if [ "$cur" = saver ]; then
                if [ -f $W/saver_nofreeze ]; then rm -f $W/saver_nofreeze; else android_thaw 2>/dev/null; fi
                ( usleep 500000; trust_unlock ) &
                rm -f $W/saver_frozen
                rm -f $X/ctl/sleep
                epd_send REDRAW
                t "screensaver off, android thawed"
                type tset >/dev/null 2>&1 && [ -n "$(tget sleep.ok)" ] && { tset wake.ok "$(date +%H:%M:%S)"; test_report; }
            fi
            cur=active ;;
        esac
        sleep 1
    done
}
