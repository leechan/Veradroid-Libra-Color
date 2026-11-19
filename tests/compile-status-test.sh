#!/bin/sh
# Pre-compilation status text (host/pw6 + host/k49 boot/lib/compile.sh): every waiting / paused state says why in msg=
# (VeraHome's settings page and the transfer page show msg as is), and the "you are using the device" wait says when
# it starts (COMPILE_IDLE_S without a touch). The conditions themselves are not changed here.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
cmp -s host/pw6/boot/lib/compile.sh host/k49/boot/lib/compile.sh || fail "host/k49 compile.sh differs from host/pw6"
c=host/pw6/boot/lib/compile.sh
sh -n $c || fail "syntax $c"
n=$(grep -c 'compile_status state=\(waiting\|paused\) ' $c)
m=$(grep 'compile_status state=\(waiting\|paused\) ' $c | grep -v 'reason=off' | grep -c '"msg=')
[ "$n" -ge 9 ] || fail "only $n waiting / paused states"
[ "$m" = $((n - 1)) ] || fail "$((n - 1 - m)) waiting / paused states without msg="
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p $T/w
txt() { W=$T/w IDLE=$1 COMPILE_IDLE_S=${2:-300} sh -c '. '"$c"' 2>/dev/null; compile_idle_s() { echo $IDLE; }; compile_idle_wait_text'; }
for case in "999999 300 1" "0 300 5" "130 300 3" "299 300 1" "0 600 10" "130 600 8"; do
    set -- $case
    want="$(( $2 / 60 )) 分钟不碰屏幕后开始（还要约 $3 分钟）"
    [ "$(txt $1 $2)" = "$want" ] || fail "idle $1 s, COMPILE_IDLE_S=$2: '$(txt $1 $2)', want '$want'"
done
echo "compile-status: ok"
