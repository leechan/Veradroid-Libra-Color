package com.veradroid.home;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.Locale;
import java.util.zip.CRC32;
import java.util.zip.Deflater;

/**
 * 屏保图片的格式（fix/saver-formats）：只用纯 Java（tests-jvm 里能测），Android 的解码 / 转换在 SaverImage。
 *
 * 宿主进屏保时用 fbink 画图，它认 PNG / JPEG / BMP / GIF；webp、手机的 heic 画不了。以前桌面和宿主都只认扩展名 png / jpg / jpeg，
 * 别的放进去不报错也不显示。现在桌面打开屏保页时把每张图转成这块屏大小的灰度 PNG（.vd-cache/），宿主优先画转好的那张
 * （host/&#42;/boot/lib/saver.sh 的 saver_cached：.src 里“字节数 修改时间”和原图一样才用）。
 */
final class SaverFormat {
    private SaverFormat() {}

    /** 当成屏保图片的扩展名（不分大小写）：和宿主 saver.sh 的 SAVER_EXTS 一样。 */
    static final String[] EXTS = { "png", "jpg", "jpeg", "jpe", "jfif", "bmp", "gif", "webp", "heic", "heif", "avif", "tif", "tiff" };

    static boolean isCandidate(String name) {
        if (name == null || name.startsWith(".")) return false;
        int d = name.lastIndexOf('.');
        if (d <= 0) return false;
        String e = name.substring(d + 1).toLowerCase(Locale.ROOT);
        for (String x : EXTS) if (x.equals(e)) return true;
        return false;
    }

    /** 看文件头：png / jpeg / gif / bmp / webp / heic / avif / tiff，认不出来返回 null。 */
    static String sniff(byte[] h, int n) {
        if (n >= 8 && (h[0] & 0xff) == 0x89 && h[1] == 'P' && h[2] == 'N' && h[3] == 'G') return "png";
        if (n >= 3 && (h[0] & 0xff) == 0xff && (h[1] & 0xff) == 0xd8 && (h[2] & 0xff) == 0xff) return "jpeg";
        if (n >= 6 && h[0] == 'G' && h[1] == 'I' && h[2] == 'F' && h[3] == '8') return "gif";
        if (n >= 2 && h[0] == 'B' && h[1] == 'M') return "bmp";
        if (n >= 12 && h[0] == 'R' && h[1] == 'I' && h[2] == 'F' && h[3] == 'F' && h[8] == 'W' && h[9] == 'E' && h[10] == 'B' && h[11] == 'P') return "webp";
        if (n >= 12 && h[4] == 'f' && h[5] == 't' && h[6] == 'y' && h[7] == 'p') {
            String brand = new String(h, 8, 4, java.nio.charset.Charset.forName("ISO-8859-1"));
            if (brand.startsWith("avi")) return "avif";
            if (brand.startsWith("hei") || brand.startsWith("hev") || brand.equals("mif1") || brand.equals("msf1")) return "heic";
            return null;                                                     // mp4 之类的视频
        }
        if (n >= 4 && ((h[0] == 'I' && h[1] == 'I' && h[2] == 42 && h[3] == 0) || (h[0] == 'M' && h[1] == 'M' && h[2] == 0 && h[3] == 42))) return "tiff";
        return null;
    }

    static String sniff(File f) {
        byte[] h = new byte[16];
        int n = 0;
        try {
            InputStream in = new FileInputStream(f);
            try { int r; while (n < h.length && (r = in.read(h, n, h.length - n)) > 0) n += r; } finally { in.close(); }
        } catch (IOException e) { return null; }
        return sniff(h, n);
    }

    /**
     * 文件是不是完整的（没传完 / 截断的 JPEG、PNG 也能解出半张图，剩下的是黑的或灰的）：JPEG 最后 4 KB 里要有结束标记 FF D9，
     * PNG 要有 IEND。别的格式不查。tail = 文件最后几 KB（null = 读不了，算完整）。宿主 saver_resolve 用同样的规则。
     */
    static boolean complete(String kind, byte[] tail) {
        if (tail == null) return true;
        if ("jpeg".equals(kind)) {
            for (int i = tail.length - 2; i >= 0; i--) if ((tail[i] & 0xff) == 0xff && (tail[i + 1] & 0xff) == 0xd9) return true;
            return false;
        }
        if ("png".equals(kind)) {
            for (int i = tail.length - 4; i >= 0; i--) if (tail[i] == 'I' && tail[i + 1] == 'E' && tail[i + 2] == 'N' && tail[i + 3] == 'D') return true;
            return false;
        }
        return true;
    }

    /** Android 7.1 的 BitmapFactory 能解的（heic / avif / tiff 不能：Android 8.1 / 9 以后才有 heic）。 */
    static boolean androidDecodes(String kind) {
        return "png".equals(kind) || "jpeg".equals(kind) || "gif".equals(kind) || "bmp".equals(kind) || "webp".equals(kind);
    }

    /** 用不了的格式给用户看的话（null = 这种格式能用）。 */
    static String unsupportedReason(String kind, String name) {
        if (kind == null) return "不是能用的图片（打不开文件头，可能是别的文件改了扩展名，或者文件坏了）";
        if ("heic".equals(kind)) return "HEIC 格式（手机拍的照片）用不了：请先在手机或电脑上转成 JPG 再放进来";
        if ("avif".equals(kind)) return "AVIF 格式用不了：请先转成 JPG 或 PNG";
        if ("tiff".equals(kind)) return "TIFF 格式用不了：请先转成 JPG 或 PNG";
        return null;
    }

    /** 转好的灰度 PNG 放在哪：key = "sd/名字" 或 "vd/名字" → Screensaver/.vd-cache/sd-名字.png（宿主 saver_cached 同一规则）。 */
    static File cacheFile(String cacheDir, String key) {
        int s = key.indexOf('/');
        return new File(cacheDir, key.substring(0, s) + "-" + key.substring(s + 1) + ".png");
    }

    /** 原图的“字节数 修改时间（秒）”：和宿主 stat -c '%s %Y' 的输出一样。 */
    static String stamp(long length, long lastModifiedMs) {
        return length + " " + (lastModifiedMs / 1000);
    }

    /** 按比例放进 pw × ph（放大缩小都做，和 fbink 的 w=-2,h=-2 一样），返回 {宽, 高}。 */
    static int[] fit(int w, int h, int pw, int ph) {
        if (w <= 0 || h <= 0) return new int[] { pw, ph };
        long a = (long) pw * h, b = (long) ph * w;   // pw/w 和 ph/h 比大小
        int tw, th;
        if (a <= b) { tw = pw; th = (int) Math.max(1, Math.round((double) h * pw / w)); }
        else { th = ph; tw = (int) Math.max(1, Math.round((double) w * ph / h)); }
        return new int[] { Math.min(tw, pw), Math.min(th, ph) };
    }

    /** BitmapFactory 的 inSampleSize：2 的幂，缩完仍不小于目标（大图按比例先粗缩，省内存）。 */
    static int sampleSize(int w, int h, int tw, int th) {
        int s = 1;
        while (w / (s * 2) >= tw && h / (s * 2) >= th) s *= 2;
        return s;
    }

    /** ARGB 像素 → 灰度（BT.601）。透明的地方按白底算，alpha 另给（keepAlpha 时）。 */
    static int gray(int argb) {
        int r = (argb >> 16) & 0xff, g = (argb >> 8) & 0xff, b = argb & 0xff;
        return (r * 299 + g * 587 + b * 114 + 500) / 1000;
    }

    /**
     * 写 8 位灰度 PNG（颜色类型 0），alpha != null 时写灰度 + 透明（类型 4，宿主把它叠在正在读的那一页上）。
     * Android 的 Bitmap.compress 只会写 RGB(A)，fbink 解出来还要再转灰度；自己写的灰度 PNG 小一半以上。
     */
    static void writePng(OutputStream out, int w, int h, byte[] gray, byte[] alpha) throws IOException {
        int ch = alpha != null ? 2 : 1;
        out.write(new byte[] { (byte) 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' });
        ByteArrayOutputStream ih = new ByteArrayOutputStream();
        int32(ih, w); int32(ih, h);
        ih.write(8); ih.write(alpha != null ? 4 : 0); ih.write(0); ih.write(0); ih.write(0);
        chunk(out, "IHDR", ih.toByteArray(), ih.size());
        Deflater d = new Deflater(6);
        ByteArrayOutputStream z = new ByteArrayOutputStream(w * h / 3 + 1024);
        byte[] row = new byte[1 + w * ch], buf = new byte[65536];
        for (int y = 0; y < h; y++) {
            row[0] = 0;
            int o = y * w;
            if (ch == 1) System.arraycopy(gray, o, row, 1, w);
            else for (int x = 0; x < w; x++) { row[1 + 2 * x] = gray[o + x]; row[2 + 2 * x] = alpha[o + x]; }
            d.setInput(row);
            while (!d.needsInput()) { int k = d.deflate(buf); z.write(buf, 0, k); }
        }
        d.finish();
        while (!d.finished()) { int k = d.deflate(buf); z.write(buf, 0, k); }
        d.end();
        chunk(out, "IDAT", z.toByteArray(), z.size());
        chunk(out, "IEND", new byte[0], 0);
    }

    private static void int32(OutputStream o, int v) throws IOException {
        o.write(v >>> 24); o.write(v >>> 16); o.write(v >>> 8); o.write(v);
    }

    private static void chunk(OutputStream out, String type, byte[] data, int len) throws IOException {
        byte[] t = type.getBytes("ISO-8859-1");
        int32(out, len);
        out.write(t);
        out.write(data, 0, len);
        CRC32 c = new CRC32();
        c.update(t);
        c.update(data, 0, len);
        int32(out, (int) c.getValue());
    }
}
