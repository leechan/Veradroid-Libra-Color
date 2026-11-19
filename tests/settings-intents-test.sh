#!/bin/sh
# Static check: apps that open the system Wi-Fi settings (no Settings app in VeraDroid) land on VeraHome's Wi-Fi page
# instead of crashing with ActivityNotFoundException (user diagnostics 2026-11-17: 多看 com.duokan.reader bookshelf,
# act=android.settings.WIFI_SETTINGS). No device access. On a device: cmd package query-activities -a android.settings.WIFI_SETTINGS
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
M=$REPO/android/packages/VeraHome/AndroidManifest.xml
fail=0
# the <activity> element of WifiActivity, up to its closing tag
blk=$(awk '/android:name="\.WifiActivity"/{f=1} f{print} f&&/<\/activity>/{exit}' "$M")
[ -n "$blk" ] || { echo "FAIL: WifiActivity not in the manifest"; exit 1; }
printf '%s\n' "$blk" | grep -q 'android:exported="true"' || { echo "FAIL: WifiActivity not exported"; fail=1; }
printf '%s\n' "$blk" | grep -q 'android.intent.category.DEFAULT' || { echo "FAIL: no DEFAULT category (startActivity needs it)"; fail=1; }
for a in android.settings.WIFI_SETTINGS android.settings.WIFI_IP_SETTINGS android.settings.WIRELESS_SETTINGS android.net.wifi.PICK_WIFI_NETWORK; do
    printf '%s\n' "$blk" | grep -q "<action android:name=\"$a\"" || { echo "FAIL: WifiActivity does not handle $a"; fail=1; }
done
# only one activity may claim them (two would pop a chooser)
n=$(grep -c '<action android:name="android.settings.WIFI_SETTINGS"' "$M")
[ "$n" = 1 ] || { echo "FAIL: android.settings.WIFI_SETTINGS claimed $n times"; fail=1; }
# well-formed XML
python3 -c 'import sys,xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$M" || { echo "FAIL: manifest is not well-formed"; fail=1; }
[ $fail = 0 ] && echo "settings-intents-test: OK"
exit $fail
