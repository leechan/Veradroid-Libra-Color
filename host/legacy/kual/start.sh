#!/bin/sh
# KUAL launcher for VeraDroid. Works on jailbreaks that expose KUAL but do not
# display .sh files in the native library.
if [ -f /mnt/base-us/veradroid/boot/veradroid.sh ]; then
    sh /mnt/base-us/veradroid/boot/veradroid.sh home
else
    eips 1 2 "VeraDroid 未安装，请先运行安装脚本" 2>/dev/null
fi
