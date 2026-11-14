#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Build the binder driver as an out-of-tree module for a Kindle kernel without CONFIG_ANDROID.
# (docker vdaosp:7.1 + AOSP arm gcc 4.9). Nothing here touches a device.
#
#   sh build-binder.sh <kernel-tree> <device-config> <binder-src-dir> <device-kallsyms> <out-dir>
#
# kernel-tree     source of the same kernel version (vendor tree when the device uses MODVERSIONS)
# binder-src-dir  directory with binder.c (+ binder.h / binder_trace.h) for that kernel generation
# device-kallsyms /proc/kallsyms copied from the device (to see what the kernel exports)
#
# binder.c calls a few kernel functions that are not exported to modules. Instead of editing the
# driver, every such symbol gets an ARM trampoline inside the module (vd_tramp.c, generated): the
# module defines the symbol itself, the trampoline jumps through a pointer that module init fills
# with kallsyms_lookup_name(). r12 (ip) is the AAPCS scratch register, so arguments pass untouched.
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (src/ = AOSP android-7.1.1_r61 tree, out/, kmod/)}"
export LC_ALL=C
KDIR=$1; CFG=$2; BSRC=$3; KSYMS=$4; OUT=$5
W=${W:-$AOSP_WORK/kmod}
# docker resource limits (override with LIMITS=...)
LIMITS=${LIMITS:---cpus=4 --memory=6g}
# PREPARED=1: the kernel tree is already configured and built (e.g. a full reference build); skip olddefconfig
PREPARED=${PREPARED:-0}
TC=$AOSP_WORK/src/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
cd $W
rm -rf $OUT && mkdir -p $OUT/m
cp $BSRC/binder*.[ch] $OUT/m/
mv $OUT/m/binder.c $OUT/m/binder_main.c
# device node /dev/vndbinder (host scripts bind that one into Android; Kindle never uses it);
# module_init instead of device_initcall; resolve trampolines first.
sed -i 's|\.name = "binder",|.name = "vndbinder",|; s|^device_initcall(binder_init);|module_init(binder_init);|' $OUT/m/binder_main.c
sed -i '/^static int __init binder_init(void)/,/^{/{s|^{|{\n\tif (vd_tramp_resolve()) return -ENOENT;|}' $OUT/m/binder_main.c
sed -i '0,/^#include/s|^#include|int vd_tramp_resolve(void);\n#include|' $OUT/m/binder_main.c
# the android-3.0 driver carries backported SELinux binder hooks the Kindle 3.0 kernel does not have:
# no LSM policy is loaded on a Kindle anyway, so they are always "allowed".
if ! grep -rq 'security_binder_transaction' $KDIR/include/linux/security.h; then
    sed -i '0,/^#include "binder.h"/s|^#include "binder.h"|#include "binder.h"\nstatic inline int security_binder_set_context_mgr(struct task_struct *m) { return 0; }\nstatic inline int security_binder_transaction(struct task_struct *f, struct task_struct *t) { return 0; }\nstatic inline int security_binder_transfer_binder(struct task_struct *f, struct task_struct *t) { return 0; }\nstatic inline int security_binder_transfer_file(struct task_struct *f, struct task_struct *t, struct file *x) { return 0; }|' $OUT/m/binder_main.c
fi
# single-value user access through copy_{to,from}_user (vendor kernels changed the __put_user_N ABI)
cp "$(dirname "$0")/vd_uaccess.h" $OUT/m/
if grep -q '^#include "binder.h"' $OUT/m/binder_main.c; then
    sed -i '0,/^#include "binder.h"/s|^#include "binder.h"|#include "binder.h"\n#include "vd_uaccess.h"|' $OUT/m/binder_main.c
else    # 3.19+ driver (drivers/android): uapi header, include it before the trace header
    sed -i '0,/^#include "binder_trace.h"/s|^#include "binder_trace.h"|#include "vd_uaccess.h"\n#include "binder_trace.h"|' $OUT/m/binder_main.c
fi
# the driver has no exit function, so the module would be permanent; allow unloading when nothing has it open
if ! grep -q 'module_exit' $OUT/m/binder_main.c; then
    printf '%s\n' '' 'static void __exit vd_binder_exit(void)' '{' \
        '	misc_deregister(&binder_miscdev);' \
        '	debugfs_remove_recursive(binder_debugfs_dir_entry_root);' \
        '	destroy_workqueue(binder_deferred_workqueue);' \
        '}' 'module_exit(vd_binder_exit);' >> $OUT/m/binder_main.c
fi
# The driver remembers the uid of the first context manager forever. If anything else (a test, a crashed
# earlier run as root) registers first, Android's servicemanager (uid 1000) is refused for the rest of the
# uptime ("BINDER_SET_CONTEXT_MGR bad uid 1000 != 0", PW3 emulator) and init "reboots" after 4 crashes.
# Forget the uid when the context manager goes away.
if grep -q '^static uid_t binder_context_mgr_uid = -1;' $OUT/m/binder_main.c; then
    sed -i 's|^\(\t*\)binder_context_mgr_node = NULL;$|\1binder_context_mgr_node = NULL;\n\1binder_context_mgr_uid = -1;   /* VeraDroid */|' $OUT/m/binder_main.c
    grep -q 'binder_context_mgr_uid = -1;   /\* VeraDroid \*/' $OUT/m/binder_main.c || { echo "context manager uid reset not applied"; exit 1; }
elif grep -q '^static kuid_t binder_context_mgr_uid = INVALID_UID;' $OUT/m/binder_main.c; then   # 3.5+ (kuid_t)
    sed -i 's|^\(\t*\)binder_context_mgr_node = NULL;$|\1binder_context_mgr_node = NULL;\n\1binder_context_mgr_uid = INVALID_UID;   /* VeraDroid */|' $OUT/m/binder_main.c
    grep -q 'binder_context_mgr_uid = INVALID_UID;   /\* VeraDroid \*/' $OUT/m/binder_main.c || { echo "context manager uid reset not applied"; exit 1; }
fi
grep -q 'module_init(binder_init)' $OUT/m/binder_main.c || { echo "binder_init not found"; exit 1; }
grep -q '#include "vd_uaccess.h"' $OUT/m/binder_main.c || { echo "vd_uaccess.h not included"; exit 1; }
grep -q 'MODULE_LICENSE' $OUT/m/binder_main.c || echo 'MODULE_LICENSE("GPL v2");' >> $OUT/m/binder_main.c

gen_tramp() { # $1 = file with symbol names
    # printf only: dash's echo would turn the C "\n" escapes into real newlines
    {
        printf '%s\n' '#include <linux/module.h>' '#include <linux/kallsyms.h>'
        while read -r s; do
            printf 'void *vd_p_%s;\n' "$s"
            printf 'asm(".text\\n.align 2\\n.global %s\\n.type %s,%%function\\n%s:\\n\\tldr ip, =vd_p_%s\\n\\tldr ip, [ip]\\n\\tbx ip\\n.ltorg\\n");\n' "$s" "$s" "$s" "$s"
        done < $1
        printf '%s\n' 'int vd_tramp_resolve(void) {'
        while read -r s; do
            printf '  vd_p_%s = (void *)kallsyms_lookup_name("%s");\n' "$s" "$s"
            printf '  if (!vd_p_%s) { pr_err("binder: kernel symbol %s not found\\n"); return -1; }\n' "$s" "$s"
        done < $1
        printf '%s\n' '  return 0; }'
    } > $OUT/m/vd_tramp.c
}
: > $OUT/tramp.txt
gen_tramp $OUT/tramp.txt
cat > $OUT/m/Makefile <<'EOF'
obj-m := binder.o
binder-y := binder_main.o vd_tramp.o
# the AOSP androideabi gcc defaults to PIC; kernel modules must not use a GOT
ccflags-y := -I$(src) -DCONFIG_ANDROID_BINDER_IPC_32BIT=1 -Wno-declaration-after-statement -fno-pic
CFLAGS_binder_main.o := -DTRACE_INCLUDE_PATH=$(src)
EOF

kbuild() {
    docker run --rm $LIMITS -v "$AOSP_WORK":"$AOSP_WORK" -w $W/$KDIR vdaosp:7.1 sh -c "
        set -e
        export ARCH=arm CROSS_COMPILE=$TC
        $1
        chmod -R a+rwX $W/$OUT"
}
# kernel tree: device config, same LOCALVERSION, prepared for external modules
[ "$PREPARED" = 1 ] || kbuild "cp $W/$CFG .config && sed -i 's/^CONFIG_LOCALVERSION=.*/CONFIG_LOCALVERSION=\"-lab126\"/' .config && \
        (nice -n 12 make olddefconfig || yes '' | nice -n 12 make oldconfig) >/dev/null 2>&1 && \
        nice -n 12 make -j4 modules_prepare >/dev/null 2>&1 && echo prepared"
# pass 1: which undefined symbols does the driver use that the device kernel does not export?
kbuild "nice -n 12 make -j4 M=$W/$OUT/m KBUILD_MODPOST_WARN=1 modules >/dev/null 2>&1 || true"
${TC}nm -u $OUT/m/binder_main.o | awk '{print $2}' | sort -u > $OUT/undef.txt
grep -E ' __ksymtab_' $KSYMS | sed 's/.* __ksymtab_//' | sort -u > $OUT/exported.txt
LC_ALL=C comm -23 $OUT/undef.txt $OUT/exported.txt | grep -v '^__aeabi_\|^__gnu_mcount_nc$\|^__stack_chk\|^__this_module$\|^vd_\|^_GLOBAL_OFFSET_TABLE_$' > $OUT/tramp.txt || true
echo "trampolines: $(tr '\n' ' ' < $OUT/tramp.txt)"
for s in $(cat $OUT/tramp.txt); do
    grep -q " $s\$" $KSYMS || { echo "symbol $s is not in the device kernel at all"; exit 1; }
done
grep -q ' __ksymtab_kallsyms_lookup_name$' $KSYMS || { echo "kallsyms_lookup_name is not exported"; exit 1; }
gen_tramp $OUT/tramp.txt
# pass 2: real build
kbuild "nice -n 12 make -j4 M=$W/$OUT/m KBUILD_MODPOST_WARN=1 modules 2>&1 | grep -E 'error|WARNING' | grep -v 'undefined!' || true"
cp $OUT/m/binder.ko $OUT/
${TC}nm -u $OUT/binder.ko | awk '{print $2}' | sort -u > $OUT/final-undef.txt
LC_ALL=C comm -23 $OUT/final-undef.txt $OUT/exported.txt > $OUT/still-missing.txt || true
if [ -s $OUT/still-missing.txt ]; then echo "still not exported: $(tr '\n' ' ' < $OUT/still-missing.txt)"; exit 1; fi
strings $OUT/binder.ko | grep '^vermagic='
ls -la $OUT/binder.ko
