#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# One native-library entry after a successful install.
set -u
B=cloud/static/bootstrap.sh
O=cloud/static/VeraDroid-Offline.sh
I=cloud/static/VeraDroid.sh
fail=0
grep -q 'VD_INSTALLER' "$I" || { echo 'FAIL online installer env'; fail=1; }
grep -q 'VD_INSTALLER' "$O" || { echo 'FAIL offline installer env'; fail=1; }
grep -q 'VeraDroid.sh|VeraDroid-Experimental.sh|VeraDroid-Offline.sh' "$B" || { echo 'FAIL installer allowlist'; fail=1; }
grep -q 'VD_OFFLINE_BUNDLE' "$B" || { echo 'FAIL bundle cleanup'; fail=1; }
grep -q 'VD_HELPER' "$B" || { echo 'FAIL helper cleanup'; fail=1; }
grep -q 'VeraDroid 启动.sh' "$B" || { echo 'FAIL launcher preserved'; fail=1; }
[ "$fail" = 0 ] && echo 'INSTALLER CLEANUP OK' || echo 'INSTALLER CLEANUP FAILURES'
exit "$fail"
