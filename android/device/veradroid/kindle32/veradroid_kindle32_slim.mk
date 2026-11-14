# VeraDroid slim variant of the 32-bit-binder system (PW5 / KT5 / KT6 and the legacy models: the 512 MB devices).
# Same device (kindle32), so it must be built in its own OUT_DIR (lunch veradroid_kindle32_slim-userdebug).
include device/veradroid/kindle/slim.mk
$(call inherit-product, device/veradroid/kindle32/veradroid_kindle32.mk)
PRODUCT_NAME := veradroid_kindle32_slim
PRODUCT_MODEL := VeraDroid on Kindle (32-bit binder)
