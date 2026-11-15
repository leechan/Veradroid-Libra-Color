# VeraDroid "kindle_k49": Cortex-A53 with the 32-bit binder ABI (binder protocol 7) of the Kindle 4.9.77 kernels
# (PW5 / KT5 / KT6 / Scribe 1 / 2). Until now this was the PW6 board with TARGET_USES_64_BIT_BINDER sed'ed to false by
# tools/build/build_rootfs.sh; a device of its own gives the k49 products their own out/target/product dir.
include device/veradroid/kindle/BoardConfig.mk
TARGET_USES_64_BIT_BINDER := false
