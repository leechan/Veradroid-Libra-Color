#!/bin/sh
# Built-in reader: EPUB table of contents (Epub.java). Static checks, plus the JVM test over synthetic EPUBs
# (tests/reader/gen_epubs.py: 1200-chapter NCX / nav / both, nested volumes, anchors, truncated NCX, no TOC, Calibre split,
# percent-encoded names, spine longer than the TOC) when python3 and a JDK are installed.
cd "$(dirname "$0")/.." || exit 2
H=android/packages/VeraHome
S=$H/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }
forbid "$S/Epub.java" 'out\.size\(\) >= 120' 'the old 120-file cap is back'
forbid "$S/Epub.java" 'import android\.' 'Epub.java must stay plain Java (tests-jvm)'
need   "$S/Epub.java" 'static List<RawToc> parseNcx' 'NCX navMap is read'
need   "$S/Epub.java" 'static List<RawToc> parseNav' 'EPUB3 nav is read'
need   "$S/Epub.java" 'static List<TocItem> headings' 'heading fallback'
need   "$S/ReaderActivity.java" 'private void mapToc\(\)' 'TOC entries mapped to pages'
forbid "$S/ReaderActivity.java" 'titles\[i\] = chapters\.get\(i\)\.title' 'classic TOC must not list every file in one dialog'
need   "$S/ReaderActivity.java" 'tocNumberInput' 'long TOCs: jump to entry N'
forbid "$S/ReaderActivity.java" 'p\.text = trimEnd' 'pages must not keep a second copy of the text'
if command -v python3 >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 && javac -version >/dev/null 2>&1; then
    o=${TMPDIR:-/tmp}/vd-epub-jvm.$$; rm -rf $o; mkdir -p $o/epubs
    python3 tests/reader/gen_epubs.py $o/epubs 600 || fail=1
    javac -encoding UTF-8 -nowarn -d $o $S/Epub.java $H/tests-jvm/com/veradroid/home/EpubTocTest.java 2>&1 | grep -v '^Note'
    java -cp $o com.veradroid.home.EpubTocTest $o/epubs || fail=1
    rm -rf $o
else
    echo "no python3 / JDK here: JVM test skipped"
fi
[ $fail = 0 ] && echo "reader-toc: ok"
exit $fail
