// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.home;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.File;
import java.util.Arrays;
import java.util.Comparator;

/**
 * Minimal file picker for reader apps (Legado and others) that call
 * ACTION_GET_CONTENT / ACTION_OPEN_DOCUMENT. AOSP has no DocumentsUI in this
 * rootfs, so those apps previously could not import a book-source JSON at all.
 */
public class FilePickerActivity extends Activity {
    private static final String ROOT = "/data/media/0";
    private File dir = new File(ROOT);
    private LinearLayout list;
    private TextView path;

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        Window w = getWindow();
        w.setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        w.setWindowAnimations(0);
        w.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.WHITE);
        root.setPadding(dp(16), dp(10), dp(16), dp(10));

        LinearLayout hd = new LinearLayout(this);
        hd.setOrientation(LinearLayout.HORIZONTAL);
        hd.setGravity(Gravity.CENTER_VERTICAL);
        hd.addView(Icons.bar(this, Icons.Kind.BACK, 28, new View.OnClickListener() {
            @Override public void onClick(View v) {
                if (ROOT.equals(dir.getAbsolutePath())) finish(); else open(dir.getParentFile());
            }
        }));
        TextView t = Ui.text(this, "选择文件", 24, true); t.setPadding(dp(10), 0, 0, 0);
        hd.addView(t);
        root.addView(hd);
        path = Ui.text(this, "", 14, false); path.setTextColor(Color.DKGRAY);
        path.setPadding(0, dp(4), 0, dp(6));
        root.addView(path);
        View pathRule = Ui.rule(this, 1, Color.LTGRAY);
        root.addView(pathRule);
        if (Blocks.on(this)) { buildBlocks(root, hd, pathRule); return; }

        list = new LinearLayout(this);
        list.setOrientation(LinearLayout.VERTICAL);
        ScrollView sv = new ScrollView(this);
        sv.addView(list);
        root.addView(sv, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        setContentView(root);
        w.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        open(new File(ROOT));
    }

    /** 方块风格：页头（返回方块 = 上一级 / 退出）、路径条、分页列表（一页整数行）。 */
    private Blocks.PagedList paged;
    private final java.util.List<File> files = new java.util.ArrayList<File>();

    private void buildBlocks(LinearLayout root, View hd, View pathRule) {
        Blocks.restyleTop(this, root, hd, pathRule, "Files / pick", "选择文件", null);
        path.setTextColor(Color.BLACK);
        path.setSingleLine(true);
        path.setEllipsize(android.text.TextUtils.TruncateAt.START);
        root.removeView(path);
        LinearLayout pb = Blocks.boxed(this, path);
        pb.setBackground(Blocks.frame(this));
        pb.setPadding(dp(10), dp(6), dp(10) + Blocks.shade(this), dp(6) + Blocks.shade(this));
        root.addView(pb, Blocks.match());
        paged = new Blocks.PagedList(this, 60, new Blocks.PagedList.Rows() {
            @Override public int count() { return files.size(); }
            @Override public View row(int i) {
                final File f = files.get(i);
                View r = Blocks.listRow(FilePickerActivity.this, f.isDirectory() ? Icons.Kind.FOLDER : Icons.Kind.IMAGE, f.getName(),
                    f.isDirectory() ? "文件夹" : (f.length() / 1024) + " KB", f.isDirectory() ? new Icons.IconView(FilePickerActivity.this, Icons.Kind.CHEV_R) : null);
                r.setClickable(true);
                r.setOnClickListener(new View.OnClickListener() { @Override public void onClick(View v) { pick(f); } });
                Blocks.fast(r);
                return r;
            }
        });
        paged.setEmpty(Blocks.empty(this, Icons.Kind.FOLDER, "这里没有能选的文件", null, false));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1);
        lp.topMargin = dp(8);
        root.addView(paged, lp);
        setContentView(root);
        getWindow().setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
        open(new File(ROOT));
    }

    @Override public void onBackPressed() {
        if (paged != null && dir != null && !ROOT.equals(dir.getAbsolutePath())) open(dir.getParentFile()); else super.onBackPressed();
    }

    private void pick(File f) {
        if (f.isDirectory()) { open(f); return; }
        Uri u = new Uri.Builder().scheme("content").authority(VeraFileProvider.AUTHORITY).path(f.getAbsolutePath()).build();
        Intent i = new Intent();
        i.setData(u);
        i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        setResult(RESULT_OK, i);
        finish();
    }

    /**
     * 目录项：isDirectory / length 在后台线程里各问一次就记下来。以前 open() 在主线程上 listFiles，排序比较时每次都
     * isDirectory()（约 2·n·log n 次 stat），每行再 length()：KindleLibrary 是 FUSE，几千本书时主线程卡几秒到几十秒（ANR）。
     */
    private static final class Entry extends File {
        final boolean dir; final long len;
        Entry(File f) { super(f.getPath()); dir = f.isDirectory(); len = dir ? 0 : f.length(); }
        @Override public boolean isDirectory() { return dir; }
        @Override public long length() { return len; }
    }
    private int openGen;

    /** 在后台读目录（每项只 stat 一次），读完回到主线程显示；期间又点了别的目录就丢掉这一次的结果。 */
    private void open(final File d) {
        if (d == null) return;
        final int gen = ++openGen;
        new Thread(new Runnable() {
            @Override public void run() {
                if (!d.isDirectory()) return;
                File[] raw = d.listFiles();
                final File[] fs;
                if (raw == null) fs = null;
                else { fs = new File[raw.length]; for (int i = 0; i < raw.length; i++) fs[i] = new Entry(raw[i]); }
                runOnUiThread(new Runnable() { @Override public void run() {
                    if (gen != openGen || isFinishing()) return;
                    show(d, fs);
                } });
            }
        }, "filepicker-list").start();
    }

    private void show(File d, File[] listed) {
        dir = d;
        path.setText(d.getAbsolutePath());
        if (paged != null) {
            files.clear();
            File[] fs0 = listed;
            if (fs0 != null) {
                Arrays.sort(fs0, new Comparator<File>() {
                    @Override public int compare(File a, File b) {
                        if (a.isDirectory() != b.isDirectory()) return a.isDirectory() ? -1 : 1;
                        return a.getName().compareToIgnoreCase(b.getName());
                    }
                });
                for (File f : fs0) if (!f.getName().startsWith(".") && (f.isDirectory() || allowed(f))) files.add(f);
            }
            paged.toFirst();
            return;
        }
        list.removeAllViews();
        File[] fs = listed;
        if (fs == null) return;
        Arrays.sort(fs, new Comparator<File>() {
            @Override public int compare(File a, File b) {
                if (a.isDirectory() != b.isDirectory()) return a.isDirectory() ? -1 : 1;
                return a.getName().compareToIgnoreCase(b.getName());
            }
        });
        for (final File f : fs) {
            if (f.getName().startsWith(".")) continue;
            if (!f.isDirectory() && !allowed(f)) continue;
            LinearLayout r = new LinearLayout(this);
            r.setOrientation(LinearLayout.VERTICAL);
            r.setPadding(0, dp(9), 0, dp(9));
            TextView n = Ui.text(this, (f.isDirectory() ? "📁 " : "📄 ") + f.getName(), 18, true);
            r.addView(n);
            TextView s = Ui.text(this, f.isDirectory() ? "文件夹" : (f.length() / 1024) + " KB", 12, false);
            s.setTextColor(Color.DKGRAY); r.addView(s);
            r.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    if (f.isDirectory()) { open(f); return; }
                    // 用 Builder 编码路径：文件名里的 # ? % 用 Uri.parse 会被当成片段 / 查询 / 转义，对方打开就找不到文件
                    Uri u = new Uri.Builder().scheme("content").authority(VeraFileProvider.AUTHORITY).path(f.getAbsolutePath()).build();
                    Intent i = new Intent();
                    i.setData(u);
                    i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
                    setResult(RESULT_OK, i);
                    finish();
                }
            });
            r.addView(Ui.rule(this, 1, Color.LTGRAY));
            list.addView(r);
        }
    }

    private boolean allowed(File f) {
        String n = f.getName().toLowerCase();
        return n.endsWith(".json") || n.endsWith(".txt") || n.endsWith(".zip")
            || n.endsWith(".epub") || n.endsWith(".pdf") || n.endsWith(".mobi")
            || n.endsWith(".azw3") || n.endsWith(".apk");
    }

    private int dp(int v) { return Ui.dp(this, v); }
}
