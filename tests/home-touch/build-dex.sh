#!/bin/sh
# Build the on-device touch-dispatch test (TouchNpeTest + the VeraHome sources it tests) into one dex.
#   sh tests/home-touch/build-dex.sh [out.dex]          (default /tmp/vd-touchnpe/touchnpe.dex)
# The dex holds only the test; it runs against the VeraHome APK under test (no install, the running Home is not touched),
# inside the Android container as root:
#   CLASSPATH=/data/local/tmp/touchnpe.dex:/data/local/tmp/VeraHome-under-test.apk app_process /system/bin com.veradroid.home.TouchNpeTest
# Prints PASS/FAIL per case and "touch-npe: N passed, M failed"; exit status = failures.
set -eu
A=$AOSP_WORK
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-/tmp/vd-touchnpe/touchnpe.dex}
T=$(mktemp -d /tmp/vd-touchnpe-build.XXXXXX)
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/src" "$T/cls" "$(dirname "$OUT")"
cp -a "$REPO/android/packages/VeraHome/src/." "$T/src/"
cp "$REPO/tests/home-touch/TouchNpeTest.java" "$T/src/com/veradroid/home/"
chmod -R a+rwX "$T"
J=out/target/common/obj/JAVA_LIBRARIES
docker run --rm --cpus=2 --memory=2g -v $A:/aosp -v "$T":/work -w /aosp vdaosp:7.1 bash -lc "
  set -e
  BCP=$J/core-oj_intermediates/classes.jar:$J/core-libart_intermediates/classes.jar:$J/framework_intermediates/classes.jar
  # compile against TouchGuard (real source) and a stub of Ui.fast; neither goes into the dex -- at run time they come
  # from the VeraHome APK under test
  mkdir -p /work/stub/com/veradroid/home /work/home /work/t
  printf 'package com.veradroid.home;\\nclass Ui { static void fast(android.view.View v) { } }\\n' > /work/stub/com/veradroid/home/Ui.java
  javac -nowarn -source 1.7 -target 1.7 -encoding UTF-8 -bootclasspath \$BCP -d /work/home /work/stub/com/veradroid/home/Ui.java /work/src/com/veradroid/home/TouchGuard.java
  javac -nowarn -source 1.7 -target 1.7 -encoding UTF-8 -bootclasspath \$BCP -classpath /work/home -d /work/t /work/src/com/veradroid/home/TouchNpeTest.java
  java -jar out/host/linux-x86/framework/dx.jar --dex --output=/work/touchnpe.dex /work/t"
cp "$T/touchnpe.dex" "$OUT"
ls -l "$OUT"
