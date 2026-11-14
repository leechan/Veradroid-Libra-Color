#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Auto-update must only move forward, keep working after an update, and not restart Android under the reader.
# (KT6 emulator 2026-11-08: an offline-installed 0.25 was silently downgraded to the live 0.24, and the updater
# then stopped for good because it read the version from a file the installer had moved.)
set -eu
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*"; exit 1; }
for A in host/pw6/boot/lib/auto-update.sh host/k49/boot/lib/auto-update.sh; do
grep -q '^ver_gt()' $A || fail "no version comparison"
grep -q 'if ! ver_gt "$new" "$cur"' $A || fail "updates on any difference (downgrades)"
grep -q '"$new" = "$cur"' $A && fail "old equality check still present"
grep -q 'after=$(cur_version)' $A || fail "post-update check reads the old version file"
grep -q '/dev/shm/veradroid/frozen' $A || fail "updates while Android is in the foreground"
# behaviour of ver_gt itself
eval "$(awk '/^ver_gt\(\)/,/^}/' $A)"
ver_gt 0.25 0.24 || fail "0.25 > 0.24"
! ver_gt 0.24 0.25 || fail "0.24 > 0.25"
! ver_gt 0.24 0.24 || fail "0.24 > 0.24"
ver_gt 0.21.41 0.21.9 || fail "0.21.41 > 0.21.9"
ver_gt 1.0 0.99 || fail "1.0 > 0.99"
sh -n $A || fail syntax
done
echo "autoupdate-test OK"
