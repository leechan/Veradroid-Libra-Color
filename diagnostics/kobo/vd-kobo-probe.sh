#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only hardware probe for the Kobo VeraDroid port (Libra 2 N418 /
# Libra Colour N428). Run on the Kobo over SSH:
#
#   sh /mnt/onboard/.adds/Veradroid-LibraColour/diagnostics/vd-kobo-probe.sh
#
# It writes nothing except an optional report file next to this script
# (diagnostics/probe-<date>.txt). Use it before reporting a porting problem.

OUT=
case "${1:-}" in
    --save) OUT=$(dirname "$0")/probe-$(date +%Y%m%d-%H%M%S).txt ;;
esac
if [ -z "${VD:-}" ]; then
    for d in /mnt/onboard/.adds/Veradroid-*; do
        [ -d "$d/boot" ] && { VD=$d; break; }
    done
fi
VD=${VD:-/mnt/onboard/.adds/Veradroid-Libra2}

say() { [ -n "$OUT" ] && printf '%s\n' "$*" >> "$OUT" || printf '%s\n' "$*"; }
sec() { say ""; say "===== $* ====="; }
kv()  { v=$(cat "$1" 2>/dev/null | tr -d '\r\n'); say "$2=${v:-?}"; }

[ -n "$OUT" ] && : > "$OUT"
say "VeraDroid Kobo hardware probe — $(date)"
sec "Identity"
kv /mnt/onboard/.kobo/version kobo_version
kv /proc/device-tree/model device_tree_model
kv /proc/version proc_version
say "uname=$(uname -a)"
say "PRODUCT=${PRODUCT:-?} PLATFORM=${PLATFORM:-?}"
kv /sys/devices/soc0/machine soc_machine
for f in /proc/board_id /proc/cpuinfo; do
    [ -r "$f" ] && { say ""; sed -n '1,40p' "$f"; }
done

sec "Memory / CPU"
sed -n '/^MemTotal:/p;/^MemAvailable:/p;/^SwapTotal:/p' /proc/meminfo
say "cpus=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
for d in /sys/devices/system/cpu/cpu0/cpufreq /sys/devices/system/cpu/cpufreq/policy0; do
    [ -d "$d" ] || continue
    say "cpufreq=$d"
    for k in scaling_governor scaling_min_freq scaling_max_freq cpuinfo_min_freq cpuinfo_max_freq; do
        [ -r "$d/$k" ] && say "  $k=$(cat "$d/$k" 2>/dev/null)"
    done
    [ -r "$d/scaling_available_frequencies" ] && say "  freqs=$(cat "$d/scaling_available_frequencies")"
done
[ -e /sys/block/zram0 ] && say "zram0=present ($(cat /sys/block/zram0/disksize 2>/dev/null) bytes)"

sec "Framebuffer / e-ink"
FB=/sys/class/graphics/fb0
for k in bits_per_pixel stride virtual_size modes pan rotate name; do
    kv "$FB/$k" "fb0_$k"
done
for f in fbink /mnt/onboard/.adds/koreader/fbink; do
    command -v "$f" >/dev/null 2>&1 || [ -x "$f" ] || continue
    say "-- $f -e --"
    "$f" -e 2>&1 | sed -n '1,30p'
    break
done
for k in waveform_mode_gck16 waveform_mode_glkw16 power_state; do
    [ -e "$FB/$k" ] && say "fb0_$k=$(cat "$FB/$k" 2>/dev/null)"
done
[ -r /proc/fb ] && { say "-- /proc/fb --"; cat /proc/fb; }

sec "Input devices"
if [ -r /proc/bus/input/devices ]; then
    awk '/^I: Bus=/{bus=$0} /^N: Name=/{name=$0} /^H: Handlers=/{print bus; print name; print $0; print ""}' /proc/bus/input/devices
else
    say "/proc/bus/input/devices missing"
fi
for d in /sys/class/input/input*; do
    [ -r "$d/name" ] || continue
    n=$(cat "$d/name" 2>/dev/null)
    case "$n" in *Elan*|*elan*|*gpio*|*pwrkey*|*bd718*|*hall*|*Hall*) ;; *) continue ;; esac
    say "-- $n ($d) --"
    for e in "$d"/event*; do [ -e "$e" ] && say "  event=$(basename "$e")"; done
    for a in /sys/class/input/$(basename "$d")/capabilities/abs /sys/class/input/$(basename "$d")/capabilities/key; do
        [ -r "$a" ] && say "  $(basename "$a")=$(cat "$a")"
    done
done

sec "Frontlight / battery"
for f in /sys/class/backlight/*/brightness /sys/class/backlight/*/max_brightness /sys/class/backlight/*/color; do
    [ -e "$f" ] && say "$f=$(cat "$f" 2>/dev/null)"
done
for d in /sys/class/power_supply/*; do
    [ -d "$d" ] || continue
    say "-- $(basename "$d") --"
    for k in type capacity status online voltage_now current_now; do
        [ -r "$d/$k" ] && say "  $k=$(cat "$d/$k" 2>/dev/null)"
    done
done

sec "Kernel modules / binder"
kv /proc/sys/kernel/osrelease osrelease
say "-- /proc/misc (binder/ashmem/madvise/uinput) --"
awk '$2 ~ /binder|ashmem|madvise|uinput/ {print}' /proc/misc 2>/dev/null
say "-- /proc/modules --"
awk '{print $1, $3}' /proc/modules 2>/dev/null | head -40
for d in /sys/class/binder32 /sys/class/binder; do
    [ -e "$d" ] || continue
    say "$d -> $(readlink -f "$d" 2>/dev/null)"
    [ -r "$d/binder32/dev" ] && say "  binder32/dev=$(cat "$d/binder32/dev")"
    [ -r "$d/binder/dev" ] && say "  binder/dev=$(cat "$d/binder/dev")"
done
for f in /dev/binder /dev/kobo_madvise /dev/uinput /dev/ashmem /dev/fuse; do
    [ -e "$f" ] && say "$f=$(ls -l "$f" 2>/dev/null)"
done
for f in "$VD"/kmod/*/*.ko /mnt/onboard/.adds/*/kmod/*/*.ko; do
    [ -f "$f" ] || continue
    say "-- $f --"
    strings "$f" 2>/dev/null | grep -E '^vermagic=|^license=' | head -3
done

sec "Network / storage"
for d in /sys/class/net/*; do
    [ -e "$d/operstate" ] || continue
    say "$(basename "$d") operstate=$(cat "$d/operstate" 2>/dev/null) mac=$(cat "$d/address" 2>/dev/null)"
done
say "-- mounts --"
sed -n '1,30p' /proc/mounts
say "-- onboard --"
df -kP /mnt/onboard 2>/dev/null | tail -2

sec "Power management"
for f in /sys/power/state /sys/power/state-extended /sys/class/rtc/rtc0/wakealarm; do
    [ -e "$f" ] && say "$f=$(cat "$f" 2>/dev/null)"
done
sed -n '1,5p' /proc/interrupts 2>/dev/null
say "-- wakeup sources --"
for f in /sys/class/wakeup/*/name; do
    [ -r "$f" ] && say "  $(cat "$f" 2>/dev/null)"
done 2>/dev/null | head -30

sec "VeraDroid state"
for f in /tmp/veradroid/pid /tmp/veradroid/mode /tmp/veradroid/epd.log /tmp/veradroid/input.log /tmp/veradroid/input.err; do
    [ -e "$f" ] || continue
    say "-- $f --"
    case "$f" in *.log|*.err) tail -40 "$f" 2>/dev/null ;; *) cat "$f" 2>/dev/null ;; esac
done
for f in "$VD"/logs/veradroid.log /mnt/onboard/.adds/*/logs/veradroid.log; do
    [ -f "$f" ] || continue
    say "-- $f (tail) --"
    tail -60 "$f"
    break
done

[ -n "$OUT" ] && echo "Report written to $OUT"
