#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# VeraDroid firmware check: everything the host scripts (boot/lib/framework.sh, sleep.sh, cmd.sh, the library
# scriptlets) expect from the Kindle firmware, one line each, "ok" or "MISSING". Read-only; does not stop
# or change anything. Use it to compare firmware versions.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH
r() { printf '%-34s %s\n' "$1" "$2"; }
yn() { if eval "$2" >/dev/null 2>&1; then r "$1" ok; else r "$1" MISSING; fi; }
r firmware "$(grep -o '[0-9][0-9]*\.[0-9][0-9.]*' /etc/prettyversion.txt 2>/dev/null | head -1)"
r kernel "$(uname -r)"
# upstart jobs framework_stop pauses (missing ones are simply skipped, but list them)
for s in mtp stored webreader kfxreader kfxview todo tmd rcm archive scanner statusbar lab126_gui powerd wifid; do
    yn "job $s" "[ -f /etc/upstart/$s.conf ]"
done
yn "home app KPPMainApp" "[ -f /etc/upstart/kppmainapp.conf ]"
yn "initctl" "command -v initctl"
yn "lipc-set-prop / lipc-probe" "command -v lipc-set-prop && command -v lipc-probe"
# lipc services and properties (a missing service makes lipc-get-prop fail)
for p in "com.lab126.powerd flIntensity" "com.lab126.powerd currentAmberLevel" "com.lab126.powerd screenSaverTimeout" \
         "com.lab126.powerd preventScreenSaver" "com.lab126.cmd wirelessEnable" "com.lab126.pillow disableEnablePillow"; do
    set -- $p
    yn "lipc $1 $2" "lipc-probe $1 2>/dev/null | grep -qw $2"
done
yn "lipc appmgrd start" "lipc-probe com.lab126.appmgrd 2>/dev/null | grep -qw start"
# processes the pause step SIGSTOPs
for p in awesome volumd; do yn "process $p" "pidof $p"; done
# input devices the host binds (names differ between models)
r "input devices" "$(grep -h '^N:' /proc/bus/input/devices 2>/dev/null | sed 's/N: Name=//' | tr -d '"' | tr '\n' ',')"
yn "page-turn keys (kindle-input-pt)" "grep -q kindle-input-pt /proc/bus/input/devices"
# drawing tools
yn "eips" "command -v eips"
r "fbink" "$(ls /mnt/us/libkh/bin/fbink /usr/bin/fbink /mnt/us/koreader/fbink 2>/dev/null | head -1)"
# jailbreak launchers present on this image
yn "KMC library scriptlets (sh_integration)" "ls /var/local/kmc/bin/sh_integration_launcher"
yn "KUAL extensions dir" "[ -d /mnt/us/extensions ]"
yn "MRPI (mrpackages)" "[ -d /mnt/us/mrpackages ]"
yn "curl with CA bundle" "[ -s /etc/ssl/certs/ca-certificates.crt ] && command -v curl"
yn "/dev/shm tmpfs" "grep -q ' /dev/shm tmpfs' /proc/mounts"
r "/var size" "$(df -m /var 2>/dev/null | awk 'NR==2{print $2 " MB"}')"
r "userstore" "$(grep -E ' /mnt/base-us ' /proc/mounts | awk '{print $3}')"
