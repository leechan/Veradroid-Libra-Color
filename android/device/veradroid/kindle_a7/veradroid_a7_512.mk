# Class "a7-512": i.MX7D 2x Cortex-A7, 512 MB, 32-bit binder (legacy host, 4.1.15 kernels). Models: Oasis 2, Oasis 3
# (1264x1680, 300 ppi).
include device/veradroid/kindle/slim.mk
include device/veradroid/kindle/class/ram-512.mk
include device/veradroid/kindle/class/panel-300.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=a7-512
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_a7_512
PRODUCT_DEVICE := kindle_a7
PRODUCT_MODEL := VeraDroid on Kindle (a7-512)
