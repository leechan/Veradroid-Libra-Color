#!/bin/sh
# 屏保图片格式（fix/saver-formats）：用户问“屏保一定要 png 格式吗，难怪放进去一直不显示”。
#  1. 宿主 saver.sh：扩展名不分大小写、多认 webp / bmp / gif / heic……；格式看文件头；桌面转好的灰度 PNG（.vd-cache，.src 对得上）优先，
#     过期的不用；fbink 画不了的格式跳过并写原因。
#  2. sleep.sh 的 screensaver_show：轮到的图用不了 / fbink 画不出来就换下一张，最后退回 Kindle 自带的；透明 PNG 照旧叠在页面上。
#  3. saver list：拷贝保留修改时间、太大的写 .skipped、写 .panel / .elsewhere。
#  4. 新机型的 pw6 / k49 两份一样；VeraHome 的屏保页用 SaverFormat / SaverImage；JVM 测 SaverFormat（有 JDK 时）。
# 需要 GNU / busybox 的 stat -c（Linux、Kindle）：在 Mac 上跳过宿主部分。
cd "$(dirname "$0")/.." || exit 2
fail=0
F() { echo "FAIL $*"; fail=1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
H=android/packages/VeraHome
J=$H/src/com/veradroid/home

TREES=; for v in pw6 k49 legacy; do grep -q '^saver_resolve()' host/$v/boot/lib/saver.sh 2>/dev/null && TREES="$TREES $v"; done
[ -n "$TREES" ] || F "no host tree has saver_resolve"
if [ -f host/pw6/boot/lib/saver.sh ] && grep -q '^saver_resolve()' host/pw6/boot/lib/saver.sh; then
    cmp -s host/pw6/boot/lib/saver.sh host/k49/boot/lib/saver.sh || F "pw6 / k49 saver.sh differ"
    cmp -s host/pw6/boot/lib/sleep.sh host/k49/boot/lib/sleep.sh || F "pw6 / k49 sleep.sh differ"
fi

png() { printf '\211PNG\r\n\032\n\000\000\000\rIHDR\000\000\000\001\000\000\000\001\010'; printf "\\$(printf %03o "$2")"; printf '\000\000\000\000\000\000\000\000\000\000\000\000IEND\256B`\202'; } # $2 = colour type
jpg() { printf '\377\330\377\340\000\020JFIF\000\001\001\000'; [ "${1:-}" = cut ] || printf '\377\331'; }
mkimg() { case "$2" in cutjpg) jpg cut ;; png) png x 2 ;; pnga) png x 6 ;; jpg) jpg ;; webp) printf 'RIFF\000\000\000\000WEBPVP8 ' ;; heic) printf '\000\000\000\030ftypheic\000\000\000\000' ;;
          bmp) printf 'BM\000\000\000\000\000\000\000\000\000\000' ;; gif) printf 'GIF89a\001\000\001\000\000\000' ;; txt) printf 'hello world 1234' ;; esac > "$1"; }

if stat -c '%s %Y' /dev/null >/dev/null 2>&1; then
for v in $TREES; do
    L=host/$v/boot/lib
    D=$T/$v; SYS=$D/sys; VD=$D/vd; W=$D/w; X=$W/kfb
    mkdir -p "$SYS/data/media/0/Screensaver" "$VD/screensaver" "$W" "$X/ctl" "$D/bin"
    LOGF=$D/log
    cat > "$D/bin/fbink" <<'EOF'
#!/bin/sh
# 假 fbink：-e 打印几何；画图时记下参数，文件名里有 bad 的画不出来
[ "$1" = -e ] && { echo 'viewWidth=1272;viewHeight=1696;screenWidth=1272'; exit 0; }
for a; do case "$a" in *bad*) exit 1 ;; esac; done
echo "$*" >> "$FBLOG"; exit 0
EOF
    chmod 755 "$D/bin/fbink"
    export FBLOG=$D/fb.log
    # saver.sh / sleep.sh 用到的东西：t、FBINK、SYS、VD、W、X
    env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" FBLOG="$FBLOG" sh -c "
        t() { echo \"\$*\" >> '$LOGF'; }
        . $L/saver.sh; . $L/sleep.sh
        for n in a.png B.PNG c.JPG d.jpeg e.webp f.WEBP g.bmp h.GIF i.heic j.jfif; do saver_is_img \$n || echo \"FAIL $v: \$n not an image\"; done
        for n in .x.png note.txt png x.pdf; do saver_is_img \$n && echo \"FAIL $v: \$n counted as an image\"; done
        true" | grep FAIL && fail=1
    sd=$SYS/data/media/0/Screensaver; vd=$VD/screensaver
    mkimg "$sd/photo.JPG" jpg; mkimg "$sd/pic.webp" webp; mkimg "$sd/phone.heic" heic; mkimg "$vd/renamed.png" jpg
    mkimg "$vd/old.bmp" bmp; mkimg "$vd/anim.gif" gif; mkimg "$vd/fake.jpg" txt; mkimg "$vd/clear.png" pnga; mkimg "$vd/bad.png" png
    mkimg "$vd/cut.jpg" cutjpg; mkimg "$vd/default.png" png; echo note > "$vd/把屏保图片放这里.txt"
    r=$(env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" FBLOG="$FBLOG" sh -c "
        t() { echo \"\$*\" >> '$LOGF'; }
        . $L/saver.sh
        for f in '$sd/photo.JPG' '$sd/pic.webp' '$sd/phone.heic' '$vd/renamed.png' '$vd/old.bmp' '$vd/anim.gif' '$vd/fake.jpg'; do saver_kind \"\$f\"; printf '%s=%s ' \"\${f##*/}\" \"\$skind\"; done")
    [ "$r" = "photo.JPG=jpeg pic.webp=webp phone.heic=heic renamed.png=jpeg old.bmp=bmp anim.gif=gif fake.jpg= " ] || F "$v: saver_kind: $r"
    # 转好的灰度图：.src 对得上才用
    mkdir -p "$sd/.vd-cache"; mkimg "$sd/.vd-cache/sd-pic.webp.png" png
    stat -c '%s %Y' "$sd/pic.webp" > "$sd/.vd-cache/sd-pic.webp.png.src"
    mkimg "$sd/.vd-cache/vd-old.bmp.png" png; echo "1 1" > "$sd/.vd-cache/vd-old.bmp.png.src"     # 过期
    r=$(env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" sh -c "
        t() { :; }
        . $L/saver.sh
        for f in '$sd/pic.webp' '$sd/phone.heic' '$vd/old.bmp' '$sd/photo.JPG' '$vd/fake.jpg'; do saver_resolve \"\$f\"; printf '%s ' \"\${sdraw#$SYS/data/media/0/}\"; done")
    case "$r" in "Screensaver/.vd-cache/sd-pic.webp.png  $vd/old.bmp Screensaver/photo.JPG  ") ;; *) F "$v: saver_resolve: [$r]" ;; esac
    # 轮换：10 次休眠，heic / 假 jpg / bad.png 跳过，webp 画转好的，透明 PNG 不清屏
    : > "$LOGF"; : > "$FBLOG"
    env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" FBLOG="$FBLOG" sh -c "
        t() { echo \"\$*\" >> '$LOGF'; }
        . $L/saver.sh; . $L/sleep.sh
        q_=0; while [ \$q_ -lt 10 ]; do screensaver_show; q_=\$((q_ + 1)); done"
    grep -q 'sd-pic.webp.png' "$FBLOG" || F "$v: converted webp not drawn"
    grep -q "photo.JPG" "$FBLOG" || F "$v: upper-case .JPG not drawn"
    grep -q "renamed.png" "$FBLOG" || F "$v: jpeg named .png not drawn"
    grep -q "old.bmp" "$FBLOG" && grep -q "anim.gif" "$FBLOG" || F "$v: bmp / gif not drawn"
    grep -q "phone.heic\|fake.jpg\|default.png\|cut.jpg" "$FBLOG" && F "$v: heic / non-image / cut-short jpeg / default.png drawn"
    grep -q "skipped .*cut.jpg (jpeg file is cut short)" "$LOGF" || F "$v: cut-short jpeg not reported"
    grep "clear.png" "$FBLOG" | grep -q -- ' -c ' && F "$v: transparent png cleared the page"
    grep "photo.JPG" "$FBLOG" | grep -q -- ' -c ' || F "$v: opaque image drawn without clearing"
    grep -q "skipped .*phone.heic (heic: this format cannot be shown" "$LOGF" || F "$v: no log line for the skipped heic"
    grep -q "fbink could not draw .*bad.png" "$LOGF" || F "$v: no log line for the failed draw"
    grep -q "pic.webp (converted copy)" "$LOGF" || F "$v: log does not say the converted copy was used"
    [ "$(grep -c "^screensaver: [^sf]" "$LOGF")" -ge 10 ] || { F "$v: not every sleep drew an image"; cat "$LOGF"; }
    # 只用一张：那张是 heic（用不了）→ 退回 Kindle 自带 / default.png，不留黑屏
    printf 'mode=one\nfile=sd/phone.heic\n' > "$sd/.vd-saver"; : > "$FBLOG"
    env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" FBLOG="$FBLOG" sh -c "t() { :; }; . $L/saver.sh; . $L/sleep.sh; screensaver_show"
    grep -q "default.png\|bg_ss" "$FBLOG" || F "$v: unusable single image does not fall back"
    rm -f "$sd/.vd-saver"
    # saver list
    head -c 40000000 /dev/zero > "$vd/huge.jpg"; touch -d '2020-01-02 03:04:05' "$vd/old.bmp"
    mkdir -p "$D/us";
    env SYS="$SYS" VD="$VD" W="$W" X="$X" FBINK="$D/bin/fbink" sh -c "t() { :; }; . $L/saver.sh; saver_cmd list"
    [ -f "$X/saver/old.bmp" ] && [ -f "$X/saver/anim.gif" ] && [ -f "$X/saver/renamed.png" ] || F "$v: saver list misses bmp / gif"
    [ "$(stat -c %Y "$X/saver/old.bmp")" = "$(stat -c %Y "$vd/old.bmp")" ] || F "$v: saver list does not keep the modification time"
    [ -f "$X/saver/huge.jpg" ] && F "$v: 40 MB file exported"
    grep -q "^huge.jpg	40000000$" "$X/saver/.skipped" || F "$v: .skipped: $(cat "$X/saver/.skipped")"
    [ "$(cat "$X/saver/.panel")" = "1272 1696" ] || F "$v: .panel"
    [ -f "$X/saver/default.png" ] && F "$v: default.png exported"
    [ -f "$X/ctl/saver.listed" ] || F "$v: saver.listed"
    rm -f "$vd/huge.jpg"
done
else
    echo "no stat -c here (Mac): host part skipped, run it on Linux"
fi

# ---- VeraHome ----
grep -q 'SaverFormat.isCandidate' "$J/ScreensaverActivity.java" || F "picker still filters by png / jpg"
grep -q 'SaverImage.convert' "$J/ScreensaverActivity.java" || F "picker does not convert"
grep -q '这张图用不了' "$J/ScreensaverActivity.java" || F "picker does not explain unusable images"
grep -q '\.skipped' "$J/ScreensaverActivity.java" || F "picker ignores the too-big list"
grep -q 'ExifInterface' "$J/SaverImage.java" || F "EXIF orientation not applied"
grep -q 'import android\.' "$J/SaverFormat.java" && F "SaverFormat.java must stay plain Java (tests-jvm)"
grep -q 'jpg / png）' "$J/ScreensaverActivity.java" && F "picker text still says jpg / png only"
if command -v javac >/dev/null 2>&1 && javac -version >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
    o=$T/jvm; mkdir -p $o
    javac -encoding UTF-8 -nowarn -d $o $J/SaverFormat.java $H/tests-jvm/com/veradroid/home/SaverFormatTest.java 2>&1 | grep -v '^Note'
    java -Djava.awt.headless=true -cp $o com.veradroid.home.SaverFormatTest || fail=1
else
    echo "no JDK here: JVM test skipped"
fi
[ $fail = 0 ] && echo "saver-formats: ok"
exit $fail
