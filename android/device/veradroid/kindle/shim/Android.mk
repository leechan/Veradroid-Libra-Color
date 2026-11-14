LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libvdshim
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := vdshim.c
LOCAL_CFLAGS := -Wall -Werror -O2
include $(BUILD_SHARED_LIBRARY)
