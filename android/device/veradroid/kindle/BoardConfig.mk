# VeraDroid on Kindle (MediaTek MT8113 "Bellatrix", 32-bit ARMv7 userspace on a 32-bit Linux 5.15 kernel)
# We never build a kernel or bootloader: the Android system runs in a container on the Kindle's own kernel.
TARGET_NO_BOOTLOADER := true
TARGET_NO_KERNEL := true
TARGET_NO_RECOVERY := true

TARGET_ARCH := arm
TARGET_ARCH_VARIANT := armv7-a-neon
TARGET_CPU_VARIANT := cortex-a53
TARGET_CPU_ABI := armeabi-v7a
TARGET_CPU_ABI2 := armeabi

# The Kindle kernel has CONFIG_ANDROID_BINDER_IPC without CONFIG_ANDROID_BINDER_IPC_32BIT: binder protocol v8 (64-bit structs)
TARGET_USES_64_BIT_BINDER := true

# No GPU: SurfaceFlinger composes with the software EGL (libagl), apps render with the CPU
USE_OPENGL_RENDERER := true
BOARD_USES_GENERIC_AUDIO := true
USE_CAMERA_STUB := true

SMALLER_FONT_FOOTPRINT := true
MINIMAL_FONT_FOOTPRINT := true

TARGET_USERIMAGES_USE_EXT4 := true
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 805306368
BOARD_USERDATAIMAGE_PARTITION_SIZE := 268435456
BOARD_FLASH_BLOCK_SIZE := 512
TARGET_USERIMAGES_SPARSE_EXT_DISABLED := true
