#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Fetch the verified Kobo Libra Colour (N428 / Linux 4.9.77) kernel modules
# used by the release packages, and verify their SHA-256 sums.
#
# Usage:
#   sh tools/kobo/fetch-libra-colour-kmod.sh [OUT_DIR]
#   # default OUT_DIR: host/kobo/kmod/4.9.77
#
# The files come from lyoe/Koboweread-Colour (GPL-2.0 kernel modules, sources in
# that repository and in Rakuten Kobo's published kernel tree). Pinned commit
# keeps the binaries reproducible. Never mix modules across kernel versions.
set -eu

TOP=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT=${1:-$TOP/host/kobo/kmod/4.9.77}
REPO=lyoe/Koboweread-Colour
REV=3d8653eca2cbc75106e7daaa88689f80e30558a1
URL="https://raw.githubusercontent.com/$REPO/$REV/kernels/4.9.77"

FETCH=curl
command -v curl >/dev/null 2>&1 || FETCH=wget
fetch() { # url out
    if [ "$FETCH" = curl ]; then curl -fsSL --retry 3 -o "$2" "$1"; else wget -qO "$2" "$1"; fi
}

mkdir -p "$OUT"
tmp=$(mktemp -d 2>/dev/null || echo "$OUT/.fetch.$$")
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching Libra Colour 4.9.77 modules from $REPO@$REV ..."
for f in SHA256SUMS binder_linux.ko kobo_madvise.ko kobo_pagecache.ko; do
    fetch "$URL/$f" "$tmp/$f"
done

# Verify in a scratch directory so a tampered download never lands in the tree.
( cd "$tmp" && shasum -a 256 -c SHA256SUMS 2>/dev/null || sha256sum -c SHA256SUMS )

for f in binder_linux.ko kobo_madvise.ko kobo_pagecache.ko SHA256SUMS; do
    cp "$tmp/$f" "$OUT/$f"
done
echo 4.42.23303 > "$OUT/firmware"
[ -f "$OUT/README.md" ] || cp "$TOP/host/kobo/kmod/4.9.77/README.md" "$OUT/README.md" 2>/dev/null || true

echo "OK: installed Libra Colour modules into $OUT"
ls -l "$OUT"
