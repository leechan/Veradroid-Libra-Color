// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.app.Dialog;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.pdf.PdfRenderer;
import android.os.Bundle;
import android.os.Handler;
import android.os.ParcelFileDescriptor;
import android.os.SystemClock;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.nio.charset.Charset;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * 内置阅读器：TXT/EPUB 按页显示文字，PDF 用系统 PdfRenderer 逐页显示。
 * 左右点按或底部箭头翻页；EPUB 有目录；文字可以调字号；进度记在 App 私有 prefs 里。
 */
public class ReaderActivity extends Activity {
    private String path, ext;
    private TextView title, pageInfo, content;
    private ImageView pdfView;
    private LinearLayout textBox;
    private TextView footLeft;
    private View topBar, bottomBar, aaBtn, bookmarkBox;
    private Icons.IconView bookmarkIcon;
    private TextView pageOverlay;
    private boolean chromeVisible = false;

    private final List<Page> pages = new ArrayList<Page>();
    private final List<Chapter> chapters = new ArrayList<Chapter>();
    private final List<Integer> chapterStart = new ArrayList<Integer>();
    private int page, textSize = 22;
    private String fontPath, fontName = "系统默认", bookTitle = "";
    private float lineSpacing = 1.35f;
    private int marginDp = 24, align = 0;
    /** 段距（字高的倍数，0 = 没有）、首行缩进（字数）、极简全屏（不显示页脚）、点按方式（0 左边上一页 / 1 全屏下一页）。 */
    private float paraSpacing = 0f;
    private int indent = 0, tapMode = 0;
    private boolean minimal;
    /** 方块风格（主页设置里选的界面风格）：点屏幕中间出上下两条工具栏，下面六个按钮各开一张设置单。 */
    private boolean blk;
    private View blkTop, blkBottom, openCard, footView;
    private LinearLayout sheetBox;
    private TextView blkTitle, blkClock;
    private View[] toolMarks;
    private int sheetOpen = -1;
    private boolean isPdf;
    private volatile PdfRenderer pdf;
    private volatile ParcelFileDescriptor pfd;
    private int pdfPages;
    private Bitmap pdfBitmap;
    private volatile int pdfGen;
    private volatile boolean gone;   // onDestroy 之后：排队的 PDF 活不再做
    private final java.util.concurrent.ExecutorService pdfWorker = java.util.concurrent.Executors.newSingleThreadExecutor();
    private final Handler ui = new Handler();
    private long readStarted;
    private int readPages;
    /** 分页还没做完时先显示的那一页（从上次的位置直接排出来）：章、起止字符位置。 */
    private Chapter provChapter;
    private int provIndex = -1, provStart, provEnd;
    private boolean firstShown;
    private int availH;
    private String leftBase = "";

    private static class Chapter { String title; String text; String entry; }   // entry = EPUB 里这一章的文件名（续读时先只读这一章）
    private static class Page { int chapter; int start; String text; }   // start = 这一页在章节文字里的起始字符位置

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        getWindow().setWindowAnimations(0);
        // 主题是“半透明”的，只为了不要系统先画一张白色的启动窗口（墨水屏上就是先闪一页空白）；窗口本身不透明，
        // 第一页画出来以后再转成普通的全屏 Activity（见 frameShown）
        getWindow().setFormat(android.graphics.PixelFormat.OPAQUE);
        openedAt = SystemClock.uptimeMillis();
        path = getIntent().getStringExtra("path");
        if (path == null) { finish(); return; }
        String name = new File(path).getName();
        int dot = name.lastIndexOf('.');
        ext = dot > 0 ? name.substring(dot + 1).toLowerCase(Locale.US) : "";
        loadStyle();
        blk = Blocks.on(this);

        // 整页是一层正文，工具栏盖在它上面（点屏幕顶部才出现）：出不出工具栏正文都不重排，墨水屏只刷工具栏那两条。
        FrameLayout pageView = new FrameLayout(this);
        pageView.setBackgroundColor(Color.WHITE);
        setContentView(pageView);
        Perf.measure(pageView, "reader");

        FrameLayout holder = new FrameLayout(this);
        pageView.addView(holder, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        content = Ui.text(this, "", textSize, false);
        content.setLineSpacing(0, lineSpacing);
        content.setGravity(Gravity.TOP | Gravity.START);
        applyStyle();
        content.setClickable(true);
        content.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { turnAt(v); }
        });
        holder.addView(content, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        pdfView = new ImageView(this);
        pdfView.setScaleType(ImageView.ScaleType.FIT_CENTER);
        pdfView.setVisibility(View.GONE);
        // PDF 时正文 TextView 是 GONE：图片上也要能点按翻页、叫出工具栏
        pdfView.setClickable(true);
        pdfView.setOnClickListener(new View.OnClickListener() {
            @Override public void onClick(View v) { turnAt(v); }
        });
        holder.addView(pdfView, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        // 页脚（一直在）：左边“本章还剩几页”，右边“第几页 / 共几页 · 百分比”，和 Kindle 左下角的阅读进度一个意思
        LinearLayout foot = new LinearLayout(this);
        foot.setOrientation(LinearLayout.HORIZONTAL);
        foot.setPadding(dp(marginDp), 0, dp(marginDp), dp(6));
        footLeft = Ui.text(this, "", 12, false);
        footLeft.setSingleLine(true);
        foot.addView(footLeft, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        pageOverlay = Ui.text(this, "", 12, false);
        foot.addView(pageOverlay);
        holder.addView(foot, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));
        footView = foot;
        if (minimal) foot.setVisibility(View.INVISIBLE);

        // 顶部工具栏：返回、书名、Aa（字体和版式）、转到（目录 / 书签 / 位置）、书签
        LinearLayout topBox = new LinearLayout(this);
        topBox.setOrientation(LinearLayout.VERTICAL);
        topBox.setBackgroundColor(Color.WHITE);
        topBox.setClickable(true);
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(dp(8), dp(22), dp(8), dp(6));   // 上面 18dp 是状态栏那一条
        top.addView(Icons.bar(this, Icons.Kind.BACK, 30, new View.OnClickListener() {
            @Override public void onClick(View v) { finish(); overridePendingTransition(0, 0); }
        }));
        title = Ui.text(this, dot > 0 ? name.substring(0, dot) : name, 18, true);
        title.setPadding(dp(8), 0, dp(6), 0);
        title.setMaxLines(1);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        top.addView(title, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        aaBtn = Icons.bar(this, Icons.Kind.FONT, 30, new View.OnClickListener() {
            @Override public void onClick(View v) { displayDialog(); }
        });
        top.addView(aaBtn);
        top.addView(Icons.bar(this, Icons.Kind.TOC, 30, new View.OnClickListener() {
            @Override public void onClick(View v) { gotoDialog(); }
        }));
        View bm = Icons.bar(this, Icons.Kind.BOOKMARK, 30, new View.OnClickListener() {
            @Override public void onClick(View v) { toggleBookmark(); }
        });
        bookmarkIcon = (Icons.IconView) ((ViewGroup) bm).getChildAt(0);
        bookmarkIcon.setDuplicateParentStateEnabled(false);
        bookmarkBox = bm;
        top.addView(bm);
        topBox.addView(top);
        topBox.addView(Ui.rule(this, 2, Color.BLACK));
        topBar = topBox;
        topBox.setVisibility(View.GONE);
        pageView.addView(topBox, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP));

        // 底部工具栏：上一页 / 位置 / 下一页
        LinearLayout bottomBox = new LinearLayout(this);
        bottomBox.setOrientation(LinearLayout.VERTICAL);
        bottomBox.setBackgroundColor(Color.WHITE);
        bottomBox.setClickable(true);
        bottomBox.addView(Ui.rule(this, 2, Color.BLACK));
        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.HORIZONTAL);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setPadding(dp(12), dp(4), dp(12), dp(8));
        bottom.addView(Icons.bar(this, Icons.Kind.BACK, 34, new View.OnClickListener() {
            @Override public void onClick(View v) { prev(); }
        }));
        pageInfo = Ui.text(this, "", 15, false);
        pageInfo.setGravity(Gravity.CENTER);
        bottom.addView(pageInfo, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        bottom.addView(Icons.bar(this, Icons.Kind.CHEV_R, 34, new View.OnClickListener() {
            @Override public void onClick(View v) { next(); }
        }));
        bottomBox.addView(bottom);
        bottomBar = bottomBox;
        bottomBox.setVisibility(View.GONE);
        pageView.addView(bottomBox, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));

        content.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
            @Override public void onLayoutChange(View v, int l, int t, int r, int b, int ol, int ot, int or, int ob) {
                int hh = b - t;
                if (hh <= 0 || hh == (availH > 0 ? availH : getResources().getDisplayMetrics().heightPixels)) return;
                android.util.Log.i("VeraHome", "reader: text area " + hh + " px, screen " + getResources().getDisplayMetrics().heightPixels);
                availH = hh;
                if (!pages.isEmpty()) v.post(new Runnable() { @Override public void run() { rebuildKeepPosition(); } });
            }
        });
        if (blk) buildBlocksChrome(pageView, dot > 0 ? name.substring(0, dot) : name);
        // 方块风格：第一页慢（大书、模拟器）时不让上一屏一直停着，最多等 1.5 秒就先出一张“正在打开”的卡片
        holdFirstFrame(pageView, blk ? Math.min(1500, holdMs()) : holdMs());
        load();
    }

    /**
     * 打开书时窗口先不画（最多等 ms 毫秒），等第一页的字排好了再画：墨水屏上只刷一次，直接出字。
     * 以前先画一页空白，整本书分完页（1 秒多）再出字，是两次刷新。
     */
    private long holdUntil;
    private void holdFirstFrame(final View root, long ms) {
        holdUntil = SystemClock.uptimeMillis() + ms;
        ui.postDelayed(new Runnable() { @Override public void run() { firstShown = true; root.invalidate(); } }, ms + 50);
        Perf.whenAttached(root, new Runnable() { @Override public void run() {
            root.getViewTreeObserver().addOnPreDrawListener(new android.view.ViewTreeObserver.OnPreDrawListener() {
                @Override public boolean onPreDraw() {
                    if (!firstShown && SystemClock.uptimeMillis() < holdUntil) return false;
                    root.getViewTreeObserver().removeOnPreDrawListener(this);
                    frameShown();
                    return true;
                }
            });
        } });
    }

    /** 最多等第一页多久（毫秒）。调试时可以用属性 debug.vd.readerhold 改（模拟器比真机慢几倍）。 */
    private static int holdMs() {
        try { return (Integer) Class.forName("android.os.SystemProperties").getMethod("getInt", String.class, int.class).invoke(null, "debug.vd.readerhold", 4000); }
        catch (Throwable t) { return 4000; }
    }

    /** 书库正在打开阅读器：桌面暂停时先不放出状态栏，等阅读器第一页一起画（墨水屏上少一次顶边的小刷新）。 */
    static volatile boolean opening;

    private long openedAt;
    private volatile String firstTiming = "";
    private boolean framed;

    /** 第一页要画了：状态栏这时才出来（和第一页同一次刷新），然后转回不透明的全屏 Activity，让桌面正常停下。 */
    private void frameShown() {
        if (framed) return;
        framed = true;
        opening = false;
        android.util.Log.i("VeraPerf", "reader first page ready " + (SystemClock.uptimeMillis() - openedAt) + " ms after onCreate" + (firstShown ? "" : " (timed out)") + firstTiming);
        if (resumedNow) { StatusBarService.setSuppressed(false); StatusBarService.refresh(this); }
        ui.post(new Runnable() { @Override public void run() {
            try { Activity.class.getMethod("convertFromTranslucent").invoke(ReaderActivity.this); } catch (Throwable ignored) { }
        } });
    }
    private boolean resumedNow;

    /** 分页用的画笔、宽、高：主线程上取好，后台线程只读。 */
    private static final class Geometry {
        android.text.TextPaint tp; int w, h; android.text.Layout.Alignment al; String sig; int indentPx, paraPx;
    }

    private Geometry geometry() {
        Geometry g = new Geometry();
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        g.tp = new android.text.TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG);
        g.tp.setTypeface(typeface());
        g.tp.setTextSize(textSize * dm.scaledDensity);
        g.w = Math.max(200, dm.widthPixels - 2 * dp(marginDp));
        // 正文区域高度：隐藏工具栏时正文占满整屏（上边距 dp(34) 给状态栏，下边距 dp(30) 给页脚）。
        // 打开书时正文还没排版，先按屏幕高度算；排版后实际高度不一样才改（见 onCreate 里的监听），前后用的是同一个数。
        int viewH = availH > 0 ? availH : dm.heightPixels;
        g.h = Math.max(240, viewH - dp(34) - dp(30));
        g.al = align == 1 ? android.text.Layout.Alignment.ALIGN_CENTER : android.text.Layout.Alignment.ALIGN_NORMAL;
        g.sig = textSize + "|" + lineSpacing + "|" + marginDp + "|" + align + "|" + fontPath + "|" + g.w + "x" + g.h + (indent > 0 || paraSpacing > 0 ? "|" + indent + "|" + paraSpacing : "");
        g.indentPx = Math.round(indent * textSize * dm.scaledDensity);
        g.paraPx = Math.round(paraSpacing * textSize * dm.scaledDensity);
        return g;
    }

    /**
     * 后台读书。续读的书先只排上次停下的那一页（TXT：读全文后从记下的字符位置排一页；EPUB：只读那一章），
     * 马上显示；整本书再在后台分页，分完后页码对上，屏幕上的字不变。
     */
    private void load() {
        final File f = new File(path);
        final Geometry g = isPdfExt() ? null : geometry();
        final SharedPreferences p = prefs();
        final boolean hasPos = p.contains("c:" + path);
        final int c0 = p.getInt("c:" + path, 0), o0 = p.getInt("o:" + path, 0);
        final String entry0 = p.getString("e:" + path, null);
        final boolean fresh = !p.contains("p:" + path);          // 没打开过：从头排第一页
        final String savedSig = p.getString("st:" + path, ""), savedLeft = p.getString("fl:" + path, "");
        final int savedPg = p.getInt("p:" + path, 0), savedTotal = p.getInt("t:" + path, 0);
        new Thread(new Runnable() {
            @Override public void run() {
                try {
                    long t0 = SystemClock.uptimeMillis();
                    // 书名书库里已经有了（Intent 带过来），不为它先解析一遍 EPUB 的 OPF
                    String given = getIntent().getStringExtra("title");
                    if (given != null && given.trim().length() > 0) bookTitle = given.trim();
                    else { String bt = Books.info(f).title; if (bt != null && bt.trim().length() > 0) bookTitle = bt; }
                    if (isPdfExt()) {
                        // 打开和第一页都放在 pdfWorker 上做：onDestroy 只等这条线程做完才关文档。
                        // 以前在这条加载线程里渲染，开着大 PDF 马上返回时，文档会在渲染途中被关掉（原生层崩溃）
                        final Bitmap first;
                        try {
                            first = pdfWorker.submit(new java.util.concurrent.Callable<Bitmap>() {
                                @Override public Bitmap call() throws Exception {
                                    if (gone) throw new Exception("已关闭");
                                    openPdf(f);
                                    return renderPdf(page);
                                }
                            }).get();
                        } catch (java.util.concurrent.ExecutionException e) { throw e.getCause(); }
                        ui.post(new Runnable() { @Override public void run() { showPdfFirst(first); } });
                        return;
                    }
                    List<Chapter> all = null;
                    Chapter first = null;
                    int firstIdx = 0, from = 0;
                    if ("epub".equals(ext)) {
                        if (hasPos && entry0 != null) { first = loadEpubChapter(f, entry0); firstIdx = c0; from = o0; }
                        else if (fresh) { all = loadEpub(f); if (!all.isEmpty()) first = all.get(0); }
                    } else {
                        Chapter c = new Chapter();
                        c.title = f.getName();
                        c.text = readText(f);
                        if (c.text.trim().length() == 0) throw new Exception("这是一个空文件");
                        all = new ArrayList<Chapter>();
                        all.add(c);
                        if (hasPos || fresh) { first = c; from = hasPos ? o0 : 0; }
                    }
                    if (first != null && from >= 0 && from < first.text.length()) {
                        long t1 = SystemClock.uptimeMillis();
                        final Chapter fc = first; final int fi = firstIdx, start = skipBreaks(first.text, from);
                        final int end = pageEnd(first.text, start, g);
                        firstTiming = ": read " + (t1 - t0) + " ms, one page " + (SystemClock.uptimeMillis() - t1) + " ms";
                        // 排版条件和上次存进度时一样：页码、本章剩几页直接用存下的，分完页以后也是这几个数，页脚不会再变
                        final boolean same = g.sig.equals(savedSig) && start == o0 && fi == c0;
                        ui.post(new Runnable() { @Override public void run() {
                            showFirst(fc, fi, start, end, same ? savedPg : -1, same ? savedTotal : 0, same ? savedLeft : "");
                        } });
                    }
                    if (all == null) all = loadEpub(f);
                    if (all.isEmpty()) throw new Exception("EPUB 里没有可读的章节");
                    final List<Chapter> chs = all;
                    final List<Page> pg = new ArrayList<Page>();
                    final List<Integer> starts = new ArrayList<Integer>();
                    long tp0 = SystemClock.uptimeMillis();
                    paginate(chs, g, pg, starts);
                    android.util.Log.i("VeraPerf", "reader whole book: " + pg.size() + " pages in " + (SystemClock.uptimeMillis() - tp0) + " ms (background)");
                    ui.post(new Runnable() { @Override public void run() { installPages(chs, pg, starts, g.sig); } });
                } catch (Throwable t) {
                    final String msg = String.valueOf(t.getMessage());
                    ui.post(new Runnable() {
                        @Override public void run() {
                            opened();
                            content.setText("打不开这本书：\n\n" + msg);
                            content.setVisibility(View.VISIBLE);
                            firstShown = true;
                        }
                    });
                }
            }
        }, "reader-load").start();
    }

    private boolean isPdfExt() { return "pdf".equals(ext); }

    /** 分页之前先显示的那一页。 */
    private void showFirst(Chapter c, int idx, int start, int end, int savedPage, int savedTotal, String left) {
        if (isDestroyed() || !pages.isEmpty()) return;
        opened();
        provChapter = c; provIndex = idx; provStart = start; provEnd = end;
        content.setVisibility(View.VISIBLE);
        pdfView.setVisibility(View.GONE);
        content.setText(styled(c.text, start, end));
        if (bookTitle.length() > 0) title.setText(bookTitle);
        if (savedPage >= 0 && savedTotal > 0) {
            int pg = Math.min(savedPage, savedTotal - 1);
            String right = (pg + 1) + " / " + savedTotal + " · " + Math.min(100, (pg + 1) * 100 / savedTotal) + "%";
            footLeft.setText(left);
            pageOverlay.setText(right);
            pageInfo.setText(right);
            firstShown = true;
        } else {
            // 页码还不知道（第一次打开、或者改过字号）：分页多半很快就完，稍等一下让页码和字一起出来；等不到就先出字
            ui.postDelayed(new Runnable() { @Override public void run() { firstShown = true; content.invalidate(); } }, 300);
        }
    }

    /** 整本书分好页了：换上真正的页表，找到正显示的那一页。字没变就只对一下页码（通常和已经显示的一样，屏幕不动）。 */
    private void installPages(List<Chapter> chs, List<Page> pg, List<Integer> starts, String sig) {
        if (isDestroyed()) return;
        opened();
        chapters.clear(); chapters.addAll(chs);
        pages.clear(); pages.addAll(pg);
        chapterStart.clear(); chapterStart.addAll(starts);
        isPdf = false;
        if (pages.isEmpty()) { firstShown = true; return; }
        if (provIndex >= 0) page = pageAt(provIndex, provStart);
        else page = savedTextPage();
        boolean sameText = provIndex >= 0 && pages.get(page).chapter == provIndex && pages.get(page).start == provStart
            && pages.get(page).text.equals(String.valueOf(content.getText()));
        provChapter = null; provIndex = -1;
        if (!sig.equals(geometry().sig)) { rebuildKeepPosition(); firstShown = true; return; }   // 分页时改了字号等
        if (sameText) { paintProgress(); savePage(); }
        else showText();
        firstShown = true;
    }

    // ------------------------------------------------------------------ turning

    private void prev() {
        if (isPdf) {
            if (page > 0) { page--; readPages++; showPdf(page); }
        } else if (page > 0) { page--; readPages++; showText(); }
    }

    private void next() {
        if (isPdf) {
            if (page < pdfPages - 1) { page++; readPages++; showPdf(page); }
        } else if (pages.isEmpty() && provChapter != null && provEnd < provChapter.text.length()) {
            // 整本还没分完页：从这一页的末尾接着排下一页（页码等分完再显示）
            Geometry g = geometry();
            int start = skipBreaks(provChapter.text, provEnd);
            if (start >= provChapter.text.length()) return;
            provStart = start; provEnd = pageEnd(provChapter.text, start, g);
            readPages++;
            content.setText(styled(provChapter.text, provStart, provEnd));
            footLeft.setText(""); pageOverlay.setText(""); pageInfo.setText("");
        } else if (page < pages.size() - 1) { page++; readPages++; showText(); }
    }

    /**
     * 点按区域和 Kindle 一样：屏幕最上面一条 = 叫出 / 收起工具栏；左边四分之一 = 上一页；其余 = 下一页。
     * 工具栏开着时点正文任何地方都是收起它。
     */
    private void turnAt(View v) {
        float w = v.getWidth(), h = v.getHeight();
        if (chromeVisible) { toggleChrome(); return; }
        if (lastX < 0 || w <= 0) { next(); return; }
        // 方块风格：点屏幕中间一块叫出工具栏（顶上一条也算）
        if (blk && lastX > w / 3f && lastX < w * 2 / 3f && lastY > h / 4f && lastY < h * 3 / 4f) { toggleChrome(); return; }
        if (tapMode == 1 && lastY >= h * 0.14f) { next(); return; }
        if (lastY < h * 0.14f) toggleChrome();
        else if (lastX < w / 4f) prev();
        else next();
    }
    private float lastX = -1, lastY = -1;
    private boolean swiped;
    /** 左右划翻页：往左划下一页，往右划上一页；抬手时翻一次，不跟手。 */
    @Override public boolean dispatchTouchEvent(android.view.MotionEvent e) {
        Perf.touch(e);
        int slop = android.view.ViewConfiguration.get(this).getScaledTouchSlop() * 4;
        switch (e.getActionMasked()) {
        case android.view.MotionEvent.ACTION_DOWN: lastX = e.getX(); lastY = e.getY(); swiped = false; break;
        case android.view.MotionEvent.ACTION_MOVE:
            if (!swiped && !chromeVisible && Math.abs(e.getX() - lastX) > slop && Math.abs(e.getX() - lastX) > 2 * Math.abs(e.getY() - lastY)) {
                swiped = true;
                android.view.MotionEvent c = android.view.MotionEvent.obtain(e);
                c.setAction(android.view.MotionEvent.ACTION_CANCEL);
                super.dispatchTouchEvent(c);
                c.recycle();
            }
            if (swiped) return true;
            break;
        case android.view.MotionEvent.ACTION_UP:
            if (swiped) { if (e.getX() < lastX) next(); else prev(); swiped = false; return true; }
            break;
        case android.view.MotionEvent.ACTION_CANCEL: if (swiped) { swiped = false; return true; } break;
        }
        return super.dispatchTouchEvent(e);
    }

    private void toggleChrome() {
        chromeVisible = !chromeVisible;
        int v = chromeVisible ? View.VISIBLE : View.GONE;
        if (blk) {
            if (chromeVisible) paintBlocksTop(); else openSheet(-1);
            blkTop.setVisibility(v);
            blkBottom.setVisibility(v);
            return;
        }
        if (chromeVisible) paintBookmark();
        topBar.setVisibility(v);
        bottomBar.setVisibility(v);
    }

    /** 页脚和底栏的文字：第几页 / 共几页 · 百分比；本章还剩几页（读了几页以后按这次的速度估个时间）。 */
    private void paintProgress() {
        int total = isPdf ? pdfPages : pages.size();
        if (total <= 0) return;
        int pct = Math.min(100, (page + 1) * 100 / total);
        String right = (page + 1) + " / " + total + " · " + pct + "%";
        String left = "";
        leftBase = "";
        if (!isPdf && !pages.isEmpty() && chapterStart.size() > 1) {
            int ch = pages.get(Math.max(0, Math.min(pages.size() - 1, page))).chapter;
            int end = ch + 1 < chapterStart.size() ? chapterStart.get(ch + 1) : pages.size();
            int remain = Math.max(0, end - page - 1);
            left = remain == 0 ? "本章最后一页" : "本章还剩 " + remain + " 页";
            leftBase = left;
            long spent = readStarted > 0 ? SystemClock.elapsedRealtime() - readStarted : 0;
            if (remain > 0 && readPages >= 5 && spent > 0) {
                long mins = Math.round(remain * (spent / (double) readPages) / 60000.0);
                if (mins >= 1 && mins < 600) left += "，约 " + mins + " 分钟";
            }
        }
        if (!left.equals(String.valueOf(footLeft.getText()))) footLeft.setText(left);
        if (!right.equals(String.valueOf(pageOverlay.getText()))) pageOverlay.setText(right);
        if (!right.equals(String.valueOf(pageInfo.getText()))) pageInfo.setText(right);
        if (chromeVisible) paintBookmark();
    }

    // ------------------------------------------------------------------ bookmarks / go to

    /** 书签存在 reader 偏好的 bm:<路径> 里：文字书是“章:字符位置”，PDF 是页码，分号隔开。 */
    private List<String> bookmarks() {
        List<String> out = new ArrayList<String>();
        for (String x : prefs().getString("bm:" + path, "").split(";")) if (x.length() > 0) out.add(x);
        return out;
    }

    private String bookmarkKey() {
        if (isPdf) return String.valueOf(page);
        if (pages.isEmpty()) return null;
        Page p = pages.get(Math.max(0, Math.min(pages.size() - 1, page)));
        return p.chapter + ":" + p.start;
    }

    private int bookmarkPage(String key) {
        try {
            if (isPdf) return Math.max(0, Math.min(pdfPages - 1, Integer.parseInt(key)));
            String[] f = key.split(":");
            return pageAt(Integer.parseInt(f[0]), Integer.parseInt(f[1]));
        } catch (Throwable t) { return -1; }
    }

    private boolean bookmarkedHere() {
        for (String k : bookmarks()) if (bookmarkPage(k) == page) return true;
        return false;
    }

    /** 这一页有书签时图标画成黑底白线。 */
    private void paintBookmark() {
        boolean on = bookmarkedHere();
        bookmarkIcon.setInverted(on);
        if (on) {
            android.graphics.drawable.GradientDrawable g = new android.graphics.drawable.GradientDrawable();
            g.setColor(Color.BLACK);
            g.setCornerRadius(dp(8));
            bookmarkBox.setBackground(g);
        } else bookmarkBox.setBackground(null);
    }

    private void toggleBookmark() {
        String key = bookmarkKey();
        if (key == null) return;
        List<String> l = bookmarks();
        boolean had = false;
        for (java.util.Iterator<String> it = l.iterator(); it.hasNext(); ) if (bookmarkPage(it.next()) == page) { it.remove(); had = true; }
        if (!had) l.add(key);
        StringBuilder sb = new StringBuilder();
        for (String k : l) { if (sb.length() > 0) sb.append(';'); sb.append(k); }
        prefs().edit().putString("bm:" + path, sb.toString()).apply();
        paintBookmark();
    }

    private void jump(int to) {
        int total = isPdf ? pdfPages : pages.size();
        if (total <= 0) return;
        page = Math.max(0, Math.min(total - 1, to));
        if (chromeVisible) toggleChrome();
        if (isPdf) showPdf(page); else showText();
    }

    /** “转到”：目录、书签、按位置跳。 */
    private void gotoDialog() {
        final int total = isPdf ? pdfPages : pages.size();
        if (total <= 0) return;
        final List<String> items = new ArrayList<String>();
        final List<Runnable> acts = new ArrayList<Runnable>();
        if (!isPdf && chapters.size() > 1) { items.add("目录（" + chapters.size() + " 章）"); acts.add(new Runnable() { @Override public void run() { showToc(); } }); }
        final List<String> bms = bookmarks();
        if (!bms.isEmpty()) { items.add("书签（" + bms.size() + " 个）"); acts.add(new Runnable() { @Override public void run() { bookmarkDialog(); } }); }
        items.add("开头"); acts.add(new Runnable() { @Override public void run() { jump(0); } });
        for (final int pc : new int[] { 10, 25, 50, 75, 90 }) {
            items.add("跳到 " + pc + "%"); acts.add(new Runnable() { @Override public void run() { jump(total * pc / 100); } });
        }
        new VeraDialog.Builder(this).title("转到").items(items.toArray(new String[0]), new VeraDialog.OnPick() {
            @Override public void onPick(int which) { acts.get(which).run(); }
        }).negative("取消", null).show();
    }

    private void bookmarkDialog() {
        final List<String> bms = bookmarks();
        final List<Integer> at = new ArrayList<Integer>();
        List<String> names = new ArrayList<String>();
        int total = isPdf ? pdfPages : pages.size();
        for (String k : bms) {
            int pg = bookmarkPage(k);
            if (pg < 0) continue;
            String label = "第 " + (pg + 1) + " 页 · " + ((pg + 1) * 100 / Math.max(1, total)) + "%";
            if (!isPdf && pg < pages.size()) {
                String t = pages.get(pg).text.replace('\n', ' ').trim();
                label += "  " + (t.length() > 18 ? t.substring(0, 18) + "…" : t);
            }
            names.add(label);
            at.add(pg);
        }
        new VeraDialog.Builder(this).title("书签").items(names.toArray(new String[0]), new VeraDialog.OnPick() {
            @Override public void onPick(int which) { jump(at.get(which)); }
        }).negative("取消", null).show();
    }

    private void showText() {
        if (pages.isEmpty()) return;
        Page p = pages.get(Math.max(0, Math.min(pages.size() - 1, page)));
        applyStyle();
        content.setText(indent > 0 || paraSpacing > 0 ? styled(chapters.get(p.chapter).text, p.start, p.start + p.text.length()) : p.text);
        paintProgress();
        if (blk && chromeVisible) paintBlocksTop();
        if (bookTitle.length() > 0 && !bookTitle.equals(String.valueOf(title.getText()))) title.setText(bookTitle);
        savePage();
    }

    private void setTextSize(int v) {
        int n = Math.max(16, Math.min(34, v));
        if (n == textSize) return;
        // PDF、打不开的书、还在加载的书都没有分页：只记下字号。以前这里会 chapterStart.get(-1)，
        // 整个桌面进程（状态栏、导航栏、传书）跟着一起崩。
        if (isPdf || pages.isEmpty() || chapterStart.isEmpty()) { textSize = n; saveStyle(); return; }
        textSize = n;
        saveStyle();
        rebuildKeepPosition();
    }

    /** 章节 + 字符位置所在的那一页（重新分页后也是同一段文字）。 */
    private int pageAt(int chapter, int offset) {
        if (pages.isEmpty() || chapterStart.isEmpty()) return 0;
        chapter = Math.max(0, Math.min(chapterStart.size() - 1, chapter));
        int from = chapterStart.get(chapter);
        int to = chapter + 1 < chapterStart.size() ? chapterStart.get(chapter + 1) : pages.size();
        int best = Math.min(from, pages.size() - 1);
        for (int i = from; i < to; i++) { if (pages.get(i).start <= offset) best = i; else break; }
        return Math.max(0, Math.min(pages.size() - 1, best));
    }

    /** 在主线程上把整本重新分页（改了字号 / 行距 / 边距 / 字体时）。 */
    private void buildPages() {
        List<Page> pg = new ArrayList<Page>();
        List<Integer> starts = new ArrayList<Integer>();
        paginate(chapters, geometry(), pg, starts);
        pages.clear(); pages.addAll(pg);
        chapterStart.clear(); chapterStart.addAll(starts);
    }

    /** 跳过页首的空行（每页都不以空行开头）。 */
    private static int skipBreaks(String s, int i) {
        while (i < s.length() && (s.charAt(i) == '\n' || s.charAt(i) == '\r')) i++;
        return i;
    }

    /**
     * 从 i 开始一页放得下的文字到哪里为止：用和正文 TextView 相同的画笔、宽度、行距排一遍，取放得下的整行。
     * 以前按“每页多少字”估算，不算换行：短段落 / 对话多的书每页末尾几行被裁掉。
     */
    private int pageEnd(String s, int i, Geometry g) {
        android.util.DisplayMetrics dm = getResources().getDisplayMetrics();
        float px = textSize * dm.scaledDensity;
        int perLine = Math.max(6, (int) (g.w / (px * fontWidth())));
        int lines = Math.max(3, (int) (g.h / (px * lineSpacing)));
        int cpp = Math.max(220, Math.min(1400, perLine * lines));      // 只用来决定每次取多长一段去排版
        int win = cpp * 2;
        int end;
        while (true) {
            int stop = Math.min(s.length(), i + win);
            CharSequence src = s; int from = i, to = stop;
            if (g.indentPx > 0 || g.paraPx > 0) { src = spans(s, i, stop, g.indentPx, g.paraPx); from = 0; to = src.length(); }
            android.text.StaticLayout sl = android.text.StaticLayout.Builder.obtain(src, from, to, g.tp, g.w)
                .setAlignment(g.al).setLineSpacing(0f, lineSpacing).setIncludePad(true)
                .setBreakStrategy(android.text.Layout.BREAK_STRATEGY_SIMPLE)
                .setHyphenationFrequency(android.text.Layout.HYPHENATION_FREQUENCY_NONE).build();
            int fit = 0;                                         // 完整放得下的行数
            int lc = sl.getLineCount();
            while (fit < lc && sl.getLineBottom(fit) <= g.h) fit++;
            if (fit >= lc && stop < s.length() && win < 20000) { win *= 2; continue; }   // 这一段全放下了还有余：取长一点再排
            if (fit <= 0) fit = 1;                               // 一行都放不下（字号极大）也要前进
            int le = sl.getLineEnd(fit - 1);
            if (sl.getLineStart(0) != i) le += i;                  // 行偏移是相对这一段的还是相对全文的，按第一行的起点判断
            end = fit >= lc ? stop : le;
            break;
        }
        if (end <= i) end = Math.min(s.length(), i + 1);
        return end;
    }

    /** 整本分页（后台线程也能调：只读 chs 和 g）。 */
    private void paginate(List<Chapter> chs, Geometry g, List<Page> out, List<Integer> starts) {
        for (int ci = 0; ci < chs.size(); ci++) {
            String s = chs.get(ci).text;
            int i = 0;
            starts.add(out.size());
            while (i < s.length()) {
                i = skipBreaks(s, i);
                if (i >= s.length()) break;
                int end = pageEnd(s, i, g);
                Page p = new Page();
                p.chapter = ci;
                p.start = i;
                p.text = trimEnd(s.substring(i, end));
                if (p.text.length() > 0) out.add(p);
                i = end;
            }
        }
    }

    private static String trimEnd(String t) {
        int e = t.length();
        while (e > 0 && (t.charAt(e - 1) == '\n' || t.charAt(e - 1) == '\r' || t.charAt(e - 1) == ' ')) e--;
        return t.substring(0, e);
    }

    private void showToc() {
        if (chapters.size() <= 1) return;
        String[] titles = new String[chapters.size()];
        for (int i = 0; i < titles.length; i++) titles[i] = chapters.get(i).title;
        new VeraDialog.Builder(this)
            .title("目录")
            .items(titles, new VeraDialog.OnPick() {
                @Override public void onPick(int which) {
                    jump(chapterStart.get(Math.max(0, Math.min(chapterStart.size() - 1, which))));
                }
            }).show();
    }

    // ------------------------------------------------------------------ pdf

    private void openPdf(File f) throws Exception {
        pfd = ParcelFileDescriptor.open(f, ParcelFileDescriptor.MODE_READ_ONLY);
        pdf = new PdfRenderer(pfd);
        pdfPages = pdf.getPageCount();
        page = Math.max(0, Math.min(pdfPages - 1, savedPage()));
    }

    /** 后台线程渲染一页 PDF（按页面比例缩到屏幕大小）。 */
    private Bitmap renderPdf(int index) {
        int w = getResources().getDisplayMetrics().widthPixels, h = getResources().getDisplayMetrics().heightPixels;
        PdfRenderer.Page p = pdf.openPage(index);
        try {
            float sc = Math.min(w / (float) p.getWidth(), h / (float) p.getHeight());
            Bitmap bm = Bitmap.createBitmap(Math.max(1, Math.round(p.getWidth() * sc)), Math.max(1, Math.round(p.getHeight() * sc)), Bitmap.Config.ARGB_8888);
            bm.eraseColor(Color.WHITE);
            p.render(bm, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY);
            return bm;
        } finally { p.close(); }
    }

    /** PDF 第一页：图和页码一起出来。 */
    private void showPdfFirst(Bitmap bm) {
        if (isDestroyed()) { bm.recycle(); return; }
        opened();
        isPdf = true;
        content.setVisibility(View.GONE);
        pdfView.setVisibility(View.VISIBLE);
        aaBtn.setVisibility(View.GONE);
        if (bookTitle.length() > 0) title.setText(bookTitle);
        pdfBitmap = bm;
        pdfView.setImageBitmap(bm);
        paintProgress();
        savePage();
        firstShown = true;
    }

    private void showPdf(final int index) {
        if (pdf == null) return;
        isPdf = true;
        paintProgress();
        final int gen = ++pdfGen;
        // 一个线程按顺序渲染：PdfRenderer 同时只能开一页，以前连点两下两个线程同时 openPage，第二个报“渲染失败”。
        pdfWorker.execute(new Runnable() {
            @Override public void run() {
                if (gen != pdfGen) return;          // 已经又翻走了：这一页不用渲染
                try {
                    // 按页面原来的宽高比缩放（以前直接画满屏幕，不是 3:4 的页面被拉伸）
                    final Bitmap bm = renderPdf(index);
                    ui.post(new Runnable() {
                        @Override public void run() {
                            if (gen != pdfGen || isDestroyed()) { bm.recycle(); return; }
                            Bitmap old = pdfBitmap;
                            pdfBitmap = bm;
                            pdfView.setImageBitmap(bm);
                            if (old != null && old != bm && !old.isRecycled()) old.recycle();
                        }
                    });
                } catch (Throwable t) {
                    final String msg = String.valueOf(t.getMessage());
                    ui.post(new Runnable() { @Override public void run() { VeraToast.show(ReaderActivity.this, "PDF 渲染失败：" + msg); } });
                }
            }
        });
        savePage();
    }

    // ------------------------------------------------------------------ text extraction

    private static String readText(File f) throws Exception {
        long len = f.length();
        if (len > 8 * 1024 * 1024) throw new Exception("文件太大（超过 8 MB）");
        byte[] b = new byte[(int) len];
        FileInputStream in = new FileInputStream(f);
        int n = 0;
        while (n < b.length) { int r = in.read(b, n, b.length - n); if (r < 0) break; n += r; }
        in.close();
        String s = new String(b, 0, n, Charset.forName("UTF-8"));
        int bad = 0;
        for (int i = 0; i < s.length(); i++) if (s.charAt(i) == '\uFFFD') bad++;
        if (bad > s.length() / 200 + 3) {
            try { s = new String(b, 0, n, Charset.forName("GBK")); } catch (Throwable ignored) { }
        }
        return s.replace("\r\n", "\n").replace('\r', '\n');
    }

    private static List<Chapter> loadEpub(File f) throws Exception {
        ZipFile z = new ZipFile(f);
        try {
            String opf = null;
            String container = readEntry(z, "META-INF/container.xml");
            if (container != null) opf = attr(container, "rootfile", "full-path");
            if (opf == null) {
                Enumeration<? extends ZipEntry> en = z.entries();
                while (en.hasMoreElements()) {
                    String n = en.nextElement().getName();
                    if (n.toLowerCase(Locale.US).endsWith(".opf")) { opf = n; break; }
                }
            }
            if (opf == null) throw new Exception("EPUB 缺少 OPF");
            String opfXml = readEntry(z, opf);
            if (opfXml == null) throw new Exception("EPUB 的 OPF 读不到");
            String base = opf.contains("/") ? opf.substring(0, opf.lastIndexOf('/') + 1) : "";

            List<String> order = new ArrayList<String>();
            Matcher sp = Pattern.compile("(?is)<itemref\\b[^>]*>").matcher(opfXml);
            java.util.Map<String, String> items = new java.util.HashMap<String, String>();
            Matcher im = Pattern.compile("(?is)<item\\b[^>]*>").matcher(opfXml);
            while (im.find()) {
                String id = attr(im.group(), "id");
                String href = attr(im.group(), "href");
                if (id != null && href != null) items.put(id, href);
            }
            while (sp.find()) {
                String idref = attr(sp.group(), "idref");
                if (idref != null && items.containsKey(idref)) order.add(items.get(idref));
            }
            if (order.isEmpty()) {
                for (String href : items.values()) if (href.matches("(?i).*\\.(x?html?|htm)$")) order.add(href);
            }

            List<Chapter> out = new ArrayList<Chapter>();
            long total = 0;
            for (String href : order) {
                if (out.size() >= 120) break;
                String name = resolve(base, href);
                String html = readEntry(z, name);
                if (html == null) { html = readEntry(z, href); name = href; }
                if (html == null) continue;
                String text = stripHtml(html);
                if (text.length() < 8) continue;
                total += text.length();
                if (total > 6 * 1024 * 1024) break;
                Chapter c = new Chapter();
                c.title = chapterTitle(html, out.size());
                c.text = text;
                c.entry = name;
                out.add(c);
            }
            return out;
        } finally {
            try { z.close(); } catch (Exception ignored) { }
        }
    }

    /** 续读时先只读上次那一章（不解析整本书）。 */
    private static Chapter loadEpubChapter(File f, String entry) throws Exception {
        ZipFile z = new ZipFile(f);
        try {
            String html = readEntry(z, entry);
            if (html == null) return null;
            Chapter c = new Chapter();
            c.text = stripHtml(html);
            c.title = "";
            c.entry = entry;
            return c;
        } finally {
            try { z.close(); } catch (Exception ignored) { }
        }
    }

    private static String readEntry(ZipFile z, String name) {
        try {
            ZipEntry e = z.getEntry(name);
            if (e == null) {
                String decoded = java.net.URLDecoder.decode(name, "UTF-8");
                e = z.getEntry(decoded);
            }
            if (e == null) return null;
            InputStream in = z.getInputStream(e);
            ByteArrayOutputStream bo = new ByteArrayOutputStream();
            byte[] b = new byte[8192];
            int n;
            while ((n = in.read(b)) > 0) { bo.write(b, 0, n); if (bo.size() > 2 * 1024 * 1024) break; }
            in.close();
            return new String(bo.toByteArray(), Charset.forName("UTF-8"));
        } catch (Exception e) {
            return null;
        }
    }

    private static String resolve(String base, String href) {
        String p = base + href;
        p = p.replace("%20", " ");
        String[] parts = p.split("/");
        java.util.ArrayList<String> out = new java.util.ArrayList<String>();
        for (String part : parts) {
            if (part.length() == 0 || part.equals(".")) continue;
            if (part.equals("..")) { if (!out.isEmpty()) out.remove(out.size() - 1); }
            else out.add(part);
        }
        StringBuilder sb = new StringBuilder();
        for (String part : out) { if (sb.length() > 0) sb.append('/'); sb.append(part); }
        return sb.toString();
    }

    private static String attr(String tag, String name, String attrName) {
        Matcher m = Pattern.compile("(?is)" + Pattern.quote(attrName) + "\\s*=\\s*\"([^\"]*)\"").matcher(tag);
        if (m.find()) return m.group(1);
        m = Pattern.compile("(?is)" + Pattern.quote(attrName) + "\\s*=\\s*'([^']*)'").matcher(tag);
        if (m.find()) return m.group(1);
        return null;
    }
    private static String attr(String tag, String attrName) { return attr(tag, null, attrName); }

    private static String chapterTitle(String html, int index) {
        Matcher m = Pattern.compile("(?is)<title[^>]*>(.*?)</title>").matcher(html);
        if (m.find()) {
            String s = htmlToText(m.group(1)).trim();
            if (s.length() > 0) return s;
        }
        m = Pattern.compile("(?is)<h[1-3][^>]*>(.*?)</h[1-3]>").matcher(html);
        if (m.find()) {
            String s = htmlToText(m.group(1)).trim();
            if (s.length() > 0) return s;
        }
        return "第 " + (index + 1) + " 章";
    }

    private static String stripHtml(String html) {
        String s = html;
        s = s.replaceAll("(?is)<head[^>]*>.*?</head>", " ");
        s = s.replaceAll("(?is)<script[^>]*>.*?</script>", " ");
        s = s.replaceAll("(?is)<style[^>]*>.*?</style>", " ");
        s = s.replaceAll("(?i)<br\\s*/?>", "\n");
        s = s.replaceAll("(?i)</p\\s*>", "\n\n");
        s = s.replaceAll("(?i)</div\\s*>", "\n");
        s = s.replaceAll("(?i)</h[1-6]\\s*>", "\n\n");
        s = s.replaceAll("(?i)<li[^>]*>", "\n· ");
        s = s.replaceAll("(?s)<[^>]+>", " ");
        s = htmlToText(s);
        s = s.replaceAll("[ \\t\\x0B\\f]+", " ");
        s = s.replaceAll("\\n[ \\t]+", "\n");
        s = s.replaceAll("\\n{3,}", "\n\n");
        return s.trim();
    }

    private static String htmlToText(String s) {
        s = s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
             .replace("&quot;", "\"").replace("&#39;", "'").replace("&apos;", "'");
        Matcher m = Pattern.compile("&#(x?)([0-9a-fA-F]+);").matcher(s);
        StringBuffer sb = new StringBuffer();
        while (m.find()) {
            try {
                int cp = Integer.parseInt(m.group(2), m.group(1).length() > 0 ? 16 : 10);
                m.appendReplacement(sb, new String(Character.toChars(cp)));
            } catch (Exception e) {
                m.appendReplacement(sb, "");
            }
        }
        m.appendTail(sb);
        return sb.toString();
    }

    // ------------------------------------------------------------------ progress

    private SharedPreferences prefs() { return Store.prefs(this, "reader"); }

    private int savedPage() {
        try { return prefs().getInt("p:" + path, 0); } catch (Throwable t) { return 0; }
    }

    /**
     * 文字书的续读位置：按“章节 + 字符位置”存（c: / o:），不按页码。字号是所有书共用的，以前在一本书里改了字号，
     * 别的书按旧页码续读就偏到别处去了。没有新记录的老进度才退回用页码。
     */
    private int savedTextPage() {
        try {
            SharedPreferences p = prefs();
            if (p.contains("c:" + path)) return pageAt(p.getInt("c:" + path, 0), p.getInt("o:" + path, 0));
        } catch (Throwable ignored) { }
        return Math.max(0, Math.min(pages.size() - 1, savedPage()));
    }

    private void savePage() {
        try {
            int total = isPdf ? pdfPages : pages.size();
            if (total <= 0) {
                // 整本还没分完页（先显示的那一页）：只记位置，不动页码和总页数
                if (!isPdf && provIndex >= 0) prefs().edit().putInt("c:" + path, provIndex).putInt("o:" + path, provStart)
                    .putLong("r:" + path, System.currentTimeMillis()).apply();
                return;
            }
            SharedPreferences.Editor e = prefs().edit().putInt("p:" + path, page).putInt("t:" + path, total)
                 .putInt("s:" + path, textSize);       // p: / t: 还给图书馆算百分比
            e.putLong("r:" + path, System.currentTimeMillis());   // 上次阅读时间：书库“最近”排序用
            if (!isPdf && !pages.isEmpty()) {
                Page cur = pages.get(Math.max(0, Math.min(pages.size() - 1, page)));
                e.putInt("c:" + path, cur.chapter).putInt("o:" + path, cur.start);
                // 下次打开时先只排这一页用：EPUB 这一章的文件名、排版条件、页脚左边那句
                if (cur.chapter < chapters.size() && chapters.get(cur.chapter).entry != null) e.putString("e:" + path, chapters.get(cur.chapter).entry);
                if (chapters.size() > 1 && cur.chapter < chapters.size()) e.putString("ch:" + path, String.valueOf(chapters.get(cur.chapter).title));   // 方块主页“继续阅读”显示的章名
                e.putString("st:" + path, geometry().sig).putString("fl:" + path, leftBase);
            }
            e.apply();   // 翻页时不在主线程同步写盘
        } catch (Throwable ignored) { }
    }

    @Override protected void onResume() {
        super.onResume();
        readStarted = SystemClock.elapsedRealtime();
        readPages = 0;
        resumedNow = true;
        Stats.sampleBattery(this);
        if (framed) { StatusBarService.setSuppressed(false); StatusBarService.refresh(this); }
    }

    @Override protected void onPause() {
        resumedNow = false;
        if (readStarted > 0) {
            Stats.addReading(this, SystemClock.elapsedRealtime() - readStarted, readPages);
            readStarted = 0;
            readPages = 0;
        }
        savePage();
        StatusBarService.setSuppressed(false);
        StatusBarService.refresh(this);
        super.onPause();
    }

    @Override protected void onDestroy() {
        pdfGen++;
        gone = true;
        // 关文档也排在 PDF 线程上：等正在渲染的那一页画完再关。以前这里最多等 2 秒就关，大 PDF 一页要画 4 秒多，
        // close() 因为页面还开着失败，文档留给 finalize 去关；finalize 又要等全局的 PDF 锁，超过 10 秒整个桌面进程被杀（实测连开 4 次就崩）。
        try {
            pdfWorker.execute(new Runnable() {
                @Override public void run() {
                    try { if (pdf != null) pdf.close(); } catch (Throwable ignored) { }
                    try { if (pfd != null) pfd.close(); } catch (Throwable ignored) { }
                }
            });
        } catch (Throwable ignored) { }
        pdfWorker.shutdown();
        if (pdfBitmap != null) pdfBitmap.recycle();
        super.onDestroy();
    }

    // ------------------------------------------------------------------ display / fonts

    private void loadStyle() {
        try {
            SharedPreferences p = prefs();
            SharedPreferences home = Store.prefs(this, "home");
            textSize = p.getInt("size", 22);
            fontPath = p.getString("font", home.getString("reader_font_path", null));
            fontName = p.getString("fontName", home.getString("reader_font_name", "系统默认"));
            lineSpacing = p.getFloat("line", 1.35f);
            marginDp = p.getInt("margin", 24);
            align = p.getInt("align", 0);
            paraSpacing = p.getFloat("para", 0f);
            indent = p.getInt("indent", 0);
            minimal = p.getBoolean("minimal", false);
            tapMode = p.getInt("tapmode", 0);
        } catch (Throwable ignored) { }
    }

    private void saveStyle() {
        try {
            prefs().edit().putInt("size", textSize).putString("font", fontPath).putString("fontName", fontName)
                .putFloat("line", lineSpacing).putInt("margin", marginDp).putInt("align", align)
                .putFloat("para", paraSpacing).putInt("indent", indent).putBoolean("minimal", minimal).putInt("tapmode", tapMode).commit();
            Store.prefs(this, "home").edit().putString("reader_font_path", fontPath)
                .putString("reader_font_name", fontName).commit();
        } catch (Throwable ignored) { }
    }

    private void applyStyle() {
        if (content == null) return;
        content.setTypeface(typeface());
        content.setTextSize(textSize);
        content.setLineSpacing(0, lineSpacing);
        content.setBreakStrategy(android.text.Layout.BREAK_STRATEGY_SIMPLE);          // 和 buildPages 的排版保持一致
        content.setHyphenationFrequency(android.text.Layout.HYPHENATION_FREQUENCY_NONE);
        content.setIncludeFontPadding(true);
        int m = dp(marginDp);
        content.setPadding(m, dp(34), m, dp(30));   // 下面 30dp 留给页脚
        content.setGravity(align == 1 ? (Gravity.TOP | Gravity.CENTER_HORIZONTAL) : (Gravity.TOP | Gravity.START));
    }

    // 每翻一页都会走到这里：字体文件（18 MB 的霞鹜文楷）只解析一次
    private String cachedFontPath;
    private Typeface cachedTypeface;
    private Typeface typeface() {
        if (fontPath != null && fontPath.length() > 0) {
            if (fontPath.equals(cachedFontPath) && cachedTypeface != null) return cachedTypeface;
            try {
                cachedTypeface = Typeface.createFromFile(fontPath);
                cachedFontPath = fontPath;
                return cachedTypeface;
            } catch (Throwable ignored) { }
        }
        return Typeface.DEFAULT;
    }

    private float fontWidth() {
        String n = fontName == null ? "" : fontName.toLowerCase(Locale.US);
        if (n.contains("bookerly") || n.contains("baskerville") || n.contains("英文")) return 0.58f;
        if (n.contains("等宽") || n.contains("mono")) return 0.62f;
        return 0.96f;
    }

    private void rebuildKeepPosition() {
        if (pages.isEmpty()) { applyStyle(); return; }
        Page cur = pages.get(Math.max(0, Math.min(pages.size() - 1, page)));
        int chapter = cur.chapter, offset = cur.start;       // 按字符位置：换了字号 / 行距 / 边距还停在同一段文字
        buildPages();
        page = pageAt(chapter, offset);
        showText();
    }

    private void displayDialog() {
        final Dialog d = new Dialog(this);
        d.requestWindowFeature(Window.FEATURE_NO_TITLE);
        Window w = d.getWindow();
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        PageScrollView sv = new PageScrollView(this);
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setPadding(dp(20), dp(10), dp(20), dp(20));
        box.setBackgroundColor(Color.WHITE);
        sv.addView(box);

        TextView h = Ui.text(this, "显示", 24, true);
        box.addView(h);
        box.addView(Ui.rule(this, 1, Color.BLACK));

        box.addView(Ui.text(this, "字体", 17, true));
        List<Books.Font> fonts = Books.fonts();
        for (final Books.Font f : fonts) {
            boolean on = (f.path == null && fontPath == null) || (f.path != null && f.path.equals(fontPath));
            View b = Ui.button(this, f.name, 15, on, new View.OnClickListener() {
                @Override public void onClick(View v) {
                    fontPath = f.path; fontName = f.name;
                    saveStyle(); rebuildKeepPosition(); d.dismiss();
                }
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
            lp.topMargin = dp(4);
            box.addView(b, lp);
        }

        box.addView(Ui.text(this, "字号", 17, true));
        LinearLayout sizeRow = new LinearLayout(this);
        sizeRow.setOrientation(LinearLayout.HORIZONTAL);
        sizeRow.setGravity(Gravity.CENTER_VERTICAL);
        final TextView sizeVal = Ui.text(this, String.valueOf(textSize), 18, true);
        sizeVal.setGravity(Gravity.CENTER);
        sizeRow.addView(Ui.button(this, "A-", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { setTextSize(textSize - 2); sizeVal.setText(String.valueOf(textSize)); }
        }));
        sizeRow.addView(sizeVal, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        sizeRow.addView(Ui.button(this, "A+", 16, false, new View.OnClickListener() {
            @Override public void onClick(View v) { setTextSize(textSize + 2); sizeVal.setText(String.valueOf(textSize)); }
        }));
        box.addView(sizeRow);

        box.addView(Ui.text(this, "行距", 17, true));
        LinearLayout lineRow = new LinearLayout(this);
        lineRow.setOrientation(LinearLayout.HORIZONTAL);
        String[] lineNames = { "紧凑", "标准", "宽松", "很松" };
        float[] lineVals = { 1.2f, 1.4f, 1.6f, 1.8f };
        for (int i = 0; i < lineNames.length; i++) {
            final float lv = lineVals[i];
            View b = Ui.button(this, lineNames[i], 14, Math.abs(lineSpacing - lv) < 0.01f, new View.OnClickListener() {
                @Override public void onClick(View v) { lineSpacing = lv; saveStyle(); rebuildKeepPosition(); d.dismiss(); }
            });
            lineRow.addView(b, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        }
        box.addView(lineRow);

        box.addView(Ui.text(this, "边距", 17, true));
        LinearLayout marginRow = new LinearLayout(this);
        marginRow.setOrientation(LinearLayout.HORIZONTAL);
        String[] marginNames = { "小", "中", "大" };
        int[] marginVals = { 12, 24, 36 };
        for (int i = 0; i < marginNames.length; i++) {
            final int mv = marginVals[i];
            View b = Ui.button(this, marginNames[i], 14, marginDp == mv, new View.OnClickListener() {
                @Override public void onClick(View v) { marginDp = mv; saveStyle(); rebuildKeepPosition(); d.dismiss(); }
            });
            marginRow.addView(b, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        }
        box.addView(marginRow);

        box.addView(Ui.text(this, "对齐", 17, true));
        LinearLayout alignRow = new LinearLayout(this);
        alignRow.setOrientation(LinearLayout.HORIZONTAL);
        View left = Ui.button(this, "左对齐", 14, align == 0, new View.OnClickListener() {
            @Override public void onClick(View v) { align = 0; saveStyle(); applyStyle(); d.dismiss(); }
        });
        View center = Ui.button(this, "居中", 14, align == 1, new View.OnClickListener() {
            @Override public void onClick(View v) { align = 1; saveStyle(); applyStyle(); d.dismiss(); }
        });
        alignRow.addView(left, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        alignRow.addView(center, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1));
        box.addView(alignRow);

        View close = Ui.button(this, "关闭", 16, true, new View.OnClickListener() {
            @Override public void onClick(View v) { d.dismiss(); }
        });
        LinearLayout.LayoutParams clp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        clp.topMargin = dp(16);
        box.addView(close, clp);

        d.setContentView(sv);
        d.show();
        w.setGravity(Gravity.BOTTOM);
        w.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND);
        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, (int) (getResources().getDisplayMetrics().heightPixels * 0.55));
    }


    // ------------------------------------------------------------------ 段距 / 首行缩进（不改文字，只加排版标记，书签和续读的字符位置不变）

    /** 段落最后一行下面多留 px 像素。 */
    private static final class ParaGap implements android.text.style.LineHeightSpan {
        final int px;
        ParaGap(int px) { this.px = px; }
        @Override public void chooseHeight(CharSequence text, int start, int end, int spanstartv, int v, android.graphics.Paint.FontMetricsInt fm) {
            if (end > 0 && end <= text.length() && text.charAt(end - 1) == '\n' && text instanceof android.text.Spanned && end == ((android.text.Spanned) text).getSpanEnd(this)) {
                fm.descent += px; fm.bottom += px;
            }
        }
    }

    /** s[i, stop) 复制一份，每段加上缩进 / 段距。firstIsPara：第一段是不是从段首开始（翻到段落中间的那一页不缩进）。 */
    private static CharSequence spans(String s, int i, int stop, int indentPx, int paraPx) {
        return spans(s.substring(i, stop), i == 0 || s.charAt(i - 1) == '\n', indentPx, paraPx);
    }

    private static CharSequence spans(String t, boolean firstIsPara, int indentPx, int paraPx) {
        android.text.SpannableString sp = new android.text.SpannableString(t);
        int ps = 0, n = t.length();
        while (ps < n) {
            int nl = t.indexOf('\n', ps);
            int pe = nl < 0 ? n : nl + 1;
            if (pe > ps) {
                char c0 = t.charAt(ps);
                boolean blank = c0 == '\n' || c0 == '　' || c0 == ' ' || c0 == '\t';
                if (indentPx > 0 && !blank && (ps > 0 || firstIsPara))
                    sp.setSpan(new android.text.style.LeadingMarginSpan.Standard(indentPx, 0), ps, pe, android.text.Spanned.SPAN_PARAGRAPH);
                if (paraPx > 0 && nl >= 0) sp.setSpan(new ParaGap(paraPx), ps, pe, android.text.Spanned.SPAN_PARAGRAPH);
            }
            ps = pe;
        }
        return sp;
    }

    /** 正文里显示的那一页文字：chapter[start, end) 去掉页尾空行，按需要加缩进 / 段距。 */
    private CharSequence styled(String chapter, int start, int end) {
        String t = trimEnd(chapter.substring(start, end));
        if (indent <= 0 && paraSpacing <= 0) return t;
        float sd = getResources().getDisplayMetrics().scaledDensity;
        return spans(t, start == 0 || chapter.charAt(start - 1) == '\n', Math.round(indent * textSize * sd), Math.round(paraSpacing * textSize * sd));
    }

    // ------------------------------------------------------------------ 方块风格：顶栏、底部六个按钮、设置单

    private static final String[] TOOLS = { "目录", "字体", "排版", "显示", "模式", "系统" };
    private static final Icons.Kind[] TOOL_ICONS = { Icons.Kind.TOC, Icons.Kind.FONT, Icons.Kind.LAYOUT, Icons.Kind.EYE, Icons.Kind.INVERT, Icons.Kind.GEAR };

    private void buildBlocksChrome(FrameLayout pageView, String name) {
        // 顶栏：返回、章名、时间、电量
        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.VERTICAL);
        top.setBackgroundColor(Color.WHITE);
        top.setClickable(true);
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(12), dp(22), dp(14), dp(8));
        row.addView(Blocks.squareButton(this, Icons.Kind.BACK, new View.OnClickListener() { @Override public void onClick(View v) { finish(); overridePendingTransition(0, 0); } }));
        blkTitle = Ui.text(this, name, 16, true);
        blkTitle.setSingleLine(true);
        blkTitle.setEllipsize(android.text.TextUtils.TruncateAt.END);
        blkTitle.setGravity(Gravity.CENTER);
        blkTitle.setPadding(dp(10), 0, dp(10), 0);
        row.addView(blkTitle, Blocks.weight(1));
        blkClock = Ui.text(this, "", 14, false);
        row.addView(blkClock);
        top.addView(row);
        top.addView(Ui.rule(this, 2, Color.BLACK));
        top.setVisibility(View.GONE);
        blkTop = top;
        pageView.addView(top, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP));

        // 底部：设置单（盖在正文上）+ 六个按钮
        LinearLayout bottom = new LinearLayout(this);
        bottom.setOrientation(LinearLayout.VERTICAL);
        bottom.setClickable(true);
        bottom.setBackgroundColor(Color.WHITE);   // 设置单和按钮条之间、两边的空隙不透出正文
        sheetBox = new LinearLayout(this);
        sheetBox.setOrientation(LinearLayout.VERTICAL);
        sheetBox.setBackground(Blocks.frame(this));
        sheetBox.setPadding(dp(12), dp(8), dp(12) + Blocks.shade(this), dp(10) + Blocks.shade(this));
        sheetBox.setVisibility(View.GONE);
        LinearLayout.LayoutParams sp = Blocks.match();
        sp.leftMargin = dp(12); sp.rightMargin = dp(12); sp.bottomMargin = dp(8);
        bottom.addView(sheetBox, sp);
        LinearLayout bar = new LinearLayout(this);
        bar.setOrientation(LinearLayout.VERTICAL);
        bar.setBackgroundColor(Color.WHITE);
        bar.addView(Ui.rule(this, 2, Color.BLACK));
        LinearLayout tools = new LinearLayout(this);
        toolMarks = new View[TOOLS.length];
        for (int i = 0; i < TOOLS.length; i++) {
            final int idx = i;
            LinearLayout cell = new LinearLayout(this);
            cell.setOrientation(LinearLayout.VERTICAL);
            cell.setGravity(Gravity.CENTER_HORIZONTAL);
            View m = new View(this);
            toolMarks[i] = m;
            LinearLayout.LayoutParams mp = new LinearLayout.LayoutParams(dp(48), dp(6));
            mp.bottomMargin = dp(4);
            cell.addView(m, mp);
            cell.addView(new Icons.IconView(this, TOOL_ICONS[i]), Blocks.lp(dp(24), dp(24)));
            TextView t = Ui.text(this, TOOLS[i], 13, false);
            t.setPadding(0, dp(2), 0, dp(10));
            t.setGravity(Gravity.CENTER);
            cell.addView(t, Blocks.match());
            cell.setPadding(dp(4), 0, dp(4), 0);
            cell.setClickable(true);
            cell.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { openSheet(sheetOpen == idx ? -1 : idx); } });
            Blocks.fast(cell);
            tools.addView(cell, Blocks.weight(1));
        }
        bar.addView(tools);
        bottom.addView(bar, Blocks.match());
        bottom.setVisibility(View.GONE);
        blkBottom = bottom;
        pageView.addView(bottom, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM));

        // “正在打开”卡片：第一页准备好以前一直在；第一页在 1.5 秒内好了的话它根本不会被画出来
        LinearLayout card = Blocks.card(this);
        card.setBackground(Blocks.frameDouble(this));
        card.setPadding(dp(18), dp(14), dp(18) + Blocks.shade(this), dp(16) + Blocks.shade(this));
        LinearLayout head = new LinearLayout(this);
        head.addView(Blocks.cap(this, "Opening / " + ext.toUpperCase(Locale.US)), Blocks.weight(1));
        head.addView(Blocks.cap(this, "Please wait"));
        card.addView(head);
        TextView tt = Ui.text(this, name, 20, true);
        tt.setSingleLine(true);
        tt.setEllipsize(android.text.TextUtils.TruncateAt.END);
        card.addView(tt);
        TextView st = Ui.text(this, "正在打开这本书…", 14, false);
        st.setPadding(0, dp(4), 0, dp(8));
        card.addView(st);
        Blocks.BlockBar bb = new Blocks.BlockBar(this, 10);
        bb.noPercent();
        bb.setValue(3);
        card.addView(bb, Blocks.match());
        FrameLayout.LayoutParams cp = new FrameLayout.LayoutParams((int) (getResources().getDisplayMetrics().widthPixels * 0.72), ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER);
        openCard = card;
        pageView.addView(card, cp);
    }

    /** 第一页（或出错信息）已经放上去了：收起“正在打开”的卡片。 */
    private void opened() {
        if (openCard != null && openCard.getVisibility() != View.GONE) openCard.setVisibility(View.GONE);
    }

    private void paintBlocksTop() {
        if (blkTitle == null) return;
        String t = bookTitle.length() > 0 ? bookTitle : String.valueOf(blkTitle.getText());
        if (!isPdf && !pages.isEmpty() && chapters.size() > 1) {
            int ch = pages.get(Math.max(0, Math.min(pages.size() - 1, page))).chapter;
            if (ch < chapters.size() && chapters.get(ch).title != null) t = chapters.get(ch).title;
        }
        if (!t.contentEquals(blkTitle.getText())) blkTitle.setText(t);
        java.util.Map<String, String> st = HostLink.kv(HostLink.CTL + "status");
        String c = Ui.clock(this) + (st.get("battery") != null ? "   " + st.get("battery") + "%" : "");
        if (!c.contentEquals(blkClock.getText())) blkClock.setText(c);
    }

    /** 打开第 i 张设置单（-1 = 收起）。同一时间只有一张；换内容只重画底部这一块。 */
    private void openSheet(int i) {
        if (i != sheetOpen && (i < 0) != (sheetOpen < 0)) Blocks.swipe(this, i < 0 ? Blocks.DIR_DOWN : Blocks.DIR_UP, Blocks.KIND_SHEET);
        sheetOpen = i;
        for (int k = 0; k < toolMarks.length; k++) toolMarks[k].setBackgroundColor(k == i ? Color.BLACK : Color.WHITE);
        sheetBox.removeAllViews();
        if (i < 0) { sheetBox.setVisibility(View.GONE); return; }
        switch (i) {
        case 0: sheetToc(0); break;
        case 1: sheetFont(); break;
        case 2: sheetLayout(); break;
        case 3: sheetDisplay(); break;
        case 4: sheetMode(); break;
        default: sheetSystem(); break;
        }
        sheetBox.setVisibility(View.VISIBLE);
    }

    private void sheetHead(String en, String zh) {
        LinearLayout h = new LinearLayout(this);
        h.setGravity(Gravity.CENTER_VERTICAL);
        h.addView(Blocks.titled(this, en, zh, 16, true), Blocks.weight(1));
        h.setPadding(0, 0, 0, dp(6));
        sheetBox.addView(h);
    }

    private void sheetRow(String zh, String en, View control) {
        LinearLayout r = Blocks.row(this, zh, en, control);
        r.setPadding(0, dp(4), 0, dp(4));
        r.setMinimumHeight(dp(52));
        sheetBox.addView(r, Blocks.match());
    }

    /** 目录 / 书签：一页 6 条，翻页条翻。 */
    private int tocPage, tocSeg;
    private void sheetToc(int pg) {
        sheetBox.removeAllViews();
        tocPage = pg;
        final List<String> bms = bookmarks();
        boolean hasToc = !isPdf && chapters.size() > 1;
        if (!hasToc) tocSeg = 1;
        sheetHead("Contents", hasToc ? "目录" : "书签");
        if (hasToc && !bms.isEmpty()) sheetBox.addView(new Blocks.SegBar(this, new String[] { "目录（" + chapters.size() + "）", "书签（" + bms.size() + "）" }, tocSeg,
            new Blocks.SegBar.Listener() { @Override public void onPick(int k) { tocSeg = k; sheetToc(0); } }), Blocks.match());
        final List<String> names = new ArrayList<String>();
        final List<Integer> targets = new ArrayList<Integer>();
        int curCh = !isPdf && !pages.isEmpty() ? pages.get(Math.max(0, Math.min(pages.size() - 1, page))).chapter : -1;
        int highlight = -1;
        if (tocSeg == 0 && hasToc) {
            for (int c = 0; c < chapters.size() && c < chapterStart.size(); c++) { names.add(String.valueOf(chapters.get(c).title)); targets.add(chapterStart.get(c)); if (c == curCh) highlight = c; }
        } else {
            int total = isPdf ? pdfPages : pages.size();
            for (String k : bms) { int p = bookmarkPage(k); if (p < 0) continue; names.add("第 " + (p + 1) + " 页 · " + ((p + 1) * 100 / Math.max(1, total)) + "%"); targets.add(p); }
        }
        final int per = 6, pages0 = Math.max(1, (names.size() + per - 1) / per);
        if (pg == 0 && highlight >= 0) tocPage = highlight / per;
        tocPage = Math.max(0, Math.min(pages0 - 1, tocPage));
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        list.setBackground(Blocks.plain(this));
        for (int n = tocPage * per; n < Math.min(names.size(), tocPage * per + per); n++) {
            final int to = targets.get(n);
            TextView t = Ui.text(this, names.get(n), 15, n == highlight);
            t.setSingleLine(true);
            t.setEllipsize(android.text.TextUtils.TruncateAt.END);
            t.setPadding(dp(10), 0, dp(10), 0);
            t.setGravity(Gravity.CENTER_VERTICAL);
            if (n == highlight) { t.setBackgroundColor(Color.BLACK); t.setTextColor(Color.WHITE); }
            t.setClickable(true);
            t.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { jump(to); } });
            Blocks.fast(t);
            if (list.getChildCount() > 0) list.addView(Blocks.hair(this));
            list.addView(t, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, dp(46)));
        }
        if (names.isEmpty()) { TextView t = Ui.text(this, "这本书没有目录，也还没有书签。", 15, false); t.setPadding(dp(10), dp(14), dp(10), dp(14)); list.addView(t); }
        sheetBox.addView(list, Blocks.gap(this, 6));
        if (pages0 > 1) {
            Blocks.Pager pager = new Blocks.Pager(this, new Blocks.Pager.Listener() { @Override public void onPage(int dir) { sheetToc(tocPage + dir); } });
            pager.set(tocPage + 1, pages0);
            sheetBox.addView(pager, Blocks.gap(this, 6));
        }
        // 跳到：百分比步进器（一步 5%），点中间的值输入页码
        final int total = isPdf ? pdfPages : pages.size();
        if (total > 1) {
            final String[] pct = new String[21];
            for (int i = 0; i <= 20; i++) pct[i] = (i * 5) + "%";
            final int curPct = Math.min(100, page * 100 / Math.max(1, total - 1));
            Blocks.Stepper js = new Blocks.Stepper(this, pct, Math.round(curPct / 5f), new Blocks.Stepper.Listener() {
                @Override public void onStep(int i) { jump(Math.min(total - 1, (total - 1) * i * 5 / 100)); } });
            js.onValueTap(new View.OnClickListener() { @Override public void onClick(View v) { pageInput(total); } });
            sheetRow("跳到 · 第 " + (page + 1) + " / " + total + " 页", "Go to (tap value: page)", js);
        }
    }

    /** 输入页码跳过去。 */
    private void pageInput(final int total) {
        final android.widget.EditText in = new android.widget.EditText(this);
        in.setInputType(android.text.InputType.TYPE_CLASS_NUMBER);
        in.setSingleLine(true);
        in.setTextSize(22);
        in.setBackground(Blocks.plain(this));
        in.setPadding(dp(12), dp(10), dp(12), dp(10));
        in.setText(String.valueOf(page + 1));
        new VeraDialog.Builder(this).title("跳到第几页").message("1 – " + total).view(in).negative("取消", null)
            .positive("跳过去", new Runnable() { @Override public void run() {
                try { jump(Integer.parseInt(in.getText().toString().trim()) - 1); } catch (Throwable ignored) { }
            } }).show();
    }

    /** 字体：字体（点中间的名字出一张一页 6 个的选择表）、字号。 */
    private void sheetFont() {
        sheetHead("Font", "字体");
        final List<Books.Font> fonts = Books.fonts();
        String[] names = new String[fonts.size()];
        int cur = 0;
        for (int i = 0; i < names.length; i++) {
            names[i] = fonts.get(i).name;
            Books.Font f = fonts.get(i);
            if ((f.path == null && fontPath == null) || (f.path != null && f.path.equals(fontPath))) cur = i;
        }
        Blocks.Stepper fs = new Blocks.Stepper(this, names, cur, new Blocks.Stepper.Listener() { @Override public void onStep(int i) {
            fontPath = fonts.get(i).path; fontName = fonts.get(i).name; saveStyle(); rebuildKeepPosition(); } }).wrap();
        fs.onValueTap(new View.OnClickListener() { @Override public void onClick(View v) { fontPicker(0); } });
        sheetRow("字体", "Font family", fs);
        final String[] sizes = new String[14];
        for (int i = 0; i < sizes.length; i++) sizes[i] = String.valueOf(14 + i * 2);
        sheetRow("字号", "Font size", new Blocks.Stepper(this, sizes, Math.max(0, Math.min(13, (textSize - 14) / 2)), new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { setTextSize(14 + i * 2); } }));
        TextView imp = Ui.text(this, "导入字体：把 .ttf / .otf 放进内部存储的 Fonts 文件夹（或用传书网页上传），这里就会多出来。", 12, false);
        imp.setPadding(0, dp(6), 0, 0);
        sheetBox.addView(imp, Blocks.match());
    }

    private void fontPicker(final int pg) {
        sheetBox.removeAllViews();
        sheetHead("Quick select", "选择字体");
        final List<Books.Font> fonts = Books.fonts();
        final int per = 6, pages0 = Math.max(1, (fonts.size() + per - 1) / per);
        final int p = Math.max(0, Math.min(pages0 - 1, pg));
        LinearLayout list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        for (int i = p * per; i < Math.min(fonts.size(), p * per + per); i++) {
            final Books.Font f = fonts.get(i);
            boolean on = (f.path == null && fontPath == null) || (f.path != null && f.path.equals(fontPath));
            TextView t = Blocks.button(this, f.name, on, new View.OnClickListener() { @Override public void onClick(View v) {
                fontPath = f.path; fontName = f.name; saveStyle(); rebuildKeepPosition(); openSheet(1); } });
            LinearLayout.LayoutParams lp = Blocks.match(); lp.topMargin = dp(4);
            list.addView(t, lp);
        }
        sheetBox.addView(list);
        Blocks.Pager pager = new Blocks.Pager(this, new Blocks.Pager.Listener() { @Override public void onPage(int dir) { fontPicker(p + dir); } });
        pager.set(p + 1, pages0);
        sheetBox.addView(pager, Blocks.gap(this, 8));
    }

    private static final float[] LINE_V = { 1.0f, 1.1f, 1.2f, 1.3f, 1.35f, 1.4f, 1.5f, 1.6f, 1.7f, 1.8f, 2.0f };
    private static final float[] PARA_V = { 0f, 0.25f, 0.5f, 0.75f, 1.0f, 1.5f };
    private static final int[] MARGIN_V = { 8, 12, 16, 20, 24, 30, 36, 44, 56 };

    private static String[] labels(float[] v, String unit) { String[] o = new String[v.length]; for (int i = 0; i < v.length; i++) o[i] = (v[i] == 0 ? "无" : String.format(Locale.US, "%.2f", v[i]).replaceAll("0+$", "").replaceAll("\\.$", "") + unit); return o; }
    private static int nearest(float[] v, float x) { int b = 0; for (int i = 0; i < v.length; i++) if (Math.abs(v[i] - x) < Math.abs(v[b] - x)) b = i; return b; }

    /** 排版：行距、段距、左右边距、首行缩进、对齐。每改一项整本按字符位置重新分页，停在同一段字上。 */
    private void sheetLayout() {
        sheetHead("Layout", "排版");
        // 常用的三档：一点就换（行距 + 段距 + 边距一起）
        final float[][] preset = { { 1.2f, 0f, 16 }, { 1.4f, 0.25f, 24 }, { 1.7f, 0.5f, 30 } };
        int ps = -1;
        for (int i = 0; i < 3; i++) if (Math.abs(lineSpacing - preset[i][0]) < 0.01f && Math.abs(paraSpacing - preset[i][1]) < 0.01f && marginDp == (int) preset[i][2]) ps = i;
        sheetBox.addView(new Blocks.SegBar(this, new String[] { "紧凑", "标准", "宽松" }, ps, new Blocks.SegBar.Listener() { @Override public void onPick(int i) {
            lineSpacing = preset[i][0]; paraSpacing = preset[i][1]; marginDp = (int) preset[i][2];
            saveStyle(); if (footView != null) footView.setPadding(dp(marginDp), 0, dp(marginDp), dp(6)); rebuildKeepPosition(); openSheet(2);
        } }), Blocks.gap(this, 2));
        String[] lineL = new String[LINE_V.length];
        for (int i = 0; i < lineL.length; i++) lineL[i] = String.format(Locale.US, "%.2f", LINE_V[i]).replaceAll("0$", "") + " 倍";
        sheetRow("行距", "Line height", new Blocks.Stepper(this, lineL, nearest(LINE_V, lineSpacing), new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { lineSpacing = LINE_V[i]; saveStyle(); rebuildKeepPosition(); } }));
        sheetRow("段距", "Paragraph spacing", new Blocks.Stepper(this, labels(PARA_V, " 行"), nearest(PARA_V, paraSpacing), new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { paraSpacing = PARA_V[i]; saveStyle(); rebuildKeepPosition(); } }));
        String[] mL = new String[MARGIN_V.length];
        int mi = 0;
        for (int i = 0; i < mL.length; i++) { mL[i] = MARGIN_V[i] + " dp"; if (Math.abs(MARGIN_V[i] - marginDp) < Math.abs(MARGIN_V[mi] - marginDp)) mi = i; }
        sheetRow("左右边距", "Margin", new Blocks.Stepper(this, mL, mi, new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { marginDp = MARGIN_V[i]; saveStyle(); if (footView != null) footView.setPadding(dp(marginDp), 0, dp(marginDp), dp(6)); rebuildKeepPosition(); } }));
        sheetRow("首行缩进", "First-line indent", new Blocks.Stepper(this, new String[] { "无", "1 字", "2 字" }, Math.max(0, Math.min(2, indent)), new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { indent = i; saveStyle(); rebuildKeepPosition(); } }));
        sheetRow("对齐", "Alignment", new Blocks.Stepper(this, new String[] { "左对齐", "居中" }, align, new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { align = i; saveStyle(); rebuildKeepPosition(); } }).wrap());
    }

    /** 显示：刷新档位（宿主的 KFB_SMOOTH，整个系统一起）、全刷周期（KFB_FLASH）、极简全屏（不要页脚）。 */
    private void sheetDisplay() {
        sheetHead("Display", "显示");
        java.util.Map<String, String> cfg = HostLink.kv(HostLink.KFB + "settings");
        LinearLayout sm = new LinearLayout(this);
        sm.setOrientation(LinearLayout.VERTICAL);
        sm.setPadding(0, dp(4), 0, dp(6));
        sm.addView(Blocks.titled(this, "Refresh mode", "刷新档位（全局）", 16, true));
        sm.addView(new Blocks.SegBar(this, BlocksSettings.SMOOTH_L, Math.max(0, Math.min(3, HostLink.num(cfg, "KFB_SMOOTH", 0))), new Blocks.SegBar.Listener() {
            @Override public void onPick(int i) { HostLink.settings("KFB_SMOOTH=" + i + "\n"); } }), Blocks.gap(this, 4));
        sheetBox.addView(sm, Blocks.match());
        int fi = 4;
        for (int i = 0; i < BlocksSettings.FLASH_V.length; i++) if (BlocksSettings.FLASH_V[i].equals(cfg.get("KFB_FLASH"))) fi = i;
        sheetRow("全刷周期", "Full refresh", new Blocks.Stepper(this, BlocksSettings.FLASH_L, fi, new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { HostLink.settings("KFB_FLASH=" + BlocksSettings.FLASH_V[i] + "\n"); } }));
        sheetRow("极简全屏", "Minimal mode", new Blocks.Switch(this, minimal, new Icons.Toggle.Listener() { @Override public void onToggle(boolean on) {
            minimal = on; saveStyle(); if (footView != null) footView.setVisibility(on ? View.INVISIBLE : View.VISIBLE); } }));
    }

    /** 模式：反色、翻页动画、点按翻页的方式。 */
    private void sheetMode() {
        sheetHead("Mode", "模式");
        java.util.Map<String, String> cfg = HostLink.kv(HostLink.KFB + "settings");
        sheetRow("反色（夜间）", "Invert", new Blocks.Switch(this, "1".equals(cfg.get("KFB_INVERT")), new Icons.Toggle.Listener() {
            @Override public void onToggle(boolean on) { HostLink.settings("KFB_INVERT=" + (on ? 1 : 0) + "\n"); } }));
        final String anim = cfg.get("KFB_ANIM_MODE");
        sheetRow("翻页动画", "Page animation", new Blocks.Switch(this, anim == null || !"0".equals(anim), new Icons.Toggle.Listener() {
            @Override public void onToggle(boolean on) { HostLink.settings("KFB_ANIM_MODE=" + (on ? 1 : 0) + "\n"); } }));
        sheetRow("点按翻页", "Tap zones", new Blocks.Stepper(this, new String[] { "左边上一页", "全屏下一页" }, tapMode, new Blocks.Stepper.Listener() {
            @Override public void onStep(int i) { tapMode = i; saveStyle(); } }).wrap());
    }

    /** 系统：书签、跳转、清残影、面板、回桌面、回 Kindle。 */
    private void sheetSystem() {
        sheetHead("System", "系统");
        String[][] b = { { bookmarkedHere() ? "去掉书签" : "加书签", "跳转…", "整屏刷新" }, { "下拉面板", "回到桌面", "回 Kindle" } };
        for (int r = 0; r < 2; r++) {
            LinearLayout row = new LinearLayout(this);
            for (int k = 0; k < 3; k++) {
                final int id = r * 3 + k;
                TextView t = Blocks.button(this, b[r][k], false, new View.OnClickListener() { @Override public void onClick(View v) {
                    switch (id) {
                    case 0: toggleBookmark(); openSheet(5); break;
                    case 1: gotoDialog(); break;
                    case 2: HostLink.cmd("clear"); break;
                    case 3: Panel.open(ReaderActivity.this); break;
                    case 4: finish(); startActivity(new Intent(ReaderActivity.this, HomeActivity.class).addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)); overridePendingTransition(0, 0); break;
                    default: HostLink.cmd("exit"); break;
                    }
                } });
                LinearLayout.LayoutParams lp = Blocks.weight(1);
                if (k > 0) lp.leftMargin = dp(8);
                row.addView(t, lp);
            }
            sheetBox.addView(row, Blocks.gap(this, r == 0 ? 2 : 8));
        }
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
