#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build binder / tun / uinput modules for a Kindle kernel that lacks them.
#   sh build.sh <kernel-version-dir> <device-config> <out-dir>
# e.g. sh build.sh linux-4.1.15 pw4.config out-pw4
# Uses the mainline tree for the same version plus the device's own /proc/config.gz,
# so struct layouts and modversion CRCs match as long as Amazon did not change the
# core headers (verified by loading the result on the emulator; never on a user device
# without that check). Runs inside the vdaosp:7.1 image with the AOSP arm gcc 4.9.
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (src/ = AOSP android-7.1.1_r61 tree, out/, kmod/)}"
KDIR=$1; CFG=$2; OUT=$3
HERE=$(cd "$(dirname "$0")" && pwd)
W=$AOSP_WORK/kmod
TC=$AOSP_WORK/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
cd $W
mkdir -p $OUT
rm -rf $OUT/binder && mkdir -p $OUT/binder
cp $KDIR/drivers/android/binder.c $KDIR/drivers/android/binder_trace.h $OUT/binder/
cp $HERE/vd_compat.h $OUT/binder/
# include the compat header after the last kernel header, resolve symbols at init,
# and register the device as /dev/vndbinder (the host scripts bind that one into Android).
sed -i 's|^#include "binder_trace.h"$|#include "binder_trace.h"\n#include "vd_compat.h"|; 0,/#include "vd_compat.h"/!{/#include "vd_compat.h"/d}' $OUT/binder/binder.c
sed -i 's|\.name = "binder",|.name = "vndbinder",|' $OUT/binder/binder.c
sed -i 's|^static int __init binder_init(void)$|static int __init binder_init(void)|; /^static int __init binder_init(void)/,/^{/{s|^{|{\n\tif (vd_resolve()) return -ENOENT;|}' $OUT/binder/binder.c
sed -i 's|^device_initcall(binder_init);|module_init(binder_init);|' $OUT/binder/binder.c
cat > $OUT/binder/Makefile <<'EOF'
obj-m := binder.o
ccflags-y := -I$(src) -DCONFIG_ANDROID_BINDER_IPC_32BIT=1
CFLAGS_binder.o := -DTRACE_INCLUDE_PATH=$(src)
EOF
docker run --rm --cpus=8 --memory=20g -v "$AOSP_WORK":"$AOSP_WORK" -w $W vdaosp:7.1 sh -c "
set -e
export ARCH=arm CROSS_COMPILE=$TC/bin/arm-linux-androideabi-
cd $KDIR
cp $W/$CFG .config
sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-lab126\"/; s/^# CONFIG_TUN is not set/CONFIG_TUN=m/; s/^# CONFIG_INPUT_UINPUT is not set/CONFIG_INPUT_UINPUT=m/' .config
nice -n 12 make olddefconfig >/dev/null
# full build: Module.symvers (modversion CRCs) only exists after vmlinux + modules are built
# KBUILD_MODPOST_WARN: some vendor modules in the tree reference Amazon-only symbols; we only need the CRCs
nice -n 12 make -j8 KBUILD_MODPOST_WARN=1 vmlinux modules > $W/$OUT/kbuild.log 2>&1 || { tail -20 $W/$OUT/kbuild.log; exit 1; }
nice -n 12 make -j8 M=$W/$OUT/binder modules 2>&1 | tail -8
cp drivers/net/tun.ko drivers/input/misc/uinput.ko $W/$OUT/
cp $W/$OUT/binder/binder.ko $W/$OUT/
chmod -R a+rwX $W/$OUT $W/$KDIR
"
ls -la $OUT/*.ko
