#!/usr/bin/env python3
"""Compose a review contact-sheet of all 60 monster sprites.
Family per row (lv1..lv5 + boss), scaled up nearest-neighbour for inspection.
Usage: python tools/mon_sheet.py [out.png] [--scale N] [--silhouette]
Also emits a per-family progression strip on request.
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MON = os.path.join(ROOT, "assets", "generated", "monsters")
FAMS = ["goblin", "wolf", "skeleton", "golem", "ghost",
        "bat", "treant", "beetle", "cultist", "slime"]
COLS = ["1", "2", "3", "4", "5", "boss"]


def load(fam, col):
    p = os.path.join(MON, f"{fam}_{col}.png")
    if not os.path.exists(p):
        return None
    return Image.open(p).convert("RGBA")


def silhouette(im):
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    px = im.load()
    op = out.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y][3] > 130:
                op[x, y] = (150, 156, 168, 255)
    return out


def sheet(out_path, scale=4, silh=False, bg=(46, 48, 56)):
    cell = 96 * scale // 3  # target cell footprint
    cell = 150
    pad = 10
    labelh = 20
    cw = cell + pad
    ch = cell + pad + labelh
    W = len(COLS) * cw + pad + 90
    H = len(FAMS) * ch + pad + 30
    sheet = Image.new("RGBA", (W, H), bg + (255,))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 8), "MONSTERS  lv1  lv2  lv3  lv4  lv5   BOSS"
           + ("   [SILHOUETTE]" if silh else ""), fill=(235, 235, 235, 255))
    for r, fam in enumerate(FAMS):
        cy0 = 30 + pad + r * ch
        d.text((W - 84, cy0 + cell // 2), fam, fill=(210, 210, 215, 255))
        for cci, col in enumerate(COLS):
            cx = pad + cci * cw
            cy = cy0
            sheet.paste((28, 30, 36, 255), [cx, cy, cx + cell, cy + cell])
            im = load(fam, col)
            if im is None:
                continue
            if silh:
                im = silhouette(im)
            # scale up nearest to fit cell (leave margin)
            fitmax = cell - 12
            s = min(fitmax / im.width, fitmax / im.height)
            im2 = im.resize((max(1, int(im.width * s)),
                             max(1, int(im.height * s))), Image.NEAREST)
            ox = cx + (cell - im2.width) // 2
            oy = cy + (cell - im2.height) // 2
            sheet.alpha_composite(im2, (ox, oy))
            d.text((cx + 4, cy + cell + 3), f"{fam[:4]}{col}",
                   fill=(180, 180, 185, 255))
    sheet.convert("RGB").save(out_path)
    print("wrote", out_path, sheet.size)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = args[0] if args else os.path.join(ROOT, "art_export", "mon_sheet.png")
    scale = 4
    if "--scale" in sys.argv:
        scale = int(sys.argv[sys.argv.index("--scale") + 1])
    silh = "--silhouette" in sys.argv
    sheet(out, scale=scale, silh=silh)
