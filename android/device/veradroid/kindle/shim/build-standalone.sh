# Builds libvdshim.so outside the AOSP tree with the tree's own toolchain and bionic, for host/*/bin:
# the host installs it over the image's /system/lib/libvdshim.so before Android starts (container.sh vdshim_prepare).
# Usage (AOSP build host): sh build-standalone.sh <dir with vdshim.c>  -> <dir>/libvdshim.so
set -e
A=$AOSP_WORK/src; O=$AOSP_WORK/out/target/product/kindle/obj/lib
T=$A/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin/arm-linux-androideabi-
cd "${1:-.}"
${T}gcc -O2 -std=gnu99 -fPIC -march=armv7-a -mfloat-abi=softfp -mfpu=vfpv3-d16 -mthumb -fno-strict-aliasing -Wall -Werror \
  -DANDROID -D__ANDROID__ -nostdinc -isystem $A/bionic/libc/arch-arm/include -isystem $A/bionic/libc/include \
  -isystem $A/bionic/libc/kernel/uapi -isystem $A/bionic/libc/kernel/uapi/asm-arm -isystem $A/bionic/libc/kernel/android/uapi \
  -isystem $(${T}gcc -print-file-name=include) -c vdshim.c -o vdshim.o
${T}gcc -nostdlib -shared -Wl,-soname,libvdshim.so -Wl,--no-undefined -Wl,-z,noexecstack -Wl,-z,relro -Wl,-z,now -Wl,--hash-style=both \
  $O/crtbegin_so.o vdshim.o -L$O -lc -ldl $(${T}gcc -mthumb -march=armv7-a -print-libgcc-file-name) $O/crtend_so.o -o libvdshim.so
${T}strip --strip-unneeded libvdshim.so
ls -la libvdshim.so; ${T}readelf -d libvdshim.so | grep -E "NEEDED|SONAME"
