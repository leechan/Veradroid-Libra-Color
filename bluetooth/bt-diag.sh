#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid 蓝牙诊断（只读）：不改设置、不重启、不删任何文件、不开关蓝牙，只把信息写进 /mnt/us/veradroid-bt-diag-时间.txt
# 用法（Kindle 上 root shell / KTerm）：sh /mnt/us/bt-diag.sh          # 普通收集
#                                     sh /mnt/us/bt-diag.sh keys     # 另外录 20 秒按键：运行后按翻页器的上一页 / 下一页
OUT=/mnt/us/veradroid-bt-diag-$(date +%Y%m%d-%H%M%S).txt
sec() { echo; echo "===== $*"; }
{
sec version; cat /etc/prettyversion.txt 2>/dev/null; uname -a; cat /proc/device-tree/model 2>/dev/null | tr -d '\0'; echo
sec memory; grep -E 'MemTotal|MemAvailable' /proc/meminfo
sec "bt processes"; ps -eo pid,etime,comm 2>/dev/null | grep -E 'bt|acs|input_manager|audiomgr|playermgr|stp|wmt' || ps | grep -E 'bt|acs|input_manager|audio'
sec "upstart jobs"; for j in btmanagerd acsbtfd btfd btd input_manager audiomgrd asr_bt_reboot; do initctl status $j 2>&1; done
sec "device nodes"; ls -l /dev/stpbt /dev/btif /dev/stpwmt /dev/uhid /dev/uinput /dev/input/uinput /dev/hidraw* /dev/input/ 2>&1
sec "/proc/bus/input/devices"; cat /proc/bus/input/devices
sec "char devices / modules"; cat /proc/devices; lsmod 2>/dev/null || cat /proc/modules
sec rfkill; for r in /sys/class/rfkill/*; do [ -e "$r" ] && echo "$r $(cat $r/name 2>/dev/null) soft=$(cat $r/soft 2>/dev/null) hard=$(cat $r/hard 2>/dev/null)"; done
sec "lipc services"; lipc-probe -l 2>&1 | tr ' ' '\n' | grep -i -E 'bt|blue|input|audio'
sec "lipc com.lab126.btfd"; lipc-probe -v com.lab126.btfd 2>&1
for p in ListPaired ListConnected ListDiscovered BTmetadata; do sec "btfd $p"; lipc-hash-prop com.lab126.btfd $p </dev/null 2>&1 | head -80; done
sec "lipc com.lab126.acsbt"; lipc-probe -v com.lab126.acsbt 2>&1 | head -40
sec "input_manager config"; cat /etc/input_manager/devices.json /etc/input_manager/categories.json 2>&1 | head -120
sec "bt stack conf"; ls -l /var/local/zbluetooth/ 2>&1; grep -v -E '^#|^$' /var/local/zbluetooth/bt_stack.conf 2>/dev/null | head -20
sec "daemon stderr"; tail -n 80 /tmp/btmanagerd.err /tmp/btfd-acs.err /tmp/input_manager.err 2>&1
sec "syslog bt"; grep -i -E 'btfd|acsbt|btmanager|bluetooth|uhid|hidhost|bta_hh|input_manager|pageturn|page_turner' /var/log/messages 2>/dev/null | tail -n 300
sec "dmesg bt/hid"; dmesg 2>/dev/null | grep -i -E 'uhid|hid|bluetooth|stp_bt|btif|wmt_cdev_bt|input:' | tail -n 120
sec "veradroid"; cat /mnt/us/system/veradroid/version 2>/dev/null; ls -l /dev/shm/veradroid/bt.pid 2>&1; tail -n 100 /dev/shm/veradroid/bt.log 2>&1
grep -E '^BT_' /mnt/us/system/veradroid/settings.conf 2>/dev/null
P=$(cat /dev/shm/veradroid/pid 2>/dev/null); [ -n "$P" ] && ls -l /proc/$P/root/dev/input/ 2>&1
if [ "$1" = keys ]; then
    sec "key capture (read-only, no grab) — connect the page turner / keyboard in Kindle settings first, then press page forward / back"
    # 最多等 30 秒让设备出现（翻页器可能刚唤醒才连上），然后所有匹配设备同时录 20 秒
    pgrep vdbtkeys >/dev/null 2>&1 && [ ! -f /dev/shm/veradroid/frozen ] && echo "note: VeraDroid 的 vdbtkeys 在安卓前台时会独占翻页器，这里可能录不到；请先回到 Kindle 再跑"
    devs=; n=0
    while [ $n -lt 30 ]; do
        for d in /sys/class/input/event*; do
            nm=$(cat $d/device/name 2>/dev/null); b=$(cat $d/device/id/bustype 2>/dev/null)
            case "$b:$nm" in 0005:*|*:kindle-input-pt) case " $devs " in *" ${d##*/} "*) ;; *) devs="$devs ${d##*/}"; echo "-- /dev/input/${d##*/} \"$nm\" bus=$b vendor=$(cat $d/device/id/vendor 2>/dev/null) product=$(cat $d/device/id/product 2>/dev/null)" ;; esac ;; esac
        done
        [ -n "$devs" ] && break
        sleep 1; n=$((n + 1))
    done
    [ -n "$devs" ] || echo "no Bluetooth (bus 0005) input device or kindle-input-pt found in 30 s"
    for e in $devs; do ( cat /dev/input/$e > /tmp/btdiag.$e & p=$!; sleep 20; kill $p ) 2>/dev/null & done
    [ -n "$devs" ] && { echo "recording 20 s ..."; sleep 21; }
    for e in $devs; do
        echo "-- $e"
        hexdump -v -e '16/1 "%02x " "\n"' /tmp/btdiag.$e 2>/dev/null | awk '{ t=$9$10; c=$12$11; v=$13; if (t=="0100") print "EV_KEY code=0x" c " value=" v }' | head -60
        rm -f /tmp/btdiag.$e
    done
fi
sec done; date
} > "$OUT" 2>&1
echo "已写入 $OUT"
