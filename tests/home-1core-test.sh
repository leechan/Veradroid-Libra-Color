#!/bin/sh
# Static checks for VeraHome on single-core / 512 MB devices (perf/home-1core). No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

# background work runs at background priority (one core: equal priority halves the UI thread)
need   "$S/Ui.java" 'THREAD_PRIORITY_BACKGROUND' 'Ui.lowPriority exists'
need   "$S/Lib.java" 'Ui\.lowExecutor\("lib"\)' 'library worker at background priority'
need   "$S/HomeActivity.java" 'Ui\.lowPriority\(\);' 'app list reload at background priority'
need   "$S/Theme.java" 'Ui\.lowPriority\(\);' 'wallpaper preparation at background priority'
# prebuild draws into one reused bitmap (not a new screen-size bitmap per page: LOS churn + GCs)
need   "$S/HomeActivity.java" 'private Bitmap warmBmp;' 'one shared warm bitmap'
forbid "$S/HomeActivity.java" 'Bitmap warm = Bitmap\.createBitmap' 'no per-page warm bitmap'
need   "$S/HomeActivity.java" 'touching\(\) \|\| android\.os\.SystemClock\.uptimeMillis\(\) - Perf\.start < 2000' 'prebuild yields to touches'
need   "$S/BlocksHome.java" 'Ui\.ONE_CORE \?' 'single core prebuilds the tabs only'
# apps: version bumps only on a real change; rendered icons cached on disk
need   "$S/HomeActivity.java" 'if \(!sameList\) appsGen\+\+;' 'apps version only on change'
need   "$S/HomeActivity.java" 'long appsVersion\(\) \{ return appsGen; \}' 'blocks pages key on appsGen'
need   "$S/HomeActivity.java" 'private Drawable cachedIcon\(' 'icon disk cache'
need   "$S/HomeActivity.java" 'if \(appsLoadedAt == 0\) reloadAfterFirstDraw\(\);' 'blocks: first app list read after the first frame'
# home page: changed cards are replaced in place; never during a gesture
need   "$S/BlocksHome.java" 'key == HOME && patchHome\(\)' 'home patches changed cards'
need   "$S/BlocksHome.java" 'if \(a\.touching\(\)\) \{ a\.afterTouch\(dataChangedLater\); return; \}' 'dataChanged waits for the finger'
need   "$S/BlocksHome.java" 'if \(a\.touching\(\)\) \{ a\.afterTouch\(appsChangedLater\); return; \}' 'appsChanged waits for the finger'
forbid "$S/BlocksHome.java" 'changed\(\) \{ if \(cur == HOME\) \{ show\(HOME\)' 'weather callback goes through dataChanged'
# cheap signatures / reads
need   "$S/Store.java" 'PREFS\.get\(name\)' 'Store.prefs caches instances'
need   "$S/Stats.java" 'bmMemo' 'bookmark count memoized'
need   "$S/HostLink.java" 'KV_CACHE' 'hot host files cached briefly'
need   "$S/PageScrollView.java" 'stopsGen == layoutGen' 'page stops cached between layouts'
# frame buffer sampling copies whole rows (not three get() per pixel)
need   "$S/BlocksCards.java" 'mb\.get\(line, 0, line\.length\)' 'bulk row reads in sampleFb'
forbid "$S/BlocksCards.java" 'mb\.get\(o \+ 1\)' 'no per-pixel buffer reads'
[ $fail = 0 ] && echo "home-1core: ok"
exit $fail
