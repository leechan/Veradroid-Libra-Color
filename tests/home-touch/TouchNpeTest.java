package com.veradroid.home;

import android.content.Context;
import android.os.Looper;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewParent;
import android.widget.FrameLayout;
import android.widget.LinearLayout;

import java.util.ArrayList;
import java.util.List;

/**
 * On-device test of the KT5 1.06 Home crash (NPE in ViewGroup.resetCancelNextUpFlag) against the real Android 7.1
 * framework of the container, without touching the running Home: run with app_process as root (see run-device.sh).
 *
 *   1. repro      -- the 1.06 pattern (click handled synchronously in ACTION_UP rebuilds the container) with a second
 *                    contact holding a TouchTarget in the same ViewGroup: must throw exactly that NPE.
 *   2. fast       -- the same tree with Ui.fast (click posted after dispatch): no crash, click not run inside dispatch.
 *   3. guard      -- the 1.06 pattern routed through TouchGuard: no crash, the tap still clicks.
 *   4. stuck      -- two contacts stuck down, then taps by the 3rd/4th/5th pointer: every tap is one clean single-pointer
 *                    DOWN/UP on the right view, the stuck ones never reach the views, active() is false between taps.
 *   5. stale      -- the view under the finger is removed mid-gesture: ACTION_CANCEL goes out, the rest is swallowed
 *                    until the next press, which works normally.
 *   6. framework  -- an exception thrown by the framework's ViewGroup dispatch is caught (gesture cancelled), one from
 *                    app code is not.
 * Prints "PASS <name>" / "FAIL <name>: why" and "touch-npe: N passed, M failed"; exit status = failures.
 */
public class TouchNpeTest {
    static Context ctx;
    static int fails, passes;
    static long T0 = 1000;

    public static void main(String[] args) throws Exception {
        Looper.prepareMainLooper();
        Object at = Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null);
        ctx = (Context) at.getClass().getMethod("getSystemContext").invoke(at);
        run("repro", new T() { public void run() throws Exception { repro(); } });
        run("fast", new T() { public void run() throws Exception { fast(); } });
        run("guard", new T() { public void run() throws Exception { guard(); } });
        run("stuck", new T() { public void run() throws Exception { stuck(); } });
        run("stale", new T() { public void run() throws Exception { stale(); } });
        run("framework", new T() { public void run() throws Exception { framework(); } });
        System.out.println("touch-npe: " + passes + " passed, " + fails + " failed");
        System.exit(fails);
    }

    interface T { void run() throws Exception; }
    static void run(String n, T t) {
        try { t.run(); passes++; System.out.println("PASS " + n); }
        catch (Throwable x) { fails++; System.out.println("FAIL " + n + ": " + x); }
    }
    static void check(boolean ok, String why) { if (!ok) throw new AssertionError(why); }

    // ------------------------------------------------------------------ a small "page": root > box > [A, B]

    static final class Rec implements View.OnTouchListener {
        final List<Integer> acts = new ArrayList<Integer>();
        final List<Integer> counts = new ArrayList<Integer>();
        Runnable onUp;
        public boolean onTouch(View v, MotionEvent e) {
            acts.add(e.getActionMasked()); counts.add(e.getPointerCount());
            if (e.getActionMasked() == MotionEvent.ACTION_UP && onUp != null) onUp.run();
            return true;
        }
        int n(int act) { int c = 0; for (int a : acts) if (a == act) c++; return c; }
        boolean single() { for (int c : counts) if (c != 1) return false; return true; }
    }

    static final class Page {
        FrameLayout root; LinearLayout box; View a, b; Rec ra = new Rec(), rb = new Rec();
        Page() throws Exception {
            root = new FrameLayout(ctx);
            box = new LinearLayout(ctx);
            box.setMotionEventSplittingEnabled(true);
            root.setMotionEventSplittingEnabled(true);
            root.addView(box, new FrameLayout.LayoutParams(1000, 1000));
            a = new View(ctx); b = new View(ctx);
            a.setClickable(true); b.setClickable(true);
            a.setOnTouchListener(ra); b.setOnTouchListener(rb);
            box.addView(a, new LinearLayout.LayoutParams(500, 1000));
            box.addView(b, new LinearLayout.LayoutParams(500, 1000));
            attach(root);
            root.measure(View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(1000, View.MeasureSpec.EXACTLY));
            root.layout(0, 0, 1000, 1000);
        }
    }

    /** give the root a non-View parent (like ViewRootImpl), so isShown() works as in a window */
    static void attach(View root) throws Exception {
        ViewParent p = (ViewParent) java.lang.reflect.Proxy.newProxyInstance(TouchNpeTest.class.getClassLoader(), new Class<?>[] { ViewParent.class },
            new java.lang.reflect.InvocationHandler() {
                public Object invoke(Object o, java.lang.reflect.Method m, Object[] a) {
                    Class<?> r = m.getReturnType();
                    if (r == boolean.class) return false;
                    if (r == int.class) return 0;
                    if (r == float.class) return 0f;
                    return null;
                }
            });
        java.lang.reflect.Method m = View.class.getDeclaredMethod("assignParent", ViewParent.class);
        m.setAccessible(true);
        m.invoke(root, p);
    }

    // ------------------------------------------------------------------ events (window coordinates)

    static MotionEvent ev(long down, long t, int action, int[] ids, float[][] xy) {
        MotionEvent.PointerProperties[] pp = new MotionEvent.PointerProperties[ids.length];
        MotionEvent.PointerCoords[] pc = new MotionEvent.PointerCoords[ids.length];
        for (int i = 0; i < ids.length; i++) {
            pp[i] = new MotionEvent.PointerProperties(); pp[i].id = ids[i]; pp[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            pc[i] = new MotionEvent.PointerCoords(); pc[i].x = xy[i][0]; pc[i].y = xy[i][1]; pc[i].pressure = 1; pc[i].size = 1;
        }
        return MotionEvent.obtain(down, t, action, ids.length, pp, pc, 0, 0, 1, 1, 2, 0, 0x1002, 0);
    }
    static int pd(int idx) { return MotionEvent.ACTION_POINTER_DOWN | (idx << MotionEvent.ACTION_POINTER_INDEX_SHIFT); }
    static int pu(int idx) { return MotionEvent.ACTION_POINTER_UP | (idx << MotionEvent.ACTION_POINTER_INDEX_SHIFT); }
    static final float[] PA = { 250, 500 }, PB = { 750, 500 };

    interface D { boolean d(MotionEvent e); }

    /** pointer 0 holds A, pointer 1 taps B (DOWN, POINTER_DOWN, POINTER_UP) */
    static void twoFingerTap(D d) {
        long t = T0;
        d.d(ev(t, t, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { PA }));
        d.d(ev(t, t + 50, pd(1), new int[] { 0, 1 }, new float[][] { PA, PB }));
        d.d(ev(t, t + 120, pu(1), new int[] { 0, 1 }, new float[][] { PA, PB }));
    }

    static void repro() throws Exception {
        final Page p = new Page();
        p.rb.onUp = new Runnable() { public void run() { p.box.removeAllViews(); } };   // 1.06: click rebuilds the page inside dispatch
        try {
            twoFingerTap(new D() { public boolean d(MotionEvent e) { return p.root.dispatchTouchEvent(e); } });
        } catch (NullPointerException x) {
            StackTraceElement s = x.getStackTrace()[0];
            check(s.getClassName().equals("android.view.ViewGroup") && s.getMethodName().equals("resetCancelNextUpFlag"), "NPE from " + s);
            System.out.println("  repro: " + x.getClass().getSimpleName() + " at " + s);
            return;
        }
        throw new AssertionError("the 1.06 pattern did not crash (repro lost)");
    }

    static void fast() throws Exception {
        final Page p = new Page();
        final int[] clicks = { 0 };
        Ui.fast(p.b);
        p.b.setOnClickListener(new View.OnClickListener() { public void onClick(View v) { clicks[0]++; p.box.removeAllViews(); } });
        p.a.setOnTouchListener(p.ra);
        twoFingerTap(new D() { public boolean d(MotionEvent e) { return p.root.dispatchTouchEvent(e); } });
        check(clicks[0] == 0, "click ran inside touch dispatch");
        check(p.box.getChildCount() == 2, "tree changed inside dispatch");
        p.box.removeAllViews();   // what the posted click does next: no gesture in flight, no crash
        long t = T0 + 500;
        p.root.dispatchTouchEvent(ev(t, t + 10, MotionEvent.ACTION_UP, new int[] { 0 }, new float[][] { PA }));
    }

    static TouchGuard guardFor(final View root, final List<Integer> ends) {
        return new TouchGuard(new TouchGuard.Target() {
            public boolean superDispatch(MotionEvent e) { return root.dispatchTouchEvent(e); }
            public void gestureEnded() { ends.add(1); }
        });
    }

    static void guard() throws Exception {
        final Page p = new Page();
        p.rb.onUp = new Runnable() { public void run() { p.box.removeAllViews(); } };
        final List<Integer> ends = new ArrayList<Integer>();
        final TouchGuard g = guardFor(p.root, ends);
        twoFingerTap(new D() { public boolean d(MotionEvent e) { return g.dispatch(e, p.root); } });
        check(p.rb.n(MotionEvent.ACTION_DOWN) == 1 && p.rb.n(MotionEvent.ACTION_UP) == 1, "B did not get its tap: " + p.rb.acts);
        check(p.ra.n(MotionEvent.ACTION_CANCEL) == 1, "A's gesture was not cancelled: " + p.ra.acts);
        check(p.ra.single() && p.rb.single(), "a view saw more than one pointer");
        check(p.box.getChildCount() == 0, "rebuild did not happen");
        check(!g.active(), "gesture still active after the tap");
        // the stuck pointer 0 lifting later is swallowed
        g.dispatch(ev(T0, T0 + 900, MotionEvent.ACTION_UP, new int[] { 0 }, new float[][] { PA }), p.root);
    }

    static void stuck() throws Exception {
        final Page p = new Page();
        final List<Integer> ends = new ArrayList<Integer>();
        final TouchGuard g = guardFor(p.root, ends);
        final int[] rebuilds = { 0 };
        p.rb.onUp = new Runnable() { public void run() { rebuilds[0]++; } };
        long t = T0;
        float[] S0 = { 672, 924 }, S1 = { 215, 131 };   // the two phantom contacts of the diagnostic (both inside the page)
        g.dispatch(ev(t, t, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { S0 }), p.root);
        g.dispatch(ev(t, t + 5, pd(1), new int[] { 0, 1 }, new float[][] { S0, S1 }), p.root);
        int before = p.rb.acts.size();
        for (int k = 0; k < 3; k++) {
            int id = 2 + k; long tt = t + 1000 * (k + 1);
            g.dispatch(ev(t, tt, MotionEvent.ACTION_MOVE, new int[] { 0, 1 }, new float[][] { S0, S1 }), p.root);
            check(!g.active() || k == 0, "a stuck contact kept a gesture alive");
            g.dispatch(ev(t, tt + 10, pd(2), new int[] { 0, 1, id }, new float[][] { S0, S1, PB }), p.root);
            check(g.active(), "the new finger did not start a gesture");
            g.dispatch(ev(t, tt + 40, MotionEvent.ACTION_MOVE, new int[] { 0, 1, id }, new float[][] { S0, S1, { PB[0] + 2, PB[1] } }), p.root);
            g.dispatch(ev(t, tt + 90, pu(2), new int[] { 0, 1, id }, new float[][] { S0, S1, PB }), p.root);
            check(!g.active(), "gesture not finished after the finger lifted (touching() would stay true)");
        }
        check(rebuilds[0] == 3, "taps under stuck contacts: " + rebuilds[0] + " of 3 reached B");
        check(p.rb.single(), "B saw the stuck pointers");
        List<Integer> mine = p.rb.acts.subList(before, p.rb.acts.size());
        check(mine.get(0) == MotionEvent.ACTION_DOWN && mine.get(mine.size() - 1) == MotionEvent.ACTION_UP, "B's events: " + mine);
    }

    static void stale() throws Exception {
        final Page p = new Page();
        final List<Integer> ends = new ArrayList<Integer>();
        final TouchGuard g = guardFor(p.root, ends);
        final int[] rootSaw = { 0 };
        long t = T0;
        g.dispatch(ev(t, t, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { PB }), p.root);
        p.box.removeView(p.b);   // a background rebuild while the finger is down
        g.dispatch(ev(t, t + 30, MotionEvent.ACTION_MOVE, new int[] { 0 }, new float[][] { PB }), p.root);
        check(!g.active(), "gesture not cancelled after the view under the finger went away");
        check(p.rb.n(MotionEvent.ACTION_CANCEL) >= 1, "B got no cancel: " + p.rb.acts);
        p.root.setOnTouchListener(new View.OnTouchListener() { public boolean onTouch(View v, MotionEvent e) { rootSaw[0]++; return true; } });
        boolean r = g.dispatch(ev(t, t + 60, MotionEvent.ACTION_UP, new int[] { 0 }, new float[][] { PB }), p.root);
        check(r && rootSaw[0] == 0 && p.ra.acts.isEmpty(), "events after the cancel were not swallowed");
        long t2 = t + 1000;
        g.dispatch(ev(t2, t2, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { PA }), p.root);
        g.dispatch(ev(t2, t2 + 60, MotionEvent.ACTION_UP, new int[] { 0 }, new float[][] { PA }), p.root);
        check(p.ra.n(MotionEvent.ACTION_DOWN) == 1 && p.ra.n(MotionEvent.ACTION_UP) == 1, "next press did not work: " + p.ra.acts);
    }

    static void framework() throws Exception {
        final Page p = new Page();
        final List<Integer> ends = new ArrayList<Integer>();
        final int[] mode = { 0 };
        final TouchGuard g = new TouchGuard(new TouchGuard.Target() {
            public boolean superDispatch(MotionEvent e) {
                if (mode[0] == 1 && e.getActionMasked() == MotionEvent.ACTION_MOVE) {
                    NullPointerException x = new NullPointerException("Attempt to read from field 'int android.view.View.mPrivateFlags' on a null object reference");
                    x.setStackTrace(new StackTraceElement[] { new StackTraceElement("android.view.ViewGroup", "resetCancelNextUpFlag", "ViewGroup.java", 2414),
                        new StackTraceElement("android.view.ViewGroup", "dispatchTouchEvent", "ViewGroup.java", 2319) });
                    throw x;
                }
                if (mode[0] == 2 && e.getActionMasked() == MotionEvent.ACTION_MOVE) throw new IllegalStateException("app bug");
                return p.root.dispatchTouchEvent(e);
            }
            public void gestureEnded() { ends.add(1); }
        });
        long t = T0;
        mode[0] = 1;
        g.dispatch(ev(t, t, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { PB }), p.root);
        boolean r = g.dispatch(ev(t, t + 30, MotionEvent.ACTION_MOVE, new int[] { 0 }, new float[][] { PB }), p.root);
        check(r && !g.active(), "framework NPE not turned into a cancelled gesture");
        check(p.rb.n(MotionEvent.ACTION_CANCEL) == 1, "B got no cancel after the framework error: " + p.rb.acts);
        check(!ends.isEmpty(), "gestureEnded not called");
        mode[0] = 2;
        g.dispatch(ev(t + 100, t + 100, MotionEvent.ACTION_DOWN, new int[] { 0 }, new float[][] { PB }), p.root);
        try {
            g.dispatch(ev(t + 100, t + 130, MotionEvent.ACTION_MOVE, new int[] { 0 }, new float[][] { PB }), p.root);
            throw new AssertionError("an app exception was swallowed");
        } catch (IllegalStateException expected) { }
    }
}
