#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Static armhf resize2fs / e2fsck / e2undo for the VeraDroid host bundle
#   sh build-e2fs.sh <out dir>
# Toolchain: vdcross-legacy (gcc 5 + glibc 2.19, static binaries start on 3.0 kernels too).
set -eu
OUT=$1; V=1.47.1; B=${E2FS_BUILD:-${VD_BUILD:-$HOME/veradroid-build}/build/e2fsprogs}
mkdir -p "$B" "$OUT"
[ -f "$B/e2fsprogs-$V.tar.gz" ] || curl -fsSL -o "$B/e2fsprogs-$V.tar.gz" "https://mirrors.edge.kernel.org/pub/linux/kernel/people/tytso/e2fsprogs/v$V/e2fsprogs-$V.tar.gz"
echo "$(sha256sum "$B/e2fsprogs-$V.tar.gz" | cut -c1-64)  e2fsprogs-$V.tar.gz"
rm -rf "$B/src"; mkdir -p "$B/src"; tar xzf "$B/e2fsprogs-$V.tar.gz" -C "$B/src" --strip-components=1
nice -n 12 docker run --rm --cpus=4 --memory=6g -v "$B/src":/s -v "$OUT":/o vdcross-legacy:gcc5-glibc219 sh -c '
set -e
# e2fsprogs builds a few generators with the native compiler (BUILD_CC)
command -v gcc >/dev/null || { apt-get update -qq >/dev/null && apt-get install -y -qq --no-install-recommends gcc libc6-dev >/dev/null; }
cd /s; mkdir -p build; cd build
../configure --host=arm-linux-gnueabihf CC=arm-linux-gnueabihf-gcc BUILD_CC=gcc CFLAGS="-Os" LDFLAGS="-static" \
  --disable-nls --disable-defrag --disable-debugfs --disable-imager --disable-uuidd --disable-fuse2fs --disable-tdb \
  --disable-mmp --disable-bmap-stats --disable-e2initrd-helper --disable-backtrace --disable-rpath --disable-fsck >/dev/null
make -j4 libs >/dev/null 2>&1 || make libs
make -C e2fsck e2fsck >/dev/null; make -C resize resize2fs >/dev/null; make -C misc e2undo >/dev/null
for p in e2fsck/e2fsck resize/resize2fs misc/e2undo; do arm-linux-gnueabihf-strip $p; cp $p /o/; done
chmod 755 /o/*; ls -la /o; file /o/*'
