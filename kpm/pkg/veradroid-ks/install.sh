#!/bin/sh
# EXPERIMENTAL KS profile. Untested; backup the Kindle before running.
PATH=/usr/bin:/bin:/usr/sbin:/sbin:$PATH; export PATH   # 系统自带的 curl/tar 优先：越狱工具或插件装的 curl 可能没有根证书（HTTPS 全部失败）
export VD_MODEL=ks
export VD_EXPERIMENTAL=1
BASE="${VD_BASE:-https://veradroid.wenjin.jp}"
show() { command -v eips >/dev/null 2>&1 && eips 1 3 "$*" >/dev/null 2>&1 || true; echo "$*"; }
show "正在下载 VeraDroid 安装器…"
if ! curl -fsSL --retry 3 --connect-timeout 20 "$BASE/bootstrap.sh" -o /mnt/us/vd-bootstrap.sh; then show "下载失败：请检查 Wi-Fi 后重试"; exit 1; fi
show "安装器已下载，正在开始安装…"
sh /mnt/us/vd-bootstrap.sh
rc=$?
if [ "$rc" != 0 ]; then show "安装失败，请回到原生 Kindle 后重试"; fi
rm -f /mnt/us/vd-bootstrap.sh
exit $rc
