#!/bin/sh
# host/legacy/boot/lib/compile.sh, COMPILE_RUNNING (compile_nocode): an app that has no usable compiled code (interpret-only /
# no odex / Android said its odex is not usable) is compiled even while it is in front; an app with good code is still left
# alone until it leaves the front; COMPILE_RUNNING=0 is the old behaviour. Android, installd and dex2oat are stubbed:
# "cmd package compile" writes a speed odex after a second.
cd "$(dirname "$0")/.." || exit 2
fail() { echo "FAIL: $*"; exit 1; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
odex() { # pkg filter
    mkdir -p $T/sys/data/app/$1-1/oat/arm
    printf 'oat\n\0compiler-filter\0%s\0' "$2" > $T/sys/data/app/$1-1/oat/arm/base.odex
}
run() { # name, env..., then the shell body
    n=$1; shift
    rm -rf $T/w; mkdir -p $T/w/kfb/ctl
    env W=$T/w X=$T/w/kfb SYS=$T/sys VD=$T/vd "$@" sh -c '
        . host/legacy/boot/lib/compile.sh
        t() { echo "[t] $*" >> $W/log; }
        alive() { [ "$1" = "$W/pid" ]; }; lowmem_ram() { return 0; }; mem_avail_mb() { echo 300; }
        compile_held() { return 1; }; compile_battery_ok() { return 0; }
        adb_sh() {
            case "$1" in
                *"cmd package compile -m speed -f com.slow"*) rm -f $SYS/data/app/com.slow-1/oat/arm/base.odex; sleep 5 ;;
                *"cmd package compile -m speed -f "*) p=${1##* }; sleep 1; mkdir -p $SYS/data/app/$p-1/oat/arm
                    printf "oat\n\0compiler-filter\0speed\0" > $SYS/data/app/$p-1/oat/arm/base.odex; echo Success ;;
                *"cmd package compile -m speed-profile -f "*|*"cmd package compile -m interpret-only -f "*)
                    set -- $1; f=$5; p=$7; mkdir -p $SYS/data/app/$p-1/oat/arm
                    printf "oat\n\0compiler-filter\0%s\0" "$f" > $SYS/data/app/$p-1/oat/arm/base.odex; echo Success ;;
                getprop*) echo "" ;;
            esac; }
        '"$BODY" > $T/out.$n 2>&1
}
export APP_COMPILE=speed
# 1. in front, interpret-only: compiled now
odex com.a interpret-only
BODY='echo com.a > $X/fg; touch $W/lastinput; echo "com.a force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 6; kill $wp 2>/dev/null; cat $W/log' run 1
grep -q 'com.a -m speed -> ok (had no usable code: compiled while in use)' $T/out.1 || fail "interpret-only app in front was not compiled: $(cat $T/out.1)"
# 2. in front, speed odex but Android said it is not usable (marker): compiled now
odex com.b speed
BODY='echo com.b > $X/fg; : > $W/compile.nocode.com.b; echo "com.b force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 6; kill $wp 2>/dev/null; cat $W/log; ls $W' run 2
grep -q 'com.b -m speed -> ok (had no usable code' $T/out.2 || fail "app with unusable odex in front was not compiled: $(cat $T/out.2)"
grep -q 'compile.nocode.com.b' $T/out.2 && fail "marker not removed after a good compile"
# 3. in front with good code, forced recompile: waits for it to leave the front
odex com.c speed
BODY='echo com.c > $X/fg; echo "com.c force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 4; kill $wp 2>/dev/null; cat $W/log; cat $X/ctl/compile.status' run 3
grep -q 'code=foreground' $T/out.3 && ! grep -q 'com.c -m speed' $T/out.3 || fail "app with good code in front was compiled: $(cat $T/out.3)"
# 4. COMPILE_RUNNING=0: the interpret-only app in front waits too
odex com.d interpret-only
BODY='echo com.d > $X/fg; echo "com.d force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 4; kill $wp 2>/dev/null; cat $W/log; cat $X/ctl/compile.status' run 4 COMPILE_RUNNING=0
grep -q 'code=foreground' $T/out.4 && ! grep -q 'com.d -m speed' $T/out.4 || fail "COMPILE_RUNNING=0 compiled an app in front: $(cat $T/out.4)"
# 5. speed does not finish (COMPILE_MAX_S): with a JIT profile it falls back to speed-profile, without one to interpret-only
if [ -r /proc/uptime ]; then
    odex com.slow interpret-only; mkdir -p $T/sys/data/misc/profiles/cur/0/com.slow; echo prof > $T/sys/data/misc/profiles/cur/0/com.slow/primary.prof
    BODY='pgrep() { :; }; echo "com.slow force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 9; kill $wp 2>/dev/null; cat $W/log' run 5 COMPILE_MAX_S=3
    grep -q 'com.slow restored to speed-profile (speed-profile)' $T/out.5 || fail "timeout with a profile: no speed-profile fallback: $(cat $T/out.5)"
    rm -rf $T/sys/data/misc/profiles/cur/0/com.slow; odex com.slow interpret-only
    BODY='pgrep() { :; }; echo "com.slow force" > $W/compile.queue; (compile_worker) & wp=$!; sleep 9; kill $wp 2>/dev/null; cat $W/log' run 6 COMPILE_MAX_S=3
    grep -q 'com.slow restored to interpret-only (interpret-only)' $T/out.6 || fail "timeout without a profile: not interpret-only: $(cat $T/out.6)"
fi
grep -q 'COMPILE_RUNNING=auto' host/legacy/boot/lib/settings.sh || fail "settings.sh: COMPILE_RUNNING default missing"
echo "compile-nocode: ok"
