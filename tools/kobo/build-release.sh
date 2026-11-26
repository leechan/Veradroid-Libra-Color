#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build clean, privacy-scrubbed release packages for Veradroid on Kobo:
#   KOBO_MODEL=libra2      -> Veradroid-Libra2-<ver>-{full,upgrade}.zip      (N418)
#   KOBO_MODEL=libracolour -> Veradroid-LibraColour-<ver>-{full,upgrade}.zip (N428)
#
# Install path on Kobo: /mnt/onboard/.adds/<package>
# Dual entry points:
#   - NickelMenu: /mnt/onboard/.adds/nm/<package>
#   - KOReader:   /mnt/onboard/.adds/koreader/plugins/<package>.koplugin/
#
# Usage:
#   KOBO_MODEL=libracolour \
#   BIN_DIR=build/kobo-bin \
#   EXTRA_BIN_DIR=/path/to/extra-bins \
#   LEGACY_DIR=/path/to/veradroid-pw6 \
#   sh tools/kobo/build-release.sh [OUT_DIR]
set -eu

export COPYFILE_DISABLE=1

TOP=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUT_DIR=${1:-$TOP/dist}
BIN_DIR=${BIN_DIR:-$TOP/build/kobo-bin}
EXTRA_BIN_DIR=${EXTRA_BIN_DIR:-}
LEGACY_DIR=${LEGACY_DIR:-}
KOBO_MODEL=${KOBO_MODEL:-libra2}

case "$KOBO_MODEL" in
    libra2)
        PKG_NAME=Veradroid-Libra2
        MODEL_NAME="Kobo Libra 2"
        MODEL_CODE=N418
        PRODUCT_ID=veradroid-kobo-libra2
        KMOD_KERS="4.1.15-00868-g58a2758be07 4.1.15-00838-g349fbf5767c"
        FW_TEXT="4.38.23852 / 4.34.20097"
        KMOD_TEXT="Kobo 4.1.15 kernel modules"
        ;;
    libracolour)
        PKG_NAME=Veradroid-LibraColour
        MODEL_NAME="Kobo Libra Colour"
        MODEL_CODE=N428
        PRODUCT_ID=veradroid-kobo-libracolour
        KMOD_KERS="4.9.77"
        FW_TEXT="4.42.23303 (kernel 4.9.77)"
        KMOD_TEXT="Kobo 4.9.77 kernel modules (protocol-7 binder32)"
        ;;
    *)
        echo "build-release: KOBO_MODEL must be libra2 or libracolour (got $KOBO_MODEL)" >&2
        exit 2 ;;
esac
KMOD_DIR=${KMOD_DIR:-$TOP/host/kobo/kmod}
RAW_VER=$(head -1 "$TOP/host/kobo/VERSION" | tr -d '\r\n')
VER=$(printf '%s' "$RAW_VER" | sed 's/-.*//')
[ -n "$VER" ] || { echo "build-release: cannot read version from host/kobo/VERSION" >&2; exit 2; }
BUILD_DATE=$(date '+%Y-%m-%d')

[ -n "$LEGACY_DIR" ] && [ -f "$LEGACY_DIR/rootfs.tar.gz" ] || {
    echo "build-release: set LEGACY_DIR to clean legacy bundle containing rootfs.tar.gz" >&2
    exit 2
}
[ -n "$KMOD_DIR" ] && [ -d "$KMOD_DIR" ] || {
    echo "build-release: set KMOD_DIR to the directory containing $KMOD_TEXT" >&2
    exit 2
}
missing_kmod=
for kver in $KMOD_KERS; do
    [ -d "$KMOD_DIR/$kver" ] || missing_kmod="$missing_kmod $kver"
done
[ -z "$missing_kmod" ] || {
    echo "build-release: missing kernel modules for:$missing_kmod" >&2
    echo "               (expected under $KMOD_DIR; run tools/kobo/fetch-libra-colour-kmod.sh for N428)" >&2
    exit 2
}

find_bin() {
    name=$1
    if [ -f "$BIN_DIR/$name" ]; then
        echo "$BIN_DIR/$name"
    elif [ -n "$EXTRA_BIN_DIR" ] && [ -f "$EXTRA_BIN_DIR/$name" ]; then
        echo "$EXTRA_BIN_DIR/$name"
    elif [ -f "$LEGACY_DIR/bin/$name" ]; then
        echo "$LEGACY_DIR/bin/$name"
    else
        return 1
    fi
}

WORK=$TOP/build/release-work
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT_DIR"

# Required binaries (must all exist — no silent omissions)
REQ_BINS="
VeraHome.apk
veradroid-epd
veradroid-input
pivot_init
vdlmk
vdloopdio
vdmkswap
vdnocap
vdsqueeze
e2fsck
mke2fs
resize2fs
fbink
fbdepth
fbink-img
kobo-sdcard
hwcomposer.kindle.so
libkobo_madvise.so
kobo-weread-opt.jar
ethernet-service-wifi.jar
"

echo "=== [1/5] Verifying required binaries & host scripts (${PKG_NAME} v${VER}) ==="
for b in $REQ_BINS; do
    p=$(find_bin "$b") || { echo "build-release: MISSING required binary: $b" >&2; exit 2; }
    printf '  OK  %-28s <- %s\n' "$b" "$p"
done

if [ "$KOBO_MODEL" = libracolour ]; then
    EPD=$(find_bin veradroid-epd) || true
    if [ -n "$EPD" ] && ! strings "$EPD" 2>/dev/null | grep -Eq 'Libra ?Colour|LibraColour|N428|monza'; then
        echo "  WARN veradroid-epd does not look like it was built against FBInk with" >&2
        echo "       Kobo Libra Colour support. The panel will not refresh on N428;" >&2
        echo "       rebuild it with FBInk >= 1.25.0-544 (tools/kobo/build-kobo-bin.sh)." >&2
    fi
    FB=$(find_bin fbink) || true
    if [ -n "$FB" ] && ! strings "$FB" 2>/dev/null | grep -Eq 'Libra ?Colour|LibraColour|N428|monza'; then
        echo "  WARN fbink does not look like it knows the Libra Colour (N428)." >&2
        echo "       Build FBInk >= 1.25.0-544 with FBINK_FOR_KOBO; an older FBInk prints" >&2
        echo "       'Unidentified Kobo device code' and the panel will not refresh." >&2
    fi
fi

for s in "$TOP"/host/kobo/install.sh "$TOP"/host/kobo/boot/*.sh "$TOP"/host/kobo/boot/lib/*.sh \
         "$TOP"/tools/kobo/weread-speed-profile.sh "$TOP"/tools/kobo/compile-boot-nodebug.sh; do
    [ -f "$s" ] || continue
    sh -n "$s" || { echo "build-release: shell syntax error in $s" >&2; exit 2; }
done
echo "  OK  All host shell scripts passed sh -n syntax check"

stage_common() {
    root=$1
    pkg_type=$2
    vd="$root/.adds/${PKG_NAME}"
    mkdir -p "$vd/bin" "$vd/boot" "$vd/models" "$vd/kmod" "$vd/koplugin" "$vd/nm" \
             "$vd/apps" "$vd/screensaver" "$vd/update" \
             "$root/.adds/nm" "$root/.adds/koreader/plugins"

    # Host scripts & configs
    cp "$TOP/host/kobo/VERSION" "$vd/VERSION"
    cp "$TOP/host/kobo/install.sh" "$vd/install.sh"
    cp -a "$TOP/host/kobo/boot/." "$vd/boot/"
    cp "$TOP/tools/kobo/weread-speed-profile.sh" "$vd/boot/weread-speed-profile.sh"
    cp "$TOP/tools/kobo/compile-boot-nodebug.sh" "$vd/boot/compile-boot-nodebug.sh"
    [ -d "$TOP/diagnostics/kobo" ] && cp -a "$TOP/diagnostics/kobo" "$vd/diagnostics"
    # Ship only this model's profile: installing the wrong package then fails
    # loudly in install.sh instead of silently booting with wrong hardware paths.
    cp "$TOP/host/kobo/models/$KOBO_MODEL.conf" "$vd/models/"
    cp -a "$TOP/host/kobo/koplugin/${PKG_NAME}.koplugin" "$vd/koplugin/"
    cp "$TOP/host/kobo/nm/${PKG_NAME}" "$vd/nm/${PKG_NAME}"

    # Dual entry points installed directly into .adds/nm and .adds/koreader/plugins
    cp "$TOP/host/kobo/nm/${PKG_NAME}" "$root/.adds/nm/${PKG_NAME}"
    cp -a "$TOP/host/kobo/koplugin/${PKG_NAME}.koplugin" "$root/.adds/koreader/plugins/"

    # Binaries
    for b in $REQ_BINS; do
        p=$(find_bin "$b")
        cp "$p" "$vd/bin/$b"
    done

    # Kernel modules for this model's verified firmware kernel(s)
    for kver in $KMOD_KERS; do
        if [ -d "$KMOD_DIR/$kver" ]; then
            mkdir -p "$vd/kmod/$kver"
            cp "$KMOD_DIR/$kver"/*.ko "$vd/kmod/$kver/"
            for mf in SHA256SUMS README.md firmware; do
                [ -f "$KMOD_DIR/$kver/$mf" ] && cp "$KMOD_DIR/$kver/$mf" "$vd/kmod/$kver/"
            done
        fi
    done

    # update/ README
    cat > "$vd/update/README.txt" <<EOF
${PKG_NAME} — 离线升级目录

将增量升级包（${PKG_NAME}-<版本>-upgrade.zip）放入本目录，
然后通过以下任一方式即可自动完成升级（保留全部已安装应用、书籍与设置）：
  1. 在 NickelMenu 中点击「${PKG_NAME} 检查更新」或直接启动 ${PKG_NAME}；
  2. 在 KOReader 中点击「工具 → ${PKG_NAME} → 应用离线升级包」或直接启动 ${PKG_NAME}。
EOF

    # Permissions
    chmod 755 "$vd/install.sh" "$vd/boot/"*.sh "$vd/boot/lib/localupdate.sh"
    [ -d "$vd/diagnostics" ] && chmod 755 "$vd/diagnostics"/*.sh 2>/dev/null || true
    chmod 755 "$vd/bin/veradroid-epd" "$vd/bin/veradroid-input" "$vd/bin/pivot_init" \
              "$vd/bin/vdlmk" "$vd/bin/vdloopdio" "$vd/bin/vdmkswap" "$vd/bin/vdnocap" \
              "$vd/bin/vdsqueeze" "$vd/bin/e2fsck" "$vd/bin/mke2fs" "$vd/bin/resize2fs" \
              "$vd/bin/fbink" "$vd/bin/fbdepth" "$vd/bin/fbink-img" "$vd/bin/kobo-sdcard"
    chmod 644 "$vd/bin/VeraHome.apk" "$vd/bin/hwcomposer.kindle.so" "$vd/bin/libkobo_madvise.so" \
              "$vd/bin/kobo-weread-opt.jar" "$vd/bin/ethernet-service-wifi.jar"

    # Root README for end users (ASCII filename avoids Windows/BusyBox unzip mojibake)
    MODEL_NOTE=
    if [ "$KOBO_MODEL" = libracolour ]; then
        MODEL_NOTE="
注意（Libra Colour 彩色屏）：
- 当前显示桥把 Android 画面转换为 8 位灰度输出，彩色内容会以灰阶显示；
  这是为墨水屏文字锐利度与刷新速度做的取舍，不影响微信读书等文字类应用。
- 必须使用支持 N428 / Libra Colour 的 FBInk（>= 1.25.0-544）构建的 fbink，
  旧版 FBInk 会报 Unidentified Kobo device code 且屏幕不刷新。
- 内核模块仅匹配 4.9.77（固件 4.42.23303）；升级 Kobo 固件后需重新获取对应模块。
"
    fi
    cat > "$root/README-INSTALL.txt" <<EOF
================================================================
${PKG_NAME} (${MODEL_NAME} / ${MODEL_CODE})  v${VER} (${pkg_type})
构建日期：${BUILD_DATE}
支持固件内核：${FW_TEXT}
支持启动入口：NickelMenu（无需 KOReader）与 KOReader 插件
================================================================

一、全新安装（使用 full 完整包）
----------------------------------------------------------------
1. 确保 ${MODEL_NAME} 剩余空间 >= 2.5 GB。
2. 用数据线将 Kobo 连接电脑，打开 Kobo U 盘根目录。
3. 将本压缩包内的「.adds」文件夹完整解压合并到 Kobo 根目录：
   - .adds/${PKG_NAME}/                                （主程序与纯净 Android 镜像）
   - .adds/nm/${PKG_NAME}                              （NickelMenu 菜单入口）
   - .adds/koreader/plugins/${PKG_NAME}.koplugin/      （KOReader 插件入口）
4. 安全弹出 USB，直接从以下任一入口启动：
   - NickelMenu 入口：右下角 NickelMenu → ${PKG_NAME} (Android)
   - KOReader 入口：顶部菜单 → 工具 → ${PKG_NAME} → 启动 ${PKG_NAME} (Android)
5. 首次启动会自动创建 2 GB ext4 系统镜像（约 1–2 分钟，屏幕有进度提示，请勿关机），
   完成后自动进入 Android 桌面，并自动删除临时的 rootfs.tar.gz 释放空间。
   （若习惯 SSH 安装，也可运行：sh /mnt/onboard/.adds/${PKG_NAME}/install.sh）

二、增量升级（使用 upgrade 升级包，保留全部应用/书籍/设置）
----------------------------------------------------------------
方式 A（推荐，无需覆盖目录）：
  将 ${PKG_NAME}-${VER}-upgrade.zip 直接放入 Kobo 的：
    .adds/${PKG_NAME}/update/
  弹出 USB 后，点击 NickelMenu「${PKG_NAME} 检查更新」/ KOReader「应用离线升级包」，
  或直接启动 ${PKG_NAME}，系统会自动校验 SHA-256 并完成增量升级（失败自动回滚）。

方式 B（USB 直接覆盖）：
  将升级包内的「.adds」目录直接解压覆盖到 Kobo 根目录即可。
  升级包不含 veradroid-sys.img，不会清除已安装的微信读书、书籍、设置或阅读记录。

三、安装第三方应用（如微信读书墨水屏版）
----------------------------------------------------------------
- 本安装包为纯净系统，不含任何个人数据或第三方应用。
- 安装应用方式：
  1. 进入桌面 → 应用商店直接下载安装；或
  2. 将 32 位 ARM（armeabi-v7a）APK 放入 .adds/${PKG_NAME}/apps/ 后启动自动安装；或
  3. 使用桌面「传书与安装」网页通过局域网上传安装。

四、退出与常用操作
----------------------------------------------------------------
- 返回 Kobo / KOReader：长按屏幕左下角 2 秒，或在下拉面板点击「返回 Kobo」。
- 实体翻页键：上键下一页、下键上一页；长按上键全刷去残影、长按下键返回。
- 电源键：短按休眠进入深度待机（省电），再按唤醒。
${MODEL_NOTE}
EOF
}

write_manifest_and_sums() {
    root=$1
    pkg_type=$2
    vd="$root/.adds/${PKG_NAME}"
    rootfs_sha=""
    if [ -f "$vd/rootfs.tar.gz" ]; then
        rootfs_sha=$(shasum -a 256 "$vd/rootfs.tar.gz" | awk '{print $1}')
    fi
    cat > "$vd/manifest.json" <<EOF
{
  "product": "${PRODUCT_ID}",
  "name": "${PKG_NAME}",
  "model": "${KOBO_MODEL}",
  "version": "${VER}",
  "raw_version": "${RAW_VER}",
  "type": "${pkg_type}",
  "build_date": "${BUILD_DATE}",
  "entries": ["nickelmenu", "koreader"],
  "rootfs_sha256": "${rootfs_sha}"
}
EOF
    find "$root" \( -name '.DS_Store' -o -name '._*' -o -name '*.idsig' \) -delete
    (
        cd "$vd"
        find . -type f ! -name 'SHA256SUMS' | sed 's|^\./||' | sort | while IFS= read -r rel; do
            shasum -a 256 "$rel"
        done > SHA256SUMS
    )
}

audit_stage() {
    root=$1
    label=$2
    vd="$root/.adds/${PKG_NAME}"
    echo "=== Auditing $label for personal data & forbidden files ==="
    bad_files=$(find "$root" \( \
        -name 'veradroid-sys.img' -o -name 'battery.log' -o -name 'settings.conf' -o \
        -name 'settings.apps' -o -name 'kobo-screen.raw' -o -name '*.log' -o \
        -name '.DS_Store' -o -name '._*' -o -name 'wpa_supplicant*' -o \
        -name '*weread*.apk' -o -name 'WRBook*' -o -name 'WRReader*' -o -name 'WRAccount*' \
    \) 2>/dev/null || true)
    if [ -n "$bad_files" ]; then
        echo "AUDIT FAILED ($label): forbidden files found:" >&2
        echo "$bad_files" >&2
        exit 10
    fi

    extra_apks=$(find "$root" -name '*.apk' ! -name 'VeraHome.apk' 2>/dev/null || true)
    if [ -n "$extra_apks" ]; then
        echo "AUDIT FAILED ($label): unexpected APK(s) found:" >&2
        echo "$extra_apks" >&2
        exit 10
    fi

    personal_pat='192\.168\.[0-9]+\.[0-9]+|/Users/[^/[:space:]]+|/home/[^/[:space:]]+'
    [ -n "${AUDIT_EXTRA_PATTERNS:-}" ] && personal_pat="${personal_pat}|${AUDIT_EXTRA_PATTERNS}"
    personal_hits=$(grep -rnI -E "$personal_pat" \
        "$vd/boot" \
        "$vd/models" \
        "$vd/nm" \
        "$vd/koplugin" \
        "$vd/install.sh" \
        "$vd/manifest.json" \
        "$root/.adds/nm" \
        "$root/.adds/koreader" \
        "$root/README-INSTALL.txt" 2>/dev/null || true)
    if [ -n "$personal_hits" ]; then
        echo "AUDIT FAILED ($label): personal string detected:" >&2
        echo "$personal_hits" >&2
        exit 11
    fi

    if [ -d "$vd/seed" ]; then
        seed_hits=$(grep -rnI -iE 'weread|6307b89fb17c2462' "$vd/seed" 2>/dev/null || true)
        if [ -n "$seed_hits" ]; then
            echo "AUDIT FAILED ($label): un-scrubbed entry in seed/:" >&2
            echo "$seed_hits" >&2
            exit 12
        fi
    fi

    if [ -f "$vd/rootfs.tar.gz" ]; then
        rfs_hits=$(tar -tzf "$vd/rootfs.tar.gz" | grep -iE 'weread|WRBook|WRReader|WRAccount|/data/app/|/data/data/' || true)
        if [ -n "$rfs_hits" ]; then
            echo "AUDIT FAILED ($label): unexpected data in rootfs.tar.gz:" >&2
            echo "$rfs_hits" >&2
            exit 13
        fi
    fi

    echo "  PASS  $label privacy & hygiene audit clean!"
}

# ==============================================================================
# Build 1: FULL package (Fresh Install + safe over existing install)
# ==============================================================================
echo "=== [2/5] Staging FULL package (Fresh Install) ==="
FULL_STAGE=$WORK/full
stage_common "$FULL_STAGE" "full"
FULL_VD="$FULL_STAGE/.adds/${PKG_NAME}"

mkdir -p "$FULL_VD/fonts" "$FULL_VD/seed/user0"
cp "$LEGACY_DIR/rootfs.tar.gz" "$FULL_VD/rootfs.tar.gz"
[ -f "$LEGACY_DIR/fonts/LXGWWenKai-Regular.ttf" ] && cp "$LEGACY_DIR/fonts/LXGWWenKai-Regular.ttf" "$FULL_VD/fonts/"
[ -f "$LEGACY_DIR/fonts/OFL.txt" ] && cp "$LEGACY_DIR/fonts/OFL.txt" "$FULL_VD/fonts/"

# Copy and scrub clean user0 seed (strip WeRead stubs & static android_id; init-sysimg.sh generates fresh random ID)
cp "$LEGACY_DIR/user0.xml" "$FULL_VD/seed/user0.xml"
cp "$LEGACY_DIR/user0/"*.xml "$FULL_VD/seed/user0/"
python3 - "$FULL_VD/seed/user0" <<'PY'
import os, re, sys
d = sys.argv[1]
for fn in os.listdir(d):
    if not fn.endswith('.xml'):
        continue
    p = os.path.join(d, fn)
    s = open(p, 'r', encoding='utf-8').read()
    s = re.sub(r'[ \t]*<pkg\s+name="com\.tencent\.weread\.eink"[^>]*>.*?</pkg>\r?\n?', '', s, flags=re.S)
    s = re.sub(r'[ \t]*<(?:pkg|package)\s+name="com\.tencent\.weread\.eink"[^/>]*/>\r?\n?', '', s)
    s = re.sub(r'(name="android_id"\s+value=")[0-9a-fA-F]+(")', r'\g<1>0000000000000000\g<2>', s)
    open(p, 'w', encoding='utf-8').write(s)
PY
chmod 644 "$FULL_VD/seed/user0.xml" "$FULL_VD/seed/user0/"*.xml

write_manifest_and_sums "$FULL_STAGE" "full"
audit_stage "$FULL_STAGE" "FULL"

# ==============================================================================
# Build 2: UPGRADE package (Lightweight Incremental Upgrade)
# ==============================================================================
echo "=== [3/5] Staging UPGRADE package (Incremental Upgrade) ==="
UPG_STAGE=$WORK/upgrade
stage_common "$UPG_STAGE" "upgrade"
write_manifest_and_sums "$UPG_STAGE" "upgrade"
audit_stage "$UPG_STAGE" "UPGRADE"

# ==============================================================================
# Zip archives cleanly (no macOS resource forks / extended attributes)
# ==============================================================================
echo "=== [4/5] Creating ZIP archives in $OUT_DIR ==="
FULL_ZIP="$OUT_DIR/${PKG_NAME}-${VER}-full.zip"
UPG_ZIP="$OUT_DIR/${PKG_NAME}-${VER}-upgrade.zip"
rm -f "$FULL_ZIP" "$UPG_ZIP" "$OUT_DIR/SHA256SUMS.txt"

( cd "$FULL_STAGE" && zip -q -r -X "$FULL_ZIP" .adds README-INSTALL.txt )
( cd "$UPG_STAGE"  && zip -q -r -X "$UPG_ZIP"  .adds README-INSTALL.txt )

(
    cd "$OUT_DIR"
    shasum -a 256 "${PKG_NAME}-${VER}-full.zip" "${PKG_NAME}-${VER}-upgrade.zip" > SHA256SUMS.txt
)

echo "=== [5/5] Verifying ZIP integrity ==="
unzip -tq "$FULL_ZIP"
unzip -tq "$UPG_ZIP"
rm -rf "$WORK"

echo ""
echo "Release packages built successfully:"
ls -lh "$FULL_ZIP" "$UPG_ZIP" "$OUT_DIR/SHA256SUMS.txt"
cat "$OUT_DIR/SHA256SUMS.txt"
