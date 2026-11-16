#!/bin/sh
# epdswap.sh install|rollback|status : put a test build of veradroid-epd on a device and take it off again (PW6 / k49 host).
# Runs ON the Kindle as root, fed through ssh stdin, e.g. from the Mac (k = the usual ssh wrapper for the device):
#   install : k 'mkdir -p /dev/shm/epdswap && cat > /dev/shm/epdswap/epd-new' < host/pw6/bin/veradroid-epd && k 'sh -s install' < tools/bench/epdswap.sh
#   rollback: k 'sh -s rollback' < tools/bench/epdswap.sh
#   status  : k 'sh -s status' < tools/bench/epdswap.sh
# install : keeps the current binary as veradroid-epd.orig (only if there is no .orig yet, so a second install never
#           overwrites the real original), copies the new one, chmod 755. rollback: puts .orig back and removes it.
# Both then restart ONLY the bridge (Android keeps running; nothing happens when Android is not running) with its current
# command line, and resend the device's own display settings (settings.conf + model file + the current app's settings.app,
# the same epd_send lines as settings_apply) - settings files are only read, never written.
VD=/mnt/base-us/veradroid; B=$VD/bin/veradroid-epd; N=/dev/shm/epdswap/epd-new; W=/dev/shm/veradroid
say() { echo "epdswap: $*"; }
md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
restart_bridge() {
    old=$(cat $W/epd.pid 2>/dev/null)
    [ -n "$old" ] && [ -r /proc/$old/cmdline ] || { say "bridge not running (Android off): file swapped only, used at the next start"; return 0; }
    cmd=$(tr '\0' ' ' < /proc/$old/cmdline)
    case "$cmd" in *veradroid-epd\ run*) ;; *) say "pid $old is not the bridge ($cmd), not restarting"; return 1 ;; esac
    kill $old; i=0; while kill -0 $old 2>/dev/null && [ $i -lt 30 ]; do usleep 100000; i=$((i+1)); done
    cp $W/epd.log $W/epd.log.swap-prev 2>/dev/null
    setsid sh -c "$cmd > $W/epd.log 2>&1 & echo \$! > $W/epd.pid" </dev/null >/dev/null 2>&1
    sleep 1
    new=$(cat $W/epd.pid); kill -0 $new 2>/dev/null || { say "BRIDGE DID NOT START: $(tail -2 $W/epd.log)"; return 1; }
    say "bridge restarted: pid $new, exe md5 $(md5 /proc/$new/exe)"
    # the device's own settings, read-only (settings_load), sent the way settings_apply sends them
    ( . $VD/boot/lib/common.sh >/dev/null 2>&1; . $VD/boot/lib/settings.sh >/dev/null 2>&1
      settings_load >/dev/null 2>&1
      epd_send ANIM $KFB_ANIM_MODE $KFB_ANIM_DIR $KFB_ANIM_STEPS $KFB_ANIM_MIN
      epd_send SET $KFB_CONTRAST $KFB_DITHER $KFB_FLASH $KFB_INVERT $KFB_MODE $KFB_SETTLE ${KFB_LIGHTF:-0} ${KFB_DARKEN:-0}
      epd_send HOLD ${KFB_HOLD:-70}
      type epd_send_smooth >/dev/null 2>&1 && epd_send_smooth
      case "$KFB_PWRDOWN" in off) epd_send PWRDOWN -1 ;; ''|*[!0-9]*) ;; *) epd_send PWRDOWN $KFB_PWRDOWN ;; esac )
    sleep 2
    say "$(grep -a 'epd: set ' $W/epd.log | tail -1)"
}
case "$1" in
install)
    [ -s $N ] && [ "$(wc -c < $N)" -gt 500000 ] || { say "no new binary at $N (copy it first)"; exit 1; }
    head -c 4 $N | grep -q ELF || { say "$N is not an ELF file"; exit 1; }
    if [ -f $B.orig ]; then say "keeping the existing $B.orig ($(md5 $B.orig))"
    else cp -p $B $B.orig || exit 1; say "original saved: $B.orig ($(md5 $B.orig))"; fi
    cp $N $B.tmp && chmod 755 $B.tmp && mv -f $B.tmp $B || { say "copy failed"; exit 1; }
    say "installed $(md5 $B)"
    restart_bridge ;;
rollback)
    [ -f $B.orig ] || { say "no $B.orig: nothing to roll back (current $(md5 $B))"; exit 1; }
    cp $B.orig $B.tmp && chmod 755 $B.tmp && mv -f $B.tmp $B || { say "copy failed"; exit 1; }
    [ "$(md5 $B)" = "$(md5 $B.orig)" ] || { say "md5 mismatch after copy, .orig kept"; exit 1; }
    rm -f $B.orig; rm -rf /dev/shm/epdswap
    say "original back: $(md5 $B)"
    restart_bridge ;;
status)
    say "binary $(md5 $B)  orig $( [ -f $B.orig ] && md5 $B.orig || echo none)  running $(md5 /proc/$(cat $W/epd.pid 2>/dev/null)/exe 2>/dev/null || echo none)" ;;
*) echo "usage: sh -s install|rollback|status < epdswap.sh"; exit 2 ;;
esac
