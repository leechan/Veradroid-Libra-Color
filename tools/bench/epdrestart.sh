#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# epdrestart.sh [extra args]: restart veradroid-epd with its current command line (+ extra args), Android keeps running
W=/dev/shm/veradroid
old=$(cat $W/epd.pid); cmd=$(tr '\0' ' ' < /proc/$old/cmdline)
[ -n "$cmd" ] || { echo "no epd"; exit 1; }
[ -f $W/epd.cmdline0 ] || echo "$cmd" > $W/epd.cmdline0
cmd=$(cat $W/epd.cmdline0)
kill $old; i=0; while kill -0 $old 2>/dev/null && [ $i -lt 30 ]; do usleep 100000; i=$((i+1)); done
cp $W/epd.log $W/epd.log.prev 2>/dev/null
setsid sh -c "$cmd $* > $W/epd.log 2>&1 & echo \$! > $W/epd.pid" </dev/null >/dev/null 2>&1
sleep 1; echo "epd now $(cat $W/epd.pid): $(tr '\0' ' ' < /proc/$(cat $W/epd.pid)/cmdline)"; echo REDRAW > $W/kfb/epd.fifo; sleep 1; tail -3 $W/epd.log
