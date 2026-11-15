# Class "pw6": MediaTek MT8113, 2x Cortex-A53 (up to 2.0 GHz), 1 GB, 64-bit binder (Kindle 5.15 kernels).
# Models: PW6 (1272x1696), Colorsoft (1264x1680 colour, same SoC / RAM / kernel: the 32 bpp frame buffer is the display
# bridge's business, not the system image's). docs/per-model-images.md has the evidence for every figure.
include device/veradroid/kindle/slim.mk
include device/veradroid/kindle/class/ram-1g.mk
include device/veradroid/kindle/class/panel-300.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=pw6
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_pw6
PRODUCT_DEVICE := kindle
PRODUCT_MODEL := VeraDroid on Kindle (pw6)
