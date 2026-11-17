// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.ime;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.inputmethodservice.InputMethodService;
import android.os.Handler;
import android.os.Looper;
import android.text.InputType;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.os.SystemClock;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.ExtractedText;
import android.view.inputmethod.ExtractedTextRequest;
import android.view.inputmethod.InputConnection;
import android.widget.HorizontalScrollView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;

/**
 * A small black-and-white IME for the e-ink panel: English QWERTY, and a pinyin mode with a compact
 * character/phrase dictionary.  It deliberately has no animations, no popups and no glossy graphics:
 * every key press is one local e-ink refresh, and candidates are committed with a single tap.
 */
public class VeraImeService extends InputMethodService {
    private static final String TAG = "VeraIME";

    private LinearLayout root, candidatesRow, keyboard;
    private HorizontalScrollView candidateScroll;
    private TextView composing;
    private final List<TextView> letterKeys = new ArrayList<TextView>();
    private TextView shiftKey, modeKey, spaceKey;
    private int rowH = 140;

    private boolean chinese = true, shift = false, numeric = false, symbols = false;
    private boolean userChinese = true;   // 用户自己按“中/英”选的模式；密码 / 网址框临时切英文后要回到它
    /** Edit panel (copy / paste / cursor) shown instead of the letter keys; selecting = arrows extend the selection. */
    private boolean editMode = false, selecting = false;
    private int selAnchor = -1;
    private long editHiddenAt;
    private String editHiddenPkg;
    /** Last text we copied: pasted when the system clipboard cannot be read (ClipboardService hides it while
     *  TrustManager still thinks the device is locked, which is the default until keyguard reports in). */
    private String lastCopied;
    private TextView selectKey;
    private final StringBuilder pinyin = new StringBuilder();
    private final Map<String, String> charMap = new HashMap<String, String>();
    private final Map<String, String> wordMap = new HashMap<String, String>();
    private final List<String> charKeys = new ArrayList<String>();
    private final List<String> candidates = new ArrayList<String>();

    private final Handler ui = new Handler(Looper.getMainLooper());

    @Override public void onCreate() {
        super.onCreate();
        loadDictionary();
    }

    private int dp(float v) {
        return (int) (v * getResources().getDisplayMetrics().density + 0.5f);
    }

    private TextView text(String s, float sp, boolean bold) {
        TextView t = new TextView(this);
        t.setText(s);
        t.setTextSize(sp);
        t.setTextColor(Color.BLACK);
        if (bold) t.setTypeface(Typeface.DEFAULT_BOLD);
        return t;
    }

    private StateListDrawable keyBackground() {
        GradientDrawable normal = new GradientDrawable();
        normal.setColor(Color.WHITE);
        normal.setStroke(dp(2), Color.BLACK);
        normal.setCornerRadius(dp(6));
        GradientDrawable pressed = new GradientDrawable();
        pressed.setColor(Color.BLACK);
        pressed.setStroke(dp(2), Color.BLACK);
        pressed.setCornerRadius(dp(6));
        StateListDrawable s = new StateListDrawable();
        s.addState(new int[] { android.R.attr.state_pressed }, pressed);
        s.addState(new int[] { android.R.attr.state_selected }, pressed);
        s.addState(new int[] {}, normal);
        return s;
    }

    private TextView key(String label, float weight, View.OnClickListener l) {
        TextView t = text(label, 24, false);
        t.setGravity(Gravity.CENTER);
        t.setBackground(keyBackground());
        t.setTextColor(new android.content.res.ColorStateList(
            new int[][] { { android.R.attr.state_pressed }, { android.R.attr.state_selected }, {} },
            new int[] { Color.WHITE, Color.WHITE, Color.BLACK }));
        t.setClickable(true);
        t.setFocusable(false);
        t.setSoundEffectsEnabled(false);
        t.setOnClickListener(l);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, weight);
        lp.setMargins(dp(3), dp(2), dp(3), dp(2));
        t.setLayoutParams(lp);
        return t;
    }

    @Override public View onCreateInputView() {
        root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(dp(6), dp(2), dp(6), dp(4));

        // Fixed height: the candidate bar must not make the keyboard jump under the finger when the first
        // pinyin letter turns into candidates.  The whole IME occupies about 44% of the panel.
        int total = (int) (getResources().getDisplayMetrics().heightPixels * 0.44f);
        int topH = dp(26), candH = dp(44);
        int kbH = Math.max(dp(280), total - topH - candH);
        rowH = kbH / 4;
        root.setLayoutParams(new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, total));

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(dp(8), 0, dp(8), 0);
        composing = text("", 18, true);
        composing.setSingleLine(true);
        top.addView(composing, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        TextView hint = text("中文/English", 12, false);
        hint.setTextColor(Color.GRAY);
        top.addView(hint);
        root.addView(top, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, topH));

        candidateScroll = new HorizontalScrollView(this);
        candidateScroll.setHorizontalScrollBarEnabled(false);
        candidateScroll.setFillViewport(false);
        candidatesRow = new LinearLayout(this);
        candidatesRow.setOrientation(LinearLayout.HORIZONTAL);
        candidatesRow.setGravity(Gravity.CENTER_VERTICAL);
        candidatesRow.setPadding(dp(4), 0, dp(4), 0);
        candidateScroll.addView(candidatesRow, new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT));
        root.addView(candidateScroll, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, candH));

        keyboard = new LinearLayout(this);
        keyboard.setOrientation(LinearLayout.VERTICAL);
        root.addView(keyboard, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, kbH));

        buildKeyboard();
        updateCandidates();
        return root;
    }

    @Override public void onStartInput(EditorInfo info, boolean restarting) {
        super.onStartInput(info, restarting);
        pinyin.setLength(0);
        selecting = false; selAnchor = -1;
        // 变体是枚举值，不是位：以前按位与 PASSWORD(0x80)，网页输入框(0xa0)、搜索过滤框(0xb0)也被当成密码框切成英文，
        // 而且之后所有普通输入框都一直是英文。现在密码 / 网址 / 邮箱框临时用英文，别的框回到用户自己选的模式。
        chinese = userChinese;
        if (info != null) {
            int cls = info.inputType & InputType.TYPE_MASK_CLASS;
            int var = info.inputType & InputType.TYPE_MASK_VARIATION;
            boolean text = cls == InputType.TYPE_CLASS_TEXT;
            boolean password = text && (var == InputType.TYPE_TEXT_VARIATION_PASSWORD
                || var == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD
                || var == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD);
            if (password) chinese = false;
            numeric = cls == InputType.TYPE_CLASS_NUMBER;
            symbols = text && (var == InputType.TYPE_TEXT_VARIATION_URI
                || var == InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                || var == InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS);
            if (symbols) { chinese = false; numeric = false; }
        }
        if (root != null) {
            buildKeyboard();
            updateKeyLabels();
            updateCandidates();
        }
    }

    /** Keyboard hidden: the next time it comes up it shows the letters again -- except when the user only moved
     *  to another field of the same app (the keyboard hides and comes back within a moment): the edit panel
     *  stays, so copy in one field and paste in the next works without reopening it. */
    @Override public void onFinishInputView(boolean finishingInput) {
        super.onFinishInputView(finishingInput);
        if (editMode) {
            EditorInfo ei = getCurrentInputEditorInfo();
            editHiddenAt = SystemClock.uptimeMillis();
            editHiddenPkg = ei != null ? ei.packageName : null;
            editMode = false;
            if (root != null) { buildKeyboard(); updateCandidates(); }
        }
    }

    /**
     * Keyboard window gone: what was under it comes back as one big change. In 均衡 the display bridge sends a change of
     * less than KFB_REAGL_MIN (35 %) of the screen as DU (1-bit, does not clean), so the keys stayed on the panel as a
     * ghost. A one-shot hint to the bridge (display/epd.c HINT, the same one the pull-down panel uses): for the next
     * 2.5 s (the app relayouts in several frames), changes of at least 5 % of the screen go out as REAGL (16 grays, cleans ghosts, no flash). Non-blocking:
     * no bridge reading the FIFO = dropped.
     */
    @Override public void onWindowHidden() {
        super.onWindowHidden();
        toBridge("HINT 2500 5\n");
    }

    /**
     * Keyboard window coming up: the app relayouts above it and the keyboard covers the bottom half - a large change
     * that is not a page turn. NOFLIP (display/epd.c page_like) keeps it out of the bridge's KFB_FLASH page count, so
     * a reader app with a page-count flash does not end a few keyboard openings in a full black flash (0.96 report).
     * A bridge that does not know NOFLIP ignores the line.
     */
    @Override public void onWindowShown() {
        super.onWindowShown();
        toBridge("NOFLIP 2500\n");
    }

    private static void toBridge(String line) {
        java.io.FileDescriptor fd = null;
        try {
            fd = android.system.Os.open("/dev/kfb/epd.fifo", android.system.OsConstants.O_WRONLY | android.system.OsConstants.O_NONBLOCK, 0);
            byte[] b = line.getBytes();
            android.system.Os.write(fd, b, 0, b.length);
        } catch (Throwable ignored) {
        } finally {
            if (fd != null) try { android.system.Os.close(fd); } catch (Throwable ignored) { }
        }
    }

    @Override public void onStartInputView(EditorInfo info, boolean restarting) {
        super.onStartInputView(info, restarting);
        boolean back = editHiddenAt > 0 && SystemClock.uptimeMillis() - editHiddenAt < 2000
            && info != null && editHiddenPkg != null && editHiddenPkg.equals(info.packageName);
        editHiddenAt = 0;
        if (back && !editMode && root != null) {
            editMode = true;
            buildKeyboard();
            updateCandidates();
        }
    }

    @Override public void onFinishInput() {
        pinyin.setLength(0);
        super.onFinishInput();
    }

    @Override public boolean onEvaluateFullscreenMode() {
        return false;
    }

    // ------------------------------------------------------------------ dictionary

    private void loadDictionary() {
        BufferedReader r = null;
        try {
            r = new BufferedReader(new InputStreamReader(getAssets().open("pinyin.tsv"), "UTF-8"));
            String line;
            while ((line = r.readLine()) != null) {
                if (line.length() == 0 || line.charAt(0) == '#') continue;
                int a = line.indexOf('\t');
                int b = line.indexOf('\t', a + 1);
                if (a < 0 || b < 0) continue;
                String type = line.substring(0, a);
                String key = line.substring(a + 1, b);
                String val = line.substring(b + 1);
                if ("C".equals(type)) {
                    charMap.put(key, val);
                    charKeys.add(key);
                } else if ("W".equals(type)) {
                    wordMap.put(key, val);
                }
            }
        } catch (Throwable ignored) {
        } finally {
            if (r != null) try { r.close(); } catch (Exception ignored) { }
        }
        Collections.sort(charKeys);
    }

    // ------------------------------------------------------------------ candidates

    private void addCandidate(String s) {
        if (s == null || s.length() == 0 || candidates.contains(s)) return;
        candidates.add(s);
    }

    private void updateCandidates() {
        if (candidatesRow == null || composing == null) return;
        candidatesRow.removeAllViews();
        candidates.clear();
        if (editMode) {
            composing.setText(selecting ? "编辑 · 选择中：用方向键扩大选区" : "编辑");
            return;
        }
        if (!chinese) {
            composing.setText("English");
            return;
        }
        String key = pinyin.toString();
        composing.setText(key.length() == 0 ? "拼音输入" : key);
        if (key.length() == 0) {
            return;
        }

        String words = wordMap.get(key);
        if (words != null) for (String w : words.split("\\|")) addCandidate(w);
        String chars = charMap.get(key);
        if (chars != null) for (int i = 0; i < chars.length(); i++) addCandidate(String.valueOf(chars.charAt(i)));

        // partial syllable: show common characters whose pinyin starts with what has been typed.
        if (candidates.isEmpty()) {
            for (String k : charKeys) {
                if (!k.startsWith(key)) continue;
                String v = charMap.get(k);
                if (v != null) for (int i = 0; i < v.length() && i < 2; i++) addCandidate(String.valueOf(v.charAt(i)));
                if (candidates.size() >= 12) break;
            }
        }

        for (int i = 0; i < candidates.size() && i < 16; i++) {
            final String c = candidates.get(i);
            TextView t = text(c, 24, false);
            t.setGravity(Gravity.CENTER);
            t.setPadding(dp(12), 0, dp(12), 0);
            t.setBackground(keyBackground());
            t.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { commit(c); }
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.MATCH_PARENT);
            lp.setMargins(dp(2), dp(2), dp(2), dp(2));
            candidatesRow.addView(t, lp);
        }
    }

    // ------------------------------------------------------------------ keyboard

    private void buildKeyboard() {
        keyboard.removeAllViews();
        letterKeys.clear();
        selectKey = null;

        if (editMode) { buildEditPanel(); return; }
        if (symbols) { buildSymbolKeyboard(); return; }
        if (numeric) {
            buildNumericKeyboard();
            return;
        }

        LinearLayout row1 = row();
        for (char c : "qwertyuiop".toCharArray()) addLetter(row1, c);
        keyboard.addView(row1, rowParams());

        LinearLayout row2 = row();
        for (char c : "asdfghjkl".toCharArray()) addLetter(row2, c);
        keyboard.addView(row2, rowParams());

        LinearLayout row3 = row();
        shiftKey = key("Shift", 1.5f, new View.OnClickListener() {
            @Override public void onClick(View v) { shift = !shift; updateKeyLabels(); }
        });
        shiftKey.setTextSize(16);
        row3.addView(shiftKey);
        for (char c : "zxcvbnm".toCharArray()) addLetter(row3, c);
        TextView back = key("退格", 1.5f, new View.OnClickListener() {
            @Override public void onClick(View v) { backspace(); }
        });
        back.setTextSize(16);
        row3.addView(back);
        keyboard.addView(row3, rowParams());

        LinearLayout row4 = row();
        modeKey = key("中", 1.4f, new View.OnClickListener() {
            @Override public void onClick(View v) { chinese = !chinese; userChinese = chinese; pinyin.setLength(0); updateKeyLabels(); updateCandidates(); }
        });
        row4.addView(modeKey);
        row4.addView(key("，", 1f, new View.OnClickListener() { @Override public void onClick(View v) { punct("，"); } }));
        spaceKey = key("空格", 2.6f, new View.OnClickListener() { @Override public void onClick(View v) { space(); } });
        row4.addView(spaceKey);
        row4.addView(key("。", 1f, new View.OnClickListener() { @Override public void onClick(View v) { punct("。"); } }));
        TextView num = key("123", 1.2f, new View.OnClickListener() {
            @Override public void onClick(View v) { numeric = true; symbols = false; buildKeyboard(); }
        });
        num.setOnLongClickListener(new View.OnLongClickListener() {
            @Override public boolean onLongClick(View v) { symbols = true; numeric = false; buildKeyboard(); return true; }
        });
        row4.addView(num);
        row4.addView(editKey());
        row4.addView(key("回车", 1.6f, new View.OnClickListener() { @Override public void onClick(View v) { enter(); } }));
        keyboard.addView(row4, rowParams());

        updateKeyLabels();
    }

    /** Numeric page: big keys for 6-digit binding codes, Wi-Fi passwords and amounts. */
    private void buildNumericKeyboard() {
        LinearLayout r1 = row();
        for (char c : "123".toCharArray()) addDigit(r1, c);
        keyboard.addView(r1, rowParams());
        LinearLayout r2 = row();
        for (char c : "456".toCharArray()) addDigit(r2, c);
        keyboard.addView(r2, rowParams());
        LinearLayout r3 = row();
        for (char c : "789".toCharArray()) addDigit(r3, c);
        keyboard.addView(r3, rowParams());
        LinearLayout r4 = row();
        TextView abc = key("ABC", 1.4f, new View.OnClickListener() {
            @Override public void onClick(View v) { numeric = false; buildKeyboard(); }
        });
        abc.setTextSize(16);
        r4.addView(abc);
        addDigit(r4, '0');
        TextView back = key("退格", 1.5f, new View.OnClickListener() {
            @Override public void onClick(View v) { backspace(); }
        });
        back.setTextSize(16);
        r4.addView(back);
        r4.addView(key("符", 1.2f, new View.OnClickListener() {
            @Override public void onClick(View v) { symbols = true; numeric = false; buildKeyboard(); }
        }));
        r4.addView(editKey());
        r4.addView(key("回车", 1.6f, new View.OnClickListener() { @Override public void onClick(View v) { enter(); } }));
        keyboard.addView(r4, rowParams());
        if (composing != null) composing.setText("数字");
    }

    /** URL / symbol page: . / : ? = & % and the rest of what a book-source URL needs. */
    private void buildSymbolKeyboard() {
        LinearLayout r1 = row();
        for (char c : "1234567890".toCharArray()) addSymbol(r1, String.valueOf(c));
        keyboard.addView(r1, rowParams());
        LinearLayout r2 = row();
        for (String s : new String[] { "-", "/", ":", ";", "(", ")", "$", "&", "@" }) addSymbol(r2, s);
        keyboard.addView(r2, rowParams());
        LinearLayout r3 = row();
        for (String s : new String[] { ".", ",", "?", "!", "'", "\"", "_", "+", "=", "%", "#" }) addSymbol(r3, s);
        keyboard.addView(r3, rowParams());
        LinearLayout r4 = row();
        r4.addView(key("ABC", 1.4f, new View.OnClickListener() {
            @Override public void onClick(View v) { symbols = false; numeric = false; buildKeyboard(); }
        }));
        r4.addView(key("空格", 2.0f, new View.OnClickListener() {
            @Override public void onClick(View v) { space(); }
        }));
        r4.addView(editKey());
        r4.addView(key("退格", 1.5f, new View.OnClickListener() {
            @Override public void onClick(View v) { backspace(); }
        }));
        r4.addView(key("回车", 1.6f, new View.OnClickListener() {
            @Override public void onClick(View v) { enter(); }
        }));
        keyboard.addView(r4, rowParams());
        if (composing != null) composing.setText("符号 / 网址");
    }


    /** The one key that opens the edit panel; it is on every keyboard page. */
    private TextView editKey() {
        TextView k = key("编辑", 1.2f, new View.OnClickListener() {
            @Override public void onClick(View v) { openEdit(true); }
        });
        k.setTextSize(18);
        return k;
    }

    private void openEdit(boolean on) {
        pinyin.setLength(0);            // unfinished pinyin is dropped, never left half-typed under the panel
        InputConnection c = ic();
        if (c != null) c.finishComposingText();
        editMode = on;
        selecting = false;
        selAnchor = -1;
        buildKeyboard();
        updateCandidates();
    }

    private TextView editButton(LinearLayout row, String label, float weight, View.OnClickListener l) {
        TextView k = key(label, weight, l);
        k.setTextSize(22);
        row.addView(k);
        return k;
    }

    /**
     * Edit panel, same 4-row height as the letters so nothing moves on the panel:
     *   全选 复制 剪切 粘贴 / 选择 行首 上移 行尾 / 撤销 左移 下移 右移 / 返回键盘 退格 回车
 *   (the system font has no arrow glyphs, so the labels are words)
     * Each tap is one local e-ink refresh; nothing animates.
     */
    private void buildEditPanel() {
        LinearLayout r1 = row();
        editButton(r1, "全选", 1f, new View.OnClickListener() { @Override public void onClick(View v) { selectAll(); } });
        editButton(r1, "复制", 1f, new View.OnClickListener() { @Override public void onClick(View v) { copy(false); } });
        editButton(r1, "剪切", 1f, new View.OnClickListener() { @Override public void onClick(View v) { copy(true); } });
        editButton(r1, "粘贴", 1f, new View.OnClickListener() { @Override public void onClick(View v) { paste(); } });
        keyboard.addView(r1, rowParams());

        LinearLayout r2 = row();
        selectKey = editButton(r2, "选择", 1.3f, new View.OnClickListener() { @Override public void onClick(View v) { toggleSelect(); } });
        selectKey.setSelected(selecting);
        editButton(r2, "行首", 1f, new View.OnClickListener() { @Override public void onClick(View v) { moveLine(false); } });
        editButton(r2, "上移", 1f, new View.OnClickListener() { @Override public void onClick(View v) { arrow(KeyEvent.KEYCODE_DPAD_UP); } });
        editButton(r2, "行尾", 1f, new View.OnClickListener() { @Override public void onClick(View v) { moveLine(true); } });
        keyboard.addView(r2, rowParams());

        LinearLayout r3 = row();
        editButton(r3, "撤销", 1.3f, new View.OnClickListener() { @Override public void onClick(View v) { undo(); } });
        editButton(r3, "左移", 1f, new View.OnClickListener() { @Override public void onClick(View v) { moveChar(-1); } });
        editButton(r3, "下移", 1f, new View.OnClickListener() { @Override public void onClick(View v) { arrow(KeyEvent.KEYCODE_DPAD_DOWN); } });
        editButton(r3, "右移", 1f, new View.OnClickListener() { @Override public void onClick(View v) { moveChar(1); } });
        keyboard.addView(r3, rowParams());

        LinearLayout r4 = row();
        editButton(r4, "返回键盘", 2f, new View.OnClickListener() { @Override public void onClick(View v) { openEdit(false); } });
        editButton(r4, "退格", 1.1f, new View.OnClickListener() { @Override public void onClick(View v) { backspace(); } });
        editButton(r4, "回车", 1.2f, new View.OnClickListener() { @Override public void onClick(View v) { enter(); } });
        keyboard.addView(r4, rowParams());
    }

    private void status(String s) {
        Log.i(TAG, "edit: " + s);
        if (composing != null) composing.setText(s);
    }

    private ExtractedText extracted() {
        InputConnection c = ic();
        if (c == null) return null;
        try {
            ExtractedText et = c.getExtractedText(new ExtractedTextRequest(), 0);
            return (et != null && et.text != null && et.selectionStart >= 0) ? et : null;
        } catch (Throwable t) { return null; }
    }

    private ClipboardManager clipboard() {
        return (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
    }

    private void selectAll() {
        InputConnection c = ic();
        if (c == null) return;
        selecting = false; selAnchor = -1;
        if (selectKey != null) selectKey.setSelected(false);
        if (!c.performContextMenuAction(android.R.id.selectAll)) {
            ExtractedText et = extracted();
            if (et != null) c.setSelection(et.startOffset, et.startOffset + et.text.length());
            else { c.sendKeyEvent(keyEv(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_A, KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON));
                   c.sendKeyEvent(keyEv(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_A, KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON)); }
        }
        status("已全选");
    }

    /** Copy (or cut) the selection.  We put the text on the clipboard ourselves when the app tells us what is
     *  selected; only apps that do not (getSelectedText == null) get the context-menu action. */
    private void copy(boolean cut) {
        InputConnection c = ic();
        if (c == null) return;
        CharSequence sel = null;
        try { sel = c.getSelectedText(0); } catch (Throwable ignored) { }
        if (sel == null) {
            ExtractedText et = extracted();
            if (et != null && et.selectionStart == et.selectionEnd) sel = "";   // the app reports no selection
        }
        if (sel != null && sel.length() > 0) {
            try {
                lastCopied = sel.toString();
                clipboard().setPrimaryClip(ClipData.newPlainText("VeraIME", lastCopied));
            } catch (Throwable t) {
                c.performContextMenuAction(cut ? android.R.id.cut : android.R.id.copy);
            }
            if (cut) c.commitText("", 1);
            status((cut ? "已剪切 " : "已复制 ") + sel.length() + " 字");
        } else if (sel == null && c.performContextMenuAction(cut ? android.R.id.cut : android.R.id.copy)) {
            status(cut ? "已剪切" : "已复制");
        } else {
            status("请先选中文字（全选，或 选择 + 方向键）");
            return;
        }
        selecting = false; selAnchor = -1;
        if (selectKey != null) selectKey.setSelected(false);
    }

    /** Paste the clipboard as plain text (works the same in every app, also when another app filled the
     *  clipboard); non-text clips are left to the app's own paste action. */
    private void paste() {
        InputConnection c = ic();
        if (c == null) return;
        CharSequence text = null;
        try {
            ClipboardManager cm = clipboard();
            ClipData clip = cm.getPrimaryClip();
            if (clip != null && clip.getItemCount() > 0) {
                StringBuilder b = new StringBuilder();
                for (int i = 0; i < clip.getItemCount(); i++) {
                    CharSequence t = clip.getItemAt(i).coerceToText(this);
                    if (t != null) { if (b.length() > 0) b.append('\n'); b.append(t); }
                }
                text = b;
            }
        } catch (Throwable ignored) { }
        if ((text == null || text.length() == 0) && lastCopied != null) {
            Log.w(TAG, "clipboard unreadable, pasting the IME's own last copy");
            text = lastCopied;
        }
        if (text != null && text.length() > 0) {
            c.commitText(text.toString(), 1);
            status("已粘贴 " + text.length() + " 字");
        } else if (c.performContextMenuAction(android.R.id.paste)) {
            status("已粘贴");
        } else {
            status("剪贴板是空的");
        }
        selecting = false; selAnchor = -1;
        if (selectKey != null) selectKey.setSelected(false);
    }

    private void undo() {
        InputConnection c = ic();
        if (c == null) return;
        // TextView, WebView and most editors take Ctrl+Z as a key shortcut.
        int meta = KeyEvent.META_CTRL_ON | KeyEvent.META_CTRL_LEFT_ON;
        c.sendKeyEvent(keyEv(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_Z, meta));
        c.sendKeyEvent(keyEv(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_Z, meta));
        status("撤销");
    }

    private void toggleSelect() {
        selecting = !selecting;
        selAnchor = -1;
        if (selecting) {
            ExtractedText et = extracted();
            if (et != null) selAnchor = et.startOffset + Math.min(et.selectionStart, et.selectionEnd);
        }
        if (selectKey != null) selectKey.setSelected(selecting);
        status(selecting ? "编辑 · 选择中：用方向键扩大选区" : "编辑");
    }

    private KeyEvent keyEv(int action, int code, int meta) {
        long t = SystemClock.uptimeMillis();
        return new KeyEvent(t, t, action, code, 0, meta, android.view.KeyCharacterMap.VIRTUAL_KEYBOARD, 0,
            KeyEvent.FLAG_SOFT_KEYBOARD | KeyEvent.FLAG_KEEP_TOUCH_MODE);
    }

    /** Arrow key as a key event (shift held while selecting): used for up/down and when the app gives no text. */
    private void arrow(int code) {
        InputConnection c = ic();
        if (c == null) return;
        int meta = selecting ? (KeyEvent.META_SHIFT_ON | KeyEvent.META_SHIFT_LEFT_ON) : 0;
        c.sendKeyEvent(keyEv(KeyEvent.ACTION_DOWN, code, meta));
        c.sendKeyEvent(keyEv(KeyEvent.ACTION_UP, code, meta));
        // the key may have moved the selection; re-read the anchor next time
        if (selecting && selAnchor < 0) {
            ExtractedText et = extracted();
            if (et != null) selAnchor = et.startOffset + Math.min(et.selectionStart, et.selectionEnd);
        }
    }

    /** Current cursor (the moving end of the selection), absolute offset. */
    private int cursorOf(ExtractedText et) {
        int a = et.startOffset + et.selectionStart, b = et.startOffset + et.selectionEnd;
        if (selecting && selAnchor >= 0) return a == selAnchor ? b : a;
        return b;
    }

    private void placeCursor(InputConnection c, ExtractedText et, int pos) {
        int len = et.startOffset + et.text.length();
        pos = Math.max(0, Math.min(len, pos));
        if (selecting) {
            if (selAnchor < 0) selAnchor = et.startOffset + Math.min(et.selectionStart, et.selectionEnd);
            c.setSelection(selAnchor, pos);
        } else {
            c.setSelection(pos, pos);
        }
    }

    private void moveChar(int dir) {
        InputConnection c = ic();
        if (c == null) return;
        ExtractedText et = extracted();
        if (et == null) { arrow(dir < 0 ? KeyEvent.KEYCODE_DPAD_LEFT : KeyEvent.KEYCODE_DPAD_RIGHT); return; }
        CharSequence t = et.text;
        int a = et.startOffset + Math.min(et.selectionStart, et.selectionEnd);
        int b = et.startOffset + Math.max(et.selectionStart, et.selectionEnd);
        int pos;
        if (!selecting && a != b) {
            pos = dir < 0 ? a : b;          // collapse a selection to its edge, like a hardware keyboard
        } else {
            pos = cursorOf(et);
            int i = pos - et.startOffset;
            if (dir < 0 && i > 0) i -= (i >= 2 && Character.isLowSurrogate(t.charAt(i - 1)) && Character.isHighSurrogate(t.charAt(i - 2))) ? 2 : 1;
            else if (dir > 0 && i < t.length()) i += (i + 1 < t.length() && Character.isHighSurrogate(t.charAt(i)) && Character.isLowSurrogate(t.charAt(i + 1))) ? 2 : 1;
            pos = et.startOffset + i;
        }
        placeCursor(c, et, pos);
    }

    private void moveLine(boolean end) {
        InputConnection c = ic();
        if (c == null) return;
        ExtractedText et = extracted();
        if (et == null) { arrow(end ? KeyEvent.KEYCODE_MOVE_END : KeyEvent.KEYCODE_MOVE_HOME); return; }
        CharSequence t = et.text;
        int i = cursorOf(et) - et.startOffset;
        i = Math.max(0, Math.min(t.length(), i));
        String s = t.toString();
        int pos;
        if (end) { int n = s.indexOf('\n', i); pos = n < 0 ? s.length() : n; }
        else pos = i == 0 ? 0 : s.lastIndexOf('\n', i - 1) + 1;
        placeCursor(c, et, et.startOffset + pos);
    }

    private void addSymbol(LinearLayout row, final String s) {
        TextView b = key(s, 1f, new View.OnClickListener() {
            @Override public void onClick(View v) {
                InputConnection ic = ic();
                if (ic != null) ic.commitText(s, 1);
            }
        });
        b.setTextSize(24);
        row.addView(b);
    }

    private void addDigit(LinearLayout row, final char c) {
        TextView b = key(String.valueOf(c), 1f, new View.OnClickListener() {
            @Override public void onClick(View v) {
                InputConnection ic = ic(); if (ic != null) ic.commitText(String.valueOf(c), 1);
            }
        });
        b.setTextSize(30);
        row.addView(b);
    }

    private LinearLayout row() {
        LinearLayout r = new LinearLayout(this);
        r.setOrientation(LinearLayout.HORIZONTAL);
        r.setGravity(Gravity.CENTER);
        return r;
    }

    private LinearLayout.LayoutParams rowParams() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, rowH);
    }

    private void addLetter(LinearLayout row, final char c) {
        final TextView b = key(String.valueOf(c), 1f, new View.OnClickListener() {
            @Override public void onClick(View v) { letter(c); }
        });
        letterKeys.add(b);
        row.addView(b);
    }

    private void updateKeyLabels() {
        if (numeric) return;
        if (modeKey != null) modeKey.setText(chinese ? "中" : "EN");
        if (spaceKey != null) spaceKey.setText(chinese ? "空格" : "space");
        if (shiftKey != null) shiftKey.setText(shift ? "shift" : "Shift");
        for (TextView b : letterKeys) {
            String s = String.valueOf(b.getText());
            if (s.length() == 1) {
                char c = s.charAt(0);
                b.setText(String.valueOf(shift ? Character.toUpperCase(c) : Character.toLowerCase(c)));
            }
        }
    }

    // ------------------------------------------------------------------ editing

    private InputConnection ic() { return getCurrentInputConnection(); }

    private void commit(String s) {
        InputConnection c = ic();
        if (c != null) c.commitText(s, 1);
        pinyin.setLength(0);
        updateCandidates();
    }

    private void letter(char c) {
        if (!chinese) {
            String s = String.valueOf(shift ? Character.toUpperCase(c) : Character.toLowerCase(c));
            commit(s);
            if (shift) { shift = false; updateKeyLabels(); }
        } else {
            pinyin.append(Character.toLowerCase(c));
            updateCandidates();
        }
    }

    private void backspace() {
        if (chinese && pinyin.length() > 0) {
            pinyin.deleteCharAt(pinyin.length() - 1);
            updateCandidates();
            return;
        }
        InputConnection c = ic();
        if (c == null) return;
        // 选中了文字（全选 / 选择 + 方向键）：退格删掉选中的部分。deleteSurroundingText 只删选区前面的一个字
        CharSequence sel = c.getSelectedText(0);
        if (sel != null && sel.length() > 0) c.commitText("", 1);
        else c.deleteSurroundingText(1, 0);
    }

    private void space() {
        if (chinese) {
            if (!candidates.isEmpty()) { commit(candidates.get(0)); return; }
            if (pinyin.length() > 0) { commit(pinyin.toString()); return; }
            commit(" ");
        } else {
            commit(" ");
        }
    }

    private void punct(String s) {
        if (chinese && pinyin.length() > 0) { commit(candidates.isEmpty() ? pinyin.toString() : candidates.get(0)); return; }
        commit(s);
    }

    private void enter() {
        if (chinese && (!candidates.isEmpty() || pinyin.length() > 0)) {
            commit(candidates.isEmpty() ? pinyin.toString() : candidates.get(0));
            return;
        }
        if (!sendDefaultEditorAction(true)) {
            InputConnection c = ic();
            if (c != null) c.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN, KeyEvent.KEYCODE_ENTER));
            if (c != null) c.sendKeyEvent(new KeyEvent(KeyEvent.ACTION_UP, KeyEvent.KEYCODE_ENTER));
        }
    }
}
