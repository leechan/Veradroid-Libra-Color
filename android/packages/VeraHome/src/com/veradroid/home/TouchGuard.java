package com.veradroid.home;

import android.util.Log;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;

/**
 * 主页窗口的触摸入口（HomeActivity.dispatchTouchEvent）：交给系统的永远是一根手指的一次完整按下-抬起。
 *
 * 现象（KT5）：面板（或输入桥）留下两个一直按着的“幽灵”触点，之后十几次点按在 Android 看来都是
 * 第三、第四根手指的 POINTER_DOWN / POINTER_UP，整个手势一分多钟没有结束。同一个 ViewGroup 里于是有两个 TouchTarget；
 * 点按在 ACTION_UP 里同步 performClick 把页面重搭（removeAllViews / removeView）时，系统正在遍历的下一个 TouchTarget
 * 已被回收（child = null），ViewGroup.resetCancelNextUpFlag 空指针，主页崩溃。另外手势不结束时 touching 一直是 true，
 * 换页（dataChanged）一直等不到抬手。
 *
 * 这里做三件事：
 * 1. 只跟一根手指，后按下的手指接管（先给之前那根发 ACTION_CANCEL，再给新手指单独发一个 ACTION_DOWN）；其余触点
 *    （包括卡住的幽灵触点）不交给系统。主页没有任何多指操作（双指手势由宿主的 vinput 处理）。
 *    每个 ViewGroup 最多一个 TouchTarget，上面那种崩溃不会再有。
 * 2. 手势进行中，按下时手指下面的那个控件不在了（页面重搭、换页、被藏起来）：发 ACTION_CANCEL，之后的事件都吞掉，
 *    直到下一次有手指按下。抬手不会落到新页面的别的东西上。
 * 3. 系统的 ViewGroup 触摸分发自己抛了异常（上面的空指针一类）：记一行日志、取消这次手势、吞到下一次按下，主页不崩。
 */
final class TouchGuard {
    interface Target {
        /** 交给系统分发（Activity.dispatchTouchEvent 的 super）。 */
        boolean superDispatch(MotionEvent e);
        /** 一次手势（对系统而言）结束了：ACTION_UP / ACTION_CANCEL 已经发出。 */
        void gestureEnded();
    }

    private static final String TAG = "VeraHome";
    private final Target target;
    /** 正交给系统的那根手指（-1 = 没有手势：事件都吞掉，直到有手指按下）。 */
    private int tracked = -1;
    /** 这次手势是不是合成的（从 POINTER_DOWN 开始，或者原事件里还有别的触点）：合成的手势全程都发单指的合成事件。 */
    private boolean synth;
    private long downTime;
    /** 按下时手指下面最深的那个控件：它不在了（或看不见了），说明手势中间页面换了。 */
    private View downView;
    private int recovered;

    TouchGuard(Target t) { target = t; }

    /** 系统眼里有手指按着（从 ACTION_DOWN 到 ACTION_UP / CANCEL）。 */
    boolean active() { return tracked >= 0; }

    boolean dispatch(MotionEvent e, View root) {
        int act = e.getActionMasked();
        if (act == MotionEvent.ACTION_DOWN) {
            if (tracked >= 0) end();   // 不该有（DOWN 之前系统会先抬起所有手指），保险
            tracked = e.getPointerId(0);
            synth = e.getPointerCount() != 1;
            downTime = e.getDownTime();
            downView = hit(root, e.getX(0), e.getY(0));
            return synth ? sendSingle(e, MotionEvent.ACTION_DOWN, 0) : send(e);
        }
        if (act == MotionEvent.ACTION_POINTER_DOWN) {
            int idx = e.getActionIndex();
            if (tracked >= 0) cancel(e);       // 后按下的手指接管
            tracked = e.getPointerId(idx);
            synth = true;
            downTime = e.getEventTime();
            downView = hit(root, e.getX(idx), e.getY(idx));
            return sendSingle(e, MotionEvent.ACTION_DOWN, idx);
        }
        if (tracked < 0) return true;          // 没有交给系统的手势：别的（幽灵）触点的事件
        int idx = e.findPointerIndex(tracked);
        if (idx < 0) { cancel(e); return true; }
        if (act != MotionEvent.ACTION_CANCEL && downView != null && !downView.isShown()) {
            Log.i(TAG, "touch: the view under the finger went away mid-gesture (page rebuilt), gesture cancelled");
            cancel(e);
            return true;
        }
        switch (act) {
        case MotionEvent.ACTION_MOVE:
            return synth || e.getPointerCount() != 1 ? sendSingle(e, MotionEvent.ACTION_MOVE, idx) : send(e);
        case MotionEvent.ACTION_POINTER_UP:
            if (e.getActionIndex() != idx) return true;   // 别的触点抬起
            return finish(sendSingle(e, MotionEvent.ACTION_UP, idx));
        case MotionEvent.ACTION_UP:
            return finish(synth ? sendSingle(e, MotionEvent.ACTION_UP, idx) : send(e));
        case MotionEvent.ACTION_CANCEL:
            return finish(synth || e.getPointerCount() != 1 ? sendSingle(e, MotionEvent.ACTION_CANCEL, idx) : send(e));
        default:
            return send(e);
        }
    }

    private boolean finish(boolean r) { if (tracked >= 0) end(); return r; }

    private void end() {
        tracked = -1;
        synth = false;
        downView = null;
        target.gestureEnded();
    }

    /** 给正跟着的那根手指发 ACTION_CANCEL（清掉各级 ViewGroup 的 TouchTarget），然后吞到下一次按下。 */
    private void cancel(MotionEvent e) {
        int idx = tracked >= 0 ? e.findPointerIndex(tracked) : -1;
        MotionEvent c = single(e, MotionEvent.ACTION_CANCEL, idx >= 0 ? idx : 0);
        try { target.superDispatch(c); } catch (RuntimeException x) { if (!framework(x)) { c.recycle(); throw x; } }
        c.recycle();
        if (tracked >= 0) end();
    }

    private boolean sendSingle(MotionEvent e, int action, int idx) {
        MotionEvent s = single(e, action, idx);
        try { return send(s); } finally { s.recycle(); }
    }

    private boolean send(MotionEvent e) {
        try {
            return target.superDispatch(e);
        } catch (RuntimeException x) {
            if (!framework(x)) throw x;
            if (++recovered <= 20) Log.w(TAG, "touch: framework touch dispatch failed, gesture cancelled", x);
            if (e.getActionMasked() != MotionEvent.ACTION_CANCEL && tracked >= 0) {
                // 一次取消就把各级 TouchTarget 清干净；再出错也不管了，吞到下一次按下
                MotionEvent c = single(e, MotionEvent.ACTION_CANCEL, Math.max(0, e.findPointerIndex(tracked)));
                try { target.superDispatch(c); } catch (RuntimeException ignored) { }
                c.recycle();
            }
            if (tracked >= 0) end();
            return true;
        }
    }

    /** 异常是不是从系统的触摸分发（ViewGroup / View 的 dispatchTouchEvent 一类）里出来的；我们自己代码里的错照样抛。 */
    static boolean framework(Throwable x) {
        StackTraceElement[] st = x.getStackTrace();
        if (st == null || st.length == 0) return false;
        String c = st[0].getClassName();
        return c.equals("android.view.ViewGroup") || c.equals("android.view.View");
    }

    /** 原事件里 idx 那根手指单独做成一个事件（ACTION_MOVE 带上历史采样），downTime 用这次手势的。 */
    private MotionEvent single(MotionEvent e, int action, int idx) {
        MotionEvent.PointerProperties[] pp = { new MotionEvent.PointerProperties() };
        MotionEvent.PointerCoords[] pc = { new MotionEvent.PointerCoords() };
        e.getPointerProperties(idx, pp[0]);
        int hs = action == MotionEvent.ACTION_MOVE ? e.getHistorySize() : 0;
        long dt = downTime;
        MotionEvent out;
        if (hs > 0) {
            e.getHistoricalPointerCoords(idx, 0, pc[0]);
            out = obtain(e, dt, e.getHistoricalEventTime(0), action, pp, pc);
            for (int h = 1; h < hs; h++) { e.getHistoricalPointerCoords(idx, h, pc[0]); out.addBatch(e.getHistoricalEventTime(h), pc, e.getMetaState()); }
            e.getPointerCoords(idx, pc[0]);
            out.addBatch(e.getEventTime(), pc, e.getMetaState());
        } else {
            e.getPointerCoords(idx, pc[0]);
            out = obtain(e, dt, e.getEventTime(), action, pp, pc);
        }
        return out;
    }

    private static MotionEvent obtain(MotionEvent e, long downTime, long time, int action, MotionEvent.PointerProperties[] pp, MotionEvent.PointerCoords[] pc) {
        return MotionEvent.obtain(downTime, time, action, 1, pp, pc, e.getMetaState(), e.getButtonState(), e.getXPrecision(), e.getYPrecision(),
                e.getDeviceId(), e.getEdgeFlags(), e.getSource(), e.getFlags());
    }

    /** 手指下面最深的那个看得见的控件（只看位置和可见性，和系统的找法差不多就够了）。 */
    static View hit(View v, float x, float y) {
        if (v == null) return null;
        for (int guard = 0; guard < 64 && v instanceof ViewGroup; guard++) {
            ViewGroup g = (ViewGroup) v;
            View found = null;
            float fx = 0, fy = 0;
            for (int i = g.getChildCount() - 1; i >= 0; i--) {
                View c = g.getChildAt(i);
                if (c == null || c.getVisibility() != View.VISIBLE) continue;
                float cx = x + g.getScrollX() - c.getLeft() - c.getTranslationX();
                float cy = y + g.getScrollY() - c.getTop() - c.getTranslationY();
                if (cx >= 0 && cy >= 0 && cx < c.getWidth() && cy < c.getHeight()) { found = c; fx = cx; fy = cy; break; }
            }
            if (found == null) return v;
            v = found; x = fx; y = fy;
        }
        return v;
    }
}
