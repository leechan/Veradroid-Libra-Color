// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.SharedPreferences;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Comparator;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;

/**
 * The "色彩" home: a light Bento dashboard for the Kaleido panel.
 *
 * Structure follows the reference the user picked: a small greeting header, a dark
 * continue-reading hero with two compact stat cards next to it, an "also reading"
 * list with a highlight card, a recently-added cover row and four small library
 * tiles. Most surfaces stay white with a hairline border; colour is spent on covers,
 * progress and a few meaningful accents, which keeps the panel calm and still shows
 * what the colour screen can do.
 */
final class ColorHome {
    private final HomeActivity a;
    private final BlocksHome h;
    private final SharedPreferences p;

    private TextView clockView, batView, greetView, weekView, streakView;
    private Icons.IconView wifiView;
    private Battery battery;

    ColorHome(BlocksHome home) {
        h = home;
        a = home.a;
        p = home.prefs;
    }

    private int dp(int v) { return Ui.dp(a, v); }
    private static final int MATCH = ViewGroup.LayoutParams.MATCH_PARENT;
    private static final int WRAP = ViewGroup.LayoutParams.WRAP_CONTENT;

    View build() {
        LinearLayout content = new LinearLayout(a);
        content.setOrientation(LinearLayout.VERTICAL);
        content.setBackgroundColor(Palette.BG);
        content.setPadding(dp(18), dp(8), dp(18), dp(8));

        content.addView(header(), new LinearLayout.LayoutParams(MATCH, WRAP));

        Lib.Book book = h.lastBook();
        String laPkg = p.getString("la_pkg", null);
        ResolveInfo app = laPkg == null || !BlocksCards.readers(a).contains(laPkg) ? null : a.findApp(laPkg);
        boolean appFirst = app != null && (book == null || p.getLong("la_time", 0) > book.lastRead);

        content.addView(heroRow(book, app, appFirst), gap(11));
        LinearLayout.LayoutParams qp = gap(11); qp.height = dp(82);
        content.addView(quickRow(), qp);
        LinearLayout.LayoutParams lp = gap(11); lp.height = dp(220);
        content.addView(libraryCard(), lp);
        LinearLayout.LayoutParams tp = gap(11); tp.height = dp(150);
        content.addView(todayCard(), tp);

        View v = h.paged(content);
        v.setBackgroundColor(Palette.BG);
        return v;
    }

    private LinearLayout.LayoutParams gap(int top) {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(MATCH, WRAP);
        lp.topMargin = dp(top);
        return lp;
    }

    // ------------------------------------------------------------------ header

    private LinearLayout header() {
        LinearLayout head = new LinearLayout(a);
        head.setOrientation(LinearLayout.HORIZONTAL);
        head.setGravity(Gravity.TOP);
        head.setPadding(dp(2), dp(2), dp(2), dp(2));

        FrameLayout sticker = new FrameLayout(a);
        sticker.setBackground(Palette.circle(a, Palette.SOFT_MINT));
        Mascot mascot = new Mascot(a, Palette.SOFT_PEACH);
        sticker.addView(mascot, new FrameLayout.LayoutParams(dp(32), dp(32), Gravity.CENTER));
        LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(40), dp(40));
        mp.rightMargin = dp(9);
        head.addView(sticker, mp);

        LinearLayout left = new LinearLayout(a);
        left.setOrientation(LinearLayout.VERTICAL);
        String name = p.getString("name", "");
        if (name.length() == 0 || "VeraDroid".equals(name)) name = "";
        String hi = Palette.greeting() + (name.length() > 0 && name.length() <= 9 ? "，" + name : "");
        TextView greet = Ui.text(a, hi, 24, true);
        greet.setTextColor(Palette.INK);
        greet.setSingleLine(true);
        greet.setEllipsize(TextUtils.TruncateAt.END);
        greetView = greet;
        left.addView(greet, new LinearLayout.LayoutParams(MATCH, WRAP));
        Calendar now = Calendar.getInstance();
        TextView date = Ui.text(a, (now.get(Calendar.MONTH) + 1) + "月" + now.get(Calendar.DAY_OF_MONTH)
                + "日 · 周" + BlocksCards.weekday(now), 11.5f, false);
        date.setTextColor(Palette.MUTED);
        date.setPadding(0, dp(2), 0, 0);
        left.addView(date, new LinearLayout.LayoutParams(MATCH, WRAP));
        head.addView(left, new LinearLayout.LayoutParams(0, WRAP, 1));

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
        clockView.setPadding(0, 0, dp(11), 0);
        status.addView(clockView, new LinearLayout.LayoutParams(WRAP, WRAP));

        Icons.IconView more = new Icons.IconView(a, Icons.Kind.MORE);
        more.setColor(Palette.INK);
        more.setClickable(true);
        more.setPadding(dp(4), dp(4), dp(4), dp(4));
        more.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { a.mainMenu(); }
        });
        status.addView(more, new LinearLayout.LayoutParams(dp(26), dp(26)));

        head.addView(status, new LinearLayout.LayoutParams(WRAP, dp(32)));
        return head;
    }

    /** One-minute tick: only the few changing numbers, so returning to the home never redraws the whole page. */
    void tick() {
        if (greetView != null) {
            String name = p.getString("name", "");
            if (name.length() == 0 || "VeraDroid".equals(name)) name = "";
            String hi = Palette.greeting() + (name.length() > 0 && name.length() <= 9 ? "，" + name : "");
            if (!hi.contentEquals(greetView.getText())) greetView.setText(hi);
        }
        if (streakView != null) {
            String s = String.valueOf(streak());
            if (!s.contentEquals(streakView.getText())) streakView.setText(s);
        }
        if (weekView != null) {
            String s = Stats.shortDuration(Stats.weekMs(a));
            if (!s.contentEquals(weekView.getText())) weekView.setText(s);
        }
    }

    /** Called by {@link BlocksHome#refreshStatus} with the same values as the classic status row. */
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

    private static int parsePct(String s) {
        if (s == null) return -1;
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c >= '0' && c <= '9') b.append(c);
            else if (b.length() > 0) break;
        }
        try { return b.length() == 0 ? -1 : Math.max(0, Math.min(100, Integer.parseInt(b.toString()))); }
        catch (Throwable t) { return -1; }
    }

    // ------------------------------------------------------------------ hero + stats

    private LinearLayout heroRow(Lib.Book book, ResolveInfo app, boolean appFirst) {
        LinearLayout row = new LinearLayout(a);
        row.setOrientation(LinearLayout.HORIZONTAL);

        LinearLayout.LayoutParams hp = new LinearLayout.LayoutParams(0, dp(196), 0.63f);
        row.addView(hero(book, app, appFirst), hp);

        LinearLayout right = new LinearLayout(a);
        right.setOrientation(LinearLayout.VERTICAL);
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(0, dp(196), 0.37f);
        rp.leftMargin = dp(10);
        row.addView(right, rp);
        right.addView(streakCard(), new LinearLayout.LayoutParams(MATCH, dp(93)));
        LinearLayout.LayoutParams wp = new LinearLayout.LayoutParams(MATCH, dp(93));
        wp.topMargin = dp(10);
        right.addView(weekCard(), wp);
        return row;
    }

    private View hero(Lib.Book book, ResolveInfo app, boolean appFirst) {
        LinearLayout card = new LinearLayout(a);
        card.setOrientation(LinearLayout.HORIZONTAL);
        card.setGravity(Gravity.CENTER_VERTICAL);
        card.setBackground(Palette.paper(a, Palette.CORAL, 24));
        card.setPadding(dp(15), dp(15), dp(15), dp(15));

        View cover;
        if (book == null && app == null) {
            LinearLayout empty = new LinearLayout(a);
            empty.setOrientation(LinearLayout.VERTICAL);
            TextView l = micro("START READING", Palette.CORAL);
            empty.addView(l, new LinearLayout.LayoutParams(MATCH, WRAP));
            TextView t = Ui.text(a, "书架还很空", 17, true);
            t.setTextColor(Palette.INK);
            t.setPadding(0, dp(7), 0, 0);
            empty.addView(t, new LinearLayout.LayoutParams(MATCH, WRAP));
            TextView s = Ui.text(a, "去书库挑一本，或把文件放进 Books 文件夹", 11, false);
            s.setTextColor(Palette.MUTED);
            s.setPadding(0, dp(4), 0, 0);
            empty.addView(s, new LinearLayout.LayoutParams(MATCH, WRAP));
            TextView go = pill("去书库", Palette.CORAL, Palette.PAPER);
            empty.addView(go, new LinearLayout.LayoutParams(WRAP, WRAP));
            ((LinearLayout.LayoutParams) go.getLayoutParams()).topMargin = dp(10);
            card.addView(empty, new LinearLayout.LayoutParams(MATCH, WRAP));
            card.setClickable(true);
            card.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { h.show(BlocksHome.FILES); a.changed(); }
            });
            Blocks.fast(card);
            return card;
        }

        if (appFirst) {
            Bitmap th = BlocksCards.lastAppThumb(a, p.getString("la_pkg", ""));
            if (th != null && !mostlyDark(th)) {
                ImageView iv = new ImageView(a);
                iv.setScaleType(ImageView.ScaleType.CENTER_CROP);
                iv.setImageBitmap(th);
                cover = iv;
            } else {
                ImageView iv = new ImageView(a);
                iv.setImageDrawable(a.iconFor(app));
                iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                iv.setPadding(dp(9), dp(9), dp(9), dp(9));
                cover = iv;
            }
        } else {
            Bitmap bm = Lib.cover(a, book);
            if (bm == null && Lib.coverMissing(a, book)) {
                List<Lib.Book> one = new ArrayList<Lib.Book>();
                one.add(book);
                Lib.generate(a, one);
            }
            cover = new CoverView(a, book, bm, false);
        }
        FrameLayout panel = new FrameLayout(a);
        panel.setBackground(Palette.roundStroke(a, Palette.PAPER, Palette.CORAL, 2, 18));
        panel.setPadding(dp(5), dp(5), dp(5), dp(5));
        panel.addView(cover, new FrameLayout.LayoutParams(MATCH, MATCH));
        if (appFirst) {
            LinearLayout.LayoutParams pp = new LinearLayout.LayoutParams(dp(76), dp(76));
            card.addView(panel, pp);
        } else {
            card.addView(panel, new LinearLayout.LayoutParams(dp(92), dp(124)));
        }

        LinearLayout col = new LinearLayout(a);
        col.setOrientation(LinearLayout.VERTICAL);
        col.setPadding(dp(12), 0, 0, 0);
        TextView label = micro(appFirst ? "CONTINUE USING" : "CONTINUE READING", Palette.CORAL);
        col.addView(label, new LinearLayout.LayoutParams(MATCH, WRAP));

        TextView title = Ui.text(a, appFirst ? a.labelFor(app) : book.title, 18, true);
        title.setTextColor(Palette.INK);
        title.setMaxLines(2);
        title.setEllipsize(TextUtils.TruncateAt.END);
        title.setPadding(0, dp(6), 0, 0);
        col.addView(title, new LinearLayout.LayoutParams(MATCH, WRAP));

        String meta;
        int pct = 0;
        if (appFirst) {
            meta = "上次使用 " + BlocksCards.ago(p.getLong("la_time", 0));
        } else {
            String ch = Store.prefs(a, "reader").getString("ch:" + book.path, "");
            pct = Math.max(0, Math.min(100, book.percent));
            meta = (book.author != null && book.author.length() > 0 ? book.author : (ch.length() > 0 ? ch : book.ext()));
            meta = (ch.length() > 0 ? ch : meta);
        }
        TextView mt = Ui.text(a, meta, 11.5f, false);
        mt.setTextColor(Palette.MUTED);
        mt.setSingleLine(true);
        mt.setEllipsize(TextUtils.TruncateAt.END);
        mt.setPadding(0, dp(4), 0, 0);
        col.addView(mt, new LinearLayout.LayoutParams(MATCH, WRAP));

        col.addView(new View(a), new LinearLayout.LayoutParams(1, 0, 1));

        LinearLayout foot = new LinearLayout(a);
        foot.setGravity(Gravity.CENTER_VERTICAL);
        if (!appFirst) {
            LinearLayout prog = new LinearLayout(a);
            prog.setOrientation(LinearLayout.VERTICAL);
            TextView pt = Ui.text(a, pct + "%" + (book.percent > 0 && book.percent < 100 ? " · 继续" : ""), 9.5f, false);
            pt.setTextColor(Palette.MUTED);
            prog.addView(pt, new LinearLayout.LayoutParams(MATCH, WRAP));
            Bar bar = new Bar(a, pct, Palette.CORAL, Palette.blend(Palette.CORAL, Palette.PAPER, 0.80f));
            LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(MATCH, dp(4));
            bp.topMargin = dp(4);
            prog.addView(bar, bp);
            foot.addView(prog, new LinearLayout.LayoutParams(0, WRAP, 1));
        } else {
            foot.addView(new View(a), new LinearLayout.LayoutParams(0, 1, 1));
        }
        TextView go = pill(appFirst ? "打开" : "恢复", Palette.CORAL, Palette.PAPER);
        LinearLayout.LayoutParams gp = new LinearLayout.LayoutParams(WRAP, WRAP);
        gp.leftMargin = dp(10);
        foot.addView(go, gp);
        col.addView(foot, new LinearLayout.LayoutParams(MATCH, WRAP));

        card.addView(col, new LinearLayout.LayoutParams(0, dp(120), 1));
        card.setClickable(true);
        final Lib.Book fb = book;
        final ResolveInfo fa = app;
        card.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (appFirst) h.openApp(fa); else h.openBook(fb);
            }
        });
        if (!appFirst && book != null) {
            card.setOnLongClickListener(new View.OnLongClickListener() {
                @Override public boolean onLongClick(View v) { a.bookMenu(fb); return true; }
            });
        }
        Blocks.fast(card);
        return card;
    }

    private String remaining(Lib.Book b) {
        // rough page-time estimate is not stored; use chapters if the reader has one
        return "—";
    }

    private TextView pill(String s, int bg, int fg) {
        TextView t = Ui.text(a, s, 10, true);
        t.setTextColor(fg);
        t.setBackground(Palette.round(a, bg, 24));
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(13), dp(6), dp(13), dp(6));
        return t;
    }

    private LinearLayout statCard(int accent) {
        LinearLayout c = new LinearLayout(a);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackground(Palette.roundStroke(a, Palette.PAPER, accent, 2, 24));
        c.setPadding(dp(13), dp(11), dp(13), dp(11));
        return c;
    }

    private View streakCard() {
        LinearLayout c = statCard(Palette.CORAL);
        c.addView(labelPill("STREAK", Palette.CORAL), new LinearLayout.LayoutParams(WRAP, WRAP));
        int n = streak();
        LinearLayout row = new LinearLayout(a);
        row.setGravity(Gravity.CENTER_VERTICAL);
        TextView v = Ui.text(a, String.valueOf(n), 22, true);
        streakView = v;
        v.setTextColor(Palette.INK);
        row.addView(v);
        TextView u = Ui.text(a, " 天", 10, false);
        u.setTextColor(Palette.MUTED);
        row.addView(u);
        row.addView(new View(a), new LinearLayout.LayoutParams(0, 1, 1));
        c.addView(row, new LinearLayout.LayoutParams(MATCH, WRAP));

        LinearLayout dots = new LinearLayout(a);
        dots.setGravity(Gravity.CENTER_VERTICAL);
        boolean[] days = readDays(7);
        for (int i = 0; i < 7; i++) {
            View d = new View(a);
            d.setBackground(Palette.circle(a, days[i] ? Palette.CORAL : Palette.BORDER));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(6), dp(6));
            if (i > 0) lp.leftMargin = dp(5);
            dots.addView(d, lp);
        }
        LinearLayout.LayoutParams dp2 = new LinearLayout.LayoutParams(MATCH, WRAP);
        dp2.topMargin = dp(6);
        c.addView(dots, dp2);
        return c;
    }

    private View weekCard() {
        LinearLayout c = statCard(Palette.TEAL);
        c.addView(labelPill("THIS WEEK", Palette.TEAL), new LinearLayout.LayoutParams(WRAP, WRAP));
        LinearLayout row = new LinearLayout(a);
        row.setGravity(Gravity.CENTER_VERTICAL);
        long ms = Stats.weekMs(a);
        String d = Stats.shortDuration(ms);
        TextView v = Ui.text(a, d, 21, true);
        weekView = v;
        v.setTextColor(Palette.INK);
        row.addView(v);
        row.addView(new View(a), new LinearLayout.LayoutParams(0, 1, 1));
        c.addView(row, new LinearLayout.LayoutParams(MATCH, WRAP));

        Bar7 bars = new Bar7(a, weekBars(), Palette.TEAL, Palette.CORAL, Palette.BORDER);
        LinearLayout.LayoutParams bp = new LinearLayout.LayoutParams(MATCH, dp(24));
        bp.topMargin = dp(5);
        c.addView(bars, bp);
        return c;
    }

    // ------------------------------------------------------------------ quick access

    private View quickRow() {
        LinearLayout row = new LinearLayout(a);
        row.setOrientation(LinearLayout.HORIZONTAL);

        ResolveInfo weread = a.findApp("com.tencent.weread.eink");
        if (weread == null) weread = a.findApp("com.tencent.weread");
        final ResolveInfo wr = weread;
        addQuick(row, "微信读书", wr != null ? a.iconFor(wr) : null, Icons.Kind.BOOK, Palette.CORAL,
                new View.OnClickListener() {
                    @Override public void onClick(View v) {
                        if (wr != null) a.launch(wr); else h.show(BlocksHome.APPS);
                    }
                }, 0);
        addQuick(row, "书库", null, Icons.Kind.BOOK, Palette.TEAL,
                new View.OnClickListener() { @Override public void onClick(View v) { h.show(BlocksHome.FILES); a.changed(); } }, 1);
        addQuick(row, "应用", null, Icons.Kind.GRID, Palette.SKY,
                new View.OnClickListener() { @Override public void onClick(View v) { h.show(BlocksHome.APPS); a.changed(); } }, 2);
        addQuick(row, "设置", null, Icons.Kind.GEAR, Palette.GRAPE,
                new View.OnClickListener() { @Override public void onClick(View v) { h.show(BlocksHome.ME); a.changed(); } }, 3);
        return row;
    }

    private void addQuick(LinearLayout row, String label, android.graphics.drawable.Drawable icon, Icons.Kind kind,
                          int accent, View.OnClickListener l, int index) {
        LinearLayout c = new LinearLayout(a);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setGravity(Gravity.CENTER);
        c.setBackground(Palette.roundStroke(a, Palette.PAPER, accent, 2, 20));
        c.setPadding(dp(4), dp(8), dp(4), dp(7));

        if (icon != null) {
            // a real app icon keeps its own identity instead of sitting on a coloured square
            ImageView iv = new ImageView(a);
            iv.setImageDrawable(icon);
            iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
            c.addView(iv, new LinearLayout.LayoutParams(dp(38), dp(38)));
        } else {
            FrameLayout chip = new FrameLayout(a);
            chip.setBackground(Palette.round(a, accent, 14));
            Icons.IconView iv = new Icons.IconView(a, kind);
            iv.setColor(Palette.PAPER);
            chip.addView(iv, new FrameLayout.LayoutParams(dp(20), dp(20), Gravity.CENTER));
            c.addView(chip, new LinearLayout.LayoutParams(dp(38), dp(38)));
        }

        TextView t = Ui.text(a, label, 10.5f, true);
        t.setTextColor(Palette.INK);
        t.setSingleLine(true);
        t.setGravity(Gravity.CENTER);
        t.setEllipsize(TextUtils.TruncateAt.END);
        t.setPadding(0, dp(5), 0, 0);
        c.addView(t, new LinearLayout.LayoutParams(MATCH, WRAP));

        c.setClickable(true);
        c.setOnClickListener(l);
        Blocks.fast(c);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, MATCH, 1);
        if (index > 0) lp.leftMargin = dp(9);
        row.addView(c, lp);
    }

    // ------------------------------------------------------------------ library / empty state

    private View libraryCard() {
        LinearLayout c = new LinearLayout(a);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setBackground(Palette.roundStroke(a, Palette.PAPER, Palette.TEAL, 2, 24));
        c.setPadding(dp(14), dp(11), dp(14), dp(11));

        LinearLayout head = new LinearLayout(a);
        head.setGravity(Gravity.CENTER_VERTICAL);
        head.addView(micro("LIBRARY", Palette.TEAL), new LinearLayout.LayoutParams(0, WRAP, 1));
        LinearLayout all = new LinearLayout(a);
        all.setGravity(Gravity.CENTER_VERTICAL);
        TextView at = Ui.text(a, "全部", 10, true);
        at.setTextColor(Palette.TEAL);
        all.addView(at);
        Icons.IconView chev = new Icons.IconView(a, Icons.Kind.CHEV_R);
        chev.setColor(Palette.TEAL);
        all.addView(chev, new LinearLayout.LayoutParams(dp(12), dp(12)));
        all.setClickable(true);
        all.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { h.backTo = BlocksHome.HOME; h.go(BlocksHome.S_LIBRARY); }
        });
        Blocks.fast(all);
        head.addView(all);
        c.addView(head, new LinearLayout.LayoutParams(MATCH, WRAP));

        List<Lib.Book> allBooks = new ArrayList<Lib.Book>(Lib.all());
        if (allBooks.isEmpty()) {
            c.addView(new View(a), new LinearLayout.LayoutParams(1, 0, 1));

            LinearLayout box = new LinearLayout(a);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setGravity(Gravity.CENTER_HORIZONTAL);

            LinearLayout intro = new LinearLayout(a);
            intro.setGravity(Gravity.CENTER_VERTICAL);
            FrameLayout chip = new FrameLayout(a);
            chip.setBackground(Palette.round(a, Palette.TEAL, 22));
            Icons.IconView ic = new Icons.IconView(a, Icons.Kind.BOOK);
            ic.setColor(Palette.PAPER);
            chip.addView(ic, new FrameLayout.LayoutParams(dp(38), dp(38), Gravity.CENTER));
            intro.addView(chip, new LinearLayout.LayoutParams(dp(88), dp(88)));

            LinearLayout words = new LinearLayout(a);
            words.setOrientation(LinearLayout.VERTICAL);
            words.setPadding(dp(13), 0, 0, 0);
            intro.addView(words, new LinearLayout.LayoutParams(0, WRAP, 1));
            box.addView(intro, new LinearLayout.LayoutParams(MATCH, WRAP));

            TextView t = Ui.text(a, "书架还空着", 18, true);
            t.setTextColor(Palette.INK);
            words.addView(t, new LinearLayout.LayoutParams(MATCH, WRAP));

            TextView sub = Ui.text(a, "把书放进 Books 文件夹，或用传书网页拖进来", 10.5f, false);
            sub.setTextColor(Palette.MUTED);
            sub.setSingleLine(true);
            sub.setEllipsize(TextUtils.TruncateAt.END);
            sub.setPadding(0, dp(3), 0, 0);
            words.addView(sub, new LinearLayout.LayoutParams(MATCH, WRAP));

            LinearLayout btns = new LinearLayout(a);
            btns.setGravity(Gravity.CENTER);
            btns.setPadding(0, dp(9), 0, 0);

            TextView go = Ui.text(a, "传书", 10.5f, true);
            go.setTextColor(Palette.PAPER);
            go.setBackground(Palette.round(a, Palette.CORAL, 24));
            go.setGravity(Gravity.CENTER);
            go.setPadding(dp(16), dp(6), dp(16), dp(6));
            go.setClickable(true);
            go.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    a.startActivity(new android.content.Intent(a, TransferActivity.class));
                }
            });
            btns.addView(go, new LinearLayout.LayoutParams(WRAP, WRAP));

            TextView browse = Ui.text(a, "浏览文件", 10.5f, true);
            browse.setTextColor(Palette.TEAL);
            browse.setBackground(Palette.roundStroke(a, Palette.PAPER, Palette.TEAL, 2, 24));
            browse.setGravity(Gravity.CENTER);
            browse.setPadding(dp(16), dp(6), dp(16), dp(6));
            browse.setClickable(true);
            browse.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { h.show(BlocksHome.FILES); a.changed(); }
            });
            LinearLayout.LayoutParams blp = new LinearLayout.LayoutParams(WRAP, WRAP);
            blp.leftMargin = dp(9);
            btns.addView(browse, blp);
            box.addView(btns, new LinearLayout.LayoutParams(MATCH, WRAP));

            TextView hint = Ui.text(a, "支持 EPUB / TXT / PDF · 也可以直接读微信读书", 9.5f, false);
            hint.setTextColor(Palette.MUTED);
            hint.setGravity(Gravity.CENTER);
            hint.setPadding(0, dp(8), 0, 0);
            box.addView(hint, new LinearLayout.LayoutParams(MATCH, WRAP));

            c.addView(box, new LinearLayout.LayoutParams(MATCH, WRAP));
            c.addView(new View(a), new LinearLayout.LayoutParams(1, 0, 1));
            return c;
        }

        Collections.sort(allBooks, new Comparator<Lib.Book>() {
            @Override public int compare(Lib.Book x, Lib.Book y) { return Long.compare(y.mtime, x.mtime); }
        });
        LinearLayout row = new LinearLayout(a);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams rp = new LinearLayout.LayoutParams(MATCH, WRAP);
        rp.topMargin = dp(9);
        c.addView(row, rp);
        int n = Math.min(4, allBooks.size());
        for (int i = 0; i < n; i++) {
            final Lib.Book b = allBooks.get(i);
            LinearLayout col = new LinearLayout(a);
            col.setOrientation(LinearLayout.VERTICAL);
            int[] mats2 = { Palette.MINT, Palette.PEACH, Palette.LEMON, Palette.LILAC };
            FrameLayout mat = new FrameLayout(a);
            mat.setBackground(Palette.round(a, mats2[i % mats2.length], 12));
            mat.setPadding(dp(5), dp(5), dp(5), dp(5));
            Bitmap bm = Lib.cover(a, b);
            if (bm == null && Lib.coverMissing(a, b)) {
                List<Lib.Book> one = new ArrayList<Lib.Book>();
                one.add(b);
                Lib.generate(a, one);
            }
            if (bm != null) {
                ImageView iv = new ImageView(a);
                iv.setScaleType(ImageView.ScaleType.CENTER_INSIDE);
                iv.setImageBitmap(bm);
                iv.setBackgroundColor(Palette.PAPER);
                mat.addView(iv, new FrameLayout.LayoutParams(MATCH, MATCH));
            } else {
                CoverView cv = new CoverView(a, b, null, false);
                mat.addView(cv, new FrameLayout.LayoutParams(MATCH, MATCH));
            }
            col.addView(mat, new LinearLayout.LayoutParams(MATCH, dp(140)));
            TextView t = Ui.text(a, b.title, 10.5f, true);
            t.setTextColor(Palette.INK);
            t.setSingleLine(true);
            t.setEllipsize(TextUtils.TruncateAt.END);
            t.setPadding(0, dp(4), 0, 0);
            col.addView(t, new LinearLayout.LayoutParams(MATCH, WRAP));
            col.setClickable(true);
            col.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) { h.openBook(b); }
            });
            col.setOnLongClickListener(new View.OnLongClickListener() {
                @Override public boolean onLongClick(View v) { a.bookMenu(b); return true; }
            });
            Blocks.fast(col);
            LinearLayout.LayoutParams cp = new LinearLayout.LayoutParams(0, WRAP, 1);
            if (i > 0) cp.leftMargin = dp(9);
            row.addView(col, cp);
        }
        return c;
    }

    private String weather() {
        String city = p.getString("wx_city", "");
        String json = p.getString("wx_norm", null);
        long at = p.getLong("wx_at", 0);
        if (city.length() == 0 || json == null || System.currentTimeMillis() - at > 6 * 3600000L) return null;
        try {
            JSONObject o = new JSONObject(json);
            return Math.round(o.getDouble("t")) + "°  " + o.optString("desc", "");
        } catch (Throwable t) {
            return null;
        }
    }

    // ------------------------------------------------------------------ today: weather/date + daily line

    private View todayCard() {
        LinearLayout c = new LinearLayout(a);
        c.setOrientation(LinearLayout.HORIZONTAL);
        c.setBackground(Palette.roundStroke(a, Palette.PAPER, Palette.AMBER, 2, 24));
        c.setPadding(dp(14), dp(11), dp(14), dp(11));

        LinearLayout left = new LinearLayout(a);
        left.setOrientation(LinearLayout.VERTICAL);
        left.addView(micro("TODAY", Palette.AMBER), new LinearLayout.LayoutParams(MATCH, WRAP));

        String wx = weather();
        LinearLayout todayRow = new LinearLayout(a);
        todayRow.setGravity(Gravity.CENTER_VERTICAL);
        FrameLayout tile = new FrameLayout(a);
        tile.setBackground(Palette.round(a, Palette.AMBER, 18));
        if (wx != null) {
            String city = p.getString("wx_city", "");
            String[] parts = wx.trim().split("\\s+", 2);
            TextView temp = Ui.text(a, parts.length > 0 ? parts[0] : wx, 20, true);
            temp.setTextColor(Palette.PAPER);
            temp.setGravity(Gravity.CENTER);
            tile.addView(temp, new FrameLayout.LayoutParams(MATCH, MATCH));
            TextView cc = Ui.text(a, city + (parts.length > 1 ? " · " + parts[1] : ""), 10, false);
            cc.setTextColor(Palette.MUTED);
            cc.setSingleLine(true);
            cc.setEllipsize(TextUtils.TruncateAt.END);
            left.addView(cc, new LinearLayout.LayoutParams(MATCH, WRAP));
        } else {
            Calendar now = Calendar.getInstance();
            TextView day = Ui.text(a, String.valueOf(now.get(Calendar.DAY_OF_MONTH)), 26, true);
            day.setTextColor(Palette.PAPER);
            day.setGravity(Gravity.CENTER);
            tile.addView(day, new FrameLayout.LayoutParams(MATCH, MATCH));
            TextView sub = Ui.text(a, (now.get(Calendar.MONTH) + 1) + "月 · 周" + BlocksCards.weekday(now), 10, false);
            sub.setTextColor(Palette.MUTED);
            left.addView(sub, new LinearLayout.LayoutParams(MATCH, WRAP));
        }
        todayRow.addView(tile, new LinearLayout.LayoutParams(dp(64), dp(64)));
        LinearLayout tcol = new LinearLayout(a);
        tcol.setOrientation(LinearLayout.VERTICAL);
        tcol.setPadding(dp(8), 0, 0, 0);
        tcol.addView(left, new LinearLayout.LayoutParams(MATCH, WRAP));
        todayRow.addView(tcol, new LinearLayout.LayoutParams(0, WRAP, 1));
        c.addView(todayRow, new LinearLayout.LayoutParams(0, MATCH, 0.36f));

        View sep = new View(a);
        sep.setBackgroundColor(Palette.BORDER);
        LinearLayout.LayoutParams sp = new LinearLayout.LayoutParams(dp(1), MATCH);
        sp.leftMargin = dp(12);
        sp.rightMargin = dp(12);
        c.addView(sep, sp);

        LinearLayout right = new LinearLayout(a);
        right.setOrientation(LinearLayout.VERTICAL);
        right.addView(micro("DAILY LINE", Palette.PLUM), new LinearLayout.LayoutParams(MATCH, WRAP));
        String[] pome = BlocksCards.poemOfDay(a);
        if (pome != null) {
            TextView t = Ui.text(a, pome[2] + "\n" + pome[3], 13, false);
            t.setTextColor(Palette.INK);
            t.setMaxLines(4);
            t.setEllipsize(TextUtils.TruncateAt.END);
            t.setLineSpacing(0, 1.10f);
            t.setPadding(0, dp(3), 0, 0);
            right.addView(t, new LinearLayout.LayoutParams(MATCH, 0, 1));
            TextView by = Ui.text(a, pome[1] + "《" + pome[0] + "》", 10.5f, false);
            by.setTextColor(Palette.MUTED);
            by.setSingleLine(true);
            by.setEllipsize(TextUtils.TruncateAt.END);
            right.addView(by, new LinearLayout.LayoutParams(MATCH, WRAP));
        } else {
            TextView t = Ui.text(a, "今天也读一点吧。", 11.5f, false);
            t.setTextColor(Palette.INK);
            right.addView(t, new LinearLayout.LayoutParams(MATCH, 0, 1));
        }
        c.addView(right, new LinearLayout.LayoutParams(0, MATCH, 0.64f));
        return c;
    }

    // ------------------------------------------------------------------ data helpers

    private boolean[] readDays(int n) {
        SharedPreferences r = Store.prefs(a, "reader");
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.US);
        boolean[] out = new boolean[n];
        long now = System.currentTimeMillis();
        for (int i = 0; i < n; i++)
            out[n - 1 - i] = r.getLong("read." + f.format(new Date(now - i * 86400000L)) + ".ms", 0) >= 60000L;
        return out;
    }

    private int streak() {
        SharedPreferences r = Store.prefs(a, "reader");
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.US);
        long now = System.currentTimeMillis();
        int n = 0;
        for (int i = 0; i < 60; i++) {
            long ms = r.getLong("read." + f.format(new Date(now - i * 86400000L)) + ".ms", 0);
            if (ms >= 60000L) n++;
            else if (i > 0) break;   // today may still be empty in the morning
        }
        return n;
    }

    /** Seven daily bars, Monday first, normalised to the largest day. */
    private float[] weekBars() {
        SharedPreferences r = Store.prefs(a, "reader");
        SimpleDateFormat f = new SimpleDateFormat("yyyyMMdd", Locale.US);
        Calendar cal = Calendar.getInstance();
        int dow = (cal.get(Calendar.DAY_OF_WEEK) + 5) % 7;   // Monday = 0
        long now = System.currentTimeMillis();
        long start = now - dow * 86400000L;
        float[] out = new float[7];
        long max = 1;
        for (int i = 0; i < 7; i++) {
            long ms = r.getLong("read." + f.format(new Date(start + i * 86400000L)) + ".ms", 0);
            out[i] = ms;
            if (ms > max) max = ms;
        }
        for (int i = 0; i < 7; i++) out[i] = out[i] / (float) max;
        return out;
    }

    private static boolean mostlyDark(Bitmap b) {
        if (b == null || b.isRecycled() || b.getWidth() <= 0 || b.getHeight() <= 0) return true;
        int dark = 0, all = 0;
        for (int y = 0; y < b.getHeight(); y += Math.max(1, b.getHeight() / 12)) {
            for (int x = 0; x < b.getWidth(); x += Math.max(1, b.getWidth() / 12)) {
                int c = b.getPixel(x, y);
                int lum = (((c >> 16) & 0xff) * 77 + ((c >> 8) & 0xff) * 150 + (c & 0xff) * 29) >> 8;
                all++;
                if (lum < 48) dark++;
            }
        }
        return all > 0 && dark * 100 / all > 65;
    }

    private TextView labelPill(String s, int bg) {
        TextView t = Ui.text(a, s, 8.5f, true);
        t.setTextColor(Palette.PAPER);
        t.setLetterSpacing(0.10f);
        t.setBackground(Palette.round(a, bg, 20));
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(8), dp(3), dp(8), dp(3));
        t.setSingleLine(true);
        return t;
    }

    private TextView micro(String s) { return micro(s, Palette.MUTED); }
    private TextView micro(String s, int color) {
        TextView t = Ui.text(a, s, 9, true);
        t.setTextColor(color);
        t.setLetterSpacing(0.10f);
        t.setSingleLine(true);
        t.setEllipsize(TextUtils.TruncateAt.END);
        return t;
    }

    private android.graphics.drawable.Drawable cardBg() {
        return Palette.roundStroke(a, Palette.CARD, Palette.BORDER, 2, 24);
    }

    /** A chubby capsule battery: rounded outline, rounded nub, rounded fill, a bolt while charging. */
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
            int col = charging ? Palette.TEAL : v <= 15 ? Palette.CORAL : v <= 30 ? Palette.AMBER : Palette.TEAL;
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(col);
            float inset = pad + Math.max(2f, h * 0.16f);
            float inner = Math.max(0, (w - pad * 3 - inset - pad) * v / 100f);
            if (inner > 1) c.drawRoundRect(new RectF(inset, inset, inset + inner, h - inset), rr / 2f, rr / 2f, paint);
            if (charging) {
                paint.setColor(Palette.PAPER);
                android.graphics.Path bolt = new android.graphics.Path();
                float bx = w * 0.42f, by = h * 0.26f;
                bolt.moveTo(bx + h * 0.12f, by);
                bolt.lineTo(bx - h * 0.10f, h * 0.52f);
                bolt.lineTo(bx + h * 0.02f, h * 0.52f);
                bolt.lineTo(bx - h * 0.06f, h * 0.76f);
                bolt.lineTo(bx + h * 0.20f, h * 0.42f);
                bolt.lineTo(bx + h * 0.05f, h * 0.42f);
                bolt.close();
                c.drawPath(bolt, paint);
            }
        }
    }

    /** A round little cat face: the home's mascot, drawn so it stays crisp on the panel. */
    static final class Mascot extends View {
        private final int face;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Mascot(android.content.Context c, int face) {
            super(c);
            this.face = face;
        }
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

            paint.setColor(Palette.blend(Palette.CORAL, Palette.PAPER, 0.35f));
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

    /** A slim horizontal progress bar. */
    static final class Bar extends View {
        private final int pct, fill, track;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Bar(android.content.Context c, int pct, int fill, int track) {
            super(c);
            this.pct = Math.max(0, Math.min(100, pct));
            this.fill = fill;
            this.track = track;
        }
        @Override protected void onDraw(Canvas c) {
            int w = getWidth(), h = getHeight();
            float rr = h / 2f;
            paint.setStyle(Paint.Style.FILL);
            paint.setColor(track);
            c.drawRoundRect(new RectF(0, 0, w, h), rr, rr, paint);
            paint.setColor(fill);
            float fw = w * pct / 100f;
            if (fw > 0) c.drawRoundRect(new RectF(0, 0, Math.max(h, fw), h), rr, rr, paint);
        }
    }

    /** Seven tiny vertical bars for the week. */
    static final class Bar7 extends View {
        private final float[] vals;
        private final int bar, todayBar, track;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        Bar7(android.content.Context c, float[] vals, int bar, int todayBar, int track) {
            super(c);
            this.vals = vals;
            this.bar = bar;
            this.todayBar = todayBar;
            this.track = track;
        }
        @Override protected void onDraw(Canvas c) {
            int w = getWidth(), h = getHeight();
            float gap = Ui.dp(getContext(), 3);
            float bw = (w - gap * 6) / 7f;
            int today = vals.length - 1;
            for (int i = 0; i < vals.length; i++) {
                float bh = Math.max(2, vals[i] * h);
                paint.setColor(track);
                float x = i * (bw + gap);
                c.drawRoundRect(new RectF(x, h - bh, x + bw, h), 2, 2, paint);
                paint.setColor(i == today ? todayBar : bar);
                if (vals[i] > 0.01f) c.drawRoundRect(new RectF(x, h - bh, x + bw, h), 2, 2, paint);
            }
        }
    }
}
