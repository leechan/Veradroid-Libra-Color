# VeraDroid base product: core_minimal plus what is needed to run apps, WITHOUT the memory / panel class properties.
# Inherited by veradroid_kindle.mk (the old family product) and by the per-class products (class/*.mk, docs/per-model-images.md).
$(call inherit-product, build/target/product/core_minimal.mk)
$(call inherit-product-if-exists, frameworks/base/data/fonts/fonts.mk)
$(call inherit-product-if-exists, external/roboto-fonts/fonts.mk)
$(call inherit-product-if-exists, frameworks/base/data/keyboards/keyboards.mk)

PRODUCT_PACKAGE_OVERLAYS := device/veradroid/kindle/overlay

PRODUCT_BRAND := VeraDroid
PRODUCT_MANUFACTURER := VeraDroid
PRODUCT_LOCALES := zh_CN en_US
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xhdpi
PRODUCT_CHARACTERISTICS := nosdcard

PRODUCT_PACKAGES += \
    libGLES_android \
    gralloc.default \
    InputDevices \
    DefaultContainerService \
    libvdshim \
    libGLESv2_vdnull \
    ca-certificates \
    libRS libRSDriver libRSCpuRef libRS_internal librs_jni libRScpp libclcore.bc libclcore_neon.bc libclcore_debug.bc libclcore_g.bc libbcc libbcinfo libLLVM_android libcompiler_rt \
    VeraHome \
    VeraIME \
    PackageInstaller
# PackageInstaller: core_minimal does not have it and PackageManagerService does not boot without an installer
# ("There must be exactly one installer"). The live images only had it as a leftover in the shared out/ dir;
# tools/build/build_rootfs.sh empties the installed system/ before each build, so it has to be listed. The module comes from
# device/veradroid/kindle32/Android.mk (packages/apps/Android.mk hides the stock apps from the build).

# no Settings app / backup UI on a reader: they only add icons to the desktop
PRODUCT_PACKAGES := $(filter-out Settings BackupRestoreConfirmation,$(PRODUCT_PACKAGES))

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.ethernet.xml:system/etc/permissions/android.hardware.ethernet.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.xml:system/etc/permissions/android.hardware.touchscreen.multitouch.xml \
    frameworks/native/data/etc/handheld_core_hardware.xml:system/etc/permissions/handheld_core_hardware.xml \
    device/veradroid/kindle/init.kindle.rc:root/init.kindle.rc

# class-independent properties (the class files add heap / low_ram / density / logd / dex2oat threads)
PRODUCT_PROPERTY_OVERRIDES += \
    ro.zygote=zygote32 \
    persist.sys.usb.config=none \
    debug.hwui.renderer=skia \
    ro.kernel.qemu=0 \
    ro.vd.oec=1

# adbd only accepts computers whose key is in adb_keys (userdebug builds leave ro.adb.secure unset = any computer is
# 'device'). Read-only, so it goes into default.prop, which adbd reads before anything can change it.
PRODUCT_DEFAULT_PROPERTY_OVERRIDES += \
    ro.adb.secure=1
