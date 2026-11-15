# Class "k49-1g": MediaTek MT8113, 2x Cortex-A53, 1 GB, 32-bit binder (4.9 kernels). Models: Scribe 1 (1860x2480),
# Scribe 2 (1872x2480 / 1860). 300 ppi.
include device/veradroid/kindle/slim.mk
# class/ram-1g.mk except heapstartsize 4m (not 8m): the 4.9 / 1 GB devices always ran with 4m (family k49 image; memory.sh
# only raises growth / max on >= 700 MB). With 8m the A/B on kt6-5202-win (970 MB) gave MemAvailable 686 / 666 MB against
# 716 / 696 MB for the family image. Written out here (no duplicate keys in build.prop).
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=4m \
    dalvik.vm.heapgrowthlimit=256m \
    dalvik.vm.heapsize=512m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=8m \
    ro.config.low_ram=true \
    ro.vd.ram=1g
include device/veradroid/kindle/class/panel-300.mk
PRODUCT_PROPERTY_OVERRIDES += ro.vd.class=k49-1g
$(call inherit-product, device/veradroid/kindle/veradroid_base.mk)
PRODUCT_NAME := veradroid_k49_1g
PRODUCT_DEVICE := kindle_k49
PRODUCT_MODEL := VeraDroid on Kindle (k49-1g)
