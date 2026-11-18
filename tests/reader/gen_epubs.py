#!/usr/bin/env python3
"""Synthetic EPUBs for the built-in reader's TOC tests (tests/reader-toc-test.sh, EpubTocTest).

No real book text: chapter bodies are random filler from a fixed set of common characters (seeded, so the files are
the same every run). Usage: gen_epubs.py <outdir> [chars-per-chapter]

Each book is named after the case it covers; EXPECT (printed as expect.tsv) is what the reader should list:
  name  toc-count  toc-source  first-title  last-title
KOReader (crengine) shows the NCX / nav TOC as is; where the book has none it falls back to headings. Cases f and m
are books whose own TOC is incomplete (truncated NCX, spine longer than the TOC): there the reader goes past KOReader.
"""
import os, random, sys, zipfile
from urllib.parse import quote

OUT = sys.argv[1] if len(sys.argv) > 1 else 'epubs'
PER = int(sys.argv[2]) if len(sys.argv) > 2 else 600
FILL = '的一是了我不人在他有这个上们来到时大地为子中你说生国年着就那和要她出也得里后自以会家可下而过天去能对小多然于心学么之都好看起发当没成只如事把还用第样道想作种开美总从无情己面最女但现前些所同日手又行意动方期它头经长儿回位分爱老因很给名法间斯知世什两次使身者被高已亲其进此话常与活正感'
CN = '零一二三四五六七八九'

def cnum(n):
    """1..9999 -> Chinese numerals (第一千二百零三章)."""
    if n < 10: return CN[n]
    out, units, zero = '', [(1000, '千'), (100, '百'), (10, '十')], False
    for v, u in units:
        d = n // v
        if d:
            if zero: out += '零'; zero = False
            out += ('' if (v == 10 and d == 1 and not out) else CN[d]) + u
        elif out: zero = True
        n %= v
    if n:
        if zero: out += '零'
        out += CN[n]
    return out

def filler(rnd, n):
    paras, left = [], n
    while left > 0:
        k = min(left, rnd.randint(60, 220)); left -= k
        paras.append(''.join(rnd.choice(FILL) for _ in range(k)) + '。')
    return paras

def xhtml(title_tag, body):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>%s</title>'
            '<link rel="stylesheet" type="text/css" href="../Styles/style.css"/></head><body>\n%s\n</body></html>\n') % (title_tag, body)

def paras_html(rnd, n):
    return '\n'.join('<p>%s</p>' % p for p in filler(rnd, n))

class Book:
    def __init__(self, name, title):
        self.name, self.title = name, title
        self.files = []        # (path inside OEBPS, id, content, in_spine)
        self.ncx = None; self.nav = None
        self.opf_dir = 'OEBPS'
    def add(self, path, content, spine=True, id=None):
        self.files.append((path, id or 'f%d' % len(self.files), content, spine))
    def write(self, out):
        p = os.path.join(out, self.name + '.epub')
        z = zipfile.ZipFile(p, 'w', zipfile.ZIP_DEFLATED)
        z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
        z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
                   '<rootfiles><rootfile full-path="%s/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>' % self.opf_dir)
        man, spine = [], []
        for path, id, content, sp in self.files:
            man.append('<item id="%s" href="%s" media-type="application/xhtml+xml"/>' % (id, quote(path)))
            if sp: spine.append('<itemref idref="%s"/>' % id)
            z.writestr(self.opf_dir + '/' + path, content)
        z.writestr(self.opf_dir + '/Styles/style.css', 'p{text-indent:2em}')
        man.append('<item id="css" href="Styles/style.css" media-type="text/css"/>')
        if self.ncx:
            npath, ntext = self.ncx
            man.append('<item id="ncx" href="%s" media-type="application/x-dtbncx+xml"/>' % npath)
            z.writestr(self.opf_dir + '/' + npath, ntext)
        if self.nav:
            vpath, vtext = self.nav
            man.append('<item id="nav" href="%s" media-type="application/xhtml+xml" properties="nav"/>' % vpath)
            z.writestr(self.opf_dir + '/' + vpath, vtext)
        opf = ('<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="%s" unique-identifier="uid">'
               '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>%s</dc:title><dc:language>zh</dc:language>'
               '<dc:identifier id="uid">vd-test-%s</dc:identifier></metadata><manifest>%s</manifest><spine%s>%s</spine></package>') % (
            '3.0' if self.nav else '2.0', self.title, self.name, ''.join(man), ' toc="ncx"' if self.ncx else '', ''.join(spine))
        z.writestr(self.opf_dir + '/content.opf', opf)
        z.close()
        return p

def ncx(points, title='测试'):
    """points: list of (label, src, children)"""
    n = [0]
    def walk(ps):
        s = ''
        for label, src, kids in ps:
            n[0] += 1
            s += '<navPoint id="np%d" playOrder="%d"><navLabel><text>%s</text></navLabel><content src="%s"/>%s</navPoint>\n' % (
                n[0], n[0], label, src, walk(kids))
        return s
    return ('<?xml version="1.0" encoding="UTF-8"?><ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1"><head></head>'
            '<docTitle><text>%s</text></docTitle><navMap>\n%s</navMap><pageList><pageTarget id="pg1" type="normal" value="1">'
            '<navLabel><text>1</text></navLabel><content src="Text/c0001.xhtml"/></pageTarget></pageList></ncx>') % (title, walk(points))

def nav(points):
    def walk(ps):
        s = '<ol>'
        for label, src, kids in ps:
            s += '<li>' + ('<a href="%s">%s</a>' % (src, label) if src else '<span>%s</span>' % label) + (walk(kids) if kids else '') + '</li>\n'
        return s + '</ol>'
    return xhtml('目录', '<nav epub:type="toc" id="toc"><h1>目录</h1>%s</nav><nav epub:type="landmarks"><ol><li><a href="Text/c0001.xhtml">正文</a></li></ol></nav>' % walk(points))

def ctitle(i):
    return '第%s章　%s' % (cnum(i), ['风起', '云涌', '夜行', '归来', '别离', '初见'][i % 6])

def simple(name, count, with_ncx, with_nav, rnd, per=None):
    b = Book(name, '测试长篇' + name)
    pts = []
    for i in range(1, count + 1):
        f = 'Text/c%04d.xhtml' % i
        # <title> is the book title in every file (common in web-novel EPUBs): it must not become the chapter name
        b.add(f, xhtml(b.title, '<h2>%s</h2>\n%s' % (ctitle(i), paras_html(rnd, per or PER))))
        pts.append((ctitle(i), f, []))
    if with_ncx: b.ncx = ('toc.ncx', ncx(pts))
    if with_nav: b.nav = ('nav.xhtml', nav(pts))
    return b, count, 'nav' if with_nav else 'ncx', ctitle(1).replace('\u3000', ' '), ctitle(count).replace('　', ' ')

def main():
    os.makedirs(OUT, exist_ok=True)
    rnd = random.Random(1234)
    expect = []
    def put(b, *e):
        b.write(OUT); expect.append((b.name,) + tuple(str(x) for x in e))

    b, *e = simple('a-ncx1200', 1200, True, False, rnd); put(b, *e)
    b, *e = simple('b-nav1200', 1200, False, True, rnd); put(b, *e)
    b, *e = simple('c-both1200', 1200, True, True, rnd); put(b, *e)

    # d: nested volumes in the NCX (卷 → 章); volume title pages are files with only the volume name (too short to be a chapter)
    b = Book('d-volumes', '分卷测试'); pts = []; n = 0
    for v in range(1, 7):
        vf = 'Text/v%02d.xhtml' % v
        b.add(vf, xhtml(b.title, '<h1>第%s卷</h1>' % cnum(v)))
        kids = []
        for k in range(200):
            n += 1; f = 'Text/c%04d.xhtml' % n
            b.add(f, xhtml(b.title, '<h2>%s</h2>\n%s' % (ctitle(n), paras_html(rnd, PER // 2))))
            kids.append((ctitle(n), f, []))
        pts.append(('第%s卷' % cnum(v), vf, kids))
    b.ncx = ('toc.ncx', ncx(pts)); put(b, 1206, 'ncx', '第一卷', ctitle(1200).replace('　', ' '))

    # e: ten chapters per file, NCX points at #anchors
    b = Book('e-anchors', '多章一文件'); pts = []; n = 0
    for fi in range(1, 121):
        f = 'Text/part%03d.xhtml' % fi; body = ''
        for k in range(10):
            n += 1
            body += '<h3 id="ch%d">%s</h3>\n%s\n' % (n, ctitle(n), paras_html(rnd, PER // 2))
            pts.append((ctitle(n), '%s#ch%d' % (f, n), []))
        b.add(f, xhtml(b.title, body))
    b.ncx = ('toc.ncx', ncx(pts)); put(b, 1200, 'ncx', ctitle(1).replace('\u3000', ' '), ctitle(1200).replace('　', ' '))

    # f: NCX truncated to the first 200 chapters, spine has 1200 (the shadow-library case): 第X章 headings take over
    b, *_ = simple('f-truncated', 1200, False, False, rnd)
    b.ncx = ('toc.ncx', ncx([(ctitle(i), 'Text/c%04d.xhtml' % i, []) for i in range(1, 201)]))
    put(b, 1200, 'headings', ctitle(1).replace('\u3000', ' '), ctitle(1200).replace('　', ' '))

    # g: no TOC at all, titles only in <p class="title">
    b = Book('g-ptitle', '无目录')
    for i in range(1, 1201):
        b.add('Text/c%04d.xhtml' % i, xhtml(b.title, '<p class="title">%s</p>\n%s' % (ctitle(i), paras_html(rnd, PER // 2))))
    put(b, 1200, 'headings', ctitle(1).replace('\u3000', ' '), ctitle(1200).replace('　', ' '))

    # h: no TOC, titles without 第X章 in <h2 class="chapterTitle">, book title once in an <h1>
    b = Book('h-h2names', '无目录二')
    names = ['风起云涌', '夜雨江湖', '长河落日', '孤城远望', '星垂平野']
    for i in range(1, 401):
        head = '<h1>无目录二</h1>' if i == 1 else ''
        b.add('Text/c%04d.xhtml' % i, xhtml(b.title, '%s<h2 class="chapterTitle">%s%d</h2>\n%s' % (head, names[i % 5], i, paras_html(rnd, PER // 2))))
    put(b, 400, 'headings', names[1] + '1', names[0] + '400')

    # i: Calibre split files: 300 chapters, each split into 1-4 index_split_NNN.html files; NCX points at the first part
    b = Book('i-calibre', 'Calibre 拆分'); pts = []; k = 0
    for i in range(1, 301):
        parts = 1 + (i % 4)
        for p in range(parts):
            f = 'index_split_%03d.html' % k; k += 1
            body = ('<h2 class="calibre1" id="calibre_toc_%d">%s</h2>\n' % (i, ctitle(i)) if p == 0 else '') + paras_html(rnd, PER // 3)
            b.add(f, xhtml('Unknown', body))
            if p == 0: pts.append((ctitle(i), f + '#calibre_toc_%d' % i, []))
    b.opf_dir = 'OEBPS'
    b.ncx = ('toc.ncx', ncx(pts)); put(b, 300, 'ncx', ctitle(1).replace('\u3000', ' '), ctitle(300).replace('　', ' '))

    # k: percent-encoded Chinese file names in a nested dir, NCX in another dir with ../ hrefs, empty navLabels for some
    b = Book('k-pctnames', '编码文件名'); pts = []
    for i in range(1, 101):
        f = 'Text/第%03d章.xhtml' % i
        b.add(f, xhtml(b.title, '<h2>%s</h2>\n%s' % (ctitle(i), paras_html(rnd, PER // 2))))
        pts.append(('' if i % 10 == 0 else ctitle(i), '../' + quote(f), []))
    b.ncx = ('Misc/toc.ncx', ncx(pts)); put(b, 100, 'ncx', ctitle(1).replace('\u3000', ' '), ctitle(100).replace('　', ' '))

    # m: TOC lists 300 chapters, the spine then has 20 extra 番外 files with headings but no TOC entries
    b, *_ = simple('m-gaps', 300, True, False, rnd)
    for i in range(1, 21):
        b.add('Text/x%02d.xhtml' % i, xhtml(b.title, '<h2>番外%s　后日谈</h2>\n%s' % (cnum(i), paras_html(rnd, PER // 2))))
    put(b, 320, 'ncx', ctitle(1).replace('\u3000', ' '), '番外二十 后日谈')

    # n: big book for the device: 3000 chapters, NCX + nav, ~2400 chars each
    if os.environ.get('VD_BIG'):
        b, *e = simple('n-big3000', 3000, True, True, rnd, int(os.environ['VD_BIG'])); put(b, *e)

    with open(os.path.join(OUT, 'expect.tsv'), 'w', encoding='utf-8') as f:
        for e in expect: f.write('\t'.join(e) + '\n')

if __name__ == '__main__':
    main()
