#!/bin/sh
# Static checks for the e-ink operation changes in VeraHome (feat/ux-eink). No device access.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
M=$REPO/android/packages/VeraHome/AndroidManifest.xml
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

# switcher = recents: per-app close + lock, close all (locked ones stay), free / total memory
need "$S/SwitcherActivity.java" 'getMethod\("removeTask", int\.class\)' 'close removes the task'
need "$S/SwitcherActivity.java" 'removeTask\(t\.persistentId\)' 'close all uses persistentId (restored tasks have id -1)'
need "$S/SwitcherActivity.java" 'Cleaner\.closeSync\(' 'close ends the process off the UI thread'
need "$S/SwitcherActivity.java" 'Cleaner\.keepAlive\(this, pkg\)\) continue;' 'close all skips locked apps'
need "$S/SwitcherActivity.java" '"全部关闭"' 'close-all button'
need "$S/SwitcherActivity.java" '可用内存 " \+ avail' 'memory line'
need "$S/SwitcherActivity.java" 'Icons\.Kind\.LOCK : Icons\.Kind\.UNLOCK' 'lock icon follows keep-alive'
need "$S/SwitcherActivity.java" 'Cleaner\.userApp\(this, pkg\)' 'system apps / VeraHome are never closable'
need "$S/Cleaner.java" 'static boolean closeSync\(Context c, String pkg\)' 'Cleaner.closeSync'
need "$S/Icons.java" 'CLEAN, LOCK, UNLOCK' 'lock icons'
need "$M" 'android.permission.REMOVE_TASKS' 'REMOVE_TASKS permission'
# reader: three-column tap zones in both styles
need "$S/ReaderActivity.java" 'TAP_L = \{ "左边上一页", "全屏下一页", "三栏" \}' 'tap-zone choices'
need "$S/ReaderActivity.java" 'if \(tapMode == 2\) \{ if \(lastX < w / 3f\) prev\(\); else if \(lastX > w \* 2 / 3f\) next\(\); else toggleChrome\(\); return; \}' 'three-column zones'
need "$S/ReaderActivity.java" 'tapRow\.addView' 'classic Aa panel has the tap-zone row'
# reader: jumps (TOC / % / bookmarks / page number) can be undone ("返回第 N 页")
need "$S/ReaderActivity.java" 'if \(page != from && !chain\) pushBack\(from\);' 'jump() records where it came from'
need "$S/ReaderActivity.java" '"‹ 返回第 "' 'back chip names the page'
need "$S/ReaderActivity.java" 'if \(isPdf\) showPdf\(page\); else showText\(\);\n?' 'goBack handles PDF'
need "$S/ReaderActivity.java" 'BACK_KEEP_TURNS' 'back chip retires after reading on'
# panel: 清残影 closes the panel first, then refreshes
for f in Panel.java BlocksPanel.java; do
  need "$S/$f" 'postDelayed\(new Runnable\(\) \{ @Override public void run\(\) \{ HostLink\.cmd\("clear"\); \} \}, 500\)' "$f: refresh after the panel is gone"
  forbid "$S/$f" 'else if \("clear"\.equals\(id\)\) HostLink\.cmd\("clear"\);' "$f: refresh while the panel is still up"
done
# per-app optimisation page: knob table, host-declared knobs, unknown keys kept, keep-alive
need "$S/AppDisplayActivity.java" 'HostLink\.KFB \+ "appknobs"' 'host knob file'
need "$S/AppDisplayActivity.java" 'static String merge\(String oldSpec' 'spec merge keeps unknown keys'
need "$S/AppDisplayActivity.java" '应用优化' 'page name'
need "$S/HomeActivity.java" 'items\.add\("应用优化"\)' 'long-press entry'
[ $fail = 0 ] && echo "home-ux-eink: ok"
exit $fail
