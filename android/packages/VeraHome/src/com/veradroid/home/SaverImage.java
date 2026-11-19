package com.veradroid.home;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Matrix;
import android.util.DisplayMetrics;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FileWriter;
import java.io.OutputStream;
import java.util.Set;

/**
 * 屏保图片转成这块屏用的灰度 PNG（fix/saver-formats，格式判断和 PNG 编码在 SaverFormat）。
 *
 * 桌面的屏保页打开时、导入一张图时做：Android 能解 jpg / png / webp / bmp / gif（含渐进式、CMYK 的 JPEG），宿主的 fbink
 * 只认 PNG / JPEG / BMP / GIF，几十兆的照片在休眠那一刻解码也慢。转好的图按面板大小（宿主写的 /dev/kfb/saver/.panel = fbink 看到的
 * 宽 高）按比例缩放，照片的 EXIF 方向转正，放在 Screensaver/.vd-cache/，旁边的 .src 记原图的“字节数 修改时间”。
 */
final class SaverImage {
    private SaverImage() {}

    static final String CACHE = ScreensaverActivity.SD_DIR + "/.vd-cache";
    /** 太大的文件不转（宿主导出 veradroid/screensaver 的上限是 32 MB；Android 里的文件也按这个说）。 */
    static final long MAX_BYTES = 32L * 1024 * 1024;

    /** 屏保画在多大的屏上（竖着：宽 ≤ 高）。先看宿主写的 .panel，再看 /dev/kfb/info，最后用显示尺寸。 */
    static int[] panel(Context c) {
        int[] p = readPair(new File(HostLink.KFB + "saver/.panel"));
        if (p == null) p = readPair(new File(HostLink.KFB + "info"));
        if (p == null) {
            DisplayMetrics m = new DisplayMetrics();
            ((android.view.WindowManager) c.getSystemService(Context.WINDOW_SERVICE)).getDefaultDisplay().getRealMetrics(m);
            p = new int[] { m.widthPixels, m.heightPixels };
        }
        return new int[] { Math.min(p[0], p[1]), Math.max(p[0], p[1]) };
    }

    private static int[] readPair(File f) {
        try {
            java.util.Scanner s = new java.util.Scanner(f);
            try {
                int a = s.nextInt(), b = s.nextInt();
                return a >= 200 && b >= 200 && a <= 8192 && b <= 8192 ? new int[] { a, b } : null;
            } finally { s.close(); }
        } catch (Exception e) { return null; }
    }

    /** 快速判断这张能不能用（只读文件头和尺寸）：null = 能用，否则是给用户看的原因。 */
    static String check(File f) {
        if (f == null || !f.isFile()) return "文件不在了";
        if (f.length() == 0) return "是空文件（0 字节）";
        if (f.length() > MAX_BYTES) return "太大（" + (f.length() >> 20) + " MB）：请缩小到 32 MB 以内";
        String kind = SaverFormat.sniff(f);
        String why = SaverFormat.unsupportedReason(kind, f.getName());
        if (why != null) return why;
        if (!SaverFormat.androidDecodes(kind)) return "这种格式用不了：请转成 JPG 或 PNG";
        BitmapFactory.Options o = new BitmapFactory.Options();
        o.inJustDecodeBounds = true;
        try { BitmapFactory.decodeFile(f.getPath(), o); } catch (Throwable t) { o.outWidth = -1; }
        if (o.outWidth <= 0 || o.outHeight <= 0) return "图片打不开（文件可能坏了，或者没传完整）";
        if (!SaverFormat.complete(kind, tail(f, 4096))) return "图片不完整（没传完或文件坏了）：请重新拷一次";
        return null;
    }

    private static byte[] tail(File f, int n) {
        try {
            java.io.RandomAccessFile r = new java.io.RandomAccessFile(f, "r");
            try {
                long len = r.length(); int k = (int) Math.min(n, len);
                byte[] b = new byte[k]; r.seek(len - k); r.readFully(b); return b;
            } finally { r.close(); }
        } catch (Exception e) { return null; }
    }

    static File cacheFile(String key) { return SaverFormat.cacheFile(CACHE, key); }

    static boolean cacheValid(String key, File src) {
        File c = cacheFile(key), s = new File(c.getPath() + ".src");
        if (!c.isFile() || c.length() == 0 || !s.isFile()) return false;
        return SaverFormat.stamp(src.length(), src.lastModified()).equals(readLine(s));
    }

    private static String readLine(File f) {
        try {
            java.io.BufferedReader r = new java.io.BufferedReader(new java.io.FileReader(f));
            try { String l = r.readLine(); return l == null ? "" : l.trim(); } finally { r.close(); }
        } catch (Exception e) { return ""; }
    }

    /** 转一张。null = 好了（或者本来就是最新的），否则是原因。在后台线程调。 */
    static synchronized String convert(String key, File src, int pw, int ph) {   // 一次一张（导入和页面的转换线程可能同时来）
        String why = check(src);
        if (why != null) return why;
        if (cacheValid(key, src)) return null;
        String kind = SaverFormat.sniff(src);
        Bitmap b = null;
        try {
            BitmapFactory.Options o = new BitmapFactory.Options();
            o.inJustDecodeBounds = true;
            BitmapFactory.decodeFile(src.getPath(), o);
            int rot = "jpeg".equals(kind) ? exif(src) : 1;
            boolean swap = rot >= 5 && rot <= 8;                 // 6 / 8 = 转 90°，5 / 7 = 转 90° 再镜像
            int ow = swap ? o.outHeight : o.outWidth, oh = swap ? o.outWidth : o.outHeight;
            int[] t = SaverFormat.fit(ow, oh, pw, ph);
            BitmapFactory.Options d = new BitmapFactory.Options();
            d.inSampleSize = SaverFormat.sampleSize(ow, oh, t[0], t[1]);
            d.inPreferredConfig = Bitmap.Config.ARGB_8888;
            b = BitmapFactory.decodeFile(src.getPath(), d);
            if (b == null) return "图片解不开（文件可能坏了）";
            b = rotate(b, rot);
            if (b.getWidth() != t[0] || b.getHeight() != t[1]) {
                Bitmap s = Bitmap.createScaledBitmap(b, t[0], t[1], true);
                if (s != b) { b.recycle(); b = s; }
            }
            int w = b.getWidth(), h = b.getHeight();
            boolean keepAlpha = "png".equals(kind) && b.hasAlpha();   // 透明 PNG 照旧叠在当前页上；别的格式铺白底
            byte[] g = new byte[w * h], a = keepAlpha ? new byte[w * h] : null;
            int[] row = new int[w];
            boolean anyClear = false;
            for (int y = 0; y < h; y++) {
                b.getPixels(row, 0, w, 0, y, w, 1);
                for (int x = 0; x < w; x++) {
                    int p = row[x], al = p >>> 24, v = SaverFormat.gray(p);
                    if (keepAlpha) { a[y * w + x] = (byte) al; if (al < 255) anyClear = true; }
                    else if (al < 255) v = (v * al + 255 * (255 - al) + 127) / 255;
                    g[y * w + x] = (byte) v;
                }
            }
            b.recycle(); b = null;
            if (keepAlpha && !anyClear) a = null;
            File dir = new File(CACHE);
            dir.mkdirs();
            dir.setReadable(true, false); dir.setExecutable(true, false);
            File out = cacheFile(key), tmp = new File(out.getPath() + ".tmp");
            OutputStream os = new BufferedOutputStream(new FileOutputStream(tmp), 65536);
            try { SaverFormat.writePng(os, w, h, g, a); } finally { os.close(); }
            File stamp = new File(out.getPath() + ".src"), stmp = new File(stamp.getPath() + ".tmp");
            FileWriter fw = new FileWriter(stmp);
            try { fw.write(SaverFormat.stamp(src.length(), src.lastModified()) + "\n"); } finally { fw.close(); }
            stamp.delete();                                  // 先让旧的 .src 失效，宿主不会拿新原图配旧转换图
            if (!tmp.renameTo(out)) throw new java.io.IOException("rename");
            out.setReadable(true, false);
            if (!stmp.renameTo(stamp)) throw new java.io.IOException("rename");
            stamp.setReadable(true, false);
            return null;
        } catch (OutOfMemoryError e) {
            return "分辨率太高，内存不够转换：请缩小一些再放进来";
        } catch (Throwable e) {
            return "转换失败：" + e.getMessage();
        } finally {
            if (b != null) b.recycle();
        }
    }

    /** EXIF 方向 1–8 转正（返回新图时旧图已回收）。 */
    static Bitmap rotate(Bitmap b, int rot) {
        if (rot <= 1 || rot > 8) return b;
        Matrix m = new Matrix();
        switch (rot) {
            case 2: m.setScale(-1, 1); break;
            case 3: m.setRotate(180); break;
            case 4: m.setScale(1, -1); break;
            case 5: m.setRotate(90); m.postScale(-1, 1); break;
            case 6: m.setRotate(90); break;
            case 7: m.setRotate(-90); m.postScale(-1, 1); break;
            case 8: m.setRotate(-90); break;
        }
        Bitmap r = Bitmap.createBitmap(b, 0, 0, b.getWidth(), b.getHeight(), m, true);
        if (r != b) b.recycle();
        return r;
    }

    /** 缩略图用：JPEG 按 EXIF 转正。 */
    static Bitmap upright(Bitmap b, File f) {
        return "jpeg".equals(SaverFormat.sniff(f)) ? rotate(b, exif(f)) : b;
    }

    private static int exif(File f) {
        try {
            return new android.media.ExifInterface(f.getPath()).getAttributeInt(android.media.ExifInterface.TAG_ORIENTATION, 1);
        } catch (Throwable t) { return 1; }
    }

    /** 删掉原图已经不在了的转换图（keys = 现在两个文件夹里的全部 "sd/名字"、"vd/名字"）。宿主没导出 veradroid/screensaver 时
     *  （宿主太旧、4 秒没回）不知道那边有哪些图，vd- 的不删（withVd = false）。 */
    static void prune(Set<String> keys, boolean withVd) {
        File[] l = new File(CACHE).listFiles();
        if (l == null) return;
        for (File f : l) {
            String n = f.getName();
            String base = n.endsWith(".png.src") ? n.substring(0, n.length() - 4) : n.endsWith(".png.tmp") ? null : n;
            if (base == null || !base.endsWith(".png") || base.length() < 8) { if (n.endsWith(".tmp")) f.delete(); continue; }
            String k = base.substring(0, 2) + "/" + base.substring(3, base.length() - 4);
            if ((base.startsWith("sd-") || (withVd && base.startsWith("vd-"))) && !keys.contains(k)) f.delete();
        }
    }
}
