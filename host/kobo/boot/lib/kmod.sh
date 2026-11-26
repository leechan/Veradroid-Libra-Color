# SPDX-License-Identifier: GPL-3.0-or-later
# Load Kobo out-of-tree kernel modules required by the Android 7 container.
#
# Libra 2 (4.1.15): binder + kobo_zsmalloc + kobo_zram + kobo_madvise.
# Libra Colour (4.9.77): the kernel already ships ashmem, zram and a
# 64-bit (protocol 8) binder; Android 7 ARM needs protocol 7, so the bundled
# binder_linux.ko registers a separate char device named "binder32" (major 511)
# and we create /dev/binder with its real major:minor. kobo_madvise.ko is still loaded (the preload
# shim and the launch path stay identical).

kmod_dir() {
    rel=$(uname -r)
    for d in "$VD/kmod/$rel" "/mnt/onboard/.adds/kobo-android-lab/kernels/$rel"; do
        [ -f "$d/${BINDER_KO:-binder_linux.ko}" ] && { echo "$d"; return 0; }
    done
    return 1
}

kmod_load_one() { # mod_name ko_path [args...]
    m=$1; ko=$2; shift 2
    [ -f "$ko" ] || return 0
    grep -q "^$m " /proc/modules && return 0
    if insmod "$ko" "$@" 2>>"$LOG"; then
        t "kmod: loaded $m (${ko##*/})"
    else
        t "kmod: insmod ${ko##*/} failed (kernel $(uname -r), firmware $(kobo_firmware))"
        return 1
    fi
}

kmod_devnum() { # device name -> major:minor
    n=$1
    # The binder32 module is a cdev with its own major (511), NOT a misc
    # device. Always take the authoritative major:minor from sysfs first.
    for p in "/sys/class/$n/$n/dev" "/sys/class/misc/$n/dev"; do
        [ -r "$p" ] || continue
        v=$(cat "$p" 2>/dev/null)
        case "$v" in *:*) echo "$v"; return 0 ;; esac
    done
    m=$(awk -v n="$1" '$2 == n { print $1; exit }' /proc/misc 2>/dev/null)
    [ -n "$m" ] && { echo "10:$m"; return 0; }
    return 1
}

kmod_node() { # node name, device name, mode
    node=$1; devname=$2; mode=${3:-666}
    dev=$(kmod_devnum "$devname") || return 1
    maj=${dev%%:*}; min=${dev##*:}
    case "$maj:$min" in *[!0-9:]*|:|*:) return 1 ;; esac
    # Replace a stale/wrong node (e.g. the kernel's 64-bit binder) instead of
    # silently keeping it: the device number is what makes protocol 7 work.
    if [ -e "/dev/$node" ] || [ -L "/dev/$node" ]; then rm -f "/dev/$node"; fi
    mknod "/dev/$node" c "$maj" "$min" || return 1
    chmod "$mode" "/dev/$node" 2>/dev/null || true
    t "kmod: mknod /dev/$node ($maj:$min, $devname)"
}

kmod_binder() {
    want=${BINDER_DEVNAME:-binder}
    ko=${BINDER_KO:-binder_linux.ko}
    if [ "$want" = binder32 ]; then
        # The stock 4.9.77 kernel already has "binder" (64-bit). Do not look at
        # it: protocol 7 only exists as the binder32 char device (major 511).
        if [ -z "$(kmod_devnum binder32)" ]; then
            kmod_load_one binder32 "$d/$ko" || {
                t "kmod: protocol-7 binder32 module unavailable for kernel $(uname -r)"
                return 1
            }
        fi
        kmod_node binder binder32 666 || {
            t "kmod: binder32 registered but /dev/binder could not be created ($(kmod_devnum binder32 2>/dev/null))"
            return 1
        }
    else
        if [ -z "$(kmod_devnum binder)" ]; then
            kmod_load_one binder "$d/$ko" || return 1
        fi
        kmod_node binder binder 666 || {
            t "kmod: /dev/binder missing after insmod"
            return 1
        }
    fi
    [ -c /dev/binder ] || { t "kmod: /dev/binder is not a character device"; return 1; }
    return 0
}

kmod_load() {
    d=$(kmod_dir) || {
        t "kmod: no modules found for kernel $(uname -r) (model ${MODEL_ID:-?}, firmware $(kobo_firmware))"
        return 1
    }
    t "kmod: model ${MODEL_ID:-?} kernel $(uname -r) using $d"
    if [ -f "$d/firmware" ]; then
        want_fw=$(head -1 "$d/firmware" 2>/dev/null | tr -d '\r\n')
        now_fw=$(kobo_firmware)
        [ -n "$want_fw" ] && [ -n "$now_fw" ] && [ "$want_fw" != "$now_fw" ] && \
            t "kmod: WARNING modules were verified on firmware $want_fw, device is $now_fw (same kernel $(uname -r) expected)"
    fi

    # 1. Binder IPC (/dev/binder); on 4.9 this must be the protocol-7 device.
    kmod_binder || return 1

    # 2. Compressed swap (kobo_zsmalloc + kobo_zram) only when zram is not built in.
    if [ "${BUILTIN_ZRAM:-0}" != 1 ] && [ ! -e /sys/block/zram0 ]; then
        kmod_load_one kobo_zsmalloc "$d/kobo_zsmalloc.ko" || true
        kmod_load_one kobo_zram "$d/kobo_zram.ko" || true
    fi

    # 3. kobo_madvise (/dev/kobo_madvise). 4.9.77 has CONFIG_ADVISE_SYSCALLS but
    #    the preload shim and the ART tuning still route through this device.
    if [ -z "$(kmod_devnum kobo_madvise)" ]; then
        kmod_load_one kobo_madvise "$d/${MADVISE_KO:-kobo_madvise.ko}" || true
    fi
    [ -n "$(kmod_devnum kobo_madvise)" ] && kmod_node kobo_madvise kobo_madvise 666 || true

    # 4. Built-in uinput device check
    if [ ! -c /dev/uinput ] && [ -n "$(kmod_devnum uinput)" ]; then
        kmod_node uinput uinput 666 || true
    fi
    chmod 666 /dev/uinput 2>/dev/null || true
    return 0
}
