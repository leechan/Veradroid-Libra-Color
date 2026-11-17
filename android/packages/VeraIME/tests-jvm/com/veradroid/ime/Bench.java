package com.veradroid.ime;

import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;

/** Bench: every prefix of the test sentences, N rounds (for profiling: java -Xint ... Bench pinyin.dat N) */
public class Bench {
    public static void main(String[] a) throws Exception {
        RandomAccessFile f = new RandomAccessFile(a[0], "r");
        ByteBuffer b = f.getChannel().map(FileChannel.MapMode.READ_ONLY, 0, f.length());
        PinyinDecoder dec = new PinyinDecoder(new PinyinDict(b));
        dec.setUser(new UserDict(new PinyinDict(b)));
        String[] s = { "zhongguoren", "chuangqianmingyueguang", "nihaoshijie", "jintiantianqibucuo", "weixindushu", "woxiangkanyibenxiaoshuo", "zhegewentiyoudiankunnan", "wxds", "zgr" };
        int rounds = a.length > 1 ? Integer.parseInt(a[1]) : 3;
        long worst = 0, tot = 0; int n = 0; String w = "";
        for (int r = 0; r < rounds; r++) for (String x : s) for (int i = 1; i <= x.length(); i++) {
            long t = System.nanoTime();
            dec.decode(x.substring(0, i), -1);
            for (int k = 0; k < 10 && dec.has(k); k++) dec.get(k);
            long us = (System.nanoTime() - t) / 1000;
            if (r == rounds - 1) { tot += us; n++; if (us > worst) { worst = us; w = x.substring(0, i); } }
        }
        System.out.println("mean " + tot / n + " us, worst " + worst + " us (" + w + ")");
    }
}
