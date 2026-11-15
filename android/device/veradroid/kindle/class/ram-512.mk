# VeraDroid memory class "512" (MemTotal 400-700 MB: PW5, KT5, KT6, PW3, Voyage, Oasis 1, PW4, KT4, Oasis 2 / 3).
# Include BEFORE inheriting veradroid_base.mk. Until now these were written into build.prop at every start by the host:
#   heap / low_ram / max_starting_bg / bg_apps_limit: boot/lib/memory.sh heap_fix (MemTotal < 700 MB)
#   ro.logd.size, dex2oat threads: models/ram-512.conf (lib/props.sh)
# The host keeps doing it (same values = no-op), so per-model overrides (HEAP_START, MAX_STARTING_BG ...) still work.
# Tried and dropped: an empty preloaded_drawables list (overlay) - system_server's AssetAtlasService crashes on an empty
# preload list (IndexOutOfBoundsException in computeBestConfiguration), boot loops (pw5 emulator). docs/per-model-images.md.
PRODUCT_PROPERTY_OVERRIDES += \
    dalvik.vm.heapstartsize=8m \
    dalvik.vm.heapgrowthlimit=128m \
    dalvik.vm.heapsize=192m \
    dalvik.vm.heaptargetutilization=0.75 \
    dalvik.vm.heapminfree=512k \
    dalvik.vm.heapmaxfree=2m \
    ro.config.low_ram=true \
    ro.config.max_starting_bg=2 \
    ro.sys.fw.bg_apps_limit=2 \
    ro.logd.size=64K \
    dalvik.vm.dex2oat-threads=1 \
    dalvik.vm.image-dex2oat-threads=1 \
    ro.vd.ram=512
