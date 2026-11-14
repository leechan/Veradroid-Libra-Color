#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build zram as an out-of-tree module for the Kindle 3.0.35 kernels (PW2 / PW3 / Voyage / Kindle 7th gen: imx60_wario).
# Their kernels have CONFIG_SWAP=y but no zram; Amazon's own GPL tree has drivers/staging/zram (zram + xvmalloc) and the
# kernel has LZO built in (CONFIG_LZO_COMPRESS/DECOMPRESS=y, exported). (docker vdaosp:7.1, AOSP arm gcc 4.9).
#
#   sh build-zram.sh <amazon linux-3.0.35 tree> <defconfig, e.g. imx60_wario_defconfig> <device /proc/kallsyms> <out dir>
#
# The tree is the one from Amazon's Kindle_src_<firmware>.tar.gz (gplrelease/linux-3.0.35.tar.gz), extracted into an empty dir.
# The kernels have no MODVERSIONS: only the vermagic string ("3.0.35-lab126 preempt mod_unload ARMv7") has to match.
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (src/ = AOSP android-7.1.1_r61 tree, out/, kmod/)}"
export LC_ALL=C
KDIR=$(cd "$1" && pwd); CFG=$2; KSYMS=$(cd "$(dirname "$3")" && pwd)/$(basename "$3"); OUT=$4
TCD=$AOSP_WORK/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9
TC=$TCD/bin/arm-linux-androideabi-
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd); rm -rf "$OUT/m"; mkdir -p "$OUT/m"
cp "$KDIR"/drivers/staging/zram/*.[ch] "$OUT/m/"
cat > "$OUT/m/Makefile" <<'MK'
obj-m := zram.o
zram-y := zram_drv.o zram_sysfs.o xvmalloc.o
ccflags-y := -I$(src) -fno-pic -DCONFIG_ZRAM_DEBUG=0 -UCONFIG_ZRAM_DEBUG
MK
kb() {
    docker run --rm --cpus=6 --memory=8g -v "$KDIR":"$KDIR" -v "$OUT":"$OUT" -v "$TCD":"$TCD":ro -w "$KDIR" vdaosp:7.1 sh -c "
        set -e; export ARCH=arm CROSS_COMPILE=$TC; $1; chmod -R a+rwX $OUT"
}
kb "[ -f .config ] || { nice -n 12 make $CFG >/dev/null; sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-lab126\"/' .config; (yes '' | nice -n 12 make oldconfig) >/dev/null 2>&1; nice -n 12 make -j6 modules_prepare >/dev/null 2>&1; }; echo prepared"
kb "nice -n 12 make -j6 M=$OUT/m modules 2>&1 | grep -E 'error|warning: implicit|WARNING' || true"
cp "$OUT/m/zram.ko" "$OUT/"
${TC}nm -u "$OUT/zram.ko" | awk '{print $2}' | grep -v '^__aeabi_\|^__gnu_mcount_nc$' | sort -u > "$OUT/undef.txt"
grep -E ' __ksymtab_' "$KSYMS" | sed 's/.* __ksymtab_//' | sort -u > "$OUT/exported.txt"
comm -23 "$OUT/undef.txt" "$OUT/exported.txt" > "$OUT/missing.txt" || true
if [ -s "$OUT/missing.txt" ]; then echo "not exported by the device kernel: $(tr '\n' ' ' < "$OUT/missing.txt")"; exit 1; fi
strings "$OUT/zram.ko" | grep '^vermagic='
ls -la "$OUT/zram.ko"
