package com.veradroid.home;

import java.awt.image.BufferedImage;
import java.awt.image.Raster;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;

import javax.imageio.ImageIO;

/**
 * 屏保图片格式（SaverFormat.java，fix/saver-formats）：扩展名、文件头、缩放、灰度 PNG 编码（用 JDK 的 ImageIO 读回来对像素）。
 * java com.veradroid.home.SaverFormatTest
 */
public class SaverFormatTest {
    static int fails = 0;
    static void check(boolean ok, String what) { if (!ok) { fails++; System.out.println("FAIL " + what); } }

    static byte[] b(int... v) { byte[] o = new byte[v.length]; for (int i = 0; i < v.length; i++) o[i] = (byte) v[i]; return o; }
    static byte[] s(String head, int pad) { byte[] h = head.getBytes(java.nio.charset.Charset.forName("ISO-8859-1")); byte[] o = new byte[h.length + pad]; System.arraycopy(h, 0, o, 0, h.length); return o; }
    static String sn(byte[] h) { return SaverFormat.sniff(h, h.length); }

    public static void main(String[] a) throws Exception {
        for (String n : new String[] { "a.png", "B.PNG", "c.JPG", "d.jpeg", "e.Jpe", "f.webp", "g.WEBP", "h.bmp", "i.GIF", "j.heic", "k.HEIF", "l.jfif" })
            check(SaverFormat.isCandidate(n), "candidate " + n);
        for (String n : new String[] { ".hidden.png", "把屏保图片放这里.txt", "png", "x.pdf", "x.png.part", "" })
            check(!SaverFormat.isCandidate(n), "not candidate " + n);

        check("png".equals(sn(b(0x89, 'P', 'N', 'G', 13, 10, 26, 10, 0, 0, 0, 13))), "png");
        check("jpeg".equals(sn(b(0xff, 0xd8, 0xff, 0xe0, 0, 16, 'J', 'F', 'I', 'F', 0, 1))), "jpeg jfif");
        check("jpeg".equals(sn(b(0xff, 0xd8, 0xff, 0xee, 0, 14, 'A', 'd', 'o', 'b', 'e', 0))), "jpeg adobe (cmyk)");
        check("gif".equals(sn(s("GIF89a", 6))), "gif");
        check("bmp".equals(sn(s("BM", 10))), "bmp");
        check("webp".equals(sn(s("RIFF\0\0\0\0WEBPVP8 ", 0))), "webp");
        check("heic".equals(sn(s("\0\0\0\030ftypheic", 4))), "heic");
        check("heic".equals(sn(s("\0\0\0\030ftypmif1", 4))), "heic mif1");
        check("avif".equals(sn(s("\0\0\0\034ftypavif", 4))), "avif");
        check(sn(s("\0\0\0\030ftypisom", 4)) == null, "mp4 is not an image");
        check("tiff".equals(sn(b('I', 'I', 42, 0, 8, 0, 0, 0))), "tiff");
        check(sn(s("%PDF-1.4", 4)) == null, "pdf");
        check(sn(new byte[0]) == null, "empty");
        check(SaverFormat.complete("jpeg", b(1, 2, 0xff, 0xd9)) && SaverFormat.complete("jpeg", b(0xff, 0xd9, 0, 0, 0)), "jpeg with EOI");
        check(!SaverFormat.complete("jpeg", b(1, 2, 3, 0xff)), "cut-short jpeg");
        check(SaverFormat.complete("png", s("xxIEND\256B`\202", 0)) && !SaverFormat.complete("png", s("IDATxxxx", 0)), "png IEND");
        check(SaverFormat.complete("webp", new byte[] { 1 }) && SaverFormat.complete("jpeg", null), "other formats / unreadable count as complete");
        check(SaverFormat.androidDecodes("webp") && SaverFormat.androidDecodes("jpeg") && !SaverFormat.androidDecodes("heic"), "android decodes");
        check(SaverFormat.unsupportedReason("heic", "x.heic").contains("JPG"), "heic reason says convert to JPG");
        check(SaverFormat.unsupportedReason("webp", "x.webp") == null, "webp is fine");

        check(SaverFormat.cacheFile("/c", "sd/我的 图.WEBP").getPath().equals("/c/sd-我的 图.WEBP.png"), "cache name sd");
        check(SaverFormat.cacheFile("/c", "vd/a.jpg").getPath().equals("/c/vd-a.jpg.png"), "cache name vd");
        check(SaverFormat.stamp(1234, 1700000000999L).equals("1234 1700000000"), "stamp = stat -c '%s %Y'");

        int[] f = SaverFormat.fit(4000, 3000, 1272, 1696);
        check(f[0] == 1272 && f[1] == 954, "landscape photo into PW6: " + f[0] + "x" + f[1]);
        f = SaverFormat.fit(3000, 4000, 1272, 1696);
        check(f[0] == 1272 && f[1] == 1696, "portrait 3:4 fills PW6: " + f[0] + "x" + f[1]);
        f = SaverFormat.fit(300, 1000, 1272, 1696);
        check(f[0] == 509 && f[1] == 1696, "tall small image scaled up: " + f[0] + "x" + f[1]);
        f = SaverFormat.fit(20000, 100, 758, 1024);
        check(f[0] == 758 && f[1] >= 1, "very wide: " + f[0] + "x" + f[1]);
        check(SaverFormat.sampleSize(12000, 9000, 1272, 954) == 8, "sample 12000 -> 1272: " + SaverFormat.sampleSize(12000, 9000, 1272, 954));
        check(SaverFormat.sampleSize(1000, 1000, 1272, 1272) == 1, "no sampling when smaller");
        check(SaverFormat.gray(0xffffffff) == 255 && SaverFormat.gray(0xff000000) == 0 && SaverFormat.gray(0xffff0000) == 76, "gray");

        // PNG 编码：灰度 + 灰度带透明，JDK 读回来逐像素一样
        int w = 37, h = 23;
        byte[] g = new byte[w * h], al = new byte[w * h];
        for (int i = 0; i < g.length; i++) { g[i] = (byte) (i * 7); al[i] = (byte) (i * 13); }
        ByteArrayOutputStream o = new ByteArrayOutputStream();
        SaverFormat.writePng(o, w, h, g, null);
        BufferedImage im = ImageIO.read(new ByteArrayInputStream(o.toByteArray()));
        check(im != null && im.getWidth() == w && im.getHeight() == h && im.getRaster().getNumBands() == 1, "gray png readable");
        boolean same = im != null;
        if (im != null) { Raster r = im.getRaster(); for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) same &= r.getSample(x, y, 0) == (g[y * w + x] & 0xff); }
        check(same, "gray png pixels");
        check((o.toByteArray()[25] & 0xff) == 0, "colour type 0 (host draws it opaque)");
        o = new ByteArrayOutputStream();
        SaverFormat.writePng(o, w, h, g, al);
        im = ImageIO.read(new ByteArrayInputStream(o.toByteArray()));
        check(im != null && im.getRaster().getNumBands() == 2, "gray+alpha png readable");
        same = im != null;
        if (im != null) { Raster r = im.getRaster(); for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) same &= r.getSample(x, y, 0) == (g[y * w + x] & 0xff) && r.getSample(x, y, 1) == (al[y * w + x] & 0xff); }
        check(same, "gray+alpha png pixels");
        check((o.toByteArray()[25] & 0xff) == 4, "colour type 4 (host overlays it on the page)");
        // 面板大小的整屏图：大小合理（白底 + 渐变）
        w = 1272; h = 1696; g = new byte[w * h];
        for (int i = 0; i < g.length; i++) g[i] = (byte) (255 - (i / w) * 255 / h);
        o = new ByteArrayOutputStream();
        long t0 = System.currentTimeMillis();
        SaverFormat.writePng(o, w, h, g, null);
        System.out.println("1272x1696 gradient: " + o.size() + " bytes, " + (System.currentTimeMillis() - t0) + " ms");
        check(o.size() < w * h / 4, "full-screen gray png compresses");

        System.out.println(fails == 0 ? "SaverFormatTest: ok" : "SaverFormatTest: " + fails + " failure(s)");
        System.exit(fails == 0 ? 0 : 1);
    }
}
