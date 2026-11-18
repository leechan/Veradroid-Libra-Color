# 用户存储根目录（USB 里看到的 Kindle 根目录，/mnt/us = /mnt/base-us）只留一个 veradroid/ 文件夹。
# 这一段在 bootstrap.sh、bootstrap-legacy.sh 和各机型的 boot/lib/tidy.sh 里是同一份（tests/root-tidy-test.sh 核对）。
# BEGIN vd_root_tidy
# 2026-11-18 起 VeraDroid 自己的日志、标记和备份都放在程序目录 veradroid/ 下面三个文件夹里，不再散在根目录：
#   veradroid/logs    install.log、install-detail.log、uninstall.log、autoupdate.log、fsck.log、localupdate.log、boot.log、resize.log
#   veradroid/state   install.lock、install.incomplete、install.<pid>（安装器临时目录）、autoupdate.lock、update.stage、
#                     docs-manifest、confirm、launchers-restored、resize.*
#   veradroid/backup  user-backup-<时间>.tgz（安装前备份）、cc.db.<时间>、documents-backup*.tgz、media-keep/（卸载时留下的书）
# 这三个文件夹不是程序：安装器把程序目录挪成 host.bak、回退时挪回来、卸载删程序，都不带上它们（vd_prog_move / vd_is_data）。
# 留在根目录的只有系统盘镜像 veradroid-sys.img 和老机型的交换文件 veradroid-swap：以前的安装器（用户手里的旧离线包）
# 会把整个 veradroid/ 挪进系统盘镜像里，镜像和交换文件要是在 veradroid/ 里就是把镜像往它自己里面拷。
# 读的地方都先看新位置、再看根目录（老版本的安装器 / 自动更新 / 离线更新还会往根目录写），vd_root_tidy 再把根目录的搬进来。
VD_TOP=${VD_TOP:-/mnt/base-us}
VD_LOGS=$VD_TOP/veradroid/logs
VD_STATE=$VD_TOP/veradroid/state
VD_BACKUP=$VD_TOP/veradroid/backup
vd_is_data() { case "$1" in logs|state|backup) return 0 ;; esac; return 1; }
# vd_prog_move 源 目标：把源目录里除 logs / state / backup 以外的东西逐个挪进目标（需要时才建目标）
vd_prog_move() {
    [ -d "$1" ] || return 0
    for vpm_e in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ -e "$vpm_e" ] || [ -L "$vpm_e" ] || continue
        vd_is_data "${vpm_e##*/}" && continue
        mkdir -p "$2" && mv "$vpm_e" "$2/" || return 1
    done
    return 0
}
# vd_prog_rm 目录：删掉程序（logs / state / backup 留着）
vd_prog_rm() {
    [ -d "$1" ] || return 0
    for vpr_e in "$1"/* "$1"/.[!.]* "$1"/..?*; do
        [ -e "$vpr_e" ] || [ -L "$vpr_e" ] || continue
        vd_is_data "${vpr_e##*/}" && continue
        rm -rf "$vpr_e" || true
    done
    return 0
}
# vd_data_rescue 目录：旧安装器把整个程序目录（连同 logs / backup）挪成了 host.bak / host.failed，删它之前把这两个搬回来（同名的不覆盖）
vd_data_rescue() {
    for vdr_s in logs backup; do
        [ -d "$1/$vdr_s" ] || continue
        mkdir -p "$VD_TOP/veradroid/$vdr_s" 2>/dev/null || continue
        for vdr_e in "$1/$vdr_s"/* "$1/$vdr_s"/.[!.]*; do
            [ -e "$vdr_e" ] || continue
            [ -e "$VD_TOP/veradroid/$vdr_s/${vdr_e##*/}" ] || mv "$vdr_e" "$VD_TOP/veradroid/$vdr_s/" 2>/dev/null || true
        done
    done
    return 0
}
vd_pid_live() { [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
# vd_old_installer：老版本的安装器正在跑（根目录的安装锁，持有者还活着）
vd_old_installer() { vd_pid_live "$(cat "$VD_TOP/veradroid-install.lock/pid" 2>/dev/null)"; }
# vd_root_tidy：把根目录里以前的文件搬进 veradroid/。安装器每次运行、veradroid.sh 每次启动都跑，重复跑没有副作用。
# 只认我们自己按固定名字建的文件；用户改过名的（带 KEEP 的备份等）、别的文件夹（vd18-keep/ 等）一律不动。
# 老版本的进程还在用的不动：老安装器在跑时整个跳过；老自动更新拿着锁时不动它的锁和下载的安装器；老的离线更新在跑时不动暂存目录。
vd_root_tidy() {
    vrt=$VD_TOP
    [ -d "$vrt" ] || return 0
    vd_old_installer && return 0
    mkdir -p "$VD_LOGS" "$VD_STATE" "$VD_BACKUP" 2>/dev/null || return 0
    # 日志：logs/ 里已经有同名的就先并进 .old（最多留 1 MB），再把根目录的改名过来（还开着它的老进程接着写进同一个文件）
    for vrt_n in install install-detail fsck uninstall boot localupdate autoupdate resize; do
        vrt_f=$vrt/veradroid-$vrt_n.log; [ -f "$vrt_f" ] || continue
        vrt_d=$VD_LOGS/$vrt_n.log
        if [ -f "$vrt_d" ]; then
            { cat "$vrt_d.old" 2>/dev/null; cat "$vrt_d"; } | tail -c 1048576 > "$vrt_d.old.tmp" 2>/dev/null && mv -f "$vrt_d.old.tmp" "$vrt_d.old" && rm -f "$vrt_d" || true
        fi
        mv -f "$vrt_f" "$vrt_d" 2>/dev/null || true
    done
    # 标记：两边都有时留较新的那份
    for vrt_n in install.incomplete docs-manifest docs-manifest.checked launchers-restored confirm resize.state resize.pending resize.notify resize.last; do
        vrt_f=$vrt/veradroid-$vrt_n; [ -f "$vrt_f" ] || continue
        if [ -e "$VD_STATE/$vrt_n" ] && [ "$(ls -t "$vrt_f" "$VD_STATE/$vrt_n" 2>/dev/null | head -1)" != "$vrt_f" ]; then rm -f "$vrt_f"
        else mv -f "$vrt_f" "$VD_STATE/$vrt_n" 2>/dev/null || true; fi
    done
    # 锁和临时文件：持有者已经不在的删掉（安装锁的持有者上面已经确认不在了）
    rm -f "$vrt/veradroid-install.lock/pid" "$vrt/veradroid-install.lock/boot" "$vrt/veradroid-install.lock/phase" 2>/dev/null || true
    rmdir "$vrt/veradroid-install.lock" 2>/dev/null || true
    # 老版本的自动更新（更新前起的，锁在根目录）在睡觉：没有安装在进行时（两个安装锁都没人拿）把它停掉，
    # 新版的 veradroid.sh 接着起新的（否则它一直占着根目录的锁，新的那个起不来，直到 Kindle 重启）。
    # 安装器里跑到这里时自己拿着新的安装锁，不会停它的父进程。
    # set -eu 下（安装器）赋值的退出码就是 $(...) 的：锁不在时 cat 失败会让整个安装器静默退出，所以每个 $(...) 和 rm 都要 || true
    vrt_p=$(cat "$vrt/veradroid-autoupdate.lock/pid" 2>/dev/null || true)
    if vd_pid_live "$vrt_p" && ! vd_pid_live "$(cat "$VD_STATE/install.lock/pid" 2>/dev/null)"; then
        case "$( { tr '\000' ' ' < /proc/$vrt_p/cmdline; } 2>/dev/null || true)" in "sh "*"/auto-update.sh"*) kill -9 "$vrt_p" 2>/dev/null && sleep 1 ;; esac
    fi
    if ! vd_pid_live "$(cat "$vrt/veradroid-autoupdate.lock/pid" 2>/dev/null)"; then
        rm -rf "$vrt/veradroid-autoupdate.lock" "$vrt/veradroid-autoupdate-bootstrap.sh" "$vrt/veradroid-autoupdate-bootstrap.sh.part" 2>/dev/null || true
    fi
    for vrt_f in "$vrt"/veradroid-install.[0-9]*; do
        [ -d "$vrt_f" ] || continue
        case "${vrt_f##*.}" in *[!0-9]*) continue ;; esac
        vd_pid_live "${vrt_f##*.}" && [ -n "$(find "$vrt_f" -mmin -2 2>/dev/null | head -1)" ] && continue   # 不拿锁的老安装器还在往里写
        rm -rf "$vrt_f" 2>/dev/null || true
    done
    rm -f "$vrt/veradroid-user-backup.partial" 2>/dev/null || true
    if [ -d "$vrt/veradroid-update.stage" ] && [ ! -e "$VD_STATE/update.stage" ] && ! vd_pid_live "$(cat /dev/shm/veradroid/localupdate.lock/pid 2>/dev/null)"; then
        mv "$vrt/veradroid-update.stage" "$VD_STATE/update.stage" 2>/dev/null || true
    fi
    # 备份：只搬安装器按时间起名的那几种；同名的已经在 backup/ 里就不动
    for vrt_f in "$vrt"/veradroid-user-backup-*.tgz "$vrt"/veradroid-documents-backup.tgz "$vrt"/veradroid-documents-backup.restored-*.tgz "$vrt"/veradroid-cc.db.*; do
        [ -f "$vrt_f" ] || continue
        vrt_n=${vrt_f##*/}; vrt_n=${vrt_n#veradroid-}
        case "$vrt_n" in
            user-backup-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].tgz) ;;
            documents-backup.tgz|documents-backup.restored-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9].tgz) ;;
            cc.db.[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]) ;;
            *) continue ;;
        esac
        [ -e "$VD_BACKUP/$vrt_n" ] || mv "$vrt_f" "$VD_BACKUP/$vrt_n" 2>/dev/null || true
    done
    if [ -d "$vrt/veradroid-media-keep" ] && [ ! -e "$VD_BACKUP/media-keep" ]; then
        mv "$vrt/veradroid-media-keep" "$VD_BACKUP/media-keep" 2>/dev/null || true
    fi
    return 0
}
# END vd_root_tidy
