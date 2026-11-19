package com.veradroid.home;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;

/**
 * 内置阅读器的注释弹框（Epub.note）：跑 tests/reader/gen_note_epubs.py 生成的书，对 expect.tsv。
 * 找目标章节的方法和 ReaderActivity.follow 一样：书脊里有就用读进来的那一章，没有就单独读那个文件。
 * java com.veradroid.home.EpubNoteTest <epub 目录>
 */
public class EpubNoteTest {
    static int fails = 0, checks = 0;
    static void check(boolean ok, String what) { checks++; if (!ok) { fails++; System.out.println("FAIL " + what); } }

    static String base(String entry) {
        String n = entry.substring(entry.lastIndexOf('/') + 1);
        int dot = n.lastIndexOf('.');
        return dot > 0 ? n.substring(0, dot) : n;
    }

    public static void main(String[] a) throws Exception {
        File dir = new File(a[0]);
        BufferedReader r = new BufferedReader(new InputStreamReader(new FileInputStream(new File(dir, "expect.tsv")), "UTF-8"));
        String line;
        while ((line = r.readLine()) != null) {
            if (line.length() == 0) continue;
            String[] e = line.split("\t");
            File f = new File(dir, e[0] + ".epub");
            Epub.Book b = Epub.load(f);
            String file = e[1].substring(0, e[1].lastIndexOf(':'));
            int idx = Integer.parseInt(e[1].substring(e[1].lastIndexOf(':') + 1));
            Epub.Chapter from = null;
            for (Epub.Chapter c : b.chapters) if (base(c.entry).equals(file)) { from = c; break; }
            String what = e[0] + " " + e[1];
            if (from == null) { check(false, what + ": no chapter " + file); continue; }
            if (e.length > 3 && e[3].startsWith("links=")) {
                int want = Integer.parseInt(e[3].substring(6));
                check(from.links.size() == want, what + ": " + from.links.size() + " links, want " + want);
            }
            if (idx >= from.links.size()) { check(false, what + ": only " + from.links.size() + " links"); continue; }
            Epub.Link k = from.links.get(idx);
            String label = from.text.substring(k.start, k.end).trim();
            int hash = k.target.indexOf('#');
            String entry = hash >= 0 ? k.target.substring(0, hash) : k.target, frag = hash >= 0 ? k.target.substring(hash + 1) : "";
            Epub.Chapter target = null;
            for (Epub.Chapter c : b.chapters) if (entry.equals(c.entry)) { target = c; break; }
            if (target == null) target = Epub.loadChapter(f, entry);
            Epub.Note n = Epub.note(k, label, target, frag);
            String got = n == null ? "JUMP" : n.toString();
            String want = e[2].replace("\\n", "\n");
            check(got.equals(want), what + " [" + label + " -> " + k.target + "]: got '" + shorten(got) + "', want '" + shorten(want) + "'");
            System.out.println(what + " [" + label + "] -> " + shorten(got).replace("\n", "\\n"));
        }
        r.close();

        // 注释号的样子
        String[] marks = { "[1]", "(2)", "〔3〕", "注1", "[注]", "注", "①", "¹²", "*", "†", "a", "［12］", "（十）" };
        for (String m : marks) check(Epub.noteMark(m), "noteMark " + m);
        String[] not = { "第二章", "见下文", "参考文献", "[1234]", "" };
        for (String m : not) check(!Epub.noteMark(m), "not noteMark " + m);

        System.out.println(fails == 0 ? "EpubNoteTest: ok (" + checks + " checks)" : "EpubNoteTest: " + fails + " failures");
        System.exit(fails == 0 ? 0 : 1);
    }

    static String shorten(String s) { return s.length() > 60 ? s.substring(0, 30) + "…(" + s.length() + ")…" + s.substring(s.length() - 20) : s; }
}
