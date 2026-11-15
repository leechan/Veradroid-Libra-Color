# Class "k49-512": MediaTek MT8110, 2x Cortex-A53, 512 MB, 32-bit binder (4.9 kernels). Models: PW5 (1236x1648),
# KT5 / KT6 (1072x1448). All 300 ppi.
include device/veradroid/kindle/slim.mk
include device/veradroid/kindle/class/ram-512.mk
include device/veradroid/kindle/class/panel-300.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=k49-512
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_k49_512
PRODUCT_DEVICE := kindle_k49
PRODUCT_MODEL := VeraDroid on Kindle (k49-512)
