#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Static regression checks for the VeraHome UI fixes of 2026-11-07 (user feedback). No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

# 1. status-bar chevron: the bar is 20dp high, Icons.bar() needs 32dp -> clipped triangle
forbid "$S/StatusBarService.java" 'Icons\.bar\(this, Icons\.Kind\.CHEV_D' 'status bar uses padded Icons.bar for the chevron (clipped)'
# the thin line chevron (2 px) looked broken on e-ink (user report 2026-11-08): it is a solid triangle now
need   "$S/StatusBarService.java" 'tri\.lineTo\(w / 2f, h\)' 'status bar chevron is a solid triangle'
need   "$S/StatusBarService.java" 'LayoutParams\(dp\(12\), dp\(6\)\)' 'status bar triangle fits the 20dp bar'
# 2. Send to Kindle tile was only an instruction dialog
forbid "$S/HomeActivity.java" 'inboxCell\(' 'Send to Kindle tile still on the home grid'
need   "$S/HomeActivity.java" 'items\.size\(\) \+ 2' 'two pinned tiles (store, stats)'
# 3. settings show what the host really uses
need   "$S/HomeActivity.java" 'FLASH_V = \{ "0", "1", "3", "6", "8",' 'KFB_FLASH=8 (host default) is a selectable value'
need   "$REPO/host/pw6/boot/lib/settings.sh" 'KFB_FLASH=8' 'host default flash'
# restore defaults sends KEY=default (no hard-coded values) so the host falls back to its own / the model's defaults
need   "$S/HomeActivity.java" 'RESET_KEYS = \{ "KFB_SETTLE", "KFB_MODE", "KFB_FLASH",' 'restore defaults covers the display settings'
need   "$S/HomeActivity.java" 'for \(String k : RESET_KEYS\) r\.append\(k\)\.append\("=default\\n"\)' 'restore defaults = host defaults (KEY=default)'
need   "$REPO/host/pw6/boot/lib/settings.sh" '\[ "\$v" = default \] \|\| echo "\$k=\$v"' 'host drops KEY=default back to its default'
need   "$S/HomeActivity.java" 'if \(BluetoothActivity\.supported\(\)\) action\(list, "蓝牙' 'bluetooth row only with bluetooth hardware'
need   "$S/HomeActivity.java" 'if \("size"\.equals\(key\)\) showSettings\(\); else vb\.setText' 'local choices update in place'
need   "$S/HomeActivity.java" 'iconCache' 'app icons are cached across redraws'
need   "$S/HomeActivity.java" 'appLabels' 'app labels are cached across redraws'
need   "$REPO/host/pw6/boot/lib/cmd.sh" 'VD_EXPERIMENTAL=1 ;; esac; B=/tmp/vd-fullupdate-bootstrap.sh; cd /;.* curl -fsSL [^;]*https://veradroid.wenjin.jp/bootstrap.sh -o "\$B"; then sh "\$B"' 'full update keeps the experimental model'
# 4. store and Google Drive are open to every device
forbid "$S/StoreActivity.java" 'showBind' 'store still asks for account binding'
forbid "$S/Cloud.java" 'api/cloud/allowed' 'Google Drive still checks account authorization'
# 5. library: no full re-scan + one redraw per book
need   "$S/Lib.java" 'private static final Map<String, Book> known' 'library keeps a process-wide book cache'
need   "$S/Lib.java" 'isLowRamDevice' 'low-RAM devices cap cover size'
need   "$S/Books.java" 'inJustDecodeBounds' 'large EPUB covers decode bounds first'
need   "$S/Books.java" 'inSampleSize' 'large EPUB covers are downsampled before decode'
need   "$S/Lib.java" 'fs\[i\]\.delete\(\)' 'cover disk cache is bounded'
need   "$S/Store.java" 'purgeLegacyCloud' 'old Google Drive tokens are purged'
forbid "$S/HomeActivity.java" 'Cloud\.' 'Google Drive cloud UI/code is gone'
need   "$S/LibraryPage.java" 'void refreshSoon\(\)' 'cover loads coalesce redraws'
# 6. new: clean background apps from the panel
need   "$S/Panel.java" 'haslight' 'panel honors haslight'
need   "$S/Panel.java" 'haswarmth' 'panel honors haswarmth'
need   "$S/Panel.java" 'hassleeptime' 'panel honors hassleeptime'
need   "$S/Panel.java" 'Cleaner\.run\(' 'panel has "clean background"'
need   "$S/Cleaner.java" 'p\.uid < Process\.FIRST_APPLICATION_UID' 'cleaner never touches system processes'
# 7. navigation mode: three-button bar reserves its strip via overscan
need   "$S/NavBarService.java" 'setOverscan' 'nav bar reserves the bottom strip (overscan)'
need   "$S/NavBarService.java" 'FLAG_LAYOUT_IN_OVERSCAN' 'nav bar can draw inside the overscan strip'
need   "$REPO/android/packages/VeraHome/AndroidManifest.xml" '\.NavBarService' 'nav bar service registered'
need   "$S/HomeActivity.java" 'navModeChoice\(list\)' 'navigation mode setting'
# 8. themes uploaded from the transfer page
need   "$S/Transfer.java" '"theme"\.equals\(to\)' 'transfer accepts theme uploads'
need   "$S/Transfer.java" '/api/theme/reset' 'theme reset endpoint'
need   "$S/Theme.java" 'name\.contains\("\.\."\)' 'theme zip rejects path traversal'
need   "$S/HomeActivity.java" 'Theme\.iconFile\(pkg\)' 'home uses themed icons'
need   "$S/StatusBarService.java" 'clockText' 'status bar avoids redundant clock invalidate'
need   "$S/HomeActivity.java" 'statusText' 'home avoids redundant status invalidate'
need   "$S/StatusBarService.java" 'Theme\.statusBar\(\)' 'status bar reads statusbar.json'
need   "$REPO/android/packages/VeraHome/assets/web.html" '/api/theme/' 'web page manages themes (wallpaper / icons)'
# 9. library hides the jailbreak marker
need   "$S/Lib.java" 'startsWith\("jailbroken"\)' 'JAILBROKEN.txt is not a book'
# 10. settings survive reboots: PackageManager wipes system-app data on every boot in this container
need   "$S/Store.java" '/data/media/0/\.vdhome/state' 'persistent state outside /data/data'
need   "$S/Store.java" 'Os\.chmod' 'state dir created 0700 in one step (no permission flapping)'
need   "$REPO/android/packages/VeraHome/AndroidManifest.xml" 'WRITE_MEDIA_STORAGE' 'media_rw gid so /data/media/0 is reachable at early boot'
for f in HomeActivity BookshelfActivity ReaderActivity Stats Token Update StatusBarService NavBarService Fonts; do
    grep -q 'getSharedPreferences(' "$S/$f.java" && { echo "FAIL $f.java still uses internal SharedPreferences"; fail=1; }
done
[ "$fail" = 0 ] && echo "HOME UI CHECKS OK"
exit $fail
