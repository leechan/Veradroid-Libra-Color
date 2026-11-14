# VeraDroid "kindle32": the same system as device/veradroid/kindle, but with the old 32-bit binder ABI
# (binder protocol 7). For Kindle kernels whose binder is built with CONFIG_ANDROID_BINDER_IPC_32BIT
# (PW5 / KT5 / KT6, 4.9.77) and for our own out-of-tree binder modules (PW4 / Oasis 3 on 4.1.15,
# PW2 / PW3 and friends on 3.0.35). Everything else comes from the PW6 board config.
include device/veradroid/kindle/BoardConfig.mk

TARGET_USES_64_BIT_BINDER := false

# The oldest supported cores are Cortex-A9 (PW2 / PW3 / PW4 on i.MX6SL / 6SLL): no hardware integer divide,
# no ARMv8 AArch32 instructions. cortex-a53 code dies there with SIGILL (seen on the PW3 emulator).
# A9 code runs unchanged on the A7 (Oasis 3) and A53 (PW5 / KT5 / KT6). Also sets dalvik.vm.isa.arm.variant
# so ART compiles apps for the same baseline.
TARGET_CPU_VARIANT := cortex-a9
