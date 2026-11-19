#!/bin/sh
# 下拉面板能回到 VeraDroid 桌面：方块面板底部有“回到桌面”按钮，快捷方块可选“回桌面”（两种面板都认 home）
D=$(dirname "$0")/../android/packages/VeraHome/src/com/veradroid/home
fail=0
grep -q '"回到桌面"' $D/BlocksPanel.java || { echo "FAIL: BlocksPanel has no 回到桌面 button"; fail=1; }
grep -q 'private void goHome()' $D/BlocksPanel.java && grep -q 'HomeActivity.homeIntent(ctx)' $D/BlocksPanel.java || { echo "FAIL: goHome does not open HomeActivity.homeIntent"; fail=1; }
grep -q '"home".equals(id)) goHome()' $D/BlocksPanel.java || { echo "FAIL: home tile action missing in BlocksPanel"; fail=1; }
grep -q '"home".equals(id)) openHome(false)' $D/Panel.java || { echo "FAIL: home tile action missing in Panel"; fail=1; }
ids=$(grep -o 'QUICK_ID = {[^}]*}' $D/Panel.java | tr ',' '\n' | grep -c '"')
names=$(grep -o 'QUICK_NAME = {[^}]*}' $D/Panel.java | tr ',' '\n' | grep -c '"')
[ "$ids" = "$names" ] || { echo "FAIL: QUICK_ID ($ids) and QUICK_NAME ($names) differ"; fail=1; }
grep -q '"lightf", "home" }' $D/Panel.java || { echo "FAIL: home not in QUICK_ID"; fail=1; }
[ $fail = 0 ] && echo "panel-home-test: ok"
exit $fail
