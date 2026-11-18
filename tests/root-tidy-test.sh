#!/bin/sh
# 用户存储根目录只留一个 veradroid/ 文件夹（2026-11-18）：
#  1. 脚本里不能再出现新的根目录 veradroid-* 路径。允许的只有：系统盘镜像 veradroid-sys.img、老机型交换文件 veradroid-swap、
#     注释行，以及标了 root-legacy 的行（读老版本写在根目录的文件、搬迁、卸载时清理）。
#  2. 给用户看的日志名也要是新位置（veradroid/logs/install.log），不能再说 veradroid-install.log。
#  3. vd_root_tidy 块在 bootstrap.sh、bootstrap-legacy.sh 和各机型 boot/lib/tidy.sh 里一字不差。
#  4. 实际跑一遍 vd_root_tidy / vd_prog_move / vd_data_rescue（假的根目录）：搬对地方、KEEP 和别的文件不动、重复跑没有副作用。
cd "$(dirname "$0")/.." || exit 2
fail=0
bad() { echo "FAIL $*"; fail=1; }

files=$(ls cloud/static/*.sh host/*/boot/*.sh host/*/boot/lib/*.sh host/*/entries/*.sh host/*/kual/*.sh host/*/VeraDroid-Launch.sh kual/*/*.sh 2>/dev/null)
# 每个文件去掉 vd_root_tidy 块（它就是搬迁本身）
strip() { awk '/^# BEGIN vd_root_tidy/{s=1} !s{print FILENAME ":" FNR ": " $0} /^# END vd_root_tidy/{s=0}' "$1"; }
for f in $files; do
    strip "$f"
done > /tmp/vd-root-tidy.$$
# 1. 根目录路径
grep -E '(/mnt/(base-)?us|\$\{?(VD_TOP|vrt)\}?)/veradroid[-.][A-Za-z]' /tmp/vd-root-tidy.$$ \
    | grep -v -e 'veradroid-sys\.img' -e 'veradroid-swap' -e 'root-legacy' \
    | grep -v -E '^[^:]*:[0-9]+: *#' > /tmp/vd-root-tidy.hits.$$
if [ -s /tmp/vd-root-tidy.hits.$$ ]; then
    bad "root-level veradroid-* paths (move them under veradroid/logs|state|backup, or tag a legacy reader with root-legacy):"
    sed 's/^/    /' /tmp/vd-root-tidy.hits.$$ | cut -c1-220
fi
# 2. 给用户看的旧日志名 / 旧文件名
NAMES='veradroid-(install|install-detail|uninstall|fsck|boot|localupdate|autoupdate|resize)\.log|veradroid-(docs-manifest|media-keep|user-backup|confirm|launchers-restored|update\.stage|autoupdate\.lock|install\.lock|install\.incomplete|cc\.db|documents-backup)'
grep -E "$NAMES" /tmp/vd-root-tidy.$$ | grep -v -e 'root-legacy' -e '/tmp/veradroid-' | grep -v -E '^[^:]*:[0-9]+: *#' > /tmp/vd-root-tidy.hits.$$
for j in android/packages/VeraHome/src/com/veradroid/home/*.java; do
    grep -n -E "$NAMES" "$j" | sed "s#^#$j:#"
done | grep -v 'root-legacy' >> /tmp/vd-root-tidy.hits.$$
if [ -s /tmp/vd-root-tidy.hits.$$ ]; then
    bad "old root file names still shown / used:"
    sed 's/^/    /' /tmp/vd-root-tidy.hits.$$ | cut -c1-220
fi
rm -f /tmp/vd-root-tidy.$$ /tmp/vd-root-tidy.hits.$$
# 行尾的“\  # 注释”会把续行断开（下一行变成单独的命令）：标记加错位置的老毛病
for f in $files; do grep -n -E '\\[[:space:]]+#' "$f" | sed "s#^#$f:#"; done > /tmp/vd-root-tidy.bs.$$
[ -s /tmp/vd-root-tidy.bs.$$ ] && { bad "comment after a line continuation:"; sed 's/^/    /' /tmp/vd-root-tidy.bs.$$ | cut -c1-200; }
rm -f /tmp/vd-root-tidy.bs.$$

# 3. 同一块
blk() { sed -n '/^# BEGIN vd_root_tidy/,/^# END vd_root_tidy/p' "$1"; }
ref=host/pw6/boot/lib/tidy.sh
[ -n "$(blk $ref)" ] || bad "$ref has no vd_root_tidy block"
for f in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh host/*/boot/lib/tidy.sh; do
    [ -f "$f" ] || continue
    [ "$(blk "$f")" = "$(blk $ref)" ] || bad "$f: vd_root_tidy block differs from $ref"
done
for v in host/*/boot/lib/common.sh; do
    grep -q 'boot/lib/tidy.sh' "$v" || bad "$v does not source tidy.sh"
done

# 4. 行为
T=${TMPDIR:-/tmp}/vd-root-tidy-run.$$; rm -rf "$T"; mkdir -p "$T/top/veradroid/boot" "$T/top/vd18-keep"
blk $ref > "$T/blk.sh"
R=$T/top
echo old-install > "$R/veradroid-install.log"
echo old-detail > "$R/veradroid-install-detail.log"
mkdir -p "$R/veradroid/logs"; echo new-detail > "$R/veradroid/logs/install-detail.log"
echo manifest > "$R/veradroid-docs-manifest"
echo 1 > "$R/veradroid-resize.pending"
echo a > "$R/veradroid-user-backup-20261117-010203.tgz"
echo b > "$R/veradroid-user-backup-KEEP-20261117.tgz"
echo c > "$R/veradroid-user-backup-20261117-010203-KEEP.tgz"
echo d > "$R/veradroid-cc.db.20261117-010203"
echo e > "$R/veradroid-documents-backup.tgz"
mkdir -p "$R/veradroid-media-keep/0"; echo book > "$R/veradroid-media-keep/0/b.epub"
mkdir -p "$R/veradroid-install.lock"; echo 999999 > "$R/veradroid-install.lock/pid"     # 持有者已经不在
mkdir -p "$R/veradroid-install.4242/x"
echo z > "$R/veradroid-user-backup.partial"
echo keep > "$R/vd18-keep/x.tgz"
echo sys > "$R/veradroid-sys.img"
echo boot > "$R/veradroid/boot/veradroid.sh"
( VD_TOP=$R; . "$T/blk.sh"; vd_root_tidy; vd_root_tidy ) || bad "vd_root_tidy returned non-zero"
chk() { [ -e "$R/$1" ] || bad "tidy: $1 missing"; }
gone() { [ ! -e "$R/$1" ] || bad "tidy: $1 still there"; }
chk veradroid/logs/install.log; gone veradroid-install.log
[ "$(cat "$R/veradroid/logs/install-detail.log" 2>/dev/null)" = old-detail ] || bad "tidy: install-detail.log not taken from the root"
grep -q new-detail "$R/veradroid/logs/install-detail.log.old" 2>/dev/null || bad "tidy: previous install-detail.log not kept in .old"
chk veradroid/state/docs-manifest; chk veradroid/state/resize.pending
chk veradroid/backup/user-backup-20261117-010203.tgz; gone veradroid-user-backup-20261117-010203.tgz
chk veradroid-user-backup-KEEP-20261117.tgz; chk veradroid-user-backup-20261117-010203-KEEP.tgz   # 用户改过名的不动
chk veradroid/backup/cc.db.20261117-010203; chk veradroid/backup/documents-backup.tgz
chk veradroid/backup/media-keep/0/b.epub; gone veradroid-media-keep
gone veradroid-install.lock; gone veradroid-install.4242; gone veradroid-user-backup.partial
chk vd18-keep/x.tgz; chk veradroid-sys.img; chk veradroid/boot/veradroid.sh
# 老安装器在跑（根目录的锁，持有者活着）：什么都不动
echo again > "$R/veradroid-install.log"; mkdir -p "$R/veradroid-install.lock"; echo $$ > "$R/veradroid-install.lock/pid"
( VD_TOP=$R; . "$T/blk.sh"; vd_root_tidy )
chk veradroid-install.log; chk veradroid-install.lock/pid
rm -rf "$R/veradroid-install.lock" "$R/veradroid-install.log"
# 老版本的自动更新（根目录的锁，睡着）：没有安装在进行时停掉它、删掉它的锁
if [ -d /proc/$$ ]; then
    mkdir -p "$T/au"; echo "sleep 300" > "$T/au/auto-update.sh"; ( cd "$T/au" && exec sh "$T/au/auto-update.sh" ) </dev/null >/dev/null 2>&1 & aup=$!
    sleep 1; mkdir -p "$R/veradroid-autoupdate.lock"; echo $aup > "$R/veradroid-autoupdate.lock/pid"
    ( VD_TOP=$R; . "$T/blk.sh"; vd_root_tidy )
    kill -0 $aup 2>/dev/null && { bad "tidy: old sleeping auto-update not stopped"; kill $aup; }
    gone veradroid-autoupdate.lock
fi
# 程序挪成备份 / 回退：logs、state、backup 留在原处
mkdir -p "$R/veradroid/bin" "$T/sys"; echo x > "$R/veradroid/.hidden"
( VD_TOP=$R; . "$T/blk.sh"; vd_prog_move "$R/veradroid" "$T/sys/host.bak.1" ) || bad "vd_prog_move failed"
[ -f "$T/sys/host.bak.1/boot/veradroid.sh" ] && [ -d "$T/sys/host.bak.1/bin" ] && [ -f "$T/sys/host.bak.1/.hidden" ] || bad "vd_prog_move: program not moved"
[ -d "$T/sys/host.bak.1/logs" ] && bad "vd_prog_move: moved logs/"
chk veradroid/logs/install.log; chk veradroid/backup/media-keep/0/b.epub; gone veradroid/boot
( VD_TOP=$R; . "$T/blk.sh"; vd_prog_move "$T/sys/host.bak.1" "$R/veradroid" )
chk veradroid/boot/veradroid.sh; chk veradroid/.hidden
# 老安装器整个挪走的程序目录：日志和备份搬回来，已有的不覆盖
mkdir -p "$T/sys/host.bak.2/backup" "$T/sys/host.bak.2/logs"
echo old > "$T/sys/host.bak.2/backup/user-backup-20261101-000000.tgz"; echo old > "$T/sys/host.bak.2/logs/install.log"
( VD_TOP=$R; . "$T/blk.sh"; vd_data_rescue "$T/sys/host.bak.2" )
chk veradroid/backup/user-backup-20261101-000000.tgz
[ "$(cat "$R/veradroid/logs/install.log")" = old-install ] || bad "vd_data_rescue overwrote logs/install.log"
# 卸载：程序删掉，三个文件夹留着
( VD_TOP=$R; . "$T/blk.sh"; vd_prog_rm "$R/veradroid" )
gone veradroid/boot; gone veradroid/.hidden; chk veradroid/logs/install.log; chk veradroid/backup/media-keep/0/b.epub
# 5. 安装器是 set -eu：vd_root_tidy 里任何一个 $(...) 赋值或 rm 失败都会让整个安装器不出声地退出（rc=1）。
#    0.99 候选的全新安装就是这样坏的：根目录没有 veradroid-autoupdate.lock 时 vrt_p=$(cat …) 失败。
#    每种根目录都在 set -eu 下跑一遍，必须走到 vd_root_tidy 后面。SH=“busybox sh” 可换 shell（Kindle 上是 busybox ash）。
SH=${SH:-sh}
eu() { # 名字：在 $R 上 set -eu 跑 vd_root_tidy 两次
    o=$( VD_TOP=$R $SH -eu -c '. "$1"; vd_root_tidy; vd_root_tidy; echo PAST' sh "$T/blk.sh" 2>&1 ) || true
    [ "$o" = PAST ] || bad "set -eu ($SH): vd_root_tidy aborted on $1 (output: $(echo "$o" | tail -2 | tr '\n' ' '))"
}
newroot() { rm -rf "$T/top"; mkdir -p "$T/top"; R=$T/top; }
newroot;                                                               eu "an empty root (new user, nothing installed)"
newroot; rm -rf "$R";                                                  eu "a missing root"
newroot; mkdir -p "$R/veradroid/boot" "$R/veradroid/state" "$R/veradroid/logs" "$R/veradroid/backup"; eu "an installed 0.99 (new layout, no root files)"
newroot; mkdir -p "$R/veradroid-autoupdate.lock";                      eu "a root auto-update lock without a pid file"
newroot; mkdir -p "$R/veradroid-autoupdate.lock"; : > "$R/veradroid-autoupdate.lock/pid"; eu "a root auto-update lock with an empty pid file"
newroot; mkdir -p "$R/veradroid-autoupdate.lock"; echo 999999 > "$R/veradroid-autoupdate.lock/pid"; eu "a root auto-update lock with a dead pid"
newroot; mkdir -p "$R/veradroid-autoupdate.lock"; echo $$ > "$R/veradroid-autoupdate.lock/pid"; eu "a root auto-update lock held by a live non-updater process"
newroot; mkdir -p "$R/veradroid-install.lock";                         eu "a root install lock without a pid file"
newroot; mkdir -p "$R/veradroid-install.lock"; echo 999999 > "$R/veradroid-install.lock/pid"; eu "a root install lock with a dead pid"
newroot; mkdir -p "$R/veradroid/state/install.lock"; echo $$ > "$R/veradroid/state/install.lock/pid"; mkdir -p "$R/veradroid-autoupdate.lock"; eu "the new install lock held, root auto-update lock without pid"
newroot; mkdir -p "$R/veradroid-install.4242" "$R/veradroid-install.x1"; eu "stale installer temp dirs"
newroot; mkdir -p "$R/veradroid-update.stage";                         eu "a root offline-update stage"
newroot; mkdir -p "$R/veradroid/logs"; echo a > "$R/veradroid-install.log"; echo b > "$R/veradroid/logs/install.log"; eu "a log in both places"
newroot; echo a > "$R/veradroid-docs-manifest"; mkdir -p "$R/veradroid/state"; echo b > "$R/veradroid/state/docs-manifest"; eu "a marker in both places"
newroot; echo a > "$R/veradroid-user-backup-20261117-010203.tgz"; mkdir -p "$R/veradroid/backup"; echo b > "$R/veradroid/backup/user-backup-20261117-010203.tgz"; eu "a backup in both places"
newroot; echo a > "$R/veradroid-user-backup-KEEP.tgz"; echo b > "$R/veradroid-appdata-backup-20261113.tgz"; eu "user-renamed backups only"
# 全新安装的开头（bootstrap 从第一行到 vd_root_tidy 之后），根目录换成假的，set -eu 照旧：必须走到后面
for bs in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh; do
    n=$(grep -n '^vd_root_tidy$' "$bs" | head -1 | cut -d: -f1)
    [ -n "$n" ] || { bad "$bs: no top-level vd_root_tidy call"; continue; }
    for case in empty installed aulock-nopid; do
        newroot
        case $case in
            installed) mkdir -p "$R/veradroid/boot" "$R/veradroid/state" "$R/system/veradroid"; echo 0.98 > "$R/veradroid/version" ;;
            aulock-nopid) mkdir -p "$R/veradroid-autoupdate.lock" ;;
        esac
        { sed -n "1,${n}p" "$bs" | sed -e "s#/mnt/base-us#$R#g" -e "s#/dev/shm/veradroid#$T/shm#g"; echo 'echo PAST_TIDY'; } > "$T/head.sh"
        o=$( cd "$T" && VD_BASE=http://127.0.0.1:9 $SH "$T/head.sh" </dev/null 2>&1 ) || true
        echo "$o" | grep -q '^PAST_TIDY$' || bad "$bs ($SH, $case root): installer stops before getting past vd_root_tidy (output: $(echo "$o" | tail -3 | tr '\n' ' '))"
        [ -d "$R/veradroid/state/install.lock" ] && bad "$bs ($case root): install lock left behind after exit"
    done
done
rm -rf "$T"
[ $fail = 0 ] && echo "root-tidy: ok"
exit $fail
