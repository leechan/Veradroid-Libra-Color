#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# cyc.sh <label> <cycles>: WeRead shelf <-> book cycles; paging counters and time to last refresh
W=/dev/shm/veradroid
one() { # name wait cmd
  v1=$(awk '/^(pgpgin|pswpin|workingset_refault_file|pgmajfault) /{a[$1]=$2} END{printf "%s %s %s %s ", a["workingset_refault_file"], a["pgpgin"], a["pgmajfault"], a["pswpin"]}' /proc/vmstat); c1=$(awk '/^cpu /{print $2+$3+$4+$7+$8, $6}' /proc/stat)
  l1=$(wc -l < $W/epd.log); i1=$(wc -l < $W/input.log)
  echo "$3" > $W/inject; usleep $(($2*1000))
  v2=$(awk '/^(pgpgin|pswpin|workingset_refault_file|pgmajfault) /{a[$1]=$2} END{printf "%s %s %s %s ", a["workingset_refault_file"], a["pgpgin"], a["pgmajfault"], a["pswpin"]}' /proc/vmstat); c2=$(awk '/^cpu /{print $2+$3+$4+$7+$8, $6}' /proc/stat)
  td=$(tail -n +$((i1+1)) $W/input.log | sed -n 's/^\[\([0-9]*\)\] inject.*/\1/p' | head -1)
  last=$(tail -n +$((l1+1)) $W/epd.log | awk -v td=$td '/epd: [0-9]+x/{t=substr($1,2)+0} END{print t-td}')
  echo "C $LAB $1 last=$last $(echo "$v1 $v2 $c1 $c2" | awk '{printf "refault=%d pgpgin_kb=%d majflt=%d swpin=%d busy_ms=%d iowait_ms=%d", $5-$1, $6-$2, $7-$3, $8-$4, ($11-$9)*10, ($12-$10)*10}')"
}
LAB=$1; n=0
while [ $n -lt $2 ]; do one back 5000 "swipe 636 1690 636 1300 120"; one open 7000 "tap 140 390"; n=$((n+1)); done
