#!/bin/sh
# Installer firmware floor (cloud/static/bootstrap.sh): PW5 from 5.16 (all 5.16.x, armhf and soft-float armel, owner 2026-11-19);
# below 5.17 the kernel must have binder; other models still need 5.17.
cd "$(dirname "$0")/.." || exit 2
T=${TMPDIR:-/tmp}/vd-oldfw.$$; mkdir -p $T; trap 'rm -rf $T' EXIT
awk '/fwmin=5017000; fwmin_s=5.17/ { on = 1 } on { print } on && /没有 binder，VeraDroid 不能运行/ { getline; print; exit }' cloud/static/bootstrap.sh |
    sed -e "s#/proc/misc#$T/misc#g" -e "s#/dev/binder#$T/binder#g" > $T/gate.sh
grep -q 'fwmin=5016000' $T/gate.sh || { echo "FAIL: firmware block not found"; exit 1; }
fail=0
run() { # model fw binder(1|0) want(ok|old|nobinder)
    if [ "$3" = 1 ]; then echo '123 binder' > $T/misc; else : > $T/misc; fi
    got=$(MODEL=$1 FW=$2 sh -c 'die() { echo "$*"; exit 1; }; fwn=$(printf "%s\n" "$FW" | awk -F. "{printf \"%d%03d%03d\", \$1, \$2, \$3}"); . '$T/gate.sh'; echo OK')
    case "$4:$got" in ok:OK|old:*太旧*|nobinder:*binder*) echo "ok   $1 $2 binder=$3 -> $4" ;; *) echo "FAIL $1 $2 binder=$3: $got"; fail=1 ;; esac
}
run pw5 5.16.2.1.1 1 ok
run pw5 5.16.21 1 ok
run pw5 5.16.21 0 nobinder
run pw5 5.15.1 1 old
run pw5 5.17.1 0 ok
run kt6 5.16.21 1 old
run pw6 5.19.5 1 ok
[ $fail = 0 ] && echo "pw5-oldfw: ok"; exit $fail
