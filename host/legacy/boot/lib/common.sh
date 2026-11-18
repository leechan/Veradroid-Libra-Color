# SPDX-License-Identifier: GPL-3.0-or-later
# 公共定义。所有模块都 source 这个文件。
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
VD=${VD:-/mnt/base-us/veradroid}          # 程序目录（一律走 ext4 的 /mnt/base-us，不走 /mnt/us 的 FUSE）
SYS=/mnt/base-us/system/veradroid          # 数据：rootfs、data、日志、设置（书库不扫 system/）
SYSTEM_IMG=/mnt/base-us/veradroid-sys.img   # vfat /mnt/base-us 上的 ext4 系统盘（PW5 等）
# 日志 / 标记 / 备份的位置（veradroid/logs、state、backup）和根目录旧文件的搬迁：tidy.sh
[ -f "$VD/boot/lib/tidy.sh" ] && . "$VD/boot/lib/tidy.sh"
# 有的机型（KT6，eink-emulator 实测）loop 节点只有 /dev/loop/N，没有 /dev/loopN，`mount -o loop` 找不到空闲设备。
# 先试 mount -o loop，不行就自己挑一个空闲节点用 busybox losetup 绑定。
# 3.0 内核：ext3 的用户扩展属性（user.*）只有带 user_xattr 挂载才有；PW2 5.12 固件的 mkfs.ext3 不把它写进超级块的默认挂载选项
# （PW3 5.16 的会）。没有它时 Android 的 PackageManager 每次开机给 /data/user_de/0 打 user.serial 失败（getxattr ENOTSUP），
# 当成“用户目录坏了”整个删掉——而 user_de/0 是指向 /data/data 的链接，于是所有应用的数据都被删光
# （pw2-5122 模拟器实测：DownloadProvider 打不开数据库、android.process.media 反复崩溃、错误对话框挡住返回键）。
LOOPOPT=rw,noatime; case "$(uname -r)" in 3.*) LOOPOPT=rw,noatime,user_xattr ;; esac
loop_mount() { # img dir
    mount -o loop,$LOOPOPT "$1" "$2" 2>/dev/null && return 0
    for d in /dev/loop/[0-9]* /dev/loop[0-9]*; do
        [ -b "$d" ] || continue
        losetup "$d" >/dev/null 2>&1 && continue      # 已占用
        losetup "$d" "$1" 2>/dev/null || continue
        { mount -t ext4 -o $LOOPOPT "$d" "$2" 2>/dev/null || mount -t ext3 -o $LOOPOPT "$d" "$2" 2>/dev/null; } && return 0   # 3.0 内核只有 ext3
        losetup -d "$d" 2>/dev/null
    done
    return 1
}
# 系统盘镜像当前挂在哪些 loop 设备上（/sys/block/loopN/loop/backing_file）
img_loops() {
    for b in /sys/block/loop*/loop/backing_file; do
        case "$(cat "$b" 2>/dev/null)" in *veradroid-sys.img) d=${b%/loop/backing_file}; echo "${d##*/}" ;; esac
    done
}
loop_dev() { # loopN -> 设备节点（有的机型只有 /dev/loop/N）
    n=${1#loop}
    [ -b /dev/loop$n ] && echo /dev/loop$n || echo /dev/loop/$n
}
storage_mount() {
    [ -f "$SYSTEM_IMG" ] || return 0
    if grep -q " $SYS " /proc/mounts; then
        # 安装器（旧版）挂的可能没带 user_xattr：补上（remount 不影响正在用的文件）
        case "$LOOPOPT" in *user_xattr*) grep " $SYS " /proc/mounts | grep -q user_xattr || mount -o remount,user_xattr "$SYS" 2>/dev/null ;; esac
        return 0
    fi
    mkdir -p "$SYS" 2>/dev/null || true
    # 绝不能把同一个镜像挂两次：上次停止时延迟卸载（umount -l）的挂载树如果还被没退干净的进程引用着，
    # 镜像的文件系统实例和它的 loop 设备都还活着，只是 $SYS 上看不到了。这时再挂一次（新的 loop 设备）
    # 就是两个 ext4/ext3 实例同时写一个文件，元数据必坏（PW3 模拟器实测：loop1 和 loop9 同时指向镜像），
    # e2fsck 去修一个还在用的镜像也一样会弄坏它。所以先把残留的 loop 摘掉；摘不掉就不启动。
    i=0
    while [ -n "$(img_loops)" ]; do
        for l in $(img_loops); do losetup -d "$(loop_dev $l)" 2>/dev/null; done
        [ -z "$(img_loops)" ] && break
        i=$((i + 1)); [ $i -ge 25 ] && { t "storage: system image still attached to $(img_loops | tr '\n' ' ')(previous run not finished)"; return 1; }
        usleep 200000
    done
    # 上次调整大小没做完（断电 / 被杀）、或者留了“下次启动时扩容”：先收尾（storage.sh）。别的进程正在调整就不挂。
    if type st_recover >/dev/null 2>&1; then
        st_recover || { t "storage: a resize is in progress, not mounting"; return 1; }
    fi
    # 系统盘是 vfat 上的一个镜像文件：没电关机、死机、强制重启都可能让它的 ext4/ext3 元数据不一致
    # （KT5 模拟器实测：“block bitmap corrupt … Data will be lost”，日志都写坏了）。挂载前先自动修：
    # -p 只修安全的问题；它说需要人工（退出码 ≥4）时用 -y 全部按默认修，总比带着坏的元数据继续写好。
    # 结果记在 /mnt/base-us/veradroid/logs/fsck.log（系统盘外面，盘坏了也看得到）。
    if command -v e2fsck >/dev/null 2>&1; then
        mkdir -p /mnt/base-us/veradroid/logs 2>/dev/null
        e2fsck -p "$SYSTEM_IMG" >/mnt/base-us/veradroid/logs/fsck.log 2>&1; rc=$?
        if [ $rc -ge 4 ]; then
            echo "-- e2fsck -p rc=$rc, retry with -y" >>/mnt/base-us/veradroid/logs/fsck.log
            e2fsck -y "$SYSTEM_IMG" >>/mnt/base-us/veradroid/logs/fsck.log 2>&1; rc=$?
        fi
        echo "-- $(date) e2fsck rc=$rc" >>/mnt/base-us/veradroid/logs/fsck.log
    fi
    loop_mount "$SYSTEM_IMG" "$SYS" || return 1
}
storage_umount() {
    # Host-ns leftovers under $SYS (notably after_boot binder_repair bind on
    # $R/dev/binder, or binderfs) keep umount(SYS) busy → Kindle cannot drop
    # userstore (/mnt/us) at shutdown (mntus EBUSY/32) and loop0 needs journal
    # recovery next boot. Drop nested mounts deepest-first before SYS itself.
    awk -v d="$SYS" 'index($2, d "/") == 1 {print length($2), $2}' /proc/mounts | sort -rn | while read _ m; do
        umount -l "$m" 2>/dev/null || true
    done
    # Also exact $SYS may already be gone after lazy nested drops; re-read.
    dev=$(awk -v m="$SYS" '$2==m {print $1}' /proc/mounts | tail -1)
    [ -n "$dev" ] || {
        # Detach any loop still tied to the system image even if mount gone
        return 0
    }
    # 刚杀掉的容器进程、延迟卸载（umount -l）的挂载要过一会儿才真正放手：立刻 umount 会报 busy，
    # 系统盘就一直挂着，下次启动前的 e2fsck 也跳过了（KT5、PW3 模拟器都实测到）。最多等 5 秒。
    i=0
    while ! umount "$SYS" 2>/dev/null; do
        # Re-drop anything that reappeared / still nested
        awk -v d="$SYS" 'index($2, d "/") == 1 {print length($2), $2}' /proc/mounts | sort -rn | while read _ m; do
            umount -l "$m" 2>/dev/null || true
        done
        i=$((i + 1)); [ $i -ge 25 ] && { t "storage: $SYS still busy, left mounted"; break; }
        usleep 200000
    done
    case "$dev" in /dev/loop*) losetup -d "$dev" 2>/dev/null || true ;; esac
}
W=/dev/shm/veradroid                       # 运行时状态（tmpfs，重启即消失）
R=$SYS/rootfs                              # 系统根目录
X=$W/kfb                                   # 宿主和系统之间的控制通道，容器里是 /dev/kfb
FZ=$W/freezer/vd                           # freezer cgroup
LOG=$SYS/veradroid.log
FB=/sys/class/graphics/fb0
# vfat /mnt/base-us is mounted noexec on some models; the host binaries live there.
# 在挑 fbink 之前做（noexec 时 -x 检查必然失败）。注意 KT5 模拟器上整包和越狱自带的 fbink 跑 -e 都会段错误，
# 那里退回“无 fbink”是 fbink 自己的问题，显示桥里编进去的 FBInk 库不受影响。
case "$(stat -f -c %T /mnt/base-us 2>/dev/null || true)" in
    vfat|msdos|exfat) mount -o remount,exec /mnt/base-us 2>/dev/null || true ;;
esac
# FBInk：优先用自己带的，否则借 KOReader / 越狱包里的。每个候选都真的跑一次 `-e`（打印屏幕几何）：
# 整包里的是 armhf 动态链接的，老固件（5.16 及以前的 armel 系统）上没有它的动态链接器；PW5 的面板上它还段错误过。
# 跑不起来就换下一个；都不行时显示桥有自己的退路。
FBINK=
fbink_probe() {
    if [ -n "$FBINK" ] && [ -x "$FBINK" ]; then
        "$FBINK" -e >/dev/null 2>&1 && return 0
        FBINK=
    fi
    for f in "$VD/bin/fbink" /mnt/us/koreader/fbink /mnt/us/libkh/bin/fbink; do
        [ -x "$f" ] || continue
        if "$f" -e >/dev/null 2>&1; then
            FBINK=$f
            return 0
        fi
    done
    return 1
}
fbink_probe || true
KFONT=
for f in /usr/java/lib/fonts/STHeitiMedium.ttf "$VD/fonts/DroidSansFallback.ttf" /system/fonts/DroidSansFallback.ttf; do
    [ -f "$f" ] && KFONT=$f && break
done
[ -n "$KFONT" ] || KFONT=/usr/java/lib/fonts/STHeitiMedium.ttf
# 方块风格的进度画面（开机画面底部的进度框、回到 Kindle 时的等待画面；安装器里内嵌同一份）
[ -f "$VD/boot/lib/progress.sh" ] && . "$VD/boot/lib/progress.sh"

t() { echo "[$(date +%H:%M:%S) up=$(cut -d' ' -f1 /proc/uptime)] $*"; }
# Wi-Fi 开关只动 Wi-Fi。以前用的 com.lab126.cmd wirelessEnable 是 Kindle 的“飞行模式”：关它连蓝牙也关了，开它又把蓝牙打开
# （KPW6 用户报告）。com.lab126.wifid enable 写得进去但不起作用（一台测试机 5.19.5：仍然连着）。起作用的是 cmd 的哈希属性
# disableInterfaces（{ wan = (0), wifi = (1) } = 关掉 Wi-Fi 接口；输入格式里整数要带括号）：测试机实测 Wi-Fi 断开（wifid enable 跟着变 0、
# wlan0 不在了），飞行模式和蓝牙不变，写回 (0) 2 秒内重新连上。没有这个属性的固件退回 wirelessEnable。飞行模式开着时 Wi-Fi 算关。
wifi_dis() { lipc-hash-prop com.lab126.cmd disableInterfaces </dev/null 2>/dev/null | sed -n "s/^[[:space:]]*$1 = (\([0-9]*\)).*/\1/p" | head -1; }
wifi_state() {
    wa=$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null); wd=$(wifi_dis wifi)
    if [ -n "$wd" ]; then [ "$wd" = 0 ] && ww=1 || ww=0; else ww=${wa:-1}; fi
    [ "$wa" = 0 ] && ww=0
    echo "$ww"
}
wifi_set() { # 0|1
    wd=$(wifi_dis wifi)
    if [ -n "$wd" ]; then
        wn=$(wifi_dis wan); [ "$1" = 1 ] && wv=0 || wv=1
        echo "{ wan = (${wn:-0}), wifi = ($wv) }" | lipc-hash-prop com.lab126.cmd disableInterfaces >/dev/null 2>&1
        # 用户明确要开 Wi-Fi 而飞行模式开着：只有关掉飞行模式 Wi-Fi 才会真的开（蓝牙按 Kindle 自己的规则恢复）
        [ "$1" = 1 ] && [ "$(lipc-get-prop com.lab126.cmd wirelessEnable 2>/dev/null)" = 0 ] && lipc-set-prop -i com.lab126.cmd wirelessEnable 1
    else lipc-set-prop -i com.lab126.cmd wirelessEnable "$1"; fi
}
alive() { [ -f "$1" ] && kill -0 "$(cat "$1" 2>/dev/null)" 2>/dev/null; }
# 给显示桥发命令。显示桥不在了就不写：往没有读端的 FIFO 里 echo 会永远卡在 open()，
# 命令监听、看门狗、唤醒流程以前都可能这样被拖死（显示桥崩过：tmpfs 写满时 SIGBUS）。
# timeout 的写法随固件里的 busybox 变：5.14 以后 `timeout N cmd`，PW2 5.12 / Voyage 5.13 的旧 busybox 只认 `timeout -t N cmd`
# （直接写 timeout 60 … 报 “can't execute '60'”，命令根本没跑：Voyage 模拟器上自检的 binder / 桌面 / 网络全部误报 FAIL）。
# 用法：vd_timeout 秒 命令…；两种都不支持时不限时直接跑。
vd_timeout() {
    vt_s=$1; shift
    if [ -z "${VD_TMO_STYLE:-}" ]; then
        if timeout 5 true 2>/dev/null; then VD_TMO_STYLE=new
        elif timeout -t 5 true 2>/dev/null; then VD_TMO_STYLE=old
        else VD_TMO_STYLE=none; fi
    fi
    case $VD_TMO_STYLE in new) timeout "$vt_s" "$@" ;; old) timeout -t "$vt_s" "$@" ;; *) "$@" ;; esac
}
epd_send() { [ -p $X/epd.fifo ] && alive $W/epd.pid || return 1; echo "$*" > $X/epd.fifo; }
# 在 Android 里执行命令的前缀：平时用 nsenter 进容器的命名空间。3.0 内核（$W/mode=chroot）没有 /proc/PID/ns，
# nsenter 用不了：chroot 到 /proc/<容器 init>/root——这个特殊链接直接落在容器（另一个挂载命名空间）的根上，
# 容器里的 /dev、/proc、/data 都看得到。用法：$(vd_in) /system/bin/sh -c '...'（也能放在 timeout 后面）。
# 重要：after_boot 是后台子 shell，可能比容器活得更久。shell 里的 $P 会过期；必须优先用仍存活的 $W/pid，
# 否则 nsenter 报 can't open '/proc/<dead>/root'，after_boot: install FAILED（用户日志 73301533302 等）。
vd_in() {
    p=$(cat $W/pid 2>/dev/null)
    if ! { [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }; then
        p=$P
        if ! { [ -n "$p" ] && kill -0 "$p" 2>/dev/null; }; then
            return 1
        fi
    fi
    P=$p
    if [ "$(cat $W/mode 2>/dev/null)" = chroot ]; then echo "chroot /proc/$p/root"
    else echo "nsenter -t $p -m -u -i -n -p -r -w"; fi
}
# 屏幕中间提示一行（启动 / 返回 / 错误），只在界面已暂停时用
[ -f "$VD/boot/lib/storage.sh" ] && . "$VD/boot/lib/storage.sh"     # 系统盘大小调整 / 断电后的收尾
case "$0" in */veradroid.sh) ST_START=1 ;; esac                    # 只有真正启动 Android 时才做“下次启动时扩容”
splash() { [ -x "$FBINK" ] && "$FBINK" -q -c -m -M -t regular=$KFONT,px=${2:-44} "$1" 2>/dev/null; }
storage_mount

# 传书网页 / 商店 / 在线更新放安装包的暂存目录（Android 里是 /data/media/0/.upload，VeraHome 以普通应用 uid 写）。
# 只在开机完成后 chmod 一次不够（用户报告：KT6 5.17 上传和链接下载都报 Permission denied）：开机超过等待时间时那一步根本没跑；
# 目录还可能是旧版本 / 别的 uid 留下的，或者被换成了别的东西。容器启动前、开机完成后、每次打开传书和每次安装前都整理一遍。
upload_dir_fix() {
    ud=$SYS/data/media/0/.upload
    [ -d $SYS/data ] || return 0
    if [ -L "$ud" ] || { [ -e "$ud" ] && [ ! -d "$ud" ]; }; then rm -f "$ud"; fi
    mkdir -p "$ud" 2>/dev/null
    chmod 777 $SYS/data/media $SYS/data/media/0 "$ud" 2>/dev/null
    [ -d "$ud" ] && [ "$(stat -c %a "$ud" 2>/dev/null)" = 777 ]
}

# rm -rf 之前的防护：$1 下面（self=1 时包括 $1 本身）有任何挂载就返回 0。
# chroot 模式（5.17 的 4.9 内核、3.0 内核）的 bind 挂载直接落在宿主上（$R/data/media/0/KindleLibrary -> Kindle 的
# documents），stop 没卸干净时 rm -rf 会穿过去删掉 Kindle 的书。删之前一律先查。
# 2026-11-13 事故：容器自己的挂载命名空间里的挂载（Kindle 的 documents 就绑在那里）在宿主的 /proc/mounts 里看不到。
# 所以还要看容器 init 的挂载表，把容器里的路径换算回宿主路径（容器的 / = $R，/data = $SYS/data）再比。
mounts_under() { # dir [self]
    awk -v d="${1%/}" -v self="${2:-0}" '($2 == d && self == 1) || index($2, d "/") == 1 { f = 1 } END { exit !f }' /proc/mounts && return 0
    mounts_under_ns "$1" "${2:-0}"
}
# legacy 和 k49 不同：这里 $W/mode=chroot 也有自己的挂载命名空间（container_start 用 unshare -m 起容器，里面 pivot_root），
# 容器里的挂载不在宿主表里，所以 chroot 模式也要查（k49 的 chroot 模式没有 unshare -m，那边直接跳过）。
# 3.0 内核没有 /proc/PID/ns，判断不了是不是同一个命名空间：一律查。/proc/PID/mounts 的路径是相对那个进程的根写的，
# 换算回宿主路径在两种情况下都成立；最多多报（拒绝删除），不会漏报。
mounts_under_ns() { # dir [self]：只查容器命名空间里的挂载
    for mu_p in $(cat $W/pid 2>/dev/null); do
        [ -r /proc/$mu_p/mounts ] || continue
        mu_a=$(readlink /proc/$mu_p/ns/mnt 2>/dev/null)
        [ -n "$mu_a" ] && [ "$mu_a" = "$(readlink /proc/self/ns/mnt 2>/dev/null)" ] && continue
        awk -v d="${1%/}" -v self="${2:-0}" -v r="$R" -v sd="$SYS/data" '
            function hit(h) { return (h == d && self == 1) || index(h, d "/") == 1 }
            { m = $2; if (m == "/") m = ""
              if (hit(r m)) f = 1
              if (m == "/data" || index(m, "/data/") == 1) { if (hit(sd substr(m, 6))) f = 1 } }
            END { exit !f }' /proc/$mu_p/mounts && return 0
    done
    return 1
}

# ---- Kindle 书库（documents）在 Android 里的位置（2026-11-13 事故后改）----
# 以前 documents 直接绑在容器的 /data/media/0/KindleLibrary：Android 自己删 /data/media/0 时（PackageManager 准备用户存储失败
# → installd destroy_user_data 递归删 /data/data 和 /data/media/0，删除不检查挂载点），会穿过这个 bind 把 Kindle 的书全删掉。
# 现在绑在容器根下的 $KLIB_MP（不在 /data、/storage、/mnt 下面：vold 重启时会卸 /storage、/mnt 下的挂载），
# /data/media/0/KindleLibrary 只是指向它的符号链接：递归删除遇到符号链接只删链接本身（installd 用 O_NOFOLLOW / unlinkat）。
KLIB_MP=/kindle_library
klib_link() { # $1 = data 目录（宿主 $SYS/data，或容器里的 $R/data）。成功（链接就位）返回 0
    kl_m=$1/media/0; kl=$kl_m/KindleLibrary
    mkdir -p "$kl_m" 2>/dev/null || return 1
    if [ -L "$kl" ]; then
        [ "$(readlink "$kl")" = "$KLIB_MP" ] && return 0
        rm -f "$kl"
    elif [ -d "$kl" ]; then
        # 旧版本留下的挂载点目录。下面还挂着东西（上次没停干净）就什么都不动
        if mounts_under "$kl" 1; then t "klib: $kl is still a mount point, not converting"; return 1; fi
        if ! rmdir "$kl" 2>/dev/null; then
            # 不是空的：没挂 documents 时有人往里写过东西。原样挪开，不删
            kl_s=$kl_m/KindleLibrary.stray-$(date +%Y%m%d-%H%M%S)
            mv "$kl" "$kl_s" || return 1
            t "klib: old non-empty KindleLibrary directory kept as ${kl_s##*/}"
        fi
    elif [ -e "$kl" ]; then
        mv "$kl" "$kl.stray-$(date +%Y%m%d-%H%M%S)" || return 1
    fi
    ln -s "$KLIB_MP" "$kl"
}

# ---- documents 自检（2026-11-13 事故后加）：开机前记下 Kindle 书库里的文件，开机完成后核对 ----
DOCS_DIR=/mnt/base-us/documents
# 列出 documents 下的普通文件（相对 /mnt/us 的路径，和安装前备份 tgz 里的写法一致）。不算安装器脚本和临时文件
docs_list() { # [dir]
    ( cd "${1:-$DOCS_DIR}/.." 2>/dev/null && find documents -type f 2>/dev/null ) | grep -v \
        -e '^documents/VeraDroid\.sh' -e '^documents/VeraDroid-Experimental\.sh' -e '^documents/VeraDroid-Offline\.sh' \
        -e '^documents/bootstrap\.sh' -e '^documents/veradroid-.*\.tar\.gz' -e '\.partial$' -e '\.tmp$' \
        -e '^documents/VeraDroid-Report\.s' -e '^documents/VeraDroid-Uninstall\.s' \
        -e '^documents/VeraDroid\.sdr/' -e '^documents/VeraDroid-Experimental\.sdr/' -e '^documents/VeraDroid-Offline\.sdr/' -e '^documents/bootstrap\.sdr/' | sort
}
docs_snapshot() { docs_list > $W/docs.before 2>/dev/null; }
# $1 = 清单文件（docs_list 的格式）。全部还在返回 0；少了就大声记下来，能从安装前备份恢复的恢复（tar -k：绝不覆盖现有文件）
docs_verify() { # list [why]
    [ -s "$1" ] || return 0
    dv_m=$W/docs.missing; : > $dv_m
    while IFS= read -r f; do [ -e "$DOCS_DIR/../$f" ] || [ -L "$DOCS_DIR/../$f" ] || printf '%s\n' "$f" >> $dv_m; done < "$1"
    [ -s $dv_m ] || return 0
    dv_n=$(wc -l < $dv_m | tr -d ' '); dv_all=$(wc -l < "$1" | tr -d ' ')
    dv_msg="!!! DOCUMENTS LOSS: $dv_n of $dv_all files in the Kindle library are gone (${2:-check})"
    t "$dv_msg"; echo "veradroid: $dv_msg" > /dev/kmsg 2>/dev/null
    { echo "[$(date '+%F %T')] $dv_msg"; head -50 $dv_m; } >> $VD/DOCUMENTS-LOSS.log 2>/dev/null
    dv_r=0
    for dv_b in $(ls -t /mnt/base-us/veradroid/backup/user-backup-*.tgz 2>/dev/null) $(ls -t /mnt/base-us/veradroid-user-backup-*.tgz 2>/dev/null); do   # root-legacy: 根目录里老版本的 / 用户改过名的备份也用来补
        tar -xzkf "$dv_b" -C "$DOCS_DIR/.." -T $dv_m 2>/dev/null
        dv_left=0; while IFS= read -r f; do [ -e "$DOCS_DIR/../$f" ] || dv_left=$((dv_left + 1)); done < $dv_m
        t "!!! documents: restored $((dv_n - dv_left)) of $dv_n from ${dv_b##*/}"; echo "[$(date '+%F %T')] restored $((dv_n - dv_left)) of $dv_n from $dv_b" >> $VD/DOCUMENTS-LOSS.log 2>/dev/null
        dv_r=1; [ $dv_left -eq 0 ] && break
    done
    [ $dv_r = 1 ] || t "!!! documents: no pre-install backup to restore from"
    sync
    return 1
}

# 回到 Kindle 以后的自检（stop.sh 结尾、冻结返回之后各跑一次）。用户报告（KT6，固件 5.17）：退出 VeraDroid 后 USB 连电脑
# 只看到一个打不开的灰色盘，重启 Kindle 才好。凡是会让 Kindle 的 USB / 用户存储不正常的残留都在这里查，
# 能当场修的修掉，修不掉的大声记下来：写进 $VD/last-stop.log（USB 里的 veradroid/last-stop.log，系统盘卸了也看得到）和内核日志。
#   $1 = stop（完全退出：不应该再有任何挂载 / loop / 占用）| freeze（冻结返回：系统盘按设计还挂着，只查 Kindle 自己的进程）
userstore_check() {
    uc_mode=${1:-stop}; uc_bad=; uc_fixed=
    # 1. volumd（管 USB 连接和用户存储）/ awesome 还停在 SIGSTOP：补发 SIGCONT
    for uc_n in volumd awesome; do
        for uc_p in $(pidof $uc_n 2>/dev/null); do
            [ "$(awk '/^State:/ {print $2}' /proc/$uc_p/status 2>/dev/null)" = T ] || continue
            kill -CONT $uc_p 2>/dev/null; usleep 200000 2>/dev/null
            if [ "$(awk '/^State:/ {print $2}' /proc/$uc_p/status 2>/dev/null)" = T ]; then uc_bad="$uc_bad $uc_n($uc_p)=still-stopped"
            else uc_fixed="$uc_fixed $uc_n($uc_p)=was-stopped"; fi
        done
    done
    # 2. 我们停过的 MTP 服务（新固件的 USB 传输）没有回来：再起一次
    if [ -f /etc/upstart/mtp.conf ] && initctl status mtp 2>/dev/null | grep -q 'stop/waiting'; then
        rm -f /var/run/upstart/mtp.restarts /var/local/upstart/mtp.restarts 2>/dev/null
        start mtp >/dev/null 2>&1
        if initctl status mtp 2>/dev/null | grep -q 'start/running'; then uc_fixed="$uc_fixed mtp=was-not-running"; else uc_bad="$uc_bad mtp=not-running"; fi
    fi
    if [ "$uc_mode" = stop ]; then
        # 3. 系统盘 / 容器的挂载、loop 设备还在：USB 大容量存储模式的机型上 Kindle 卸不掉用户存储，电脑上就是一个打不开的盘
        uc_m=$(awk -v d="$SYS" '$2 == d || index($2, d "/") == 1 { n++ } END { print n + 0 }' /proc/mounts)
        [ "$uc_m" -gt 0 ] && uc_bad="$uc_bad mounts-under-system-image=$uc_m($(awk -v d="$SYS" '$2 == d || index($2, d "/") == 1 { printf "%s,", $2 }' /proc/mounts | cut -c1-300))"
        uc_l=$(img_loops | tr '\n' ' '); [ -n "$uc_l" ] && uc_bad="$uc_bad loop-still-attached=$uc_l"
        # 4. 谁还开着系统盘 / 程序目录里的文件（只在上面发现残留时才扫：要看每个进程的 fd，慢）
        if [ -n "$uc_bad" ]; then
            for uc_d in /proc/[0-9]*; do
                uc_p=${uc_d#/proc/}; [ "$uc_p" = "$$" ] && continue
                uc_h=$(ls -l $uc_d/cwd $uc_d/root $uc_d/fd 2>/dev/null | grep -c -- "-> \($SYS\|$VD\)\(/\|\$\)")
                [ "${uc_h:-0}" -gt 0 ] && uc_bad="$uc_bad holder=$uc_p:$(tr '\000' ' ' < $uc_d/cmdline 2>/dev/null | cut -c1-70)"
            done
        fi
    fi
    uc_line="[$(date '+%F %T') up=$(cut -d' ' -f1 /proc/uptime)] after $uc_mode:"
    if [ -n "$uc_bad" ]; then
        uc_line="$uc_line USER STORE / USB NOT CLEAN:$uc_bad${uc_fixed:+ | repaired:$uc_fixed}"
        echo "veradroid: $uc_line" > /dev/kmsg 2>/dev/null
    elif [ -n "$uc_fixed" ]; then uc_line="$uc_line repaired:$uc_fixed"
    elif [ "$uc_mode" = freeze ]; then uc_line="$uc_line kindle processes running (android frozen, system image stays mounted)"
    else uc_line="$uc_line clean (volumd running, nothing of VeraDroid left on the user store)"; fi
    t "$uc_line"
    if [ -d "$VD" ]; then
        { tail -n 60 "$VD/last-stop.log" 2>/dev/null; echo "$uc_line"; } > "$VD/last-stop.log.tmp" 2>/dev/null && mv -f "$VD/last-stop.log.tmp" "$VD/last-stop.log" 2>/dev/null
    fi
    [ -z "$uc_bad" ]
}
