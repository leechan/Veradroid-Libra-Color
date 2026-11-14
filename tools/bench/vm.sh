#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# vm.sh <wait_ms> "<inject>": paging activity during one action
v() { awk '/^(pgpgin|pswpin|pswpout|pgmajfault|pgfault|workingset_refault_file|workingset_refault_anon|pgsteal_kswapd|pgsteal_direct|allocstall_normal|allocstall_movable|pgscan_direct) /{printf "%s=%s ", $1, $2}' /proc/vmstat; awk '/^cpu /{printf "iowait=%s busy=%s idle=%s", $6, $2+$3+$4+$7+$8, $5}' /proc/stat; echo; }
a=$(v); echo "$2" > /dev/shm/veradroid/inject; usleep $(($1*1000)); b=$(v)
echo "$a" | tr ' ' '\n' > /dev/shm/vdb/v1; echo "$b" | tr ' ' '\n' > /dev/shm/vdb/v2
awk -F= 'NR==FNR{x[$1]=$2;next}{printf "%s+%d ", $1, $2-x[$1]} END{print ""}' /dev/shm/vdb/v1 /dev/shm/vdb/v2
grep -E "MemFree|MemAvailable|^Cached|SwapFree|Active\(file|Inactive\(file|Active\(anon|Inactive\(anon" /proc/meminfo | tr -s ' ' | tr '\n' ' '; echo
