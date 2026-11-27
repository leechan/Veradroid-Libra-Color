// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapShader;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.graphics.Shader;
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
        if (h >= 5 && h < 10) return 1;
        if (h >= 10 && h < 16) return 2;
        if (h >= 16 && h < 20) return 3;
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
        switch (moodIndex()) {
        case 1: return "早上好呀";
        case 2: return "下午好呀";
        case 3: return "傍晚好呀";
        default: return "晚上好呀";
        }
    }

    /** muted accent for a given tab: home / library / apps / me. */
    static int tabAccent(int i) {
        switch (i) {
        case 0: return CORAL;
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
