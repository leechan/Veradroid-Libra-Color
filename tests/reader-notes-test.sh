#!/bin/sh
# Built-in reader: footnote popup (Epub.note / ReaderActivity.showNote). Static checks, plus the JVM test over synthetic
# EPUBs (tests/reader/gen_note_epubs.py: aside footnotes, a separate notes file with back links, relative and percent-encoded
# hrefs, <ol class="notes">, Duokan image markers, notes in an image alt, <br/> separated notes, endnotes outside the spine,
# contents links that must jump) when python3 and a JDK are installed.
cd "$(dirname "$0")/.." || exit 2
H=android/packages/VeraHome
S=$H/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }
need   "$S/Epub.java" 'static Note note\(Link k, String label, Chapter target, String frag\)' 'note text is decided in Epub (JVM-tested)'
need   "$S/Epub.java" 'k\.inline = alt' 'notes written in an image alt'
need   "$S/Epub.java" '\(k\.img \|\| k\.inline != null\)' 'only real image markers become empty-text links (not Duokan empty back links)'
need   "$S/ReaderActivity.java" 'Epub\.note\(k, label' 'the reader asks Epub.note'
need   "$S/ReaderActivity.java" 'else jumpTo\(ci, off\);' 'not a note / no text: jump on the first tap'
need   "$S/ReaderActivity.java" 'HostLink\.epd\("H R "' 'popup region gets a clean all-pixel refresh (bridge H hint)'
forbid "$S/ReaderActivity.java" 'HostLink\.epd\("H F "' 'H F flashes the whole screen (force_full), not the popup region'
need   "$S/ReaderActivity.java" 'if \(clean\) epdClean\(\);' 'and again when it closes'
need   "$S/ReaderActivity.java" 'bg\.setStroke\(st, Color\.BLACK\)' 'black border'
need   "$S/ReaderActivity.java" 'tv\.setTextColor\(Color\.BLACK\)' 'black note text'
forbid "$S/ReaderActivity.java" 'title\("注释"\)\.message' 'the note must not be a VeraDialog (dim layer, grey text, ghosting)'
forbid "$S/ReaderActivity.java" 'positive\("跳到注释处"' 'no intermediate "jump to note" box'
need   display/epd.c "line\[0\] == 'H' && line\[1\] == ' '" 'the bridge understands H <c> x y w h'
if command -v python3 >/dev/null 2>&1 && command -v javac >/dev/null 2>&1 && javac -version >/dev/null 2>&1; then
    o=${TMPDIR:-/tmp}/vd-note-jvm.$$; rm -rf $o; mkdir -p $o/epubs
    python3 tests/reader/gen_note_epubs.py $o/epubs || fail=1
    javac -encoding UTF-8 -nowarn -d $o $S/Epub.java $H/tests-jvm/com/veradroid/home/EpubNoteTest.java 2>&1 | grep -v '^Note'
    java -cp $o com.veradroid.home.EpubNoteTest $o/epubs || fail=1
    rm -rf $o
else
    echo "no python3 / JDK here: JVM test skipped"
fi
[ $fail = 0 ] && echo "reader-notes: ok"
exit $fail
