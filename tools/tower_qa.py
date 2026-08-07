#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tower_qa.py — 塔 / 魔法摳圖驗收。round-19 `monster_qa.py` 嗰套。

  --sheet OUT     20x3 接觸表(棋盤格底,睇得到半透明同殘留)
  --check         邊緣殘留來源底色掃描(3% 門檻)
  --zoom id=OUT   某座塔三個 tier 放大
  --spells        改為驗魔法 icon
  --ground OUT    接地線 / 底座中心對齊圖(三個 tier 疊埋一齊睇跳唔跳位)
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.stdout.reconfigure(encoding="utf-8")

TOWER_STAGE = os.path.join(ROOT, "qa", "tower_cutout", "out")
SPELL_STAGE = os.path.join(ROOT, "qa", "magic_cutout", "out")
TIERS = ["", "_t2", "_t3"]


def checker(w, h, s=8, a=(90, 90, 96), b=(64, 64, 70)):
    im = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range(0, w, s):
            if ((x // s) + (y // s)) % 2:
                d.rectangle([x, y, x + s - 1, y + s - 1], fill=b)
    return im


def _path(d, kind, i, suf):
    return os.path.join(d, "%s_%d%s.png" % (kind, i, suf))


def contact(d, out, kind="tower", n=20, cell=170):
    W, H = cell * 3 + 4, cell * n + n + 1
    page = checker(W, H)
    dr = ImageDraw.Draw(page)
    for r in range(1, n + 1):
        for c, suf in enumerate(TIERS):
            p = _path(d, kind, r, suf)
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGBA")
            k = min((cell - 8) / im.width, (cell - 8) / im.height)
            im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))),
                           Image.LANCZOS)
            x = c * cell + (c + 1) + (cell - im.width) // 2
            y = (r - 1) * cell + r + (cell - im.height) // 2
            page.paste(im, (x, y), im)
        dr.text((4, (r - 1) * cell + r + 4), str(r), fill=(255, 240, 120))
    page.save(out)
    print("sheet ->", out)


def zoom(d, ident, out, kind="tower", cell=360):
    page = checker(cell * 3 + 4, cell + 2)
    for i, suf in enumerate(TIERS):
        im = Image.open(_path(d, kind, ident, suf)).convert("RGBA")
        k = min((cell - 8) / im.width, (cell - 8) / im.height)
        im = im.resize((int(im.width * k), int(im.height * k)), Image.NEAREST)
        x = i * cell + (i + 1) + (cell - im.width) // 2
        page.paste(im, (x, 1 + (cell - im.height) // 2), im)
    page.save(out)
    print("zoom ->", out)


def ground_chart(d, out, n=20, cell=150):
    """三個 tier 疊喺同一個坐標系入面 —— 接地線同底座中心對唔對得正,
    一眼睇得出。錯位嘅話三個 tier 嘅腳會散開。"""
    page = Image.new("RGB", (cell * 10 + 11, cell * 2 + 3), (26, 28, 32))
    dr = ImageDraw.Draw(page)
    for idx in range(1, n + 1):
        r, c = (idx - 1) // 10, (idx - 1) % 10
        ox, oy = c * cell + c + 1, r * cell + r + 1
        for i, (suf, col) in enumerate(zip(TIERS, [(255, 90, 90), (90, 255, 120),
                                                   (120, 170, 255)])):
            im = Image.open(_path(d, "tower", idx, suf)).convert("RGBA")
            a = np.asarray(im)[:, :, 3]
            k = (cell - 10) / 128.0
            ys, xs = np.nonzero(a > 100)
            if not len(ys):
                continue
            # 逐張畫佢嘅實心 bbox + 接地線,全部用同一個(畫布)坐標系
            x0, x1 = xs.min() - im.width / 2.0, xs.max() - im.width / 2.0
            dr.rectangle([ox + cell / 2 + x0 * k, oy + 5 + ys.min() * k,
                          ox + cell / 2 + x1 * k, oy + 5 + ys.max() * k],
                         outline=col)
            dr.line([ox + 4, oy + 5 + ys.max() * k, ox + cell - 4,
                     oy + 5 + ys.max() * k], fill=col)
        dr.line([ox + cell / 2, oy + 2, ox + cell / 2, oy + cell - 2],
                fill=(140, 140, 150))
        dr.text((ox + 4, oy + 2), str(idx), fill=(255, 240, 120))
    page.save(out)
    print("ground ->", out)


def _ray(rgb, bg, tmin=0.55, tmax=1.35):
    t = np.clip((rgb @ bg) / max(float(bg @ bg), 1e-6), tmin, tmax)
    return np.linalg.norm(rgb - t[:, None] * bg[None, :], axis=1)


def check(d, meta, kind="tower", n=20, limit=3.0):
    """量「仲有幾多粒實色邊緣像素似返來源底色」。門檻用返摳圖嗰個 d_hi ——
    低過佢嘅像素本來就應該被 key 走,仲留喺邊上就係漏網。"""
    rows, bad = [], 0
    for i in range(1, n + 1):
        m = meta.get(str(i), {})
        bg = np.array(m.get("bg", [4, 252, 4]), float)
        mode = m.get("mode", "green")
        d_hi = float(m.get("d_hi", 58))
        for suf in TIERS:
            p = _path(d, kind, i, suf)
            tname = "%d%s" % (i, suf or "_t1")
            if not os.path.exists(p):
                rows.append((tname, "MISSING", 0.0)); bad += 1; continue
            im = np.asarray(Image.open(p).convert("RGBA")).astype(float)
            a = im[:, :, 3]
            on = a > 16
            off = ~on
            nb = np.zeros_like(off)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nb |= np.roll(np.roll(off, dy, 0), dx, 1)
            edge = on & nb & (a > 128)
            if edge.sum() == 0:
                rows.append((tname, "EMPTY", 0.0)); bad += 1; continue
            px = im[:, :, :3][edge]
            dd = _ray(px, bg) if mode == "green" else np.linalg.norm(px - bg, axis=1)
            pct = 100.0 * (dd < d_hi).mean()
            ok = pct <= limit
            if not ok:
                bad += 1
            rows.append((tname, "ok" if ok else "FRINGE", pct))
    print("%-9s %-8s %9s" % ("item", "verdict", "bgfringe%"))
    for r in rows:
        print("%s%-9s %-8s %9.2f" % ("  " if r[1] == "ok" else "!!", *r))
    print("failures: %d / %d  (fail if >%.1f%% of opaque edge px fall inside the "
          "sheet's own key threshold)" % (bad, len(rows), limit))
    return bad


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="")
    ap.add_argument("--spells", action="store_true")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--zoom", default="")
    ap.add_argument("--ground", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    kind = "spell" if a.spells else "tower"
    n = 15 if a.spells else 20
    d = a.dir or (SPELL_STAGE if a.spells else TOWER_STAGE)
    rep = os.path.join(ROOT, "qa",
                       "magic_cutout" if a.spells else "tower_cutout", "report.json")
    meta = {}
    if os.path.exists(rep):
        with open(rep, encoding="utf-8") as f:
            meta = json.load(f).get("towers" if kind == "tower" else "spells", {})
    if a.sheet:
        contact(d, a.sheet, kind, n)
    if a.zoom:
        ident, out = a.zoom.split("=")
        zoom(d, int(ident), out, kind)
    if a.ground:
        ground_chart(d, a.ground, n)
    if a.check:
        sys.exit(1 if check(d, meta, kind, n) else 0)
