// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.hardware.input.InputManager;
import android.os.IBinder;
import android.os.SystemClock;
import android.util.Log;
import android.view.Gravity;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.KeyCharacterMap;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.widget.LinearLayout;

import java.lang.reflect.Method;

/**
 * 传统“三大金刚键”导航栏：屏幕底部 返回 / 主页 / 多任务。
 * 用 overscan 把底部这一条从应用的显示区域里让出来，所以不会挡住应用自己的底栏（比如微信读书的工具栏）。
 * 设置 → 桌面 → 导航方式 里打开；prefs "navmode"：0 手势，1 三大金刚键，2 两者都要。
 */
public class NavBarService extends Service {
    private static final String TAG = "VeraNavBar";
    static final int HEIGHT_DP = 28;   // 24 → 28：三个键按得更准（用户反馈“有点小”）
    private WindowManager wm;
    private View bar;

    static int mode(Context c) { return Store.prefs(c, "home").getInt("navmode", 0); }

    static void apply(Context c) {
        Intent i = new Intent(c, NavBarService.class);
        if (mode(c) == 0) c.stopService(i); else c.startService(i);
    }

    @Override public IBinder onBind(Intent i) { return null; }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (mode(this) == 0) { stopSelf(); return START_NOT_STICKY; }
        show();
        return START_STICKY;
    }

    private void show() {
        if (bar != null) return;
        wm = (WindowManager) getSystemService(WINDOW_SERVICE);
        int h = Ui.dp(this, HEIGHT_DP);
        LinearLayout wrap = new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.setBackgroundColor(Color.WHITE);
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.addView(button(Icons.Kind.BACK, new Runnable() { @Override public void run() { key(KeyEvent.KEYCODE_BACK); } }),
            new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        row.addView(button(Icons.Kind.HOME, new Runnable() { @Override public void run() { home(); } }),
            new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        row.addView(button(Icons.Kind.SWITCH, new Runnable() { @Override public void run() { recents(); } }),
            new LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.MATCH_PARENT, 1));
        wrap.addView(row, new LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, h));

        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT, h,
            WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
                | WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                | WindowManager.LayoutParams.FLAG_LAYOUT_IN_OVERSCAN,   // 底部这条已经让给 overscan，必须能画进去
            PixelFormat.OPAQUE);
        // 不能用 Gravity.BOTTOM：它参照的是已经被 overscan 缩小的应用区域，整条会往上偏，盖住应用的底部。
        // 按屏幕真实高度从顶部绝对定位，正好落在让出来的那一条里。
        android.util.DisplayMetrics real = new android.util.DisplayMetrics();
        wm.getDefaultDisplay().getRealMetrics(real);
        lp.gravity = Gravity.TOP | Gravity.LEFT;
        lp.y = real.heightPixels - h;
        try {
            setOverscanBottom(h);
            wm.addView(wrap, lp);
            bar = wrap;
        } catch (Throwable t) {
            Log.w(TAG, "cannot add nav bar: " + t);
            setOverscanBottom(0);
        }
    }

    private View button(Icons.Kind k, final Runnable r) {
        LinearLayout b = new LinearLayout(this);
        b.setGravity(Gravity.CENTER);
        android.graphics.drawable.StateListDrawable bg = new android.graphics.drawable.StateListDrawable();
        bg.addState(new int[] { android.R.attr.state_pressed }, new android.graphics.drawable.ColorDrawable(Color.BLACK));
        b.setBackground(bg);
        b.addView(new Icons.IconView(this, k), new LinearLayout.LayoutParams(Ui.dp(this, 19), Ui.dp(this, 19)));
        b.setClickable(true);
        b.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { r.run(); } });
        return b;
    }

    private void key(int code) {
        try {
            InputManager im = (InputManager) getSystemService(Context.INPUT_SERVICE);
            Method m = InputManager.class.getMethod("injectInputEvent", InputEvent.class, int.class);
            long now = SystemClock.uptimeMillis();
            for (int action : new int[] { KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP }) {
                KeyEvent e = new KeyEvent(now, now, action, code, 0, 0, KeyCharacterMap.VIRTUAL_KEYBOARD, 0,
                    KeyEvent.FLAG_FROM_SYSTEM | KeyEvent.FLAG_VIRTUAL_HARD_KEY, InputDevice.SOURCE_KEYBOARD);
                m.invoke(im, e, 0);   // INJECT_INPUT_EVENT_MODE_ASYNC
            }
        } catch (Throwable t) { Log.w(TAG, "inject key failed: " + t); }
    }

    private void home() {
        Intent i = new Intent(this, HomeActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        startActivity(i);
    }

    private void recents() {
        Intent i = new Intent(this, SwitcherActivity.class);
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_NO_ANIMATION);
        startActivity(i);
    }

    /** IWindowManager.setOverscan(display 0, 0, 0, 0, bottom): apps lay out above the bar instead of under it. */
    private void setOverscanBottom(int px) {
        try {
            Class<?> g = Class.forName("android.view.WindowManagerGlobal");
            Object wms = g.getMethod("getWindowManagerService").invoke(null);
            wms.getClass().getMethod("setOverscan", int.class, int.class, int.class, int.class, int.class)
                .invoke(wms, 0, 0, 0, 0, px);
        } catch (Throwable t) { Log.w(TAG, "setOverscan failed: " + t); }
    }

    @Override public void onDestroy() {
        if (bar != null) {
            try { wm.removeView(bar); } catch (Throwable ignored) { }
            bar = null;
        }
        setOverscanBottom(0);
        super.onDestroy();
    }
}
