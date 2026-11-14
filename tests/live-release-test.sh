#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Live smoke test: OTA endpoint points at a downloadable APK with matching size/SHA.
set -u
BASE=${BASE:-https://veradroid.wenjin.jp}
TMP=${TMPDIR:-/tmp}/vd-ota-test.apk
json=$(curl -fsS "$BASE/api/ota/check?package=com.veradroid.home&version_code=0&version_name=test&device_id=selftest&model=PW6") || { echo "FAIL ota endpoint"; exit 1; }
url=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["url"])')
sha=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha256"])')
size=$(printf '%s' "$json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["size"])')
curl -fsSL "$url" -o "$TMP" || { echo "FAIL download"; exit 1; }
got_size=$(wc -c < "$TMP" | tr -d ' ')
got_sha=$(shasum -a 256 "$TMP" | cut -d' ' -f1)
rm -f "$TMP"
[ "$got_size" = "$size" ] || { echo "FAIL size got=$got_size want=$size"; exit 1; }
[ "$got_sha" = "$sha" ] || { echo "FAIL sha"; exit 1; }
echo "OK OTA $size bytes $sha"
