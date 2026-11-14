// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.util.Log;
import android.view.MotionEvent;
import android.view.View;

/** 触摸覆盖测试：全屏网格，触摸点会画十字并标坐标；用于检查四角/边缘/状态栏区域。 */
public class TouchTestActivity extends Activity {
    private TouchView view;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        getWindow().setWindowAnimations(0);
        view = new TouchView(this);
        setContentView(view);
    }

    @Override public boolean dispatchTouchEvent(MotionEvent e) {
        Log.d("TouchTest", "activity dispatch action=" + e.getActionMasked() + " x=" + (int) e.getX() + " y=" + (int) e.getY());
        return super.dispatchTouchEvent(e);
    }

    @Override protected void onResume() {
        super.onResume();
        StatusBarService.setSuppressed(true);
        StatusBarService.refresh(this);
    }

    @Override protected void onPause() {
        StatusBarService.setSuppressed(false);
        StatusBarService.refresh(this);
        super.onPause();
    }

    static class TouchView extends View {
        private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        private float x = -1, y = -1;
        private String action = "";

        TouchView(Context c) { super(c); setClickable(true); setFocusable(true); setFocusableInTouchMode(true); }

        @Override protected void onDraw(Canvas c) {
            c.drawColor(Color.WHITE);
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(1);
            p.setColor(Color.LTGRAY);
            for (int i = 0; i < getWidth(); i += 100) c.drawLine(i, 0, i, getHeight(), p);
            for (int i = 0; i < getHeight(); i += 100) c.drawLine(0, i, getWidth(), i, p);
            p.setColor(Color.BLACK);
            p.setStrokeWidth(2);
            c.drawLine(getWidth() / 2f, 0, getWidth() / 2f, getHeight(), p);
            c.drawLine(0, getHeight() / 2f, getWidth(), getHeight() / 2f, p);
            if (x >= 0) {
                p.setStyle(Paint.Style.STROKE);
                p.setStrokeWidth(4);
                p.setColor(Color.BLACK);
                c.drawCircle(x, y, 26, p);
                c.drawLine(x - 34, y, x + 34, y, p);
                c.drawLine(x, y - 34, x, y + 34, p);
                p.setStyle(Paint.Style.FILL);
                p.setTextSize(28);
                c.drawText("x=" + (int) x + "  y=" + (int) y + "  " + action, 24, 52, p);
            }
        }

        @Override public boolean onTouchEvent(MotionEvent e) {
            Log.d("TouchTest", "view touch x=" + (int) e.getX() + " y=" + (int) e.getY() + " action=" + e.getActionMasked());
            x = e.getX(); y = e.getY();
            switch (e.getActionMasked()) {
                case MotionEvent.ACTION_DOWN: action = "DOWN"; break;
                case MotionEvent.ACTION_MOVE: action = "MOVE"; break;
                case MotionEvent.ACTION_UP: action = "UP"; break;
                default: action = "OTHER"; break;
            }
            invalidate();
            return true;
        }
    }
}
