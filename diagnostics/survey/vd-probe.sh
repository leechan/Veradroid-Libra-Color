#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid capability probe: one screen of facts that decide whether (and how) a Kindle
# can host the Android container. Read-only; safe on any model/firmware. Prints key=value.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
kv() { printf '%s=%s\n' "$1" "$2"; }
cfg() { # cfg CONFIG_X -> y/m/n/? from /proc/config.gz
    if [ -r /proc/config.gz ]; then
        v=$(zcat /proc/config.gz 2>/dev/null | grep -E "^$1=|^# $1 is not set" | head -1)
        case "$v" in *=y) echo y ;; *=m) echo m ;; "# "*) echo n ;; *) echo - ;; esac
    else echo '?'; fi
}
kv firmware "$(grep -o '[0-9][0-9]*\.[0-9][0-9.]*' /etc/prettyversion.txt 2>/dev/null | head -1)"
kv pretty "$(head -1 /etc/prettyversion.txt 2>/dev/null)"
kv kernel "$(uname -r)"
kv arch "$(uname -m)"
kv compatible "$(tr '\0' ' ' < /proc/device-tree/compatible 2>/dev/null)"
kv platform "$(grep -m1 -E 'Hardware|model name' /proc/cpuinfo | sed 's/.*: //')"
kv cpus "$(grep -c ^processor /proc/cpuinfo)"
kv cpu_features "$(grep -m1 Features /proc/cpuinfo | sed 's/.*: //')"
kv memtotal_kb "$(awk '/MemTotal/{print $2}' /proc/meminfo)"
kv memavail_kb "$(awk '/MemAvailable/{print $2}' /proc/meminfo)"
kv overcommit "$(cat /proc/sys/vm/overcommit_memory 2>/dev/null)"
kv config_gz "$([ -r /proc/config.gz ] && echo yes || echo no)"
kv ns "$(ls /proc/self/ns 2>/dev/null | tr '\n' ' ')"
for c in NAMESPACES UTS_NS IPC_NS PID_NS NET_NS USER_NS CGROUPS CGROUP_FREEZER \
         ANDROID ANDROID_BINDER_IPC ANDROID_BINDERFS ASHMEM ION SW_SYNC SYNC \
         BLK_DEV_LOOP EXT4_FS SQUASHFS ZRAM TUN VETH INPUT_UINPUT FUSE_FS \
         SECURITY_SELINUX EPOLL SIGNALFD TIMERFD EVENTFD INOTIFY_USER \
         FHANDLE SECCOMP SECCOMP_FILTER MODULES MODULE_SIG_FORCE VT FB; do
    kv "CONFIG_$c" "$(cfg CONFIG_$c)"
done
kv binder_devs "$(ls /dev 2>/dev/null | grep -E 'binder' | tr '\n' ' ')"
kv binder_proc "$(ls /proc/binder /sys/kernel/debug/binder 2>/dev/null | head -3 | tr '\n' ' ')"
kv ashmem_dev "$([ -e /dev/ashmem ] && echo yes || echo no)"
kv filesystems "$(grep -v nodev /proc/filesystems | tr -d '\t' | tr '\n' ' ') | $(grep -E 'binder|cgroup|tmpfs|squashfs|fuse' /proc/filesystems | awk '{print $2}' | tr '\n' ' ')"
kv cgroup_freezer "$(grep -w freezer /proc/cgroups 2>/dev/null | awk '{print $4}')"
kv loop "$(ls /dev/loop* 2>/dev/null | head -3 | tr '\n' ' ')"
kv uinput "$([ -e /dev/uinput ] || [ -e /dev/input/uinput ] && echo yes || echo no)"
kv tun "$([ -e /dev/net/tun ] && echo yes || echo no)"
if command -v unshare >/dev/null 2>&1; then
    unshare -m -u -i -p -f -n true 2>/dev/null && kv unshare_test ok || kv unshare_test fail
else kv unshare_test no-binary; fi
kv selinux "$(cat /sys/fs/selinux/enforce 2>/dev/null || echo none)"
for f in /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/stride; do
    kv "fb_$(basename $f)" "$(cat $f 2>/dev/null)"
done
kv fb_name "$(cat /proc/fb 2>/dev/null | tr '\n' ' ')"
kv input "$(grep -h '^N:' /proc/bus/input/devices 2>/dev/null | sed 's/N: Name=//' | tr -d '"' | tr '\n' ',')"
kv userstore "$(grep -E ' /mnt/(base-us|us) ' /proc/mounts | awk '{print $2":"$3}' | tr '\n' ' ')"
kv us_free_mb "$(df -m /mnt/base-us 2>/dev/null | awk 'NR==2{print $4}')"
kv var_local_free_mb "$(df -m /var/local 2>/dev/null | awk 'NR==2{print $4}')"
kv shm_mb "$(df -m /dev/shm 2>/dev/null | awk 'NR==2{print $2}')"
kv fscrypt "$([ -e /mnt/base-us/_uid_ses.0 ] || ls /mnt/base-us 2>/dev/null | grep -q '^_uid' && echo yes || echo no)"
kv init "$( [ -d /etc/upstart ] && echo upstart || echo sysv)"
kv lipc "$(command -v lipc-get-prop >/dev/null && echo yes || echo no)"
kv fbink "$(ls /mnt/us/libkh/bin/fbink /usr/bin/fbink /mnt/us/extensions/MRInstaller/bin/*/fbink 2>/dev/null | head -1)"
kv eips "$(command -v eips >/dev/null && echo yes || echo no)"
kv kual "$([ -d /mnt/us/extensions ] && ls /mnt/us/extensions | tr '\n' ' ')"
kv mrpi "$([ -d /mnt/us/mrpackages ] && echo yes || echo no)"
kv jb_markers "$(ls /mnt/us/jb* /mnt/us/libkh /var/local/kmc /var/local/mkk /etc/upstart/*jb* 2>/dev/null | tr '\n' ' ')"
kv scriptlets "$(ls /mnt/us/documents/*.sh 2>/dev/null | wc -l)"
kv sh_integration "$(ls /usr/bin/*sh_integration* /var/local/kmc/bin/*sh_integration* /mnt/us/libkh/bin/*launcher* 2>/dev/null | tr '\n' ' ')"
kv busybox "$(busybox 2>&1 | head -1)"
kv curl "$(command -v curl) $(curl --version 2>/dev/null | head -1 | cut -d' ' -f1-2)"
kv ca_certs "$(ls /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs 2>/dev/null | head -1)"
