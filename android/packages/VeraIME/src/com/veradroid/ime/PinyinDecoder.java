// SPDX-License-Identifier: GPL-3.0-or-later
package com.veradroid.ime;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;

/**
 * Pinyin letters -> candidates.  Plain Java (JVM tests: tests-jvm/).
 *
 * The letters are cut into syllables in every possible way (xian = xian | xi an); a letter with no syllable starting
 * at it stands for any syllable with that initial (nh = ni hao), and the last, unfinished syllable for every syllable
 * it begins (zhongg = zhong guo).  Walking the dictionary trie along those syllables gives the words that can start
 * at each letter; a beam search (word bigrams, backing off to word frequency) picks the best chain of words.
 *
 * Candidates, in order: phrases the user taught us that cover everything typed, the best sentence(s), then the words
 * that can start the input, longest first, down to single characters.  Each says how many typed characters it uses:
 * after a partial choice the rest stays for the next choice.
 */
final class PinyinDecoder {
    static final int MAX_LETTERS = 48;
    private static final int BEAM = 6, TOP = 2;
    /** cost of a syllable given only by its initial / by its first letters */
    private static final int ABBR = 28, PREFIX = 22;
    /** per word of a chain: of two readings about as likely, the one with fewer, longer words */
    static int WORD = 8;
    private static final int BUDGET = 30000;
    private static final int INF = Integer.MAX_VALUE / 2;

    static final class Cand {
        String text;
        /** characters of the typed string this candidate uses */
        int end;
        /** dictionary word ids, in order (-1: a phrase of the user's own) and the trie node of each */
        int[] ids, nodes;
        /** syllable ids as chars, for a phrase of the user's own */
        String key;
        int cost;
        boolean partial;        // abbreviated or completed syllables

        int lastId() { return ids == null || ids.length == 0 ? -1 : ids[ids.length - 1]; }
    }

    private final PinyinDict d;
    private UserDict u;

    // one decode
    private final char[] ch = new char[MAX_LETTERS];
    private final boolean[] brk = new boolean[MAX_LETTERS + 1];
    private final int[] rawEnd = new int[MAX_LETTERS + 1];
    private int n, budget;
    private final int[] bCount = new int[MAX_LETTERS + 1];
    private final int[] bCost = new int[(MAX_LETTERS + 1) * BEAM], bWord = new int[(MAX_LETTERS + 1) * BEAM],
        bNode = new int[(MAX_LETTERS + 1) * BEAM], bPrev = new int[(MAX_LETTERS + 1) * BEAM];
    private final int[] hRow = new int[BEAM], hBow = new int[BEAM];
    /** per decode: syllable id of the letters [pos, pos+len) (-1 none), and the id range of syllables they begin */
    private final int[] sylAt = new int[MAX_LETTERS * 7], sylLo = new int[MAX_LETTERS * 7], sylHi = new int[MAX_LETTERS * 7];
    /** word id -> bigram row of its context word, kept across decodes (direct mapped) */
    private final int[] rowKey = new int[2048], rowVal = new int[2048], bowVal = new int[2048];
    private final boolean[] tailVal = new boolean[2048];
    { java.util.Arrays.fill(rowKey, Integer.MIN_VALUE); }
    /** entry k's context is the last model word of a longer word (你好 -> 好): its bigrams are only a guess */
    private final boolean[] hTail = new boolean[BEAM];
    /** LOG1P[x] = 10 * ln(1 + e^(-x/10)): cost of a 50/50 mix of two probabilities whose costs differ by x */
    private static final int[] LOG1P = new int[80];
    static {
        for (int x = 0; x < LOG1P.length; x++) LOG1P[x] = (int) Math.round(10 * Math.log(1 + Math.exp(-x / 10.0)));
    }

    /** cost of 0.5 * p(a) + 0.5 * p(b) */
    static int mix(int a, int b) {
        int lo = Math.min(a, b), d = Math.abs(a - b);
        return lo + 7 - (d < LOG1P.length ? LOG1P[d] : 0);
    }
    private final ArrayList<UserDict.Entry> uWords = new ArrayList<UserDict.Entry>();
    private final StringBuilder uKey = new StringBuilder();
    // word edges that start at the first letter: node, end letter, depth, penalty
    private int[] first = new int[4 * 256];
    private int firstN;
    private final ArrayList<Cand> firstUser = new ArrayList<Cand>();
    private int ctx;
    /** trie nodes visited by the last decode (tests, tuning) */
    int visited;

    PinyinDecoder(PinyinDict dict) { d = dict; }

    void setUser(UserDict user) { u = user; }

    static boolean isLetter(char c) { return c >= 'a' && c <= 'z'; }

    /**
     * @param raw  letters a-z and ' (syllable separator)
     * @param context  id of the word before the cursor, {@link PinyinDict#start} at the start of a sentence, -1 unknown
     */
    List<Cand> decode(String raw, int context) {
        ArrayList<Cand> out = new ArrayList<Cand>();
        n = 0;
        boolean pending = false;
        for (int i = 0; i < raw.length() && n < MAX_LETTERS; i++) {
            char c = raw.charAt(i);
            if (isLetter(c)) {
                brk[n] = pending && n > 0;
                pending = false;
                ch[n++] = c;
                rawEnd[n] = i + 1;
            } else if (c == '\'') {
                pending = true;
                if (n > 0) rawEnd[n] = i + 1;
            }
        }
        list = out; pN = pNext = 0;
        if (n == 0) return out;
        ctx = context;
        budget = BUDGET;
        firstN = 0;
        firstUser.clear();
        uWords.clear();
        for (int i = 0; i <= n; i++) bCount[i] = 0;
        bCount[0] = 1; bCost[0] = 0; bWord[0] = context; bNode[0] = 0; bPrev[0] = -1;

        for (int p = 0; p < n; p++) for (int len = 1; len <= 6; len++) {
            int i = p * 7 + len;
            if (p + len > n) { sylAt[i] = -1; sylLo[i] = sylHi[i] = 0; continue; }
            sylAt[i] = d.syllable(ch, p, len);
            sylLo[i] = sylHi[i] = 0;
            if (len <= 5) { sylLo[i] = d.syllableLower(ch, p, len); sylHi[i] = d.syllableUpper(ch, p, len); }
        }
        boolean userPhrases = u != null && u.hasOwn();
        for (int p = 0; p < n; p++) {
            int h = bCount[p];
            if (h == 0) continue;
            minK = 0;
            for (int k = 0; k < h; k++) {
                contextOf(bWord[p * BEAM + k], k);
                if (bCost[p * BEAM + k] + hBow[k] < bCost[p * BEAM + minK] + hBow[minK]) minK = k;
            }
            walk(p, 0, p, 0, 0);
            if (userPhrases) { uKey.setLength(0); walkUser(p, p); }
        }
        visited = BUDGET - budget;

        int e = n;
        while (e > 0 && bCount[e] == 0) e--;
        seen.clear();
        // 1. the user's own phrases for everything typed
        Collections.sort(firstUser, BY_COST);
        for (Cand c : firstUser) if (c.end == rawEnd[n] && seen.add(c.text)) out.add(c);
        // 2. the best chains of words
        if (e > 0) {
            Integer[] order = new Integer[bCount[e]];
            for (int k = 0; k < order.length; k++) order[k] = k;
            final int base = e * BEAM;
            java.util.Arrays.sort(order, new Comparator<Integer>() {
                @Override public int compare(Integer a, Integer b) { return bCost[base + a] - bCost[base + b]; }
            });
            int best = bCost[base + order[0]];
            for (int i = 0; i < order.length && i < 3; i++) {
                if (bCost[base + order[i]] > best + 40) break;
                Cand c = chain(e, order[i]);
                if (seen.add(c.text)) out.add(c);
            }
        }
        for (Cand c : firstUser) if (c.end != rawEnd[n] && seen.add(c.text)) out.add(c);
        // 3. words that can start the input: longest first, whole syllables before guessed ones, then cheapest.
        //    Only their sort keys now; the texts are made when the bar gets to them (has / get).
        int cc = context >= 0 ? d.context(context) : -1;
        cRow = cc >= 0 ? d.row(cc) : -1;
        cTail = cc != context;
        cBow = context >= 0 ? d.backoff(context) : 0;
        pN = 0; pNext = 0; partialEnd = -1; partials = 0;
        for (int i = 0; i < firstN; i++) {
            int node = first[4 * i], end = first[4 * i + 1], depth = first[4 * i + 2], pen = first[4 * i + 3];
            int w0 = d.wordStart(node), w1 = d.wordStart(node + 1);
            int lim = pen > 0 ? Math.min(w1, w0 + 4) : depth > 1 ? Math.min(w1, w0 + 60) : w1;
            for (int w = w0; w < lim; w++) pend(i, w, end, depth, pen);
            if (u != null) for (int j = u.boostLower(lim); j < u.boostId.length && u.boostId[j] < w1; j++) pend(i, u.boostId[j], end, depth, pen);
        }
        java.util.Arrays.sort(pKey, 0, pN);
        list = out;
        return out;
    }

    // words still to be turned into candidates: key = letters left | guessed | cost | index, and the word of each
    private long[] pKey = new long[512];
    private int[] pWord = new int[512], pEdge = new int[512];
    private int pN, pNext, partialEnd, partials, cRow, cBow;
    private boolean cTail;
    private final HashSet<String> seen = new HashSet<String>();
    private ArrayList<Cand> list = new ArrayList<Cand>();

    private void pend(int edge, int w, int end, int depth, int pen) {
        if (pN == pKey.length) {
            pKey = java.util.Arrays.copyOf(pKey, pN * 2); pWord = java.util.Arrays.copyOf(pWord, pN * 2); pEdge = java.util.Arrays.copyOf(pEdge, pN * 2);
        }
        int f = d.follow(cRow, w);
        int cu = d.cost(w, depth), t = f >= 0 ? f : cBow + cu;
        int cost = (cTail ? mix(t, cu) : t) + pen - (u != null ? u.bonusOf(w) : 0);
        pKey[pN] = ((long) (n - end) << 44) | ((pen > 0 ? 1L : 0L) << 43) | ((long) (cost + 4096) << 24) | pN;
        pWord[pN] = w; pEdge[pN] = edge;
        pN++;
    }

    /** true when the last decode has a candidate i (makes it if needed) */
    boolean has(int i) {
        while (list.size() <= i && pNext < pN) {
            long key = pKey[pNext++];
            int idx = (int) (key & 0xffffff), edge = pEdge[idx], pen = first[4 * edge + 3], end = first[4 * edge + 1];
            if (pen > 0) {                          // a few of the guesses for each length, not hundreds
                if (end != partialEnd) { partialEnd = end; partials = 0; }
                if (++partials > 24) continue;
            }
            Cand c = new Cand();
            c.text = d.text(pWord[idx]);
            if (!seen.add(c.text)) continue;
            c.end = rawEnd[end];
            c.ids = new int[] { pWord[idx] };
            c.nodes = new int[] { first[4 * edge] };
            c.cost = (int) ((key >>> 24) & 0x7ffff) - 4096;
            c.partial = pen > 0;
            list.add(c);
        }
        return i < list.size();
    }

    Cand get(int i) { return has(i) ? list.get(i) : null; }

    private static final Comparator<Cand> BY_COST = new Comparator<Cand>() {
        @Override public int compare(Cand a, Cand b) { return a.cost - b.cost; }
    };
    /** the words of beam entry k at letter e, as one candidate */
    private Cand chain(int e, int k) {
        int count = 0;
        for (int p = e, i = k; p > 0; ) { int prev = bPrev[p * BEAM + i]; count++; p = prev / BEAM; i = prev % BEAM; }
        Cand c = new Cand();
        c.ids = new int[count];
        c.nodes = new int[count];
        c.end = rawEnd[e];
        c.cost = bCost[e * BEAM + k];
        String[] parts = new String[count], keys = new String[count];
        for (int p = e, i = k, j = count - 1; p > 0; j--) {
            int at = p * BEAM + i, w = bWord[at];
            if (w >= 0) { c.ids[j] = w; c.nodes[j] = bNode[at]; parts[j] = d.text(w); }
            else {
                UserDict.Entry ue = uWords.get(-2 - w);
                c.ids[j] = -1; c.nodes[j] = -1; parts[j] = ue.text; keys[j] = ue.key;
            }
            int prev = bPrev[at];
            p = prev / BEAM; i = prev % BEAM;
        }
        StringBuilder t = new StringBuilder(), key = new StringBuilder();
        for (int j = 0; j < count; j++) {
            t.append(parts[j]);
            if (keys[j] != null) key.append(keys[j]);
            else for (int s : d.path(c.nodes[j])) key.append((char) s);
        }
        c.text = t.toString();
        if (count > 1 || keys[0] != null) c.key = key.toString();
        return c;
    }

    /** syllable ids of a candidate (for learning), or null */
    int[] syllables(Cand c) {
        String k = c.key;
        if (k == null) {
            if (c.ids == null || c.ids.length != 1 || c.ids[0] < 0) return null;
            return d.path(c.nodes[0]);
        }
        int[] s = new int[k.length()];
        for (int i = 0; i < s.length; i++) s[i] = k.charAt(i);
        return s;
    }

    // ---------------------------------------------------------------- search

    /** bigram row / backoff / "is a guess" of word w as context, into hRow[k] hBow[k] hTail[k] */
    private void contextOf(int w, int k) {
        if (w < 0) { hRow[k] = -1; hBow[k] = 0; hTail[k] = false; return; }
        int slot = (w * 0x9E3779B1 >>> 21) & (rowKey.length - 1);
        if (rowKey[slot] != w) {
            int cw = d.context(w);
            rowKey[slot] = w;
            rowVal[slot] = cw >= 0 ? d.row(cw) : -1;
            bowVal[slot] = d.backoff(w);
            tailVal[slot] = cw != w;
        }
        hRow[k] = rowVal[slot]; hBow[k] = bowVal[slot]; hTail[k] = tailVal[slot];
    }

    private boolean clear(int from, int to) {       // no separator inside [from, to)
        for (int i = from + 1; i < to; i++) if (brk[i]) return false;
        return true;
    }

    /** Follow the trie from `node` (depth syllables, reached at letter pos); the word starts at letter `start`. */
    private void walk(int start, int node, int pos, int depth, int pen) {
        if (depth > 0 && d.wordStart(node + 1) > d.wordStart(node)) {
            relax(start, pos, node, depth, pen);
            if (start == 0) {
                if (4 * firstN + 4 > first.length) first = java.util.Arrays.copyOf(first, first.length * 2);
                first[4 * firstN] = node; first[4 * firstN + 1] = pos; first[4 * firstN + 2] = depth; first[4 * firstN + 3] = pen;
                firstN++;
            }
        }
        if (pos == n || depth == d.maxLen || d.childStart(node + 1) == d.childStart(node)) return;
        if (--budget < 0) return;
        int left = n - pos, exactLeft = -1;
        boolean any = false;
        for (int len = 1; len <= left && len <= 6; len++) {
            if (len > 1 && brk[pos + len - 1]) break;
            int s = sylAt[pos * 7 + len];
            if (s < 0) continue;
            any = true;
            if (len == left) exactLeft = s;
            int c = d.child(node, s);
            if (c >= 0) walk(start, c, pos + len, depth + 1, pen);
        }
        // the unfinished last syllable: everything that begins with the letters left
        if (left <= 5 && clear(pos, n)) range(start, node, pos, left, n, depth, pen + (left == 1 ? ABBR : PREFIX), exactLeft);
        // a letter (or zh ch sh) that starts no syllable here: an initial -- unless the letters left are the start of
        // a syllable (zho: the user is still typing zhong / zhou, the line above covers it)
        boolean midSyllable = left <= 5 && sylLo[pos * 7 + left] < sylHi[pos * 7 + left] && clear(pos, n);
        if (!any && left > 1 && !midSyllable) {
            range(start, node, pos, 1, pos + 1, depth, pen + ABBR, -1);
            if (left > 2 && ch[pos + 1] == 'h' && !brk[pos + 1] && (ch[pos] == 'z' || ch[pos] == 'c' || ch[pos] == 's'))
                range(start, node, pos, 2, pos + 2, depth, pen + ABBR, -1);
        }
    }

    /** children of node whose syllable starts with ch[pos, pos+len): each continues at letter `next` */
    private void range(int start, int node, int pos, int len, int next, int depth, int pen, int skip) {
        int lo = sylLo[pos * 7 + len], hi = sylHi[pos * 7 + len];
        if (lo >= hi) return;
        int end = d.childStart(node + 1);
        for (int c = d.childLower(node, lo); c < end; c++) {
            int s = d.nodeSyl(c);
            if (s >= hi) break;
            if (s == skip) continue;
            walk(start, c, next, depth + 1, pen);
            if (budget < 0) return;
        }
    }

    /** Words of `node` span the letters [start, end): extend the beam entries at start with the ones worth it. */
    private void relax(int start, int end, int node, int depth, int pen) {
        int w0 = d.wordStart(node), w1 = d.wordStart(node + 1), h = bCount[start], base = start * BEAM;
        // the most frequent words of the node, after any entry
        for (int w = w0; w < w1 && w < w0 + TOP; w++) best(start, end, node, w, d.cost(w, depth), pen);
        // words an entry's last word is known to be followed by (on the guessed paths of abbreviations, which are
        // many, only after the best entry)
        for (int k = pen == 0 ? 0 : minK, kEnd = pen == 0 ? h : minK + 1; k < kEnd; k++) {
            int row = hRow[k];
            if (row < 0) continue;
            int re = d.rowEnd(row);
            for (int i = d.entryLower(d.rowStart(row), re, w0); i < re; i++) {
                int v = d.entry(i), w = v >>> 8;
                if (w >= w1) break;
                int f = v & 0xff;
                if (hTail[k]) f = mix(f, d.cost(w, depth));
                add(end, bCost[base + k] + f + pen - (u != null ? u.bonusOf(w) : 0), w, node, base + k);
            }
        }
        // words the user chose before
        if (u != null && u.boostId.length > 0)
            for (int j = u.boostLower(w0 + Math.min(TOP, w1 - w0)); j < u.boostId.length && u.boostId[j] < w1; j++)
                best(start, end, node, u.boostId[j], d.cost(u.boostId[j], depth), pen);
    }

    /** entry at the current start position with the cheapest cost + backoff */
    private int minK;

    /** word w (unigram cost cu) after the entry at `start` that makes it cheapest */
    private void best(int start, int end, int node, int w, int cu, int pen) {
        int h = bCount[start], base = start * BEAM, bc = INF, bk = 0;
        if (pen > 0) {                      // a guessed path: no bigram lookups
            int c = bCost[base + minK] + (hTail[minK] ? mix(hBow[minK] + cu, cu) : hBow[minK] + cu);
            add(end, c + pen - (u != null ? u.bonusOf(w) : 0), w, node, base + minK);
            return;
        }
        for (int k = 0; k < h; k++) {
            int f = d.follow(hRow[k], w);
            int t = f >= 0 ? f : hBow[k] + cu;
            int c = bCost[base + k] + (hTail[k] ? mix(t, cu) : t);
            if (c < bc) { bc = c; bk = k; }
        }
        add(end, bc + pen - (u != null ? u.bonusOf(w) : 0), w, node, base + bk);
    }

    private void add(int end, int cost, int word, int node, int prev) {
        cost += WORD;
        int base = end * BEAM, cnt = bCount[end], worst = -1, wc = -1;
        for (int k = 0; k < cnt; k++) {
            if (bWord[base + k] == word) {
                if (cost < bCost[base + k]) { bCost[base + k] = cost; bNode[base + k] = node; bPrev[base + k] = prev; }
                return;
            }
            if (bCost[base + k] > wc) { wc = bCost[base + k]; worst = k; }
        }
        int at;
        if (cnt < BEAM) { at = base + cnt; bCount[end] = cnt + 1; }
        else if (cost < wc) at = base + worst;
        else return;
        bCost[at] = cost; bWord[at] = word; bNode[at] = node; bPrev[at] = prev;
    }

    /** the user's own phrases that start at letter `start` (whole syllables only) */
    private void walkUser(int start, int pos) {
        for (int len = 1; len <= n - pos && len <= 6; len++) {
            if (len > 1 && brk[pos + len - 1]) break;
            int s = sylAt[pos * 7 + len];
            if (s < 0) continue;
            uKey.append((char) s);
            List<UserDict.Entry> l = u.own(uKey);
            if (l != null) for (UserDict.Entry e : l) {
                int id = -2 - uWords.size(), h = bCount[start], base = start * BEAM, bc = INF, bk = 0;
                uWords.add(e);
                for (int k = 0; k < h; k++) {
                    int c = bCost[base + k] + hBow[k] + e.cost();
                    if (c < bc) { bc = c; bk = k; }
                }
                add(pos + len, bc, id, -1, base + bk);
                if (start == 0) {
                    Cand c = new Cand();
                    c.text = e.text; c.end = rawEnd[pos + len]; c.ids = new int[] { -1 }; c.nodes = new int[] { -1 };
                    c.key = e.key; c.cost = e.cost() - 40;      // ahead of dictionary words of the same length
                    firstUser.add(c);
                }
            }
            if (u.isPrefix(uKey) && uKey.length() < UserDict.MAX_CHARS) walkUser(start, pos + len);
            uKey.setLength(uKey.length() - 1);
        }
    }

    // ---------------------------------------------------------------- suggestions after a commit

    /** Words that often follow: what the user typed after this text before, then the dictionary's bigrams. */
    List<Cand> predict(int lastId, String lastText, int max) {
        ArrayList<Cand> out = new ArrayList<Cand>();
        HashSet<String> seen = new HashSet<String>();
        if (u != null) {
            List<UserDict.Entry> l = u.after(lastText);
            if (l != null) for (UserDict.Entry e : l) {
                if (out.size() >= max / 2) break;
                Cand c = new Cand();
                c.text = e.text;
                if (seen.add(c.text)) out.add(c);
            }
        }
        int row = lastId >= 0 ? d.row(d.context(lastId)) : -1;
        if (row >= 0) {
            int rs = d.rowStart(row), re = d.rowEnd(row), cnt = re - rs;
            long[] v = new long[cnt];                   // cost << 32 | id: sorts by cost
            for (int i = 0; i < cnt; i++) { int x = d.entry(rs + i); v[i] = ((long) (x & 0xff) << 32) | (x >>> 8); }
            java.util.Arrays.sort(v);
            for (int i = 0; i < cnt && out.size() < max; i++) {
                int w = (int) v[i];
                Cand c = new Cand();
                c.text = d.text(w);
                c.ids = new int[] { w };
                c.nodes = new int[] { -1 };
                c.cost = (int) (v[i] >>> 32);
                if (seen.add(c.text)) out.add(c);
            }
        }
        return out;
    }
}
