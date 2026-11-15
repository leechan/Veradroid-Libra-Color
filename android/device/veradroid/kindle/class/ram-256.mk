# VeraDroid memory class "256" (MemTotal < 400 MB: PW2). Include BEFORE inheriting veradroid_base.mk.
# Values = what the legacy host set at every start for PW2 (memory.sh heap_values < 400 MB: 96m / 160m,
# models/pw2.conf HEAP_START=4m, MAX_STARTING_BG=1, LCD_DENSITY=213, strictmode off) plus the 512 class items.
# (No empty preloaded_drawables: AssetAtlasService boot-loops on it, see ram-512.mk.)
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=4m \
    dalvik.vm.heapgrowthlimit=96m \
    dalvik.vm.heapsize=160m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=2m \
    ro.config.low_ram=true \
    ro.config.max_starting_bg=1 \
    ro.sys.fw.bg_apps_limit=2 \
    ro.logd.size=64K \
    dalvik.vm.dex2oat-threads=1 \
    dalvik.vm.image-dex2oat-threads=1 \
    ro.vd.ram=256
