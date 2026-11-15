#!/bin/sh
# Name: VeraDroid 离线安装
# Author: ajie / wenjin.jp
# Icon: data:image/png;base64,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
# Offline installer: the full bundle and bootstrap.sh sit next to this file.
# 全程写日志：失败时用 USB 取 /mnt/us/veradroid-install.log
trap '' PIPE   # 书库启动器把输出管道给 fbink；fbink 缺失/崩溃时管道断开，不能让 SIGPIPE 杀掉脚本
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
LOG=/mnt/us/veradroid-install.log
if : >>"$LOG" 2>/dev/null; then exec >>"$LOG" 2>&1; fi   # 写不了日志也要继续，不能让 exec 失败直接退出
echo "==== $(date) offline install: \$0=$0 uid=$(id -u 2>/dev/null) fw=$(cat /etc/prettyversion.txt 2>/dev/null | head -1)"
rm -f /tmp/vd-progress.on
# ---- 屏幕上的说明 ----
# eips 只有 ASCII 字形（中文它画不出来），以前 msg / fail 用 eips 写中文，屏幕上什么都没有，用户看到的就是“点了闪退”
# （Scribe 用户：拿错了离线包，安装器在屏幕上什么都没说就退了）。现在：fbink + Kindle 自带的中文字体能刷出来就写中文，
# 刷不出来（没有能用的 fbink、Scribe 上旧 FBInk 不认识机型、驱动拒绝刷新）就用 eips 写英文。
# screen 中文行… [-- 英文行…]：整屏显示；没给英文行时 eips 只能写出中文行里的 ASCII 部分
screen() {
    zh=; en=; sec=zh
    for l in "$@"; do
        if [ "$l" = -- ]; then sec=en; continue; fi
        if [ $sec = zh ]; then zh="$zh$l
"; else en="$en$l
"; fi
    done
    eips -c >/dev/null 2>&1 || true
    fb=; for c in "$(command -v fbink 2>/dev/null)" /var/local/kmc/bin/fbink /mnt/us/libkh/bin/fbink /mnt/us/koreader/fbink /mnt/base-us/veradroid/bin/fbink; do
        [ -n "$c" ] && [ -x "$c" ] && "$c" -e >/dev/null 2>&1 && fb=$c && break   # 每个候选真的跑一次（KT6 上越狱自带的那个会段错误）
    done
    ft=; for c in /usr/java/lib/fonts/STHeitiMedium.ttf /usr/java/lib/fonts/STSongMedium.ttf /usr/java/lib/fonts/MYingHeiSMedium.ttf; do [ -f "$c" ] && ft=$c && break; done
    if [ -n "$fb" ] && [ -n "$ft" ]; then
        sw=$("$fb" -e 2>/dev/null | tr ';' '\n' | sed -n 's/^viewWidth=//p' | head -1)
        case "$sw" in ''|*[!0-9]*) sw=1272 ;; esac
        px=$((26 * sw / 1272)); [ $px -ge 20 ] || px=20   # 字号随屏宽（Scribe 1860 宽，PW6 的 26 px 在上面太小）
        # FBInk 不认识这台机器（Scribe 上越狱带的旧 FBInk、模拟器）时它用 i.MX 的刷新命令，驱动拒绝（"MXCFB_SEND_UPDATE: ..."），
        # 返回值却是 0，屏幕上什么都没有（scr-ks 模拟器实测）：看它的报错，有就当画不出来，改用 eips
        if fe=$("$fb" -q -c -t regular="$ft",px=$px,top=$((40 * sw / 1272)),left=30,right=30 "$zh" 2>&1 >/dev/null); then
            case "$fe" in
                *Unidentified*|*SEND_UPDATE*|*rror*|*ailed*)
                    echo "screen: fbink cannot refresh here ($(printf '%s' "$fe" | head -2 | tr '\n' ' ')), eips"
                    eips -c >/dev/null 2>&1 || true ;;   # fbink 写进了帧缓冲但没刷出来：先清掉，免得 eips 刷新时带出半截中文
                *) return 0 ;;
            esac
        fi
    fi
    [ -n "$en" ] || en=$(printf '%s' "$zh" | tr -cd '\n -~')
    r=2; printf '%s' "$en" | while IFS= read -r l; do eips 1 $r "$l" >/dev/null 2>&1 || true; r=$((r + 2)); done
}
# 安装器画了整屏进度画面（/tmp/vd-progress.on）时不再往上写字：出错原因和代码已经在画面上
msg() { echo "$*"; }
# fail 中文原因 [英文原因]：在屏幕上停够时间（书库界面会盖住，30 秒里重画几次）再退出
fail() {
    echo "$1"
    if [ ! -f /tmp/vd-progress.on ]; then
        i=0; while [ $i -lt 3 ]; do
            screen "VeraDroid 离线安装：没有安装" "" "$1" "" "什么都没有改动。日志：veradroid-install.log" \
                -- "VeraDroid offline install: NOT installed" "" "${2:-Error, see veradroid-install.log}" "" "Nothing was changed."
            sleep 10; i=$((i + 1))
        done
    fi
    exit 1
}
# 有的固件用 sh -c 之类的方式启动，$0 不是脚本路径：退回到 documents
HERE=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
case "$HERE" in ''|/|/bin|/usr/bin|/tmp) HERE=/mnt/us/documents ;; esac
ls "$HERE"/veradroid-*-*.tar.gz >/dev/null 2>&1 || HERE=/mnt/us/documents
echo "HERE=$HERE"
[ "$(id -u 2>/dev/null)" = 0 ] || fail "需要 root 权限运行（当前 uid=$(id -u)），请确认越狱已生效" "Needs root (uid=$(id -u)). Is the jailbreak active?"
# ---- 这台 Kindle 该用哪个离线包（按内核，和 bootstrap.sh 的检查一样）----
#   5.x 内核（PW6 / Colorsoft）          veradroid-pw6-<版本>.tar.gz     VeraDroid-Offline.zip
#   4.9 内核（PW5 / KT5 / KT6 / Scribe）  veradroid-k49-<版本>.tar.gz     VeraDroid-Offline-Experimental.zip
#   3.0 / 4.1 内核（老机型）              veradroid-legacy-<版本>.tar.gz  VeraDroid-Offline-Legacy.zip
# 拿错了包以前的样子：PW6 包在 Scribe 上被 bootstrap 的“实验机型”检查拒绝，原因用 eips 写中文 = 屏幕上什么都没有；
# 老机型包在 Scribe 上什么都不拦（包里也有 bin/vdlmk），会把 3.0 内核的系统装上去。现在在这里就停下，屏幕上写清楚该用哪个 zip。
fbw=$(cut -d, -f1 /sys/class/graphics/fb0/virtual_size 2>/dev/null)
case "$(uname -r)" in
    3.*|4.1.*) WANT=legacy; WANTZ=VeraDroid-Offline-Legacy.zip; DEV="老机型（$(uname -r | cut -d. -f1-2) 内核）"; DEVEN="older Kindle (kernel $(uname -r | cut -d. -f1-2))" ;;
    4.*) WANT=k49; WANTZ=VeraDroid-Offline-Experimental.zip
         case "$fbw" in 1860|1872|2480) DEV="Kindle Scribe"; DEVEN="Kindle Scribe" ;;
             *) DEV="实验机型（PW5 / 入门款 2022、2024 / Scribe）"; DEVEN="PW5 / Kindle 2022, 2024 / Scribe" ;; esac ;;
    *) WANT=pw6; WANTZ=VeraDroid-Offline.zip; DEV="PaperWhite 6 / Colorsoft"; DEVEN="PaperWhite 6 / Colorsoft" ;;
esac
echo "device: $DEVEN, kernel $(uname -r), fb width ${fbw:-?}: needs veradroid-$WANT-*.tar.gz ($WANTZ)"
B=
for f in "$HERE"/veradroid-$WANT-*.tar.gz; do [ -f "$f" ] && B=$f && break; done
if [ -z "$B" ]; then
    other=; for f in "$HERE"/veradroid-pw6-*.tar.gz "$HERE"/veradroid-k49-*.tar.gz "$HERE"/veradroid-legacy-*.tar.gz; do [ -f "$f" ] && other=$(basename "$f") && break; done
    if [ -n "$other" ]; then
        case "$other" in veradroid-pw6-*) oz=VeraDroid-Offline.zip ;; veradroid-k49-*) oz=VeraDroid-Offline-Experimental.zip ;; *) oz=VeraDroid-Offline-Legacy.zip ;; esac
        echo "wrong offline package: $other (from $oz); this device needs $WANTZ"
        i=0; while [ $i -lt 4 ]; do   # 书库界面可能会盖住：40 秒里重画几次
            screen "VeraDroid 离线安装：离线包拿错了" "" "这台 Kindle：$DEV" "documents 里的是：$other" "（来自 $oz，不是给这台机器的）" "" \
                "请到官网下载：$WANTZ" "解压后把里面的 3 个文件放进 documents，" "删掉 $other，再点“VeraDroid 离线安装”。" "" "什么都没有改动。" \
                -- "VeraDroid: WRONG OFFLINE PACKAGE" "" "This Kindle: $DEVEN" "Found: $other" "(from $oz)" "" "Download $WANTZ" "from the VeraDroid website, copy its 3 files" "into documents, delete $other, tap again." "" "Nothing was changed."
            sleep 10; i=$((i + 1))
        done
        exit 1
    fi
    fail "缺少安装包（veradroid-$WANT-…tar.gz）：请把 $WANTZ 里的文件全部放进 documents" "Missing veradroid-$WANT-*.tar.gz. Copy all files of $WANTZ into documents."
fi
VER=$(basename "$B" .tar.gz); VER=${VER##*-}
case "$B" in *veradroid-k49-*) export VD_EXPERIMENTAL=1 ;; esac   # 实验机型离线包
# 老机型（3.0 / 4.1 内核）离线包：veradroid-legacy-<版本>.tar.gz，只在模拟器上验证过，和联网安装一样先警告、再点一次确认
case "$B" in *veradroid-legacy-*) export VD_EXPERIMENTAL=1; VER=$(basename "$B" .tar.gz); VER=${VER#veradroid-legacy-} ;; esac
# ---- 只在模拟器上验证过的机型（3.0 内核 PW2 / PW3 / Voyage，4.1 内核 PW4 / 入门款 2019 / Oasis 2 / Oasis 3）----
# 先在屏幕上把风险说清楚，要用户在 10 秒到 2 分钟之内再点一次本脚本才继续（Kindle 上没有键盘，这是最简单的“确认”）。
# 真机验证过的实验机型（PW5 / KT5 / KT6 / Scribe，4.9 / 5.x 内核）不经过这里，流程和以前一样。
EMU=
case "$(uname -r)" in 3.*) EMU="3.0 内核（PW2 / PW3 / Voyage 一代）" ;; 4.1.*) EMU="4.1 内核（PW4 / 入门款 2019 / Oasis 2 / Oasis 3）" ;; esac
if [ -n "$EMU" ]; then
    CF=/mnt/base-us/veradroid-confirm
    bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null); now=$(cut -d. -f1 /proc/uptime)
    set -- $(cat "$CF" 2>/dev/null); cw=${1:-}; cb=${2:-}; cu=${3:-0}
    rm -f "$CF"
    if [ "$cw" = install ] && [ "$cb" = "$bid" ] && [ $((now - cu)) -ge 10 ] && [ $((now - cu)) -le 120 ] 2>/dev/null; then
        echo "emulator-only model ($EMU): confirmed by the second tap after $((now - cu))s"
        export VD_EMUONLY_OK=1
    else
        fwv=$(sed -n 's/.*Kindle[[:space:]]*\([0-9][0-9.]*\).*/\1/p' /etc/prettyversion.txt 2>/dev/null | head -1)
        echo "emulator-only model ($EMU, fw $fwv): warning shown, waiting for the second tap"
        echo "install $bid $now" > "$CF"; sync
        i=0
        while [ $i -lt 4 ]; do   # 书库界面可能会盖住：40 秒里重画几次
            screen "VeraDroid 实验机型 · 测试版" "这台：$EMU，固件 ${fwv:-?}" "-------------------------------" \
                "这个机型只在模拟器上跑过，" "没有在真机上验证。可能无法启动；" "启动失败会自动回到 Kindle（最多约 15 分钟）。" \
                "不会改动 Kindle 系统分区，只在用户存储里放文件。" "安装前会记下书库清单并备份小文件。" \
                "请先用 USB 把重要的书拷到电脑！" "卸载：点书库里的“VeraDroid 卸载”。" "-------------------------------" \
                "确认安装：10 秒后、2 分钟内再点一次本脚本。" "不想装：什么都不用做。"
            sleep 10; i=$((i + 1))
        done
        exit 0
    fi
fi

[ -f "$HERE/bootstrap.sh" ] || fail "缺少 bootstrap.sh，请把 $WANTZ 里的文件全部放进 documents" "Missing bootstrap.sh. Copy all files of $WANTZ into documents."
msg "VeraDroid：使用离线整包安装…"
VD_BUNDLE="$B" VD_OFFLINE_BUNDLE="$B" VD_INSTALLER="$0" VD_HELPER="$HERE/bootstrap.sh" VD_VERSION="$VER" sh "$HERE/bootstrap.sh"
rc=$?
echo "bootstrap rc=$rc"
# 安装器在进度画面出现之前就停下（机型 / 分辨率 / 固件检查）时，原因只在日志里：把它的最后一句话也写到屏幕上
why=; whyen=; [ -f "$LOG" ] && why=$(tail -n 20 "$LOG" 2>/dev/null | grep -v -e '^bootstrap rc=' -e '^EN: ' -e '^[[:space:]]*$' | tail -1 | cut -c1-120)
[ -f "$LOG" ] && whyen=$(tail -n 20 "$LOG" 2>/dev/null | sed -n 's/^EN: //p' | tail -1 | cut -c1-120)   # 安装器给 eips 留的英文原因
[ "$rc" = 0 ] || fail "安装失败（代码 $rc）${why:+：$why}" "${whyen:-Install failed (code $rc). See veradroid-install.log}"
exit 0
