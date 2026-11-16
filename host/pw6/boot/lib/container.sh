# SPDX-License-Identifier: GPL-3.0-or-later
# 容器：unshare 出 mount / UTS / IPC / net / PID 命名空间，在新命名空间里把 $R 变成根（pivot_root）并执行 /init。
# net 命名空间里默认只有 lo（网络由 slirp4netns 另行接入，尚未实现）。

# 触摸屏（fts_ts）、翻页键（kindle-input-pt）的事件节点；名字认不出来就按多点触摸的 ABS 位图找
input_find() {   # $1 = 设备名（正则）
    awk -v pat="$1" '/^N: Name=/ { m = ($0 ~ pat) }
        m && /^H: Handlers=/ { for (i = 1; i <= NF; i++) if (match($i, /event[0-9]+$/)) { print "/dev/input/" substr($i, RSTART); exit } }' /proc/bus/input/devices
}
touch_setup() {
    KFB_KEYS=$(input_find '"kindle-input-pt"')
    [ -n "$KFB_KEYS" ] && chmod 666 $KFB_KEYS
    export KFB_KEYS
    t "pt keys=${KFB_KEYS:-none}"
}

display_prepare() {
    rm -rf $X; mkdir -p $X/ctl
    if [ -x "$FBINK" ]; then
        eval "$($FBINK -e 2>/dev/null)"
    else
        # No FBInk (some jailbreak packages omit it): read the real framebuffer.
        # PW5 reports virtual_size=1248 (stride) while visible modes=1236.
        # Use the hardware stride width: FBInk/fb0 write in 1248-byte rows.
        v=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null)
        vw=${v%%,*}; vh=${v#*,}
        m=$(sed -n 's/.*U:\([0-9][0-9]*\)x\([0-9][0-9]*\)p.*/\1 \2/p' /sys/class/graphics/fb0/modes 2>/dev/null | head -1)
        mw=; mh=; [ -n "$m" ] && { set -- $m; mw=$1; mh=$2; }
        viewWidth=${vw:-$mw}
        viewHeight=${mh:-$vh}
        viewVisWidth=${mw:-$viewWidth}     # visible width (PW5: 1236 of the 1248-pixel rows); rotation turns inside it
        deviceName=$(cat /proc/device-tree/model 2>/dev/null | tr -d '\0')
        t "display: no fbink, fallback ${viewWidth:-1272}x${viewHeight:-1696}"
    fi
    # 旋转（docs/rotation.md）：90 / 270 时 Android 按横屏的逻辑尺寸（高 x 可见宽）开机，显示桥和触摸前端负责把它转到面板上
    case "$(rot_deg)" in
        90|270) echo "${viewHeight:-1696} ${viewVisWidth:-${viewWidth:-1272}} ${deviceName:-PaperWhite 6}" > $X/info ;;
        *)      echo "${viewWidth:-1272} ${viewHeight:-1696} ${deviceName:-PaperWhite 6}" > $X/info ;;
    esac
    # Hardware model detected by bootstrap; Android's ro.product.model is generic.
    m=$(cat $SYS/model 2>/dev/null | tr -d '\r\n')
    [ -n "$m" ] && echo "$m" > $X/model
    hwc_prepare
    chmod -R 777 $X
}
# 系统合成：hwcomposer.kindle.so 随宿主程序发（bin/），开机前装进系统的 /system/lib/hw；
# 用不用由 $X/hwc.off 决定（模块自己在 SurfaceFlinger 打开它时看这个文件），所以装着也不影响 KFB_HWC=0 的机器。
hwc_prepare() {
    if [ -f "$VD/bin/hwcomposer.kindle.so" ] && [ -d "$R/system/lib/hw" ]; then
        if ! cmp -s "$VD/bin/hwcomposer.kindle.so" "$R/system/lib/hw/hwcomposer.kindle.so"; then
            cp "$VD/bin/hwcomposer.kindle.so" "$R/system/lib/hw/hwcomposer.kindle.so.new" && chmod 644 "$R/system/lib/hw/hwcomposer.kindle.so.new" \
                && mv -f "$R/system/lib/hw/hwcomposer.kindle.so.new" "$R/system/lib/hw/hwcomposer.kindle.so" && t "display: hwcomposer.kindle.so installed"
        fi
    fi
    if [ "$KFB_HWC" = 1 ] && [ -f "$R/system/lib/hw/hwcomposer.kindle.so" ]; then rm -f $X/hwc.off; else touch $X/hwc.off; fi
    case "$KFB_HZ" in 60|20|15) echo $KFB_HZ > $X/hz ;; *) echo 30 > $X/hz ;; esac
    # 对话框遮罩（hwcomposer.kindle 的 hwc.dim，0-255）：KFB_DIM 是百分比，off = -1（遮罩帧交给 GLES）
    case "${KFB_DIM:-20}" in off) echo -1 > $X/hwc.dim ;; ''|*[!0-9]*) echo 51 > $X/hwc.dim ;;
        *) d=${KFB_DIM}; [ "$d" -gt 100 ] && d=100; echo $((d * 255 / 100)) > $X/hwc.dim ;; esac
    # framework 项目（docs/framework-project.md）：只有 project/framework 分支的镜像认这些开关文件，老镜像看不见它们
    if [ "$KFB_HWC" = 1 ] && [ "${KFB_ONEPAGE:-0}" = 1 ]; then touch $X/onepage; else rm -f $X/onepage; fi
    if [ "${KFB_RGB565:-0}" = 1 ]; then touch $X/rgb565; else rm -f $X/rgb565; fi
    if [ "${VD_AUDIO:-1}" = 0 ]; then touch $X/noaudio; else rm -f $X/noaudio; fi
}
# 屏幕旋转 KFB_ROTATE=0|90|180|270（docs/rotation.md）：Android 永远正着画，显示桥（veradroid-epd）转画面，
# 触摸前端（veradroid-input）转坐标和边缘手势区。0 时两个程序的命令行和以前完全一样。
rot_deg() { case "$KFB_ROTATE" in 90|180|270) echo $KFB_ROTATE ;; *) echo 0 ;; esac; }
rot_args() {   # 给 veradroid-epd / veradroid-input 的额外参数（0 度时为空：命令行和以前一样）
    r=$(rot_deg); ra=
    if [ "$r" != 0 ]; then
        ra="--rotate $r"
        [ -n "$viewVisWidth" ] && [ "$viewVisWidth" != "${viewWidth:-1272}" ] && ra="$ra --vw $viewVisWidth"
    fi
    echo $ra
}
# 显示桥接：系统往共享缓冲 $X/fb 画、往 $X/epd.fifo 报“第几页”，桥接程序比较差异后局部刷新墨水屏
display_start() {
    [ -x "$VD/bin/veradroid-epd" ] || { t "display: veradroid-epd missing"; return 0; }
    epd_pd=-1; case "$KFB_PWRDOWN" in ""|*[!0-9]*) ;; *) epd_pd=$KFB_PWRDOWN ;; esac   # 面板掉电延时，没设 / off = 不碰
    $VD/bin/veradroid-epd run $X/fb $X/epd.fifo $X/ctl --w ${viewWidth:-1272} --h ${viewHeight:-1696} --contrast ${KFB_CONTRAST:-1.3} --dither ${KFB_DITHER:-3} --flash ${KFB_FLASH:-0} --invert ${KFB_INVERT:-0} --lightf ${KFB_LIGHTF:-0} --darken ${KFB_DARKEN:-0} --mode ${KFB_MODE:-0} --settle ${KFB_SETTLE:-120} --hold ${KFB_HOLD:-70} --pace ${KFB_PACE:-0} --clean ${KFB_CLEAN:-0} --reagl-min ${KFB_REAGL_MIN:-35} --anim-mode ${KFB_ANIM_MODE:-1} --anim-dir ${KFB_ANIM_DIR:-2} --anim-steps ${KFB_ANIM_STEPS:-12} --anim-min ${KFB_ANIM_MIN:-60} --pwrdown $epd_pd $(rot_args) >$W/epd.log 2>&1 &
    echo $! > $W/epd.pid
    rot_deg > $W/rotate
    # 以后能不能当场转 180：0 度启动时没传 --vw，可见宽 != 行宽（PW5 无 FBInk）的机器转了会偏 12 像素，只能重启
    if [ "$(rot_deg)" != 0 ] || [ -z "$viewVisWidth" ] || [ "$viewVisWidth" = "${viewWidth:-1272}" ]; then touch $W/rotate.live; else rm -f $W/rotate.live; fi
    usleep 500000
    t "display: bridge pid $(cat $W/epd.pid)"
}
display_stop() { alive $W/epd.pid && kill "$(cat $W/epd.pid)" 2>/dev/null; rm -f $W/epd.pid $W/rotate $W/rotate.live; }

# 宿主命名空间（chroot）模式：3.0 内核（PW2 / PW3 / Oasis 1/2 / Voyage / 入门款 2014、2016）没有任何命名空间。
# Android 直接 chroot 进 $R，和 Kindle 共用进程、挂载和网络。保护 Kindle 的手段：
#  - /dev/vdchroot 标记：系统里的 android_reboot 看到它就不调用 reboot() / remount_ro（small-patches.py）；
#  - /proc/sys 整个只读（包括 net：这里的 net 就是 Kindle 的）；没有 slirp，Android 暂时没有网络；
#  - 容器的进程按“根目录是 $R”识别（冻结 / 停止都用它），挂载在 stop.sh 里由深到浅逐个卸掉。
# 测试开关：$VD/test-hostns 存在时，有命名空间的内核也走 chroot / 共用网络这条路（只为在 PW6 真机上测这条路径；正常安装里没有这个文件）
hostns() { [ -e "$VD/test-hostns" ] || [ ! -e /proc/self/ns/pid ]; }
chroot_pids() { # 容器的进程（没有 PID 命名空间时）
    # 以前只认“/proc/PID/root 这个链接读出来正好是 $R”。容器根上面的挂载一旦被延迟卸载（umount -l：上一次 stop 和新的一次启动
    # 踩在一起时就会这样），还活着的容器进程的 root 读出来变成 “/”，这里再也认不出它们：stop.sh 杀不掉，它们一直占着系统盘的
    # loop 设备（kt6-517104 模拟器复现：/init、logd、servicemanager 留着，loop1 摘不掉，之后启动 / 安装都报“系统盘还在被占用”，
    # 只能重启 Kindle）。所以再加一条不看路径的：根目录所在的设备就是系统盘镜像的 loop 设备（或者和 $R 是同一个目录）。
    cp_devs=" "
    for cp_l in $(img_loops); do
        cp_d=$(cat /sys/block/$cp_l/dev 2>/dev/null)
        [ -n "$cp_d" ] && cp_devs="$cp_devs$(( ${cp_d%%:*} * 256 + ${cp_d##*:} )) "
    done
    cp_r=$(stat -L -c %d:%i "$R/." 2>/dev/null); [ "$cp_r" = "$(stat -L -c %d:%i /. 2>/dev/null)" ] && cp_r=
    {
        for d in /proc/[0-9]*; do
            [ "$(readlink $d/root 2>/dev/null)" = "$R" ] && echo ${d#/proc/}
        done
        # 一次 stat 看完所有进程的根目录（设备号 inode 路径）
        stat -L -c '%d %i %n' /proc/[0-9]*/root 2>/dev/null | awk -v devs="$cp_devs" -v r="$cp_r" '
            { split($3, a, "/"); if (index(devs, " " $1 " ") > 0 || (r != "" && ($1 ":" $2) == r)) print a[3] }'
    } | sort -un
}
# vold 的 fstrim 在没有 fstab 的容器里必然段错误（TrimTask::addFromFstab 解引用空指针），vold 重启的那几秒里
# PackageManager 准备用户 0 的存储失败，就会删掉用户 0 的全部数据（2026-11-13 事故：/data/data 全没了，documents 也被清空）。
# PackageManager 开机时“距上次 fstrim 超过 3 天”就强制跑一次（last-fstrim 的修改时间）：每次开机前把它摸新，这条路就不会走到。
fstrim_defuse() {
    [ -d $SYS/data/system ] || return 0
    touch $SYS/data/system/last-fstrim 2>/dev/null && chown 1000:1000 $SYS/data/system/last-fstrim 2>/dev/null
    return 0
}
# 系统字体（SYSTEM_FONT，桌面“系统字体 → 应用到所有应用”写）：让所有应用的默认字体（微信读书的“系统默认字体”、设置、浏览器……）都换成它。
# 做法：开机前按镜像里的 /system/etc/fonts.xml 生成一份改过的放在 $W/sysfont，容器里绑在 /system/etc/fonts.xml 上；字体文件绑到
# /dev/vdfont/system.ttf（容器自己的 tmpfs）。fonts.xml 里的文件名是相对 /system/fonts/ 的（FontListParser、WebView 的 Skia 都是），
# 所以写成 ../../dev/vdfont/system.ttf。改动三处：
#   1. sans-serif（第一个家族 = 默认字体）只留这一个字体（400 常规；粗体 / 斜体由 Minikin 合成）——第一个家族有的字一律用它；
#   2. 原来的 Roboto 挪成紧跟着的无名回退家族：选的字体缺的西文字母还用 Roboto；
#   3. 加 zh-Hans / zh-Hant / ja 三个家族指向它，放在所有回退字体前面：serif、monospace 之类别的家族里的中文也用它（语言匹配分更高）。
# 系统镜像本身一个字节都不改；没设、文件不在 / 读不了 / 太小 / 不是字体，就什么都不绑（原样字体）。
# 换字体要重启 Android 才生效（zygote 开机时预载 Typeface）。
# 保险：带着这个字体连续两次没开机完成（$SYS/sysfont.try 计数，after_boot 开机完成时删掉），以后就不再用它（$SYS/sysfont.bad），
# 直到用户重新选一次字体（settings_apply 清掉）。
SYSFONT_REF=../../dev/vdfont/system.ttf
sysfont_host() {   # Android 里的路径 -> 宿主上的文件。只认三个字体目录里的文件，不认子目录和 ..
    sf_n=${1##*/}
    case "$sf_n" in ''|.*|*..*) return 1 ;; esac
    case "${1%/*}" in
        /data/media/0/Fonts|/sdcard/Fonts|/storage/emulated/0/Fonts) echo "$VD/fonts/$sf_n" ;;
        /data/media/0/KindleFonts|/sdcard/KindleFonts|/storage/emulated/0/KindleFonts) echo "/usr/java/lib/fonts/$sf_n" ;;
        /system/fonts) echo "$R/system/fonts/$sf_n" ;;
        *) return 1 ;;
    esac
}
sysfont_ok() {     # 能读、至少 16 KB、文件头是 TrueType / OpenType / 字体集
    [ -f "$1" ] && [ -r "$1" ] || return 1
    [ "$(wc -c < "$1" 2>/dev/null || echo 0)" -ge 16384 ] || return 1
    case "$(head -c 4 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')" in 00010000|4f54544f|74727565|74746366) return 0 ;; esac
    return 1
}
sysfont_prepare() {   # 宿主侧，container_start 里、启动容器之前
    rm -rf $W/sysfont
    case "$SYSTEM_FONT" in ''|default|none) rm -f $SYS/sysfont.try; return 0 ;; esac
    sf_src=$(sysfont_host "$SYSTEM_FONT") || { t "sysfont: ignored (not in a font folder): $SYSTEM_FONT"; return 0; }
    if [ "$(cat $SYS/sysfont.bad 2>/dev/null)" = "$SYSTEM_FONT" ]; then t "sysfont: $SYSTEM_FONT failed to boot twice before, using stock fonts (pick it again to retry)"; return 0; fi
    sf_try=0
    if [ -f $SYS/sysfont.try ] && [ "$(sed -n 2p $SYS/sysfont.try)" = "$SYSTEM_FONT" ]; then sf_try=$(sed -n 1p $SYS/sysfont.try); fi
    case "$sf_try" in ''|*[!0-9]*) sf_try=0 ;; esac
    if [ "$sf_try" -ge 2 ]; then
        printf '%s\n' "$SYSTEM_FONT" > $SYS/sysfont.bad; rm -f $SYS/sysfont.try
        t "sysfont: Android did not finish booting twice with $SYSTEM_FONT, using stock fonts"; return 0
    fi
    sysfont_ok "$sf_src" || { t "sysfont: $sf_src missing, unreadable or not a font: stock fonts"; return 0; }
    sf_xml=$R/system/etc/fonts.xml
    [ -f "$sf_xml" ] || { t "sysfont: no $sf_xml"; return 0; }
    mkdir -p $W/sysfont || return 0
    awk -v ref="$SYSFONT_REF" '
        function fam(attr) { return "    <family" attr ">\n        <font weight=\"400\" style=\"normal\">" ref "</font>\n    </family>" }
        st == 0 && /<family[^>]*name="sans-serif"[ >\/]/ && !/<\/family>/ {
            st = 1; print "    <family name=\"sans-serif\">"; print "        <font weight=\"400\" style=\"normal\">" ref "</font>"; print "    </family>"
            print "    <family>"; next
        }
        st == 1 { print; if (/<\/family>/) { st = 2; print fam(" lang=\"zh-Hans\""); print fam(" lang=\"zh-Hant\""); print fam(" lang=\"ja\"") } next }
        { print }
        END { if (st != 2) exit 1 }' "$sf_xml" > $W/sysfont/fonts.xml 2>/dev/null
    if [ $? -ne 0 ] || ! grep -q '</familyset>' $W/sysfont/fonts.xml; then
        rm -rf $W/sysfont; t "sysfont: could not rewrite fonts.xml (no sans-serif family?): stock fonts"; return 0
    fi
    chmod 644 $W/sysfont/fonts.xml
    printf '%s\n' "$sf_src" > $W/sysfont/src
    printf '%s\n' "$SYSTEM_FONT" > $W/sysfont/android
    printf '%s\n%s\n' $((sf_try + 1)) "$SYSTEM_FONT" > $SYS/sysfont.try
    t "sysfont: $SYSTEM_FONT -> all apps (try $((sf_try + 1)))"
}
sysfont_mount() {     # 容器里（run_in_ns），/dev 的 tmpfs 建好之后、换根之前
    [ -s $W/sysfont/fonts.xml ] && [ -s $W/sysfont/src ] || return 0
    sf_src=$(cat $W/sysfont/src)
    mkdir -p $R/dev/vdfont && touch $R/dev/vdfont/system.ttf || return 0
    if mount --bind "$sf_src" $R/dev/vdfont/system.ttf; then
        mount -o remount,ro,bind $R/dev/vdfont/system.ttf 2>/dev/null
        if [ "$(wc -c < $R/dev/vdfont/system.ttf)" = "$(wc -c < "$sf_src")" ]; then   # 真的绑上了（不是那个空占位文件）
            mount --bind $W/sysfont/fonts.xml $R/system/etc/fonts.xml && return 0
        fi
        umount $R/dev/vdfont/system.ttf 2>/dev/null
    fi
    echo "veradroid: system font $sf_src not mounted, stock fonts" >&2
    return 0
}
container_start() {
    sysfont_prepare       # 系统字体：生成 $W/sysfont（run_in_ns 绑进去）
    fstrim_defuse
    docs_snapshot         # 开机完成后 after_boot 拿它核对 Kindle 书库（docs_verify）
    wc -l < $SYS/data/system/uiderrors.txt 2>/dev/null | tr -d ' ' > $W/uiderr.lines
    if hostns; then
        freezer_setup
        setsid sh $VD/boot/veradroid.sh --in-chroot "$KFB_TOUCH" "$KFB_KEYS_VIRT" "$KFB_KEYS" </dev/null >>$LOG 2>&1 &
        P=$!                                      # exec 链（sh -> chroot -> /init）保持同一个 PID
        echo $P > $W/pid
        echo chroot > $W/mode
        t "container started (host namespaces, chroot): init=$P"
        return 0
    fi
    # 本进程先进 freezer 组再 fork，容器的进程都在组里；fork 完回到根组
    freezer_setup && freezer_enter
    unshare -m -u -i -n -p -f -- sh $VD/boot/veradroid.sh --in-ns "$KFB_TOUCH" "$KFB_KEYS_VIRT" "$KFB_KEYS" </dev/null >>$LOG 2>&1 &
    UPID=$!
    [ -d $FZ ] && freezer_leave
    P=
    for i in 1 2 3 4 5 6 7 8 9 10; do
        read -r P _ < /proc/$UPID/task/$UPID/children 2>/dev/null
        [ -n "$P" ] && break
        usleep 200000
    done
    [ -n "$P" ] || { t "container did not start"; return 1; }
    echo $P > $W/pid
    echo $UPID > $W/unshare.pid
    t "container started: unshare=$UPID init=$P"
}


# 确保容器根下的 /dev/binder 是可打开的字符设备。init 偶发把 tmpfs 盖在节点上，
# 或 bind 失败时只剩普通文件 → 早期服务 SIGABRT（Binder driver could not be opened）。

binder_repair() {
    # Prefer repairing inside the live container mount namespace. Doing
    # mount --bind on the host path $R/dev/binder leaves a nested mount under
    # $SYS that stop/storage_umount must clear, or Kindle userstore unmount fails.
    p=$(cat $W/pid 2>/dev/null)
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null && [ -d /proc/$p/ns/mnt ]; then
        nsenter -t "$p" -m -- /bin/sh -c '
            target=/dev/binder
            if [ -d "$target" ]; then umount "$target" 2>/dev/null; rmdir "$target" 2>/dev/null; fi
            if [ -c "$target" ] && [ -e /dev/vndbinder ]; then chmod 666 "$target" 2>/dev/null; exit 0; fi
            # Inside the container ns, /dev/vndbinder is the host bind (or missing).
            if [ -e /dev/vndbinder ]; then
                chmod 666 /dev/vndbinder 2>/dev/null
                rm -f "$target" 2>/dev/null
                touch "$target"
                mount --bind /dev/vndbinder "$target" || exit 1
                chmod 666 "$target" 2>/dev/null
                [ -c "$target" ] || exit 1
                exit 0
            fi
            exit 1
        ' && return 0
        # fall through to host-path repair if nsenter path failed
    fi
    target=$R/dev/binder
    mkdir -p $R/dev
    if [ -d "$target" ]; then
        umount "$target" 2>/dev/null || true
        rmdir "$target" 2>/dev/null || true
    fi
    if [ -c "$target" ] && [ -e /dev/vndbinder ]; then
        chmod 666 "$target" 2>/dev/null || true
        return 0
    fi
    rm -f "$target" 2>/dev/null || true
    if [ -e /dev/vndbinder ]; then
        chmod 666 /dev/vndbinder
        touch "$target"
        mount --bind /dev/vndbinder "$target" || return 1
        chmod 666 "$target" 2>/dev/null || true
        [ -c "$target" ] || return 1
        return 0
    fi
    return 1
}

# 在新命名空间里执行（由 veradroid.sh --in-ns 调用）
run_in_ns() {
    TOUCH=$1 KEYS=$2 PTKEYS=$3
    # HOSTNS=1：由 veradroid.sh --in-chroot 调用（没有命名空间，挂载直接做在宿主上，stop.sh 负责卸掉）
    [ -z "$HOSTNS" ] && mount --make-rprivate / 2>/dev/null
    # Kindle 书库的挂载点在根下（见 common.sh 的 KLIB_MP）：根马上要变只读，先建好
    [ -f $R/.demo ] || mkdir -p $R$KLIB_MP $R$KLIB_FSP 2>/dev/null
    mount --bind $R $R || exit 1                       # pivot_root 要求新根是挂载点
    DEMO=; [ -f $R/.demo ] && DEMO=1
    [ -z "$DEMO" ] && mount -o remount,ro,bind $R
    mount -t tmpfs -o nosuid,mode=755 tmpfs $R/dev || exit 1
    for n in null zero full tty random urandom kmsg fuse; do
        [ -e /dev/$n ] && touch $R/dev/$n && mount --bind /dev/$n $R/dev/$n
    done
    # Kindle 自己用 /dev/binder，系统借没人用的 /dev/vndbinder。
    # 没有可用 binder 时 Android 会在开机前几秒连环 SIGABRT（Abort: Binder driver could not be opened）
    # ——用户日志 PW5/KT5 低内存机；必须保证容器里真有可打开的 /dev/binder，否则直接失败。
    binder_ok=
    if [ -e /dev/vndbinder ]; then
        chmod 666 /dev/vndbinder
        touch $R/dev/binder
        if mount --bind /dev/vndbinder $R/dev/binder; then binder_ok=1; fi
    fi
    # binderfs 回退（部分 5.x 内核）：单独实例，不跟 Kindle 的 /dev/binder 抢。
    if [ -z "$binder_ok" ] && grep -qw binder /proc/filesystems 2>/dev/null; then
        mkdir -p $R/dev/binderfs
        if mount -t binder binder $R/dev/binderfs 2>/dev/null; then
            # binderfs 默认节点名 binder、hwbinder、vndbinder
            if [ -e $R/dev/binderfs/binder ]; then
                ln -sf binderfs/binder $R/dev/binder
                binder_ok=1
            fi
        fi
    fi
    if [ -z "$binder_ok" ] || [ ! -e $R/dev/binder ]; then
        echo "veradroid: no binder device for Android (need /dev/vndbinder or binderfs)" >&2
        exit 1
    fi
    chmod 666 $R/dev/binder 2>/dev/null || true
    # Final: must be a char device, not a plain file/dir covered by tmpfs.
    if [ ! -c $R/dev/binder ]; then
        binder_repair || { echo "veradroid: binder node is not a char device" >&2; exit 1; }
    fi
    [ -z "$HOSTNS" ] && [ -e /dev/net/tun ] && { touch $R/dev/tun; mount --bind /dev/net/tun $R/dev/tun; }
    [ -n "$HOSTNS" ] && touch $R/dev/vdchroot      # 系统里的 android_reboot 看到它就不碰 Kindle（见上面 hostns 的说明）
    mkdir -p $R/dev/socket $R/dev/input $R/dev/kfb $R/dev/pts $R/dev/__properties__
    # 内核 < 3.17 没有 memfd：ashmem 退回到这块 tmpfs 上的已删除文件（libcutils/ashmem-dev.c、vdshim.c）
    mkdir -p $R/dev/vdshm && chmod 1777 $R/dev/vdshm
    [ -n "$TOUCH" ] && { touch $R/dev/input/event0; mount --bind "$TOUCH" $R/dev/input/event0; }
    [ -n "$KEYS" ]  && { touch $R/dev/input/event1; mount --bind "$KEYS" $R/dev/input/event1; }
    [ -n "$PTKEYS" ] && { touch $R/dev/input/event2; mount --bind "$PTKEYS" $R/dev/input/event2; }   # Kindle 的翻页键 kindle-input-pt
    [ -n "$KFB_BTKEYS" ] && [ -c "$KFB_BTKEYS" ] && { touch $R/dev/input/event3; mount --bind "$KFB_BTKEYS" $R/dev/input/event3; }   # 蓝牙翻页器桥 veradroid-btkeys（bt.sh）
    mount --bind $X $R/dev/kfb
    # 墨水屏：系统里的显示后端直接写 Kindle 的帧缓冲、发刷新
    [ -e /dev/fb0 ] && { touch $R/dev/epd $R/dev/fb0; mount --bind /dev/fb0 $R/dev/epd; mount --bind /dev/fb0 $R/dev/fb0; }   # FBInk 认 /dev/fb0，系统里的显示后端用 /dev/epd
    mount -t devpts -o mode=620,ptmxmode=666,newinstance devpts $R/dev/pts && ln -s pts/ptmx $R/dev/ptmx

    mount -t proc proc $R/proc || exit 1
    [ -f $W/cmdline ] && mount --bind $W/cmdline $R/proc/cmdline
    # /proc/sys 是整个内核的，不是命名空间的：Android 的 init 会往里写一大批参数（调度、内存、pid_max……），不能让它改 Kindle。
    # 整个只读；net 是 net 命名空间自己的，放开；init 开机必须写 mmap 随机化位数（写不了它就停），只放开这一个。
    if [ -z "$DEMO" ]; then
        [ -z "$HOSTNS" ] && mount --bind $R/proc/sys/net $R/proc/sys/net    # chroot 模式下 net 就是 Kindle 的：一起只读
        mount --rbind $R/proc/sys $R/proc/sys && mount -o remount,ro,bind $R/proc/sys
        f=vm/mmap_rnd_compat_bits; [ -e /proc/sys/$f ] || f=vm/mmap_rnd_bits
        # 4.5 以前的内核（PW4 / Oasis 3 / 3.0 机型）没有这个设置；系统的 init 已打补丁，文件不存在时跳过
        if [ -e /proc/sys/$f ]; then
            mount --bind /proc/sys/$f $R/proc/sys/$f && mount -o remount,rw,bind $R/proc/sys/$f || { echo "cannot open $f"; exit 1; }
        fi
        for f in sysrq-trigger cpu/alignment; do
            [ -e "$R/proc/$f" ] && mount --bind "$R/proc/$f" "$R/proc/$f" && mount -o remount,ro,bind "$R/proc/$f"
        done
    fi
    mount -t sysfs -o ro sysfs $R/sys || exit 1
    # 内核编进了 SELinux 但没加载策略：系统绝不能碰宿主的 SELinux，盖一层只读空目录
    for d in sys/fs/selinux sys/fs/bpf sys/fs/pstore sys/kernel/tracing sys/kernel/debug; do
        [ -d $R/$d ] && mount -t tmpfs -o ro,size=4k tmpfs $R/$d
    done

    if [ -n "$DEMO" ]; then
        # 演示根：借宿主的 busybox、库、FBInk 和字体（只读）
        for d in bin lib usr/lib; do mkdir -p $R/$d; mount --bind /$d $R/$d; mount -o remount,ro,bind $R/$d; done
        mkdir -p $R/opt $R/fonts $R/tmp
        touch $R/opt/fbink; mount --bind "$FBINK" $R/opt/fbink
        mount --bind /usr/java/lib/fonts $R/fonts
    else
        mkdir -p $SYS/data && mount --bind $SYS/data $R/data && mount -o remount,bind,nosuid,nodev,noatime $R/data
        mkdir -p $R/data/cache                       # 根里的 /cache 是指向 /data/cache 的符号链接
        # 存储：Android 里的 /sdcard 和 /storage/emulated/0 都指向 data/media/0（没有 sdcard 守护进程，直接绑）；
        # Kindle 自己的书库（documents）也绑进来，传书网页上传到“Kindle 书库”就直接出现在 Kindle 里。
        mkdir -p $R/data/media/0/Books $R/data/local/tmp
        chmod 777 $R/data/media $R/data/media/0 $R/data/media/0/Books $R/data/local/tmp 2>/dev/null
        upload_dir_fix 2>/dev/null     # 安装包暂存目录：Android 开机前就准备好（common.sh）
        # Kindle 的 documents 属于它自己的框架用户、权限 755：Android 应用（传书网页）写不进去，“传到 Kindle 书库”报 Permission denied。
        # 给其他用户加上写权限（FUSE 那一侧的 /mnt/us/documents 本来就是 777）。
        [ -d /mnt/base-us/documents ] && chmod o+rwx /mnt/base-us/documents 2>/dev/null
        # Kindle 书库：documents 绑在 /data/media/0/KindleLibrary（真正的挂载点：应用经 /sdcard 的 FUSE 才看得到，见 common.sh）。
        # 开机期间只读（PackageManager 准备用户存储时万一要删 /data/media/0，删除只会得到 EROFS），开机完成后 after_boot 的
        # klib_rw 把可写的那份（$R$KLIB_MP，/data 外面）再叠绑上去。不能 remount：应用的挂载命名空间里留着只读那份的拷贝，
        # 改标志传不过去；Android 的 toybox mount 也做不了 remount。只读做不到就不绑：宁可 Android 里暂时看不到书库。
        if [ -d /mnt/base-us/documents ] && [ -d $R$KLIB_MP ] && klib_dir $R/data; then
            # 加密用户分区时可写层要用的解密视图（见 common.sh 的 KLIB_FSP）；用不用由 klib_rw 开机后试读决定
            fsp=$(klib_fsp_src) && [ -d $R$KLIB_FSP ] && mount --bind "$fsp" $R$KLIB_FSP 2>/dev/null
            if mount --bind /mnt/base-us/documents $R$KLIB_MP; then
                if mount --bind /mnt/base-us/documents $R$KLIB && ! mount -o remount,ro,bind $R$KLIB; then
                    umount $R$KLIB; echo "veradroid: cannot bind the Kindle library read-only, NOT bound into Android" >&2
                fi
            fi
        else
            echo "veradroid: KindleLibrary mount point not in place, Kindle library NOT bound into Android" >&2
        fi
        # Kindle 自带字体（宋体/黑体/Bookerly 等）只读绑进 Android，阅读器可以直接选，不复制、不打包
        mkdir -p $R/data/media/0/KindleFonts $R/data/media/0/Fonts
        [ -d /usr/java/lib/fonts ] && mount --bind /usr/java/lib/fonts $R/data/media/0/KindleFonts
        [ -d $VD/fonts ] && mount --bind $VD/fonts $R/data/media/0/Fonts
        chmod 777 $R/data/media/0/Fonts 2>/dev/null
        sysfont_mount        # 系统字体（SYSTEM_FONT）：上面 sysfont_prepare 准备好的才绑
        # /sdcard -> /storage/self/primary -> /storage/emulated/0. vold/FUSE
        # replaces /storage/emulated and filters by sdcard_rw group; KOReader
        # then gets EACCES on books. Drop that FUSE view and bind the ext4
        # media directory directly, so normal app permissions apply.
        umount -l $R/storage/emulated 2>/dev/null
        mkdir -p $R/storage/emulated/0
        mount --bind $R/data/media/0 $R/storage/emulated/0
    fi
    # 新根是只读的，put_old 必须是根里已有的目录：Android 的根里有个空的 /mnt，旧根临时挂在那儿，由 pivot_init（静态）卸掉。
    # Android 的 init 第一阶段会加载 SELinux 策略（对宿主内核的操作！）并重新挂 /dev。必须直接走第二阶段：
    # 它不加载策略，用我们准备好的 /dev。演示系统的 init 是普通脚本。
    if [ -n "$DEMO" ]; then
        mkdir -p $R/old
        cd $R && pivot_root . old && cd / && umount -l /old && rmdir /old 2>/dev/null
        exec /init
    fi
    if [ -n "$HOSTNS" ]; then
        cd $R && exec chroot $R /init --second-stage
    fi
    exec $VD/bin/pivot_init $R mnt /init --second-stage
}
