#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild assets/pinyin.tsv from the public pinyin/word-frequency data.

Sources (all MIT):
  https://github.com/mozillazg/pinyin-data          character -> pinyin
  https://github.com/mozillazg/phrase-pinyin-data   phrase -> pinyin
  https://github.com/fxsjy/jieba                    word frequencies

Run from this directory:  python3 tools/gen_dict.py
"""
import collections
import os
import re
import urllib.request

BASE = "https://raw.githubusercontent.com/"
TONE = str.maketrans({
    "ā": "a", "á": "a", "ǎ": "a", "à": "a", "ē": "e", "é": "e", "ě": "e", "è": "e",
    "ī": "i", "í": "i", "ǐ": "i", "ì": "i", "ō": "o", "ó": "o", "ǒ": "o", "ò": "o",
    "ū": "u", "ú": "u", "ǔ": "u", "ù": "u", "ǖ": "v", "ǘ": "v", "ǚ": "v", "ǜ": "v", "ü": "v",
    "ń": "n", "ň": "n", "ǹ": "n", "ḿ": "m",
})


def fetch(url):
    print("GET", url)
    return urllib.request.urlopen(url, timeout=60).read().decode("utf-8")


def plain(s):
    return re.sub(r"[^a-zv]", "", s.translate(TONE).lower())


def main():
    chars = collections.defaultdict(list)
    for line in fetch(BASE + "mozillazg/pinyin-data/master/pinyin.txt").splitlines():
        m = re.match(r"U\+([0-9A-Fa-f]+):\s*([^#]+)", line.strip())
        if not m:
            continue
        ch = chr(int(m.group(1), 16))
        if not ("\u4e00" <= ch <= "\u9fff"):
            continue
        for p in m.group(2).split(","):
            q = plain(p)
            if q and q not in chars[ch]:
                chars[ch].append(q)

    freq = {}
    for line in fetch(BASE + "fxsjy/jieba/master/jieba/dict.txt").splitlines():
        p = line.split()
        if len(p) >= 2 and re.fullmatch(r"[\u4e00-\u9fff]+", p[0]):
            try:
                freq[p[0]] = int(p[1])
            except ValueError:
                pass

    syllable = collections.defaultdict(list)
    for ch, ps in chars.items():
        for p in ps:
            syllable[p].append((freq.get(ch, 0), ch))
    for p in syllable:
        syllable[p] = [c for _, c in sorted(syllable[p], reverse=True)[:24]]

    phrase = {}
    for line in fetch(BASE + "mozillazg/phrase-pinyin-data/master/pinyin.txt").splitlines():
        if ":" not in line:
            continue
        w, py = line.split(":", 1)
        w, py = w.strip(), py.strip()
        if not re.fullmatch(r"[\u4e00-\u9fff]{2,4}", w):
            continue
        key = "".join(plain(x) for x in py.split())
        if key:
            phrase[w] = key

    words = []
    for w, key in phrase.items():
        f = freq.get(w, 0)
        if f >= 2:
            words.append((f, w, key))
    words.sort(reverse=True)

    by_key = collections.defaultdict(list)
    total = 0
    for f, w, key in words:
        if len(by_key[key]) < 8:
            by_key[key].append(w)
            total += 1
        if total >= 20000:
            break

    out = os.path.join(os.path.dirname(__file__), "..", "assets", "pinyin.tsv")
    with open(out, "w", encoding="utf-8") as f:
        f.write("# VeraIME pinyin dictionary: type,key,candidates\n")
        for p in sorted(syllable):
            if syllable[p]:
                f.write("C\t%s\t%s\n" % (p, "".join(syllable[p])))
        for key in sorted(by_key):
            f.write("W\t%s\t%s\n" % (key, "|".join(by_key[key])))
    print("wrote", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
