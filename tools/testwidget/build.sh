#!/bin/sh
# 编出测试小部件 APK（只用于模拟器验证 AppWidgetHost）：sh tools/testwidget/build.sh -> /tmp/testwidget/TestWidget.apk
set -eu
: "${AOSP_WORK:?set AOSP_WORK to the build work directory (src/ = AOSP android-7.1.1_r61 tree, out/, kmod/)}"
A=$AOSP_WORK; H=$A/out/host/linux-x86; J=$A/out/target/common/obj/JAVA_LIBRARIES
D=$(cd "$(dirname "$0")" && pwd); T=/tmp/testwidget; rm -rf $T; mkdir -p $T/gen $T/cls
FW=$A/out/target/common/obj/APPS/framework-res_intermediates/package-export.apk
[ -f $FW ] || FW=$A/out/target/product/kindle/system/framework/framework-res.apk
LD_LIBRARY_PATH=$H/lib64 $H/bin/aapt package -f -M $D/AndroidManifest.xml -S $D/res -I $FW -J $T/gen -F $T/res.apk
cp -r $D/src $T/src; chmod -R 777 $T
# javac 1.7 字节码 + dx 1.12 在 AOSP 的编译容器里做（较新的 JDK 不能出 1.7 字节码，dx 1.12 又不认 1.8）
docker run --rm --cpus=1 --memory=1g -v $A:/aosp -v $T:/work -w /work vdaosp:7.1 bash -lc \
  "javac -nowarn -source 1.7 -target 1.7 -bootclasspath /aosp/out/target/common/obj/JAVA_LIBRARIES/core-oj_intermediates/classes.jar:/aosp/out/target/common/obj/JAVA_LIBRARIES/framework_intermediates/classes.jar -d cls \$(find src gen -name '*.java') && /aosp/out/host/linux-x86/bin/dx --dex --output=classes.dex cls"
cp $T/res.apk $T/unsigned.apk; (cd $T && zip -q unsigned.apk classes.dex)
chmod -R 777 $T
docker run --rm --cpus=1 --memory=1g -v $A:/aosp -v $T:/work -w /aosp vdaosp:7.1 bash -lc \
  "java -Djava.library.path=/aosp/out/host/linux-x86/lib64 -jar out/host/linux-x86/framework/signapk.jar src/build/target/product/security/testkey.x509.pem src/build/target/product/security/testkey.pk8 /work/unsigned.apk /work/TestWidget.apk"
ls -l $T/TestWidget.apk
