# VeraDroid "kindle_a7": NXP i.MX7D, 2x Cortex-A7 (Oasis 2 / Oasis 3, 4.1.15 kernels with our binder module: 32-bit
# binder ABI). The A7 has hardware integer divide and LPAE (the A9 of kindle32 has neither), so the native code is built
# with -mcpu=cortex-a7 and dex2oat compiles the boot image, framework and system apps with --instruction-set-variant=
# cortex-a7 (features div, atomic ldrd/strd). In this AOSP (7.1.1) both are the same as for cortex-a53 on arm32
# (build/core/combo/arch/arm/armv7-a-neon.mk, art/runtime/arch/arm/instruction_set_features_arm.cc).
include device/veradroid/kindle/BoardConfig.mk
TARGET_USES_64_BIT_BINDER := false
TARGET_CPU_VARIANT := cortex-a7
