#!/bin/sh
# VeraIME pinyin engine: static checks, plus the JVM unit tests (tests-jvm/) when a JDK is installed and assets/pinyin.dat is there

cd "$(dirname "$0")/.." || exit 2
M=android/packages/VeraIME
fail() { echo "FAIL: $*"; exit 1; }
DAT=1; [ -f $M/assets/pinyin.dat ] || { DAT=; echo "assets/pinyin.dat not generated: dictionary checks skipped"; }
[ -z "$DAT" ] || [ "$(head -c 4 $M/assets/pinyin.dat)" = VPY1 ] || fail "assets/pinyin.dat missing or not VPY1"
[ -z "$DAT" ] || { sz=$(wc -c < $M/assets/pinyin.dat); [ "$sz" -lt 6000000 ] || fail "pinyin.dat $sz bytes (keep the APK small)"; }
grep -q 'LOCAL_AAPT_FLAGS := -0 .dat' $M/Android.mk || fail "pinyin.dat must be stored uncompressed (it is mapped)"
grep -q 'LGPL-2.1-or-later' $M/assets/NOTICE-pinyin.txt || fail "NOTICE-pinyin.txt without the data licence"
grep -q 'fb75a179065e690dfc4559ce1807cbaf4fbe4f0111a5005615be9f435e6b9d76' tools/ime/gen_pinyin_dict.py || fail "generator does not pin its sources"
grep -q 'pinyin.tsv' $M/src/com/veradroid/ime/*.java && fail "the old pinyin.tsv is still referenced"
grep -q '"HINT 2500 5' $M/src/com/veradroid/ime/VeraImeService.java || fail "IME close HINT (0.96) lost"
grep -q 'HorizontalScrollView' $M/src/com/veradroid/ime/*.java && fail "candidate bar must page, not scroll"
grep -qE 'Animat|ValueAnimator' $M/src/com/veradroid/ime/*.java && fail "no animations in the IME"
if [ -n "$DAT" ] \&\& command -v javac >/dev/null 2>&1 && javac -version >/dev/null 2>&1; then
    o=${TMPDIR:-/tmp}/vd-ime-jvm.$$; rm -rf $o; mkdir -p $o
    javac -encoding UTF-8 -nowarn -d $o $M/src/com/veradroid/ime/PinyinDict.java $M/src/com/veradroid/ime/PinyinDecoder.java \
        $M/src/com/veradroid/ime/UserDict.java $M/src/com/veradroid/ime/KeyGrid.java $M/tests-jvm/com/veradroid/ime/*.java 2>&1 | grep -v '^Note' 
    java -cp $o com.veradroid.ime.DecoderTest $M/assets/pinyin.dat; rc=$?; rm -rf $o; [ $rc = 0 ] || fail "DecoderTest"
else
    echo "no JDK or no dictionary here: JVM tests skipped"
fi
echo "ime-decoder: ok"
