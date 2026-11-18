#!/bin/sh
# EXPERIMENTAL KT5 profile. Only verified in eink-emulator; back up the Kindle first.
# bootstrap.sh picks the 4.9-kernel bundle (32-bit binder rootfs) by itself.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
export VD_MODEL=kt5
export VD_EXPERIMENTAL=1
BASE="${VD_BASE:-https://veradroid.wenjin.jp}"
show() { command -v eips >/dev/null 2>&1 && eips 1 3 "$*" >/dev/null 2>&1 || true; echo "$*"; }
show "正在下载 VeraDroid 安装器…"
if ! curl -fsSL --retry 3 --connect-timeout 20 "$BASE/bootstrap.sh?t=$(date +%s)" -o /tmp/vd-kpm-bootstrap.sh; then show "下载失败：请检查 Wi-Fi 后重试"; exit 1; fi
show "正在安装 KT5（实验性，仅模拟器验证）…"
sh /tmp/vd-kpm-bootstrap.sh
rc=$?
rm -f /tmp/vd-kpm-bootstrap.sh
if [ "$rc" != 0 ]; then show "安装失败，请回到原生 Kindle 后重试"; fi
exit $rc
