# VeraDroid: null GLES2 dispatch table for ES2-only libagl configs (Chromium WebView's GPU thread). See nullgles2.cpp.
LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := libGLESv2_vdnull
LOCAL_MODULE_TAGS := optional
LOCAL_SRC_FILES := nullgles2.cpp
LOCAL_C_INCLUDES := frameworks/native/opengl/libs
LOCAL_CFLAGS := -Wall -Werror -O2 -fvisibility=hidden
include $(BUILD_SHARED_LIBRARY)
