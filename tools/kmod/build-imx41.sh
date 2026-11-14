#!/bin/sh
# binder.ko + uinput.ko for one Kindle 4.1.15 kernel (PW4 / Kindle 2019 / Oasis 2 / Oasis 3)..
#
#   build-imx41.sh <name> <boot.img> <device-kallsyms> <out-dir>
#
# boot.img        the firmware's boot image (eink-emulator: firmware/versions/<model>/<fw>/boot.img)
# device-kallsyms /proc/kallsyms of that kernel (kptr_restrict is 0 on Kindles; the emulator boots the same kernel)
# out-dir         gets binder.ko, uinput.ko and uname-v (host/legacy/boot/lib/kmod.sh loads them only on a
#                 kernel whose `uname -v` is exactly that)
#
# Amazon does not publish these kernels' sources in a form we may fetch, and modules built from NXP's
# rel_imx_4.1.15_2.0.0_ga tree disagree with most of the device's modversion CRCs. The comments below explain
# what was different and how it was found; this script redoes the whole thing for one kernel:
#  1. unpack the kernel image and its config (kimage.py), read every exported CRC out of it (kcrc.py);
#  2. reference build of the NXP tree with the device config plus the two differences that change the
#     layout of structures modules touch: vmacache_seqnum is u64 (the CVE-2018-17182 fix Amazon backported;
#     shifts mm_struct and task_struct) and ZONE_DMA stays on when the device has it (shifts pglist_data);
#  3. compare the struct offsets the device kernel and the reference build use in the kernel functions that
#     touch everything binder and uinput touch (fieldcmp.py). Any difference stops the build;
#  4. build the modules against the reference tree, then give the imported symbols the device's CRCs
#     (modcrc.py): a mismatching CRC there only means some type somewhere in the symbol's closure differs
#     (e.g. struct net or struct sock), the fields these modules use were checked in step 3.
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (src/ = AOSP android-7.1.1_r61 tree, out/, kmod/)}"
NAME=$1; BOOT=$2; KSYMS=$3; OUT=$4
HERE=$(cd "$(dirname "$0")" && pwd)
W=${W:-$AOSP_WORK/kmod/imx41}
NXP=${NXP:-$AOSP_WORK/kmod/imx-4.1.15.tar.gz}
TC=$AOSP_WORK/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
LIMITS=${LIMITS:---cpus=4 --memory=6g}
mkdir -p "$W" "$OUT"; cd "$W"
KSYMS=$(readlink -f "$KSYMS")

# 1. device kernel
python3 "$HERE/kimage.py" "$BOOT" "$NAME" > "$NAME.banner"
UNAMEV=$(sed -n 's/^Linux version .*) \(#.*\)$/\1/p' "$NAME.banner")
[ -n "$UNAMEV" ] || { echo "no version banner in $BOOT" >&2; exit 1; }
python3 "$HERE/kcrc.py" "$NAME.Image" "$KSYMS" > "$NAME.crcs"
echo "$NAME: $(wc -l < "$NAME.crcs") exported CRCs, uname -v: $UNAMEV"

# 2. reference tree
R=ref-$NAME
if [ ! -d "$R" ]; then
    rm -rf "$R.tmp"; mkdir "$R.tmp"; tar -xzf "$NXP" -C "$R.tmp"
    mv "$R.tmp/$(ls "$R.tmp" | head -1)" "$R"; rmdir "$R.tmp"
    sed -i 's/^\tu32 vmacache_seqnum;\(.*\)$/\tu64 vmacache_seqnum;\1/' "$R/include/linux/mm_types.h" "$R/include/linux/sched.h"
    [ "$(grep -c 'u64 vmacache_seqnum;' "$R/include/linux/mm_types.h" "$R/include/linux/sched.h" | grep -c ':1$')" = 2 ] || { echo "vmacache patch failed" >&2; exit 1; }
    # ZONE_DMA has no prompt in this tree (Amazon's SOC_IMX6SLL selects it): give it one so the device value stays
    sed -i '/^config ZONE_DMA$/{n;s/^\tbool$/\tbool "DMA zone (VeraDroid: keep the device value)"/}' "$R/arch/arm/Kconfig"
    # struct kobj_uevent_env: the Oasis kernels have 64 env pointers instead of 32 (add_uevent_var compares
    # envp_idx with 63). Only reached through pointers, but it is in the CRC closure of everything kobject.
    a=$(awk -v f=add_uevent_var '$3 == f { print $1; exit }' "$KSYMS")
    n=$(${TC}objdump -D -b binary -marm --adjust-vma=0x80008000 --start-address=0x$a --stop-address=$(printf '0x%x' $((0x$a + 64))) "$NAME.Image" \
        | sed -n 's/.*cmp\tr[0-9]*, #\([0-9]*\)$/\1/p' | head -1)
    [ -n "$n" ] || { echo "cannot read UEVENT_NUM_ENVP from add_uevent_var" >&2; exit 1; }
    sed -i "s/^#define UEVENT_NUM_ENVP\t\t\t32\t/#define UEVENT_NUM_ENVP\t\t\t$((n + 1))\t/" "$R/include/linux/kobject.h"
    grep -q "^#define UEVENT_NUM_ENVP.*$((n + 1))" "$R/include/linux/kobject.h" || { echo "UEVENT_NUM_ENVP patch failed" >&2; exit 1; }
fi
# the Oasis configs carry LOCALVERSION="" + LOCALVERSION_AUTO; the release string is 4.1.15-lab126 everywhere
sed -e 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION="-lab126"/' -e 's/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/' \
    "$NAME.config" > "$NAME.build.config"
if [ ! -f "$R/vmlinux" ] || ! cmp -s "$NAME.build.config" "$R/.vd-config"; then
    cp "$NAME.build.config" "$R/.config"
    docker run --rm $LIMITS -v "$AOSP_WORK":"$AOSP_WORK" -w "$W/$R" vdaosp:7.1 sh -c "
        set -e; export ARCH=arm CROSS_COMPILE=$TC
        (nice -n 12 make olddefconfig || yes '' | nice -n 12 make oldconfig) > ../$NAME.olddefconfig.log 2>&1
        nice -n 12 make -j4 KBUILD_SYMTYPES=1 KBUILD_MODPOST_WARN=1 vmlinux modules > ../$NAME.kbuild.log 2>&1 || { tail -30 ../$NAME.kbuild.log; exit 1; }
        chmod -R a+rwX ."
    cp "$NAME.build.config" "$R/.vd-config"
fi
for o in CONFIG_ZONE_DMA CONFIG_HIGHMEM CONFIG_PREEMPT CONFIG_SMP CONFIG_MODVERSIONS; do
    a=$(grep "^$o=" "$NAME.config" || true); b=$(grep "^$o=" "$R/.config" || true)
    [ "$a" = "$b" ] || { echo "config differs after olddefconfig: '$a' vs '$b'" >&2; exit 1; }
done
${TC}objcopy -O binary "$R/vmlinux" "$R.Image"

# 3. struct offsets used by the device kernel vs the reference build
STRICT="get_task_mm vm_munmap vm_insert_page __lock_task_sighand get_files_struct __fd_install __close_fd put_files_struct
 dequeue_signal check_kill_permission sys_getpriority sys_nice special_mapping_fault __install_special_mapping
 generic_file_mmap vmap find_vm_area single_open seq_read sys_geteuid sys_gettid get_unused_fd_flags fd_install
 mutex_lock mutex_unlock down_write up_write __wake_up finish_wait seq_lseek seq_printf seq_puts __free_pages"
python3 "$HERE/fieldcmp.py" "$NAME.Image" "$KSYMS" "$R.Image" "$R/System.map" $STRICT > "verify-$NAME.txt"
if grep -v 'SAME-OFFSETS' "verify-$NAME.txt"; then
    echo "$NAME: the device kernel uses different struct offsets in the functions above; not building" >&2
    exit 1
fi
echo "$NAME: struct offsets agree in $(grep -c SAME-OFFSETS "verify-$NAME.txt") kernel functions"
# whole-layout checks through genksyms: these types (and everything they embed) must have been seen in a
# symbol whose CRC equals the device's. struct module: the loader reads our .gnu.linkonce.this_module;
# input_dev / file / miscdevice: uinput and binder use them directly.
python3 "$HERE/symclosure.py" "$R" "$NAME.crcs" s#module s#file s#seq_file s#file_operations s#miscdevice s#input_dev s#mutex \
    s#rw_semaphore t#wait_queue_head_t s#work_struct > "closure-$NAME.txt"
if grep 'layout NOT verified' "closure-$NAME.txt"; then
    echo "$NAME: a structure the modules depend on is not proven identical; not building" >&2
    exit 1
fi

# 4. modules
PREPARED=1 W=$W LIMITS="$LIMITS" sh "$HERE/build-binder.sh" "$R" "$NAME.build.config" "$R/drivers/android" "$KSYMS" "binder-$NAME"
rm -rf "uinput-$NAME"; mkdir -p "uinput-$NAME"
cp "$R/drivers/input/misc/uinput.c" "$R/drivers/input/input-compat.h" "uinput-$NAME/"
sed -i 's|"../input-compat.h"|"input-compat.h"|' "uinput-$NAME/uinput.c"
printf 'obj-m := uinput.o\nccflags-y := -fno-pic -I$(src)\n' > "uinput-$NAME/Makefile"
docker run --rm $LIMITS -v "$AOSP_WORK":"$AOSP_WORK" -w "$W/$R" vdaosp:7.1 sh -c "
    export ARCH=arm CROSS_COMPILE=$TC; nice -n 12 make M=$W/uinput-$NAME modules >/dev/null; chmod -R a+rwX $W/uinput-$NAME"
for m in binder-$NAME/binder.ko uinput-$NAME/uinput.ko; do
    b=$(basename "$m")
    set -- $(python3 "$HERE/modcrc.py" check "$m" "$NAME.crcs" | awk '$1 == "DIFF" { print $2 }')
    if python3 "$HERE/modcrc.py" check "$m" "$NAME.crcs" | grep -q '^MISSING'; then
        echo "$m imports a symbol the device kernel does not export" >&2; exit 1
    fi
    python3 "$HERE/modcrc.py" set "$m" "$NAME.crcs" "$OUT/$b" "$@"
    ${TC}strip --strip-debug "$OUT/$b"
    echo "$b: device CRCs for $# symbols: $*" >> "$OUT/BUILD-NOTES"
done
printf '%s\n' "$UNAMEV" > "$OUT/uname-v"
strings "$OUT/binder.ko" | grep '^vermagic='
ls -la "$OUT"
