/* host stand-in for Android's <cutils/log.h> (tests/hwc-test.sh) */
#pragma once
#include <stdio.h>
#define ALOGI(...) ((void)0)
#define ALOGW(...) (fprintf(stderr, __VA_ARGS__), fputc('\n', stderr))
