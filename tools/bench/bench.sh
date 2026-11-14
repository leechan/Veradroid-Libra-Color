#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid latency benchmark (runs on the Kindle host).
# usage: bench.sh <label> <runs> <wait_ms> "<inject cmd>" ["<inject cmd 2>" ...]   (commands are used in turn)
# One line per run:
#   R <label> <run> first=<ms touch-down -> first refresh sent> last=<ms -> last refresh sent> done=<ms -> panel done, or -> n=<refreshes>
#     frames=<frames Android posted> area=<sum of refreshed area, % of screen> wfm=<waveform:count,...>
#     app=<fg app cpu ms> sf=<surfaceflinger cpu ms> ss=<system_server cpu ms> epd=<cpu ms> busy=<% of both cores> majflt=<fg app major faults>
W=/dev/shm/veradroid; E=$W/epd.log; I=$W/input.log
label=$1; runs=$2; wait=$3; shift 3
ncmd=$#
pidof_cmd() { for p in /proc/[0-9]*; do c=$(tr '\0' ' ' < $p/cmdline 2>/dev/null); case "$c" in "$1"|"$1 "*) echo ${p#/proc/}; return;; esac; done; }
st() { # pid -> "cpu_ticks majflt"
  [ -n "$1" ] && [ -r /proc/$1/stat ] && sed 's/.*) //' /proc/$1/stat | awk '{print $12+$13, $10}' || echo "0 0"; }
cpu() { awk '/^cpu /{print $2+$3+$4+$6+$7+$8, $5+$6}' /proc/stat; }   # busy idle(+iowait)
SF=$(pidof_cmd /system/bin/surfaceflinger); SS=$(pidof_cmd system_server); EP=$(cat $W/epd.pid 2>/dev/null)
r=0
while [ $r -lt $runs ]; do
  n=$((r % ncmd + 1)); eval "c=\${$n}"
  fg=$(cat $W/kfb/fg 2>/dev/null); AP=$(pidof_cmd "$fg")
  l1=$(wc -l < $E); i1=$(wc -l < $I)
  a1=$(st $AP); s1=$(st $SF); y1=$(st $SS); e1=$(st $EP); c1=$(cpu)
  echo "$c" > $W/inject
  usleep $((wait * 1000))
  a2=$(st $AP); s2=$(st $SF); y2=$(st $SS); e2=$(st $EP); c2=$(cpu)
  td=$(tail -n +$((i1 + 1)) $I | sed -n 's/^\[\([0-9]*\)\] inject \(tap\|swipe\|down\).*/\1/p' | head -1)
  tail -n +$((l1 + 1)) $E | awk -v td="$td" -v lab="$label" -v r=$r -v a1="$a1" -v a2="$a2" -v s1="$s1" -v s2="$s2" -v y1="$y1" -v y2="$y2" -v e1="$e1" -v e2="$e2" -v c1="$c1" -v c2="$c2" '
    function d(a,b,k,  x,y){split(a,x," ");split(b,y," ");return y[k]-x[k]}
    /epd: frame/ { fr++ ; next }
    /panel done/ { t=substr($1,2)+0; dn=t-td; next }
    /epd: [0-9]+x[0-9]+\+/ { t=substr($1,2)+0; if(!n) first=t-td; last=t-td; n++
        split($3,g,/[x+]/); area+=g[1]*g[2]; w=$5; sub("wfm=","",w); f=$6; sub("full=","",f); wf[w (f==1?"F":"")]++ }
    END { s=""; for(k in wf) s=s (s==""?"":",") k ":" wf[k];
      busy=d(c1,c2,1); idle=d(c1,c2,2); tot=busy+idle; if(tot<1)tot=1
      printf "R %s %d first=%s last=%s done=%s n=%d frames=%d area=%.0f wfm=%s app=%d sf=%d ss=%d epd=%d busy=%.0f majflt=%d\n", lab, r, (n?first:"-"), (n?last:"-"), (dn?dn:"-"), n, fr, area*100/(1272*1696), (s==""?"-":s), d(a1,a2,1)*10, d(s1,s2,1)*10, d(y1,y2,1)*10, d(e1,e2,1)*10, busy*100/tot, d(a1,a2,2) }'
  r=$((r + 1))
done
