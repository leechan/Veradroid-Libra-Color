#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# OFFLINE SIMULATION of diagnostics/compat/veradroid_probe.sh and veradroid_preflight.sh.
# Nothing here touches a Kindle. Every result line is labelled SIMULATED; none of it is a real-device verification.
#
# - probe: run unmodified, only VERADROID_INPUT_DEVICES / VERADROID_BPL are set (the two inputs the script already reads).
# - preflight: firmware, framebuffer, /dev and /proc/misc paths are hard-coded in the script, so a COPY is made under
#   /tmp/vd-sim/<scenario>/ and only that copy has those paths rewritten into a fixture root. The production scripts are
#   never edited and are not taught to trust any new environment variable.
# - fixtures: tests/fixtures/input-devices.<model> (each file states its SOURCE: MEASURED / DERIVED / COMMENT / SYNTH),
#   copied to /tmp/input-devices.<model>.
#
# Usage: sh tests/sim-compat.sh            (SH=busybox\ sh to run the scripts under another shell)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(dirname "$HERE")
PROBE=$REPO/diagnostics/compat/veradroid_probe.sh
PRE=$REPO/diagnostics/compat/veradroid_preflight.sh
FIX=$HERE/fixtures
SIM=/tmp/vd-sim
SH=${SH:-sh}
fail=0

say()    { echo "SIMULATED $*"; }
expect() {  # label got want
    if [ "$2" = "$3" ]; then say "ok   $1: $2"; else say "FAIL $1: got '$2' want '$3'"; fail=1; fi
}

[ -f "$PROBE" ] && [ -f "$PRE" ] || { echo "missing probe/preflight under $REPO/diagnostics/compat" >&2; exit 2; }

# ---------------------------------------------------------------- 1. fixtures -> /tmp/input-devices.<model>
say "== 1. fixtures =="
for f in "$FIX"/input-devices.*; do
    m=${f##*/input-devices.}
    cp "$f" "/tmp/input-devices.$m"
    say "fixture /tmp/input-devices.$m  [$(head -1 "$f" | sed 's/^# //' | cut -c1-70)]"
done

# ---------------------------------------------------------------- 2. probe
# model bpl | touch_count touch_name btn_touch mt_slot mt_tracking prop_direct
say "== 2. probe (VERADROID_INPUT_DEVICES + VERADROID_BPL only) =="
while read -r m bpl want; do
    [ -n "$m" ] || continue
    out=$(VERADROID_INPUT_DEVICES=/tmp/input-devices.$m VERADROID_BPL=$bpl $SH "$PROBE" 2>&1)
    v() { printf '%s\n' "$out" | sed -n "s/^$1=//p" | tail -1; }
    got="$(v touch_count) $(v touch_name) btn=$(v touch_btn_touch) slot=$(v touch_mt_slot) track=$(v touch_mt_tracking) direct=$(v touch_prop_direct)"
    expect "probe $m BPL=$bpl" "$got" "$want"
done <<'EOF'
pw6-5.20.2            32 1 fts_ts btn=1 slot=1 track=1 direct=1
pw6-5.20.2            64 0 none btn=0 slot=0 track=0 direct=0
pw6-5.20.2-running    32 1 fts_ts btn=1 slot=1 track=1 direct=1
pt_mt-comment         32 1 pt_mt btn=0 slot=1 track=1 direct=0
synth-pt_mt-noslot    32 1 pt_mt btn=0 slot=0 track=1 direct=0
synth-no-tracking     32 1 fts_ts btn=1 slot=1 track=0 direct=1
synth-no-touch        32 0 none btn=0 slot=0 track=0 direct=0
synth-two-touch       32 2 synth_ts btn=1 slot=1 track=1 direct=1
synth-arm64-layout    64 1 fts_ts btn=1 slot=1 track=1 direct=1
synth-arm64-layout    32 0 none btn=0 slot=0 track=0 direct=0
EOF

# ---------------------------------------------------------------- 3. the real has_bit() from each script
# (tests/bitmask-test.sh tests its own copy of the function; this extracts the one the scripts actually run)
say "== 3. has_bit() extracted from the scripts =="
for s in "$PROBE" "$PRE"; do
    fn=$(awk '/^has_bit\(\) *\{/,/^}/' "$s")
    for c in "2618000 0:47:1" "2618000 0:48:1" "2618000 0:53:1" "2618000 0:54:1" "2618000 0:57:1" "2618000 0:55:0" \
             "2e18000 0:55:1" "400 0 0 0 0 0 0 0 0 0 0:330:1" "0:330:0" ":53:0" "2:1:1" "0:1:0"; do
        mask=${c%%:*}; rest=${c#*:}; bit=${rest%%:*}; want=${rest#*:}
        got=$(BPL=32 $SH -c "$fn
BPL=32; if has_bit \"\$1\" \"\$2\"; then echo 1; else echo 0; fi" x "$mask" "$bit")
        expect "has_bit[$(basename "$s")] '$mask' bit $bit" "$got" "$want"
    done
done
say "-- tests/bitmask-test.sh (existing):"
bt=$($SH "$HERE/bitmask-test.sh" 2>&1); btrc=$?
printf '%s\n' "$bt" | sed 's/^/SIMULATED   /'
expect "tests/bitmask-test.sh exit" "$btrc" 0

# ---------------------------------------------------------------- 4. preflight in a fixture root
# MEASURED /proc/misc of the user's PW6 (survey-20261105-224120.txt lines 253-271)
misc_real() { cat <<'EOF'
  0 touch
120 cpu_dma_latency
121 vndbinder
122 hwbinder
123 binder
239 uhid
236 device-mapper
130 watchdog
223 uinput
200 tun
162 frontlight
124 aed2
125 aed1
126 aed0
237 loop-control
183 hw_random
229 fuse
127 mdp_sync
EOF
}

# sandbox <name> <fw|none> <fb|none> "<dev nodes>" <misc: real|nobinder|ashmem>
sandbox() {
    SB=$SIM/$1
    case "$SB" in /tmp/vd-sim/*) ;; *) echo "bad sandbox path" >&2; exit 2 ;; esac
    [ -d "$SB" ] && find "$SB" -mindepth 1 -delete
    mkdir -p "$SB/etc" "$SB/sys/class/graphics" "$SB/dev" "$SB/dev/input" "$SB/proc/device-tree"
    printf 'amazon,sangria\0' > "$SB/proc/device-tree/compatible"
    [ "$2" = none ] || printf 'Kindle %s (~~otaVersion~~)\n' "$2" > "$SB/etc/prettyversion.txt"   # format as measured on PW6
    if [ "$3" != none ]; then mkdir -p "$SB/sys/class/graphics/fb0"; printf '%s\n' "$3" > "$SB/sys/class/graphics/fb0/virtual_size"; fi
    for n in $4; do : > "$SB/dev/$n"; [ "$n" = uinput ] && : > "$SB/dev/input/uinput"; done   # -e is all the script tests
    case "$5" in
        real)     misc_real ;;
        nobinder) misc_real | grep -v binder ;;
        ashmem)   misc_real; echo " 58 ashmem" ;;                                              # SYNTH
    esac > "$SB/proc/misc"
    sed -e "s|/etc/prettyversion.txt|$SB/etc/prettyversion.txt|g" \
        -e "s|/etc/version.txt|$SB/etc/version.txt|g" \
        -e "s|/sys/class/graphics/|$SB/sys/class/graphics/|g" \
        -e "s|/dev/input/uinput|$SB/dev/input/uinput|g" \
        -e "s|/dev/uinput|$SB/dev/uinput|g" \
        -e "s|/dev/binder|$SB/dev/binder|g" \
        -e "s|/dev/vndbinder|$SB/dev/vndbinder|g" \
        -e "s|/dev/ashmem|$SB/dev/ashmem|g" \
        -e "s|/proc/misc|$SB/proc/misc|g" \
        -e "s|/proc/device-tree/compatible|$SB/proc/device-tree/compatible|g" "$PRE" > "$SB/preflight.sh"
    # the copy must not read any host path the scenario is supposed to control
    left=$(grep -nE '(^|[^A-Za-z0-9_.-])/(etc|sys|dev|proc)/' "$SB/preflight.sh" | grep -v '/dev/null' | grep -v '/proc/bus/input/devices')
    [ -z "$left" ] || { say "FAIL sandbox $1 still reads host paths: $left"; fail=1; }
}

# scenario fixture fw fb nodes misc args | want_result want_rc  [note]
say "== 4. preflight (sandboxed copy) =="
N_PW6="binder hwbinder vndbinder"            # MEASURED on PW6: no /dev/uinput, no /dev/ashmem
while IFS='|' read -r name fx fw fb nodes misc args want; do
    [ -n "$name" ] || continue
    id=${name%% *}                                   # S01..: the sandbox dir must not contain spaces or '/dev/...' text
    case "$id" in S[0-9][0-9]) ;; *) echo "bad scenario id: $name" >&2; exit 2 ;; esac
    sandbox "$id" "$fw" "$fb" "$nodes" "$misc"
    # shellcheck disable=SC2086
    out=$(VERADROID_INPUT_DEVICES=/tmp/input-devices.$fx VERADROID_BPL=32 $SH "$SB/preflight.sh" --report $args 2>&1); rc=$?
    res=$(printf '%s\n' "$out" | sed -n 's/^RESULT=//p')
    why=$(printf '%s\n' "$out" | sed -n 's/^reason=//p')
    expect "preflight $name" "$res rc=$rc" "$want"
    [ -n "$why" ] && say "     reason=$why"
done <<EOF
S01 pw6-as-measured|pw6-5.20.2|5.20.2|1272,3392|$N_PW6|real||REFUSE rc=1
S02 pw6-as-measured+running|pw6-5.20.2-running|5.20.2|1272,3392|$N_PW6|real||REFUSE rc=1
S03 pw6+fw5.19.5|pw6-5.20.2|5.19.5|1272,3392|$N_PW6|real||REFUSE rc=1
S04 pw6+/dev/uinput|pw6-5.20.2|5.20.2|1272,3392|$N_PW6 uinput|real||REFUSE rc=1
S05 pw6+fw5.19.5+/dev/uinput|pw6-5.20.2|5.19.5|1272,3392|$N_PW6 uinput|real||EXPERIMENTAL rc=2
S06 S05+--force-experimental|pw6-5.20.2|5.19.5|1272,3392|$N_PW6 uinput|real|--force-experimental|EXPERIMENTAL rc=0
S07 pt_mt+fw5.19.5+uinput+ashmem|pt_mt-comment|5.19.5|1272,3392|$N_PW6 uinput ashmem|real||VERIFIED rc=0
S08 pt_mt+fw5.19.5+uinput,no-ashmem|pt_mt-comment|5.19.5|1272,3392|$N_PW6 uinput|real||EXPERIMENTAL rc=2
S09 pt_mt-noslot|synth-pt_mt-noslot|5.19.5|1272,3392|$N_PW6 uinput ashmem|real||EXPERIMENTAL rc=2
S10 no-firmware-file|pt_mt-comment|none|1272,3392|$N_PW6 uinput ashmem|real||EXPERIMENTAL rc=2
S11 fw5.16.0|pt_mt-comment|5.16.0|1272,3392|$N_PW6 uinput ashmem|real||REFUSE rc=1
S12 fb-1072x1448|pt_mt-comment|5.19.5|1072,1448|$N_PW6 uinput ashmem|real||REFUSE rc=1
S13 fb-1272x1696|pt_mt-comment|5.19.5|1272,1696|$N_PW6 uinput ashmem|real||VERIFIED rc=0
S14 no-fb|pt_mt-comment|5.19.5|none|$N_PW6 uinput ashmem|real||REFUSE rc=1
S15 no-touch|synth-no-touch|5.19.5|1272,3392|$N_PW6 uinput ashmem|real||REFUSE rc=1
S16 two-touch|synth-two-touch|5.19.5|1272,3392|$N_PW6 uinput ashmem|real||REFUSE rc=1
S17 no-tracking|synth-no-tracking|5.19.5|1272,3392|$N_PW6 uinput ashmem|real||EXPERIMENTAL rc=2
S18 no-binder-anywhere|pt_mt-comment|5.19.5|1272,3392|uinput ashmem|nobinder||REFUSE rc=1
S19 binder-only-in-proc-misc|pt_mt-comment|5.19.5|1272,3392|uinput ashmem|real||VERIFIED rc=0
S20 ashmem-only-in-proc-misc|pt_mt-comment|5.19.5|1272,3392|$N_PW6 uinput|ashmem||VERIFIED rc=0
EOF

# ---------------------------------------------------------------- 5. unmodified preflight on this host (no sandbox)
# Shows which branches fail only because this machine is not a Kindle (no fb, firmware file, /dev/uinput, binder).
say "== 5. unmodified preflight on this host (expected to REFUSE: host has no Kindle files) =="
out=$(VERADROID_INPUT_DEVICES=/tmp/input-devices.pw6-5.20.2 VERADROID_BPL=32 $SH "$PRE" --report 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/^/SIMULATED   host: /'
say "     host rc=$rc  firmware_file=$([ -f /etc/prettyversion.txt ] && echo yes || echo no) fb0=$([ -e /sys/class/graphics/fb0 ] && echo yes || echo no) /dev/uinput=$([ -e /dev/uinput ] && echo yes || echo no) /dev/binder=$([ -e /dev/binder ] && echo yes || echo no) /dev/vndbinder=$([ -e /dev/vndbinder ] && echo yes || echo no) /proc/misc=$([ -e /proc/misc ] && echo yes || echo no)"

echo
if [ "$fail" = 0 ]; then say "ALL CHECKS MATCH EXPECTATIONS (offline simulation only; nothing was verified on a device)"
else say "SOME CHECKS FAILED (see FAIL lines)"; fi
exit "$fail"
