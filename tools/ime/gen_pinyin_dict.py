#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build VeraIME's phrase dictionary  android/packages/VeraIME/assets/pinyin.dat  (offline, on a PC).

Input (LGPL-2.1-or-later, the data libime / fcitx5 ships; see assets/NOTICE-pinyin.txt):
    dict_sc.txt   word <TAB> pin'yin <TAB> log10 weight of this reading
    lm_sc.arpa    ARPA n-gram model over the same words (only the 1-grams and 2-grams are used)

    python3 tools/ime/gen_pinyin_dict.py [--cache DIR] [--words N] [--bigrams N] [--out FILE]

Without the files in --cache (default ~/.cache/veradroid-ime) they are downloaded and their SHA-256 checked.

Output, little endian, read in place through a ByteBuffer (PinyinDict.java):
    header   16 x u32: magic 'VPY1', version, nSyl, nNodes, nWords, maxLen, nBiA, nBi,
                       offSyl, offNodeSyl, offNodeChild, offNodeWord, offLen, offWords, offBiA, offBi
    syl      nSyl x 8 bytes, ASCII, zero padded, sorted                      (syllable id = index)
    nodeSyl  nNodes x u16        trie over syllable ids in breadth-first order, node 0 = root
    nodeChild (nNodes+1) x u32   children of node i = [nodeChild[i], nodeChild[i+1]), sorted by syllable
    nodeWord (nNodes+1) x u32    words of node i = ids [nodeWord[i], nodeWord[i+1]), cheapest first
    len      (maxLen+2) x (u32 firstId, u32 byteOffset)   words of L characters: fixed records of 2L+3 bytes
    words    L x u16 characters, u8 cost, u8 backoff, u8 tail     cost = -ln(p) * 10, capped at 255
    biA      nBiA x u32 sorted word ids that have followers; then (nBiA+1) x u32 start index into bi
    bi       nBi x u32 = follower id << 8 | cost of the follower given the word, sorted by follower id
The word id nWords stands for "start of sentence" (context only; this model has no followers for it).

The model's own vocabulary cuts many dictionary words in two (你好 = 你 + 好).  Such a word gets the probability of
its best chain of model words, and "tail" = the number of characters of the last word of that chain: what follows
the word is looked up under that last word (tail 0 = the word itself).
"""
import argparse
import collections
import hashlib
import math
import os
import struct
import subprocess
import sys
import urllib.request

SOURCES = [
    ("dict-20260907.tar.zst", "fb75a179065e690dfc4559ce1807cbaf4fbe4f0111a5005615be9f435e6b9d76", "dict_sc.txt"),
    ("lm_sc.arpa-20260629.tar.zst", "06808333b9173e5374cf2cb5afc12d08f5625bf9abb536489cac376fc05f2e7f", "lm_sc.arpa"),
]
BASE = "https://download.fcitx-im.org/data/"
SCALE = 10.0            # cost units per nat
LN10 = math.log(10.0)
MAXLEN = 8
FLOOR = -6.7            # log10 p of a word the model does not know


def fetch(cache):
    os.makedirs(cache, exist_ok=True)
    for tar, sha, member in SOURCES:
        if os.path.exists(os.path.join(cache, member)):
            continue
        path = os.path.join(cache, tar)
        if not os.path.exists(path):
            print("GET", BASE + tar)
            urllib.request.urlretrieve(BASE + tar, path)
        h = hashlib.sha256(open(path, "rb").read()).hexdigest()
        if h != sha:
            sys.exit("%s: sha256 %s, expected %s" % (tar, h, sha))
        subprocess.check_call("zstd -dc '%s' | tar xf - -C '%s'" % (path, cache), shell=True)


def cost(log10p):
    return max(1, min(255, int(round(-log10p * LN10 * SCALE))))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cache", default=os.path.expanduser("~/.cache/veradroid-ime"))
    ap.add_argument("--words", type=int, default=120000, help="multi-character words kept (most frequent first)")
    ap.add_argument("--bigrams", type=int, default=450000)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "../../android/packages/VeraIME/assets/pinyin.dat"))
    a = ap.parse_args()
    fetch(a.cache)

    # ---- model: unigrams, then the bigrams worth keeping
    uni, bow = {}, {}
    big = {}
    sec = 0
    with open(os.path.join(a.cache, "lm_sc.arpa"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("\\"):
                sec = {"\\1-grams:": 1, "\\2-grams:": 2}.get(line.strip(), 0 if sec < 2 else 3)
                if sec == 3:
                    break
                continue
            p = line.rstrip("\n").split("\t")
            if len(p) < 2:
                continue
            if sec == 1:
                uni[p[1]] = float(p[0])
                bow[p[1]] = float(p[2]) if len(p) > 2 else 0.0
            elif sec == 2:
                x, y = p[1].split(" ")
                if x in uni and y in uni:
                    big[(x, y)] = float(p[0])
    print("model: %d words, %d bigrams" % (len(uni), len(big)))

    # ---- lexicon: every reading of every word; keep all single characters and the most frequent words
    def ok_char(c):
        return 0x4E00 <= ord(c) <= 0x9FA5 or c == "〇"

    entries = collections.defaultdict(list)          # word -> [(syllables, weight)]
    for line in open(os.path.join(a.cache, "dict_sc.txt"), encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) < 2:
            p = line.split()
        if len(p) < 2:
            continue
        w, py = p[0], p[1]
        wt = float(p[2]) if len(p) > 2 else 0.0
        syl = py.split("'")
        if len(syl) != len(w) or len(w) > MAXLEN or not all(ok_char(c) for c in w):
            continue
        # a..z only; a lone consonant (m, n, r, ng...) is no syllable for us: those letters are abbreviations
        if not all(s.isalpha() and s.islower() and s.isascii() and (len(s) > 1 or s in "aeo") for s in syl):
            continue
        if any(s in ("ng", "hm", "hng") for s in syl):
            continue
        entries[w].append((tuple(syl), wt))
    # probability of a word = the better of its own unigram and its best chain of model words
    def chain(w):
        best = [dict() for _ in range(len(w) + 1)]         # position -> {last token: log10 p}
        best[0][None] = 0.0
        for i in range(len(w)):
            for j in range(i + 1, len(w) + 1):
                t = w[i:j]
                if t not in uni or t == w:
                    continue
                for prev, sc in best[i].items():
                    v = sc + (uni[t] if prev is None else big.get((prev, t), bow[prev] + uni[t]))
                    if v > best[j].get(t, -1e9):
                        best[j][t] = v
        if not best[len(w)]:
            return -1e9, None
        t = max(best[len(w)], key=best[len(w)].get)
        return best[len(w)][t], t

    eff, tail = {}, {}
    for w in entries:
        own = uni.get(w, FLOOR)
        if len(w) > 1:
            sc, t = chain(w)
            if sc > own:
                eff[w], tail[w] = sc, t
                continue
        eff[w] = own
    multi = sorted((w for w in entries if len(w) > 1 and (w in uni or w in tail)), key=lambda w: -eff[w])[:a.words]
    keep = set(multi) | set(w for w in entries if len(w) == 1)
    print("lexicon: %d words (%d single characters)" % (len(keep), sum(1 for w in keep if len(w) == 1)))

    syls = sorted(set(s for w in keep for r, _ in entries[w] for s in r))
    sid = dict((s, i) for i, s in enumerate(syls))
    assert max(len(s) for s in syls) <= 7 and len(syls) < 65535

    # ---- trie in breadth-first order
    class Node(object):
        __slots__ = ("kids", "words", "idx")

        def __init__(self):
            self.kids, self.words = {}, []

    root = Node()
    for w in keep:
        best = max(wt for _, wt in entries[w])
        for r, wt in entries[w]:
            n = root
            for s in r:
                n = n.kids.setdefault(sid[s], Node())
            n.words.append((cost(eff[w] + wt), w, wt == best, wt))
    order, level = [root], [root]
    while level:
        level = [n.kids[s] for n in level for s in sorted(n.kids)]
        order += level
    # second pass for the per-node tables (children are contiguous in breadth-first order)
    node_syl, node_child, node_word = [0], [], []
    for i, n in enumerate(order):
        n.idx = i
    pos = 1
    wid = 0
    primary, other = {}, collections.defaultdict(list)       # word -> id of its main reading / [(id, weight)]
    words_by_len = collections.defaultdict(list)
    depth = {0: 0}
    for i, n in enumerate(order):
        node_child.append(pos)
        for s in sorted(n.kids):
            k = n.kids[s]
            assert k.idx == pos
            node_syl.append(s)
            depth[pos] = depth[i] + 1
            pos += 1
        node_word.append(wid)
        for c, w, main, wt in sorted(n.words):
            words_by_len[depth[i]].append((c, w))
            if main and w not in primary:
                primary[w] = wid
            else:
                other[w].append((wid, wt))
            wid += 1
    node_child.append(pos)
    node_word.append(wid)
    n_nodes, n_words = len(order), wid
    assert pos == n_nodes

    # ---- bigrams: the ones that say most beyond "back off to the unigram"
    scored = []
    for (x, y), lp in big.items():
        if y not in primary or (x not in primary and x != "<s>"):
            continue
        gain = lp - (bow[x] + uni[y])
        if gain <= 0.1:
            continue
        scored.append((-(10 ** (uni[x] + lp)) * gain, x, y, lp))
    scored.sort()
    del big
    rows = collections.defaultdict(dict)
    for _, x, y, lp in scored[:a.bigrams]:
        xa = n_words if x == "<s>" else primary[x]
        rows[xa][primary[y]] = cost(lp)
        for oid, wt in other.get(y, ()):                    # a common second reading of the follower
            if wt > -1.0:
                rows[xa][oid] = cost(lp + wt)
    bi_a = sorted(rows)
    bi_off, bi = [], []
    for x in bi_a:
        bi_off.append(len(bi))
        for y in sorted(rows[x]):
            bi.append(y << 8 | rows[x][y])
    bi_off.append(len(bi))

    # ---- write
    id_bow = [0] * n_words
    blob_words = bytearray()
    len_tab = []
    wid = 0
    for L in range(MAXLEN + 2):
        len_tab.append((wid, len(blob_words)))
        for c, w in words_by_len.get(L, ()):
            t = tail.get(w)
            bo = bow.get(t if t else w, 0.0)
            blob_words += w.encode("utf-16-le") + bytes((c, cost(bo) if bo < 0 else 0, len(t) if t else 0))
            wid += 1
    assert wid == n_words
    parts = [
        b"".join(s.encode("ascii").ljust(8, b"\0") for s in syls),
        struct.pack("<%dH" % n_nodes, *node_syl) + (b"\0\0" if n_nodes & 1 else b""),
        struct.pack("<%dI" % (n_nodes + 1), *node_child),
        struct.pack("<%dI" % (n_nodes + 1), *node_word),
        b"".join(struct.pack("<II", i, o) for i, o in len_tab),
        bytes(blob_words) + b"\0" * (-len(blob_words) % 4),
        struct.pack("<%dI" % len(bi_a), *bi_a) + struct.pack("<%dI" % len(bi_off), *bi_off),
        struct.pack("<%dI" % len(bi), *bi),
    ]
    offs, o = [], 64
    for p in parts:
        offs.append(o)
        o += len(p)
    head = struct.pack("<4s15I", b"VPY1", 1, len(syls), n_nodes, n_words, MAXLEN, len(bi_a), len(bi), *offs)
    out = os.path.abspath(a.out)
    with open(out, "wb") as f:
        f.write(head)
        for p in parts:
            f.write(p)
    print("%s: %d bytes; %d syllables, %d nodes, %d words, %d bigrams in %d rows" % (
        out, o, len(syls), n_nodes, n_words, len(bi), len(bi_a)))
    for name, p in zip("syl nodeSyl nodeChild nodeWord len words biA bi".split(), parts):
        print("  %-9s %8d" % (name, len(p)))


if __name__ == "__main__":
    main()
