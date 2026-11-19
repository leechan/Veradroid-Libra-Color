#!/bin/sh
# 用户放进 veradroid/ 的文件升级 / 重装 / 卸载后还在（2026-11-19，KPW5 用户：“放到 veradroid/fonts 的字体，升级以后就没了”）。
# 整包安装把程序目录挪成 host.bak 后只带回了 screensaver/ apps/ kindle-crash/ 顶层的文件，fonts/（= Android 的 内部存储/Fonts，
# 字体商店也装在这里）整个留在 host.bak 里，下次安装就删了；卸载（保留书）也把它删了。
# 这里从 bootstrap*.sh 里把整包安装“替换程序目录”那一段和一次性找回那一段原样截出来，/mnt/base-us 换成假的根目录，set -eu 下跑：
#  1. 升级：用户字体（含子文件夹）、屏保、待装 APK、崩溃转储都带过去；包里的字体 / 屏保用新的；旧包自带、新包去掉的不复活
#  2. 连着升两次还在；从没有包清单的旧版本（1.00 / 0.8.11）升级也带
#  3. 1.00 升级时丢的字体还在最近的 host.bak 里：一次性找回，之后不再找（用户删掉的不复活）
#  4. 卸载（vd_user_keep + vd_prog_rm）：用户的字体 / 屏保留在 backup/user-files，重新安装放回去，backup/user-files 清掉
#  5. vd_user_carry 这一段在 bootstrap*.sh 和 tidy.sh 里一字不差，卸载脚本调了 vd_user_keep
cd "$(dirname "$0")/.." || exit 2
fail=0
bad() { echo "FAIL $*"; fail=1; }
SH=${SH:-sh}
T=${TMPDIR:-/tmp}/vd-user-files.$$; rm -rf "$T"; mkdir -p "$T"
blk() { sed -n "/^# BEGIN $2\$/,/^# END $2\$/p" "$1"; }
cut_install() { awk '/^vd_prog_move "\$VD" "\$BAK"/{p=1} p; /^vd_bundled_save "\$TMP\/veradroid-pw6"$/{p=0}' "$1"; }
cut_rescue() { awk '/^# 1\.00 \/ 0\.8\.11 及以前的整包安装不带 fonts/{p=1} /^# 只保留最近一份旧系统/{p=0} p' "$1"; }

# 假的包：新的 DroidSansFallback / default.png、OFL.txt、两个 APK
mkbundle() {
    rm -rf "$T/tmp"; B=$T/tmp/veradroid-pw6; mkdir -p "$B/boot" "$B/bin" "$B/fonts" "$B/screensaver" "$B/apks"
    echo new-boot > "$B/boot/veradroid.sh"; echo new > "$B/fonts/DroidSansFallback.ttf"; echo ofl > "$B/fonts/OFL.txt"
    echo new > "$B/screensaver/default.png"; echo apk > "$B/apks/VeraHome.apk"; echo apk > "$B/apks/VeraIME.apk"
}
# 假的根目录 $R：装着旧版本，用户放了字体（含子文件夹）、屏保、待装 APK、崩溃转储
mkroot() { # [有包清单 1/0]
    R=$T/r; rm -rf "$R"; V=$R/veradroid; mkdir -p "$V/boot" "$V/fonts/家族" "$V/screensaver" "$V/apps" "$V/kindle-crash" "$V/logs" "$V/state" "$V/backup" "$R/system/veradroid"
    echo old-boot > "$V/boot/veradroid.sh"; echo old > "$V/fonts/DroidSansFallback.ttf"; echo old > "$V/fonts/Dropped.ttf"
    echo user > "$V/fonts/我的字体.ttf"; echo user > "$V/fonts/家族/Bold.otf"
    echo old > "$V/screensaver/default.png"; echo user > "$V/screensaver/my photo.jpg"
    echo user > "$V/apps/pending.apk"; echo crash > "$V/kindle-crash/dump.txt"
    if [ "${1:-1}" = 1 ]; then printf '%s\n' DroidSansFallback.ttf Dropped.ttf > "$V/state/bundled.fonts"; echo default.png > "$V/state/bundled.screensaver"; fi
}
run() { # 安装器 [rescue] -> 跑一次整包安装的那一段
    stamp=$(date +%H%M%S)$$${RUNS:-0}; RUNS=$(( ${RUNS:-0} + 1 ))
    mkbundle
    {
        echo 'set -eu'
        echo "VD=/mnt/base-us/veradroid; SYS=/mnt/base-us/system/veradroid; TMP='$T/tmp'; stamp=$stamp; BAK=\$SYS/host.bak.\$stamp"
        echo 'LOOP=0; free_mb=99999; need_mb=100; MODEL=pw6; MODEL_FILE=$SYS/model'
        echo 'vlog() { echo "$*" >> "$TMP/vlog"; }; show() { :; }; guard_rm() { :; }; vd_launch_backup() { :; }'
        blk "$1" vd_root_tidy; blk "$1" vd_user_carry
        [ "${2:-}" = rescue ] && cut_rescue "$1"
        cut_install "$1"
    } | sed -e "s#/mnt/base-us#$R#g" -e "s#/mnt/us#$R#g" > "$T/run.sh"
    ( $SH "$T/run.sh" ) > "$T/out" 2>"$T/err" || bad "$1: install section rc=$? $(tail -3 "$T/err" | tr '\n' ' ')"
}
has() { [ -f "$V/$1" ] && [ "$(cat "$V/$1")" = "$2" ] || bad "$I $CASE: $1 should be '$2' ($(cat "$V/$1" 2>/dev/null || echo missing))"; }
hasnt() { [ ! -e "$V/$1" ] || bad "$I $CASE: $1 should be gone"; }

for I in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh; do
    grep -q '^# BEGIN vd_user_carry$' "$I" 2>/dev/null || continue     # 这个分支没改这个安装器（另一条线的旧副本）
    CASE=upgrade; mkroot 1; run "$I"
    has boot/veradroid.sh new-boot; has fonts/DroidSansFallback.ttf new; has fonts/OFL.txt ofl
    has "fonts/我的字体.ttf" user; has "fonts/家族/Bold.otf" user; hasnt fonts/Dropped.ttf
    has screensaver/default.png new; has "screensaver/my photo.jpg" user
    has apps/pending.apk user; has apps/VeraHome.apk apk; has kindle-crash/dump.txt crash
    grep -qx DroidSansFallback.ttf "$V/state/bundled.fonts" && grep -qx OFL.txt "$V/state/bundled.fonts" && ! grep -q Dropped "$V/state/bundled.fonts" \
        || bad "$I $CASE: state/bundled.fonts $(tr '\n' ' ' < "$V/state/bundled.fonts" 2>/dev/null)"
    grep -qx VeraHome.apk "$V/state/bundled.apps" || bad "$I $CASE: state/bundled.apps"
    CASE=upgrade-twice; run "$I"
    has "fonts/我的字体.ttf" user; has "fonts/家族/Bold.otf" user; has "screensaver/my photo.jpg" user; has fonts/DroidSansFallback.ttf new
    CASE=from-old-version; mkroot 0; run "$I"
    has "fonts/我的字体.ttf" user; has "fonts/家族/Bold.otf" user; has "screensaver/my photo.jpg" user; has fonts/DroidSansFallback.ttf new

    # 3. 以前升级时丢的：还在最近一份 host.bak 里
    CASE=rescue; mkroot 1; rm -f "$V/fonts/我的字体.ttf"; rm -rf "$V/fonts/家族"
    mkdir -p "$R/system/veradroid/host.bak.20261119-0700/fonts/家族"; echo lost > "$R/system/veradroid/host.bak.20261119-0700/fonts/家族/Bold.otf"
    echo lost > "$R/system/veradroid/host.bak.20261119-0700/fonts/我的字体.ttf"
    run "$I" rescue
    has "fonts/我的字体.ttf" lost; has "fonts/家族/Bold.otf" lost; [ -f "$V/state/user-carry.v1" ] || bad "$I $CASE: no marker"
    CASE=rescue-once; rm -f "$V/fonts/我的字体.ttf"; run "$I" rescue
    hasnt "fonts/我的字体.ttf"

    # 4. 卸载保留，再重新安装
    CASE=uninstall; mkroot 1
    { echo 'set -eu'; echo "VD=$R/veradroid"; blk "$I" vd_root_tidy; blk "$I" vd_user_carry
      echo 'echo "kept=$(vd_user_keep "$VD")"; vd_prog_rm "$VD"'; } | sed -e "s#/mnt/base-us#$R#g" > "$T/un.sh"
    ( $SH "$T/un.sh" ) > "$T/out" 2>"$T/err" || bad "$I $CASE: rc=$? $(tail -3 "$T/err" | tr '\n' ' ')"
    grep -qx 'kept=3' "$T/out" || bad "$I $CASE: $(cat "$T/out")"
    K=$V/backup/user-files
    [ -f "$K/fonts/我的字体.ttf" ] && [ -f "$K/fonts/家族/Bold.otf" ] && [ -f "$K/screensaver/my photo.jpg" ] || bad "$I $CASE: user files not kept"
    [ -e "$K/fonts/DroidSansFallback.ttf" ] || [ -e "$K/screensaver/default.png" ] && bad "$I $CASE: bundled files kept"
    [ -e "$V/fonts" ] || [ -e "$V/boot" ] && bad "$I $CASE: program not removed"
    CASE=reinstall; run "$I"
    has "fonts/我的字体.ttf" user; has "fonts/家族/Bold.otf" user; has "screensaver/my photo.jpg" user; has fonts/DroidSansFallback.ttf new
    [ -e "$K" ] && bad "$I $CASE: backup/user-files left behind ($(find "$K" | tr '\n' ' '))"
done

# 5. 同一份代码
for B in cloud/static/bootstrap.sh cloud/static/bootstrap-legacy.sh; do
    grep -q '^# BEGIN vd_user_carry$' "$B" 2>/dev/null || continue
    case $B in *legacy*) H="host/legacy" ;; *) H="host/pw6 host/k49" ;; esac
    for h in $H; do
        [ "$(blk "$B" vd_user_carry)" = "$(blk $h/boot/lib/tidy.sh vd_user_carry)" ] || bad "$h/boot/lib/tidy.sh: vd_user_carry differs from $B"
        grep -q 'vd_user_keep "\$VD"' $h/boot/uninstall.sh || bad "$h/boot/uninstall.sh does not keep the user files"
    done
done
[ -n "${KEEP:-}" ] || rm -rf "$T"
[ $fail = 0 ] && echo "user-files: ok"
exit $fail
