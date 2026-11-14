// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.ime;

import android.app.Activity;
import android.content.Context;
import android.graphics.Color;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.TextView;

/** A tiny page for checking the IME: tap the field, type pinyin, pick a candidate. */
public class TestActivity extends Activity {
    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            | WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        int pad = (int) (18 * getResources().getDisplayMetrics().density);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("输入法测试");
        title.setTextSize(26);
        title.setTextColor(Color.BLACK);
        title.setTypeface(android.graphics.Typeface.DEFAULT_BOLD);
        root.addView(title);

        TextView hint = new TextView(this);
        hint.setText("点下面的输入框，用键盘输入 nihao，再点候选词；“编辑”键里有全选 / 复制 / 剪切 / 粘贴。");
        hint.setTextSize(16);
        hint.setTextColor(Color.DKGRAY);
        hint.setPadding(0, pad / 2, 0, pad);
        root.addView(hint);

        final EditText edit = new EditText(this);
        edit.setHint("在这里输入…");
        edit.setTextSize(24);
        edit.setGravity(Gravity.TOP | Gravity.START);
        edit.setMinLines(3);
        edit.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE);
        edit.setBackgroundColor(Color.WHITE);
        root.addView(edit, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        // a second field to paste into (copy / paste check)
        EditText edit2 = new EditText(this);
        edit2.setHint("第二个输入框（粘贴到这里）");
        edit2.setTextSize(24);
        edit2.setSingleLine(true);
        root.addView(edit2, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        setContentView(root);

        edit.requestFocus();
        edit.postDelayed(new Runnable() {
            @Override public void run() {
                InputMethodManager im = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
                if (im != null) im.showSoftInput(edit, InputMethodManager.SHOW_IMPLICIT);
            }
        }, 400);
    }
}
