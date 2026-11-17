// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.ime;

import android.content.Context;
import android.view.View;
import android.widget.LinearLayout;

/**
 * One row of keys, laid out by exact pixel arithmetic instead of LinearLayout's weight + margin distribution:
 * key i spans [round(W * w0..i-1 / sum), round(W * w0..i / sum)) of the row's actual width W, minus a fixed gap,
 * so the leftover pixels are spread over the row, every row with the same weights has exactly the same edges,
 * and a key's position depends on nothing but the width (not on labels, not on the order of measure passes).
 * Children are the key views with LinearLayout.LayoutParams (only the weight is used; margins are ignored).
 */
final class KeyRow extends LinearLayout {
    private final int gapX, gapY;
    private int[] edge = new int[0];

    KeyRow(Context c, int gapX, int gapY) {
        super(c);
        setOrientation(HORIZONTAL);
        this.gapX = gapX;
        this.gapY = gapY;
    }

    private float[] weights() {
        int n = getChildCount();
        float[] w = new float[n];
        for (int i = 0; i < n; i++) {
            LayoutParams lp = (LayoutParams) getChildAt(i).getLayoutParams();
            w[i] = lp.weight > 0 ? lp.weight : 1f;
        }
        return w;
    }

    @Override protected void onMeasure(int ws, int hs) {
        int w = MeasureSpec.getSize(ws), h = MeasureSpec.getSize(hs);
        setMeasuredDimension(w, h);
        int inner = w - getPaddingLeft() - getPaddingRight();
        edge = KeyGrid.edges(inner, weights());
        int ch = Math.max(0, h - 2 * gapY);
        for (int i = 0; i < getChildCount(); i++) {
            View v = getChildAt(i);
            int cw = Math.max(0, edge[i + 1] - edge[i] - gapX);
            v.measure(MeasureSpec.makeMeasureSpec(cw, MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(ch, MeasureSpec.EXACTLY));
        }
    }

    @Override protected void onLayout(boolean changed, int l, int t, int r, int b) {
        int x0 = getPaddingLeft() + gapX / 2;
        for (int i = 0; i < getChildCount() && i + 1 < edge.length; i++) {
            View v = getChildAt(i);
            int left = x0 + edge[i];
            v.layout(left, gapY, left + v.getMeasuredWidth(), gapY + v.getMeasuredHeight());
        }
    }
}
