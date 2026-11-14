#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline installer must not require the bootstrap API/bundle download.
set -u
B=cloud/static/bootstrap.sh
O=cloud/static/VeraDroid-Offline.sh
fail=0
[ -f "$O" ] || { echo 'FAIL offline launcher'; fail=1; }
grep -q 'VD_BUNDLE' "$O" || { echo 'FAIL launcher bundle env'; fail=1; }
grep -q 'VD_BUNDLE' "$B" || { echo 'FAIL bootstrap bundle env'; fail=1; }
grep -q '使用离线整包' "$B" || { echo 'FAIL offline label'; fail=1; }
grep -q 'offline=1' "$B" || { echo 'FAIL offline branch'; fail=1; }
[ "$fail" = 0 ] && echo 'OFFLINE PACKAGE OK' || echo 'OFFLINE PACKAGE FAILURES'
exit "$fail"
