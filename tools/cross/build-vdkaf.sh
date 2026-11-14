#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build bin/vdkaf for the legacy bundle (tools/vdkaf/vdkaf.c; see host/legacy/boot/lib/framework.sh, KINDLE_UI=stop).
# Builds bin/vdkaf-sf.  sh build-vdkaf.sh <dir with vdkaf.c> <out dir> <a Kindle's /usr/lib/liblipc.so.1.0 (soft-float firmware)>
# The bundle carries two binaries, both dynamically linked against the Kindle's own liblipc at run time:
#   vdkaf     hard-float (/lib/ld-linux-armhf.so.3, firmware 5.16+): the build from feat/slim (host/k49/bin/vdkaf; its recipe
#             is in the header of vdkaf.c and needs a hard-float liblipc.so to link against). Not built here.
#   vdkaf-sf  soft-float (/lib/ld-linux.so.3: PW2 5.12, Voyage 5.13 …). vdcross-legacy has no soft-float gcc, so the object is
#             compiled with -mfloat-abi=soft (vdkaf passes no floating-point values) and linked by hand against the soft-float
#             glibc 2.19 of the vdcross-legacy:14.04 image. Needs only GLIBC_2.4 symbols; tested on pw2-5122 (5.12.2.2):
#             with the framework stopped the power key works only while vdkaf runs.
set -eu
SRC=$1; OUT=$2; LIPC=$3
B=$(mktemp -d "${TMPDIR:-/tmp}/vdkaf-build.XXXXXX"); trap 'rm -rf "$B"' EXIT
mkdir -p "$B/kl" "$OUT"; cp "$SRC/vdkaf.c" "$B/"; cp "$LIPC" "$B/kl/liblipc.so"
c=$(docker create vdcross-legacy:14.04); docker cp "$c:/usr/arm-linux-gnueabi" "$B/sf"; docker rm "$c" >/dev/null
nice -n 12 docker run --rm -v "$B":/w vdcross-legacy:gcc5-glibc219 sh -c 'set -e; cd /w
arm-linux-gnueabihf-gcc -O2 -Wall -mfloat-abi=soft -fno-stack-protector -c vdkaf.c -o vdkaf-sf.o
arm-linux-gnueabihf-ld -o vdkaf-sf -dynamic-linker /lib/ld-linux.so.3 sf/lib/crt1.o sf/lib/crti.o vdkaf-sf.o -Lsf/lib kl/liblipc.so \
    sf/lib/libc.so.6 sf/lib/libc_nonshared.a sf/lib/crtn.o --allow-shlib-undefined -rpath /usr/lib
arm-linux-gnueabihf-strip vdkaf-sf'
cp "$B/vdkaf-sf" "$OUT/"; chmod 755 "$OUT/vdkaf-sf"
file "$OUT/vdkaf-sf"
