// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;

/** A row of mutually exclusive buttons ("segmented control"); the selected one is drawn inverted (white on black). */
class Seg extends LinearLayout {
    interface Listener { void onPick(int index); }

    private final Button[] buttons;
    private final String[] labels;
    private int selected = -1;
    private final float sp;

    Seg(Context c, String[] labels, float sp, final Listener l) {
        super(c);
        this.labels = labels;
        this.sp = sp;
        setOrientation(HORIZONTAL);
        buttons = new Button[labels.length];
        for (int i = 0; i < labels.length; i++) {
            final int idx = i;
            buttons[i] = Ui.button(c, labels[i], sp, false, new View.OnClickListener() {
                @Override public void onClick(View v) { select(idx); if (l != null) l.onPick(idx); }
            });
            buttons[i].setMinWidth(0);
            buttons[i].setMinimumWidth(0);
            buttons[i].setPadding(Ui.dp(c, 6), Ui.dp(c, 6), Ui.dp(c, 6), Ui.dp(c, 6));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1);
            lp.leftMargin = i == 0 ? 0 : Ui.dp(c, 6);
            addView(buttons[i], lp);
        }
    }

    void select(int idx) {
        if (idx == selected) return;     // 没变：不换背景，不触发重画
        selected = idx;
        Context c = getContext();
        for (int i = 0; i < buttons.length; i++) {
            Button b = buttons[i];
            boolean on = i == idx;
            b.setBackground(Ui.frame(c, on));
            b.setTextColor(new android.content.res.ColorStateList(new int[][] { { android.R.attr.state_pressed }, {} },
                new int[] { on ? android.graphics.Color.BLACK : android.graphics.Color.WHITE, on ? android.graphics.Color.WHITE : android.graphics.Color.BLACK }));
        }
    }

    int selected() { return selected; }
}
