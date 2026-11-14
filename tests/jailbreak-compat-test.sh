#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Environment fallbacks for different jailbreak packages.
set -u
B=cloud/static/bootstrap.sh
fail=0
for H in host/pw6 host/k49; do
V=$H/boot/veradroid.sh
C=$H/boot/lib/container.sh
grep -q '需要 root/越狱环境' "$B" || { echo 'FAIL root check'; fail=1; }
grep -q '缺少命令' "$B" || { echo 'FAIL command check'; fail=1; }
grep -q 'verify_sha' "$B" || { echo 'FAIL sha fallback'; fail=1; }
grep -q 'no fbink; continuing' "$V" || { echo "FAIL fbink removal ($H)"; fail=1; }
grep -q 'No FBInk' "$C" || { echo "FAIL framebuffer fallback ($H)"; fail=1; }
grep -q 'Restart scanner/stored before' $H/boot/lib/framework.sh || { echo "FAIL scanner-before-home ($H)"; fail=1; }
done
[ -f kual/VeraDroid/menu.json ] || { echo 'FAIL KUAL menu'; fail=1; }
[ -x kual/VeraDroid/start.sh ] || { echo 'FAIL KUAL start'; fail=1; }
[ -f kual/VeraDroid/config.xml ] && grep -q '<menu type="json"' kual/VeraDroid/config.xml || { echo 'FAIL KUAL config.xml (KUAL hides extensions without it)'; fail=1; }
[ -x kual/VeraDroid/install.sh ] || { echo 'FAIL KUAL install.sh'; fail=1; }
python3 -c "import json;json.load(open('kual/VeraDroid/menu.json'))" 2>/dev/null || { echo 'FAIL KUAL menu.json is not valid JSON'; fail=1; }
grep -q 'KUAL is an alternative' "$B" || { echo 'FAIL KUAL install'; fail=1; }
[ "$fail" = 0 ] && echo 'JAILBREAK COMPAT OK' || echo 'JAILBREAK COMPAT FAILURES'
exit "$fail"
