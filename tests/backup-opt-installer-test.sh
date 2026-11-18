#!/bin/sh
# 安装器的“更新前备份”那一段（UPDATE_BACKUP=full|light|off、空间不够退到只备份小文件）实际跑一遍：
# 从 bootstrap.sh / bootstrap-legacy.sh 里把这一段原样截出来，/mnt/us、/mnt/base-us 换成假的根目录，set -eu 下跑。
# 看：备份里有没有书、state/backup.last 写对没有、off 时一个备份都不做、完整备份放不下时改成只备份设置和阅读进度。
cd "$(dirname "$0")/.." || exit 2
fail=0
bad() { echo "FAIL $*"; fail=1; }
SH=${SH:-sh}
T=${TMPDIR:-/tmp}/vd-bk-inst.$$; rm -rf "$T"; mkdir -p "$T/bin"
if ! stat -c %s / >/dev/null 2>&1; then   # macOS
    printf '%s\n' '#!/bin/sh' '[ "$1" = -c ] || exec /usr/bin/stat "$@"' \
        'case "$2" in "%s %n") f="%z %N" ;; %s) f=%z ;; %Y) f=%m ;; *) f=$2 ;; esac' 'shift 2; exec /usr/bin/stat -f "$f" "$@"' > "$T/bin/stat"
    chmod 755 "$T/bin/stat"
fi
cut_pw6() { awk '/^BKL=\$TMP\/bk.list/{p=1} /^# 安装前的 Kindle 书库清单/{p=0} p' cloud/static/bootstrap.sh; }
cut_legacy() { awk '/^BKL=\/tmp\/veradroid-bk/{p=1} /^EMU_BAKK=0$/{p=0} /^# 进度（bk_progress）/{p=1} /^# 安装前的 Kindle 书库清单/{p=0} p' cloud/static/bootstrap-legacy.sh; }
blk() { sed -n '/^# BEGIN vd_backup_mode/,/^# END vd_backup_mode/p' "$1"; }

run_case() { # 安装器 模式 [DF_FREE] -> $T/out.*，$R 是假的根目录
    R=$T/r; rm -rf "$R"; mkdir -p "$R/documents/sub" "$R/koreader/settings" "$R/veradroid/backup" "$R/veradroid/state" "$R/veradroid/logs" "$R/system/veradroid" "$T/tmp"
    head -c 30000 /dev/zero > "$R/documents/book1.epub"; head -c 40000 /dev/zero > "$R/documents/sub/book2.azw3"
    echo progress > "$R/documents/book1.sdr"; echo settings > "$R/koreader/settings/reader.lua"
    [ "$2" = none ] || echo "UPDATE_BACKUP=$2" > "$R/system/veradroid/settings.conf"
    {
        echo 'set -eu'
        echo "VD_TOP='$R'; VD_STATE='$R/veradroid/state'; SYS='$R/system/veradroid'; TMP='$T/tmp'; stamp=20261119-120000"
        echo 'LOOP=0; PARTS=; PARTS_ROOTFS_GZ=; TESTED=device; VP_ON=; UI_AUTO=; VP_L2='
        echo 'vlog() { echo "$*" >> "$TMP/vlog"; }; show() { echo "$*" >> "$TMP/show"; }; vp_step() { echo "$*" >> "$TMP/show"; }'
        echo 'df() { echo "Filesystem 1K-blocks Used Available"; echo "fake 99999999 0 $DF_FREE"; }'   # 剩余空间（KB）由 DF_FREE 定，和跑测试的机器无关
        echo 'progress_line() { :; }; vp_progress() { :; }; vp_now() { date +%s; }; vp_elapsed() { echo 0; }'
        echo 'is_installer_path() { case "$1" in documents/VeraDroid.sh*) return 0 ;; esac; return 1; }'
        blk "$1"
        if [ "$1" = cloud/static/bootstrap.sh ]; then cut_pw6; else cut_legacy; fi
        echo 'echo "USER_SAFE=$USER_SAFE"'
    } | sed -e "s#/mnt/base-us#$R#g" -e "s#/mnt/us#$R#g" -e "s#/tmp/veradroid-bk#$T/tmp/bk#g" > "$T/run.sh"
    ( PATH=$T/bin:$PATH DF_FREE=${3:-99999999} $SH "$T/run.sh" ) > "$T/out" 2>"$T/err" || bad "$1 $2: rc=$? $(tail -3 "$T/err" | tr '\n' ' ')"
}
inbk() { ls "$R"/veradroid/backup/user-backup-*.tgz >/dev/null 2>&1 && tar -tzf "$R"/veradroid/backup/user-backup-*.tgz 2>/dev/null | grep -q "$1"; }
last() { sed -n "s/^$1=//p" "$R/veradroid/state/backup.last" 2>/dev/null; }

for I in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh; do
    blk "$I" | grep -q vd_backup_mode || continue     # 这个分支没改这个安装器（另一条线的旧副本）
    run_case $I none
    inbk book1.epub && inbk reader.lua || bad "$I default: books / settings not in the backup"
    [ "$(last result)" = ok ] && [ "$(last kind)" = full ] && [ "$(last file)" = user-backup-20261119-120000.tgz ] || bad "$I default: backup.last $(tr '\n' ' ' < "$R/veradroid/state/backup.last")"
    run_case $I light
    inbk reader.lua && inbk book1.sdr || bad "$I light: settings / progress not in the backup"
    inbk book1.epub && bad "$I light: a book is in the backup"
    [ "$(last kind)" = light ] && [ "$(last result)" = ok ] || bad "$I light: backup.last"
    grep -qx 'user-backup-20261119-120000.tgz light' "$R/veradroid/state/backup-kinds" || bad "$I light: backup-kinds"
    run_case $I off
    ls "$R"/veradroid/backup/user-backup-* >/dev/null 2>&1 && bad "$I off: a backup was made"
    [ "$(last result)" = off ] && [ -z "$(last file)" ] || bad "$I off: backup.last"
    grep -q '更新前备份已关闭' "$T/tmp/show" 2>/dev/null || bad "$I off: nothing on the screen"
    # 剩余 150 MB：书（70 KB）放得下，但完整备份 + 安装的估算放不下（新机型）/ 都放得下（legacy 只看备份 + 100 MB）
    run_case $I full 153600
    if [ $I = cloud/static/bootstrap.sh ]; then
        [ "$(last kind)" = light ] && [ "$(last fallback)" = light ] || bad "$I tight space: no fall back to light ($(tr '\n' ' ' < "$R/veradroid/state/backup.last"))"
        inbk book1.epub && bad "$I tight space: books backed up"
        grep -q '空间不够做完整备份' "$T/tmp/show" || bad "$I tight space: not said on the screen"
    fi
    # 剩余 100 MB 多一点：完整的放不下，只备份小文件的放得下（两个安装器都要退）
    run_case $I full 102450
    [ "$(last kind)" = light ] && [ "$(last result)" = ok ] || bad "$I very tight: expected a light backup ($(tr '\n' ' ' < "$R/veradroid/state/backup.last"))"
    # 一点地方都没有：跳过，记 nospace
    run_case $I full 1000
    [ "$(last result)" = nospace ] || bad "$I no space: result $(last result)"
done
[ -n "${KEEP:-}" ] || rm -rf "$T"
[ $fail = 0 ] && echo "backup-opt-installer: ok"
exit $fail
