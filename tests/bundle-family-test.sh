#!/bin/sh
# The installer tells a k49 bundle from a PW6 one by the bundle's manifest.json product (vd_bundle_k49 in bootstrap.sh):
# since 1.00 the PW6 bundle also ships bin/vdlmk (memkeep), which used to be the k49 marker (every PW6 install of the
# first 1.00 candidate stopped with code 30 "这个离线包是给 PW5 / KT5 / KT6 用的" on a test PW6).
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
sed -n '/^# BEGIN vd_bundle_k49/,/^# END vd_bundle_k49/p' cloud/static/bootstrap.sh > $T/f.sh
grep -q 'vd_bundle_k49()' $T/f.sh || { echo "FAIL: no vd_bundle_k49 block in bootstrap.sh"; exit 1; }
. $T/f.sh
fail=0; ck() { if [ "$2" = "$3" ]; then :; else echo "FAIL: $1: got $3, want $2"; fail=1; fi; }
b() { rm -rf $T/b; mkdir -p $T/b/bin; [ -n "$1" ] && printf '{"product": "%s", "version": "1.00"}\n' "$1" > $T/b/manifest.json; [ "$2" = lmk ] && : > $T/b/bin/vdlmk; vd_bundle_k49 $T/b && echo k49 || echo pw6; }
ck "pw6 1.00 (vdlmk + manifest)" pw6 "$(b veradroid-pw6 lmk)"
ck "pw6 0.99 (no vdlmk)" pw6 "$(b veradroid-pw6 '')"
ck "k49 family" k49 "$(b veradroid-k49 lmk)"
ck "k49-512 class" k49 "$(b veradroid-k49-512 lmk)"
ck "old bundle without manifest, vdlmk" k49 "$(b '' lmk)"
ck "old bundle without manifest, no vdlmk" pw6 "$(b '' '')"
[ $fail = 0 ] && echo "bundle-family: ok"
exit $fail
