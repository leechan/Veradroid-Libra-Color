#!/usr/bin/env python3
"""Generate display/badge_font.h: the 1-bit glyphs and line icons the e-ink bridge (veradroid-epd) uses to draw the
gesture badge (BADGE command, docs/gesture-hint.md) without any font file on the Kindle.

    python3 tools/gen-badge-font.py <NotoSansCJK-Regular.ttc> <Roboto-Bold.ttf> > display/badge_font.h

Fonts: Noto Sans CJK (SIL OFL 1.1) and Roboto (Apache 2.0), both from the AOSP tree
(external/noto-fonts/cjk, external/roboto-fonts). Needs Pillow. The CJK set is every CJK character that appears in a
double-quoted string in the code (not the comments) of host/*/boot/action.sh, plus a few spares; run it again after
adding a new label there (the bridge skips characters it has no glyph for).
"""
import glob
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CJK_TTC, ROBOTO = sys.argv[1], sys.argv[2]
SC = 2  # face index of Noto Sans CJK SC in the .ttc

SPARE = "返回面板切换桌面清残影反色亮度暖光前开关截图重启关闭打应用没有响应长按左右上下角两指轻点到可能卡住了请稍候"


def cjk_chars():
    s = set(SPARE)
    for f in glob.glob(os.path.join(ROOT, "host", "*", "boot", "action.sh")):
        for line in open(f, encoding="utf-8"):
            code = line.split(" #")[0] if not line.lstrip().startswith("#") else ""
            for q in re.findall(r'"([^"]*)"', code):
                s.update(c for c in q if ord(c) >= 0x2E80)
    return sorted(s)


ASCII = [chr(c) for c in range(0x20, 0x7F)]


def render(chars, size, cjk_bold):
    """one font size: every glyph is a cell as tall as the line and as wide as its advance; 1 bit per pixel"""
    cjk = ImageFont.truetype(CJK_TTC, size, index=SC)
    lat = ImageFont.truetype(ROBOTO, size)
    asc, desc = cjk.getmetrics()
    la, ld = lat.getmetrics()
    base = max(asc, la)
    height = base + max(desc, ld)
    # trim: the CJK em box has a lot of air above and below; keep the line tight but never cut ink
    out = []
    for ch in chars:
        f = cjk if ord(ch) >= 0x2E80 else lat
        adv = int(round(f.getlength(ch)))
        if ch == " ":
            adv = size // 3
        im = Image.new("L", (adv + 4, height), 0)
        d = ImageDraw.Draw(im)
        a = f.getmetrics()[0]
        sw = 1 if (cjk_bold and f is cjk) else 0
        d.text((0, base - a), ch, font=f, fill=255, stroke_width=sw, stroke_fill=255)
        bb = im.getbbox()
        w = max(adv + sw, (bb[2] if bb else 0))
        im = im.crop((0, 0, w, height))
        out.append((ord(ch), adv + sw, w, im))
    # common vertical trim over the whole set
    top, bot = height, 0
    for _, _, _, im in out:
        bb = im.getbbox()
        if bb:
            top, bot = min(top, bb[1]), max(bot, bb[3])
    top = max(0, top - 1)
    bot = min(height, bot + 1)
    res = []
    for cp, adv, w, im in out:
        res.append((cp, adv, w, im.crop((0, top, w, bot))))
    return res, bot - top


def pack(im, thr=110):
    w, h = im.size
    px = im.load()
    rows = []
    for y in range(h):
        bits = 0
        row = []
        for x in range(w):
            bits = (bits << 1) | (1 if px[x, y] >= thr else 0)
            if x % 8 == 7:
                row.append(bits)
                bits = 0
        if w % 8:
            row.append(bits << (8 - w % 8))
        rows.extend(row)
    return rows


# ---- icons: drawn at 4x on a 24-unit grid (like VeraHome's Icons.java), stroke 2 units, scaled down ----
IC = 56
S4 = IC * 4
U = S4 / 24.0


def P(x, y):
    return (x * U, y * U)


def line(d, pts, w=2.0):
    d.line([P(*p) for p in pts], fill=255, width=int(w * U), joint="curve")
    for p in (pts[0], pts[-1]):
        r = w * U / 2
        x, y = P(*p)
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)


def rect(d, x0, y0, x1, y1, w=2.0, fill=False):
    if fill:
        d.rectangle((*P(x0, y0), *P(x1, y1)), fill=255)
    else:
        d.rectangle((*P(x0, y0), *P(x1, y1)), outline=255, width=int(w * U))


def circle(d, cx, cy, r, w=2.0, fill=False):
    box = (*P(cx - r, cy - r), *P(cx + r, cy + r))
    if fill:
        d.ellipse(box, fill=255)
    else:
        d.ellipse(box, outline=255, width=int(w * U))


def arc(d, cx, cy, r, a0, a1, w=2.0):
    d.arc((*P(cx - r, cy - r), *P(cx + r, cy + r)), a0, a1, fill=255, width=int(w * U))


def icon(name):
    im = Image.new("L", (S4, S4), 0)
    d = ImageDraw.Draw(im)
    if name == "back":
        line(d, [(19, 12), (5, 12)]); line(d, [(11, 6), (5, 12), (11, 18)])
    elif name == "home":            # four squares, as on the 方块 home / switcher ("桌面")
        for x, y in ((3, 3), (13, 3), (3, 13), (13, 13)):
            rect(d, x, y, x + 8, y + 8)
    elif name == "panel":           # a sheet pulled down from the top edge
        rect(d, 3, 2, 21, 5, fill=True); rect(d, 3, 2, 21, 14); line(d, [(8, 18), (12, 22), (16, 18)])
    elif name == "switch":          # two stacked squares
        rect(d, 8, 3, 21, 16); rect(d, 3, 8, 16, 21); d.rectangle((*P(4, 9), *P(15, 20)), fill=0); rect(d, 3, 8, 16, 21)
    elif name == "kindle":          # an open book
        line(d, [(12, 6), (12, 20)]); line(d, [(12, 6), (7, 4), (2, 5), (2, 19), (7, 18), (12, 20)])
        line(d, [(12, 6), (17, 4), (22, 5), (22, 19), (17, 18), (12, 20)])
    elif name in ("clear", "restart"):
        arc(d, 12, 12, 8, 40, 330); line(d, [(20, 4), (20, 10), (14, 10)])
        if name == "clear":
            circle(d, 12, 12, 2, fill=True)
    elif name == "invert":
        circle(d, 12, 12, 9); d.pieslice((*P(3, 3), *P(21, 21)), 90, 270, fill=255)
    elif name == "light":
        circle(d, 12, 12, 4)
        for a in range(8):
            import math
            t = a * math.pi / 4
            line(d, [(12 + 7 * math.cos(t), 12 + 7 * math.sin(t)), (12 + 10 * math.cos(t), 12 + 10 * math.sin(t))])
    elif name == "warm":            # a flame
        line(d, [(12, 2), (17, 9), (18, 14), (16, 19), (12, 21), (8, 19), (6, 14), (8, 9), (12, 2)])
        line(d, [(12, 12), (14, 15), (13, 18), (11, 18), (10, 15), (12, 12)], 1.6)
    elif name == "stuck":           # a square with "!" (方块 warning)
        rect(d, 3, 3, 21, 21, 2.4); rect(d, 10.6, 6.5, 13.4, 14.5, fill=True); rect(d, 10.6, 16.5, 13.4, 19.2, fill=True)
    elif name == "power":
        arc(d, 12, 13, 8, 300, 240); line(d, [(12, 3), (12, 12)])
    elif name == "camera":
        rect(d, 2, 7, 22, 20); rect(d, 8, 4, 16, 7, fill=True); circle(d, 12, 13.5, 4)
    elif name == "wifi":
        for r in (4, 8, 12):
            arc(d, 12, 20, r, 225, 315)
        circle(d, 12, 20, 1.6, fill=True)
    elif name == "app":
        rect(d, 3, 3, 21, 21); line(d, [(12, 7), (12, 17)]); line(d, [(7, 12), (17, 12)])
    else:                           # unknown name: a plain dot
        circle(d, 12, 12, 4, fill=True)
    return im.resize((IC, IC), Image.LANCZOS)


ICONS = ["back", "home", "panel", "switch", "kindle", "clear", "restart", "invert", "light", "warm", "stuck",
         "power", "camera", "wifi", "app"]


def emit_font(name, glyphs, h, o):
    data = []
    o.append(f"static const struct bg_glyph {name}_g[] = {{")
    for cp, adv, w, im in glyphs:
        off = len(data)
        data += pack(im)
        o.append(f"    {{ 0x{cp:04x}, {adv}, {w}, {off} }},")
    o.append("};")
    o.append(f"static const uint8_t {name}_bits[] = {{")
    for i in range(0, len(data), 24):
        o.append("    " + ",".join(str(b) for b in data[i:i + 24]) + ",")
    o.append("};")
    o.append(f"static const struct bg_font {name} = {{ {h}, {len(glyphs)}, {name}_g, {name}_bits }};")


def main():
    cj = cjk_chars()
    o = ["/* generated by tools/gen-badge-font.py - do not edit. Glyphs: Noto Sans CJK SC (SIL OFL 1.1), Roboto Bold",
         "   (Apache 2.0), rendered 1 bit per pixel; rows padded to whole bytes, MSB first. */",
         "#include <stdint.h>",
         "struct bg_glyph { uint32_t cp; uint16_t adv, w; uint32_t off; };",
         "struct bg_font { int h, n; const struct bg_glyph *g; const uint8_t *bits; };",
         "struct bg_icon { const char *name; const uint8_t *bits; };",
         f"#define BG_ICON {IC}"]
    lab, lh = render(sorted(ASCII + cj, key=ord), 40, True)
    sub, sh = render(sorted(ASCII + cj, key=ord), 26, True)
    cap, ch = render(ASCII, 17, False)
    emit_font("bg_label", lab, lh, o)
    emit_font("bg_sub", sub, sh, o)
    emit_font("bg_cap", cap, ch, o)
    for n in ICONS:
        o.append(f"static const uint8_t bg_icon_{n}[] = {{ " + ",".join(str(b) for b in pack(icon(n), 128)) + " };")
    o.append("static const struct bg_icon bg_icons[] = {")
    for n in ICONS:
        o.append(f'    {{ "{n}", bg_icon_{n} }},')
    o.append("};")
    print("\n".join(o))
    sys.stderr.write(f"{len(cj)} CJK chars, label h={lh}, sub h={sh}, caps h={ch}\n")


main()
