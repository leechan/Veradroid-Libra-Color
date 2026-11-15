# Class "a9-256": NXP i.MX6SL, 1x Cortex-A9, 256 MB, 32-bit binder (legacy host, 3.0.35). Model: PW2 (758x1024 212 ppi).
include device/veradroid/kindle/slim.mk
include device/veradroid/kindle/class/ram-256.mk
include device/veradroid/kindle/class/panel-212.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=a9-256
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_a9_256
PRODUCT_DEVICE := kindle32
PRODUCT_MODEL := VeraDroid on Kindle (a9-256)
