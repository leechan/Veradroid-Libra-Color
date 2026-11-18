# SPDX-License-Identifier: GPL-3.0-or-later
# 设置：默认值 + 用户的 $SYS/settings.conf（shell 变量赋值，一行一个）
settings_defaults() {
    RETURN_MODE=freeze     # 返回 Kindle 时：freeze = 冻结留在内存（再打开几秒），off = 关掉
    ZRAM_MB=512            # 运行期间的压缩内存（MB），0 = 不开
    ZRAM_EXTRA=auto        # zram0 已在用、比 ZRAM_MB 小时再加一块 zram：auto（>= 700 MB 机型）| on | off
    LMK_MINFREE=auto       # lmkd 杀进程门槛：auto（按内存，见 memkeep.sh）| stock（原厂大屏表）| "页数:adj ..."（最多 6 对）
    MEM_KEEP=auto          # 桌面 / 输入法不换出（memory cgroup swappiness 0）：auto（>= 700 MB 机型）| on | off
    MEM_KEEP_APPS=         # 另外也不换出的应用（逗号分隔的包名）
    BG_STOP_MIN=0          # 后台应用定时停止：BG_STOP_APPS 里的应用离开前台超过这么多分钟就 force-stop，0 = 关
    BG_STOP_APPS=          # 逗号分隔的包名（桌面 / 输入法 / 前台应用永远不停）
    BOOT_BLOCK=1           # 1 = 第三方应用不许开机自启（pm disable 它们的开机广播接收器，闹钟 / 日历 / 待办类除外）；0 = 恢复（memkeep.sh）
    BOOT_ALLOW=            # 允许开机自启的第三方应用（逗号分隔的包名）
    WIFI_IDLE_OFF_MIN=0    # Android 在前台时 Wi-Fi 空闲（收发 < WIFI_IDLE_BPS 字节/秒）超过这么多分钟就关，换应用时再开；0 = 不关
    WIFI_IDLE_BPS=512
    SLIM=1                 # 系统瘦身（lib/slim.sh）：1 = 停掉用不上的系统服务，0 = 原样
    LOWMEM=auto            # 低内存模式：auto = 内存不到约 700 MB 的机型自动开，on / off = 强制开 / 关（见下面 lowmem 的说明）
    KINDLE_UI=auto         # Android 在前台时 Kindle 自己的界面怎么处置（lib/framework.sh）：keep 只暂停 | freeze 再把后台进程冻住 |
                           # stop 把 Java 框架和书库程序停掉腾内存（返回 Kindle 约一分钟）| auto = 低内存模式用 stop，否则 freeze
    SYSTEM_APP=home        # 启动后打开什么：home 或包名
    ANDROID_DNS="223.5.5.5 223.6.6.6"
    KFB_CONTRAST=1.3       # 显示：对比度曲线 gamma 1.0~2.5
    KFB_DITHER=3           # 硬件抖动：0 关，1 Floyd-Steinberg，2 Atkinson，3 有序
    KFB_FLASH=8            # 显示：每翻 N 页（大面积变化）整屏闪刷一次，0 = 不按页数（和 Kindle 的页面刷新一样，清残影）
    KFB_INVERT=0           # 显示：反色
    KFB_SETTLE=40          # 显示：滑动 / 动画时合并中间帧，静止这么多毫秒后才刷（0 = 每帧都刷）
    KFB_MODE=0             # 显示：刷新方式 0 均衡 1 灰度最准 2 最快
    KFB_HOLD=70            # 显示：小于屏幕 3% 的首个变化（按钮高亮）暂缓这么多毫秒，和随后的整页变化合成一次刷新（0 = 不暂缓）
    KFB_ANIM_MODE=1        # 显示：翻页动画 0 关 1 跟随手势 2 左 3 右 4 上 5 下
    KFB_ANIM_DIR=2         # 动画方向：0 下 1 上 2 左 3 右（翻下一页通常用左）
    KFB_ANIM_STEPS=12      # 动画步数：越大越慢越细腻（MTK 驱动要求 <= 刷新区域宽/高）
    KFB_ANIM_MIN=45        # 变化面积超过百分之多少才动画（微信读书翻页约 60%，给别的 App 留余量）
    KFB_ROTATE=0           # 屏幕旋转 0 竖 / 90 / 180 倒过来 / 270（度，画面顺时针转；docs/rotation.md）。180 可即时切换，90/270 要重启 Android
    G_TL=none; G_TR=none; G_BL=kindle; G_BR=none   # 四角长按的动作。左下角默认“回到 Kindle”（2026-11-14 起：Android / 应用卡住时总有一个宿主手势能出去，
                           # 手势提示的“没有响应”会说这个）；其余默认不做（握机器时大拇指压在角上 2 秒容易误触发）。只有配了动作的角才吞掉长按（G_CORNERS）
    KFB_GESTURES=1         # 全局手势总开关（底边上滑返回总是有效）
    KFB_EDGE_BACK=1        # 底边上滑返回：阅读类 App 自己也用底部上滑（微信读书：上滑显示工具栏），冲突时设 0
    # 每个手势单独的开关（veradroid-input 下一次触摸就读到，不用重启）
    G_EDGE_BACK=1          # 从最下边往上划：返回
    G_EDGE_PANEL=1         # 从最上边往下划：面板
    G_TWO_TAP=1            # 双指轻点：整屏刷新
    G_TWO_LONG=1           # 双指长按 2 秒：反色
    G_TWO_BACK=1           # 双指左右滑：返回
    G_TWO_SLIDE=1          # 双指上下滑：亮度 / 色温
    G_EDGE_SENS=1          # 边缘滑动灵敏度：0 低（条窄、要滑得长）1 标准 2 高（条宽、滑一点就算）
    G_BACK_EXCLUDE=com.tencent.weread.eink   # 这些 App 在前台时不做底边上滑返回（逗号分隔；none = 不排除）。微信读书上滑 = 阅读工具栏
    G_EDGE_THIRDS=0        # 底边分三段：1 = 从左 / 中 / 右三分之一往上划分别做 G_EB_L / G_EB_M / G_EB_R，
                           # 上划后停住不动约 G_EB_HOLD_MS 毫秒做 G_EB_HOLD；0 = 整条底边都是返回（原来的做法）。要 G_EDGE_BACK=1 且手势总开关开着
    G_EB_L=appopt          # 左段上划：当前应用的显示设置（应用优化；在桌面上 = 下拉面板）。动作名同四角长按（action.sh），none = 这段不做手势
    G_EB_M=home            # 中段上划：回到桌面
    G_EB_R=back            # 右段上划：返回
    G_EB_HOLD=switch       # 上划后停住：切换应用（最近任务）；none = 不等停住，划到就做
    G_EB_HOLD_MS=500       # 停住多久算（毫秒，200..3000）
    DNS_MODE=auto          # DNS：auto（Wi-Fi 自动）| aliyun | tencent | google
    G_WINDOW=40            # 双指判定窗口（毫秒）。越小单指触摸越跟手（每次触摸都要先等这么久才放给 Android）
    G_TWO_TAP_ACT=clear    # 双指轻点做什么（动作名同四角长按，见 action.sh / docs/host-settings.md）
    G_TWO_LONG_ACT=invert  # 双指长按 2 秒做什么
    WIFI_PS=auto           # Wi-Fi 省电：auto（平时省电，传书 / 大量下载时临时关）| on（一直省电）| off（Android 运行时关）
    APP_COMPILE=auto       # 应用预编译（compile.sh）：auto | speed | off
    TIME_12_24=auto        # 12 / 24 小时制：auto（跟 Kindle）| 12 | 24
    GESTURE_HINT=all       # 手势提示（宿主画的小方块，action.sh / docs/gesture-hint.md）：all 每个手势都提示 | stuck 只在 Android 没有响应时提示 | off 不提示。action.sh 每次手势都重读，立即生效
    SYSTEM_FONT=           # 所有应用的默认字体：Android 里的字体文件路径（/data/media/0/Fonts/…、KindleFonts/…、/system/fonts/…），空 = 原样。
                           # 重启 Android 生效（container.sh 的 sysfont_prepare / sysfont_mount）。settings.conf 里带单引号存
}
# ---- 低内存模式（一个开关）-------------------------------------------------------------------------------
# 512 MB 的机型（PW5、Kindle 2022 / KT5、KT6 和老机型）上 Kindle 自己的界面和 Android 抢同一块内存。低内存模式把相关做法收在一起：
#   1. Android 运行期间 Kindle 的书库程序（KPPMainApp）停掉；KINDLE_UI=auto 在这个模式下取 stop：连 Java 框架（cvm）也停掉
#      （KT5 模拟器实测：只停框架一项，可用内存 +50 MB、交换区空出 70 MB，见 docs/slim-android.md）；
#   2. 返回 Kindle = 完全退出 Android（不冻结留在内存里）；框架停过的话要等它重新启动，约一分钟，屏幕上有提示；
#   3. 可选的重功能默认关：翻页动画（KFB_ANIM_MODE=0）、窗口动画、几个用不上的系统应用。
# 下面这些是 512 MB 的内核上跑起来的前提，不是“模式”，只看实际内存，LOWMEM=off 也照做：
#   overcommit_memory=1、内核 LMK / lmkd 阈值、zram 扩到 256 MB、Java 堆 128m / 192m（lib/memory.sh）。
# 状态写在 /dev/kfb/ctl/status 里（lowmem= / lowmem_setting= / kindleui=），桌面可以显示；LOWMEM 和 KINDLE_UI 也能从桌面的设置改。
lowmem_ram() { _mt=$(awk '/^MemTotal:/{print $2}' /proc/meminfo); [ -n "$_mt" ] && [ "$_mt" -lt 700000 ]; }
lowmem() {
    case "${LOWMEM:-auto}" in on|1) return 0 ;; off|0) return 1 ;; esac
    lowmem_ram
}
# ---- 具体机型（legacy 包）--------------------------------------------------------------------------------
# 先看主板号（3.0 内核的 /proc/board_id，前三位是机型：亚马逊源码 include/boardid.h），没有或认不出再按硬件特征：
#   3.0：有 fsr_keypad（PagePress）= Voyage；面板短边 758 = PW2，1072 = PW3（Oasis 1 只认主板号）
#   4.1：设备树 imx7d-zelda = Oasis 2 / 3（Oasis 2 的 5.16 内核没有 PID 命名空间）；imx6sll（rex）短边 600 = 入门款 2019，否则 PW4
# 测试 / 排障：$VD/submodel 里写机型名强制指定。结果缓存在 $W/submodel（一次运行内硬件不会变）。
fb_short_side() {
    awk -F'[:x p]' '/^U:/ { w=$2; h=$3; if (w+0 > 0) { print (w < h ? w : h); exit } }' /sys/class/graphics/fb0/modes 2>/dev/null
}
model_sub() {
    [ -s "$VD/submodel" ] && { tr -cd 'a-z0-9' < "$VD/submodel"; return 0; }
    [ -n "$W" ] && [ -s "$W/submodel" ] && { cat "$W/submodel"; return 0; }
    _ms=
    case "$(uname -r)" in
        3.*)
            case "$(cut -c1-3 /proc/board_id 2>/dev/null)" in
                027|02A|02E|02F) _ms=pw2 ;;
                01A|01B|025|026|047|048) _ms=kv ;;
                067|068|13G) _ms=pw3 ;;
                078|079|07F) _ms=oa1 ;;
            esac
            if [ -z "$_ms" ]; then
                if grep -q 'Name="fsr_keypad"' /proc/bus/input/devices 2>/dev/null; then _ms=kv
                else case "$(fb_short_side)" in 758) _ms=pw2 ;; 1072) _ms=pw3 ;; esac; fi
            fi ;;
        4.1.*)
            case "$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null)" in
                *imx7d-zelda*) if [ -e /proc/self/ns/pid ]; then _ms=ko3; else _ms=oa2; fi ;;
                *imx6sll*) case "$(fb_short_side)" in 600) _ms=kt4 ;; *) _ms=pw4 ;; esac ;;
            esac ;;
    esac
    [ -n "$_ms" ] && [ -n "$W" ] && [ -d "$W" ] && echo "$_ms" > "$W/submodel" 2>/dev/null
    echo "$_ms"
}
# Kindle 界面这次怎么处置：keep / freeze / stop（旧值 normal = keep，nofw = stop）
kindle_ui_mode() {
    case "${KINDLE_UI:-auto}" in
        keep|normal) echo keep ;;
        freeze) echo freeze ;;
        stop|nofw) echo stop ;;
        *) if lowmem; then echo stop; else echo freeze; fi ;;
    esac
}

settings_load() {
    settings_defaults
    # First-install default only.  It must be applied before settings.conf:
    # otherwise every settings_apply() reset the user's animation choice to 0.
    case "$(cat "$SYS/model" 2>/dev/null)" in
        kt5|kt6|pw6) KFB_ANIM_MODE=0 ;;
    esac
    # Optional per-model overlay (models/<id>.conf). User settings.conf still wins.
    m=$(cat "$SYS/model" 2>/dev/null)
    if [ -n "$m" ] && [ -f "$VD/models/$m.conf" ]; then
        . "$VD/models/$m.conf"
    fi
    # legacy 包：安装器只按内核代际写 legacy / imx41，具体机型（pw2 / kv / pw3 / oa1 / pw4 / kt4 / oa2 / ko3）在这里按硬件认，
    # 再叠一层 models/<机型>.conf（每台机型的调优默认值）。settings.conf 仍然最后读、优先。
    # 两层：models/old-base.conf = 所有老机型共用的默认值（先验证、单独量），models/<机型>.conf = 这台机型在共用层之上的少量差异。
    MODEL_SUB=$(model_sub)
    if [ -n "$MODEL_SUB" ]; then
        [ -f "$VD/models/old-base.conf" ] && . "$VD/models/old-base.conf"
        [ -f "$VD/models/$MODEL_SUB.conf" ] && . "$VD/models/$MODEL_SUB.conf"
    fi
    [ -f "$SYS/settings.conf" ] && . "$SYS/settings.conf"
    # 排障 / 测试用的覆盖：系统盘没挂上时也能改（settings.conf 在系统盘里）
    [ -f "$VD/slim" ] && SLIM=$(cat "$VD/slim" 2>/dev/null)
    # 同上，任意设置（KEY=value 行，比如测试时 LOWMEM=off / KINDLE_UI=keep）：程序目录在用户分区上，不用先挂系统盘
    [ -f "$VD/settings.test" ] && . "$VD/settings.test"
    # Low-memory mode: page-turn animation is an optional heavy feature, off unless the user chose one.
    if lowmem && ! grep -qs '^KFB_ANIM_MODE=' "$SYS/settings.conf"; then KFB_ANIM_MODE=0; fi
    # 记下全局值：面板 / 设置页显示和修改的是全局设置，不能把“当前应用的单独设置”当成全局值发布出去
    # （否则在某个应用里打开面板会看到“翻页动画关 / 刷新合并关”，再点一下别的就把它存成全局了）。
    for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_MODE KFB_SETTLE KFB_HOLD KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN; do eval "GLOB_$k=\$$k"; done
    [ -f "$SYS/settings.app" ] && . "$SYS/settings.app"       # 当前前台应用的显示参数（cmd.sh appdisp 写，已校验）
    # 512 MB devices: default to full exit when returning to Kindle, unless the
    # user already set RETURN_MODE. A frozen WeRead + Home sits on ~200 MB and
    # is what LMK then shoots (adj 0) when the user re-opens it.
    if ! grep -q '^RETURN_MODE=' "$SYS/settings.conf" 2>/dev/null; then
        lowmem && RETURN_MODE=off
    fi
    # Kindle framework stopped: freezing Android and restarting the framework next to it would put both back in memory.
    [ "$(kindle_ui_mode)" = stop ] && RETURN_MODE=off
    # 3.0 内核没有 PID 命名空间，也没有 freezer（冻结只能逐个发 SIGSTOP）：返回 Kindle 一律完全退出，回到 Kindle 以后用户存储上
    # 不留 VeraDroid 的进程、loop 设备和系统盘挂载（USB 连电脑时用户分区要能导出；k49 chroot 模式同样的规则）。屏保仍用信号冻结（sleep.sh）。
    if [ ! -e /proc/self/ns/pid ] && [ "$RETURN_MODE" != off ]; then RETURN_MODE=off; RETURN_MODE_FORCED=hostns; fi
}

# 把当前设置写给桌面看（/dev/kfb/settings）
settings_publish() {
    { for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_MODE KFB_SETTLE KFB_HOLD KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN KFB_GESTURES KFB_ROTATE RETURN_MODE LOWMEM KINDLE_UI DNS_MODE G_TL G_TR G_BL G_BR G_EDGE_BACK G_EDGE_PANEL G_TWO_TAP G_TWO_LONG G_TWO_BACK G_TWO_SLIDE G_EDGE_SENS STORAGE_AUTO G_BACK_EXCLUDE G_EDGE_THIRDS G_EB_L G_EB_M G_EB_R G_EB_HOLD G_EB_HOLD_MS G_TWO_TAP_ACT G_TWO_LONG_ACT WIFI_PS APP_COMPILE TIME_12_24 GESTURE_HINT; do eval "echo $k=\${GLOB_$k:-\$$k}"; done; } > $X/settings.tmp \
        && printf 'SYSTEM_FONT=%s\nSYSTEM_FONT_LIVE=%s\n' "$SYSTEM_FONT" "$(cat $W/sysfont/android 2>/dev/null)" >> $X/settings.tmp \
        && mv -f $X/settings.tmp $X/settings
}
# 桌面写了 ctl/settings.new（KEY=value 行）：只接受已知的键和简单的值，合并进 settings.conf，立即生效的推给显示桥
settings_apply() {
    # 先把文件挪走再读：看门狗和命令监听会同时调到这里（桌面发 apply 的同时看门狗看到 settings.new），
    # 以前两个一起读同一个文件，一个读完删掉，另一个满屏 "sed: settings.new: No such file"，那次设置可能没存上（用户诊断）
    sfile=$W/settings.apply.$$.$(cut -d' ' -f1 /proc/uptime | tr -d .)
    mv -f $X/ctl/settings.new "$sfile" 2>/dev/null || return 0
    touch $SYS/settings.conf
    for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_MODE KFB_SETTLE KFB_HOLD KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN KFB_GESTURES KFB_ROTATE RETURN_MODE LOWMEM KINDLE_UI DNS_MODE G_TL G_TR G_BL G_BR G_EDGE_BACK G_EDGE_PANEL G_TWO_TAP G_TWO_LONG G_TWO_BACK G_TWO_SLIDE G_EDGE_SENS STORAGE_AUTO G_BACK_EXCLUDE G_EDGE_THIRDS G_EB_L G_EB_M G_EB_R G_EB_HOLD G_EB_HOLD_MS G_TWO_TAP_ACT G_TWO_LONG_ACT WIFI_PS APP_COMPILE TIME_12_24 GESTURE_HINT; do
        v=$(sed -n "s/^$k=\([0-9A-Za-z._,]*\)\$/\1/p" "$sfile" | tail -1)
        [ -n "$v" ] || continue
        case "$k=$v" in LOWMEM=auto|LOWMEM=on|LOWMEM=off|KINDLE_UI=auto|KINDLE_UI=keep|KINDLE_UI=freeze|KINDLE_UI=stop|GESTURE_HINT=all|GESTURE_HINT=stuck|GESTURE_HINT=off|GESTURE_HINT=default) ;; LOWMEM=*|KINDLE_UI=*|GESTURE_HINT=*) continue ;; esac
        grep -v "^$k=" $SYS/settings.conf > "$sfile.conf" 2>/dev/null
        echo "$k=$v" >> "$sfile.conf"
        mv -f "$sfile.conf" $SYS/settings.conf
    done
    # 系统字体：值是路径（有 /、-、空格、中文），不走上面那条只认 [0-9A-Za-z._,] 的规则。只收三个字体目录里的文件（sysfont_host），
    # 不收引号、$、`、\；带单引号写进 settings.conf（root 会 source 它）。default / none = 删掉（原样字体）。重启 Android 生效。
    if grep -q '^SYSTEM_FONT=' "$sfile"; then
        v=$(sed -n 's/^SYSTEM_FONT=//p' "$sfile" | tail -1)
        case "$v" in
            ''|default|none) v= ;;
            *[\'\"\$\`\\]*) v=bad ;;
            *) sysfont_host "$v" >/dev/null || v=bad ;;
        esac
        if [ "$v" != bad ]; then
            grep -v '^SYSTEM_FONT=' $SYS/settings.conf > "$sfile.conf" 2>/dev/null
            [ -n "$v" ] && printf "SYSTEM_FONT='%s'\n" "$v" >> "$sfile.conf"
            mv -f "$sfile.conf" $SYS/settings.conf
            rm -f $SYS/sysfont.bad $SYS/sysfont.try      # 用户重新选过：之前“开不了机”的记录作废
            t "settings: SYSTEM_FONT=${v:-stock} (restart Android to apply)"
        else
            t "settings: SYSTEM_FONT rejected"
        fi
    fi
    rm -f "$sfile" "$sfile.conf"
    settings_load
    settings_publish
    # ANIM 必须先于 SET：显示桥收到 SET 会立刻重绘，若 ANIM 在后面，这次重绘仍用旧步数，
    # 下一条 P/D 又可能先碰到旧缓冲，导致“设置里选了 6 步，日志还是 12”。
    epd_send ANIM $KFB_ANIM_MODE $KFB_ANIM_DIR $KFB_ANIM_STEPS $KFB_ANIM_MIN
    epd_send SET $KFB_CONTRAST $KFB_DITHER $KFB_FLASH $KFB_INVERT $KFB_MODE $KFB_SETTLE
    epd_send HOLD ${KFB_HOLD:-70}
    dns_apply
    # 手势开关：输入程序每次触摸前看这个标记文件
    if [ "$KFB_GESTURES" = 0 ]; then touch $W/nogestures; else rm -f $W/nogestures; fi
    gestures_write
    # 新键（docs/host-settings.md）：立即生效的部分
    type wifi_ps_tick >/dev/null 2>&1 && [ ! -f $W/frozen ] && wifi_ps_tick
    type time_format_apply >/dev/null 2>&1 && alive $W/pid && time_format_apply
    [ "$APP_COMPILE" = off ] && rm -f $W/compile.queue
    t "settings applied: contrast=$KFB_CONTRAST dither=$KFB_DITHER flash=$KFB_FLASH invert=$KFB_INVERT"
    rotate_apply      # 旋转变了才有动作（cmd.sh）
}


# 可选 DNS：Android 的 netd 里把 eth0（netId 100）的解析器换掉；不碰 Kindle 的 /etc/resolv.conf。
# auto = slirp 给的 10.157.43.3；其余是公共 DNS。
dns_apply() {
    case "$DNS_MODE" in
        aliyun)  d1=223.5.5.5; d2=223.6.6.6 ;;
        tencent) d1=119.29.29.29; d2=182.254.116.116 ;;
        google)  d1=8.8.8.8; d2=8.8.4.4 ;;
        *)       d1=10.157.43.3; d2= ;;
    esac
    # hostnet（chroot，共用 Kindle 网络）没有 slirp，10.157.43.3 不存在：auto 时用写给系统的那份 DNS（ANDROID_DNS + Kindle 的）
    if [ "$DNS_MODE" != aliyun ] && [ "$DNS_MODE" != tencent ] && [ "$DNS_MODE" != google ] && [ -s $X/hostnet ]; then
        d1=$(sed -n "s/^dns=//p" $X/hostnet | sed -n 1p); d2=$(sed -n "s/^dns=//p" $X/hostnet | sed -n 2p)
        [ -n "$d1" ] || return 0
    fi
    pid=$(cat $W/pid 2>/dev/null)   # 以前读 $X/pid（从来没人写），DNS 选择一直没生效
    [ -n "$pid" ] || return 0
    P=$pid; $(vd_in) /system/bin/sh -c "export ANDROID_DATA=/data ANDROID_ROOT=/system PATH=/system/bin; ndc resolver setnetdns 100 '' $d1 $d2" >/dev/null 2>&1
    t "dns $DNS_MODE ($d1 $d2)"
}

# 每个手势的开关写给 veradroid-input（--gconf）：它在每次触摸开始时看文件有没有变，变了就重读，立即生效
gestures_write() {
    eb=${G_EDGE_BACK:-1}; [ "${KFB_EDGE_BACK:-1}" = 0 ] && eb=0   # 旧设置 KFB_EDGE_BACK=0 仍然有效
    { echo "G_EDGE_BACK=$eb"; echo "G_EDGE_PANEL=${G_EDGE_PANEL:-1}"; echo "G_TWO_TAP=${G_TWO_TAP:-1}"; echo "G_TWO_LONG=${G_TWO_LONG:-1}"
      echo "G_TWO_BACK=${G_TWO_BACK:-1}"; echo "G_TWO_SLIDE=${G_TWO_SLIDE:-1}"; echo "G_EDGE_SENS=${G_EDGE_SENS:-1}"; echo "G_BACK_EXCLUDE=${G_BACK_EXCLUDE:-none}"
      echo "G_EDGE_THIRDS=${G_EDGE_THIRDS:-0}"; echo "G_EB_L=${G_EB_L:-appopt}"; echo "G_EB_M=${G_EB_M:-home}"; echo "G_EB_R=${G_EB_R:-back}"
      echo "G_EB_HOLD=${G_EB_HOLD:-switch}"; echo "G_EB_HOLD_MS=${G_EB_HOLD_MS:-500}"
      cs=; for c in TL:tl TR:tr BL:bl BR:br; do eval "a=\${G_${c%%:*}:-none}"; [ "$a" = none ] || cs="$cs${cs:+,}${c#*:}"; done
      echo "G_CORNERS=${cs:-none}"   # 只有配了动作的角才算手势，别的角的长按照样给 Android
      echo "ROTATE=$(rot_deg)"; } > $W/gestures.tmp \
        && mv -f $W/gestures.tmp $W/gestures
}
