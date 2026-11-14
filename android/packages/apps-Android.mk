# packages/apps/Android.mk for the system image (tools/build/build_rootfs.sh copies this file over the AOSP tree's).
# Having an Android.mk here hides every stock app under packages/apps from the build; device/veradroid/kindle32/Android.mk
# pulls PackageInstaller back in. VeraHome's Java comes from packages/apps/VeraHome/src, its manifest from
# packages/apps/AndroidManifest.xml (both synced from android/packages/VeraHome).
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := VeraHome
LOCAL_ASSET_DIR := $(LOCAL_PATH)/VeraHome/assets
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := $(call all-java-files-under, VeraHome/src)
LOCAL_CERTIFICATE := platform
LOCAL_PRIVILEGED_MODULE := true
# Not wanted on a reader, never installed into the image (slim.sh used to move the last four out at every boot):
# Settings (and its FallbackHome), the adb backup confirmation UI, the two CTS shims, the wallpaper backup agent
# (there is no wallpaper service).
LOCAL_OVERRIDES_PACKAGES := Settings BackupRestoreConfirmation CtsShimPrebuilt CtsShimPrivPrebuilt WallpaperBackup
LOCAL_PROGUARD_ENABLED := disabled
# Precompiled in the image (odex next to the APK) AND classes.dex kept in the APK: the bundle ships this same file as
# apks/VeraHome.apk, the installer sees it is identical and keeps the odex -> no first-boot dexopt of the launcher.
LOCAL_DEX_PREOPT := nostripping
include $(BUILD_PACKAGE)

include $(LOCAL_PATH)/VeraIME/Android.mk

# HTMLViewer is in core_minimal's package list, but the Android.mk above hides it: the live images had it only as a
# leftover. Keep it (some apps open local .html through it); dropping it would also make PackageManager delete its data.
include $(TOPDIR)packages/apps/HTMLViewer/Android.mk
