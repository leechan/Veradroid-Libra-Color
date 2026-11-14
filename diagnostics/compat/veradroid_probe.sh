#!/bin/sh
# VeraDroid compatibility probe (read-only).
# Usage: sh veradroid_probe.sh [--out /mnt/us/probe.txt]
set -u

OUT=
while [ $# -gt 0 ]; do
    case "$1" in
        --out) OUT=${2:-}; shift 2 ;;
        *) echo "usage: $0 [--out FILE]" >&2; exit 2 ;;
    esac
done

# Kernel bitmaps are BITS_PER_LONG wide. PW6 is currently 32-bit armv7l.
MACH=${VERADROID_BPL:-$(uname -m 2>/dev/null)}
case "$MACH" in
    aarch64|arm64|64) BPL=64 ;;
    *) BPL=32 ;;
esac

has_bit() {  # $1=hex words (most significant first), $2=bit number
    _bits=$1; _bit=$2
    _widx=$((_bit / BPL)); _boff=$((_bit % BPL))
    # shellcheck disable=SC2086
    set -- $_bits
    _pos=$(($# - _widx))
    [ "$_pos" -ge 1 ] || return 1
    eval _w=\${$_pos}
    [ -n "${_w:-}" ] || return 1
    [ $(( (0x${_w} >> _boff) & 1 )) -eq 1 ]
}

input_blocks() {
    IN=${VERADROID_INPUT_DEVICES:-/proc/bus/input/devices}
    awk -v input_file="$IN" '
    function emit() {
        if (name != "")
            printf "%s|%s|%s|%s|%s|%s|%s|%s\n", name, handlers, phys, sysfs, prop, ev, key, abs
    }
    /^I: Bus=/ { emit(); name=""; handlers=""; phys=""; sysfs=""; prop=""; ev=""; key=""; abs="" }
    /^N: Name=/ { name=$0; sub(/^N: Name="/,"",name); sub(/"$/,"",name) }
    /^P: Phys=/ { phys=$0; sub(/^P: Phys=/,"",phys) }
    /^S: Sysfs=/ { sysfs=$0; sub(/^S: Sysfs=/,"",sysfs) }
    /^H: Handlers=/ { handlers=$0; sub(/^H: Handlers=/,"",handlers) }
    /^B: PROP=/ { prop=$0; sub(/^B: PROP=/,"",prop) }
    /^B: EV=/ { ev=$0; sub(/^B: EV=/,"",ev) }
    /^B: KEY=/ { key=$0; sub(/^B: KEY=/,"",key) }
    /^B: ABS=/ { abs=$0; sub(/^B: ABS=/,"",abs) }
    END { emit() }
    ' "$IN" 2>/dev/null
}

if [ -n "$OUT" ]; then
    exec >"$OUT" 2>&1
fi

echo "== VeraDroid compatibility probe =="
echo "time=$(date 2>/dev/null)"
echo "uname=$(uname -a 2>/dev/null)"
echo "machine=$(uname -m 2>/dev/null) BPL=$BPL"
echo "prettyversion=$(cat /etc/prettyversion.txt 2>/dev/null | head -1)"
echo "version=$(cat /etc/version.txt 2>/dev/null | head -1)"
echo "usid_prefix=$(cut -c1-6 /proc/usid 2>/dev/null)"
echo "model=$(cat /proc/device-tree/model 2>/dev/null | tr '\0' ' ')"
echo "compatible=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' ' ')"
echo
echo "== framebuffer =="
for d in /sys/class/graphics/fb*; do
    [ -e "$d" ] || continue
    echo "fb=$(basename "$d") virtual_size=$(cat "$d/virtual_size" 2>/dev/null) bpp=$(cat "$d/bits_per_pixel" 2>/dev/null) stride=$(cat "$d/stride" 2>/dev/null)"
done
fbset 2>/dev/null | head -10
echo
echo "== input devices =="
i=0
TOUCH_COUNT=0
TOUCH_NAME=; TOUCH_EVENT=; TOUCH_ABS=; TOUCH_KEY=; TOUCH_PROP=; TOUCH_SYSFS=
while IFS='|' read -r name handlers phys sysfs prop ev key abs; do
    [ -n "$name" ] || continue
    i=$((i + 1))
    lname=$(printf '%s' "$name" | tr 'A-Z' 'a-z')
    case "$sysfs" in */virtual/*) virtual=1 ;; *) virtual=0 ;; esac
    echo "[$i] name=$name"
    echo "    handlers=$handlers"
    echo "    phys=$phys"
    echo "    sysfs=$sysfs"
    echo "    prop=$prop ev=$ev key=$key abs=$abs"
    # Find MT touch devices: exclude virtual devices and key-only devices.
    case "$lname" in
        *kindle-input-pt*|*veradroid-touch*|*veradroid-keys*|*pwrkey*|*power*|*gpio*|*button*) continue ;;
    esac
    [ "$virtual" = 0 ] || continue
    has_bit "$abs" 53 || continue
    has_bit "$abs" 54 || continue
    event=$(printf '%s\n' "$handlers" | tr ' ' '\n' | grep '^event[0-9]' | head -1)
    [ -n "$event" ] || continue
    TOUCH_COUNT=$((TOUCH_COUNT + 1))
    TOUCH_NAME=$name; TOUCH_EVENT=$event; TOUCH_ABS=$abs; TOUCH_KEY=$key; TOUCH_PROP=$prop; TOUCH_SYSFS=$sysfs
    echo "    touch_candidate=yes event=$event"
    echo "    mt_slot=$(has_bit "$abs" 47 && echo yes || echo no) mt_tracking=$(has_bit "$abs" 57 && echo yes || echo no)"
    echo "    mt_x=$(has_bit "$abs" 53 && echo yes || echo no) mt_y=$(has_bit "$abs" 54 && echo yes || echo no)"
    echo "    btn_touch=$(has_bit "$key" 330 && echo yes || echo no) direct=$(has_bit "$prop" 1 && echo yes || echo no)"
done <<EOF
$(input_blocks)
EOF
echo
echo "== touch summary =="
echo "touch_count=$TOUCH_COUNT"
echo "touch_name=${TOUCH_NAME:-none}"
echo "touch_event=${TOUCH_EVENT:-none}"
echo "touch_sysfs=${TOUCH_SYSFS:-none}"
echo "touch_abs=${TOUCH_ABS:-none}"
echo "touch_key=${TOUCH_KEY:-none}"
echo "touch_btn_touch=$(has_bit "${TOUCH_KEY:-0}" 330 && echo 1 || echo 0)"
echo "touch_mt_slot=$(has_bit "${TOUCH_ABS:-0}" 47 && echo 1 || echo 0)"
echo "touch_mt_tracking=$(has_bit "${TOUCH_ABS:-0}" 57 && echo 1 || echo 0)"
echo "touch_prop_direct=$(has_bit "${TOUCH_PROP:-0}" 1 && echo 1 || echo 0)"
echo
echo "== i2c / drivers =="
for d in /sys/bus/i2c/devices/*; do
    [ -e "$d" ] || continue
    n=$(cat "$d/name" 2>/dev/null)
    [ -n "$n" ] || continue
    drv=$(basename "$(readlink -f "$d/driver" 2>/dev/null)" 2>/dev/null)
    echo "$(basename "$d") name=$n driver=${drv:-none}"
done
echo
echo "== container deps =="
for f in /dev/uinput /dev/binder /dev/vndbinder /dev/ashmem; do
    if [ -e "$f" ]; then echo "$f=yes"; else echo "$f=no"; fi
done
for f in /proc/filesystems /proc/misc; do
    echo "$f=$(grep -E 'binder|ashmem|binderfs' "$f" 2>/dev/null | tr '\n' ' ')"
done
echo
echo "== loaded modules =="
grep -E 'binder|ashmem|uinput|focal|ft[0-9]|pt_mt' /proc/modules 2>/dev/null | head -20
echo "== done =="
