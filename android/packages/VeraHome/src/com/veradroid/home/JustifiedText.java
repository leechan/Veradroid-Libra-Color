package com.veradroid.home;

import android.content.Context;
import android.graphics.Canvas;
import android.text.Layout;
import android.text.TextPaint;
import android.widget.TextView;

/**
 * 阅读器正文：两端对齐（API 25 的 StaticLayout 还没有 JUSTIFICATION_MODE，那是 API 26 才有的）。
 *
 * 断行完全交给 TextView 自己的 StaticLayout（左对齐，和分页用的是同一套参数），这里只改“画”：
 * 每一行算出离右边距还差多少，平均分到这一行里能拉开的地方——
 * 中日韩文字（含全角标点；—— …… 和弯引号不算，它们只在挨着汉字的一边拉开）两两之间、中日韩文字和西文之间，西文只在空格处（单词里面不拆开）。
 * 段落最后一行（行尾是换行）、整页最后一行而这一段到这里就结束了，都照常左对齐。
 * 行尾的空格不算宽度（不拉开，右边贴齐的是最后一个可见字符，句号逗号就在行尾贴着右边距）；
 * 一行里没地方拉开（一个很长的单词 / 网址）或每处要拉开得太多（超过两个字宽），也照常左对齐，免得字被拉得七零八落。
 * 所以分页、续读位置、书签都不受影响：每页放哪些字和左对齐时一模一样。
 */
final class JustifiedText extends TextView {
    private boolean justify;
    /** 这一页最后一行之后这一段还没完（翻到下一页接着）：最后一行也要两端对齐。 */
    private boolean continues;

    JustifiedText(Context c) { super(c); }

    void setJustify(boolean on) { if (on != justify) { justify = on; invalidate(); } }
    void setContinues(boolean on) { if (on != continues) { continues = on; invalidate(); } }
    boolean justify() { return justify; }

    @Override protected void onDraw(Canvas canvas) {
        Layout l = getLayout();
        if (!justify || l == null) { super.onDraw(canvas); return; }
        CharSequence text = l.getText();
        TextPaint p = getPaint();
        p.setColor(getCurrentTextColor());
        p.drawableState = getDrawableState();
        canvas.save();
        canvas.translate(getCompoundPaddingLeft(), getExtendedPaddingTop());
        int top = getScrollY(), bottom = top + getHeight();
        int n = l.getLineCount();
        for (int line = 0; line < n; line++) {
            if (l.getLineBottom(line) < top) continue;
            if (l.getLineTop(line) > bottom) break;
            int s = l.getLineStart(line), e = l.getLineEnd(line);
            int ve = e;                                            // 去掉行尾的换行和空白
            while (ve > s && isTrailingSpace(text.charAt(ve - 1))) ve--;
            boolean paraEnd = e > s && text.charAt(e - 1) == '\n' || line == n - 1 && !continues;
            float left = l.getParagraphLeft(line);                 // 首行缩进（LeadingMarginSpan）已经算在里面
            float avail = l.getParagraphRight(line) - left;
            int base = l.getLineBaseline(line);
            if (paraEnd || ve <= s || !drawJustified(canvas, text, s, ve, left, avail, base, p)) {
                canvas.drawText(text, s, ve, l.getLineLeft(line), base, p);
            }
        }
        canvas.restore();
    }

    /** 画一行两端对齐的字；不适合拉开就返回 false（调用的人照常画）。 */
    private static boolean drawJustified(Canvas c, CharSequence t, int s, int e, float x, float avail, int y, TextPaint p) {
        // 先数能拉开的地方，同时量出自然宽度（按“段”量：两个拉开点之间的字一起量，西文单词的字距不变）
        // 段首用全角空格缩进的（中文 TXT 常见“　　”）：缩进那几个空格不拉开，各段首行缩进一样宽
        int lead = s;
        while (lead < e && t.charAt(lead) == '\u3000') lead++;
        int gaps = 0;
        float natural = 0;
        int runStart = s;
        for (int i = s + 1; i <= e; i++) {
            if (i == e || i > lead && breakBetween(t.charAt(i - 1), t.charAt(i))) {
                natural += p.measureText(t, runStart, i);
                if (i < e) gaps++;
                runStart = i;
            }
        }
        float extra = avail - natural;
        if (gaps == 0 || extra <= 0) return false;
        float per = extra / gaps;
        if (per > 2 * p.getTextSize()) return false;              // 每处要拉开两个字宽以上：这一行左对齐更好看
        runStart = s;
        for (int i = s + 1; i <= e; i++) {
            if (i == e || i > lead && breakBetween(t.charAt(i - 1), t.charAt(i))) {
                c.drawText(t, runStart, i, x, y, p);
                x += p.measureText(t, runStart, i) + per;
                runStart = i;
            }
        }
        return true;
    }

    /** a 和 b 之间能不能拉开：空格后面、中日韩文字的前后（代理对中间、组合附加符号前面不行）。 */
    static boolean breakBetween(char a, char b) {
        if (Character.isHighSurrogate(a) || Character.isLowSurrogate(b)) return false;
        if (Character.getType(b) == Character.NON_SPACING_MARK || Character.getType(b) == Character.ENCLOSING_MARK) return false;
        if (a == '\u00A0' || b == '\u00A0') return false;             // 不断行空格：两边粘在一起
        if (b == ' ') return false;                                // 空格本身算前一个单词的一部分，拉开点在空格后面
        if (a == ' ') return true;
        return cjk(a) || cjk(b);
    }

    private static boolean isTrailingSpace(char c) { return c == '\n' || c == '\r' || c == ' ' || c == '\t'; }

    /** 中日韩文字、假名、注音、全角标点和全角字母（这些字之间都可以均匀拉开）。 */
    static boolean cjk(char c) {
        return c >= 0x2E80 && c <= 0x9FFF      // 部首、CJK 符号与标点（含全角空格、「」《》。、）、假名、注音、统一汉字
            || c >= 0xAC00 && c <= 0xD7AF      // 韩文
            || c >= 0xF900 && c <= 0xFAFF      // 兼容汉字
            || c >= 0xFE30 && c <= 0xFE4F      // 竖排兼容标点
            || c >= 0xFF00 && c <= 0xFFEF;     // 全角 ASCII 与全角标点（，！？：；（））
        // —— …… 和弯引号不算：中英文里都用，算进来英文的 ago—never 会被拉成 ago — never；挨着汉字时汉字那一边照样拉开，两个破折号之间不拉开（—— 不会断开）
    }
}
