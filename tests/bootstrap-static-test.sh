#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Static regression checks for bootstrap data-safety invariants.
set -u
B=${1:-cloud/static/bootstrap.sh}
fail=0
need() { grep -qE "$1" "$B" || { echo "FAIL missing: $2"; fail=1; }; }
forbid() { grep -qE "$1" "$B" && { echo "FAIL forbidden: $2"; fail=1; } || true; }

need 'if \[ ! -d "\$SYS/data/system/users/0" \]; then' 'user0 absence handling'
forbid '^[[:space:]]*export VD_FACTORY=1[[:space:]]*$' 'unconditional VD_FACTORY export'
need 'Only a factory install may discard PackageManager state' 'packages.xml factory-only comment'
need 'if \[ "\$\{VD_FACTORY:-0\}" = "1" \]; then' 'factory guard for package state'
need 'veradroid-device-id' 'stable device id path'
need 'data/media/0/.veradroid/device-id' 'Android-visible stable id'
need 'Migrate a pre-existing device id' 'device id migration'
need 'VD_EXPERIMENTAL' 'experimental model gate'
[ "$fail" = 0 ] && echo "BOOTSTRAP STATIC CHECKS OK" || echo "BOOTSTRAP STATIC FAILURES"
exit "$fail"
