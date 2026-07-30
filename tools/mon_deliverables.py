#!/usr/bin/env python3
"""Compose round-3 monster-art review deliverables into OUTDIR:
  - boss_lineup.png       : all 10 bosses side by side (threat check, A1)
  - progression_<fam>.png : per-family 6-across ladder rows (already in sheet)
  - before_after.png      : before baseline vs after, stacked
Run after gen_art.py. Usage: python tools/mon_deliverables.py <outdir>
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MON = os.path.join(ROOT, "assets", "generated", "monsters")
FAMS = ["goblin", "wolf", "skeleton", "golem", "ghost",
        "bat", "treant", "beetle", "cultist", "slime"]


def up(path, s):
    im = Image.open(path).convert("RGBA")
    return im.resize((im.width * s, im.height * s), Image.NEAREST)


def boss_lineup(out):
    cell = 200
    pad = 12
    W = len(FAMS) * (cell + pad) + pad
    H = cell + pad + 34
    sheet = Image.new("RGBA", (W, H), (40, 30, 44, 255))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 8), "BOSS LINEUP  — all 10 bosses, threat + no-round check",
           fill=(240, 235, 235, 255))
    for i, fam in enumerate(FAMS):
        x = pad + i * (cell + pad)
        y = 30
        sheet.paste((26, 20, 30, 255), [x, y, x + cell, y + cell])
        im = up(os.path.join(MON, f"{fam}_boss.png"), 2)
        s = min((cell - 10) / im.width, (cell - 10) / im.height)
        im = im.resize((int(im.width * s), int(im.height * s)), Image.NEAREST)
        sheet.alpha_composite(im, (x + (cell - im.width) // 2,
                                   y + (cell - im.height) // 2))
        d.text((x + 6, y + cell - 16), fam, fill=(210, 205, 210, 255))
    sheet.convert("RGB").save(out)
    print("wrote", out)


def progression(out):
    """One tall image: each family a row of lv1..lv5+boss, 6-across, upscaled."""
    cell = 120
    pad = 8
    lab = 74
    cols = 6
    W = cols * (cell + pad) + pad + lab
    rowh = cell + pad + 16
    H = len(FAMS) * rowh + pad + 24
    sheet = Image.new("RGBA", (W, H), (44, 46, 54, 255))
    d = ImageDraw.Draw(sheet)
    d.text((pad, 6), "PROGRESSION  lv1 -> lv2 -> lv3 -> lv4 -> lv5 -> BOSS "
           "(weak->strong: colour deepens, kit accrues, size grows)",
           fill=(235, 235, 235, 255))
    for r, fam in enumerate(FAMS):
        y = 24 + pad + r * rowh
        d.text((W - lab + 4, y + cell // 2), fam, fill=(215, 215, 220, 255))
        for ci, col in enumerate(["1", "2", "3", "4", "5", "boss"]):
            x = pad + ci * (cell + pad)
            sheet.paste((26, 28, 34, 255), [x, y, x + cell, y + cell])
            im = up(os.path.join(MON, f"{fam}_{col}.png"), 4)
            s = min((cell - 10) / im.width, (cell - 10) / im.height)
            im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))),
                           Image.NEAREST)
            sheet.alpha_composite(im, (x + (cell - im.width) // 2,
                                       y + (cell - im.height) // 2))
    sheet.convert("RGB").save(out)
    print("wrote", out)


if __name__ == "__main__":
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "art_export")
    os.makedirs(outdir, exist_ok=True)
    boss_lineup(os.path.join(outdir, "boss_lineup.png"))
    progression(os.path.join(outdir, "progression_all.png"))
