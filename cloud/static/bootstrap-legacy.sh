#!/bin/sh
# VeraDroid PW6 one-click bootstrap for an already jailbroken Kindle with SSH.
#   curl -fsSL https://veradroid.wenjin.jp/bootstrap.sh | sh
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
set -eu
BASE="${VD_BASE:-https://veradroid.wenjin.jp}"
MIRROR="${VD_MIRROR:-}"
# Optional network overrides for restricted networks:
#   /mnt/base-us/veradroid/network.conf
#   VD_PROXY=socks5h://192.0.2.2:1080
#   VD_IP=203.0.113.10
#   VD_DNS=223.5.5.5
[ -f /mnt/base-us/veradroid/network.conf ] && . /mnt/base-us/veradroid/network.conf
CURL_OPTS=
[ -n "${VD_PROXY:-}" ] && CURL_OPTS="$CURL_OPTS -x $VD_PROXY"
[ -n "${VD_IP:-}" ] && CURL_OPTS="$CURL_OPTS --resolve veradroid.wenjin.jp:443:$VD_IP --resolve veradroid.wenjin.jp:80:$VD_IP"
[ -n "${VD_DNS:-}" ] && CURL_OPTS="$CURL_OPTS --dns-servers $VD_DNS"
curl_do() { curl $CURL_OPTS "$@"; }
# --retry-all-errors 是 curl 7.71 才有的：老固件（Voyage 5.13.6 自带 curl 7.61）遇到不认识的选项直接退出，
# 安装包一个字节都不下载就报“下载失败”（kv-5136 模拟器实测）。不支持时只用 --retry（只重试临时性错误，断点续传照旧）。
RETRY_ALL=; curl --help all 2>/dev/null | grep -q -- --retry-all-errors && RETRY_ALL=--retry-all-errors
SYS=/mnt/base-us/system/veradroid
VD=/mnt/base-us/veradroid
STABLE=$SYS/device-id
MODEL_FILE=$SYS/model
VERSION_FILE=$SYS/version
FULL_LOG=$SYS/fullupdate.log
W=/dev/shm/veradroid
SYSTEM_IMG=/mnt/base-us/veradroid-sys.img
TMP=/mnt/base-us/veradroid-install.$$
trap 'rm -rf "$TMP"' EXIT
# BH081-3：同一时间只允许一个安装器（书库脚本连点两次 / KUAL + 自动更新同时跑，会互相 mv 程序目录）。
# 被 kill / 断电的上一次安装留下的 veradroid-install.<pid>（整包 + 解压，约 300 MB）和还在往里写的 curl/tar 子进程，在这里清掉。
INSTALL_LOCK=/mnt/base-us/veradroid-install.lock
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo noboot)
# 结束所有命令行里引用目录 $1 的进程（curl -o $1/bundle.tar.gz、tar -C $1 …），不碰自己
vd_kill_users() {
    for pp in /proc/[0-9]*; do
        pn=${pp#/proc/}; [ "$pn" = "$$" ] && continue
        cl=$( { tr '\0' ' ' < "$pp/cmdline"; } 2>/dev/null ) || continue   # 进程可能刚退出：不要往安装输出里刷 can't open
        case "$cl" in *"$1/"*|*"$1 "*) kill -9 "$pn" 2>/dev/null || true ;; esac
    done
}
vd_unlock() { [ "$(cat "$INSTALL_LOCK/pid" 2>/dev/null)" = "$$" ] || return 0; rm -f "$INSTALL_LOCK/pid" "$INSTALL_LOCK/boot" "$INSTALL_LOCK/phase"; rmdir "$INSTALL_LOCK" 2>/dev/null || true; }
# 退出时（成功、die、被打断）一律清理。set +eu：EXIT 陷阱里任何一步失败 / 变量没设，在 set -eu 下 shell 会当场退出，
# 临时目录（整包 + 解开的 ~290 MB）和安装锁就留到下一次安装（老机型存储小）。先删临时目录、放锁，再做别的。
vd_cleanup() { set +eu; type syncer_off >/dev/null 2>&1 && syncer_off; vd_kill_users "$TMP"; rm -rf "$TMP"
    [ -d "$TMP" ] && { sleep 1; vd_kill_users "$TMP"; rm -rf "$TMP"; }; vd_unlock
    [ -n "${KEEPAWAKE:-}" ] && lipc-set-prop com.lab126.powerd preventScreenSaver "$KEEPAWAKE" >/dev/null 2>&1; return 0; }
if ! mkdir "$INSTALL_LOCK" 2>/dev/null; then
    lp=$(cat "$INSTALL_LOCK/pid" 2>/dev/null || true); lb=$(cat "$INSTALL_LOCK/boot" 2>/dev/null || true)
    # 锁在 /mnt/base-us 上，断电后还在：只认本次开机（boot_id 相同）里还活着的持有者
    if [ -n "$lp" ] && [ "$lb" = "$BOOT_ID" ] && kill -0 "$lp" 2>/dev/null; then
        printf '%s\n' "另一个 VeraDroid 安装/更新正在进行（pid $lp），这次不重复安装，请等它完成"; exit 0
    fi
    rm -f "$INSTALL_LOCK/pid" "$INSTALL_LOCK/boot" "$INSTALL_LOCK/phase"; rmdir "$INSTALL_LOCK" 2>/dev/null || true
    mkdir "$INSTALL_LOCK" 2>/dev/null || { printf '%s\n' "无法获取安装锁 $INSTALL_LOCK（另一个安装器刚启动？）"; exit 1; }
fi
echo $$ > "$INSTALL_LOCK/pid"; echo "$BOOT_ID" > "$INSTALL_LOCK/boot"
# 安装进行到哪一步（veradroid.sh 看它决定能不能启动）：check / download = 还没动任何东西，可以照常启动；
# wait = 自动更新在等用户离开 Android；replace = 正在停 Android、替换程序和系统，这时不能启动
vd_phase() { echo "$1" > "$INSTALL_LOCK/phase" 2>/dev/null || true; }
vd_phase check
trap 'vd_cleanup' EXIT
trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM
# 拿到锁以后，别的 veradroid-install.<pid> 都是残留：持有锁的只有我们。
# 唯一例外：旧版（无锁）安装器还活着——它的 pid 在本次开机里存在且目录 2 分钟内还在变。
for old_tmp in /mnt/base-us/veradroid-install.[0-9]*; do
    [ -d "$old_tmp" ] || continue
    [ "$old_tmp" = "$TMP" ] && continue
    op=${old_tmp##*.}
    case "$op" in *[!0-9]*) continue ;; esac
    if kill -0 "$op" 2>/dev/null && [ -n "$(find "$old_tmp" -mmin -2 2>/dev/null | head -1)" ]; then
        cl=$( { tr '\0' ' ' < /proc/$op/cmdline; } 2>/dev/null || true)
        case "$cl" in *sh*) printf '%s\n' "旧版安装器 pid $op 还在运行，跳过清理 $old_tmp"; continue ;; esac
    fi
    vd_kill_users "$old_tmp"
    show_mb=$(du -sm "$old_tmp" 2>/dev/null | cut -f1)
    printf '%s\n' "清理上次中断留下的临时目录 $old_tmp（${show_mb:-?} MB）"
    rm -rf "/mnt/base-us/veradroid-install.$op" 2>/dev/null || true
done

show() {
    printf '%s\n' "$*"
    if command -v eips >/dev/null 2>&1; then
        eips 1 3 "$*" >/dev/null 2>&1 || true
    fi
}
progress_line() { # pct label
    pct=$1
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    fill=$((pct / 5))
    empty=$((20 - fill))
    bar=$(printf '%*s' "$fill" '' | tr ' ' '#')
    pad=$(printf '%*s' "$empty" '' | tr ' ' '-')
    show "$2 ${pct}% [${bar}${pad}]"
}
# 与 boot/lib/common.sh 的 loop_mount 相同：有的机型（KT6）只有 /dev/loop/N 节点，mount -o loop 会失败
# 和 boot/lib/common.sh 的 storage_mount 一样：镜像如果还挂在某个 loop 设备上（上次延迟卸载的挂载树没放手），
# 再挂一次就是两个文件系统实例同时写同一个镜像，数据必坏。先摘掉残留的 loop，摘不掉就不装。
img_loops() {
    for b in /sys/block/loop*/loop/backing_file; do
        case "$(cat "$b" 2>/dev/null)" in *veradroid-sys.img) d=${b%/loop/backing_file}; echo "${d##*/}" ;; esac
    done
}
img_free() {
    i=0
    while [ -n "$(img_loops)" ]; do
        for l in $(img_loops); do n=${l#loop}; losetup -d /dev/loop$n 2>/dev/null || losetup -d /dev/loop/$n 2>/dev/null; done
        [ -z "$(img_loops)" ] && return 0
        i=$((i + 1)); [ $i -ge 25 ] && return 1
        sleep 1
    done
    return 0
}
loop_mount() { # img dir
    img_free || die "系统盘还在被上次的进程占用：请重启 Kindle 后再安装"
    # 3.0 内核的 ext3 要带 user_xattr（见 boot/lib/common.sh 的 LOOPOPT：没有它 Android 每次开机删光应用数据）
    lo=rw,noatime; case "$(uname -r)" in 3.*) lo=rw,noatime,user_xattr ;; esac
    mount -o loop,$lo "$1" "$2" 2>/dev/null && return 0
    for d in /dev/loop/[0-9]* /dev/loop[0-9]*; do
        [ -b "$d" ] || continue
        losetup "$d" >/dev/null 2>&1 && continue
        losetup "$d" "$1" 2>/dev/null || continue
        { mount -t ext4 -o $lo "$d" "$2" 2>/dev/null || mount -t ext3 -o $lo "$d" "$2" 2>/dev/null; } && return 0   # 3.0 内核只有 ext3
        losetup -d "$d" 2>/dev/null
    done
    return 1
}
die() {
    show "安装失败：$*"
    show "请检查 Wi-Fi / 空间，然后按电源键回到原生后重试"
    sleep 8
    exit 1
}

verify_sha() { # file expected
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$2  $1" | ${LOWPRI:-} sha256sum -c - >/dev/null 2>&1
    elif command -v openssl >/dev/null 2>&1; then
        got=$(openssl dgst -sha256 "$1" 2>/dev/null | awk '{print $NF}')
        [ "$got" = "$2" ]
    else
        return 1
    fi
}

# Restore only files that are missing from DEST. busybox tar -k aborts at the
# first file that already exists ("File exists"), so list the archive first and
# extract just the missing names (-T); existing/newer user files are never touched.

# 下载前空间预检：下载目录（$TMP 所在分区）和 /mnt/base-us 都要够放下安装包+余量。
# 不够就明确报需要/剩余 MB，安全退出，不改任何已有安装。
space_check_before_download() { # size_bytes
    need_b=${1:-0}
    [ "$need_b" -gt 0 ] 2>/dev/null || return 0
    # 安装包先下载到 $TMP，再在同一个分区里解压（解压出来和安装包差不多大），两份同时存在。
    # 以前只按“安装包 + 64 MB”检查：空间刚好够下载的设备会白下 270 MB，然后在解压时报“No space left”。
    # 按 MB 算，避免 32 位 shell 里字节数相乘溢出。
    need_mb=$(( need_b / 1048576 * 21 / 10 + 64 ))
    parent=$(dirname "$TMP")
    mkdir -p "$parent" 2>/dev/null || true
    dl_mb=$(df -m "$parent" 2>/dev/null | awk 'NR==2{print $4}')
    us_mb=$(df -m /mnt/base-us 2>/dev/null | awk 'NR==2{print $4}')
    vlog "pre-download space: need ${need_mb}M (bundle + unpacked + 64M) dl=${dl_mb:-?}M base-us=${us_mb:-?}M"
    short=
    [ -n "$dl_mb" ] && [ "$dl_mb" -lt "$need_mb" ] 2>/dev/null && short="下载目录只剩 ${dl_mb} MB"
    [ -n "$us_mb" ] && [ "$us_mb" -lt "$need_mb" ] 2>/dev/null && short="${short:+$short；}用户存储(/mnt/base-us)只剩 ${us_mb} MB"
    if [ -n "$short" ]; then
        die "空间不够，无法下载安装包：需要约 ${need_mb} MB（安装包+余量），${short}。没有改动任何文件，请清理空间后重试"
    fi
}

restore_missing() { # backup.tgz destdir
    [ -f "$1" ] && [ -d "$2" ] || return 0
    mkdir -p "$TMP" 2>/dev/null || true
    rl="$TMP/restore.list"
    : > "$rl" || return 0
    tar -tzf "$1" 2>/dev/null | while IFS= read -r f; do
        case "$f" in */) continue ;; esac
        p=${f#./}
        [ -n "$p" ] || continue
        is_installer_path "$f" && continue
        [ -e "$2/$p" ] || [ -L "$2/$p" ] || printf '%s\n' "$f" >> "$rl"
    done
    [ -s "$rl" ] || return 0
    show "从安装前的备份恢复 $(wc -l < "$rl" | tr -d ' ') 个缺失文件…"
    tar -xzkf "$1" -C "$2" -T "$rl" 2>/dev/null || true
}
# 2026-11-10 数据安全（在 eink-emulator 里复现 / 排除过）
vlog() { echo "[$(date '+%F %T')] $*" >> /mnt/base-us/veradroid-install-detail.log 2>/dev/null || true; }
android_up() { [ -f "$W/pid" ] && kill -0 "$(cat "$W/pid" 2>/dev/null)" 2>/dev/null; }
# 用户在用：Android 在前台，或者正在启动 / 解冻（veradroid.sh 的 starting / thawing 锁，持有者还活着）
android_in_use() {
    for d in starting thawing; do [ -d "$W/$d" ] && kill -0 "$(cat "$W/$d/pid" 2>/dev/null)" 2>/dev/null && return 0; done
    android_up && [ ! -f "$W/frozen" ]
}
# 替换文件之前调：从这里起 veradroid.sh 不再启动（它会等安装完）。
# 自动更新（VD_AUTOUPDATE=1）决定更新时用户在 Kindle 里（Android 冻结或没开），可下载要好几分钟，这期间用户可能又点了“启动”。
# 以前这里直接 stop.sh：用户刚打开的 Android 十秒后被关掉，屏幕上没有任何解释（用户报告：0.96 更新后“启动后 10 秒被停、再点 20 分钟没反应”）。
# 现在等它回到冻结或退出（最多 2 小时，之后放弃这一次，auto-update 过一会儿再来）。用户自己点的安装 / 更新照旧立刻停。
install_wait_idle() {
    if [ "${VD_AUTOUPDATE:-0}" = 1 ] && android_in_use; then
        vd_phase wait
        vlog "auto update: android is in use, waiting until it is frozen or stopped"
        n=0
        while :; do
            while android_in_use; do
                n=$((n + 1)); [ $n -gt 240 ] && { vlog "auto update: android still in use after 2 h, deferring"; exit 75; }
                sleep 30
            done
            vd_phase replace
            # 置 replace 之前那一刻用户可能刚又点了“启动”（那时 veradroid.sh 还允许启动）：再看一次，又在前台了就接着等
            sleep 2
            android_in_use && { vd_phase wait; continue; }
            break
        done
        vlog "auto update: android no longer in front, installing"
    fi
    vd_phase replace
}
# 安装器停 Android：stop.sh 把原因写进 veradroid.log（以前只记一个已经退出的父进程，看不出是谁停的）
install_stop_android() {
    show "先退出正在运行的 VeraDroid（正在安装更新）…"
    VD_STOP_REASON="installer pid $$ (${VD_AUTOUPDATE:+auto }update ${cur_ver:-?} -> ${LATEST_VER:-${ver:-?}})" sh "$VD/boot/stop.sh" ${1:-} || true
}
# rm -rf 之前：$1 下面（self=1 包括 $1 本身）有挂载就返回 0（绝不能穿过 bind 挂载删到 Kindle 的书）
# 2026-11-13：容器自己的挂载命名空间里的挂载（Kindle 的 documents 绑在那里）宿主 /proc/mounts 看不到，也要查（同 boot/lib/common.sh）
mounts_under() { # dir [self]
    awk -v d="${1%/}" -v self="${2:-0}" '($2 == d && self == 1) || index($2, d "/") == 1 { f = 1 } END { exit !f }' /proc/mounts && return 0
    # legacy 宿主（3.0 / 4.1 内核）的 chroot 模式也在 unshare -m 的私有挂载命名空间里（k49 的 chroot 模式不是）；
    # 3.0 内核没有 /proc/PID/ns，判断不了是不是同一个命名空间：一律查（同 host/legacy 的 mounts_under_ns，最多多报）
    case "$(uname -r)" in 3.*|4.1.*) mu_leg=1 ;; *) mu_leg= ;; esac
    [ -z "$mu_leg" ] && [ "$(cat $W/mode 2>/dev/null)" = chroot ] && return 1
    for mu_p in $(cat $W/pid 2>/dev/null); do
        [ -r /proc/$mu_p/mounts ] || continue
        mu_a=$(readlink /proc/$mu_p/ns/mnt 2>/dev/null || true)
        [ -n "$mu_a" ] && [ "$mu_a" = "$(readlink /proc/self/ns/mnt 2>/dev/null || true)" ] && continue
        awk -v d="${1%/}" -v self="${2:-0}" -v r="$SYS/rootfs" -v sd="$SYS/data" '
            function hit(h) { return (h == d && self == 1) || index(h, d "/") == 1 }
            { m = $2; if (m == "/") m = ""
              if (hit(r m)) f = 1
              if (m == "/data" || index(m, "/data/") == 1) { if (hit(sd substr(m, 6))) f = 1 } }
            END { exit !f }' /proc/$mu_p/mounts && return 0
    done
    return 1
}
guard_rm() { # dir...: 删除系统目录前的防护；下面有挂载就停下，什么都不删
    for g in "$@"; do
        [ -e "$g" ] || continue
        if mounts_under "$g" 1; then
            vlog "refuse rm -rf $g: $(awk -v d="${g%/}" '$2 == d || index($2, d "/") == 1 {print $2}' /proc/mounts | tr '\n' ' ')"
            die "$g 下面还有挂载（上次的 VeraDroid 没有停干净）。为了不误删 Kindle 的书，安装已停止：请重启 Kindle 后再装"
        fi
    done
}
# 书库脚本（安装器）本身不是用户数据：不要从备份里恢复，也不要因为它们“不见了”就留着旧备份
is_installer_path() {
    case "$1" in
        documents/VeraDroid.sh*|documents/VeraDroid-Experimental.sh*|documents/VeraDroid-Offline.sh*|documents/bootstrap.sh*|\
        ./VeraDroid.sh*|./VeraDroid-Experimental.sh*|./VeraDroid-Offline.sh*|./bootstrap.sh*) return 0 ;;
        # 离线包带来的整包和书库给安装器建的 .sdr：装完会被删掉，同样不是用户数据
        documents/veradroid-pw6-*.tar.gz|documents/veradroid-k49-*.tar.gz|\
        documents/VeraDroid-Report.sh*|documents/VeraDroid-Uninstall.sh*|documents/VeraDroid-Report.sdr*|documents/VeraDroid-Uninstall.sdr*|\
        documents/VeraDroid.sdr|documents/VeraDroid.sdr/*|documents/VeraDroid-Experimental.sdr|documents/VeraDroid-Experimental.sdr/*|\
        documents/VeraDroid-Offline.sdr|documents/VeraDroid-Offline.sdr/*|documents/bootstrap.sdr|documents/bootstrap.sdr/*|\
        documents/veradroid-legacy-*.tar.gz|documents/VeraDroid-Legacy.sh*|documents/VeraDroid-Legacy.sdr|documents/VeraDroid-Legacy.sdr/*|./VeraDroid-Legacy.sh*) return 0 ;;
    esac
    return 1
}
# 安装器运行时把自己（书库里的 VeraDroid*.sh）交给我们删：父进程 sh 还在读这个文件，立刻删掉会让它读到半截
# （KT6 模拟器：“line 27: syntax error: unterminated quoted string”）。等它退出后再删。
# 书库给每个被索引的文件建一个附属文件夹（脚本是 <文件名>.sh.sdr，放图标；txt 是 <去掉扩展名>.sdr）；
# 安装器删掉后它就是垃圾，一起删。只认这几个固定名字，只删紧挨着安装器的那两个目录名。
remove_installer_later() {
    if [ -n "${VD_INSTALLER:-}" ] && [ -f "$VD_INSTALLER" ]; then
        case "$(basename "$VD_INSTALLER")" in
            VeraDroid.sh|VeraDroid-Experimental.sh|VeraDroid-Offline.sh)
                ( cd / && setsid sh -c 'sleep 30; rm -f "$1"; for d in "$1.sdr" "${1%.sh}.sdr"; do [ -d "$d" ] && [ ! -L "$d" ] && rm -rf "$d"; done; sync' sh "$VD_INSTALLER" ) </dev/null >/dev/null 2>&1 & ;;
        esac
    fi
}
# 离线包里的 README.txt：只有内容确实是我们那份说明（很小，第一行以“VeraDroid ”开头并写着“离线”）才算。
# 用户自己的 README.txt 不动。
is_offline_readme() { # file
    [ -f "$1" ] && [ ! -L "$1" ] || return 1
    [ "$(wc -c < "$1" 2>/dev/null | tr -d ' ')" -lt 4096 ] 2>/dev/null || return 1
    head -n 1 "$1" 2>/dev/null | grep -q '^VeraDroid .*离线' || return 1
    return 0
}
# 书库清单里不算用户书：离线包的 README.txt / README.sdr（安装成功后安装器自己删掉；以前算进清单，
# 第一次开机报“DOCUMENTS LOSS”再从备份恢复回书库——真机 PW4 第一份报告）
offline_readme_doc() { case "$1" in documents/README.txt|documents/README.sdr|documents/README.sdr/*) is_offline_readme /mnt/base-us/documents/README.txt ;; *) return 1 ;; esac; }
# 离线安装成功后：把离线包带来的文件全部清掉（整包、bootstrap.sh、README.txt 和它们的 .sdr）。
# 只在离线包所在的目录里、只按固定名字删；安装器本身由 remove_installer_later 等它退出后再删。
remove_offline_package() {
    [ -n "${VD_OFFLINE_BUNDLE:-}" ] || return 0
    od=$(dirname "$VD_OFFLINE_BUNDLE")
    [ -d "$od" ] || return 0
    case "$(basename "$VD_OFFLINE_BUNDLE")" in
        veradroid-pw6-*.tar.gz|veradroid-k49-*.tar.gz|veradroid-legacy-*.tar.gz) [ -f "$VD_OFFLINE_BUNDLE" ] && rm -f "$VD_OFFLINE_BUNDLE" 2>/dev/null || true ;;
    esac
    if [ -n "${VD_HELPER:-}" ] && [ -f "$VD_HELPER" ] && [ "$(basename "$VD_HELPER")" = bootstrap.sh ]; then
        rm -f "$VD_HELPER" 2>/dev/null || true
        for hs in "$VD_HELPER.sdr" "${VD_HELPER%.sh}.sdr"; do
            if [ -d "$hs" ] && [ ! -L "$hs" ]; then rm -rf "$hs" 2>/dev/null || true; fi
        done
    fi
    if is_offline_readme "$od/README.txt"; then
        rm -f "$od/README.txt" 2>/dev/null || true
        if [ -d "$od/README.sdr" ] && [ ! -L "$od/README.sdr" ]; then rm -rf "$od/README.sdr" 2>/dev/null || true; fi
        vlog "offline package: removed README.txt"
    fi
    sync 2>/dev/null || true
}

res=$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)
model_tree=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' ' ')
case "$model_tree" in
    *sangria*) detected=pw6 ;;
    *seabreeze*) detected=cs ;;
    *malbec*) detected=pw5 ;;
    *rossini*) detected=kt6 ;;
    *cava*) detected=kt5 ;;
    *barolo*) detected=ks ;;
    *pisco*) detected=ks2 ;;
    *) detected= ;;
esac
# PW5/KT5/KT6（eink-emulator 实测）的设备树只有通用的 "mediatek,mt8110 mediatek,mt8512"，没有板名。
# 这时按屏宽猜：1236/1248 -> pw5；1072 -> KT（vfat 用户分区 -> kt5，否则 kt6）。
# 只在没有 VD_MODEL 时使用；kt5/kt6 的安装行为相同（文件系统和内存都在后面按实测处理）。
guessed=
# 老机型按内核代际归类（eink-emulator 实测，见 docs/compat-matrix.md）：
#   3.0.x：PW2 / PW3 / Oasis 1/2 / Voyage / 入门款 2014、2016——没有命名空间，走 chroot 模式 + 自带 binder 模块（legacy）
#   4.1.x：PW4 / 入门款 2019 / Oasis 2 / Oasis 3——有（或没有）命名空间、没有 binder / tun / uinput / freezer：
#          装 legacy 整包（Cortex-A9 系统）+ 按这台 Kindle 的内核编的 binder / uinput 模块（imx41，docs/imx41.md）；
#          只有模拟器验证过，测试时带 VD_IMX41_TEST=1
case "$(uname -r)" in
    3.*) [ -z "$detected" ] && guessed=legacy ;;
    4.1.*) [ -z "$detected" ] && guessed=imx41 ;;
esac
# 老机型包只给 3.0 / 4.1 内核：新机型（PW5 / PW6 / Scribe……）在这里就拦下，什么都还没动。
case "$(uname -r)" in
    3.*|4.1.*) ;;
    *) die "这个安装包是老机型（PW2 / PW3 / Voyage / PW4 / Oasis）用的，这台 Kindle（内核 $(uname -r | cut -d. -f1-2)）不能装，本机未改动。PW6 / Colorsoft 请用 VeraDroid-Offline.zip，PW5 / KT5 / KT6 / Scribe 请用 VeraDroid-Offline-Experimental.zip / This package is for older Kindles (Legacy) and cannot be installed here; nothing was changed. Use VeraDroid-Offline.zip (PW6 / Colorsoft) or VeraDroid-Offline-Experimental.zip (PW5 / KT5 / KT6 / Scribe)" ;;
esac
if [ -z "$detected" ] && [ -z "$guessed" ]; then
    case "$model_tree" in
        *mt8110*)
            case "${res%%,*}" in
                1236|1248) guessed=pw5 ;;
                # Scribe：模拟器设备树没有板名（pisco/barolo），按屏宽区分（ks2 1872，ks 1860）。
                1872) guessed=ks2 ;;
                1860|2480) guessed=ks ;;
                1072) case "$(stat -f -c %T /mnt/base-us 2>/dev/null)" in
                          vfat|msdos) guessed=kt5 ;;
                          *) guessed=kt6 ;;
                      esac ;;
            esac ;;
    esac
fi
MODEL=${VD_MODEL:-${detected:-$guessed}}
MODEL=$(printf '%s' "$MODEL" | tr 'A-Z' 'a-z')
if [ -n "$detected" ] && [ -n "${VD_MODEL:-}" ] && [ "$MODEL" != "$detected" ]; then
    echo "机型不匹配：设备是 $detected，安装包是 $MODEL。"
    exit 1
fi
[ -n "$MODEL" ] || MODEL=pw6
# 自动更新从已有的实验机型安装过来时（auto-update.sh 读 $SYS/model 来设 VD_EXPERIMENTAL）：loop 机型（KT5/KT6/PW5）
# Android 没在跑时系统盘没挂上，读不到 model，更新就被下面拒绝，设备永远卡在旧版本（KT5 0.78 -> 0.79 模拟器复现）。
# 已经装过（程序目录 + 系统盘都在）就说明用户当初选了实验机型：沿用，并把机型也记在系统盘外面。
if [ "$MODEL" != "pw6" ] && [ "${VD_EXPERIMENTAL:-0}" != "1" ]; then
    prevm=$(cat /mnt/base-us/veradroid/model 2>/dev/null || true)   # set -e：文件不存在不能让脚本退出
    if [ "$prevm" = "$MODEL" ] || { [ -z "$prevm" ] && [ -d /mnt/base-us/veradroid/boot ] && [ -f /mnt/base-us/veradroid-sys.img ]; }; then
        echo "已安装的实验机型 $MODEL：继续更新"
        VD_EXPERIMENTAL=1
    fi
fi
# 还不能装的机型先说清楚：以前 PW4 / 入门款 2019 用正式脚本时被告知“请改用实验机型脚本”，换了脚本才看到“暂时不能安装”，
# 而且这些原因只写进日志，屏幕上只有“安装失败（代码 1）”。现在直接在屏幕上显示原因（show = 日志 + eips）。
# 机型表的“验证程度”：emulator-only = 只在模拟器上跑过、没有真机验证（3.0 内核 legacy、4.1 内核 imx41）。
# 这些机型走实验机型安装，但必须是用户在实验机型脚本里看过警告、10 秒到 2 分钟内又点了一次（VD_EMUONLY_OK=1）；
# 开发测试用的 VD_IMX41_TEST=1 / VD_LEGACY_TEST=1 照旧放行。装好后写 $VD/tested，宿主据此开自检和兜底（boot/lib/tester.sh）。
# 真机验证过的机型（pw6 / pw5 / kt5 / kt6 / ks / ks2 / cs）TESTED=device，下面这些都不经过。
model_tested() { case "$1" in legacy|imx41) echo emulator-only ;; *) echo device ;; esac; }
TESTED=$(model_tested "$MODEL")
emuonly_ok() {
    [ "${VD_EMUONLY_OK:-0}" = 1 ] && return 0
    case "$MODEL" in imx41) [ "${VD_IMX41_TEST:-0}" = 1 ] ;; legacy) [ "${VD_LEGACY_TEST:-0}" = 1 ] ;; *) return 1 ;; esac
}
# 日志里记下序列号的机型代码（不记完整序列号），志愿者的安装日志能直接看出是哪台机型
sc=$( { tr -cd '0-9A-Za-z' </proc/usid; } 2>/dev/null || true); case "$sc" in B*) sc=$(echo "$sc" | cut -c3-4) ;; ?*) sc=$(echo "$sc" | cut -c4-6) ;; esac
vlog "model $MODEL ($TESTED), serial model code ${sc:-?}, kernel $(uname -r), firmware $(head -1 /etc/prettyversion.txt 2>/dev/null || true)"
if [ "$TESTED" = emulator-only ] && ! emuonly_ok; then
    if [ "${VD_AUTOUPDATE:-0}" = 1 ]; then echo "emulator-only model $MODEL: no automatic update without the user's confirmation"; exit 0; fi
    show "这台 Kindle 的机型只在模拟器上验证过：请用“VeraDroid 安装（实验机型）”，看完屏幕上的说明后再点一次确认"
    exit 1
fi
# emulator-only 机型逐台放行：只有通过了模拟器发布门（全新安装、开机、自检、返回 Kindle、强制失败自动返回、卸载、书库 md5 不变，
# docs/compat-matrix.md 8.5）的机型才装；其余的屏幕上说“还在测试”，什么都不动。认机型的办法和宿主 settings.sh 的 model_sub 相同。
# 开发测试（VD_LEGACY_TEST=1 / VD_IMX41_TEST=1）不受限制。
LEGACY_READY="pw3 pw4 kv oa2 ko3 pw2"
legacy_sub() {
    ls_fb=$(awk -F'[:x p]' '/^U:/ { w=$2; h=$3; if (w+0 > 0) { print (w < h ? w : h); exit } }' /sys/class/graphics/fb0/modes 2>/dev/null)
    case "$(uname -r)" in
        3.*) case "$(cut -c1-3 /proc/board_id 2>/dev/null)" in
                 027|02A|02E|02F) echo pw2; return ;; 01A|01B|025|026|047|048) echo kv; return ;;
                 067|068|13G) echo pw3; return ;; 078|079|07F) echo oa1; return ;; esac
             if grep -q 'Name="fsr_keypad"' /proc/bus/input/devices 2>/dev/null; then echo kv
             else case "$ls_fb" in 758) echo pw2 ;; 1072) echo pw3 ;; esac; fi ;;
        4.1.*) case "$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null)" in
                 *imx7d-zelda*) if [ -e /proc/self/ns/pid ]; then echo ko3; else echo oa2; fi ;;
                 *imx6sll*) case "$ls_fb" in 600) echo kt4 ;; *) echo pw4 ;; esac ;; esac ;;
    esac
}
if [ "$TESTED" = emulator-only ] && [ "${VD_LEGACY_TEST:-0}" != 1 ] && [ "${VD_IMX41_TEST:-0}" != 1 ]; then
    SUBM=$(legacy_sub)
    vlog "emulator-only sub-model: ${SUBM:-unknown} (ready: $LEGACY_READY)"
    case " $LEGACY_READY " in
        *" ${SUBM:-none} "*) ;;
        *) [ "${VD_AUTOUPDATE:-0}" = 1 ] && { echo "sub-model ${SUBM:-unknown} not released yet"; exit 0; }
           show "这台 Kindle（${SUBM:-没认出的机型}）还在模拟器里测试，暂时不能安装。什么都没有改动"; exit 1 ;;
    esac
fi
if [ "$MODEL" != "pw6" ] && [ "${VD_EXPERIMENTAL:-0}" != "1" ]; then
    show "这台 Kindle 是 $MODEL（实验机型）：请改用“VeraDroid 安装（实验机型）”脚本"
    exit 1
fi
case "$MODEL" in
    pw6|cs) ok='1272,1696 1272,3392' ;;
    pw5) ok='1236,1648 1236,3296 1248,1648 1248,3296' ;;
    kt5|kt6) ok='1072,1448 1072,2896' ;;
    ks) ok='1860,2480 2480,1860 1860,4960 2480,3720 2480,4960' ;;
    ks2) ok='1872,4960 1872,2480 1860,2480 1860,4960' ;;
    imx41) # 4.1 内核（PW4 / 入门款 2019 / Oasis 2 / Oasis 3）：emulator-only，上面已经要求确认
        ok="$res" ;;   # 显示尺寸开机时从帧缓冲读
    legacy) # 3.0 内核老机型（PW2 / PW3 / Voyage 等）：emulator-only，上面已经要求确认
        ok="$res" ;;   # 机型多、分辨率各不相同：显示尺寸开机时从帧缓冲读
    *) ok='' ;;
esac
valid=0
for r in $ok; do [ "$res" = "$r" ] && valid=1; done
if [ "$valid" != "1" ]; then
    echo "机型 $MODEL 的分辨率不匹配（检测到 $res）。"
    echo "这是实验性适配，未验证前不要安装。"
    exit 1
fi
if [ "$MODEL" != "pw6" ]; then
    echo "!! 实验机型 $MODEL：尚未实机验证，可能黑屏/触摸失效。继续。"
fi
# Package survey: the Android userspace needs firmware 5.18+.
FW=$(sed -n 's/.*Kindle[[:space:]]*\([0-9][0-9.]*\).*/\1/p' /etc/prettyversion.txt 2>/dev/null | head -1)
if [ -n "$FW" ]; then
    fwn=$(printf '%s\n' "$FW" | awk -F. '{printf "%d%03d%03d", $1, $2, $3}')
    if [ "$MODEL" != legacy ] && [ "$MODEL" != imx41 ] && [ "$fwn" -lt 5017000 ] 2>/dev/null && [ "${VD_ALLOW_OLD_FW:-0}" != 1 ]; then
        die "固件 $FW 太旧；VeraDroid 需要 5.17 或更新"
    fi
fi
if [ "${VD_DRY_RUN:-0}" = "1" ]; then
    fw=$(sed -n 's/.*Kindle[[:space:]]*\([0-9][0-9.]*\).*/\1/p' /etc/prettyversion.txt 2>/dev/null | head -1)
    show "自检通过：model=$MODEL firmware=${fw:-unknown} framebuffer=$res"
    show "未下载、未安装（VD_DRY_RUN=1）"
    exit 0
fi
[ "$(id -u)" = "0" ] || die "需要 root/越狱环境"
for c in curl tar id; do
    command -v "$c" >/dev/null 2>&1 || die "缺少命令 $c"
done
[ -d /mnt/base-us ] && [ -w /mnt/base-us ] || die "/mnt/base-us 不可写；这个越狱方式可能不兼容"
# ---- 老机型（3.0 内核：PW2 / PW3 / Voyage …）安装期间的保护 ----
# PW2 / Voyage 模拟器上两次装到一半整机重启：Kindle 自己的 Java 框架（cvm）和安装器（建 1.5 GB 系统盘、解压）抢 CPU 和闪存，
# 105 秒内没起来就算一次失败，连续 3 次 lab126_gui_monitor 就重启整机（/etc/upstart/monitor_functions 的计数文件）。所以：
#  1. 开机后马上装的话，先等框架起来（最多 3 分钟），别在它最需要 CPU 的时候抢；
#  2. 重活（建盘、校验、解压）用低优先级（nice 10、ionice 尽力而为级最低档），Kindle 的界面和看门狗先跑；
#  3. 安装期间每 5 秒清一次 lab126_gui / framework 的重启计数，框架真起不来时也不会在安装途中重启整机（安装结束就不再管）。
# 大量写盘期间（解压）每 2 秒 sync 一次：小内存的老机型上脏页攒多了一次刷盘会把整机卡住（见下面建系统盘的说明）
SYNCER=
syncer_on() { [ -n "$LOWPRI" ] || return 0; ( while :; do sleep 2; sync; done ) </dev/null >/dev/null 2>&1 & SYNCER=$!; }
syncer_off() { [ -n "$SYNCER" ] && kill "$SYNCER" 2>/dev/null; SYNCER=; return 0; }
LOWPRI=
if [ "$MODEL" = legacy ] || [ "$MODEL" = imx41 ]; then
    LOWPRI="nice -n 10"; command -v ionice >/dev/null 2>&1 && LOWPRI="$LOWPRI ionice -c 2 -n 7"
    if [ "$(lipc-get-prop com.lab126.kaf frameworkStarted 2>/dev/null)" != 1 ] && initctl status framework 2>/dev/null | grep -q 'start/'; then
        show "等待 Kindle 界面启动完成…"
        i=0; while [ $i -lt 60 ] && [ "$(lipc-get-prop com.lab126.kaf frameworkStarted 2>/dev/null)" != 1 ]; do sleep 3; i=$((i + 1)); done
        vlog "legacy: waited $((i * 3))s for the Kindle framework (frameworkStarted=$(lipc-get-prop com.lab126.kaf frameworkStarted 2>/dev/null))"
    fi
    ( while kill -0 $$ 2>/dev/null; do
          for j in lab126_gui framework framework_setup; do rm -f "/var/run/upstart/$j.restarts" "/var/local/upstart/$j.restarts"; done
          sleep 5
      done ) </dev/null >/dev/null 2>&1 &
fi
# emulator-only 机型：安装前一定要有一份书库的备份（documents 里 20 MB 以下的文件 + 完整文件清单），做不了就不装。
# 先算好要多大，后面建系统盘时把这部分空间留出来（大文件不备份：屏幕上和说明里都要求用户先自己拷到电脑）。
EMU_BAKK=0
if [ "$TESTED" = emulator-only ] && [ -d /mnt/base-us/documents ]; then
    EMU_BAKK=$(cd /mnt/base-us && find documents -type f -size -20480k 2>/dev/null | while IFS= read -r f; do is_installer_path "$f" || stat -c %s "$f" 2>/dev/null; done | awk '{s += $1} END {print int(s / 1024) + 1}')
    vlog "emulator-only: small-file documents backup needs ~${EMU_BAKK} KB"
fi
# emulator-only 机型的安装要 15–40 分钟（建盘最慢），比 Kindle 自动进屏保的时间长：一进屏保机器就睡下去，安装停在半路
# （PW3 模拟器实测：建盘途中休眠，之后 ssh 都连不上）。安装期间不让它进屏保，结束（成功、失败、被杀）时恢复原来的值。
KEEPAWAKE=
if [ "$TESTED" = emulator-only ]; then
    KEEPAWAKE=$(lipc-get-prop com.lab126.powerd preventScreenSaver 2>/dev/null || true); case "$KEEPAWAKE" in 1) ;; *) KEEPAWAKE=0 ;; esac
    lipc-set-prop com.lab126.powerd preventScreenSaver 1 >/dev/null 2>&1 || true
fi
FS=$(stat -f -c %T /mnt/base-us 2>/dev/null || true)
LOOP=0
case "$FS" in
    ext2/ext3|ext4|xfs|btrfs|f2fs) ;;
    vfat|msdos|exfat) LOOP=1; mount -o remount,exec /mnt/base-us 2>/dev/null || true ;;
    *) die "/mnt/base-us 是 $FS，不能保存 Android 的符号链接" ;;
esac
# KT6 等 4.9 内核机型（eink-emulator 实测）：/mnt/base-us/system 和 documents 用 fscrypt v1 加密，
# 密钥挂在 uid 0 的默认会话 keyring 里。system_server（uid 1000）拿不到密钥，新建文件报
# "Required key not available"，开机循环崩溃。改用 ext4 loop 系统盘，镜像内部不加密。
# 只限 4.x 内核：PW6（5.15）不走这里，已有安装不会被挪动。
if [ "$LOOP" = 0 ]; then
    case "$(uname -r)" in
        4.*) grep -q ' logon .*fscrypt:' /proc/keys 2>/dev/null && LOOP=1 ;;
    esac
fi
[ -d /dev/shm ] || die "缺少 /dev/shm"

stamp=$(date +%Y%m%d-%H%M%S)
if [ "$LOOP" = 1 ]; then
    # 上次建系统盘被打断（断电 / 被杀：在 vfat 上 dd 3 GB 要好几分钟）会留下一个没有文件系统的半截镜像，
    # 以后每次安装都“无法挂载 ext4 系统盘”。没挂着、也没有 ext2/3/4 超级块（偏移 1080 处 53 ef）的镜像里不可能有数据：删掉重建。
    if [ -f "$SYSTEM_IMG" ] && ! grep -q " $SYS " /proc/mounts; then
        mg=$(dd if="$SYSTEM_IMG" bs=1 skip=1080 count=2 2>/dev/null | od -An -tx1 | tr -d ' \n')
        if [ -n "$mg" ] && [ "$mg" != "53ef" ]; then   # od / dd 不可用时 mg 为空：什么都不删
            vlog "system image $SYSTEM_IMG has no ext superblock (magic '$mg', size $(stat -c %s "$SYSTEM_IMG" 2>/dev/null)): interrupted creation, recreating"
            rm -f "$SYSTEM_IMG"
        fi
    fi
    if [ ! -f "$SYSTEM_IMG" ]; then
        # 3.0 内核没有 ext4 驱动，只能用 ext3；这些机型存储也小（PW2 2 GB），系统盘 1.5 GB 够用
        # 起始大小按剩余空间挑（装好以后可以在 设置 → 设备与更新 → 存储空间 里调，快满时还会自动扩大，见 boot/lib/storage.sh）：
        # 默认 2 GB；Kindle 快满时依次退到 1536 / 1280 / 1024 MB。条件：系统盘 + 安装要用的地方（IMGSLACK）+ 留给 Kindle 的 256 MB
        # 都放得下 —— 以前固定 3072 MB，8 GB 的机器上书一多就装不了，装上了也把 Kindle 挤满。
        IMGFS=ext4; IMGSIZES="2048 1536 1280 1024"
        IMGSLACK=300; IMGKEEP=256
        # legacy：建完系统盘还要下载并解开约 140 MB 的安装包（下载前的检查要 ~350 MB）。余量只留 300 MB 时，
        # 3 GB 存储的 PW3 上先花十几分钟建好 1.5 GB 的盘，然后才报“空间不够，无法下载”（模拟器实测）。先把账算够。
        # 这些机型存储小（PW2 2 GB），没有 ext4 驱动只能用 ext3：1536 起，放不下退到 1024 / 768，不另留 256 MB。
        # 4.1 内核（PW4 / KT4 / Oasis 2 / Oasis 3，imx41）有 ext4，存储也小（KT4 4 GB）：同样 1536 起。
        case "$(uname -r)" in 3.*) IMGFS=ext3; IMGSIZES="1536 1024 768"; IMGSLACK=400; IMGKEEP=0 ;;
                              4.1.*) IMGSIZES="1536 1024 768"; IMGSLACK=400; IMGKEEP=0 ;; esac
        IMGSLACK=$((IMGSLACK + EMU_BAKK / 1024))      # emulator-only：书库备份要的空间（压缩前的大小，留足）
        free_mb=$(df -m /mnt/base-us 2>/dev/null | awk 'NR==2{print $4}')
        IMGMB=
        for c in $IMGSIZES; do
            IMGMIN=$c
            case "$free_mb" in ''|*[!0-9]*) IMGMB=$c; break ;; esac        # 读不到剩余空间：按默认值试
            [ "$free_mb" -ge $((c + IMGSLACK + IMGKEEP)) ] && { IMGMB=$c; break; }
        done
        # 测试 / 存储很小的机器（模拟器的入门款 2019 只有 800 MB）：VD_IMGMB 指定系统盘大小（MB）。legacy 系统解开约 270 MB；
        # 余量只留后面下载 + 解开整包要的 360 MB
        case "${VD_IMGMB:-}" in ''|*[!0-9]*) ;; *) [ "$VD_IMGMB" -ge 300 ] && { IMGMB=$VD_IMGMB; IMGMIN=$VD_IMGMB; IMGSLACK=360; IMGKEEP=0
            [ -n "$free_mb" ] && [ "$free_mb" -lt $((IMGMB + IMGSLACK)) ] 2>/dev/null && IMGMB=; } ;; esac
        [ -n "$IMGMB" ] || die "Kindle 空间不够：至少需要约 $((IMGMIN + IMGSLACK + IMGKEEP)) MB，现在只有 ${free_mb} MB"
        show "创建 $IMGFS 系统盘（$IMGMB MB）…"
        if [ -n "$LOWPRI" ]; then
            # 老机型（vfat 用户分区不支持稀疏文件，整盘全要真写）：一次写完会在 256 / 512 MB 内存里攒满脏页，
            # 整机卡死几十秒（PW2 / Voyage 模拟器在这一步被硬件看门狗复位过好几次）。每 32 MB 落盘一次、歇一下。
            rm -f "$SYSTEM_IMG"; o=0
            while [ $o -lt $IMGMB ]; do
                $LOWPRI dd if=/dev/zero of="$SYSTEM_IMG" bs=1M count=32 seek=$o conv=notrunc 2>/dev/null || die "无法创建系统盘"
                sync; o=$((o + 32)); progress_line $((o * 100 / IMGMB)) "建系统盘"; sleep 1
            done
            [ "$(stat -c %s "$SYSTEM_IMG" 2>/dev/null)" -ge $((IMGMB * 1048576)) ] 2>/dev/null || die "无法创建系统盘"
        else
            ( truncate -s ${IMGMB}M "$SYSTEM_IMG" 2>/dev/null || dd if=/dev/zero of="$SYSTEM_IMG" bs=1M count=$IMGMB 2>/dev/null ) || die "无法创建系统盘"
        fi
        $LOWPRI mkfs.$IMGFS -F -q -L VeraDroid "$SYSTEM_IMG" || die "mkfs.$IMGFS 失败"
    fi
    if ! grep -q " $SYS " /proc/mounts; then
        if [ -d "$SYS" ] && [ -n "$(ls -A "$SYS" 2>/dev/null)" ]; then
            mv "$SYS" "$SYS.pre-ext4.$stamp" 2>/dev/null || true
        fi
        mkdir -p "$SYS"
        loop_mount "$SYSTEM_IMG" "$SYS" || die "无法挂载 ext4 系统盘"
    fi
    # 卸载（或更早的非 loop 安装）留下的书 / 微信读书下载 / token 在 $SYS.pre-ext4.*/data/media：搬进系统盘（不覆盖、原目录保留）
    if [ ! -d "$SYS/data/media/0" ]; then
        pre=
        [ -d /mnt/base-us/veradroid-media-keep/0 ] && pre=/mnt/base-us/veradroid-media-keep   # 卸载时留下的
        [ -n "$pre" ] || pre=$(ls -dt "$SYS".pre-ext4.*/data/media 2>/dev/null | head -1)
        if [ -n "$pre" ]; then
            need=$(du -sk "$pre" 2>/dev/null | awk '{print $1}')
            freei=$(df -k "$SYS" 2>/dev/null | awk 'NR==2{print $4}')
            if [ $(( ${need:-0} + 102400 )) -lt "${freei:-0}" ]; then
                show "把以前的书和账号搬回系统盘…"
                if mkdir -p "$SYS/data" && cp -a "$pre" "$SYS/data/media"; then
                    vlog "restored data/media from $pre"
                    # 卸载留下的那份：核对数量一致后删掉（已经在系统盘里了）；pre-ext4 的旧目录不动
                    if [ "$pre" = /mnt/base-us/veradroid-media-keep ] && [ "$(find "$pre" | wc -l)" = "$(find "$SYS/data/media" | wc -l)" ]; then
                        rm -rf "$pre" && vlog "removed $pre after verified copy"
                    fi
                else
                    vlog "copy from $pre failed"
                fi
            else
                vlog "not enough space in system image to restore $pre (${need}K)"
            fi
        fi
    fi
fi

# Existing-install check: do not blindly reinstall a complete, current install.
# Repair if important files are missing; update only when the server has a
# newer bundle.  VD_FACTORY=1 or --force still forces a full install.
apply_patch() {
    [ -n "$LATEST_PATCH_URL" ] && [ -n "$LATEST_PATCH_SHA" ] || return 1
    [ "$LATEST_PATCH_FROM" = "$cur_ver" ] || return 1
    [ "$LATEST_VER" != "$cur_ver" ] || return 1
    show "发现增量补丁 ${cur_ver} -> ${LATEST_VER}（约 ${LATEST_PATCH_SIZE:-?} bytes）"
    vd_phase download
    rm -rf "$TMP/patch" "$TMP/patch.tar.gz"
    mkdir -p "$TMP/patch"
    curl_do -fL --retry 8 $RETRY_ALL --retry-delay 3 --connect-timeout 20 --max-time 600 --speed-limit 512 --speed-time 30 -C - -o "$TMP/patch.tar.gz" "$LATEST_PATCH_URL" || return 1
    verify_sha "$TMP/patch.tar.gz" "$LATEST_PATCH_SHA" || return 1
    tar -xzf "$TMP/patch.tar.gz" -C "$TMP/patch" || return 1
    [ -d "$TMP/patch/veradroid-pw6" ] || return 1
    install_wait_idle
    if android_up; then
        install_stop_android >/dev/null 2>&1
        sleep 1
        if [ "$LOOP" = 1 ]; then
            mkdir -p "$SYS"
            grep -q " $SYS " /proc/mounts || loop_mount "$SYSTEM_IMG" "$SYS" || return 1
        fi
    fi
    for d in boot bin apks screensaver fonts kmod; do
        [ -d "$TMP/patch/veradroid-pw6/$d" ] || continue
        mkdir -p "$VD/$d"
        cp -a "$TMP/patch/veradroid-pw6/$d/." "$VD/$d/" 2>/dev/null || true
    done
    if [ -d "$TMP/patch/veradroid-pw6/rootfs" ]; then
        cp -a "$TMP/patch/veradroid-pw6/rootfs/." "$SYS/rootfs/" 2>/dev/null || true
    fi
    for f in VeraDroid-Launch.sh libandroid_runtime.so; do
        [ -f "$TMP/patch/veradroid-pw6/$f" ] || continue
        if [ "$f" = libandroid_runtime.so ]; then
            cp -a "$TMP/patch/veradroid-pw6/$f" "$SYS/rootfs/system/lib/$f" 2>/dev/null || return 1
        else
            cp -a "$TMP/patch/veradroid-pw6/$f" "$VD/$f" 2>/dev/null || true
        fi
    done
    echo "$LATEST_VER" > "$VERSION_FILE"
    echo "$LATEST_VER" > "$VD/version"
    vd_phase done
    show "增量更新完成：$LATEST_VER"
    [ "${VD_NO_START:-0}" = 1 ] || setsid sh "$VD/boot/veradroid.sh" home </dev/null >/dev/null 2>&1 || true
    return 0
}

install_complete() {
    for f in \
        "$SYS/rootfs/init" \
        "$SYS/rootfs/system/bin/sh" \
        "$SYS/rootfs/system/framework/framework.jar" \
        "$SYS/rootfs/system/priv-app/VeraHome/VeraHome.apk" \
        "$SYS/rootfs/system/lib/libandroid_runtime.so" \
        "$VD/boot/veradroid.sh" \
        "$VD/boot/stop.sh" \
        "$VD/bin/veradroid-epd" \
        "$VD/bin/veradroid-input" \
        "$VD/VeraDroid-Launch.sh"; do
        [ -e "$f" ] || return 1
    done
    # vdlmk is only shipped in the k49 (4.9 kernel) bundle; the PW6 bundle has none and
    # afterboot.sh treats it as optional. Requiring it on PW6 made every run reinstall.
    case "$(uname -r)" in
        4.*) [ -e "$VD/bin/vdlmk" ] || return 1 ;;
    esac
    return 0
}
vercmp() { # $1 $2 -> -1/0/1
    awk -v a="$1" -v b="$2" 'BEGIN{
        n=split(a,x,"."); m=split(b,y,".");
        k=(n>m?n:m);
        for(i=1;i<=k;i++){ if((x[i]+0)>(y[i]+0)){print 1; exit} if((x[i]+0)<(y[i]+0)){print -1; exit} }
        print 0
    }'
}
LATEST_VER=
LATEST_PATCH_URL=
LATEST_PATCH_SHA=
LATEST_PATCH_SIZE=
LATEST_PATCH_FROM=
latest_version() {
    if [ -n "${VD_BUNDLE:-}" ]; then
        LATEST_VER=${VD_VERSION:-}
        printf '%s' "$LATEST_VER"
        return 0
    fi
    case "$(uname -r)" in
        3.*|4.1.*) m="$BASE/static/bootstrap-legacy.json?t=$(date +%s)" ;;
        4.*) m="$BASE/static/bootstrap-k49.json?t=$(date +%s)" ;;
        *)   m="$BASE/api/bootstrap" ;;
    esac
    j=$(curl_do -fsSL --max-time 12 "$m" 2>/dev/null) || return 1
    LATEST_VER=$(printf '%s' "$j" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p')
    LATEST_PATCH_URL=$(printf '%s' "$j" | sed -n 's/.*"patch_url": *"\([^"]*\)".*/\1/p')
    LATEST_PATCH_SHA=$(printf '%s' "$j" | sed -n 's/.*"patch_sha256": *"\([^"]*\)".*/\1/p')
    LATEST_PATCH_SIZE=$(printf '%s' "$j" | sed -n 's/.*"patch_size": *\([0-9]*\).*/\1/p')
    LATEST_PATCH_FROM=$(printf '%s' "$j" | sed -n 's/.*"patch_from": *"\([^"]*\)".*/\1/p')
    printf '%s' "$LATEST_VER"
}
# 上一次安装在“替换文件”阶段被打断（断电、死机、被杀）时，/mnt/base-us/veradroid-install.incomplete 还在：
# 程序目录是半新的，rootfs 可能只解压了一半。以前这种状态没人管，点“启动”就是起不来。
# 能回退就回退到安装前的那一版（host.bak / rootfs.bak 还在）；回退不了（loop 机型旧系统已删）就把版本号清掉，让接下来走完整重装。
INCOMPLETE=/mnt/base-us/veradroid-install.incomplete
install_recover() {
    [ -f "$INCOMPLETE" ] || return 0
    st=$(cat "$INCOMPLETE" 2>/dev/null); [ -n "$st" ] || { rm -f "$INCOMPLETE"; return 0; }
    if [ -d "$SYS/host.bak.$st" ]; then
        [ -e "$VD" ] && mv "$VD" "$SYS/host.failed.$st"
        mv "$SYS/host.bak.$st" "$VD"
        if [ -d "$SYS/rootfs.bak.$st" ]; then
            [ -e "$SYS/rootfs" ] && mv "$SYS/rootfs" "$SYS/rootfs.failed.$st"
            mv "$SYS/rootfs.bak.$st" "$SYS/rootfs"
            echo "[$(date '+%F %T')] interrupted install $st: rolled back to the previous version" >> /mnt/base-us/veradroid-install-detail.log
        else
            rm -f "$VD/version" "$SYS/version"
            echo "[$(date '+%F %T')] interrupted install $st: program dir restored, system image incomplete -> needs reinstall" >> /mnt/base-us/veradroid-install-detail.log
        fi
    else
        rm -f "$VD/version" "$SYS/version" 2>/dev/null
        echo "[$(date '+%F %T')] interrupted install $st: nothing to roll back to -> needs reinstall" >> /mnt/base-us/veradroid-install-detail.log
    fi
    rm -f "$INCOMPLETE"
}
install_recover
cur_ver=
[ -f "$VERSION_FILE" ] && cur_ver=$(cat "$VERSION_FILE" 2>/dev/null || true)
[ -n "$cur_ver" ] || { [ -f "$VD/version" ] && cur_ver=$(cat "$VD/version" 2>/dev/null || true); }
if [ "${VD_FACTORY:-0}" != "1" ]; then
    if install_complete; then
        # Do NOT run latest_version in $(...): command substitution is a
        # subshell, so LATEST_PATCH_* would be lost and apply_patch() would
        # always see an empty patch URL.
        latest_version >/dev/null 2>&1 || true
        latest_ver=$LATEST_VER
        if [ -n "$cur_ver" ] && [ -n "$latest_ver" ]; then
            c=$(vercmp "$cur_ver" "$latest_ver")
            if [ "$c" = "0" ]; then
                show "已安装 VeraDroid $cur_ver，完整性检查通过，无需重装"
                show "直接启动…"
                remove_installer_later
                [ "${VD_NO_START:-0}" = 1 ] || setsid sh "$VD/boot/veradroid.sh" home </dev/null >/dev/null 2>&1 || true
                exit 0
            elif [ "$c" -gt 0 ] 2>/dev/null; then
                show "本机 $cur_ver 不低于服务器 $latest_ver，跳过重装"
                remove_installer_later
                [ "${VD_NO_START:-0}" = 1 ] || setsid sh "$VD/boot/veradroid.sh" home </dev/null >/dev/null 2>&1 || true
                exit 0
            else
                show "检测到 VeraDroid $cur_ver，服务器最新 $latest_ver，开始升级…"
                if apply_patch; then remove_installer_later; exit 0; fi
                show "增量补丁不可用/失败，回退整包"
            fi
        elif [ -z "$latest_ver" ]; then
            show "已有完整安装 VeraDroid ${cur_ver:-unknown}，但暂时无法查询服务器；保留现有安装"
            remove_installer_later
            [ "${VD_NO_START:-0}" = 1 ] || setsid sh "$VD/boot/veradroid.sh" home </dev/null >/dev/null 2>&1 || true
            exit 0
        else
            show "已有安装但版本未知，执行完整重装以确认版本"
        fi
    else
        show "检测到已有安装但不完整，开始修复安装…"
    fi
else
    show "VD_FACTORY=1：强制完整安装"
fi
# Consolidate old install metadata and backups under system/veradroid.
mkdir -p "$SYS/tmp" 2>/dev/null || true
for f in veradroid-device-id veradroid-model veradroid-version veradroid-fullupdate.log veradroid-fullupdate.rc; do
    if [ -e "/mnt/base-us/$f" ]; then
        mv "/mnt/base-us/$f" "$SYS/${f#veradroid-}" 2>/dev/null || true
    fi
done
for d in /mnt/base-us/veradroid.bak.*; do
    [ -d "$d" ] || continue
    mv "$d" "$SYS/$(basename "$d")" 2>/dev/null || true
done
offline=0
vd_phase download
if [ -n "${VD_BUNDLE:-}" ] && [ -f "$VD_BUNDLE" ]; then
    offline=1
    ver=${VD_VERSION:-0.21}
    mkdir -p "$TMP"
    size=$(wc -c < "$VD_BUNDLE" | tr -d ' ')
    space_check_before_download "${size:-0}"
    show "使用离线整包 VeraDroid $ver…"
    cp "$VD_BUNDLE" "$TMP/bundle.tar.gz" || die "无法读取离线安装包"
    progress_line 100 "离线包"
    sha=
else
    show "查询最新 VeraDroid 安装包…"
    # 4.9 内核机型（PW5/KT5/KT6）要用 32 位 binder 的 rootfs，不能用 PW6（5.15）的包。
    case "$(uname -r)" in
        3.*|4.1.*) meta="$BASE/static/bootstrap-legacy.json?t=$(date +%s)" ;;   # 3.0 / 4.1 内核：Cortex-A9 版 32 位系统 + binder 模块
        4.*) meta="$BASE/static/bootstrap-k49.json?t=$(date +%s)" ;;   # 静态文件，带参数绕过 CDN 缓存
        *) meta="$BASE/api/bootstrap" ;;
    esac
    json=$(curl_do -fsSL --connect-timeout 20 --max-time 30 "$meta") || die "无法连接更新服务器"
    url=$(printf '%s' "$json" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')
    sha=$(printf '%s' "$json" | sed -n 's/.*"sha256":"\([^"]*\)".*/\1/p')
    ver=$(printf '%s' "$json" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    size=$(printf '%s' "$json" | sed -n 's/.*"size":\([0-9]*\).*/\1/p')
    [ -n "$url" ] && [ -n "$sha" ] || die "服务器没有可用的安装包"

    space_check_before_download "${size:-0}"
    mkdir -p "$TMP"
    show "正在下载 VeraDroid $ver（约 130 MB）…"
    progress_line 0 "下载中"
    # Resume partial downloads and abort only on a real stall.  This makes a
    # flaky/blocked CDN retry from the same byte instead of restarting 130 MB.
    curl_do -fL --retry 8 $RETRY_ALL --retry-delay 3 --connect-timeout 20 --max-time 1200 --speed-limit 1024 --speed-time 30 -C - -o "$TMP/bundle.tar.gz" "$url" &
    cpid=$!
    while kill -0 "$cpid" 2>/dev/null; do
        sz=0
        [ -f "$TMP/bundle.tar.gz" ] && sz=$(wc -c < "$TMP/bundle.tar.gz" | tr -d ' ')
        if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
            pct=$((sz * 100 / size))
            [ "$pct" -gt 100 ] && pct=100
            progress_line "$pct" "下载中"
        else
            show "下载中 ${sz} / ${size:-?} bytes"
        fi
        sleep 5
    done
    wait "$cpid" || die "安装包下载失败"
    if [ -n "$size" ] && [ "$size" -gt 0 ] 2>/dev/null; then
        got=$(wc -c < "$TMP/bundle.tar.gz" | tr -d ' ')
        [ "$got" = "$size" ] || die "下载不完整（${got}/${size} bytes）"
    fi
fi
if [ "$offline" = 1 ]; then progress_line 100 "安装包就绪"; else progress_line 100 "下载完成"; fi
if [ -n "$sha" ]; then
    show "正在校验 SHA-256…"
    verify_sha "$TMP/bundle.tar.gz" "$sha" || die "SHA-256 校验失败"
fi
show "正在解压安装包…"
progress_line 100 "解压"
syncer_on
$LOWPRI tar -xzf "$TMP/bundle.tar.gz" -C "$TMP" || { syncer_off; die "解压安装包失败"; }
syncer_off
[ -d "$TMP/veradroid-pw6" ] || die "安装包结构不对"
# 包和内核要对得上：4.9 内核（PW5 / KT5 / KT6）的 binder 是 32 位协议，用 PW6 的系统所有原生服务开机即崩
# （用户诊断 092A03 / 001122：Binder driver protocol does not match，Android 永远起不来）。在线安装按内核选包；
# 离线包是用户自己挑的，这里拦一下（k49 包才带 bin/vdlmk）。
# 只有 legacy 包带 kmod/（给 3.0 / 4.1 内核编的 binder 模块）。新机型（4.9 / 5.x：PW5 / PW6 / Scribe……）装上它会是 32 位老系统，按内核拦。
case "$(uname -r)" in
    3.*|4.1.*) [ -d "$TMP/veradroid-pw6/kmod" ] || die "这个安装包不是老机型用的。这台 Kindle（内核 $(uname -r | cut -d. -f1-2)）请用 VeraDroid-Offline-Legacy.zip / This package is not for older Kindles: use VeraDroid-Offline-Legacy.zip on this Kindle" ;;
    *) die "这个安装包是老机型（PW2 / PW3 / Voyage / PW4 / Oasis）用的，这台 Kindle（内核 $(uname -r | cut -d. -f1-2)）不能装，本机未改动。PW6 / Colorsoft 请用 VeraDroid-Offline.zip，PW5 / KT5 / KT6 / Scribe 请用 VeraDroid-Offline-Experimental.zip / This package is for older Kindles (Legacy) and cannot be installed here; nothing was changed. Use VeraDroid-Offline.zip (PW6 / Colorsoft) or VeraDroid-Offline-Experimental.zip (PW5 / KT5 / KT6 / Scribe)" ;;
esac
case "$(uname -r)" in
    3.*|4.1.*) ;;     # legacy 包（3.0 / 4.1 内核）：下面按内核核对模块
    4.*) [ -e "$TMP/veradroid-pw6/bin/vdlmk" ] || die "这个离线包是 PW6 用的。这台 Kindle 请用“其他机型（Experimental）”安装包" ;;
    5.*) [ -e "$TMP/veradroid-pw6/bin/vdlmk" ] && die "这个离线包是给 PW5 / KT5 / KT6 用的。这台 Kindle 请用 VeraDroid 安装包" ;;
esac
# 4.1 内核：binder 模块是按每个固件的内核单独编、单独核对过的（kmod/<uname -r>/<编号>/uname-v）。
# 包里没有这台 Kindle 内核的那一份就不装：装上也开不了机，而 Kindle 界面会被停掉一次。
if [ "$MODEL" = imx41 ]; then
    kv=$(uname -v); kfound=
    for f in "$TMP"/veradroid-pw6/kmod/"$(uname -r)"/*/uname-v; do
        [ -f "$f" ] && [ "$(cat "$f")" = "$kv" ] && kfound=$f
    done
    [ -n "$kfound" ] || die "这台 Kindle 的内核（$(uname -r) $kv）还没有对应的 binder 模块，暂时不能安装"
    vlog "imx41: kernel modules $(dirname "$kfound")"
fi

# Stop the running Android first, so rootfs/host files are not in use.
install_wait_idle
if android_up; then
    install_stop_android
    sleep 1
    if [ "$LOOP" = 1 ]; then
        mkdir -p "$SYS"
        # stop.sh 会卸载系统盘；挂不回去就停下，否则会把文件写进（可能加密的）裸目录
        grep -q " $SYS " /proc/mounts || loop_mount "$SYSTEM_IMG" "$SYS" || die "无法重新挂载 ext4 系统盘"
    fi
fi

mkdir -p "$SYS"
# Migrate a pre-existing device id before moving $VD. Older installers stored
# it under $VD or under data/media; do not discard it on upgrade.
if [ ! -s "$STABLE" ]; then
    for f in "$VD/device-id" "$SYS/data/media/0/.veradroid/device-id"; do
        if [ -s "$f" ]; then cp "$f" "$STABLE"; break; fi
    done
fi
BAK="$SYS/host.bak.$stamp"
# ---- 安装前备份（2026-11-10 改）----
# 旧版每次都新建一份 documents+koreader+extensions+thumbnails 的 tgz、从来不删，还每次覆盖唯一的那份
# veradroid-documents-backup.tgz，错误全部吞掉 —— 一天几十次自动更新就能把用户存储写满。现在：
#  - 先估空间，不够就跳过备份（安装本身不删除任何用户文件），写进 veradroid-install-detail.log；
#  - 写到 .partial，成功了才改名；只保留最新一份。旧备份只有在“里面的每个文件现在都还在”时才删除，
#    否则留着（它可能是用户丢书之前唯一的一份）；
#  - veradroid-documents-backup.tgz 不再写入（user backup 已经包含 documents），已有的那份原样保留。
USER_SAFE=
if [ -d /mnt/us ]; then
    set --
    for d in documents koreader extensions system/thumbnails; do [ -e "/mnt/us/$d" ] && set -- "$@" "$d"; done
    if [ $# -gt 0 ]; then
        need=$(cd /mnt/us && du -sk "$@" 2>/dev/null | awk '{s += $1} END {print s + 0}')
        freek=$(df -k /mnt/base-us | awk 'NR==2{print $4}')
        if [ $(( need + 512000 )) -gt "${freek:-0}" ]; then
            show "空间不够做安装前备份（需要约 $((need / 1024)) MB），跳过备份；安装不会删除任何书或设置"
            vlog "user backup skipped: need ${need}K + 500M, free ${freek}K"
        else
            part=/mnt/base-us/veradroid-user-backup.partial
            rm -f "$part"
            # 真机 PW4（第一份真机报告）：书库 260 MB 时这一步要好几分钟，以前屏幕上一直停在“解压 100%”，用户以为卡住又点了一次。
            # 现在先说在做什么，每 15 秒按已经写出的大小画一次进度（书多半已经是压缩格式，备份大小接近原大小）
            show "Backing up books ($((need / 1024)) MB), do NOT restart the Kindle / 正在备份书和设置（约 $((need / 1024)) MB），请勿重启 Kindle"
            ( while sleep 15; do [ -f "$part" ] || break; bk=$(( $(wc -c < "$part" 2>/dev/null || echo 0) / 1024 ))
                  bp=$(( bk * 100 / (need + 1) )); [ "$bp" -gt 99 ] && bp=99; progress_line "$bp" "Backup / 备份 $((bk / 1024)) MB"; done ) </dev/null &
            BKW=$!
            vlog "user backup: ${need}K to back up"
            if tar -czf "$part" -C /mnt/us "$@" 2>>/mnt/base-us/veradroid-install-detail.log; then
                kill "$BKW" 2>/dev/null || true
                USER_SAFE=/mnt/base-us/veradroid-user-backup-$stamp.tgz
                mv "$part" "$USER_SAFE"
                vlog "user backup ok: $USER_SAFE ($(wc -c < "$USER_SAFE") bytes)"
                # BH081-6：以前“旧备份里有设备上已经没有的文件就永远保留”——用户每两次更新之间删过一本读完的书，
                # 就多留一整份备份（documents+koreader 全量），几次自动更新就把用户存储吃满。
                # 现在：最新这份 + 最多再留一份“含已删除文件”的旧备份（最近的那份），更早的删掉。
                kept_old=
                for old in $(ls -t /mnt/base-us/veradroid-user-backup-*.tgz 2>/dev/null); do
                    [ "$old" = "$USER_SAFE" ] && continue
                    # 只管安装器自己按时间戳起名的备份（veradroid-user-backup-YYYYMMDD-HHMMSS.tgz）；
                    # 用户自己改过名、拷过来的（如 …-KEEP-….tgz）一律不动（真机实测：KEEP 备份曾被当成旧备份删掉）
                    case "${old##*/}" in veradroid-user-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].tgz) ;; *) continue ;; esac
                    if [ -n "$kept_old" ]; then rm -f "$old"; vlog "pruned $old (already keeping $kept_old as the one older backup)"; continue; fi
                    tar -tzf "$old" >/dev/null 2>&1 || { vlog "keep $old (cannot read it)"; continue; }
                    miss=$(tar -tzf "$old" 2>/dev/null | while IFS= read -r f; do
                        case "$f" in (*/|*.partial|*.tmp|system/thumbnails/*|./system/thumbnails/*) continue ;; esac   # 缩略图是缓存，会自己重建
                        is_installer_path "$f" && continue
                        p=${f#./}; [ -e "/mnt/us/$p" ] || [ -L "/mnt/us/$p" ] || { echo "$p"; break; }
                    done)
                    if [ -z "$miss" ]; then rm -f "$old"; vlog "pruned $old (everything in it is still on the device)"
                    else kept_old=$old; vlog "keep $old: has files no longer on the device (e.g. $miss)"; fi
                done
            else
                kill "$BKW" 2>/dev/null || true
                rm -f "$part"
                show "安装前备份失败（见 veradroid-install-detail.log），继续安装；安装不会删除任何书或设置"
                vlog "user backup FAILED"
            fi
        fi
    fi
fi
# 安装前的 Kindle 书库清单（2026-11-13 事故后加）：新系统第一次开机完成后 after_boot（boot/lib/afterboot.sh 的 boot_data_check）
# 逐个核对，少了就大声记日志并从上面那份安装前备份补回；核对完改名 .checked。安装器自己启动 Android 时也在这里等它核对。
if [ "$TESTED" = emulator-only ] && [ -z "$USER_SAFE" ] && [ -d /mnt/base-us/documents ]; then
    # 整份备份放不下（或失败了）：只备份 20 MB 以下的书库文件。这一份必须成功，否则什么都不改、停止安装
    bl=$TMP/emu-backup.list
    ( cd /mnt/base-us && find documents -type f -size -20480k 2>/dev/null ) | while IFS= read -r f; do is_installer_path "$f" || printf '%s\n' "$f"; done > "$bl"
    freek=$(df -k /mnt/base-us | awk 'NR==2{print $4}')
    [ $(( EMU_BAKK + 102400 )) -le "${freek:-0}" ] || die "空间不够做书库备份（需要约 $(( EMU_BAKK / 1024 + 100 )) MB）。什么都没有改动；请先把一些书拷到电脑上再装"
    part=/mnt/base-us/veradroid-user-backup.partial; rm -f "$part"
    show "正在备份书库里的小文件…"
    if [ -s "$bl" ]; then tar -czf "$part" -C /mnt/base-us -T "$bl" 2>>/mnt/base-us/veradroid-install-detail.log || { rm -f "$part"; die "书库备份失败。什么都没有改动"; }
    else tar -czf "$part" -C /mnt/base-us documents 2>/dev/null || { rm -f "$part"; die "书库备份失败。什么都没有改动"; }; fi
    USER_SAFE=/mnt/base-us/veradroid-user-backup-$stamp.tgz; mv "$part" "$USER_SAFE"
    vlog "emulator-only: small-file documents backup $USER_SAFE ($(wc -l < "$bl" | tr -d ' ') files, $(wc -c < "$USER_SAFE") bytes)"
fi
DOCS_MANIFEST=/mnt/base-us/veradroid-docs-manifest
if [ -d /mnt/base-us/documents ]; then
    ( cd /mnt/base-us && find documents -type f 2>/dev/null ) | while IFS= read -r f; do is_installer_path "$f" || offline_readme_doc "$f" || printf '%s\n' "$f"; done \
        | grep -v -e '\.partial$' -e '\.tmp$' -e '^documents/veradroid-.*\.tar\.gz' | sort > "$DOCS_MANIFEST.tmp" 2>/dev/null \
        && mv -f "$DOCS_MANIFEST.tmp" "$DOCS_MANIFEST" && vlog "documents manifest: $(wc -l < "$DOCS_MANIFEST" | tr -d ' ') files"
fi
if [ -f /var/local/cc.db ] && cp -a /var/local/cc.db /mnt/base-us/veradroid-cc.db.$stamp 2>/dev/null; then
    for old in $(ls -t /mnt/base-us/veradroid-cc.db.* 2>/dev/null | tail -n +2); do rm -f "$old"; done
fi
# ---- 空间预检：在动任何东西之前（旧系统要留作回退）----
rootfs_gz=$(wc -c < "$TMP/veradroid-pw6/rootfs.tar.gz" 2>/dev/null | tr -d ' ')
need_mb=$(( ${rootfs_gz:-150000000} * 3 / 1048576 + 200 ))
# loop 镜像：旧 rootfs 先删再解新的，不会同时有两份。解开约 2.1 倍（0.8.6 的 129 MB -> 267 MB），按 2.5 倍 + 128 MB 算；
# 以前按 3 倍 + 200 MB，768 MB 镜像装了几个应用的 PW2 就升级不了
[ "$LOOP" = 1 ] && need_mb=$(( ${rootfs_gz:-150000000} / 1048576 * 5 / 2 + 128 ))
# VD_IMGMB（小存储测试）：系统是预编译好的（odex / boot.oat 都在镜像里），解开后约是压缩包的 2 倍，余量只留 30 MB
case "${VD_IMGMB:-}" in ''|*[!0-9]*) ;; *) need_mb=$(( ${rootfs_gz:-150000000} * 2 / 1048576 + 30 )) ;; esac
if [ "$LOOP" = 1 ]; then free_mb=$(df -m "$SYS" | awk 'NR==2{print $4}')
    old_mb=$(du -sm "$SYS/rootfs" 2>/dev/null | awk '{print $1}'); free_mb=$(( free_mb + ${old_mb:-0} ))
else free_mb=$(df -m /mnt/base-us | awk 'NR==2{print $4}'); fi
vlog "space: need ${need_mb}M free ${free_mb}M (loop=$LOOP)"
[ "${free_mb:-0}" -ge "$need_mb" ] || die "空间不够：安装需要约 ${need_mb} MB，现在只有 ${free_mb} MB。什么都没有删除"
# 动任何东西（包括把程序目录挪成 host.bak）之前先查挂载：拒绝时设备要保持原样，“VeraDroid 启动”还能用
guard_rm "$SYS/rootfs"
# 只保留最近一份旧系统 / 程序目录备份（不是用户数据）。删之前查挂载。
for pat in rootfs.bak host.bak rootfs.failed host.failed; do
    for old in $(ls -dt "$SYS"/$pat.* 2>/dev/null); do
        guard_rm "$old"
        rm -rf "$old" 2>/dev/null || true
    done
done
echo "$stamp" > "$INCOMPLETE"; sync      # 从这里到写完版本号之间被打断，下次安装 / 启动会按这个标记回退
[ -d "$VD" ] && mv "$VD" "$BAK"
if [ "$LOOP" = 1 ]; then
    # loop 镜像只有 3 GB，放不下新旧两份 rootfs：旧的不是用户数据，先删
    guard_rm "$SYS/rootfs"
    rm -rf "$SYS/rootfs" 2>/dev/null || true
elif [ -d "$SYS/rootfs" ]; then
    guard_rm "$SYS/rootfs"
    if [ "${free_mb:-0}" -ge $(( need_mb + 400 )) ]; then mv "$SYS/rootfs" "$SYS/rootfs.bak.$stamp"
    else rm -rf "$SYS/rootfs" 2>/dev/null || true; vlog "old rootfs removed instead of kept (space)"; fi
fi
mkdir -p "$VD" "$SYS/rootfs"
echo "$MODEL" > "$MODEL_FILE"
echo "$MODEL" > "$VD/model" 2>/dev/null || true   # 系统盘外的一份（loop 机型停着时 auto-update 也能读到）
cp -a "$TMP/veradroid-pw6/boot" "$TMP/veradroid-pw6/bin" "$VD/"
[ -f "$TMP/veradroid-pw6/VeraDroid-Launch.sh" ] && cp "$TMP/veradroid-pw6/VeraDroid-Launch.sh" "$VD/VeraDroid-Launch.sh" && chmod 755 "$VD/VeraDroid-Launch.sh"
# 程序目录里这一份只是备份（书库入口被删时 framework.sh 的 launcher_ensure 用它补回去）。标题和书库里的正式入口分开：
# 有用户把整个 veradroid 文件夹拷进了 documents，书库里于是出现两个一模一样的“VeraDroid”（用户报告：KT6 5.17）。
if [ -f "$VD/VeraDroid-Launch.sh" ]; then
    sed 's/^# Name: VeraDroid$/# Name: VeraDroid（备用入口）/' "$VD/VeraDroid-Launch.sh" > "$VD/.vd-launch.tmp" 2>/dev/null \
        && mv "$VD/.vd-launch.tmp" "$VD/VeraDroid-Launch.sh" && chmod 755 "$VD/VeraDroid-Launch.sh"
    rm -f "$VD/.vd-launch.tmp" 2>/dev/null || true
fi
[ -d "$TMP/veradroid-pw6/fonts" ] && cp -a "$TMP/veradroid-pw6/fonts" "$VD/fonts"
# 老机型（legacy / imx41）的逐台调优文件（models/old-base.conf + models/<机型>.conf，settings.sh 读 $VD/models）。
# 以前漏拷：模拟器发布门里 $VD/models 不存在，PW2 的 density 213 / 起步堆 4m 等机型层一项都没生效（2026-11-13）。
case "$MODEL" in legacy|imx41) [ -d "$TMP/veradroid-pw6/models" ] && { rm -rf "$VD/models"; cp -a "$TMP/veradroid-pw6/models" "$VD/models"; } ;; esac
# 老内核用的外挂模块（kmod/<uname -r>/*.ko，boot/lib/kmod.sh 开机时加载）
[ -d "$TMP/veradroid-pw6/kmod" ] && cp -a "$TMP/veradroid-pw6/kmod" "$VD/kmod"
[ -d "$TMP/veradroid-pw6/screensaver" ] && cp -a "$TMP/veradroid-pw6/screensaver" "$VD/screensaver"
# Invoked via "sh" everywhere, but the launcher and KUAL also probe it.
chmod 755 "$VD/boot/veradroid.sh" 2>/dev/null || true
# Keep the debug SSH keys/authorized_keys across the upgrade.  The old host dir is
# moved to $BAK above; dropbear's -D path points into it.
# Never fatal: on the rc089 matrix (pw6-5201) the test saw the directory and cp then could not stat it, and under
# set -e that one optional copy failed the whole upgrade (rc=1, half-installed until the next start rolled it back).
if [ -d "$BAK/ssh" ]; then cp -a "$BAK/ssh" "$VD/ssh" 2>/dev/null || vlog "ssh keys not carried over from $BAK/ssh"; fi
# BH081-2：程序目录里还有用户自己放的设置 / 文件，整包安装把 $VD 挪成 $BAK 后要带回来，否则每次升级都丢：
#   autoupdate（=0 关闭自动更新）、network.conf（代理 / DNS，受限网络下没有它就更新不了）、debugboot、
#   screensaver/ 里的自定义屏保、apps/ 里还没装的 APK（afterboot 装好才删）。包里有的同名文件以包为准。
for f in autoupdate network.conf debugboot; do
    [ -f "$BAK/$f" ] && [ ! -e "$VD/$f" ] && cp -a "$BAK/$f" "$VD/$f" 2>/dev/null || true
done
for d in screensaver apps; do
    [ -d "$BAK/$d" ] || continue
    mkdir -p "$VD/$d"
    for f in "$BAK/$d"/*; do
        [ -f "$f" ] || continue
        [ -e "$VD/$d/${f##*/}" ] || [ -e "$TMP/veradroid-pw6/apks/${f##*/}" ] || cp -a "$f" "$VD/$d/" 2>/dev/null || true
    done
done
mkdir -p "$VD/apps"
cp "$TMP/veradroid-pw6/apks/"*.apk "$VD/apps/"
# Stable identity lives outside $VD because $VD is moved to .bak on every
# install. It also survives a factory reset of /data.
if [ ! -s "$STABLE" ]; then
    usid=$(tr -cd '0-9A-Fa-f' </proc/usid 2>/dev/null | cut -c1-16)
    if [ -z "$usid" ]; then
        usid=$(tr -d '-' </proc/sys/kernel/random/uuid 2>/dev/null | cut -c1-16)
    fi
    [ -n "$usid" ] && echo "$usid" > "$STABLE"
fi
if [ -s "$STABLE" ]; then
    cp "$STABLE" "$VD/device-id"
    # Android cannot see /mnt/base-us; expose the same id through /data/media,
    # which factory mode deliberately preserves.
    mkdir -p "$SYS/data/media/0/.veradroid" 2>/dev/null || true
    cp "$STABLE" "$SYS/data/media/0/.veradroid/device-id" 2>/dev/null || true
    chmod 644 "$STABLE" "$VD/device-id" "$SYS/data/media/0/.veradroid/device-id" 2>/dev/null || true
fi
show "Installing Android, do NOT restart the Kindle (1-5 min) / 正在安装 Android 系统，请勿重启 Kindle（约 1–5 分钟）"
progress_line 0 "Android system / 安装系统"
syncer_on
# 解开约是压缩包的 2.1 倍：每 15 秒按 $SYS/rootfs 已经写出的大小画进度（真机上这一步几分钟，以前一直停在“安装中 100%”）
rf_total=$(( $(wc -c < "$TMP/veradroid-pw6/rootfs.tar.gz") / 1024 * 21 / 10 ))
( while sleep 15; do rk=$(du -sk "$SYS/rootfs" 2>/dev/null | cut -f1); rp=$(( ${rk:-0} * 100 / (rf_total + 1) )); [ "$rp" -gt 99 ] && rp=99
      progress_line "$rp" "Android system / 安装系统"; done ) </dev/null &
RFW=$!
$LOWPRI tar -xzf "$TMP/veradroid-pw6/rootfs.tar.gz" -C "$SYS/rootfs" || { kill "$RFW" 2>/dev/null; syncer_off; die "解压 Android rootfs 失败（空间不足？）"; }
kill "$RFW" 2>/dev/null || true
syncer_off
[ -x "$SYS/rootfs/system/bin/sh" ] || die "Android rootfs 不完整（缺少 /system/bin/sh）"
# Patched Android runtime for 5.17-era kernels: skip unknown zygote fds
# (ashmem/binder) in FileDescriptorTable instead of aborting.
if [ -f "$TMP/veradroid-pw6/libandroid_runtime.so" ]; then
    cp "$TMP/veradroid-pw6/libandroid_runtime.so" "$SYS/rootfs/system/lib/libandroid_runtime.so" || die "写入 libandroid_runtime 失败"
    chmod 755 "$SYS/rootfs/system/lib/libandroid_runtime.so" 2>/dev/null || true
fi
# The bundle's VeraHome must replace the copy inside the rootfs. after_boot
# only skips "already a system app", so without this the UI stays on the old
# version even after a new bundle is installed.
# First boot may happen before after_boot; create the reader download dirs here
# so WeRead does not sit on "downloading" with an unwritable Android/data.
for d in Android Android/data Android/obb WeRead Download; do
    mkdir -p "$SYS/rootfs/data/media/0/$d" 2>/dev/null || true
    chmod 777 "$SYS/rootfs/data/media/0/$d" 2>/dev/null || true
done
# 0.46–0.70 的 VeraHome 是 OTA 装进 /data/app 的更新版（versionCode 47–54），会盖住包里的系统版。
# 往前发（roll-forward）要换回包里的 VeraHome：删掉更新版的 apk 目录（它的设置在 /data/media/0/.vdhome，不受影响）。
for vh in "$SYS"/data/app/com.veradroid.home-*; do
    [ -d "$vh" ] || continue
    guard_rm "$vh"; rm -rf "$vh" 2>/dev/null && vlog "removed updated VeraHome $vh"
done
# 输入法同理：系统镜像里带的是很早的 VeraIME 0.2（没有“长按 123 出符号键盘”），after_boot 看到“已安装”就跳过，
# 包里新的输入法永远装不上（更新日志写了有、用户长按 123 还是数字键盘）。安装时直接换掉系统里的那份。
if [ -f "$TMP/veradroid-pw6/apks/VeraIME.apk" ]; then
    for vi in "$SYS"/data/app/com.veradroid.ime-*; do
        [ -d "$vi" ] || continue
        guard_rm "$vi"; rm -rf "$vi" 2>/dev/null && vlog "removed updated VeraIME $vi"
    done
    VI="$SYS/rootfs/system/app/VeraIME"
    mkdir -p "$VI"
    cp "$TMP/veradroid-pw6/apks/VeraIME.apk" "$VI/VeraIME.apk" || die "写入 VeraIME 失败"
    chmod 644 "$VI/VeraIME.apk" 2>/dev/null || true
    rm -rf "$VI/oat" 2>/dev/null || true
fi
if [ -f "$TMP/veradroid-pw6/apks/VeraHome.apk" ]; then
    VH="$SYS/rootfs/system/priv-app/VeraHome"
    mkdir -p "$VH"
    cp "$TMP/veradroid-pw6/apks/VeraHome.apk" "$VH/VeraHome.apk" || die "写入 VeraHome 失败"
    chmod 644 "$VH/VeraHome.apk" 2>/dev/null || true
    rm -rf "$VH/oat" 2>/dev/null || true
fi
# Keep existing data; a fresh machine gets the directories init needs.
# Factory reset mode: keep /data/media (Books, fonts, token), discard all Android
# app/system state. This is the reliable path for a machine that has been through
# several failed installs.
if [ "${VD_FACTORY:-0}" = "1" ]; then
    echo "全新安装：清理 Android 数据，保留 media..."
    for p in data/data data/system data/app data/dalvik-cache data/resource-cache              data/misc data/property data/user data/user_de data/local/tmp; do
        guard_rm "$SYS/$p"
        rm -rf "$SYS/$p" 2>/dev/null || true
    done
fi
mkdir -p "$SYS/data/data" "$SYS/data/system" "$SYS/data/local/tmp" "$SYS/data/media/0"
# Android's system_server must own /data, /data/system and /data/data.
# Fresh installs previously left them root:root, so Settings could not write its user state.
chown 1000:1000 "$SYS/data" "$SYS/data/system" "$SYS/data/data" 2>/dev/null || true
chmod 0771 "$SYS/data" "$SYS/data/data" 2>/dev/null || true
chmod 0770 "$SYS/data/system" 2>/dev/null || true
chown 2000:2000 "$SYS/data/local/tmp" 2>/dev/null || true
chmod 0771 "$SYS/data/local/tmp" 2>/dev/null || true
chown 1023:1023 "$SYS/data/media" 2>/dev/null || true
chmod 0770 "$SYS/data/media" 2>/dev/null || true
chmod 0777 "$SYS/data/media/0" 2>/dev/null || true
# A stale MediaProvider database from a previous Android image can crash on first boot.
# This only clears the media index; books and personal files are untouched.
rm -rf "$SYS/data/data/com.android.providers.media/databases" 2>/dev/null || true
rm -rf "$SYS/data/data/com.android.providers.media/files" 2>/dev/null || true
# System apps can also have stale settings databases after switching Android images.
# These are settings only; books, apps and account data are not touched.
for pkg in com.android.settings com.android.systemui com.android.providers.media; do
    rm -rf "$SYS/data/data/$pkg" 2>/dev/null || true
done
# SettingsProvider owns hide_error_dialogs and other global switches. Keep it
# across normal upgrades; deleting it makes the media crash dialog return.

# Settings is intentionally excluded from the product (packages/apps/Android.mk).
# An old Settings.apk left in the rootfs provides FallbackHome/CryptKeeper and steals
# the HOME intent on a fresh user. Remove it completely; SettingsProvider stays.
rm -rf "$SYS/rootfs/system/priv-app/Settings" 2>/dev/null || true
rm -rf "$SYS/rootfs/system/app/Settings" 2>/dev/null || true
# A stale dalvik-cache can contain a dex for a different Settings.apk. ART then
# ignores the matching system odex and ClassNotFound for CryptKeeper. Clearing it
# only forces recompilation; apps and books are untouched.
rm -rf "$SYS/data/dalvik-cache" 2>/dev/null || true
rm -rf "$SYS/data/resource-cache" 2>/dev/null || true
# Stale user/settings state from a previous Android image can crash Settings even
# after app data is cleared. Books, /data/media, and the device token are preserved.
# Never delete a valid user 0: that makes FallbackHome launch Settings.CryptKeeper,
# whose class is not present in this stripped Settings APK. If the user directory is
# absent, let system_server recreate it from scratch instead of keeping half state.
if [ ! -d "$SYS/data/system/users/0" ]; then
    rm -rf "$SYS/data/system/users" 2>/dev/null || true
fi
# android_id (Settings.Secure.ANDROID_ID) of a seeded user 0. The seed in the bundle (user0/settings_secure.xml) carries
# one fixed value, so every install had the same id: a privacy leak, and apps that bind accounts / licences to it
# treated all VeraDroid Kindles as one device. A user 0 seeded here gets a fresh random 64-bit id, once: this only runs
# when users/0.xml does not exist yet (new install, uninstall + install, factory reset), so an upgrade keeps the id the
# installed system already has (changing it would sign users out of apps). If no random source works the line is
# dropped and SettingsProvider generates one itself on first boot (Android 7.1 does that for a missing android_id).
# BEGIN vd_seed_android_id
vd_seed_android_id() {   # $1 = settings_secure.xml of the freshly seeded user 0
    [ -f "$1" ] || return 0
    _aid=$(od -An -tx1 -N8 /dev/urandom 2>/dev/null | tr -d ' \n')
    [ ${#_aid} = 16 ] || _aid=$(hexdump -n 8 -e '8/1 "%02x"' /dev/urandom 2>/dev/null)
    case "$_aid" in ????????????????) ;; *) _aid= ;; esac
    case "$_aid" in *[!0-9a-f]*|0000000000000000) _aid= ;; esac
    if [ -n "$_aid" ]; then
        sed "s/\(name=\"android_id\" value=\"\)[0-9a-fA-F]*\"/\1$_aid\"/" "$1" > "$1.aid"
    else
        sed '/name="android_id"/d' "$1" > "$1.aid"
    fi
    [ -s "$1.aid" ] && cat "$1.aid" > "$1"   # cat, not mv: keeps the seed file's mode
    rm -f "$1.aid"
}
# END vd_seed_android_id
if [ "${VD_FACTORY:-0}" != "1" ] && [ ! -f "$SYS/data/system/users/0.xml" ]; then
    mkdir -p "$SYS/data/system/users"
    cp -a "$TMP/veradroid-pw6/user0.xml" "$SYS/data/system/users/0.xml" 2>/dev/null || true
    cp -a "$TMP/veradroid-pw6/user0/." "$SYS/data/system/users/0/" 2>/dev/null || true
    vd_seed_android_id "$SYS/data/system/users/0/settings_secure.xml"
    chown -R 1000:1000 "$SYS/data/system/users" 2>/dev/null || true
fi
# Only a factory install may discard PackageManager state. A normal KPM/OTA
# upgrade must keep installed apps and their package records.
if [ "${VD_FACTORY:-0}" = "1" ]; then
    rm -f "$SYS/data/system/packages.xml" "$SYS/data/system/packages.list" 2>/dev/null || true
fi

[ -n "$ver" ] && echo "$ver" > "$VERSION_FILE"
[ -n "$ver" ] && echo "$ver" > "$VD/version"
# 机型的验证程度（宿主的自检 / 兜底 / 自动更新看它，boot/lib/tester.sh）和这次装的内核模块编号（auto-update 只在模块没变时自动更新）
if [ "$TESTED" = emulator-only ]; then
    echo emulator-only > "$VD/tested"
    [ -f "$TMP/veradroid-pw6/kmod.id" ] && cp "$TMP/veradroid-pw6/kmod.id" "$VD/kmod.id" || true
    ok_id=$(cat "$BAK/kmod.id" 2>/dev/null || true); nk_id=$(cat "$VD/kmod.id" 2>/dev/null || true)
    [ -n "$ok_id" ] && [ "$ok_id" != "$nk_id" ] && { show "注意：这次更新换了内核模块（${ok_id} -> ${nk_id:-?}）"; vlog "emulator-only: kernel modules changed $ok_id -> $nk_id"; }
    [ -d "$BAK/test" ] && [ ! -e "$VD/test" ] && cp -a "$BAK/test" "$VD/test" 2>/dev/null || true
    [ -f "$BAK/settings.test" ] && [ ! -e "$VD/settings.test" ] && cp -a "$BAK/settings.test" "$VD/settings.test" 2>/dev/null || true
else
    rm -f "$VD/tested" || true
fi
sync; rm -f "$INCOMPLETE"
vd_phase done      # 文件都换好了：从这里起 veradroid.sh（包括下面自己启动的那次）不用再等
# Native Kindle library entry: a .sh with # Name/# Icon is indexed as a book.
DOCS=/mnt/base-us/documents
[ -d "$DOCS" ] || DOCS=/mnt/us/documents
# Restore only missing documents from the pre-install backup.
# BH081-4：旧版留下的 veradroid-documents-backup.tgz 只恢复一次。以前每次安装 / 自动更新都从这份旧备份
# “补回缺失的书”，用户后来自己删掉的书每次更新都会复活。恢复过一次就改名保留（不删除，用户还能手动找回）。
if [ -f /mnt/base-us/veradroid-documents-backup.tgz ]; then
    restore_missing /mnt/base-us/veradroid-documents-backup.tgz "$DOCS"
    mv /mnt/base-us/veradroid-documents-backup.tgz /mnt/base-us/veradroid-documents-backup.restored-$stamp.tgz 2>/dev/null || true
    vlog "legacy documents backup restored once, renamed to veradroid-documents-backup.restored-$stamp.tgz"
fi
restore_missing "$USER_SAFE" /mnt/us
if [ -f /mnt/base-us/veradroid-cc.db.$stamp ] && [ ! -f /var/local/cc.db ]; then
    cp -a /mnt/base-us/veradroid-cc.db.$stamp /var/local/cc.db 2>/dev/null || true
fi
if [ -f "$TMP/veradroid-pw6/VeraDroid-Launch.sh" ]; then
    # Kindle's home library may use either mount; put the launcher in both so
    # returning to Kindle always finds a "VeraDroid 启动" entry.
    for D in "$DOCS" /mnt/us/documents /mnt/base-us/documents; do
        [ -d "$D" ] || continue
        cp "$TMP/veradroid-pw6/VeraDroid-Launch.sh" "$D/VeraDroid 启动.sh" 2>/dev/null || true
        chmod 755 "$D/VeraDroid 启动.sh" 2>/dev/null || true
        # force a fresh library scan without touching user books
        touch "$D/VeraDroid 启动.sh" 2>/dev/null || true
    done
    sync 2>/dev/null || true
    # 旧包里的启动入口没有忽略 SIGPIPE：书库启动器的 fbink 管道断开时会一点就退出。在文件头注释后补一行。
    if ! grep -q "trap '' PIPE" "$DOCS/VeraDroid 启动.sh" 2>/dev/null; then
        awk 'f==0 && !/^#/ {print "trap '\'''\'' PIPE"; f=1} {print}' "$DOCS/VeraDroid 启动.sh" > "$DOCS/.vd-launch.tmp" 2>/dev/null \
            && mv "$DOCS/.vd-launch.tmp" "$DOCS/VeraDroid 启动.sh"
    fi
    chmod 755 "$DOCS/VeraDroid 启动.sh" 2>/dev/null || true
    # 马上就要启动 Android（会停掉 Kindle 的索引服务 scanner）：趁它还在，点名让它现在就索引这个入口，
    # 否则入口文件在、书库里却看不到（“安装后书库入口不见”）。
    lipc-set-prop com.lab126.scanner reScanFile "/mnt/us/documents/VeraDroid 启动.sh" 2>/dev/null || true
    sleep 2
fi
# emulator-only 机型：书库里再放两个入口——“VeraDroid 上传测试结果”（先在屏幕上说明，再点一次才上传）和“VeraDroid 卸载”（一点就卸，不留痕迹）
if [ "$TESTED" = emulator-only ] && [ -d "$TMP/veradroid-pw6/entries" ]; then
    for e in "$TMP/veradroid-pw6/entries"/*.sh; do
        [ -f "$e" ] || continue
        # 内容没变就不重写：书库索引（sh_integration）把每次改动当成“删条目 + 新 UUID 重建”，反复覆盖会让条目重复 / 消失。
        # 入口里也不用 # UseHooks（见 docs/prior-art.md）
        cmp -s "$e" "$DOCS/${e##*/}" 2>/dev/null && continue
        cp "$e" "$DOCS/${e##*/}" 2>/dev/null && chmod 755 "$DOCS/${e##*/}" 2>/dev/null || true
        lipc-set-prop com.lab126.scanner reScanFile "/mnt/us/documents/${e##*/}" 2>/dev/null || true
    done
fi
# KUAL is an alternative for jailbreaks that do not index .sh books.
if [ -d "$TMP/veradroid-pw6/kual" ]; then
    mkdir -p /mnt/us/extensions/VeraDroid 2>/dev/null || true
    cp -a "$TMP/veradroid-pw6/kual/." /mnt/us/extensions/VeraDroid/ 2>/dev/null || true
    chmod 755 /mnt/us/extensions/VeraDroid/start.sh /mnt/us/extensions/VeraDroid/install.sh 2>/dev/null || true
fi
# BH081-1：自动更新（VD_NO_START=1）时用户正在用 Kindle（Android 冻结或没开）：装完不要把 Android 弹到前台。
if [ "${VD_NO_START:-0}" = 1 ]; then
    show "更新完成：下次点“VeraDroid 启动”时生效"
else
    show "正在启动 VeraDroid…"
    progress_line 100 "启动"
    setsid sh "$VD/boot/veradroid.sh" home </dev/null >/dev/null 2>&1
fi
# A 3G loop image cannot hold every historical backup. Keep only the newest
# host/rootfs backup on loop-backed installs; clean up after the new boot starts.
if [ "$LOOP" = 1 ]; then
    for pat in rootfs.bak.* host.bak.*; do
        for old in $(ls -dt "$SYS"/$pat 2>/dev/null | tail -n +2); do
            # Android 已经启动：下面有挂载就跳过（不 die，安装已经完成），绝不穿过挂载删
            if mounts_under "$old" 1; then vlog "skip rm -rf $old: mounts under it"; continue; fi
            rm -rf "$old" 2>/dev/null || true
        done
    done
fi
# The native library should show one VeraDroid launcher, not installer + launcher.
# Delete only the known installer names, never "VeraDroid 启动.sh".
remove_installer_later
remove_offline_package
echo
# 只列真的存在的备份：全新安装（或空间不够、旧系统被删掉）时没有备份，以前也照样打印两个不存在的路径
bak_list=; for b in "$BAK" "$SYS/rootfs.bak.$stamp"; do [ -e "$b" ] && bak_list="$bak_list $b"; done
if [ -n "$bak_list" ]; then
    echo "完成。旧版本已备份到："
    for b in $bak_list; do echo "  $b"; done
    echo "如果启动失败，可以用 SSH 执行 stop.sh，再把备份移回来。"
else
    echo "完成。"
fi
