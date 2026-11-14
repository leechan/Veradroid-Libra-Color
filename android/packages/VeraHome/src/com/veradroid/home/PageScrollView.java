// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.view.MotionEvent;
import android.view.ViewConfiguration;
import android.widget.ScrollView;

/**
 * E-ink friendly scrolling: a swipe turns one page when the finger lifts (no
 * following the finger, no fling, no animation), so the panel redraws once.
 * The up/down buttons do the same.
 */
class PageScrollView extends ScrollView {
    private final int slop;
    private float downY;
    private boolean dragging;

    PageScrollView(Context c) {
        super(c);
        slop = ViewConfiguration.get(c).getScaledTouchSlop() * 2;
        setVerticalScrollBarEnabled(false);
        setOverScrollMode(OVER_SCROLL_NEVER);
        setSmoothScrollingEnabled(false);
    }

    @Override public boolean onInterceptTouchEvent(MotionEvent e) {
        switch (e.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
            downY = e.getY();
            dragging = false;
            return false;
        case MotionEvent.ACTION_MOVE:
            if (Math.abs(e.getY() - downY) > slop) {
                dragging = true;
                return true;
            }
            return false;
        case MotionEvent.ACTION_UP:
        case MotionEvent.ACTION_CANCEL:
            dragging = false;
            return false;
        }
        return false;
    }

    private Runnable onPage;
    /** 翻了一页以后调用（更新页码之类）。 */
    void setOnPage(Runnable r) { onPage = r; }
    /** 用按钮翻页以后调用：和划动翻页一样通知（页码立刻跟上，不等下一次排版）。 */
    void firePage() { if (onPage != null) onPage.run(); }

    /**
     * 手指划动时内容不跟着动（墨水屏上跟手滚动 = 一路连着刷）：抬手时按划的方向整页翻一次，只换一次画面。
     */
    @Override public boolean onTouchEvent(MotionEvent e) {
        switch (e.getActionMasked()) {
        case MotionEvent.ACTION_DOWN:
            downY = e.getY();
            dragging = false;
            return true;
        case MotionEvent.ACTION_MOVE:
            if (Math.abs(e.getY() - downY) > slop) dragging = true;
            return true;
        case MotionEvent.ACTION_UP:
            if (dragging && page(e.getY() < downY ? 1 : -1) && onPage != null) onPage.run();
            dragging = false;
            return true;
        case MotionEvent.ACTION_CANCEL:
            dragging = false;
            return true;
        }
        return true;
    }

    @Override public void fling(int velocityY) { /* no inertia */ }

    /** 方块风格：从第一页开始按 page() 的规则一页页往下算，得到每一页的顶边（页数、当前页都按它算，和真翻页一致）。 */
    private java.util.List<Integer> stops() {
        java.util.List<Integer> out = new java.util.ArrayList<Integer>();
        out.add(0);
        int content = getChildCount() > 0 ? getChildAt(0).getHeight() - tailPad : 0, h = getHeight();
        if (h <= 0) return out;
        java.util.List<int[]> items = leaves();
        int y = 0;
        for (int guard = 0; guard < 200 && y + h < content; guard++) {
            int target = y + (h - h / 10);
            for (int[] it : items) if (it[1] > y + h) { if (it[0] > y) target = it[0]; break; }
            if (target <= y) break;
            y = target;
            out.add(y);
        }
        return out;
    }

    int pages() {
        if (blocks) return stops().size();
        int content = getChildCount() > 0 ? getChildAt(0).getHeight() : 0;
        int h = Math.max(1, getHeight());
        return Math.max(1, (content + h - 1) / h);
    }

    int currentPage() {
        if (blocks) {
            java.util.List<Integer> st = stops();
            int y = getScrollY(), n = 1;
            for (int i = 0; i < st.size(); i++) if (st.get(i) <= y + 2) n = i + 1;
            return n;
        }
        int content = getChildCount() > 0 ? getChildAt(0).getHeight() : 0;
        if (pages() > 1 && getScrollY() >= content - getHeight()) return pages();   // 到底了就是最后一页
        int h = Math.max(1, getHeight() - getHeight() / 10);
        return Math.max(1, Math.min(pages() - 1, (getScrollY() + h / 2) / h + 1));
    }

    /**
     * 翻一页。尽量停在一行的边上：往下翻时，这一页最下面那个没显示全的条目成为下一页的第一条；
     * 往上翻时反过来。这样不会有条目被切成两半、上一页看半行下一页看半行。
     */
    boolean page(int dir) {
        int content = getChildCount() > 0 ? getChildAt(0).getHeight() : 0;
        int h = getHeight();
        int max = Math.max(0, content - h);
        int y = getScrollY();
        if (blocks && dir > 0 && y + h >= content - tailPad) return false;   // 已经是最后一页（下面只剩垫的空白）
        int target = y + dir * (h - h / 10);
        if (blocks && getChildCount() > 0) {
            // 方块风格：分组框里的每一行也算一个条目（设置页一个分组常常比一屏还高），翻页停在行的边上
            java.util.List<int[]> items = leaves();
            if (dir > 0) {
                for (int[] it : items) if (it[1] > y + h) { if (it[0] > y) target = it[0]; break; }
            } else {
                // 往回翻：回到上一个真正的页顶（和往下翻停过的位置一样；第一页是 0，不是第一个条目的顶边）
                target = 0;
                for (int st : stops()) if (st < y - 2) target = st;
            }
        } else if (getChildCount() > 0 && getChildAt(0) instanceof android.view.ViewGroup) {
            android.view.ViewGroup g = (android.view.ViewGroup) getChildAt(0);
            if (dir > 0) {
                for (int i = 0; i < g.getChildCount(); i++) {
                    android.view.View c = g.getChildAt(i);
                    if (c.getVisibility() == GONE) continue;
                    if (c.getBottom() > y + h) { if (c.getTop() > y) target = c.getTop(); break; }
                }
            } else {
                for (int i = 0; i < g.getChildCount(); i++) {
                    android.view.View c = g.getChildAt(i);
                    if (c.getVisibility() == GONE) continue;
                    if (c.getTop() >= y - h) { if (c.getTop() < y) target = c.getTop(); break; }
                }
            }
        }
        // 最后一页：内容不够一整屏时，原来会被夹到“底部对齐”，于是最后一页顶上露出上一页条目的下半截。
        // 改成在内容底下垫空白，让最后一页也从一个条目的顶边开始。
        if (dir > 0 && target > max && target > y && getChildCount() > 0) {
            final android.view.View ch = getChildAt(0);
            final int pad = tailPad + (target - max);
            final int to = target;
            ch.setPadding(ch.getPaddingLeft(), ch.getPaddingTop(), ch.getPaddingRight(), ch.getPaddingBottom() - tailPad + pad);
            tailPad = pad;
            ch.measure(MeasureSpec.makeMeasureSpec(ch.getWidth(), MeasureSpec.EXACTLY), MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED));
            ch.layout(ch.getLeft(), ch.getTop(), ch.getLeft() + ch.getMeasuredWidth(), ch.getTop() + ch.getMeasuredHeight());
            scrollTo(0, to);
            return true;
        }
        target = Math.max(0, Math.min(max, target));
        if (target == y) return false;
        scrollTo(0, target);
        return true;
    }

    private final boolean blocks = Blocks.on(getContext());
    private final android.graphics.Paint white = new android.graphics.Paint();

    /**
     * 条目（内容坐标的 [上, 下]），按从上到下：内容的每个子控件；比七成屏幕还高的竖排分组（LinearLayout，设置页的长分组）
     * 再拆成它里面的每一行。矮一些的卡片（首页的天气、日历）整张算一条，不会被拆开、丢了框的下边。
     */
    private java.util.List<int[]> leaves() {
        java.util.List<int[]> out = new java.util.ArrayList<int[]>();
        if (getChildCount() == 0 || !(getChildAt(0) instanceof android.view.ViewGroup)) return out;
        android.view.ViewGroup g = (android.view.ViewGroup) getChildAt(0);
        for (int i = 0; i < g.getChildCount(); i++) {
            android.view.View c = g.getChildAt(i);
            if (c.getVisibility() == GONE) continue;
            if (c instanceof android.widget.LinearLayout && ((android.widget.LinearLayout) c).getOrientation() == android.widget.LinearLayout.VERTICAL
                && ((android.view.ViewGroup) c).getChildCount() > 1 && c.getHeight() > getHeight() * 7 / 10) {
                android.view.ViewGroup cg = (android.view.ViewGroup) c;
                for (int k = 0; k < cg.getChildCount(); k++) {
                    android.view.View r = cg.getChildAt(k);
                    if (r.getVisibility() == GONE || r.getHeight() <= 4) continue;   // 细线不算条目
                    out.add(new int[] { c.getTop() + r.getTop(), c.getTop() + r.getBottom() });
                }
            } else out.add(new int[] { c.getTop(), c.getBottom() });
        }
        return out;
    }

    /**
     * 方块风格：这一屏最下面没显示全的那一条用白色盖住（它会是下一页的第一条），屏幕上不出现半行。
     */
    @Override protected void dispatchDraw(android.graphics.Canvas c) {
        super.dispatchDraw(c);
        if (!blocks || getChildCount() == 0) return;
        int y = getScrollY(), h = getHeight();
        int content = getChildAt(0).getHeight();
        if (content <= h) return;
        for (int[] it : leaves()) {
            if (it[1] > y + h) {
                if (it[0] > y && it[0] < y + h) {
                    white.setColor(android.graphics.Color.WHITE);
                    c.drawRect(0, it[0], getWidth(), y + h, white);
                }
                break;
            }
        }
    }

    /** page() 为了让最后一页从条目顶边开始而在内容底下垫的空白；回到第一页时去掉。 */
    private int tailPad;

    @Override public void scrollTo(int x, int y) {
        super.scrollTo(x, y);
        if (y == 0 && tailPad > 0 && getChildCount() > 0) {
            android.view.View ch = getChildAt(0);
            ch.setPadding(ch.getPaddingLeft(), ch.getPaddingTop(), ch.getPaddingRight(), ch.getPaddingBottom() - tailPad);
            tailPad = 0;
        }
    }
}
