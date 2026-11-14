// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

/** Plain black-and-white widgets for the e-ink panel: thin black frames, pressed = inverted, no shadows or ripples. */
final class Ui {
    /** 时间格式：设置 → 外观里可以选 12 小时制（默认 24 小时）。 */
    static String clockPattern(Context c) {
        try { return Store.prefs(c, "home").getBoolean("clock12", false) ? "a h:mm" : "HH:mm"; } catch (Throwable t) { return "HH:mm"; }
    }
    static String clock(Context c) {
        return new java.text.SimpleDateFormat(clockPattern(c), java.util.Locale.CHINA).format(new java.util.Date());
    }

    private Ui() { }

    static int dp(Context c, int v) { return (int) (v * c.getResources().getDisplayMetrics().density + 0.5f); }

    static TextView text(Context c, String s, float sp, boolean bold) {
        TextView t = new TextView(c);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(Color.BLACK);
        Fonts.apply(t, bold);
        return t;
    }

    static Drawable frame(Context c, boolean filled) {
        // 方块风格：直角黑框（墨水屏上不画按下状态，见 fast()），和 Blocks 的控件一样
        if (Blocks.on(c)) return filled ? Blocks.plainFilled(c) : Blocks.plain(c);
        GradientDrawable normal = new GradientDrawable();
        normal.setColor(filled ? Color.BLACK : Color.WHITE);
        normal.setStroke(2, Color.BLACK);
        normal.setCornerRadius(dp(c, 6));
        GradientDrawable pressed = new GradientDrawable();
        pressed.setColor(filled ? Color.WHITE : Color.BLACK);
        pressed.setStroke(2, Color.BLACK);
        pressed.setCornerRadius(dp(c, 6));
        StateListDrawable s = new StateListDrawable();
        s.addState(new int[] { android.R.attr.state_pressed }, pressed);
        s.addState(new int[] {}, normal);
        return s;
    }

    static Button button(Context c, String label, float sp, boolean filled, View.OnClickListener l) {
        Button b = new Button(c);
        b.setText(label);
        b.setTextSize(sp);
        b.setTypeface(Fonts.typeface(c));
        b.setAllCaps(false);
        b.setMinWidth(dp(c, 56));
        b.setMinimumWidth(dp(c, 56));
        b.setMinHeight(dp(c, 44));
        b.setMinimumHeight(dp(c, 44));
        b.setPadding(dp(c, 14), dp(c, 6), dp(c, 14), dp(c, 6));
        int idle = filled ? Color.WHITE : Color.BLACK, press = filled ? Color.BLACK : Color.WHITE;
        b.setTextColor(new ColorStateList(new int[][] { { android.R.attr.state_pressed }, {} }, new int[] { press, idle }));
        b.setBackground(frame(c, filled));
        if (Blocks.on(c)) { b.setTextColor(idle); Fonts.apply(b, true); b.setMinHeight(dp(c, 48)); b.setMinimumHeight(dp(c, 48)); }
        if (l != null) b.setOnClickListener(l);
        fast(b);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.leftMargin = dp(c, 8);
        b.setLayoutParams(lp);
        return b;
    }

    /**
     * 点按在抬手时立刻生效，不先画“按下”状态：墨水屏上按下高亮是多出来的一帧（显示桥还要为这块小变化等 70 ms），
     * 以前的流程是 按下→高亮帧→抬起→（排队）点击→新页面。可以长按的控件不动，仍走系统的处理。
     * 手指移出控件（或被外面的滚动接管）就不算点击。
     */
    static void fast(View v) {
        final int slop = android.view.ViewConfiguration.get(v.getContext()).getScaledTouchSlop();
        v.setOnTouchListener(new View.OnTouchListener() {
            private boolean armed;
            @Override public boolean onTouch(View view, android.view.MotionEvent e) {
                if (view.isLongClickable() || !view.isEnabled()) return false;
                switch (e.getActionMasked()) {
                case android.view.MotionEvent.ACTION_DOWN:
                    armed = true;
                    Perf.touch(e);
                    return true;
                case android.view.MotionEvent.ACTION_MOVE:
                    if (e.getX() < -slop || e.getY() < -slop || e.getX() > view.getWidth() + slop || e.getY() > view.getHeight() + slop) armed = false;
                    return true;
                case android.view.MotionEvent.ACTION_UP:
                    if (armed) { armed = false; view.performClick(); }
                    return true;
                default:
                    armed = false;
                    return true;
                }
            }
        });
    }

    static View rule(Context c, int px, int color) {
        View v = new View(c);
        v.setBackgroundColor(color);
        v.setLayoutParams(new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, px));
        return v;
    }
}
