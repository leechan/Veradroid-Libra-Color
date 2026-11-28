#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Render the boot splash title as a per-letter coloured PNG.

FBInk can only colour a whole text block (no per-character horizontal offsets),
so the title is pre-rendered here and drawn in image mode by boot/lib/splash.sh.

Usage: make-splash-title.py FONT.ttf OUT.png [--px 95] [--width 1264]
"""
import sys
from PIL import Image, ImageDraw, ImageFont

TEXT = "LibraColor(Android)"
# 品牌五色（与桌面配色一致：墨绿 / 琥珀 / 珊瑚 / 藕紫 / 天蓝）
COLORS = ["#007568", "#B57400", "#D8341F", "#A32E6B", "#1A6DB5"]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = {a.split("=")[0]: a.split("=")[1] for a in sys.argv[1:] if "=" in a and a.startswith("--")}
    if len(args) < 2:
        sys.exit(__doc__)
    font_path, out = args[0], args[1]
    px = int(opts.get("--px", 95))
    width = int(opts.get("--width", 1264))
    # 墨水屏上图片比文字渲染略淡：描 1px 边当“假粗”，和 fbink 的文字笔锋观感接近
    stroke = int(opts.get("--stroke", 1))

    font = ImageFont.truetype(font_path, px)
    ascent, descent = font.getmetrics()
    img = Image.new("RGB", (width, ascent + descent + 4), "white")
    draw = ImageDraw.Draw(img)

    advances = [font.getlength(ch) for ch in TEXT]
    total = sum(advances)
    x = (width - total) / 2.0
    for i, ch in enumerate(TEXT):
        col = COLORS[i % len(COLORS)]
        draw.text((x, 0), ch, font=font, fill=col, stroke_width=stroke, stroke_fill=col)
        x += advances[i]

    img.save(out, optimize=True)
    print(f"{out}: {img.width}x{img.height}, text {total:.1f}px, font px={px}")


if __name__ == "__main__":
    main()
