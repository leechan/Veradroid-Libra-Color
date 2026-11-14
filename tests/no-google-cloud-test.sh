#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Google Drive/Cloud account integration is intentionally removed (since 2026-11-08).
set -u
fail=0
hit() {
    if grep -qiE "$2" "$1"; then echo "FAIL $(basename "$1"): $3"; fail=1; fi
}
A=android/packages/VeraHome
hit "$A/src/com/veradroid/home/Cloud.java" 'google|drive\.google|oauth' 'Google code remains in Cloud.java'
hit "$A/src/com/veradroid/home/Transfer.java" '/api/cloud|google|drive' 'cloud routes remain in Transfer.java'
hit "$A/src/com/veradroid/home/HomeActivity.java" 'Cloud\.|云盘|Google 云端' 'cloud UI remains in HomeActivity.java'
hit "$A/assets/web.html" 'cloud|Google|云端硬盘' 'cloud tab remains in transfer web UI'
hit "cloud/changelog.json" 'Google 云盘|Google Drive|云端硬盘' 'Google copy remains in changelog'
[ "$fail" = 0 ] && echo 'NO GOOGLE CLOUD OK'
exit "$fail"
