#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid on-device benchmark (runs on the Kindle host as root; busybox ash).
#   sh vdbench.sh boot                 cold start timeline (stops VeraDroid first, starts it, waits for Home)
#   sh vdbench.sh app <pkg> [n]        cold + warm launch times via `am start -W` (n cold runs, default 3)
#   sh vdbench.sh mem                  memory / swap / zram / top processes snapshot
#   sh vdbench.sh idle [seconds]       CPU used by the container and the host helpers while idle (default 60)
# Output is one "key=value" per line so runs can be diffed.
B=/mnt/base-us/veradroid/boot; W=/dev/shm/veradroid; LOG=/mnt/base-us/system/veradroid/veradroid.log
A="sh $B/ashell.sh"
up() { cut -d' ' -f1 /proc/uptime; }
since() { awk "BEGIN{printf \"%.1f\", $(up) - $1}"; }
wait_boot() { i=0; while [ $i -lt ${1:-300} ]; do [ "$($A 'getprop sys.boot_completed' 2>/dev/null)" = 1 ] && return 0; i=$((i+1)); sleep 1; done; return 1; }
case "${1:-}" in
boot)
    sh $B/stop.sh >/dev/null 2>&1; sleep 3
    echo "model=$(cat /mnt/base-us/system/veradroid/model 2>/dev/null) version=$(cat /mnt/base-us/veradroid/version 2>/dev/null) kernel=$(uname -r) memtotal_kb=$(awk '/MemTotal/{print $2}' /proc/meminfo)"
    n0=$(wc -l < $LOG); t0=$(up)
    sh $B/veradroid.sh home
    echo "launcher_returned_s=$(since $t0)"
    wait_boot 300 && echo "boot_completed_s=$(since $t0)" || echo "boot_completed_s=TIMEOUT"
    i=0; while [ $i -lt 60 ]; do $A 'dumpsys activity activities' 2>/dev/null | grep -q 'mResumedActivity.*veradroid.home' && break; i=$((i+1)); sleep 1; done
    echo "home_resumed_s=$(since $t0)"
    # host-side milestones (uptime stamps written by t())
    tail -n +$((n0+1)) $LOG | sed -n 's/^\[[0-9:]* up=\([0-9.]*\)\] \(.*\)/\1 \2/p' | awk -v t0=$t0 '{printf "host %6.1f  %s\n", $1 - t0, substr($0, index($0,$2))}' | cut -c1-110
    # Android boot_progress events (ms since kernel boot of the container's clock = host uptime)
    $A 'logcat -b events -d' 2>/dev/null | sed -n 's/.* I \(boot_progress[a-z_]*\): \([0-9]*\).*/\1 \2/p' | awk -v t0=$t0 '{printf "android %6.1f  %s\n", $2/1000 - t0, $1}'
    ;;
app)
    pkg=${2:?package}; n=${3:-3}
    act=$($A "cmd package resolve-activity --brief -c android.intent.category.LAUNCHER $pkg" 2>/dev/null | tail -1)
    case "$act" in */*) ;; *) echo "cannot resolve launcher activity of $pkg ($act)"; exit 1 ;; esac
    echo "activity=$act"
    i=0; while [ $i -lt $n ]; do i=$((i+1))
        $A "am force-stop $pkg"; sleep 2
        $A "am start -W -n $act" 2>/dev/null | awk -v i=$i '/ThisTime|TotalTime|WaitTime/{printf "cold%d_%s=%s ", i, tolower($1), $2} END{print ""}' | tr -d ':'
        sleep 4
        $A "input keyevent 3"; sleep 2
        $A "am start -W -n $act" 2>/dev/null | awk -v i=$i '/ThisTime|TotalTime|WaitTime/{printf "warm%d_%s=%s ", i, tolower($1), $2} END{print ""}' | tr -d ':'
        sleep 2
    done
    $A "dumpsys meminfo $pkg" 2>/dev/null | awk '/TOTAL/{print "pss_kb=" $2; exit}'
    $A "input keyevent 3"
    ;;
mem)
    awk '/MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|^Cached/{printf "%s=%s ", tolower($1), $2} END{print ""}' /proc/meminfo | tr -d ':'
    for z in /sys/block/zram*; do [ -e $z/disksize ] && echo "zram=$(basename $z) disksize_mb=$(( $(cat $z/disksize) / 1048576 )) $(awk '{printf "orig_mb=%d compr_mb=%d", $1/1048576, $2/1048576}' $z/mm_stat 2>/dev/null)"; done
    $A 'dumpsys meminfo' 2>/dev/null | sed -n '/Total PSS by process/,/Total PSS by OOM/p' | sed -n '2,16p'
    ;;
idle)
    s=${2:-60}; P=$(cat $W/pid)
    cpu() { # total jiffies of all processes in the container's pid namespace + host helpers
        ns=$(readlink /proc/$P/ns/pid); tot=0; hp=0
        for d in /proc/[0-9]*; do
            set -- $(cut -d' ' -f14,15 $d/stat 2>/dev/null) ; [ -n "${1:-}" ] || continue
            if [ "$(readlink $d/ns/pid 2>/dev/null)" = "$ns" ]; then tot=$((tot + $1 + $2))
            else case "$(tr '\0' ' ' < $d/cmdline 2>/dev/null)" in *veradroid*|*slirp4netns*) hp=$((hp + $1 + $2)) ;; esac; fi
        done; echo "$tot $hp"
    }
    set -- $(cpu); a1=$1; h1=$2; sleep $s; set -- $(cpu)
    hz=$(getconf CLK_TCK 2>/dev/null || echo 100)
    awk -v a=$(( $1 - a1 )) -v h=$(( $2 - h1 )) -v s=$s -v hz=$hz 'BEGIN{printf "idle_window_s=%d android_cpu_pct=%.2f host_helpers_cpu_pct=%.2f\n", s, a*100/hz/s, h*100/hz/s}'
    ;;
*) sed -n '2,8p' "$0" ;;
esac
