/* host stand-in for the parts of <hardware/hardware.h> hwc_kindle.c uses (tests/hwc-test.sh); layouts need not match */
#pragma once
#include <stdint.h>
#define MAKE_TAG_CONSTANT(A, B, C, D) (((A) << 24) | ((B) << 16) | ((C) << 8) | (D))
#define HARDWARE_MODULE_TAG MAKE_TAG_CONSTANT('H', 'W', 'M', 'T')
#define HARDWARE_DEVICE_TAG MAKE_TAG_CONSTANT('H', 'W', 'D', 'T')
#define HARDWARE_HAL_API_VERSION 0x0100
typedef struct native_handle { int version, numFds, numInts; int data[0]; } native_handle_t;
typedef const native_handle_t *buffer_handle_t;
struct hw_module_t;
struct hw_device_t;
struct hw_module_methods_t { int (*open)(const struct hw_module_t *, const char *, struct hw_device_t **); };
typedef struct hw_module_t {
    uint32_t tag; uint16_t module_api_version, hal_api_version; const char *id, *name, *author;
    struct hw_module_methods_t *methods;
} hw_module_t;
typedef struct hw_device_t { uint32_t tag, version; struct hw_module_t *module; int (*close)(struct hw_device_t *); } hw_device_t;
