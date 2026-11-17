#!/usr/bin/env python3
"""Covers of the Kindle library entries (the `# Icon: data:image/png;base64,...` line of each scriptlet).

The Kindle indexer (sh_integration_extractor.so, docs/host-settings.md) decodes that line into <script>.sdr/icon.png and
shows it as the book cover. Until 0.97 / legacy 0.8.9 every entry had the same cover, so "VeraDroid 卸载" looked exactly
like "VeraDroid 启动" (users tapped the wrong one). Each kind of entry now gets its own cover; uninstall is the only
one that is black (inverted) with a warning sign and big "卸载".

    python3 tools/gen-entry-covers.py            rewrite the # Icon: line of every entry file that exists in this tree
    python3 tools/gen-entry-covers.py --check    exit 1 if a file's cover differs from what this script draws
    python3 tools/gen-entry-covers.py --png DIR  also write the PNGs to DIR (for looking at them)

Needs Pillow (check: python3 -c 'import PIL'). Font: fonts/LXGWWenKai-Regular.ttf (OFL, in the repo), so the
output is the same on every machine. 160x240 8-bit grey, like the old cover; each PNG is a few KB.
"""
import base64, io, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "fonts", "LXGWWenKai-Regular.ttf")
W, H = 160, 240
BLACK, WHITE, GREY = 0, 255, 200


def font(px):
    return ImageFont.truetype(FONT, px)


def text(d, xy, s, px, fill, stroke=1):
    d.text(xy, s, font=font(px), fill=fill, anchor="mm", stroke_width=stroke, stroke_fill=fill)


def fit(s, px, maxw, stroke=1):
    while px > 10 and font(px).getbbox(s, stroke_width=stroke)[2] > maxw:
        px -= 1
    return px


def frame(d, fg, bg):
    d.rectangle([0, 0, W - 1, H - 1], fill=bg)
    d.rectangle([4, 4, W - 5, H - 5], outline=fg, width=3)
    text(d, (W // 2, 24), "VeraDroid", 18, fg, 0)
    d.line([20, 40, W - 21, 40], fill=fg, width=2)


def big_word(d, word, fg, y=170, px=52):
    text(d, (W // 2, y), word, fit(word, px, W - 24, 2), fg, 2)


def sub(d, s, fg, y=212):
    if s:
        text(d, (W // 2, y), s, fit(s, 20, W - 24, 0), fg, 0)


def tray(d, fg, y):   # open box the arrows go into / come out of
    d.line([42, y, 42, y + 22, 118, y + 22, 118, y], fill=fg, width=5, joint="curve")


def start(sub_s=""):
    im = Image.new("L", (W, H)); d = ImageDraw.Draw(im)
    frame(d, BLACK, WHITE)
    cx, cy, r = W // 2, 96, 40
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=BLACK)
    d.polygon([(cx - 13, cy - 22), (cx - 13, cy + 22), (cx + 24, cy)], fill=WHITE)   # play
    big_word(d, "启动", BLACK)
    sub(d, sub_s, BLACK)
    return im


def install(sub_s=""):
    im = Image.new("L", (W, H)); d = ImageDraw.Draw(im)
    frame(d, BLACK, WHITE)
    d.rectangle([72, 56, 88, 98], fill=BLACK)                      # arrow down into a tray
    d.polygon([(56, 96), (104, 96), (80, 120)], fill=BLACK)
    tray(d, BLACK, 108)
    big_word(d, "安装", BLACK)
    sub(d, sub_s, BLACK)
    return im


def update(sub_s=""):
    im = Image.new("L", (W, H)); d = ImageDraw.Draw(im)
    frame(d, BLACK, WHITE)
    cx, cy, r = W // 2, 96, 34
    d.arc([cx - r, cy - r, cx + r, cy + r], 200, 340, fill=BLACK, width=8)   # two arrows in a circle
    d.arc([cx - r, cy - r, cx + r, cy + r], 20, 160, fill=BLACK, width=8)
    d.polygon([(cx + 22, cy - 34), (cx + 44, cy - 20), (cx + 22, cy - 6)], fill=BLACK)
    d.polygon([(cx - 22, cy + 34), (cx - 44, cy + 20), (cx - 22, cy + 6)], fill=BLACK)
    big_word(d, "更新", BLACK)
    sub(d, sub_s, BLACK)
    return im


def report(sub_s="测试结果"):
    im = Image.new("L", (W, H)); d = ImageDraw.Draw(im)
    frame(d, BLACK, WHITE)
    d.rectangle([72, 74, 88, 114], fill=BLACK)                     # arrow up out of a tray
    d.polygon([(56, 78), (104, 78), (80, 52)], fill=BLACK)
    tray(d, BLACK, 108)
    big_word(d, "上传", BLACK)
    sub(d, sub_s, BLACK)
    return im


def factory(sub_s="清空 Android 数据"):
    im = Image.new("L", (W, H)); d = ImageDraw.Draw(im)
    frame(d, BLACK, GREY)
    d.rectangle([72, 56, 88, 98], fill=BLACK)
    d.polygon([(56, 96), (104, 96), (80, 120)], fill=BLACK)
    tray(d, BLACK, 108)
    big_word(d, "全新安装", BLACK, px=40)
    sub(d, sub_s, BLACK)
    return im


def uninstall(sub_s="删除 VeraDroid"):
    """The dangerous one: black cover, hazard stripes, a warning triangle, huge 卸载."""
    im = Image.new("L", (W, H), BLACK); d = ImageDraw.Draw(im)
    for band in ((0, 18), (H - 18, H)):                             # diagonal hazard stripes top and bottom
        y0, y1 = band
        for x in range(-40, W + 40, 20):
            d.polygon([(x, y1), (x + 10, y1), (x + 10 + (y1 - y0), y0), (x + (y1 - y0), y0)], fill=WHITE)
    cx = W // 2
    d.polygon([(cx, 34), (cx + 46, 112), (cx - 46, 112)], fill=WHITE)   # warning sign
    d.rectangle([cx - 5, 56, cx + 5, 90], fill=BLACK)
    d.rectangle([cx - 5, 96, cx + 5, 105], fill=BLACK)
    text(d, (cx, 160), "卸载", fit("卸载", 64, W - 16, 3), WHITE, 3)
    text(d, (cx, 204), sub_s, fit(sub_s, 18, W - 20, 0), WHITE, 0)
    return im


# file (relative to the repo) -> cover. Files that do not exist in this tree are skipped.
COVERS = {
    "host/pw6/VeraDroid-Launch.sh": start,
    "host/k49/VeraDroid-Launch.sh": start,
    "host/legacy/VeraDroid-Launch.sh": start,
    "cloud/static/VeraDroid-Launch.sh": start,
    "cloud/static/VeraDroid.sh": install,
    "cloud/static/VeraDroid-Experimental.sh": lambda: install("实验机型"),
    "cloud/static/VeraDroid-Legacy.sh": lambda: install("老机型"),
    "cloud/static/VeraDroid-Offline.sh": lambda: install("离线安装"),
    "cloud/static/VeraDroid-Update.sh": update,
    "cloud/static/VeraDroid-Factory.sh": factory,
    "host/legacy/entries/VeraDroid-Report.sh": report,
    "host/legacy/entries/VeraDroid-Uninstall.sh": uninstall,
    "host/pw6/entries/VeraDroid-Uninstall.sh": uninstall,
    "host/k49/entries/VeraDroid-Uninstall.sh": uninstall,
}


def png(im):
    b = io.BytesIO()
    im.save(b, "PNG", optimize=True)
    return b.getvalue()


def main(argv):
    check = "--check" in argv
    pngdir = argv[argv.index("--png") + 1] if "--png" in argv else None
    bad = 0
    for rel, fn in COVERS.items():
        p = os.path.join(ROOT, rel)
        if not os.path.isfile(p):
            continue
        data = png(fn())
        line = "# Icon: data:image/png;base64," + base64.b64encode(data).decode() + "\n"
        if pngdir:
            os.makedirs(pngdir, exist_ok=True)
            with open(os.path.join(pngdir, os.path.basename(rel).replace(".sh", ".png")), "wb") as f:
                f.write(data)
        with open(p, encoding="utf-8") as f:
            lines = f.readlines()
        idx = [i for i, l in enumerate(lines[:6]) if l.startswith("# Icon:")]
        if not idx:
            print("no # Icon: line in the header of", rel); bad += 1; continue
        if lines[idx[0]] == line:
            continue
        if check:
            print("cover out of date:", rel); bad += 1; continue
        lines[idx[0]] = line
        with open(p, "w", encoding="utf-8") as f:
            f.writelines(lines)
        print("cover written: %s (%d bytes)" % (rel, len(data)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
