#!/bin/sh
# Static checks for the VeraHome touch-dispatch crash fix (fix/home-touch-npe). No device access.
# KT5 1.06 diagnostic: NPE in ViewGroup.resetCancelNextUpFlag from HomeActivity.dispatchTouchEvent -- a tap's click rebuilt
# the page synchronously inside touch dispatch while a stuck second contact held another TouchTarget in the same ViewGroup.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
S=$REPO/android/packages/VeraHome/src/com/veradroid/home
fail=0
need()   { grep -qE "$2" "$1" || { echo "FAIL $(basename "$1"): $3"; fail=1; }; }
forbid() { grep -qE "$2" "$1" && { echo "FAIL $(basename "$1"): $3"; fail=1; } || true; }

# 1. no view-tree mutation from inside touch dispatch: fast clicks and swipe page turns are posted
need   "$S/Ui.java" 'static void clickAfterDispatch\(final View v\)' 'posted click helper'
need   "$S/Ui.java" 'v\.post\(new Runnable\(\) \{ @Override public void run\(\) \{ if \(v\.isAttachedToWindow\(\)\) v\.performClick\(\);' 'click runs after dispatch, only on an attached view'
for f in "$S"/*.java; do
    forbid "$f" 'armed = false; view\.performClick\(\)' 'onTouch listener clicks synchronously inside dispatch'
done
need   "$S/Blocks.java" 'armed = false; Ui\.clickAfterDispatch\(view\)' 'Blocks.fast posts its click'
need   "$S/Ui.java" 'armed = false; clickAfterDispatch\(view\)' 'Ui.fast posts its click'
need   "$S/PagedBox.java" 'post\(new Runnable\(\) \{ @Override public void run\(\) \{ l\.onPage\(dir\); \} \}\)' 'PagedBox page turn (removeAllViews) posted'
forbid "$S/PagedBox.java" '^ *listener\.onPage\(' 'PagedBox turns the page inside onTouchEvent'

# 2. HomeActivity routes every touch through TouchGuard
need   "$S/HomeActivity.java" 'return touchGuard\.dispatch\(e, getWindow\(\)\.getDecorView\(\)\);' 'Home dispatch goes through TouchGuard'
need   "$S/HomeActivity.java" 'HomeActivity\.super\.dispatchTouchEvent\(e\)' 'TouchGuard hands events to the framework'
need   "$S/HomeActivity.java" 'boolean touching\(\) \{ return touchGuard\.active\(\); \}' 'touching() follows the guarded gesture (ends even with a stuck contact)'
forbid "$S/HomeActivity.java" 'private boolean touching;' 'old touching flag (stays true forever with a stuck contact)'
need   "$S/BlocksHome.java" 'a\.touching\(\)' 'home rebuild still waits for the finger to lift'

# 3. TouchGuard: one pointer, latest wins; stale view -> cancel + swallow; framework exception -> cancel, no crash
G=$S/TouchGuard.java
need   "$G" 'act == MotionEvent\.ACTION_POINTER_DOWN' 'handles a new pointer'
need   "$G" 'if \(tracked >= 0\) cancel\(e\);       // 后按下的手指接管' 'a new pointer cancels the old one'
need   "$G" 'return sendSingle\(e, MotionEvent\.ACTION_DOWN, idx\);' 'new pointer becomes its own ACTION_DOWN'
need   "$G" 'if \(tracked < 0\) return true;' 'events with no guarded gesture are swallowed until the next press'
need   "$G" 'downView != null && !downView\.isShown\(\)' 'view under the finger gone mid-gesture -> cancel'
need   "$G" 'if \(e\.getActionIndex\(\) != idx\) return true;' 'other pointers lifting are ignored'
need   "$G" 'return finish\(sendSingle\(e, MotionEvent\.ACTION_UP, idx\)\);' 'tracked pointer lifting ends the gesture with ACTION_UP'
need   "$G" 'catch \(RuntimeException x\) \{' 'framework dispatch exceptions caught'
need   "$G" 'if \(!framework\(x\)\) throw x;' 'only framework-side exceptions are swallowed'
need   "$G" 'c\.equals\("android\.view\.ViewGroup"\) \|\| c\.equals\("android\.view\.View"\)' 'framework() looks at the throwing frame'
need   "$G" 'MotionEvent\.obtain\(downTime, time, action, 1, pp, pc' 'synthetic events carry exactly one pointer'
need   "$G" 'out\.addBatch\(e\.getHistoricalEventTime\(h\), pc' 'synthetic moves keep their history'
forbid "$G" 'getPointerCount\(\) > 1\) return super' 'no bypass for multi-pointer events'

[ $fail = 0 ] && echo "home-touch-guard: ok"
exit $fail
