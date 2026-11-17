LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := VeraIME
LOCAL_CERTIFICATE := platform
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := $(call all-java-files-under, src)
LOCAL_ASSET_DIR := $(LOCAL_PATH)/assets
LOCAL_RESOURCE_DIR := $(LOCAL_PATH)/res
LOCAL_PROGUARD_ENABLED := disabled
# Precompiled in the system image (odex) and classes.dex kept in the APK (it is also shipped / installed on its own):
# without an odex the IME was compiled on the device at every first boot of a new image.
LOCAL_DEX_PREOPT := nostripping
# assets/pinyin.dat is mapped straight out of the APK (AssetManager.openFd): it must be stored, not deflated
LOCAL_AAPT_FLAGS := -0 .dat
include $(BUILD_PACKAGE)
