#!/bin/sh
# Per-app display profiles (host/*/boot/lib/appprof.sh, boot/appprofiles.conf, the fg / appset commands in cmd.sh):
# the three hosts carry the same files, the built-in table is well-formed, and the lookup / save logic behaves.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
for h in k49 legacy; do
    cmp -s host/pw6/boot/lib/appprof.sh host/$h/boot/lib/appprof.sh || fail "host/$h/boot/lib/appprof.sh differs from host/pw6"
    cmp -s host/pw6/boot/appprofiles.conf host/$h/boot/appprofiles.conf || fail "host/$h/boot/appprofiles.conf differs from host/pw6"
done
for h in pw6 k49 legacy; do
    c=host/$h/boot/lib/cmd.sh
    grep -q '\. "\$VD/boot/lib/appprof.sh"' $c || fail "$c does not source appprof.sh"
    grep -q 'fg)  *type appprof_fg' $c || fail "$c has no fg command"
    grep -q 'appset)  *type appprof_set' $c || fail "$c has no appset command"
    grep -q 'appprof_publish' host/$h/boot/veradroid.sh || fail "host/$h/boot/veradroid.sh does not publish the table"
    sh -n host/$h/boot/lib/appprof.sh || fail "syntax host/$h/boot/lib/appprof.sh"
done
# every rule: "<pkg>[*] KEY=v[;KEY=v]" with keys the host accepts, one rule per package
. host/pw6/boot/lib/appprof.sh
bad=$(grep -v '^[[:space:]]*\(#\|$\)' host/pw6/boot/appprofiles.conf | sed 's/[[:space:]]*#.*//' | while read -r p s rest; do
    [ -n "$rest" ] && { echo "extra field: $p"; continue; }
    pp=${p%\*}; appprof_valid_pkg "$pp" || { echo "bad package: $p"; continue; }
    printf '%s\n' "$s" | tr ';' '\n' | while read -r kv; do printf '%s\n' "$kv" | grep -Eq "$APPPROF_RE" || echo "bad setting $p: $kv"; done
done)
[ -z "$bad" ] || fail "appprofiles.conf: $bad"
dup=$(grep -v '^[[:space:]]*\(#\|$\)' host/pw6/boot/appprofiles.conf | awk '{print $1}' | sort | uniq -d)
[ -z "$dup" ] || fail "appprofiles.conf: duplicate $dup"
# behaviour, with the display bridge / settings mocked
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p $T/vd/boot $T/sys $T/w/kfb
cp host/pw6/boot/appprofiles.conf $T/vd/boot/
out=$(VD=$T/vd SYS=$T/sys W=$T/w X=$T/w/kfb sh -c '
    t() { :; }; settings_load() { :; }; epd_send() { echo "EPD $*" >> $W/epd; }
    . host/pw6/boot/lib/appprof.sh
    appprof_init
    appprof_fg com.tencent.weread.eink; echo "A $(tr "\n" ";" < $SYS/settings.app)"
    : > $W/epd; appprof_fg com.duokan.reader; echo "B $(wc -l < $W/epd | tr -d " ")"            # same profile: nothing sent
    appprof_fg org.mozilla.firefox; echo "C $(tr "\n" ";" < $SYS/settings.app)"                  # prefix rule
    appprof_fg com.example.none; echo "D $([ -f $SYS/settings.app ] && echo app || echo global)"
    appprof_set "com.duokan.reader|KFB_MODE=2;KFB_X=\$(reboot);KFB_FLASH=3"
    echo "E $(cat $SYS/settings.apps)"
    appprof_set "org.mozilla.firefox|-"; appprof_fg org.mozilla.firefox; echo "F $([ -f $SYS/settings.app ] && echo app || echo global)"
    echo "G $(grep "^org.mozilla.firefox " $X/appprof)"
    appprof_set "com.duokan.reader|"; appprof_fg com.duokan.reader; echo "H $(tr "\n" ";" < $SYS/settings.app)"
    appprof_set "bad;pkg|KFB_MODE=1"; echo "I $(grep -c bad $SYS/settings.apps)"
    appprof_set "*|"; echo "J $(wc -c < $SYS/settings.apps | tr -d " ")"
    appprof_fg home; echo "K $([ -f $SYS/settings.app ] && echo app || echo global)"
')
expect() { printf '%s\n' "$out" | grep -qxF "$1" || fail "expected '$1' in:
$out"; }
expect "A KFB_MODE=1;KFB_FLASH=6;"
expect "B 0"
expect "C KFB_SCROLLDU=300;"
expect "D global"
expect "E com.duokan.reader KFB_MODE=2;KFB_FLASH=3"
expect "F global"
expect "G org.mozilla.firefox u -"
expect "H KFB_MODE=1;KFB_FLASH=6;"
expect "I 0"
expect "J 0"
expect "K global"
echo "appprof: ok"
