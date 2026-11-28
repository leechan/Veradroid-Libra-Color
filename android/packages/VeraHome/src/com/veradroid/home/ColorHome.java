// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.SharedPreferences;
import android.content.pm.ResolveInfo;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.RectF;
import android.text.SpannableString;
import android.text.Spanned;
import android.text.TextUtils;
import android.text.style.ForegroundColorSpan;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.Calendar;
import java.util.List;

/**
 * The "色彩" home: the app launcher. No local library, no reading cards — every
 * installed app is on the home grid, sorted by the user's app-sort preference.
 *
 * The header keeps the mascot, greeting, full date and status cluster; below it a
 * four-column grid of app icons (paginated, swipe or the pager). Colour comes from
 * the app icons and the small accents, so text stays black on paper.
 */
final class ColorHome {
    private final HomeActivity a;
    private final BlocksHome h;
    private final SharedPreferences p;

    private TextView clockView, batView, greetView;
    private String greetPlain = "";
    private Icons.IconView wifiView;
    private Battery battery;

    private PagedBox grid;
    private Blocks.Pager pager;
    private int page, perPage;
    private static final int COLS = 3;
    private static final int CELL_DP = 172;

    ColorHome(BlocksHome home) {
        h = home;
        a = home.a;
        p = home.prefs;
    }

    private int dp(int v) { return Ui.dp(a, v); }
    private static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    private static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    View build() {
        LinearLayout root = new LinearLayout(a);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackground(Palette.homeBg(a));

        LinearLayout body = new LinearLayout(a);
        body.setOrientation(LinearLayout.VERTICAL);
        body.setPadding(dp(18), dp(8), dp(18), dp(90));
        root.addView(body, new LinearLayout.LayoutParams(MATCH, 0, 1));

        body.addView(header(), new LinearLayout.LayoutParams(MATCH, WRAP));

        grid = new PagedBox(a);
        grid.setOrientation(LinearLayout.VERTICAL);
        grid.setPadding(0, dp(10), 0, dp(4));
        grid.setListener(new PagedBox.Listener() {
            @Override public void onPage(int dir) { turn(dir); }
        });
        body.addView(grid, new LinearLayout.LayoutParams(MATCH, 0, 1));

        pager = new Blocks.Pager(a, new Blocks.Pager.Listener() {
            @Override public void onPage(int dir) { turn(dir); }
        });
        LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(MATCH, WRAP);
        pp.topMargin = dp(2);
        pp.bottomMargin = dp(6);
        body.addView(pager, pp);
        pager.setVisibility(View.GONE);

        grid.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            @Override public void onLayoutChange(View v, int l, int top, int r, int b, int ol, int ot, int or, int ob) {
                int rows = Math.max(1, (b - top - v.getPaddingTop() - v.getPaddingBottom()) / dp(CELL_DP));
                int np = rows * COLS;
                if (np != perPage && b - top > 0) {
                    perPage = np;
                    v.post(new Runnable() { @Override public void run() { render(); } });
                }
            }
        });
        return root;
    }

    private List<ResolveInfo> apps() {
        List<ResolveInfo> out = new java.util.ArrayList<ResolveInfo>();
        String pin = p.getString("blk_pins", "");
        java.util.HashSet<String> picked = new java.util.HashSet<String>();
        for (String s : pin.split(",")) {
            if (s.length() == 0 || !picked.add(s)) continue;
            ResolveInfo ri = a.findApp(s);
            if (ri != null) out.add(ri);
        }
        for (ResolveInfo ri : a.appList())
            if (picked.add(ri.activityInfo.packageName)) out.add(ri);
        return out;
    }

    private int pages() {
        int n = apps().size();
        return perPage <= 0 ? 1 : Math.max(1, (n + perPage - 1) / perPage);
    }

    void pageKey(int dir) { turn(dir); }

    private void turn(int dir) {
        int np = Math.max(0, Math.min(pages() - 1, page + dir));
        if (np == page) return;
        Blocks.swipe(a, dir > 0 ? Blocks.DIR_UP : Blocks.DIR_DOWN, Blocks.KIND_LIST);
        page = np;
        render();
        a.changed();
    }

    private void render() {
        if (grid == null || perPage <= 0) return;
        grid.removeAllViews();
        List<ResolveInfo> apps = apps();
        int pages = pages();
        if (page >= pages) page = pages - 1;
        int from = page * perPage, to = Math.min(apps.size(), from + perPage);
        LinearLayout row = null;
        for (int i = from; i < to; i++) {
            if ((i - from) % COLS == 0) {
                row = new LinearLayout(a);
                row.setOrientation(LinearLayout.HORIZONTAL);
                grid.addView(row, new LinearLayout.LayoutParams(MATCH, dp(CELL_DP)));
            }
            if ((i - from) % COLS != 0) {
                View gap = new View(a);
                row.addView(gap, new LinearLayout.LayoutParams(dp(14), 1));
            }
            row.addView(appCell(apps.get(i), (i - from) % COLS), new LinearLayout.LayoutParams(0, MATCH, 1));
        }
        if (row != null) {
            for (int k = (to - from) % COLS; k != 0 && k < COLS; k++) {
                View gap = new View(a);
                row.addView(gap, new LinearLayout.LayoutParams(dp(14), 1));
                row.addView(new View(a), new LinearLayout.LayoutParams(0, 1, 1));
            }
        }
        pager.set(page + 1, pages);
        pager.setVisibility(pages > 1 ? View.VISIBLE : View.GONE);
    }

    private View appCell(final ResolveInfo ri, int col) {
        LinearLayout c = new LinearLayout(a);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setGravity(Gravity.CENTER_HORIZONTAL);
        c.setPadding(0, dp(6), 0, dp(4));

        FrameLayout plate = new FrameLayout(a);
        // 应用卡：纯色描边（比之前深一点），卡片本身半透明白
        plate.setBackground(Palette.roundStroke(a, 0xEFFFFFFF, Palette.blend(Palette.BORDER, Palette.INK, 0.38f), 2, 46));
        ImageView iv = new ImageView(a);
        iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
        iv.setImageDrawable(a.iconFor(ri));
        plate.addView(iv, new FrameLayout.LayoutParams(dp(74), dp(74), Gravity.CENTER));
        c.addView(plate, new LinearLayout.LayoutParams(MATCH, dp(108)));

        TextView t = Ui.text(a, a.labelFor(ri), 15, true);
        t.setTextColor(Palette.INK);
        t.setGravity(Gravity.CENTER);
        t.setSingleLine(false);
        t.setMaxLines(2);
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setPadding(0, dp(6), 0, 0);
        c.addView(t, new LinearLayout.LayoutParams(MATCH, WRAP));

        c.setClickable(true);
        c.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { a.launch(ri); }
        });
        c.setOnLongClickListener(new View.OnLongClickListener() {
            @Override public boolean onLongClick(View v) { a.appMenu(ri); return true; }
        });
        Blocks.fast(c);
        return c;
    }

    // ------------------------------------------------------------------ header (same as before)

    private LinearLayout header() {
        LinearLayout head = new LinearLayout(a);
        head.setOrientation(LinearLayout.VERTICAL);
        head.setPadding(dp(2), dp(2), dp(2), dp(2));

        LinearLayout line = new LinearLayout(a);
        line.setGravity(Gravity.TOP);

        LinearLayout left = new LinearLayout(a);
        left.setOrientation(LinearLayout.VERTICAL);

        Calendar now = Calendar.getInstance();
        TextView date = Ui.text(a, now.get(Calendar.YEAR) + "年" + (now.get(Calendar.MONTH) + 1) + "月"
                + now.get(Calendar.DAY_OF_MONTH) + "日  星期" + BlocksCards.weekday(now), 11, false);
        date.setTextColor(Palette.MUTED);
        date.setGravity(Gravity.LEFT);
        left.addView(date, new LinearLayout.LayoutParams(MATCH, WRAP));

        String name = p.getString("name", "");
        if (name.length() == 0 || "VeraDroid".equals(name)) name = "";
        String hi = Palette.greeting() + (name.length() > 0 && name.length() <= 9 ? "，" + name : "");
        TextView greet = Ui.text(a, hi, 24, true);
        greet.setTextColor(Palette.INK);
        greet.setSingleLine(true);
        greet.setEllipsize(TextUtils.TruncateAt.END);
        greet.setPadding(0, dp(3), 0, 0);
        greetView = greet;
        greetPlain = hi;
        greet.setText(colourText(hi));
        left.addView(greet, new LinearLayout.LayoutParams(MATCH, WRAP));
        line.addView(left, new LinearLayout.LayoutParams(0, WRAP, 1));

        int[] live = Ui.liveBattery(a);
        int pct = live != null ? live[0] : 60;
        boolean chg = live != null && live[1] == 1;

        LinearLayout status = new LinearLayout(a);
        status.setGravity(Gravity.CENTER_VERTICAL);

        wifiView = new Icons.IconView(a, Icons.Kind.WIFI);
        wifiView.setColor(Palette.TEAL);
        wifiView.setVisibility(View.GONE);
        status.addView(wifiView, new LinearLayout.LayoutParams(dp(17), dp(17)));

        battery = new Battery(a, pct, chg);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(dp(28), dp(14));
        bp.leftMargin = dp(9);
        status.addView(battery, bp);

        batView = Ui.text(a, pct + "%", 11.5f, true);
        batView.setTextColor(Palette.INK);
        batView.setPadding(dp(5), 0, dp(9), 0);
        status.addView(batView, new LinearLayout.LayoutParams(WRAP, WRAP));

        clockView = Ui.text(a, Ui.clock(a), 14, true);
        clockView.setTextColor(Palette.INK);
        status.addView(clockView, new LinearLayout.LayoutParams(WRAP, WRAP));

        line.addView(status, new LinearLayout.LayoutParams(WRAP, dp(32)));
        head.addView(line, new LinearLayout.LayoutParams(MATCH, WRAP));
        return head;
    }

    private CharSequence colourText(String s) {
        SpannableString sp = new SpannableString(s);
        int[] cols = { Palette.INDIGO, Palette.TEAL, Palette.PLUM, Palette.AMBER, Palette.GRAPE };
        int j = 0;
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch == ' ' || ch == '，' || ch == ',') continue;
            sp.setSpan(new ForegroundColorSpan(Palette.blend(cols[j++ % cols.length], Palette.INK, 0.18f)), i, i + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE);
        }
        return sp;
    }

    void refreshStatus(String clock, String bat, boolean wifi) {
        if (clockView != null && clock != null && !clock.contentEquals(clockView.getText())) clockView.setText(clock);
        int pct = parsePct(bat);
        if (batView != null) {
            String s = pct >= 0 ? pct + "%" : bat;
            if (!s.contentEquals(batView.getText())) batView.setText(s);
        }
        if (battery != null) battery.set(pct, bat != null && bat.contains("充"));
        if (wifiView != null) wifiView.setVisibility(wifi ? View.VISIBLE : View.GONE);
    }

    void tick() {
        if (greetView == null) return;
        String name = p.getString("name", "");
        if (name.length() == 0 || "VeraDroid".equals(name)) name = "";
        String hi = Palette.greeting() + (name.length() > 0 && name.length() <= 9 ? "，" + name : "");
        if (!hi.equals(greetPlain)) { greetPlain = hi; greetView.setText(colourText(hi)); }
    }

    private static int parsePct(String s) {
        if (s == null) return -1;
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            if (ch >= '0' && ch <= '9') b.append(ch);
            else if (b.length() > 0) break;
        }
        try { return b.length() == 0 ? -1 : Math.max(0, Math.min(100, Integer.parseInt(b.toString()))); }
        catch (Throwable t) { return -1; }
    }

    /** A chubby capsule battery. */
    static final class Battery extends View {
        private int pct;
        private boolean charging;
        Battery(android.content.Context c, int pct, boolean charging) {
            super(c);
            this.pct = pct;
            this.charging = charging;
        }
        void set(int pct, boolean charging) {
            if (this.pct == pct && this.charging == charging) return;
            this.pct = pct;
            this.charging = charging;
            invalidate();
        }
        @Override protected void onDraw(Canvas c) {
            int w = getWidth(), h = getHeight();
            float pad = Math.max(1f, Ui.dp(getContext(), 1));
            float rr = (h - 2 * pad) / 2f;
            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(Math.max(1.6f, Ui.dp(getContext(), 1)));
            paint.setColor(Palette.INK);
            c.drawRoundRect(new RectF(pad, pad, w - pad * 3, h - pad), rr, rr, paint);
            float nubW = Math.max(2f, w * 0.08f), nubH = h * 0.38f;
            c.drawRoundRect(new RectF(w - pad * 3, (h - nubH) / 2f, w - pad * 0.5f, (h + nubH) / 2f),
                    nubW / 2f, nubW / 2f, paint);
            int v = pct < 0 ? 60 : pct;
            int col = charging ? Palette.TEAL : v <= 15 ? Palette.PLUM : v <= 30 ? Palette.AMBER : Palette.TEAL;
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(col);
            float inset = pad + Math.max(2f, h * 0.16f);
            float inner = Math.max(0, (w - pad * 3 - inset - pad) * v / 100f);
            if (inner > 1) c.drawRoundRect(new RectF(inset, inset, inset + inner, h - inset), rr / 2f, rr / 2f, paint);
        }
    }

    /** Round little cat mascot. */
    static final class Mascot extends View {
        private final int face;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Mascot(android.content.Context c, int face) { super(c); this.face = face; }
        @Override protected void onDraw(Canvas c) {
            float w = getWidth(), h = getHeight();
            float cx = w / 2f, cy = h * 0.58f, r = Math.min(w, h) * 0.40f;
            int line = Palette.blend(face, Palette.INK, 0.42f);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(face);
            c.drawCircle(cx - r * 0.62f, cy - r * 0.72f, r * 0.32f, paint);
            c.drawCircle(cx + r * 0.62f, cy - r * 0.72f, r * 0.32f, paint);
            c.drawCircle(cx, cy, r, paint);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(Math.max(1.4f, r * 0.07f));
            paint.setColor(line);
            c.drawCircle(cx, cy, r, paint);
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(Palette.INK);
            c.drawCircle(cx - r * 0.32f, cy - r * 0.04f, r * 0.10f, paint);
            c.drawCircle(cx + r * 0.32f, cy - r * 0.04f, r * 0.10f, paint);
            paint.setColor(Palette.blend(Palette.PLUM, Palette.PAPER, 0.55f));
            c.drawCircle(cx - r * 0.56f, cy + r * 0.26f, r * 0.13f, paint);
            c.drawCircle(cx + r * 0.56f, cy + r * 0.26f, r * 0.13f, paint);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(Math.max(1.2f, r * 0.055f));
            paint.setColor(Palette.INK);
            paint.setStrokeCap(Paint.Cap.ROUND);
            android.graphics.Path mouth = new android.graphics.Path();
            mouth.moveTo(cx - r * 0.16f, cy + r * 0.24f);
            mouth.quadTo(cx, cy + r * 0.38f, cx + r * 0.16f, cy + r * 0.24f);
            c.drawPath(mouth, paint);
        }
    }
}
