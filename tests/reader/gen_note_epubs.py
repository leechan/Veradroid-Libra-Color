#!/usr/bin/env python3
"""Synthetic EPUBs for the built-in reader's footnote popup (tests/reader-notes-test.sh, EpubNoteTest).

No real book text: every note and body line is made up here. Each book covers one way EPUBs mark notes up.
Usage: gen_note_epubs.py <outdir>. Writes <name>.epub and expect.tsv:
  book  file:link-index  expected
file = the basename of the chapter file that holds the link, link-index = its place in that file's link list (Epub.Link),
expected = the popup text (\\n for a line break, a leading + when the note is longer than the cap) or JUMP (no popup: the
reader goes to the target). One more column "links=<n>" checks the number of links in that file.
"""
import os, sys, zipfile
from urllib.parse import quote

OUT = sys.argv[1] if len(sys.argv) > 1 else 'note-epubs'
BODY = '这是用来测试注释的一段正文，它没有任何意义，只是占一些位置。'

def xhtml(body):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" '
            'xmlns:epub="http://www.idpf.org/2007/ops"><head><title>测试</title></head><body>\n%s\n</body></html>\n') % body

def book(name, files, spine_skip=(), quote_names=False):
    """files: list of (path inside OEBPS, html body)"""
    z = zipfile.ZipFile(os.path.join(OUT, name + '.epub'), 'w', zipfile.ZIP_DEFLATED)
    z.writestr(zipfile.ZipInfo('mimetype'), 'application/epub+zip', compress_type=zipfile.ZIP_STORED)
    z.writestr('META-INF/container.xml', '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
               '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    man, spine = [], []
    for i, (path, body) in enumerate(files):
        href = quote(path) if quote_names else path
        man.append('<item id="f%d" href="%s" media-type="application/xhtml+xml"/>' % (i, href))
        if path not in spine_skip: spine.append('<itemref idref="f%d"/>' % i)
        z.writestr('OEBPS/' + path, xhtml(body))
    opf = ('<?xml version="1.0" encoding="utf-8"?><package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">'
           '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>注释测试 %s</dc:title><dc:language>zh</dc:language>'
           '<dc:identifier id="uid">vd-note-%s</dc:identifier></metadata><manifest>%s</manifest><spine>%s</spine></package>') % (
        name, name, ''.join(man), ''.join(spine))
    z.writestr('OEBPS/content.opf', opf)
    z.close()

EXPECT = []
def expect(name, at, text, links=None):
    EXPECT.append('\t'.join([name, at, text.replace('\n', '\\n')] + (['links=%d' % links] if links is not None else [])))

os.makedirs(OUT, exist_ok=True)

# a: EPUB3 noteref + aside footnote in the same file (two paragraphs in the second note)
book('a-aside', [('Text/c1.xhtml',
    '<p>%s<a epub:type="noteref" href="#n1" id="r1">1</a>，后面还有。<a epub:type="noteref" href="#n2">2</a></p>\n<p>%s</p>\n'
    '<aside epub:type="footnote" id="n1"><p>注释甲：第一条脚注的文字。</p></aside>\n'
    '<aside epub:type="footnote" id="n2"><p>注释乙的第一段。</p><p>注释乙的第二段。</p></aside>' % (BODY, BODY))])
expect('a-aside', 'c1:0', '注释甲：第一条脚注的文字。')
expect('a-aside', 'c1:1', '注释乙的第一段。\n\n注释乙的第二段。')

# b: [5] to a separate notes file, the note starts with its back link [5]; the back link itself jumps back
book('b-notesfile', [
    ('Text/ch1.xhtml', '<p>%s<a href="notes.xhtml#n5" id="r5">[5]</a>正文继续。<a href="notes.xhtml#n6" id="r6">[6]</a></p>' % BODY),
    ('Text/notes.xhtml', '<h2>注释</h2>\n<p><a id="n5" href="ch1.xhtml#r5">[5]</a>注释丙：在另一个文件里的注释。</p>\n'
                         '<p><a id="n6" href="ch1.xhtml#r6">[6]</a> 注释丁，带一个空格。</p>')])
expect('b-notesfile', 'ch1:0', '注释丙：在另一个文件里的注释。')
expect('b-notesfile', 'ch1:1', '注释丁，带一个空格。')
expect('b-notesfile', 'notes:0', 'JUMP')

# c: relative path into another folder, the id on the <p>, a superscript marker
book('c-relative', [
    ('Text/part1/ch.xhtml', '<p>%s<sup><a href="../../Notes/n.xhtml#fn7" id="ref7">7</a></sup>。</p>' % BODY),
    ('Notes/n.xhtml', '<p id="fn7" class="note"><a href="../Text/part1/ch.xhtml#ref7">7.</a> 注释戊：相对路径的注释。</p>')])
expect('c-relative', 'ch:0', '注释戊：相对路径的注释。')

# d: <ol class="notes"> list items with a trailing back link (pandoc / calibre style)
book('d-olnotes', [('Text/c.xhtml',
    '<p>%s<a href="#fn1" class="footnote-ref" id="fnref1"><sup>1</sup></a>，再来一个<a href="#fn2" class="footnote-ref" id="fnref2"><sup>2</sup></a>。</p>\n'
    '<section class="footnotes"><hr/><ol class="notes">\n'
    '<li id="fn1"><p>注释己：列表里的注释。<a href="#fnref1" class="footnote-back">↩</a></p></li>\n'
    '<li id="fn2"><p>注释庚。<a href="#fnref2">↩︎</a></p></li>\n</ol></section>' % BODY)])
expect('d-olnotes', 'c:0', '注释己：列表里的注释。')
expect('d-olnotes', 'c:1', '注释庚。')
expect('d-olnotes', 'c:2', 'JUMP')     # the ↩ back link

# e: Duokan: an image marker, the aside holds an empty back link and an <ol> item; the empty back link must not become a link
book('e-duokan', [('Text/c.xhtml',
    '<p>%s<a class="duokan-footnote" epub:type="noteref" href="#df1" id="df1-back"><img alt="" src="../Images/note.png"/></a>正文。</p>\n'
    '<aside epub:type="footnote" id="df1"><a href="#df1-back"></a><ol class="duokan-footnote-content">'
    '<li class="duokan-footnote-item" id="df1-c">注释辛：多看格式的注释。</li></ol></aside>' % BODY)])
expect('e-duokan', 'c:0', '注释辛：多看格式的注释。', links=1)

# f: percent-encoded file names (Chinese) in the OPF and in the href
book('f-pctname', [
    ('Text/正文.xhtml', '<p>%s<a href="%s#z2">[2]</a></p>' % (BODY, quote('注释.xhtml'))),
    ('Text/注释.xhtml', '<div id="z2"><p>[2] 注释壬：文件名是中文的注释。</p></div>')], quote_names=True)
expect('f-pctname', '正文:0', '注释壬：文件名是中文的注释。')

# g: notes as lines in one <div> separated by <br/>, anchors without text: the note stops at the next [n]
book('g-brlines', [
    ('Text/c.xhtml', '<p>%s<a href="n.xhtml#m1">[1]</a>又一处<a href="n.xhtml#m2">[2]</a></p>' % BODY),
    ('Text/n.xhtml', '<div class="notes"><a id="m1"></a>[1] 注释癸：第一行。<br/><a id="m2"></a>[2] 注释子：第二行。<br/>[3] 第三条。</div>')])
expect('g-brlines', 'c:0', '注释癸：第一行。')
expect('g-brlines', 'c:1', '注释子：第二行。')

# h: the note text in the alt of a footnote image (QQ 阅读 / 微信读书 style), no link at all
book('h-imgalt', [('Text/c.xhtml',
    '<p>%s<img class="qqreader-footnote" src="../Images/note.png" alt="注释丑：写在图片里的注释。"/>后面的字。</p>' % BODY)])
expect('h-imgalt', 'c:0', '注释丑：写在图片里的注释。', links=1)

# i: endnotes file not in the spine (manifest only), epub:type="rearnote" items
book('i-notspine', [
    ('Text/c.xhtml', '<p>%s<a epub:type="noteref" href="rear.xhtml#e1">i</a></p>' % BODY),
    ('Text/rear.xhtml', '<ol><li epub:type="rearnote" id="e1"><p>注释寅：不在书脊里的尾注。</p></li></ol>')], spine_skip=('Text/rear.xhtml',))
expect('i-notspine', 'c:0', '注释寅：不在书脊里的尾注。')

# j: a contents link to a heading: no popup, jump
book('j-toclink', [
    ('Text/c1.xhtml', '<p>%s 见<a href="c2.xhtml#h2">第二章</a>。</p>' % BODY),
    ('Text/c2.xhtml', '<h2 id="h2">第二章 测试</h2><p>%s</p>' % BODY)])
expect('j-toclink', 'c1:0', 'JUMP')

# k: a note longer than the cap
long_note = '很长的注释。' * 300
book('k-long', [('Text/c.xhtml', '<p>%s<a epub:type="noteref" href="#l1">[1]</a></p><aside epub:type="footnote" id="l1"><p>%s</p></aside>' % (BODY, long_note))])
expect('k-long', 'c:0', '+' + long_note[:1500] + '…')

# l: the back link is the number inside brackets: [<a>3</a>] note
book('l-bracket', [
    ('Text/c.xhtml', '<p>%s<a href="n.xhtml#q3" id="w3">〔3〕</a></p>' % BODY),
    ('Text/n.xhtml', '<p>[<a id="q3" href="c.xhtml#w3">3</a>] 注释卯：括号里的回链。</p>')])
expect('l-bracket', 'c:0', '注释卯：括号里的回链。')

# m: a link to a whole notes chapter (no fragment): jump
book('m-nofrag', [
    ('Text/c.xhtml', '<p>%s<a href="n.xhtml">注释</a></p>' % BODY),
    ('Text/n.xhtml', '<p>%s</p>' % BODY)])
expect('m-nofrag', 'c:0', 'JUMP')

with open(os.path.join(OUT, 'expect.tsv'), 'w', encoding='utf-8') as f:
    f.write('\n'.join(EXPECT) + '\n')
print('%d note books, %d checks' % (len(set(e.split('\t')[0] for e in EXPECT)), len(EXPECT)))
