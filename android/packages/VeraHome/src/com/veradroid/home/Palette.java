// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PathMeasure;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
import android.graphics.SweepGradient;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;

import java.util.Calendar;

/**
 * The colour palette of the "色彩" launcher style.
 *
 * Kaleido 3 is a subtractive CFA panel: dark, saturated colours survive, very light tints
 * wash out to white and neon colours turn muddy. So the palette uses deep inks for text,
 * mid-dark saturated accents for blocks of colour, and only a few gentle tints as card mats.
 *
 * The accent follows the time of day ("晨光 / 午后 / 黄昏 / 夜色"): the home changes colour
 * through the day instead of being one fixed theme.
 */
final class Palette {
    private Palette() { }

    static final int PAPER = 0xFFFFFFFF;
    static final int PAPER_WARM = 0xFFFFFBF4;
    static final int BG = 0xFFFBF7F1;
    static final int CARD = 0xFFFFFFFF;
    static final int BORDER = 0xFFE7E1D7;
    static final int MAT = 0xFFF1EEE7;
    static final int DARK = 0xFF262A38;
    static final int GRAPE = 0xFF5B2FB0;
    static final int GREEN = 0xFF2E7D4F;
    static final int BLUE = 0xFF163E78;
    static final int COBALT = 0xFF1F4FD8;
    static final int INK = 0xFF17181C;
    static final int MUTED = 0xFF4E525A;
    static final int LINE = 0xFFDDD9D1;

    static final int CORAL = 0xFFD8341F;
    static final int TEAL = 0xFF007568;
    static final int INDIGO = 0xFF2533B8;
    static final int AMBER = 0xFFB57400;
    static final int PLUM = 0xFFA32E6B;
    static final int SKY = 0xFF1A6DB5;

    static final int MINT = 0xFFC6DCD2;
    static final int PEACH = 0xFFEDCAB6;
    static final int LEMON = 0xFFE7D394;
    static final int ROSE = 0xFFE3C4CD;
    static final int MIST = 0xFFC9D7E7;
    static final int LILAC = 0xFFD5CCE4;

    /* macaron card fills: cute but still light enough for ink text */
    static final int SOFT_PEACH = 0xFFF6C9A4;
    static final int SOFT_MINT = 0xFFDBEDE4;
    static final int SOFT_LEMON = 0xFFF7EBC5;
    static final int SOFT_LILAC = 0xFFE7E0F4;
    static final int SOFT_ROSE = 0xFFF7DEE5;
    static final int SOFT_SKY = 0xFFDDE9F5;

    /** The five-colour ribbon at the top of the home: the brand mark of the colour style. */
    static final int[] RIBBON = { CORAL, AMBER, TEAL, SKY, PLUM };

    private static final String[] MOOD_NAME = { "夜色", "晨光", "午后", "黄昏" };

    /** Fixed warm highlight for the selected bottom tab (the mood teal read as muddy green). */
    static final int ACCENT = CORAL;

    /** 0 night, 1 morning, 2 afternoon, 3 dusk. */
    static int moodIndex() {
        int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        if (h >= 5 && h < 12) return 1;
        if (h >= 12 && h < 18) return 2;
        if (h >= 18 && h < 23) return 3;
        return 0;
    }

    /** Deep, friendly hero fill for each part of the day (no muddy teal). */
    static int hero() {
        switch (moodIndex()) {
        case 1: return CORAL;
        case 2: return COBALT;
        case 3: return CORAL;
        default: return INDIGO;
        }
    }

    static int mood() {
        switch (moodIndex()) {
        case 1: return AMBER;
        case 2: return TEAL;
        case 3: return CORAL;
        default: return INDIGO;
        }
    }

    static String moodName() { return MOOD_NAME[moodIndex()]; }

    static String greeting() {
        int h = Calendar.getInstance().get(Calendar.HOUR_OF_DAY);
        if (h >= 6 && h < 8) return "早上好";
        if (h >= 8 && h < 12) return "上午好";
        if (h >= 12 && h < 14) return "中午好";
        if (h >= 14 && h < 18) return "下午好";
        if (h >= 18 && h < 22) return "晚上好";
        return "夜深了";
    }

    /** muted accent for a given tab: home / library / apps / me. */
    static int tabAccent(int i) {
        switch (i) {
        case 0: return GREEN;
        case 1: return TEAL;
        case 2: return SKY;
        default: return PLUM;
        }
    }

    /** t = 0 returns a, t = 1 returns b. */
    static int blend(int a, int b, float t) {
        if (t <= 0) return a;
        if (t >= 1) return b;
        int aa = (a >>> 24) & 0xff, ar = (a >> 16) & 0xff, ag = (a >> 8) & 0xff, ab = a & 0xff;
        int ba = (b >>> 24) & 0xff, br = (b >> 16) & 0xff, bg = (b >> 8) & 0xff, bb = b & 0xff;
        int ra = Math.round(aa + (ba - aa) * t), rr = Math.round(ar + (br - ar) * t);
        int rg = Math.round(ag + (bg - ag) * t), rb = Math.round(ab + (bb - ab) * t);
        return (ra << 24) | (rr << 16) | (rg << 8) | rb;
    }

    /** secondary text on the dark hero card */
    static int dimOnDark() { return 0xFFC9CDD8; }
    /** micro caps on the dark hero card */
    static int barOnDark() { return 0xFFAEB4C6; }

    static int tint(int c) { return blend(c, PAPER, 0.76f); }
    static int soft(int c) { return blend(c, PAPER, 0.52f); }

    /** White text on dark accents, ink on light tints. */
    static int textOn(int bg) {
        int lum = (((bg >> 16) & 0xff) * 77 + ((bg >> 8) & 0xff) * 150 + (bg & 0xff) * 29) >> 8;
        return lum < 150 ? PAPER : INK;
    }

    /** A rounded border painted with a smooth colour sweep (a real gradient, not segments). */
    static Drawable gradientBorder(Context c, int fill, int[] colors, int strokeDp, int radiusDp) {
        return new GradientBorder(c, fill, colors, strokeDp, radiusDp);
    }

    static final class GradientBorder extends Drawable {
        private final Paint fillP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint strokeP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int fill;
        private final int[] colors;
        private final float radius, stroke;
        GradientBorder(Context c, int fill, int[] colors, int strokeDp, int radiusDp) {
            this.fill = fill;
            this.colors = colors;
            radius = Ui.dp(c, radiusDp);
            stroke = Math.max(2f, Ui.dp(c, strokeDp) / 2f);
            strokeP.setStyle(Paint.Style.STROKE);
            strokeP.setStrokeWidth(stroke);
            strokeP.setStrokeCap(Paint.Cap.ROUND);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            RectF r = new RectF(b.left + stroke / 2f, b.top + stroke / 2f, b.right - stroke / 2f, b.bottom - stroke / 2f);
            fillP.setStyle(Paint.Style.FILL);
            fillP.setColor(fill);
            c.drawRoundRect(r, radius, radius, fillP);
            int n = colors.length;
            int[] ring = new int[n + 1];
            System.arraycopy(colors, 0, ring, 0, n);
            ring[n] = colors[0];
            SweepGradient sg = new SweepGradient(r.centerX(), r.centerY(), ring, null);
            strokeP.setShader(sg);
            c.drawRoundRect(r, radius, radius, strokeP);
            strokeP.setShader(null);
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** 面板后面的遮罩：淡白底 + 细斜线（45°）。用一张小位图平铺，整屏只有两次绘制。 */
    static Drawable scrim(Context c) { return new Scrim(c); }

    static final class Scrim extends Drawable {
        private final Paint base = new Paint();
        private final Paint line = new Paint(Paint.ANTI_ALIAS_FLAG);
        Scrim(Context c) {
            int p = Math.max(6, Ui.dp(c, 9));
            float w = Math.max(1f, Ui.dp(c, 1) * 0.55f);
            Bitmap tile = Bitmap.createBitmap(p, p, Bitmap.Config.ARGB_8888);
            Canvas tc = new Canvas(tile);
            Paint tp = new Paint(Paint.ANTI_ALIAS_FLAG);
            tp.setStyle(Paint.Style.STROKE);
            tp.setStrokeWidth(w);
            tp.setColor(0xB3000000);
            tc.drawLine(-1, p + 1, p + 1, -1, tp);   // 45° 线，平铺后接成斜纹
            line.setShader(new BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT));
            base.setColor(0x59FFFFFF);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            c.drawRect(b, base);
            c.drawRect(b, line);
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** 斜条纹底：糖果色斜纹 + 可选的彩虹描边。edge 传 null 就只画斜纹。 */
    static Drawable candy(Context c, int[] stripes, int[] edge, int strokeDp, int radiusDp, int periodDp, int bandDp) {
        return new Candy(c, PAPER, stripes, edge, strokeDp, radiusDp, periodDp, bandDp);
    }

    /** 实色圆角块 + 斜纹（选中标签用）。 */
    static Drawable stripeFill(Context c, int base, int[] stripes, int radiusDp, int periodDp, int bandDp) {
        return new Candy(c, base, stripes, null, 0, radiusDp, periodDp, bandDp);
    }

    static final class Candy extends Drawable {
        private final Paint fillP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint strokeP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint lineP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int[] stripes, colors;
        private final int base;
        private final float radius, stroke, period, band;

        Candy(Context c, int base, int[] stripes, int[] colors, int strokeDp, int radiusDp, int periodDp, int bandDp) {
            this.base = base;
            this.stripes = stripes;
            this.colors = colors;
            radius = Ui.dp(c, radiusDp);
            stroke = Math.max(2f, Ui.dp(c, strokeDp) / 2f);
            period = Math.max(4f, Ui.dp(c, periodDp));
            band = Math.max(2f, Ui.dp(c, bandDp));
            fillP.setStyle(Paint.Style.FILL);
            strokeP.setStyle(Paint.Style.STROKE);
            strokeP.setStrokeWidth(stroke);
            strokeP.setStrokeCap(Paint.Cap.ROUND);
            lineP.setStyle(Paint.Style.STROKE);
            lineP.setStrokeWidth(band);
            lineP.setStrokeCap(Paint.Cap.BUTT);
        }

        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            RectF r = new RectF(b.left + stroke / 2f, b.top + stroke / 2f, b.right - stroke / 2f, b.bottom - stroke / 2f);
            Path clip = new Path();
            clip.addRoundRect(r, radius, radius, Path.Direction.CW);
            int save = c.save();
            c.clipPath(clip);
            fillP.setColor(base);
            c.drawRect(b, fillP);
            float h = b.height();
            int k = 0;
            for (float x = b.left - h; x < b.right + h; x += period) {
                lineP.setColor(stripes[k++ % stripes.length]);
                c.drawLine(x, b.bottom, x + h, b.top, lineP);
            }
            c.restoreToCount(save);
            if (colors != null && colors.length > 0) {
                int n = colors.length;
                int[] ring = new int[n + 1];
                System.arraycopy(colors, 0, ring, 0, n);
                ring[n] = colors[0];
                SweepGradient sg = new SweepGradient(r.centerX(), r.centerY(), ring, null);
                strokeP.setShader(sg);
                c.drawRoundRect(r, radius, radius, strokeP);
                strokeP.setShader(null);
            }
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** A white pill whose border is split into several colours. */
    static Drawable multiBorder(Context c, int fill, int[] colors, int strokeDp, int radiusDp) {
        return new MultiBorder(c, fill, colors, strokeDp, radiusDp);
    }

    static final class MultiBorder extends Drawable {
        private final Paint fillP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Paint strokeP = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final Path path = new Path(), seg = new Path();
        private final PathMeasure pm = new PathMeasure();
        private final int[] colors;
        private final int fill;
        private final float radius, stroke;
        MultiBorder(Context c, int fill, int[] colors, int strokeDp, int radiusDp) {
            this.fill = fill;
            this.colors = colors;
            radius = Ui.dp(c, radiusDp);
            stroke = Math.max(2f, Ui.dp(c, strokeDp) / 2f);
            strokeP.setStyle(Paint.Style.STROKE);
            strokeP.setStrokeWidth(stroke);
            strokeP.setStrokeCap(Paint.Cap.ROUND);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            RectF r = new RectF(b.left + stroke / 2f, b.top + stroke / 2f, b.right - stroke / 2f, b.bottom - stroke / 2f);
            fillP.setStyle(Paint.Style.FILL);
            fillP.setColor(fill);
            c.drawRoundRect(r, radius, radius, fillP);
            path.reset();
            path.addRoundRect(r, radius, radius, Path.Direction.CW);
            pm.setPath(path, false);
            float len = pm.getLength();
            if (len <= 0) return;
            int n = colors.length;
            for (int i = 0; i < n; i++) {
                seg.reset();
                pm.getSegment(len * i / n, len * (i + 1) / n, seg, true);
                strokeP.setColor(colors[i]);
                c.drawPath(seg, strokeP);
            }
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** Launcher background: warm dot grid + a few large, light geometric shapes. */
    static Drawable homeBg(Context c) { return new HomeBg(c); }

    static final class HomeBg extends Drawable {
        private final Context ctx;
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final BitmapShader shader;
        HomeBg(Context c) {
            ctx = c;
            int step = Math.max(9, Ui.dp(c, 12));
            Bitmap tile = Bitmap.createBitmap(step, step, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(tile);
            cv.drawColor(PAPER_WARM);
            Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);
            dot.setColor(blend(GREEN, PAPER_WARM, 0.80f));
            cv.drawCircle(step / 2f, step / 2f, Math.max(1.6f, Ui.dp(c, 1)), dot);
            shader = new BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            paint.setStyle(Paint.Style.FILL);
            paint.setShader(shader);
            c.drawRect(b, paint);
            paint.setShader(null);

            float w = b.width(), h = b.height();
            paint.setStyle(Paint.Style.FILL);

            // teal circle just peeking off the top-right corner
            paint.setColor(blend(TEAL, PAPER, 0.74f));
            c.drawCircle(b.left + w * 0.99f, b.top + h * 0.04f, w * 0.23f, paint);

            // sky rounded rectangle behind the cards, centre-right
            paint.setColor(blend(SKY, PAPER, 0.76f));
            c.save();
            c.rotate(9, b.left + w * 0.62f, b.top + h * 0.47f);
            c.drawRoundRect(new RectF(b.left + w * 0.47f, b.top + h * 0.39f, b.left + w * 0.78f, b.top + h * 0.56f), 32, 32, paint);
            c.restore();

            // amber triangle, right middle
            paint.setColor(blend(AMBER, PAPER, 0.72f));
            Path tri = new Path();
            tri.moveTo(b.left + w * 0.88f, b.top + h * 0.35f);
            tri.lineTo(b.left + w * 1.03f, b.top + h * 0.46f);
            tri.lineTo(b.left + w * 0.84f, b.top + h * 0.48f);
            tri.close();
            c.drawPath(tri, paint);

            // green leaf, lower middle (organic shape instead of the bar)
            paint.setColor(blend(GREEN, PAPER, 0.74f));
            Path leaf = new Path();
            leaf.moveTo(b.left + w * 0.36f, b.top + h * 0.73f);
            leaf.quadTo(b.left + w * 0.42f, b.top + h * 0.63f, b.left + w * 0.57f, b.top + h * 0.66f);
            leaf.quadTo(b.left + w * 0.52f, b.top + h * 0.76f, b.left + w * 0.36f, b.top + h * 0.73f);
            c.drawPath(leaf, paint);

            // plum circle, bottom right, with a clear gap
            paint.setColor(blend(PLUM, PAPER, 0.74f));
            c.drawCircle(b.left + w * 0.87f, b.top + h * 0.86f, w * 0.13f, paint);
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** Full-bleed dot grid: a quiet texture for the launcher background (no border). */
    static Drawable pattern(Context c, int base, int accent) {
        return new PatternDrawable(c, base, accent);
    }

    static final class PatternDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final BitmapShader shader;
        PatternDrawable(Context c, int base, int accent) {
            int step = Math.max(9, Ui.dp(c, 12));
            Bitmap tile = Bitmap.createBitmap(step, step, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(tile);
            cv.drawColor(base);
            Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);
            dot.setColor(blend(accent, base, 0.80f));
            cv.drawCircle(step / 2f, step / 2f, Math.max(1.6f, Ui.dp(c, 1)), dot);
            shader = new BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            paint.setStyle(Paint.Style.FILL);
            paint.setShader(shader);
            c.drawRect(b, paint);
            paint.setShader(null);
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    /** Light warm paper with a fine coloured dot grid: a texture that stays readable. */
    static Drawable paper(Context c, int accent, int radiusDp) {
        return new PaperDrawable(c, accent, radiusDp);
    }

    static final class PaperDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final BitmapShader shader;
        private final int radius, stroke, accent;
        PaperDrawable(Context c, int accent, int radiusDp) {
            this.accent = accent;
            radius = Ui.dp(c, radiusDp);
            stroke = Math.max(2, Ui.dp(c, 1));
            int step = Math.max(8, Ui.dp(c, 10));
            Bitmap tile = Bitmap.createBitmap(step, step, Bitmap.Config.ARGB_8888);
            Canvas cv = new Canvas(tile);
            cv.drawColor(PAPER_WARM);
            Paint dot = new Paint(Paint.ANTI_ALIAS_FLAG);
            dot.setColor(blend(accent, PAPER_WARM, 0.72f));
            cv.drawCircle(step / 2f, step / 2f, Math.max(2f, Ui.dp(c, 1)), dot);
            shader = new BitmapShader(tile, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT);
        }
        @Override public void draw(Canvas c) {
            Rect b = getBounds();
            RectF r = new RectF(b.left + stroke / 2f, b.top + stroke / 2f, b.right - stroke / 2f, b.bottom - stroke / 2f);
            paint.setStyle(Paint.Style.FILL);
            paint.setShader(shader);
            c.drawRoundRect(r, radius, radius, paint);
            paint.setShader(null);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(stroke);
            paint.setColor(accent);
            c.drawRoundRect(r, radius, radius, paint);
        }
        @Override public void setAlpha(int a) { }
        @Override public void setColorFilter(android.graphics.ColorFilter f) { }
        @Override public int getOpacity() { return android.graphics.PixelFormat.TRANSLUCENT; }
    }

    static GradientDrawable round(Context c, int color, int radiusDp) {
        GradientDrawable g = new GradientDrawable();
        g.setColor(color);
        g.setCornerRadius(Ui.dp(c, radiusDp));
        return g;
    }

    static GradientDrawable roundStroke(Context c, int fill, int stroke, int strokeDp, int radiusDp) {
        GradientDrawable g = round(c, fill, radiusDp);
        g.setStroke(Math.max(1, Ui.dp(c, Math.max(1, strokeDp / 2))), stroke);
        return g;
    }

    static GradientDrawable pill(Context c, int color) { return round(c, color, 24); }
    static GradientDrawable circle(Context c, int color) { return round(c, color, 99); }
}
