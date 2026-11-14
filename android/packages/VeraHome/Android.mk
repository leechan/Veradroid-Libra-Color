LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_PACKAGE_NAME := VeraHome
LOCAL_ASSET_DIR := $(LOCAL_PATH)/assets
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := $(call all-java-files-under, src)
LOCAL_CERTIFICATE := platform
LOCAL_PRIVILEGED_MODULE := true
# Settings (and its FallbackHome) and the backup confirmation UI are not wanted on a reader; boot goes straight to our home
LOCAL_OVERRIDES_PACKAGES := Settings BackupRestoreConfirmation
LOCAL_PROGUARD_ENABLED := disabled
include $(BUILD_PACKAGE)
