#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the Android system images (rootfs.tar.gz) from this checkout.
#   AOSP_WORK=<dir> sh tools/build/build_rootfs.sh prepare|sync|pw6|k49|repack <flavour>|all
#
# Flavours:
#   pw6  product veradroid_kindle (Cortex-A53, 64-bit binder = binder protocol 8, Kindle 5.15 kernels)
#   k49  the same product with TARGET_USES_64_BIT_BINDER=false (libbinder, servicemanager, healthd use binder
#        protocol 7: the 4.9 kernels of PW5 / KT5 / KT6 / Scribe), plus 512 MB-class heap defaults
#        in init.kindle.rc / build.prop (boot/lib/memory.sh rewrites build.prop per device anyway).
#   The legacy bundle (3.0 / 4.1 kernels, Cortex-A9) is a different product (veradroid_kindle32); not built here.
#
# Layout of $AOSP_WORK:
#   src/            AOSP android-7.1.1_r61 (repo sync), left untouched
#   out/            optional earlier build output of src/ (copied once to speed up the first build)
#   src-big/        private copy of src/ that the patches from android/ are applied to
#   out-big/, out-big32/   build output of the pw6 / k49 flavours
#   ccache/         compiler cache;  cacerts-extra/  optional current Mozilla CA files (*.0) added to the image
# Builds run in the docker image vdaosp:7.1 (tools/build/Dockerfile.aosp).
# WORK=<git checkout> (default: this repository).  Output: $DEST/rootfs-<flavour>-<git>.tar.gz (+ .sha256)
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (see the header of this script)}"
if [ -z "${VD_BUILD_LOCKED:-}" ] && command -v flock >/dev/null; then VD_BUILD_LOCKED=1 exec flock "$AOSP_WORK/.build.lock" sh "$0" "$@"; fi
A=$AOSP_WORK; WORK=${WORK:-$(cd "$(dirname "$0")/../.." && pwd)}
SRC=$A/src-big; O64=$A/out-big; O32=$A/out-big32; DEST=${DEST:-$A/rootfs}
REV=$(git -C "$WORK" rev-parse --short HEAD)
BC=$SRC/device/veradroid/kindle/BoardConfig.mk
# veradroid_kindle_slim = veradroid_kindle + slim.mk (trimmed preloaded-classes / boot image classes, no media helper
# daemons, no boot animation process, config.disable_* switches; docs/slim-android.md). PRODUCT=veradroid_kindle: plain.
PRODUCT=${PRODUCT:-veradroid_kindle_slim}
mkdir -p "$DEST" "$A/log"

prepare() {
    [ -d "$SRC" ] || nice -n 15 cp -a --reflink=auto "$A/src" "$SRC"
    [ -d "$O64" ] || { if [ -d "$A/out" ]; then nice -n 15 cp -a --reflink=auto "$A/out" "$O64"; else mkdir -p "$O64"; fi; }
}
sync_src() {
    # device config, source overlays, VeraHome dir, small patches (apply-patches.sh), then what apply-patches does not do
    sh "$WORK/android/apply-patches.sh" "$SRC" | grep -v '^already\|^overlay:' || true
    rm -rf "$SRC/device/veradroid/kindle32"; cp -R "$WORK/android/device/veradroid/kindle32" "$SRC/device/veradroid/kindle32"
    chmod 644 "$SRC/device/veradroid/kindle/init.kindle.rc"
    # packages/apps/Android.mk defines VeraHome (manifest = packages/apps/AndroidManifest.xml) and includes VeraIME.
    # Ours (android/packages/apps-Android.mk); the stock one would also pull in Bluetooth (not shipped).
    cp "$WORK/android/packages/apps-Android.mk" "$SRC/packages/apps/Android.mk"
    # packages/apps/res = the VeraHome module's default resource dir (LOCAL_PATH is packages/apps). It only holds two files
    # left over from an early VeraIME (app_name, input-method xml); VeraHome references neither, but they are in the shipped
    # VeraHome.apk, so they are kept byte-identical from git until a release that may change the APK drops them.
    rm -rf "$SRC/packages/apps/res"; cp -R "$WORK/android/packages/apps-res" "$SRC/packages/apps/res"
    cp "$WORK/android/packages/VeraHome/AndroidManifest.xml" "$SRC/packages/apps/AndroidManifest.xml"
    rm -f "$SRC/packages/apps/VeraHome/Android.mk"
    W=$WORK/android/packages/VeraIME; D=$SRC/packages/apps/VeraIME
    for d in src res assets; do rm -rf "$D/$d"; cp -a "$W/$d" "$D/$d"; done
    cp "$W/AndroidManifest.xml" "$W/Android.mk" "$D/"
    find "$SRC/device/veradroid" "$SRC/packages/apps/VeraHome" "$D" -name '._*' -delete
    chmod -R a+rX "$SRC/device/veradroid" "$SRC/packages/apps/VeraHome" "$D" "$SRC/packages/apps/AndroidManifest.xml"
    grep -q 'config_enableWallpaperService">false' "$SRC/device/veradroid/kindle/overlay/frameworks/base/core/res/res/values/config.xml"
    echo "synced $REV into $SRC"
}
build() { # out-dir log
    docker ps --format '{{.Names}}' | grep -q '^vdbuild' && { echo "another vdbuild container is running" >&2; exit 1; }
    docker run --rm --name vdbuild-big \
        --tmpfs /aosp/out/target/product/kindle/dex_bootjars:rw,exec,size=3g,uid=1000,gid=1000,mode=0755 \
        --cpus=6 --memory=14g --memory-swap=18g \
        -v "$SRC":/aosp/src -v "$1":/aosp/out -v "$A/ccache":/aosp/ccache \
        -e USER=builder -e OUT_DIR=/aosp/out -e USE_CCACHE=1 -e CCACHE_DIR=/aosp/ccache -e CCACHE_MAXSIZE=30G \
        -e ANDROID_JACK_VM_ARGS='-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx3g' \
        -e PRODUCT=$PRODUCT vdaosp:7.1 bash -c 'cd /aosp/src && source build/envsetup.sh >/dev/null && lunch $PRODUCT-userdebug >/dev/null &&
            P=/aosp/out/target/product/kindle && rm -rf $P/system $P/root $P/data $P/obj/PACKAGING $P/*.img $P/installed-files*.txt && nice -n 12 make -j6 systemimage ramdisk; echo BUILD-EXIT=$?' > "$2" 2>&1
    tail -1 "$2" | grep -q 'BUILD-EXIT=0' || { tail -30 "$2"; exit 1; }
}
pack() { # flavour product-dir
    P=$2; ST=$DEST/stage-$1; rm -rf "$ST"; mkdir -p "$ST"
    cp -a "$P/root/." "$ST/"; cp -a "$P/system/." "$ST/system/"
    for d in data cache mnt storage sdcard dev proc sys; do [ -e "$ST/$d" ] || [ -L "$ST/$d" ] || mkdir "$ST/$d"; done
    mkdir -p "$ST/storage/emulated/0"
    # Some build-host file systems hand out ACL-style modes (directories 0700, files 0705 / 0604 ...); tar only keeps the mode bits,
    # and inside the container non-root services (servicemanager runs as system) then cannot even reach /system/bin
    # ("cannot execve: Permission denied", servicemanager exit 127, zygote never starts). Normalise like an image would be:
    # directories 0755, executables 0755, everything else 0644.
    find "$ST" -type d -exec chmod 755 {} +
    find "$ST" -type f -perm /111 -exec chmod 755 {} +
    find "$ST" -type f ! -perm /111 -exec chmod 644 {} +
    for f in "$A"/cacerts-extra/*.[0-9]; do b=${f##*/}; [ -e "$ST/system/etc/security/cacerts/$b" ] || cp "$f" "$ST/system/etc/security/cacerts/$b"; done
    chmod 644 "$ST"/system/etc/security/cacerts/*
    # the security-relevant files keep their usual modes
    [ "$(stat -c %a "$ST/init.kindle.rc")" = 644 ] || { echo "init.kindle.rc is not 644" >&2; exit 1; }
    [ "$(find "$ST" ! -type l \( -perm -o+w -o -perm -g+w \) | wc -l)" = 0 ] || { echo "group/world writable files in the image" >&2; exit 1; }
    if [ "$1" = k49 ]; then
        # k49 heap defaults (512 MB class)
        sed -i 's/^on early-init$/on early-init\n    setprop dalvik.vm.heapsize 256m\n    setprop dalvik.vm.heapgrowthlimit 128m\n    setprop dalvik.vm.heapstartsize 4m/' "$ST/init.kindle.rc"
        printf '\n# PW5: 512 MB RAM; keep ART under the kernel/32-bit address-space limit\ndalvik.vm.heapstartsize=4m\ndalvik.vm.heapgrowthlimit=128m\ndalvik.vm.heapsize=256m\ndalvik.vm.heaptargetutilization=0.75\ndalvik.vm.heapminfree=512k\ndalvik.vm.heapmaxfree=8m\n' >> "$ST/system/build.prop"
    fi
    # what the images must have (the reasons for this rebuild)
    for f in system/lib/libGLESv2_vdnull.so system/bin/vold system/bin/installd system/framework/services.jar system/priv-app/PackageInstaller/PackageInstaller.apk system/app/HTMLViewer/HTMLViewer.apk init.kindle.rc; do
        [ -e "$ST/$f" ] || { echo "image $1 lacks $f" >&2; exit 1; }
    done
    for f in system/app/Bluetooth system/app/CtsShimPrebuilt system/priv-app/CtsShimPrivPrebuilt system/app/WallpaperBackup system/priv-app/BackupRestoreConfirmation system/priv-app/Settings; do
        [ -e "$ST/$f" ] && { echo "image $1 has $f (not wanted)" >&2; exit 1; }
    done
    grep -q 'VeraDroid: skipping non-whitelisted zygote fd' "$ST/system/lib/libandroid_runtime.so" || { echo "libandroid_runtime without the fd patch" >&2; exit 1; }
    for a in priv-app/VeraHome/VeraHome.apk app/VeraIME/VeraIME.apk; do
        unzip -l "$ST/system/$a" | grep -q ' classes.dex$' || { echo "$a has no classes.dex" >&2; exit 1; }
        [ -f "$ST/system/${a%/*}/oat/arm/$(basename "$a" .apk).odex" ] || { echo "$a has no odex" >&2; exit 1; }
    done
    # the bundle ships these exact files: the installer keeps the image's odex when they match
    cp "$ST/system/priv-app/VeraHome/VeraHome.apk" "$DEST/VeraHome-$1-$REV.apk"; cp "$ST/system/app/VeraIME/VeraIME.apk" "$DEST/VeraIME-$1-$REV.apk"
    cp "$ST/system/lib/libandroid_runtime.so" "$DEST/libandroid_runtime-$1-$REV.so"
    echo "ro.vd.image=$1-$REV" >> "$ST/system/build.prop"
    t=$DEST/rootfs-$1-$REV.tar.gz
    nice -n 12 tar --owner=0 --group=0 --numeric-owner -czf "$t.partial" -C "$ST" . && mv "$t.partial" "$t"
    (cd "$ST" && find . -type f -print0 | sort -z | xargs -0 md5sum) > "$DEST/rootfs-$1-$REV.md5"
    rm -rf "$ST"
    sha256sum "$t" | tee "$t.sha256"
}
case "${1:-all}" in
    prepare) prepare ;;
    sync) sync_src ;;
    pw6) sync_src; build "$O64" "$A/log/build-big-pw6.log"; pack pw6 "$O64/target/product/kindle" ;;
    repack) # repack pw6|k49: pack the image again from the last build of that flavour (no compile)
        case "${2:-}" in pw6) pack pw6 "$O64/target/product/kindle" ;; k49) pack k49 "$O32/target/product/kindle" ;; *) exit 2 ;; esac ;;
    k49)
        [ -d "$O32" ] || nice -n 15 cp -a --reflink=auto "$O64" "$O32"
        sync_src
        trap 'sed -i "s/^TARGET_USES_64_BIT_BINDER := false # k49$/TARGET_USES_64_BIT_BINDER := true/" "$BC"' EXIT
        sed -i 's/^TARGET_USES_64_BIT_BINDER := true$/TARGET_USES_64_BIT_BINDER := false # k49/' "$BC"
        grep -q 'BINDER := false # k49' "$BC"
        build "$O32" "$A/log/build-big-k49.log"; pack k49 "$O32/target/product/kindle" ;;
    all) prepare; sh "$0" pw6; sh "$0" k49 ;;
    *) echo "usage: prepare|sync|pw6|k49|all" >&2; exit 2 ;;
esac
