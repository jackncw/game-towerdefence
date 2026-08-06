#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""monster_compare.py — 新舊怪物喺**真實顯示尺寸**下嘅對照圖。

舊圖顯示尺寸 = 檔案邊長 × GameData.RENDER_SCALE(2.0)
新圖顯示尺寸 = 檔案邊長 × (2.0 / SS),SS = 3(lv1-5) / 2(boss)
兩者用同一條地面線,睇得出接地點對唔對得返。
"""
import os, sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OLD = os.path.join(ROOT, "assets", "generated", "monsters")
NEW = os.path.join(ROOT, "qa", "monster_cutout", "out")
FAMS = ["goblin", "wolf", "skeleton", "golem", "ghost",
        "bat", "treant", "beetle", "cultist", "slime"]
LEVELS = ["1", "2", "3", "4", "5", "boss"]


def disp(path, boss):
    im = Image.open(path).convert("RGBA")
    ss = 1.5 if boss else 2.5
    k = 2.0 / ss if "monster_cutout" in path else 2.0
    return im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)


def main(out, levels=LEVELS):
    CW, CH = 230, 230
    W = CW * len(levels) + 60
    H = CH * len(FAMS) * 2 + 20
    page = Image.new("RGB", (W, H), (44, 40, 36))
    dr = ImageDraw.Draw(page)
    for r, fam in enumerate(FAMS):
        for half in (0, 1):                       # 0 = 舊, 1 = 新
            row = r * 2 + half
            y0 = 10 + row * CH
            # sprite 中心 = 怪物喺路上嘅位置(Sprite2D centered),所以對照要
            # 對中心線,唔係對圖底 —— 咁先睇得出腳有冇浮 / 沉。
            axis = y0 + CH // 2
            dr.rectangle([60, axis, W, axis + 1], fill=(96, 82, 66))
            dr.text((6, y0 + CH // 2 - 4), "%s %s" % (fam, "NEW" if half else "old"),
                    fill=(230, 226, 220))
            for c, lv in enumerate(levels):
                p = os.path.join(NEW if half else OLD, "%s_%s.png" % (fam, lv))
                if not os.path.exists(p):
                    continue
                im = disp(p, lv == "boss")
                x = 60 + c * CW + (CW - im.width) // 2
                page.paste(im, (x, axis - im.height // 2), im)
    page.save(out)
    print("compare ->", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "compare.png")
