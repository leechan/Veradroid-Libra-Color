// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.text.Layout;
import android.text.StaticLayout;
import android.text.TextPaint;
import android.text.TextUtils;
import android.view.View;

/**
 * 一本书的封面格子，整个只是一个 View：封面图（居中裁切）或者“书名 + 格式”的白底占位，外面一圈 1 像素黑框，
 * 右上角黑底白字的进度角标。以前一格是 FrameLayout + ImageView + 两三个 TextView，一页几十个控件要量要排；
 * 现在一格一个，搭一页和画一页都快，也没有按下状态（墨水屏上按下高亮是多出来的一帧）。
 */
class CoverView extends View {
    private final Lib.Book book;
    private Bitmap bitmap;
    private final boolean badge;
    private final Paint paint = new Paint(Paint.FILTER_BITMAP_FLAG);
    private final TextPaint text = new TextPaint(Paint.ANTI_ALIAS_FLAG);
    private StaticLayout titleLayout;
    private int titleFor = -1;

    CoverView(Context c, Lib.Book b, Bitmap bm, boolean badge) {
        super(c);
        book = b;
        bitmap = bm;
        this.badge = badge;
        text.setTypeface(Fonts.typeface(c));
    }

    Lib.Book book() { return book; }
    boolean hasBitmap() { return bitmap != null && !bitmap.isRecycled(); }
    void setBitmap(Bitmap bm) { if (bm != bitmap) { bitmap = bm; invalidate(); } }

    @Override protected void onDraw(Canvas c) {
        int w = getWidth(), h = getHeight();
        if (w <= 0 || h <= 0) return;
        if (hasBitmap()) {
            // 居中裁切到格子的比例
            int bw = bitmap.getWidth(), bh = bitmap.getHeight();
            Rect src;
            if ((long) bw * h > (long) bh * w) { int cw = (int) ((long) bh * w / h); src = new Rect((bw - cw) / 2, 0, (bw + cw) / 2, bh); }
            else { int ch = (int) ((long) bw * h / w); src = new Rect(0, (bh - ch) / 2, bw, (bh + ch) / 2); }
            c.drawBitmap(bitmap, src, new Rect(0, 0, w, h), paint);
        } else {
            c.drawColor(Color.WHITE);
            float ts = Math.max(14f, w / 8.5f);
            // 这支画笔后面还要画格式名和角标，每次画书名前都设回来（排版对象引用的是同一支画笔）
            text.setColor(Color.BLACK);
            text.setFakeBoldText(true);
            text.setTextSize(ts);
            if (titleLayout == null || titleFor != w) {
                int pad = Math.max(6, w / 12);
                CharSequence t = book.title == null ? "" : book.title;
                titleLayout = new StaticLayout(t, 0, t.length(), text, Math.max(10, w - 2 * pad), Layout.Alignment.ALIGN_CENTER,
                    1.15f, 0f, false, TextUtils.TruncateAt.END, Math.max(10, w - 2 * pad));
                titleFor = w;
            }
            int lines = Math.min(titleLayout.getLineCount(), h > w ? 4 : 2);
            int th = titleLayout.getLineBottom(lines - 1);
            c.save();
            c.translate(Math.max(6, w / 12), Math.max(4, (h - th) / 2 - h / 14));
            c.clipRect(0, 0, titleLayout.getWidth(), th);
            titleLayout.draw(c);
            c.restore();
            text.setFakeBoldText(false);
            text.setTextSize(ts * 0.62f);
            text.setTextAlign(Paint.Align.CENTER);
            c.drawText(book.ext(), w / 2f, h - ts * 0.7f, text);
            text.setTextAlign(Paint.Align.LEFT);
        }
        paint.setStyle(Paint.Style.STROKE);
        paint.setColor(Color.BLACK);
        paint.setStrokeWidth(hasBitmap() ? 1 : 2);
        float half = hasBitmap() ? 0.5f : 1f;
        c.drawRect(half, half, w - half, h - half, paint);
        if (badge && (book.percent > 0 || book.lastRead > 1)) {
            String s = book.percent >= 100 ? "已读" : book.percent + "%";
            float bs = Math.max(20f, w / 11f);   // 小封面上也要看得清
            text.setTextSize(bs);
            text.setFakeBoldText(true);
            float tw = text.measureText(s), px = bs * 0.45f, bh = bs * 1.45f;
            paint.setStyle(Paint.Style.FILL);
            c.drawRect(w - tw - 2 * px, 0, w, bh, paint);
            text.setColor(Color.WHITE);
            c.drawText(s, w - tw - px, bh - bs * 0.38f, text);
            text.setColor(Color.BLACK);
        }
        paint.setStyle(Paint.Style.FILL);
    }
}
