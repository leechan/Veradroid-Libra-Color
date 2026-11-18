# 屏保挑选（VeraHome 的 ScreensaverActivity，docs/host-settings.md 第 10 节）。
# 选择存在 Android 存储里的一个小文件（桌面写，宿主在每次进屏保时读）：
#   $SYS/data/media/0/Screensaver/.vd-saver   （Android 里 /sdcard/Screensaver/.vd-saver）
#     mode=kindle   用 Kindle 自带的屏保图（默认）
#     mode=rotate   轮换用户的全部图片（veradroid/screensaver/ 和 Android 的 Screensaver/）
#     mode=one      只用一张：file=sd/<文件名>（Android 的 Screensaver/）或 file=vd/<文件名>（Kindle 的 veradroid/screensaver/）
# 没有这个文件 = 以前的做法（有用户图就轮换，没有就用 Kindle 自带的），老用户行为不变。
SAVER_SEL=$SYS/data/media/0/Screensaver/.vd-saver
# 读选择：设 smode（kindle / rotate / one / 空=旧做法）和 sone（一张图的宿主路径）
saver_choice() {
    smode=; sone=
    [ -f "$SAVER_SEL" ] && [ ! -L "$SAVER_SEL" ] || return 0
    smode=$(sed -n 's/^mode=\([a-z]*\)$/\1/p' "$SAVER_SEL" | tail -1)
    case "$smode" in kindle|rotate|one) ;; *) smode= ; return 0 ;; esac
    [ "$smode" = one ] || return 0
    sf=$(sed -n 's/^file=\(.*\)$/\1/p' "$SAVER_SEL" | tail -1)
    sname=${sf#*/}
    case "$sname" in ''|*/*|.*) smode=rotate; return 0 ;; esac          # 只认文件名，不认路径（.. 之类一律不要）
    case "$sf" in
        sd/*) sone="$SYS/data/media/0/Screensaver/$sname" ;;
        vd/*) sone="$VD/screensaver/$sname" ;;
    esac
    [ -n "$sone" ] && [ -f "$sone" ] && [ ! -L "$sone" ] || { sone=; smode=rotate; }   # 那张图被删了：退回轮换
    return 0
}
# 给桌面看 veradroid/screensaver/ 里的图（Android 看不到 Kindle 的 veradroid 文件夹）：临时拷到 $X/saver/（tmpfs，Android 里 /dev/kfb/saver/），
# 另拷一张 Kindle 自带的屏保图当“Kindle 自带”的预览。页面关掉时 saver done 删掉。每张不超过 8 MB，最多 60 张。
saver_cmd() {
    case "$1" in
    list)
        rm -rf $X/saver; mkdir -p $X/saver.tmp || return 0
        n=0
        for f in "$VD"/screensaver/*.[pP][nN][gG] "$VD"/screensaver/*.[jJ][pP][gG] "$VD"/screensaver/*.[jJ][pP][eE][gG]; do
            [ -f "$f" ] && [ ! -L "$f" ] || continue
            case "$f" in */default.png|*/default.PNG) continue ;; esac
            [ "$(wc -c < "$f")" -le 8388608 ] || continue
            cp "$f" $X/saver.tmp/ 2>/dev/null && n=$((n + 1))
            [ $n -ge 60 ] && break
        done
        for f in /usr/share/blanket/screensaver/bg_ss*.png; do [ -f "$f" ] && { cp "$f" $X/saver.tmp/.kindle-preview.png; break; }; done
        chmod 755 $X/saver.tmp; chmod 644 $X/saver.tmp/* $X/saver.tmp/.kindle-preview.png 2>/dev/null
        mv $X/saver.tmp $X/saver; : > $X/ctl/saver.listed
        t "screensaver: exported $n image(s) from veradroid/screensaver for the picker" ;;
    done) rm -rf $X/saver $X/saver.tmp $X/ctl/saver.listed ;;
    esac
}

# Android 的 内部存储/Screensaver（/sdcard/Screensaver）：用户放屏保图片的另一个地方。开机就建好，里面放一份说明
# （和 veradroid/screensaver/ 的那份对应）。以前要等桌面第一次打开屏保页才由桌面自己建，是桌面 uid 的 0700
# （测试机上：10012 drwx------），传书网页以外的应用、文件管理进不去。现在和 Books / Download 一样：属主 media_rw（1023，
# sdcard 守护进程用它）、777。里面已有的文件（桌面写的 .vd-saver、导入的图）不动。
SAVER_NOTE_SD="把屏保图片（jpg / png）放在这个文件夹里。
Kindle 休眠时，VeraDroid 显示这里的图片。在 设置 → 屏保 里可以选“轮换全部图片”或只用其中一张。
竖图、和屏幕差不多大最好。

也可以用 USB 连电脑，放进 Kindle 盘的 veradroid/screensaver/ 文件夹；传书网页的“文件”里也能上传到这里。"
saver_dir_fix() {
    sdd=$SYS/data/media/0
    [ -d "$sdd" ] || return 0
    [ -L "$sdd/Screensaver" ] && return 0
    { [ -e "$sdd/Screensaver" ] && [ ! -d "$sdd/Screensaver" ]; } && return 0     # 同名的文件：用户的，不动
    mkdir -p "$sdd/Screensaver" 2>/dev/null || return 0
    chown 1023:1023 "$sdd/Screensaver" 2>/dev/null || true; chmod 777 "$sdd/Screensaver" 2>/dev/null || true
    sdn="$sdd/Screensaver/把屏保图片放这里.txt"
    if [ "$(cat "$sdn" 2>/dev/null)" != "$SAVER_NOTE_SD" ]; then
        { printf '%s\n' "$SAVER_NOTE_SD" > "$sdn" && chmod 644 "$sdn" && chown 1023:1023 "$sdn"; } 2>/dev/null || true
    fi
    return 0
}
