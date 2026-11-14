#!/bin/sh
# Name: VeraDroid
# Author: VeraDroid
#
# 书库里的入口：点它启动 VeraDroid（Android 阅读环境）。已经在后台时，直接回到 Android。
# 程序在 /mnt/base-us/veradroid/，数据在 /mnt/base-us/system/veradroid/。
exec sh /mnt/base-us/veradroid/boot/veradroid.sh home >/dev/null 2>&1 </dev/null
