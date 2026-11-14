#!/bin/sh
# Name: VeraDroid 调查二
# Author: VeraDroid
#
# 第二轮调查：回答第一轮没解决的问题。
# 全部只读，或只做会立刻撤销的无副作用测试：
#   - unshare 起一个空的命名空间，里面只 echo，然后退出
#   - 在 /var/tmp 里挂一次 freezer cgroup，建一个空组，立刻卸掉
# 不停 Kindle 界面，不写 /mnt/us 以外的任何持久位置，报告在 /mnt/us/veradroid/survey/。

OUT_DIR=/mnt/us/veradroid/survey
TS=$(date +%Y%m%d-%H%M%S)
OUT="$OUT_DIR/survey2-$TS.txt"
mkdir -p "$OUT_DIR" || exit 1

section() { printf '\n========== %s ==========\n' "$1"; }
run() { printf '\n$ %s\n' "$1"; sh -c "$1" 2>&1; }

collect() {
    section "A. 真实身份（停 Kindle 界面时会不会被一起杀掉）"
    run 'id; grep -E "^(Name|Uid|Gid|Groups|CapEff|NoNewPrivs|Seccomp)" /proc/self/status'
    run 'cat /proc/self/cgroup; cat /proc/self/oom_score_adj'
    run 'ps -o pid,ppid,user,group,comm,args | head -60'
    run 'ls -l /proc/self/exe /proc/$PPID/exe; cat /proc/$PPID/cmdline | tr "\000" " "; echo'
    run 'ls -l /usr/bin/su /bin/su /usr/sbin/su 2>&1; ls -la /mnt/us/libkh /mnt/us/libkh/* 2>&1 | head -30'

    section "B. SELinux（Android 的 init 加载策略会不会影响 Kindle）"
    run 'ls -la /sys/fs/selinux/ 2>&1 | head -30'
    run 'cat /sys/fs/selinux/status /sys/fs/selinux/enforce /sys/fs/selinux/policyvers 2>&1'
    run 'cat /proc/self/attr/current 2>&1; echo; cat /proc/cmdline | tr " " "\n" | grep -i selinux'
    run 'command -v getenforce setenforce sestatus load_policy; ls /etc/selinux /sepolicy 2>&1 | head'
    run 'grep selinux /proc/mounts'

    section "C. unshare / 命名空间（无副作用）"
    run 'unshare --help 2>&1 | head -20'
    run 'unshare -m -u -i -n -p -f -- sh -c "echo ns-ok pid=\$\$; ls /proc | head -3; readlink /proc/self/ns/pid /proc/self/ns/net"; echo exit=$?'
    run 'unshare -m -- sh -c "mount --make-rprivate / && echo make-rprivate-ok"; echo exit=$?'
    run 'mkdir -p /var/tmp/vdns; unshare -m -- sh -c "mount --make-rprivate / 2>/dev/null; mount -t tmpfs tmpfs /var/tmp/vdns && echo tmpfs-mount-ok && touch /var/tmp/vdns/x && ls /var/tmp/vdns"; echo exit=$?; echo "outside sees:"; ls -A /var/tmp/vdns; grep -c " /var/tmp/vdns " /proc/mounts; rmdir /var/tmp/vdns'
    run 'nsenter --help 2>&1 | head -5; pivot_root 2>&1 | head -3; chroot 2>&1 | head -3'
    run 'ls -l /bin/busybox /bin/sh /bin/unshare /bin/mount /usr/bin/unshare 2>&1; /bin/busybox 2>&1 | head -5'

    section "D. cgroup freezer（挂载 → 建组 → 冻结空组 → 解冻 → 卸载，全部在 /var/tmp/vdfz）"
    run 'mkdir -p /var/tmp/vdfz && mount -t cgroup -o freezer freezer /var/tmp/vdfz && echo mount-ok; ls /var/tmp/vdfz | head -20'
    run 'mkdir /var/tmp/vdfz/t && echo mkdir-ok; ls /var/tmp/vdfz/t; cat /var/tmp/vdfz/t/freezer.state'
    run 'echo FROZEN > /var/tmp/vdfz/t/freezer.state; cat /var/tmp/vdfz/t/freezer.state; echo THAWED > /var/tmp/vdfz/t/freezer.state; cat /var/tmp/vdfz/t/freezer.state'
    run 'rmdir /var/tmp/vdfz/t; umount /var/tmp/vdfz && echo umount-ok; rmdir /var/tmp/vdfz; ls -d /var/tmp/vdfz 2>&1'
    run 'grep -E "freezer" /proc/mounts || echo "freezer not mounted (clean)"'

    section "E. 显示接口（只读）"
    run 'ls -l /proc/hwtcon /proc/eink 2>&1; ls /proc/hwtcon/* /proc/eink/* 2>&1 | head -30'
    for f in /proc/hwtcon/* /proc/eink/*; do
        [ -f "$f" ] && [ -r "$f" ] && printf '\n$ head -c 600 %s\n%s\n' "$f" "$(head -c 600 "$f" 2>&1)"
    done
    run 'ls -l /mnt/wfm/ /mnt/wfm/waveform_to_use/ 2>&1 | head; ls -l /lib/modules/hwtcon_v2.ko'
    run 'ls /sys/devices/platform/14000000.hwtcon_v2/ 2>&1; ls /sys/module/hwtcon_v2/parameters/ 2>&1'
    run 'for p in /sys/module/hwtcon_v2/parameters/*; do echo "$p: $(cat $p 2>&1)"; done'
    run 'lipc-get-prop com.lab126.pillow -h 2>&1 | head -3'

    section "F. 电源 / 框架 / 事件（只读）"
    run 'lipc-get-prop com.lab126.kaf frameworkStarted'
    run 'lipc-get-prop com.lab126.powerd -s status 2>&1 | head -5; lipc-get-prop com.lab126.powerd screenSaverTimeout'
    run 'lipc-get-prop com.lab126.appmgrd activeApp; lipc-get-prop com.lab126.appmgrd activeView'
    run 'cat /sys/class/backlight/fp9967-bl0/actual_brightness /sys/class/backlight/fp9967-bl1/actual_brightness'
    run 'cat /proc/loadavg; free -k 2>&1 | head -4'
    for pn in KPPMainApp java Xorg awesome blanket pillowd powerd lipc-daemon appmgrd weblabdaemon; do
        for p in $(pidof $pn); do
            printf '%s %s: ' "$pn" "$p"; grep -E "^(VmRSS|Pss)" /proc/$p/status | tr "\n" " "; echo
        done
    done
    run 'cat /proc/pagetypeinfo 2>&1 | head -3; cat /proc/buddyinfo'
    run 'ls /usr/bin | grep -i -E "ssh|dropbear|scp|nc$|telnet|curl|wget|tar|gzip|unzip|xz|cpio" '

    section "G. SSH 现状（不启动任何服务，只看）"
    run 'cat /etc/upstart/sshd.conf 2>&1 | head -30'
    run 'ls -l /mnt/us/koreader/dropbear /mnt/us/koreader/dbclient 2>&1; (netstat -tln 2>/dev/null || cat /proc/net/tcp) | head -20'
    run 'ifconfig wlan0 2>&1 | head -4'
}

{
    echo "VeraDroid 调查二报告"
    echo "生成时间: $TS"
    collect
} > "$OUT" 2>&1

# 隐去 MAC、Wi-Fi 名称和局域网地址
sed -i -r 's/([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}/<MAC>/g; s/ESSID:"[^"]*"/ESSID:"<SSID>"/g; s/inet addr:[0-9.]+/inet addr:<IP>/g; s/Bcast:[0-9.]+/Bcast:<IP>/g' "$OUT"
SN=$(cat /proc/usid 2>/dev/null)
[ -n "$SN" ] && sed -i "s/$SN/<SERIAL>/g" "$OUT"

echo "报告: $OUT"
command -v eips >/dev/null 2>&1 && eips 1 2 "VeraDroid survey2 done" >/dev/null 2>&1
exit 0
