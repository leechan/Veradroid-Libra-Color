# VeraDroid slim variant of the PW6 system (64-bit binder). Same device (kindle), so it must be built in its own OUT_DIR.
include device/veradroid/kindle/slim.mk
$(call inherit-product, device/veradroid/kindle/veradroid_kindle.mk)
PRODUCT_NAME := veradroid_kindle_slim
PRODUCT_MODEL := VeraDroid on Kindle
