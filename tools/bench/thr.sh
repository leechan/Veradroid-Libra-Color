#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# thr.sh <wait_ms> "<inject cmd>" [n]: per-thread CPU (ms) during one action, busiest first
W=/dev/shm/veradroid
snap() { for f in /proc/[0-9]*/task/[0-9]*/stat; do read -r l < $f 2>/dev/null || continue; echo "${f#/proc/} $l"; done | awk '{ split($1,a,"/"); i=index($0,") "); rest=substr($0,i+2); n=split(rest,b," "); name=substr($0, index($0,"(")+1, i-index($0,"(")-1); gsub(/ /,"_",name); print a[1], a[3], name, b[12]+b[13], b[10], b[16], b[17] }'; }
snap > /dev/shm/vdb/t1
[ -n "$2" ] && echo "$2" > $W/inject
usleep $(($1 * 1000))
snap > /dev/shm/vdb/t2
awk 'NR==FNR{c[$2]=$4; f[$2]=$5; next} {d=($4-c[$2])*10; if(d>=20) printf "%6d ms  majflt+%-5d prio=%s nice=%s  pid=%s tid=%s %s\n", d, $5-f[$2], $6, $7, $1, $2, $3}' /dev/shm/vdb/t1 /dev/shm/vdb/t2 | sort -rn | head -${3:-14}
