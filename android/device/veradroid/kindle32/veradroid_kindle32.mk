# VeraDroid for 512 MB / older Kindles: same packages as veradroid_kindle, 32-bit binder ABI (see BoardConfig.mk).
# Build in its own OUT_DIR (lunch veradroid_kindle32-userdebug).
#
# Java heap: keep the PW6 values (256m growth limit / 512m). A 128m limit makes WeChat Read and other large
# readers die with OutOfMemoryError at start; the old reason for 128m (the 256 MB heap mapping being refused on
# 512 MB kernels) is handled on the host with vm.overcommit_memory=1 (boot/lib/memory.sh).

$(call inherit-product, device/veradroid/kindle/veradroid_kindle.mk)

# core_minimal does not include PackageInstaller. Without it PackageManagerService dies at boot
# ("There must be exactly one installer; found []", PW3 emulator, first clean build of this product).
# The PW6 out/ directory only has it as a leftover of older builds: a clean PW6 build has the same problem.
PRODUCT_PACKAGES += PackageInstaller

PRODUCT_NAME := veradroid_kindle32
PRODUCT_DEVICE := kindle32
PRODUCT_MODEL := VeraDroid on Kindle (32-bit binder)
