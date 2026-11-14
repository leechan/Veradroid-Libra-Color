#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Ensure the emulator dry-run path and matrix documentation stay present.
set -u
B=cloud/static/bootstrap.sh
D=docs/eink-emulator.md
fail=0
grep -q 'VD_DRY_RUN' "$B" || { echo 'FAIL dry-run'; fail=1; }
grep -q '自检通过' "$B" || { echo 'FAIL dry-run output'; fail=1; }
[ -f "$D" ] || { echo 'FAIL emulator doc'; fail=1; }
grep -q '不能验证' "$D" || { echo 'FAIL limitations'; fail=1; }
grep -q 'pw5-5192' "$D" || { echo 'FAIL pw5 matrix'; fail=1; }
[ "$fail" = 0 ] && echo 'EMULATOR MATRIX OK' || echo 'EMULATOR MATRIX FAILURES'
exit "$fail"
