#!/bin/sh
# Name: VeraDroid 关闭
# Author: VeraDroid
#
# 完全关闭 VeraDroid 并把内存还给 Kindle（Android 里卡住、点不动时用）。
exec sh /mnt/base-us/veradroid/boot/stop.sh >/dev/null 2>&1 </dev/null
