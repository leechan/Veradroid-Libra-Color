#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Static check that the host and Android layers agree on the persistent device id.
set -u
B=cloud/static/bootstrap.sh
J=android/packages/VeraHome/src/com/veradroid/home/Update.java
fail=0
grep -q 'veradroid-device-id' "$B" || { echo 'FAIL host stable path'; fail=1; }
grep -q 'data/media/0/.veradroid/device-id' "$B" || { echo 'FAIL media copy'; fail=1; }
grep -q 'Migrate a pre-existing device id' "$B" || { echo 'FAIL migration'; fail=1; }
grep -q 'data/media/0/.veradroid/device-id' "$J" || { echo 'FAIL app media read'; fail=1; }
grep -q 'veradroid-device-id' "$J" || { echo 'FAIL app host fallback'; fail=1; }
[ "$fail" = 0 ] && echo 'DEVICE ID CONTRACT OK' || echo 'DEVICE ID CONTRACT FAILURES'
exit "$fail"
