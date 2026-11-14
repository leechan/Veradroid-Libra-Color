#!/bin/sh
# Name: VeraDroid 全新安装（清 Android 数据）
# Author: ajie / wenjin.jp
# Icon: cover is in the normal installer
# Wipes Android app/system state but keeps /data/media: Books and device token survive.
trap '' PIPE   # 书库启动器把输出管道给 fbink；fbink 缺失/崩溃时管道断开，不能让 SIGPIPE 杀掉脚本
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
BASE=https://veradroid.wenjin.jp
eips 1 2 "VeraDroid: 全新安装，保留书和 token..." 2>/dev/null
export VD_FACTORY=1
B=/tmp/vd-bootstrap.sh; curl -fsSL "$BASE/bootstrap.sh" -o "$B" && sh "$B"; rm -f "$B"
