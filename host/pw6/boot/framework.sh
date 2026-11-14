#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# 独立命令行：sh framework.sh stop | start | status（调试用；正式流程由 veradroid.sh 调用 lib/framework.sh）
VD=${VD:-$(cd "$(dirname "$0")/.." && pwd)}
. "$VD/boot/lib/common.sh"
. "$VD/boot/lib/framework.sh"
case "$1" in
    stop) framework_stop ;;
    start) framework_start ;;
    status) framework_paused && echo paused || echo running ;;
    *) echo "usage: $0 stop|start|status"; exit 2 ;;
esac
