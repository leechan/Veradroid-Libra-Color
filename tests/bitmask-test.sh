#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Regression test for the VeraDroid preflight bit decoder.
# 5.19.5 PW6: /proc/bus/input/devices -> pt_mt: B: ABS=2e18000 0, B: KEY=0
set -u
BPL=32
has_bit() {
    _bits=$1; _bit=$2
    _widx=$((_bit / BPL)); _boff=$((_bit % BPL))
    set -- $_bits
    _pos=$(($# - _widx))
    [ "$_pos" -ge 1 ] || return 1
    eval _w=\${$_pos}
    [ -n "${_w:-}" ] || return 1
    [ $(( (0x${_w} >> _boff) & 1 )) -eq 1 ]
}
fail=0
check() { # mask bit expected
    if has_bit "$1" "$2"; then got=1; else got=0; fi
    if [ "$got" = "$3" ]; then
        printf 'ok   mask=%-12s bit=%-3s = %s\n' "$1" "$2" "$got"
    else
        printf 'FAIL mask=%-12s bit=%-3s expected %s got %s\n' "$1" "$2" "$3" "$got"
        fail=1
    fi
}
# Bits present in 0x2e18000 as the high 32-bit word.
for b in 47 48 53 54 55 57; do check '2e18000 0' "$b" 1; done
for b in 15 16 21 22 23 25 46 49 50 51 52 56 58 330; do check '2e18000 0' "$b" 0; done
# KEY=0 has no BTN_TOUCH (330).
check '0' 330 0
# Empty/absent capability.
check '' 53 0
exit "$fail"
