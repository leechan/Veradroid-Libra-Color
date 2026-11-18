#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# The in-app library must include the native Kindle documents bind and formats.
# The scan lives in Lib.java (process-wide index, one background worker); BookshelfActivity is only a redirect now.
set -u
cd "$(dirname "$0")/.."
B=android/packages/VeraHome/src/com/veradroid/home/Lib.java
fail=0
grep -q 'new File(Transfer.KINDLE),' "$B" || { echo 'FAIL native KindleLibrary root not scanned'; fail=1; }
grep -q 'Transfer.KINDLE + "/Downloads"' "$B" || { echo 'FAIL KindleLibrary/Downloads not scanned'; fail=1; }
grep -q 'endsWith(".kfx")' "$B" || { echo 'FAIL kfx not recognized'; fail=1; }
grep -qE 'newSingleThreadExecutor|Ui\.lowExecutor\(' "$B" || { echo 'FAIL scans are not serialized on one worker'; fail=1; }
grep -q 'if (scanning) { scanAgain' "$B" || { echo 'FAIL duplicate scan guard missing'; fail=1; }
grep -q 'if (differs\[0\])' "$B" || { echo 'FAIL unchanged-library render guard missing'; fail=1; }
grep -q 'seen.add(key)' "$B" || { echo 'FAIL the same file can be listed twice'; fail=1; }
[ "$fail" = 0 ] && echo 'LIBRARY SCAN OK' || echo 'LIBRARY SCAN FAILURES'
exit "$fail"
