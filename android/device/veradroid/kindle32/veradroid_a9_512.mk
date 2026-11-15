# Class "a9-512": NXP i.MX6SL / 6SLL, 1x Cortex-A9 (no hardware divide, no LPAE), 512 MB, 32-bit binder (legacy host,
# 3.0.35 / 4.1.15 kernels with our binder module). Models: PW3, Voyage, Oasis 1 (3.0), PW4, KT4 (4.1). 300 ppi except
# KT4 (167 ppi: host models/kt4.conf).
include device/veradroid/kindle/slim.mk
include device/veradroid/kindle/class/ram-512.mk
include device/veradroid/kindle/class/panel-300.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=a9-512
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_a9_512
PRODUCT_DEVICE := kindle32
PRODUCT_MODEL := VeraDroid on Kindle (a9-512)
