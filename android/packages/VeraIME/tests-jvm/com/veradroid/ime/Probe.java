package com.veradroid.ime;

import java.io.RandomAccessFile;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.util.List;

/** Interactive probe: java ... Probe pinyin.dat nihao zhongguoren ...   (prints candidates and timing) */
public class Probe {
    public static void main(String[] a) throws Exception {
        RandomAccessFile f = new RandomAccessFile(a[0], "r");
        ByteBuffer b = f.getChannel().map(FileChannel.MapMode.READ_ONLY, 0, f.length());
        PinyinDict d = new PinyinDict(b);
        PinyinDecoder dec = new PinyinDecoder(d);
        dec.setUser(new UserDict(d));
        for (int i = 1; i < a.length; i++) {
            if (a[i].startsWith("+")) {         // +你好: what follows
                List<PinyinDecoder.Cand> l0 = dec.decode(a[i].substring(1), d.start);
                PinyinDecoder.Cand c0 = l0.get(0);
                StringBuilder s = new StringBuilder(c0.text + " ->");
                for (PinyinDecoder.Cand c : dec.predict(c0.lastId(), c0.text, 16)) s.append(' ').append(c.text);
                System.out.println(s);
                continue;
            }
            List<PinyinDecoder.Cand> l = null;
            long t = System.nanoTime();
            for (int k = 0; k < 200; k++) l = dec.decode(a[i], d.start);
            long us = (System.nanoTime() - t) / 200000;
            StringBuilder s = new StringBuilder(a[i] + " [" + dec.visited + " nodes, " + us + " us]");
            for (int k = 0; k < 14 && dec.has(k); k++) s.append(' ').append(dec.get(k).text).append(dec.get(k).end < a[i].length() ? "/" + dec.get(k).end : "");
            System.out.println(s);
        }
    }
}
