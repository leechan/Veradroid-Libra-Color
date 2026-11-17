package com.veradroid.ime;

import java.io.RandomAccessFile;
import java.io.StringReader;
import java.io.StringWriter;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.List;

/** Plain-JVM checks of the pinyin engine:  java -cp out com.veradroid.ime.DecoderTest assets/pinyin.dat */
public class DecoderTest {
    static int fails, checks;
    static PinyinDict d;
    static PinyinDecoder dec;
    static UserDict u;

    static void check(boolean ok, String what) {
        checks++;
        if (!ok) { fails++; System.out.println("FAIL " + what); }
    }

    static List<String> cands(String py, int ctx, int max) {
        dec.decode(py, ctx);
        List<String> l = new ArrayList<String>();
        for (int i = 0; i < max && dec.has(i); i++) l.add(dec.get(i).text);
        return l;
    }

    static String top(String py) { List<String> l = cands(py, -1, 1); return l.isEmpty() ? "" : l.get(0); }

    static int rank(String py, String want) { return cands(py, -1, 200).indexOf(want); }

    public static void main(String[] a) throws Exception {
        RandomAccessFile f = new RandomAccessFile(a[0], "r");
        ByteBuffer b = f.getChannel().map(FileChannel.MapMode.READ_ONLY, 0, f.length());
        d = new PinyinDict(b);
        dec = new PinyinDecoder(d);
        u = new UserDict(d);
        dec.setUser(u);

        // syllables
        check(d.syllable("zhuang") >= 0 && d.syllable("lve") >= 0 && d.syllable("nv") >= 0, "syllable table");
        check(d.syllable("zh") < 0 && d.syllable("v") < 0, "zh / v are no syllables");
        // whole sentences
        String[][] sent = {
            { "nihao", "你好" }, { "nihaoshijie", "你好世界" }, { "jintiantianqibucuo", "今天天气不错" },
            { "weixindushu", "微信读书" }, { "woxiangkanyibenxiaoshuo", "我想看一本小说" }, { "zhongguoren", "中国人" },
            { "womenquchifanba", "我们去吃饭吧" }, { "zhegewentiyoudiankunnan", "这个问题有点困难" },
            { "xi'an", "西安" }, { "lvse", "绿色" }, { "nvhai", "女孩" },
            { "jintiantianqihenhaowomenyiqiqugongyuansanbu", "今天天气很好我们一起去公园散步" },
        };
        for (String[] t : sent) check(top(t[0]).equals(t[1]), t[0] + " -> " + t[1] + " (got " + top(t[0]) + ")");
        // separators: xian is one syllable, xi'an two
        check(top("xian").length() == 1, "xian -> one character (got " + top("xian") + ")");
        check(top("ni'hao").equals("你好"), "ni'hao");
        // abbreviations and unfinished syllables
        check(rank("zgr", "中国人") == 0, "zgr -> 中国人 first (" + rank("zgr", "中国人") + ")");
        check(rank("bj", "北京") >= 0 && rank("bj", "北京") < 5, "bj -> 北京 in the first 5");
        check(rank("nh", "你好") >= 0 && rank("nh", "你好") < 16, "nh -> 你好 on the first pages (" + rank("nh", "你好") + ")");
        check(rank("zhongg", "中国") == 0, "zhongg -> 中国 first");
        check(rank("sj", "时间") >= 0 && rank("sj", "时间") < 5, "sj -> 时间");
        // partial candidates say how much they use
        dec.decode("nihaoshijie", -1);
        boolean partial = false;
        for (int i = 0; dec.has(i) && i < 30; i++) if (dec.get(i).text.equals("你好")) partial = dec.get(i).end == 5;
        check(partial, "你好 uses 5 of nihaoshijie");
        dec.decode("xi'an", -1);
        check(dec.get(0).end == 5, "西安 uses all of xi'an incl. the separator");
        // after a partial choice, the rest decodes with the chosen word as context
        dec.decode("nihao", -1);
        int nihao = dec.get(0).lastId();
        check(cands("shijie", nihao, 1).get(0).equals("世界"), "shijie after 你好 -> 世界");
        // single characters are always there, and nothing returns for junk
        check(cands("a", -1, 40).contains("啊"), "a -> 啊");
        check(cands("'''", -1, 5).isEmpty(), "separators only -> nothing");
        cands("vvvv", -1, 5);
        // suggestions
        List<PinyinDecoder.Cand> p = dec.predict(nihao, "你好", 20);
        List<String> pt = new ArrayList<String>();
        for (PinyinDecoder.Cand c : p) pt.add(c.text);
        check(pt.contains("吗") && pt.size() >= 10, "联想 after 你好: " + pt);
        dec.decode("weixin", -1);
        p = dec.predict(dec.get(0).lastId(), "微信", 20);
        pt.clear();
        for (PinyinDecoder.Cand c : p) pt.add(c.text);
        check(pt.contains("公众号"), "联想 after 微信: " + pt);

        // learning: a word further down becomes first after it is chosen a few times
        String low = cands("shiji", -1, 8).get(3);
        int[] syl = { d.syllable("shi"), d.syllable("ji") };
        for (int i = 0; i < 3; i++) u.learn(syl, low);
        check(top("shiji").equals(low), "learned " + low + " is first for shiji (got " + top("shiji") + ")");
        // a phrase the dictionary does not have, chosen piece by piece, comes back whole
        check(!top("vediluoshu").equals("维迪罗书"), "precondition");
        int[] s2 = { d.syllable("wei"), d.syllable("di"), d.syllable("luo"), d.syllable("shu") };
        u.learn(s2, "维迪罗书");
        check(top("weidiluoshu").equals("维迪罗书"), "own phrase 维迪罗书 (got " + top("weidiluoshu") + ")");
        u.learnPair("维迪罗书", "真好");
        dec.decode("weidiluoshu", -1);
        PinyinDecoder.Cand own = dec.get(0);
        check(own.lastId() == -1 && dec.syllables(own).length == 4, "own phrase keeps its syllables");
        p = dec.predict(-1, "维迪罗书", 10);
        check(!p.isEmpty() && p.get(0).text.equals("真好"), "user 联想 pair");
        // save / load round trip
        StringWriter w = new StringWriter();
        u.save(w);
        UserDict u2 = new UserDict(d);
        u2.load(new StringReader(w.toString()));
        check(u2.phraseCount() == u.phraseCount() && u2.pairCount() == u.pairCount(), "userdict round trip");
        dec.setUser(u2);
        check(top("weidiluoshu").equals("维迪罗书"), "own phrase after reload");
        // bounded
        UserDict u3 = new UserDict(d);
        int[] one = { d.syllable("a") };
        for (int i = 0; i < UserDict.MAX_PHRASES + 500; i++) u3.learn(new int[] { d.syllable("a"), d.syllable("a") }, "阿" + (char) (0x4e00 + i));
        for (int i = 0; i < UserDict.MAX_PAIRS + 500; i++) u3.learnPair("甲" + i, "乙");
        check(u3.phraseCount() <= UserDict.MAX_PHRASES && u3.pairCount() <= UserDict.MAX_PAIRS, "userdict bounded "
            + u3.phraseCount() + "/" + u3.pairCount());
        u3.clear();
        check(u3.phraseCount() == 0 && u3.pairCount() == 0, "clear");
        dec.setUser(u);

        // key grid: every panel width, the letter rows (10 keys; 9 keys; shift 1.5 + 7 + 1.5) and the bottom row
        float[][] rows = { { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, { 1, 1, 1, 1, 1, 1, 1, 1, 1 }, { 1.5f, 1, 1, 1, 1, 1, 1, 1, 1.5f },
            { 1.4f, 1, 2.6f, 1, 1.2f, 1.2f, 1.6f } };
        int density16 = 30;                                  // 1.875 * 16
        for (int width : new int[] { 758, 1072, 1236, 1264, 1272, 1448, 1680, 1860, 1920 }) {
            int inner = width - 2 * ((6 * density16 + 8) / 16);
            for (float[] wts : rows) {
                int[] e = KeyGrid.edges(inner, wts);
                boolean ok = e[0] == 0 && e[wts.length] == inner;
                int lo = Integer.MAX_VALUE, hi = 0;
                for (int i = 0; i < wts.length; i++) {
                    ok &= e[i + 1] > e[i];
                    if (wts[i] == 1f) { lo = Math.min(lo, e[i + 1] - e[i]); hi = Math.max(hi, e[i + 1] - e[i]); }
                }
                check(ok && hi - lo <= 1, "key grid " + width + " px, " + wts.length + " keys: widths " + lo + ".." + hi);
            }
            // the letter row and the shift row share the edges of z..m with q..p shifted by 1.5 keys only where the arithmetic says so;
            // the same weights always give the same edges
            check(java.util.Arrays.equals(KeyGrid.edges(inner, rows[0]), KeyGrid.edges(inner, rows[0])), "deterministic " + width);
        }

        // time: every prefix of the test sentences, as typed
        long worst = 0, total = 0; int runs = 0;
        for (int rep = 0; rep < 3; rep++) for (String[] t : sent) for (int i = 1; i <= t[0].length(); i++) {
            long t0 = System.nanoTime();
            dec.decode(t[0].substring(0, i), -1);
            for (int k = 0; k < 12 && dec.has(k); k++) dec.get(k);
            long us = (System.nanoTime() - t0) / 1000;
            if (rep == 2) { worst = Math.max(worst, us); total += us; runs++; }
        }
        System.out.println("decode per key (JVM, warm): mean " + total / runs + " us, worst " + worst + " us over " + runs);
        System.out.println(fails == 0 ? "OK " + checks + " checks" : fails + " of " + checks + " checks FAILED");
        System.exit(fails == 0 ? 0 : 1);
    }
}
