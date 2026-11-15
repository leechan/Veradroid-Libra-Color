# SPDX-License-Identifier: GPL-3.0-or-later
# 设置：默认值 + 用户的 $SYS/settings.conf（shell 变量赋值，一行一个）
settings_defaults() {
    RETURN_MODE=freeze     # 返回 Kindle 时：freeze = 冻结留在内存（再打开几秒），off = 关掉
    ZRAM_MB=512            # 运行期间的压缩内存（MB），0 = 不开
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
    KFB_LIGHTF=0           # 显示：浅色过滤 0 关 1 弱 2 中 3 强：比阈值浅的颜色（浅灰 / 米色 / 浅绿底、半透明的灰色蒙层）直接变纯白，
                           # 少了抖动噪点和大面积变化，闪刷少、字更清楚（epd.c build_lut：弱 235 / 中 220 / 强 200，按原始亮度）
    KFB_DARKEN=0           # 显示：深色加深 1 = 没被滤成白的部分再压深一档（浅灰字变黑）
    KFB_SETTLE=40          # 显示：滑动 / 动画时合并中间帧，静止这么多毫秒后才刷（0 = 每帧都刷）
    KFB_MODE=0             # 显示：刷新方式 0 均衡 1 灰度最准 2 最快
    KFB_HOLD=70            # 显示：小于屏幕 3% 的首个变化（按钮高亮）暂缓这么多毫秒，和随后的整页变化合成一次刷新（0 = 不暂缓）
    KFB_SMOOTH=0           # 显示：流畅度档位。0 = 不用档位（按下面各项单独的设置，和以前完全一样）；1 流畅优先；2 均衡；3 画质优先。
                           # 选了 1 / 2 / 3 时，档位决定 KFB_PACE / KFB_HOLD / KFB_CLEAN / KFB_SETTLE / KFB_MODE（smooth_apply），其余设置照旧
    KFB_PACE=0             # 显示：跟随面板。1 = 新的一帧落在还没刷完的区域上时先不发，等面板刷完只发最新画面（滚动 / 动画按面板自己的速度走，
                           # 停下来不用再等“刷新合并”的静止时间）；开着时 KFB_SETTLE 不起作用
    KFB_CLEAN=0            # 显示：快刷（DU，黑白两级）之后画面静止这么多毫秒，把快刷过的区域用 16 级灰度补刷一遍（字的边缘、图片变细腻；不闪）。0 = 不补
    KFB_REAGL_MIN=85       # 显示（均衡刷新方式）：一帧里变化面积达到屏幕的百分之多少就用 REAGL（16 级灰、清残影、约 205 ms）而不是 DU（黑白两级、约 134 ms、
                           # 盖住原来的文字时会透出残影——下拉面板上的“底下那页的影子”就是这个）。85 = 以前的规则（只有接近整屏才用 REAGL）
    KFB_HWC=1              # 系统合成：1 = 用 hwcomposer.kindle（bin/ 里带着，开机时装进系统），每帧省 30–60 ms；0 = 原来的软件 GLES 合成。重启 Android 生效
                           # 0.93 / 1.01 起所有机型默认 1（docs/framework-project.md §9.9）
    KFB_HZ=30              # KFB_HWC=1 时的界面帧率 30 或 60（60 时触摸到出帧平均少等约 20 ms，动画多画一倍的帧）。重启 Android 生效
    KFB_ONEPAGE=0          # framework 项目：1 = 系统合成（KFB_HWC=1）时共享缓冲只用一页（省一页 RGBX，PW6 约 8.6 MB）。要 project/framework 的镜像
                           # 512 MB 机型默认 1（settings_load 里按内存设）；1 GB 机型上对话框淡入淡出多刷约一倍，默认 0
    KFB_RGB565=0           # framework 项目：1 = 不透明的应用窗口用 RGB565 缓冲（每块缓冲省一半）。要 project/framework 的镜像
                           # 512 MB 机型默认 1（settings_load 里按内存设）；1 GB 机型上多花一点 CPU（测试机实测），默认 0
    VD_AUDIO=0             # framework 项目：0 = 不起 audioserver（应用的声音调用直接返回错误；镜像里本来就没有音频 HAL）。要 project/framework 的镜像。0.93 / 1.01 起默认 0
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
    DNS_MODE=auto          # DNS：auto（Wi-Fi 自动）| aliyun | tencent | google
    G_WINDOW=40            # 双指判定窗口（毫秒）。越小单指触摸越跟手（每次触摸都要先等这么久才放给 Android）
    G_TWO_TAP_ACT=clear    # 双指轻点做什么（动作名同四角长按，见 action.sh / docs/host-settings.md）
    G_TWO_LONG_ACT=invert  # 双指长按 2 秒做什么
    WIFI_PS=auto           # Wi-Fi 省电：auto（平时省电，传书 / 大量下载时临时关）| on（一直省电）| off（Android 运行时关）
    APP_COMPILE=auto       # 应用预编译（compile.sh）：auto | speed | off
    STORAGE_AUTO=1         # 系统盘快满时自动扩大（storage.sh；只对镜像机型有意义）
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
    # Scribe（ks / ks2）：models/ks.conf 想关动画，但安装器从来不拷 models/（$VD/models 不存在），那份覆盖从没生效过：
    # Scribe 上一直是“跟随手势”，每次整页变化（点开应用、换页、桌面换页）都让控制器把 1860x2480 整屏滑进来，比 PW6 多一倍多的像素。
    # 和 PW6 / KT 一样默认关；想要的话面板 / 设置里照样能开（settings.conf 里有就按用户的）。
    case "$(cat "$SYS/model" 2>/dev/null)" in
        kt5|kt6|pw6|cs|ks|ks2) KFB_ANIM_MODE=0 ;;
    esac
    # PW5（MT8110，FBInk 认作 Bellatrix，不是 Bellatrix4）：文字发虚。和 PW6 不同的地方在面板这一侧——显示桥送出去的 8 位灰度
    # 与 Android 画的逐像素一致（pw5-5192 模拟器：1236x1648 一比一，/dev/fb0 = 对比度曲线(kfb)，没有缩放）：
    #   - 抖动：FBInk 在非 Bellatrix4 上不管什么波形都加 Y4 抖动标志，连 DU（黑白两级）也加；文字边缘的灰点被抖成噪点 → 关掉；
    #   - “均衡”方式下变化不到 85% 屏幕的帧都用 DU：微信读书翻页约 60%，字只剩黑白两级、带残影 → 50% 以上就用 REAGL（16 级灰）；
    #   - 剩下的 DU（点按钮、打字）停 600 ms 后用 GL16 补刷一遍（不闪），字的灰边回来。
    # 只是默认值：用户在面板 / 设置里改过的（settings.conf 里有）照旧。
    case "$(cat "$SYS/model" 2>/dev/null)" in
        pw5) KFB_DITHER=0; KFB_REAGL_MIN=50; KFB_CLEAN=600 ;;
        # Scribe（barolo / MT8113 Bellatrix3，也不是 Bellatrix4）：同一个 FBInk 行为。用户反馈（KS1，1.00）“有些应用里的菜单很糊”：
        # 菜单 / 弹窗只占屏幕一小块 → DU（两级）+ Y4 抖动，没有补刷。和 PW5 同样的三项默认值。
        ks|ks2) KFB_DITHER=0; KFB_REAGL_MIN=50; KFB_CLEAN=600 ;;
    esac
    # 512 MB 机型（实际内存 < 700 MB，和 lowmem_ram 一样，不看 LOWMEM 开关）：一页共享缓冲 + RGB565 窗口缓冲默认开（省 ~8 + ~8 MB）。
    # 只是默认值：机型文件和 settings.conf 照样能改（docs/framework-project.md §9.9）。
    if lowmem_ram; then KFB_ONEPAGE=1; KFB_RGB565=1; fi
    # Optional per-model overlay (models/<id>.conf). User settings.conf still wins.
    m=$(cat "$SYS/model" 2>/dev/null)
    if [ -n "$m" ] && [ -f "$VD/models/$m.conf" ]; then
        . "$VD/models/$m.conf"
    fi
    [ -f "$SYS/settings.conf" ] && . "$SYS/settings.conf"
    # 排障 / 测试用的覆盖：系统盘没挂上时也能改（settings.conf 在系统盘里）
    [ -f "$VD/slim" ] && SLIM=$(cat "$VD/slim" 2>/dev/null)
    # Low-memory mode: page-turn animation is an optional heavy feature, off unless the user chose one.
    if lowmem && ! grep -qs '^KFB_ANIM_MODE=' "$SYS/settings.conf"; then KFB_ANIM_MODE=0; fi
    # 记下全局值：面板 / 设置页显示和修改的是全局设置，不能把“当前应用的单独设置”当成全局值发布出去
    # （否则在某个应用里打开面板会看到“翻页动画关 / 刷新合并关”，再点一下别的就把它存成全局了）。
    for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_LIGHTF KFB_DARKEN KFB_MODE KFB_SETTLE KFB_HOLD KFB_SMOOTH KFB_PACE KFB_CLEAN KFB_REAGL_MIN KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN; do eval "GLOB_$k=\$$k"; done
    [ -f "$SYS/settings.app" ] && . "$SYS/settings.app"       # 当前前台应用的显示参数（cmd.sh appdisp 写，已校验）
    smooth_apply
    # 512 MB devices: default to full exit when returning to Kindle, unless the
    # user already set RETURN_MODE. A frozen WeRead + Home sits on ~200 MB and
    # is what LMK then shoots (adj 0) when the user re-opens it.
    if ! grep -q '^RETURN_MODE=' "$SYS/settings.conf" 2>/dev/null; then
        lowmem && RETURN_MODE=off
    fi
    # Kindle framework stopped: freezing Android and restarting the framework next to it would put both back in memory.
    [ "$(kindle_ui_mode)" = stop ] && RETURN_MODE=off
    # 没有命名空间的内核（固件 5.17 的 KT6 等，chroot 模式）：容器的四十多个挂载（/proc、/sys、/dev、系统盘……）直接落在 Kindle 自己的
    # 挂载表里、就在用户存储下面，而且这种模式下 freezer 组里其实没有 Android 的进程（container_start 没有把它们放进去），
    # “冻结返回”等于 Android 原样在 Kindle 界面后面接着跑。用户报告（KT6 5.17）退出后 USB 连电脑不正常、要重启才好。
    # 这种机型上返回 Kindle 一律完全退出：回到 Kindle 以后用户存储上不留任何 VeraDroid 的挂载、进程和 loop 设备（代价是再进来要重新开机）。
    if { [ -e "$VD/test-hostns" ] || [ ! -e /proc/self/ns/pid ]; } && [ "$RETURN_MODE" != off ]; then RETURN_MODE=off; RETURN_MODE_FORCED=hostns; fi
}

# 流畅度档位（KFB_SMOOTH，全局或某个应用单独设）：一个明确的选择，决定下面这几项；0 = 不用档位。
# 数值来自 PW6 真机实测。
smooth_apply() {
    case "$KFB_SMOOTH" in
        1) KFB_PACE=1; KFB_HOLD=0;  KFB_CLEAN=500; KFB_REAGL_MIN=85; KFB_MODE=0 ;;                 # 流畅优先：马上快刷（DU），跟着面板走，停下来再补一遍灰度
        2) KFB_PACE=1; KFB_HOLD=70; KFB_CLEAN=0;   KFB_REAGL_MIN=30; KFB_MODE=0 ;;                 # 均衡：按钮高亮和整页合成一次刷新；变化超过三成屏幕就直接用 REAGL
        3) KFB_PACE=0; KFB_HOLD=70; KFB_CLEAN=0;   KFB_REAGL_MIN=30; KFB_MODE=3; KFB_SETTLE=120 ;; # 画质优先：驱动自动选波形（灰度内容用 GC16），合并中间帧
        *) KFB_SMOOTH=0 ;;
    esac
}
epd_send_smooth() { epd_send PACE ${KFB_PACE:-0}; epd_send CLEAN ${KFB_CLEAN:-0}; epd_send REAGL ${KFB_REAGL_MIN:-85}; }

# 把当前设置写给桌面看（/dev/kfb/settings）
settings_publish() {
    { for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_LIGHTF KFB_DARKEN KFB_MODE KFB_SETTLE KFB_HOLD KFB_SMOOTH KFB_PACE KFB_CLEAN KFB_REAGL_MIN KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN KFB_PWRDOWN KFB_HWC KFB_HZ KFB_GESTURES KFB_ROTATE RETURN_MODE LOWMEM KINDLE_UI DNS_MODE G_TL G_TR G_BL G_BR G_EDGE_BACK G_EDGE_PANEL G_TWO_TAP G_TWO_LONG G_TWO_BACK G_TWO_SLIDE G_EDGE_SENS G_BACK_EXCLUDE G_TWO_TAP_ACT G_TWO_LONG_ACT G_TAP G_TAP_KEY WIFI_PS APP_COMPILE STORAGE_AUTO TIME_12_24 GESTURE_HINT; do eval "echo $k=\${GLOB_$k:-\$$k}"; done; } > $X/settings.tmp \
        && printf 'SYSTEM_FONT=%s\nSYSTEM_FONT_LIVE=%s\n' "$SYSTEM_FONT" "$(cat $W/sysfont/android 2>/dev/null)" >> $X/settings.tmp \
        && mv -f $X/settings.tmp $X/settings
}
# 桌面写了 ctl/settings.new（KEY=value 行）：只接受已知的键和简单的值，合并进 settings.conf，立即生效的推给显示桥
settings_apply() {
    # 先把文件挪走再读：看门狗和命令监听会同时调到这里（桌面发 apply 的同时看门狗看到 settings.new），
    # 以前两个一起读同一个文件，一个读完删掉，另一个满屏 "sed: settings.new: No such file"，那次设置可能没存上（用户诊断 632015）
    sfile=$W/settings.apply.$$.$(cut -d' ' -f1 /proc/uptime | tr -d .)
    mv -f $X/ctl/settings.new "$sfile" 2>/dev/null || return 0
    touch $SYS/settings.conf
    for k in KFB_CONTRAST KFB_DITHER KFB_FLASH KFB_INVERT KFB_LIGHTF KFB_DARKEN KFB_MODE KFB_SETTLE KFB_HOLD KFB_SMOOTH KFB_PACE KFB_CLEAN KFB_REAGL_MIN KFB_ANIM_MODE KFB_ANIM_DIR KFB_ANIM_STEPS KFB_ANIM_MIN KFB_PWRDOWN KFB_HWC KFB_HZ KFB_GESTURES KFB_ROTATE RETURN_MODE LOWMEM KINDLE_UI DNS_MODE G_TL G_TR G_BL G_BR G_EDGE_BACK G_EDGE_PANEL G_TWO_TAP G_TWO_LONG G_TWO_BACK G_TWO_SLIDE G_EDGE_SENS G_BACK_EXCLUDE G_TWO_TAP_ACT G_TWO_LONG_ACT G_TAP G_TAP_KEY WIFI_PS APP_COMPILE STORAGE_AUTO TIME_12_24 GESTURE_HINT; do
        v=$(sed -n "s/^$k=\([0-9A-Za-z._,]*\)\$/\1/p" "$sfile" | tail -1)
        [ -n "$v" ] || continue
        case "$k=$v" in LOWMEM=auto|LOWMEM=on|LOWMEM=off|KINDLE_UI=auto|KINDLE_UI=keep|KINDLE_UI=freeze|KINDLE_UI=stop|GESTURE_HINT=all|GESTURE_HINT=stuck|GESTURE_HINT=off|GESTURE_HINT=default) ;; LOWMEM=*|KINDLE_UI=*|GESTURE_HINT=*) continue ;; esac
        grep -v "^$k=" $SYS/settings.conf > "$sfile.conf" 2>/dev/null
        # KEY=default：删掉用户的设置，回到默认值（机型默认 / models/<id>.conf / settings_defaults）——桌面“恢复默认设置”用
        [ "$v" = default ] || echo "$k=$v" >> "$sfile.conf"
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
    epd_send SET $KFB_CONTRAST $KFB_DITHER $KFB_FLASH $KFB_INVERT $KFB_MODE $KFB_SETTLE ${KFB_LIGHTF:-0} ${KFB_DARKEN:-0}
    epd_send HOLD ${KFB_HOLD:-70}
    epd_send_smooth
    # 面板掉电延时：数字 = 毫秒；off = 还给驱动原来的值；没设 = 不碰
    case "$KFB_PWRDOWN" in off) epd_send PWRDOWN -1 ;; ''|*[!0-9]*) ;; *) epd_send PWRDOWN $KFB_PWRDOWN ;; esac
    dns_apply
    # 手势开关：输入程序每次触摸前看这个标记文件
    if [ "$KFB_GESTURES" = 0 ]; then touch $W/nogestures; else rm -f $W/nogestures; fi
    gestures_write
    # 新键（docs/host-settings.md）：立即生效的部分
    type wifi_ps_tick >/dev/null 2>&1 && [ ! -f $W/frozen ] && wifi_ps_tick
    type time_format_apply >/dev/null 2>&1 && alive $W/pid && time_format_apply
    [ "$APP_COMPILE" = off ] && rm -f $W/compile.queue
    t "settings applied: contrast=$KFB_CONTRAST dither=$KFB_DITHER flash=$KFB_FLASH invert=$KFB_INVERT lightf=${KFB_LIGHTF:-0} darken=${KFB_DARKEN:-0}"
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
      echo "G_TAP=${G_TAP:-1}"; echo "G_TAP_KEY=${G_TAP_KEY:-voldown}"
      cs=; for c in TL:tl TR:tr BL:bl BR:br; do eval "a=\${G_${c%%:*}:-none}"; [ "$a" = none ] || cs="$cs${cs:+,}${c#*:}"; done
      echo "G_CORNERS=${cs:-none}"   # 只有配了动作的角才算手势，别的角的长按照样给 Android
      echo "ROTATE=$(rot_deg)"; } > $W/gestures.tmp \
        && mv -f $W/gestures.tmp $W/gestures
}
