# VeraDroid Kindle product (the "family" image of releases up to PW6 0.90 / k49 0.98): the base product plus the
# 1 GB heap defaults. The per-class products (veradroid_pw6, veradroid_k49_*, veradroid_a9_*, veradroid_a7_512) inherit
# veradroid_base.mk directly and take their properties from class/*.mk instead.
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)

PRODUCT_NAME := veradroid_kindle
PRODUCT_DEVICE := kindle
PRODUCT_MODEL := VeraDroid on Kindle

PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=256m \
    dalvik.vm.heapsize=512m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m \
    ro.sf.lcd_density=300 \
    ro.config.low_ram=true
