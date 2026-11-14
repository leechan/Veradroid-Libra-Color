#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Offline integrity test for KPM packages/repo. Does not install anything.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
fail=0
# Only packages that are part of the source tree. A checkout can hold ignored leftovers under kpm/ (e.g. the removed
# kpm/pkg/veradroid-ssh with only a host key in it, see .gitignore): those are not packages and must not fail the test.
# In a git checkout the tracked files decide; without git (exported tree, busybox) every veradroid* directory counts.
pkg_dirs() {
    if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git -C "$REPO" ls-files -- 'kpm/pkg/veradroid*' | sed -n 's|^\(kpm/pkg/veradroid[^/]*\)/.*|\1|p' | sort -u | sed "s|^|$REPO/|"
    else
        for d in "$REPO"/kpm/pkg/veradroid*; do [ -d "$d" ] && echo "$d"; done
    fi
}
tracked() { # file: tracked by git (or no git to ask)
    command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
    [ -n "$(git -C "$REPO" ls-files -- "${1#$REPO/}")" ]
}
PKGS=$(pkg_dirs)
while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$d" ] || { echo "FAIL tracked package dir missing: $d"; fail=1; continue; }
    name=$(basename "$d")
    python3 - "$d/manifest.json" <<'PY' || fail=1
import json,sys
p=sys.argv[1]; d=json.load(open(p))
assert d['manifest_version']==2, p
assert d['id'] and d['name'] and d['version'], p
assert isinstance(d['supported_platforms'],list) and d['supported_platforms'], p
print('manifest ok', p)
PY
    sh -n "$d/install.sh" || { echo "FAIL syntax $d/install.sh"; fail=1; }
    if [ "$name" = veradroid ]; then
        grep -q 'Never factory-wipe' "$d/install.sh" || { echo 'FAIL upgrade factory guard'; fail=1; }
        grep -q 'export VD_FACTORY=1' "$d/install.sh" && { echo 'FAIL auto factory export'; fail=1; }
    fi
    sh -n "$d/launch.sh" || { echo "FAIL syntax $d/launch.sh"; fail=1; }
    pkg="$REPO/kpm/${name}_${VER:-}.kpkg"
    # Find the matching artifact by prefix rather than hard-coding a version.
    found=0
    for f in "$REPO"/kpm/"$name"_*.kpkg; do
        [ -f "$f" ] || continue
        tracked "$f" || continue
        found=1
        tar -tzf "$f" | grep -qx manifest.json || { echo "FAIL tar manifest $f"; fail=1; }
        tar -tzf "$f" | grep -qx install.sh || { echo "FAIL tar install $f"; fail=1; }
        tar -tzf "$f" | grep -qx launch.sh || { echo "FAIL tar launch $f"; fail=1; }
    done
    [ "$found" = 1 ] || { echo "FAIL no kpkg for $name"; fail=1; }
done <<EOF
$PKGS
EOF
[ -n "$PKGS" ] || { echo "FAIL no KPM packages found"; fail=1; }
[ "$fail" = 0 ] && echo "ALL KPM PACKAGES OK" || echo "KPM PACKAGE FAILURES"
exit "$fail"
