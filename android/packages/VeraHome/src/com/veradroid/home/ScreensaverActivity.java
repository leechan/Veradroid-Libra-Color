package com.veradroid.home;

import android.app.Activity;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/**
 * 设置 → 设备与更新 → 屏保：Kindle 自带（默认）/ 轮换全部图片 / 只用一张；还能从内部存储导入图片。
 *
 * 图片来自两个地方：Android 的 /sdcard/Screensaver/（导入、传书网页都放这里）和 Kindle 存储的 veradroid/screensaver/
 * （USB 拷进去的；Android 看不到那个文件夹，宿主的 `saver list` 临时拷到 /dev/kfb/saver/ 给这里显示缩略图）。
 * 选择写到 /sdcard/Screensaver/.vd-saver，宿主每次进屏保时读（host/&#42;/boot/lib/saver.sh）。
 * 缩略图一页 3×3，一页的图全部解码好才换上去（一次刷新），翻页用按钮或横划，没有滚动和动画。
 */
public class ScreensaverActivity extends Activity {
    static final String SD_DIR = "/data/media/0/Screensaver";
    static final String SEL = SD_DIR + "/.vd-saver";
    private static final String VD_DIR = HostLink.KFB + "saver";
    private static final int COLS = 3, ROWS = 3, PER = COLS * ROWS;

    private final Handler handler = new Handler();
    private final List<Item> items = new ArrayList<Item>();
    private LinearLayout page, grid;
    private TextView modeText, pageLabel;
    private Blocks.Pager pager;
    private int pageNo;
    private String mode, file;   // 当前选择
    private int gen;             // 换页 / 重读时作废还在解码的上一批

    static final class Item {
        final String key;   // "kindle" | "sd/名字" | "vd/名字"
        final File f;       // 缩略图来源（Kindle 自带的预览可能没有）
        final String label;
        Item(String key, File f, String label) { this.key = key; this.f = f; this.label = label; }
    }

    @Override protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().setBackgroundDrawable(new android.graphics.drawable.ColorDrawable(Color.WHITE));
        getWindow().setWindowAnimations(0);
        page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);
        page.setBackgroundColor(Color.WHITE);
        page.setPadding(dp(16), dp(8), dp(16), dp(8));
        setContentView(page);
        TextView title = Ui.text(this, "屏保", 30, true);
        title.setPadding(0, dp(8), 0, dp(4));
        page.addView(title);
        modeText = Ui.text(this, "正在读取…", 17, false);
        modeText.setPadding(0, 0, 0, dp(8));
        page.addView(modeText);
        LinearLayout modes = new LinearLayout(this);
        modes.addView(Ui.button(this, "用 Kindle 自带的", 17, false, new View.OnClickListener() {
            @Override public void onClick(View v) { choose("kindle", null); }
        }), weight());
        modes.addView(Ui.button(this, "轮换全部图片", 17, false, new View.OnClickListener() {
            @Override public void onClick(View v) { choose("rotate", null); }
        }), weight());
        page.addView(modes);
        TextView hint = Ui.text(this, "点一张图：每次休眠都只用这一张。", 15, false);
        hint.setPadding(0, dp(10), 0, dp(4));
        page.addView(hint);
        grid = new PagedBox(this);
        grid.setOrientation(LinearLayout.VERTICAL);
        ((PagedBox) grid).setListener(new PagedBox.Listener() { @Override public void onPage(int dir) { turn(dir); } });
        page.addView(grid, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
        LinearLayout nav = new LinearLayout(this);
        nav.setGravity(Gravity.CENTER_VERTICAL);
        nav.addView(Ui.button(this, "上一页", 17, false, new View.OnClickListener() { @Override public void onClick(View v) { turn(-1); } }), weight());
        pageLabel = Ui.text(this, "", 17, false);
        pageLabel.setGravity(Gravity.CENTER);
        nav.addView(pageLabel, weight());
        nav.addView(Ui.button(this, "下一页", 17, false, new View.OnClickListener() { @Override public void onClick(View v) { turn(1); } }), weight());
        page.addView(nav);
        LinearLayout actions = new LinearLayout(this);
        actions.setPadding(0, dp(6), 0, 0);
        actions.addView(Ui.button(this, "返回", 17, false, new View.OnClickListener() { @Override public void onClick(View v) { finish(); } }), weight());
        actions.addView(Ui.button(this, "从内部存储导入…", 17, true, new View.OnClickListener() { @Override public void onClick(View v) { importImage(); } }), weight());
        page.addView(actions);
        if (Blocks.on(this)) {   // 方块风格：方块页头；“上一页 / 下一页”换成翻页条
            Blocks.restyle(this, page, title, actions, "Sleep / screensaver");
            int at = page.indexOfChild(nav);
            page.removeView(nav);
            pager = new Blocks.Pager(this, new Blocks.Pager.Listener() { @Override public void onPage(int dir) { turn(dir); } });
            page.addView(pager, at, Blocks.gap(this, 8));
        }
        readChoice();
        // 宿主把 veradroid/screensaver 的图拷出来（最多等 4 秒；宿主太旧就只显示 Android 里的图）
        new File(HostLink.CTL + "saver.listed").delete();
        HostLink.cmd("saver list");
        handler.postDelayed(new Runnable() {
            int n = 0;
            @Override public void run() {
                if (isFinishing()) return;
                if (new File(HostLink.CTL + "saver.listed").exists() || ++n > 20) { load(); return; }
                handler.postDelayed(this, 200);
            }
        }, 200);
    }

    @Override protected void onDestroy() {
        handler.removeCallbacksAndMessages(null);
        HostLink.cmd("saver done");
        super.onDestroy();
    }

    private int dp(int v) { return Ui.dp(this, v); }
    private LinearLayout.LayoutParams weight() { return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1); }

    private static boolean isImage(String n) {
        String s = n.toLowerCase(java.util.Locale.ROOT);
        return !s.startsWith(".") && (s.endsWith(".png") || s.endsWith(".jpg") || s.endsWith(".jpeg"));
    }

    private static List<File> images(String dir) {
        List<File> out = new ArrayList<File>();
        File[] l = new File(dir).listFiles();
        if (l == null) return out;
        Arrays.sort(l, new Comparator<File>() { @Override public int compare(File a, File b) { return a.getName().compareToIgnoreCase(b.getName()); } });
        for (File f : l) if (f.isFile() && isImage(f.getName()) && !f.getName().equalsIgnoreCase("default.png")) out.add(f);
        return out;
    }

    private void load() {
        items.clear();
        File kp = new File(VD_DIR, ".kindle-preview.png");
        items.add(new Item("kindle", kp.isFile() ? kp : null, "Kindle 自带"));
        for (File f : images(SD_DIR)) items.add(new Item("sd/" + f.getName(), f, f.getName()));
        for (File f : images(VD_DIR)) items.add(new Item("vd/" + f.getName(), f, f.getName() + "（USB）"));
        if (mode == null) mode = items.size() > 1 ? "rotate" : "kindle";   // 没选过：宿主照旧做法，有用户图就轮换
        pageNo = 0;
        showMode();
        renderPage();
    }

    private void readChoice() {
        mode = null; file = null;
        java.util.Map<String, String> m = HostLink.kv(SEL);
        String md = m.get("mode");
        if ("kindle".equals(md) || "rotate".equals(md) || "one".equals(md)) { mode = md; file = m.get("file"); }
    }

    private void showMode() {
        String s;
        if ("one".equals(mode) && file != null) s = "当前：只用一张（" + file.substring(file.indexOf('/') + 1) + "）";
        else if ("rotate".equals(mode)) s = "当前：轮换全部图片（共 " + (items.size() - 1) + " 张，没有图片时用 Kindle 自带的）";
        else s = "当前：Kindle 自带的屏保";
        modeText.setText(s);
    }

    private void choose(String m, String f) {
        try {
            new File(SD_DIR).mkdirs();
            File tmp = new File(SD_DIR, ".vd-saver.tmp");
            FileWriter w = new FileWriter(tmp);
            w.write("mode=" + m + "\n" + (f != null ? "file=" + f + "\n" : ""));
            w.close();
            if (!tmp.renameTo(new File(SEL))) throw new java.io.IOException("rename");
            new File(SEL).setReadable(true, false);
            mode = m; file = f;
        } catch (Exception e) {
            VeraToast.show(this, "没能保存选择：" + e.getMessage());
            return;
        }
        showMode();
        renderPage();
    }

    private void turn(int dir) {
        int pages = Math.max(1, (items.size() + PER - 1) / PER);
        int np = Math.max(0, Math.min(pages - 1, pageNo + dir));
        if (np == pageNo) return;
        pageNo = np;
        renderPage();
    }

    private boolean selected(Item it) {
        if (it.key.equals("kindle")) return "kindle".equals(mode);
        return "one".equals(mode) && it.key.equals(file);
    }

    /** 这一页的缩略图在后台解码，全部好了才一次换上（墨水屏只刷一次）。 */
    private void renderPage() {
        final int my = ++gen;
        final int from = pageNo * PER, to = Math.min(items.size(), from + PER);
        int pages = Math.max(1, (items.size() + PER - 1) / PER);
        pageLabel.setText((pageNo + 1) + " / " + pages);
        if (pager != null) pager.set(pageNo + 1, pages);
        final int cw = Math.max(dp(80), (getResources().getDisplayMetrics().widthPixels - dp(32)) / COLS - dp(12));
        final int ch = cw * 4 / 3;
        new Thread(new Runnable() {
            @Override public void run() {
                final Bitmap[] bm = new Bitmap[to - from];
                for (int i = from; i < to && my == gen; i++) bm[i - from] = thumb(items.get(i).f, cw, ch);
                handler.post(new Runnable() { @Override public void run() { if (my == gen && !isFinishing()) fill(from, to, bm, cw, ch); } });
            }
        }, "saver-thumbs").start();
    }

    private void fill(int from, int to, Bitmap[] bm, int cw, int ch) {
        grid.removeAllViews();
        LinearLayout row = null;
        for (int i = 0; i < PER; i++) {
            if (i % COLS == 0) {
                row = new LinearLayout(this);
                row.setGravity(Gravity.CENTER_HORIZONTAL);
                grid.addView(row, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
            }
            LinearLayout cell = new LinearLayout(this);
            cell.setOrientation(LinearLayout.VERTICAL);
            cell.setGravity(Gravity.CENTER_HORIZONTAL);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.MATCH_PARENT, 1);
            lp.setMargins(dp(4), dp(4), dp(4), dp(4));
            row.addView(cell, lp);
            int idx = from + i;
            if (idx >= to) continue;
            final Item it = items.get(idx);
            boolean sel = selected(it);
            GradientDrawable bg = new GradientDrawable();
            bg.setColor(Color.WHITE);
            bg.setStroke(sel ? dp(4) : 2, Color.BLACK);
            cell.setBackground(bg);
            cell.setPadding(dp(4), dp(4), dp(4), dp(4));
            if (bm[i] != null) {
                ImageView iv = new ImageView(this);
                iv.setImageBitmap(bm[i]);
                iv.setScaleType(ImageView.ScaleType.FIT_CENTER);
                cell.addView(iv, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
            } else {
                TextView none = Ui.text(this, it.key.equals("kindle") ? "Kindle\n自带" : "无法预览", 18, true);
                none.setGravity(Gravity.CENTER);
                cell.addView(none, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1));
            }
            TextView name = Ui.text(this, (sel ? "[当前] " : "") + it.label, 13, sel);
            name.setSingleLine(true);
            name.setEllipsize(android.text.TextUtils.TruncateAt.MIDDLE);
            name.setGravity(Gravity.CENTER);
            cell.addView(name, new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            cell.setClickable(true);
            cell.setOnClickListener(new View.OnClickListener() {
                @Override public void onClick(View v) {
                    if (it.key.equals("kindle")) choose("kindle", null); else choose("one", it.key);
                }
            });
            Ui.fast(cell);
        }
    }

    /** 灰度、按格子大小缩小；坏图 / 太大的图返回 null。 */
    static Bitmap thumb(File f, int w, int h) {
        if (f == null || !f.isFile() || f.length() > 16L * 1024 * 1024) return null;
        try {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(f.getPath(), o);
            if (o.outWidth <= 0 || o.outHeight <= 0) return null;
            int s = 1;
            while (o.outWidth / (s * 2) >= w && o.outHeight / (s * 2) >= h) s *= 2;
            o = new BitmapFactory.Options();
            o.inSampleSize = s;
            o.inPreferredConfig = Bitmap.Config.RGB_565;
            return BitmapFactory.decodeFile(f.getPath(), o);
        } catch (Throwable t) {
            return null;
        }
    }

    /** 从内部存储（Pictures、Download、Kindle 的 documents……）挑一张，复制进 /sdcard/Screensaver/ 并设成“只用这一张”。 */
    private void importImage() {
        new Thread(new Runnable() {
            @Override public void run() {
                final List<File> all = Theme.findImages();
                final List<File> imgs = new ArrayList<File>();
                for (File f : all) if (!f.getParent().equals(SD_DIR) && isImage(f.getName())) imgs.add(f);
                handler.post(new Runnable() {
                    @Override public void run() {
                        if (isFinishing()) return;
                        if (imgs.isEmpty()) {
                            new VeraDialog.Builder(ScreensaverActivity.this).title("导入屏保图片")
                                .message("没有找到 jpg / png 图片。用传书网页上传到内部存储，或用 USB 把图片放进 Kindle 的 veradroid/screensaver 文件夹。")
                                .positive("知道了", null).show();
                            return;
                        }
                        String[] names = new String[imgs.size()];
                        for (int i = 0; i < names.length; i++) names[i] = imgs.get(i).getName() + "\n" + Theme.placeLabel(imgs.get(i)) + " · " + Math.max(1, imgs.get(i).length() / 1024) + " KB";
                        new VeraDialog.Builder(ScreensaverActivity.this).title("导入屏保图片").items(names, new VeraDialog.OnPick() {
                            @Override public void onPick(int which) { copyIn(imgs.get(which)); }
                        }).negative("取消", null).show();
                    }
                });
            }
        }, "saver-find").start();
    }

    private void copyIn(File src) {
        try {
            File dir = new File(SD_DIR);
            dir.mkdirs();
            String name = src.getName().replaceAll("[^A-Za-z0-9._\\-\\u4e00-\\u9fa5]", "_");
            File dst = new File(dir, name);
            InputStream in = new FileInputStream(src);
            OutputStream out = new FileOutputStream(dst);
            byte[] buf = new byte[65536];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            in.close(); out.close();
            dst.setReadable(true, false);
            choose("one", "sd/" + name);
            load();
            for (int i = 0; i < items.size(); i++) if (items.get(i).key.equals("sd/" + name)) { pageNo = i / PER; renderPage(); break; }
            VeraToast.show(this, "已导入并设为屏保");
        } catch (Exception e) {
            VeraToast.show(this, "导入失败：" + e.getMessage());
        }
    }
}
