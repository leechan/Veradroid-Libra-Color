#!/bin/sh
# VeraHome：软件商店的两栏（官方推荐 / 用户上传）和字体商店——只看源码里几处不能丢的约定。
cd "$(dirname "$0")/.." || exit 2
H=android/packages/VeraHome; J=$H/src/com/veradroid/home; fail=0
has() { grep -qF -- "$2" "$1" || { echo "missing in $1: $2"; fail=1; }; }
has $H/AndroidManifest.xml 'android:name=".FontStoreActivity"'
has $J/StoreNet.java 'debug.vd.storebase'
has $J/StoreNet.java '"https://veradroid.wenjin.jp"'
has $J/StoreActivity.java '/api/store/apps?category='
has $J/StoreActivity.java '" · 用户上传 · " + a.uploader + " · 已审核"'
has $J/StoreActivity.java 'Blocks.paged(this, list)'
has $J/StoreActivity.java 'FontStoreActivity.open('
has $J/FontStoreActivity.java '/api/fonts?page='
has $J/FontStoreActivity.java 'Blocks.paged(this, list)'
has $J/FontStoreActivity.java 'StoreNet.sha256(part).equalsIgnoreCase(it.sha)'
has $J/HomeActivity.java 'FontStoreActivity.open(HomeActivity.this)'
# 下载的字体放进现有字体功能读的那个目录（Books.fonts、Transfer、宿主 sysfont_host 的 $VD/fonts）
has $J/FontStoreActivity.java 'static final String DIR = "/data/media/0/Fonts";'
has $J/Books.java '"/data/media/0/Fonts"'
has host/pw6/boot/lib/container.sh '/data/media/0/Fonts|/sdcard/Fonts|/storage/emulated/0/Fonts) echo "$VD/fonts/$sf_n"'
# 文件名会进宿主的 SYSTEM_FONT：只收字母数字 . _ -
has $J/FontStoreActivity.java 'it.file.matches("[A-Za-z0-9._-]{1,80}")'
# 商店页不许有跟手滚动的 ScrollView
grep -n 'new ScrollView' $J/StoreActivity.java $J/FontStoreActivity.java && { echo "plain ScrollView in a store page"; fail=1; }
exit $fail
