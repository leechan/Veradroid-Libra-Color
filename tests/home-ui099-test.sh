#!/bin/sh
# Static checks for the VeraHome 0.99 UI fixes (fix/ui-099). No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

# paged lists: last page check for both styles (classic paged into blank pages forever)
need   "$S/PageScrollView.java" 'if \(dir > 0 && y \+ h >= content - tailPad\) return false;' 'page() stops at the last page in both styles'
need   "$S/PageScrollView.java" 'int pages\(\) \{ return stops\(\)\.size\(\); \}' 'page count from the real page stops'
# Home keeps the device density (多看's forced density must not relaunch / enlarge Home) and says fg home itself
need   "$S/HomeActivity.java" 'DisplayMetrics\.DENSITY_DEVICE' 'Home pins its density'
need   "$S/HomeActivity.java" 'HostService\.foregroundHome\(\)' 'Home sends fg home on resume'
need   "$S/AppProf.java" 'HostService\.profPkg = pkg;' 'launching records the announced package'
need   "$S/BlocksHome.java" 'a\.touching\(\)' 'home rebuild waits for the finger to lift'
# wallpaper "去掉" asks first; the clear call sits inside the confirm runnable
need   "$S/HomeActivity.java" 'confirm\("不用壁纸？"' '去掉 wallpaper asks for confirmation'
forbid "$S/HomeActivity.java" 'onClick\(View v\) \{ Theme\.clearWallpaper\(\)' 'one tap clears the wallpaper'
# a style changed elsewhere (SettingsActivity over an app) is applied when Home comes back
need   "$S/HomeActivity.java" 'shownStyle\.equals\(styleName\(Blocks\.on\(this\)\)\)\) applyStyle' 'Home re-syncs the UI style on resume'
# reader footnotes
need   "$S/ReaderActivity.java" 'k\.back = type\.contains\("back"\)' 'back links jump, not pop up'
need   "$S/ReaderActivity.java" 'static String pctDecode' 'chapter entries and link targets percent-decoded alike'
need   "$S/ReaderActivity.java" 'k\.end <= k\.start && !k\.back' 'image-only note markers kept'
[ $fail = 0 ] && echo "home-ui099: ok"
exit $fail
