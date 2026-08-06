#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""monster_qa.py — 摳圖驗收:接觸表 + 綠/灰邊 checker。

  --dir     睇邊個資料夾(預設 staging)
  --sheet   出接觸表(棋盤格底,睇得到半透明同殘留)
  --check   自動邊緣掃描,report 綠/灰 fringe
  --zoom F  某一族放大逐格睇
"""
import argparse, os, sys, json
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAMS = ["goblin", "wolf", "skeleton", "golem", "ghost",
        "bat", "treant", "beetle", "cultist", "slime"]
LEVELS = ["1", "2", "3", "4", "5", "boss"]


def checker(w, h, s=8, a=(90, 90, 96), b=(64, 64, 70)):
    im = Image.new("RGB", (w, h), a)
    px = im.load()
    for y in range(h):
        for x in range(w):
            if ((x // s) + (y // s)) % 2:
                px[x, y] = b
    return im


def contact(d, out, cell=150, bgmode="checker"):
    W, H = cell * 6 + 7, cell * 10 + 11
    page = checker(W, H) if bgmode == "checker" else Image.new("RGB", (W, H), (30, 32, 36))
    for r, fam in enumerate(FAMS):
        for c, lv in enumerate(LEVELS):
            p = os.path.join(d, "%s_%s.png" % (fam, lv))
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGBA")
            k = min((cell - 6) / im.width, (cell - 6) / im.height)
            im = im.resize((max(1, int(im.width * k)), max(1, int(im.height * k))), Image.LANCZOS)
            x = c * cell + (c + 1) + (cell - im.width) // 2
            y = r * cell + (r + 1) + (cell - im.height) // 2
            page.paste(im, (x, y), im)
    page.save(out)
    print("sheet ->", out)


def zoom(d, fam, out, cell=300):
    page = checker(cell * 3 + 4, cell * 2 + 3)
    for i, lv in enumerate(LEVELS):
        p = os.path.join(d, "%s_%s.png" % (fam, lv))
        im = Image.open(p).convert("RGBA")
        k = min((cell - 8) / im.width, (cell - 8) / im.height)
        im = im.resize((int(im.width * k), int(im.height * k)), Image.NEAREST)
        x = (i % 3) * cell + (i % 3) + (cell - im.width) // 2
        y = (i // 3) * cell + (i // 3) + (cell - im.height) // 2
        page.paste(im, (x, y), im)
    page.save(out)
    print("zoom ->", out)


def _bg_colors():
    """逐族嘅來源底色。由 monster_cutout 嘅 report.json 攞,唔另外 hardcode。"""
    p = os.path.join(ROOT, "qa", "monster_cutout", "report.json")
    if not os.path.exists(p):
        return {}
    with open(p, encoding="utf-8") as f:
        r = json.load(f)
    return {k: (np.array(v["bg"], float), v.get("mode", "green"), float(v.get("d_hi", 50)))
            for k, v in r.items() if v.get("bg")}


def _ray_dist(rgb, bg, tmin=0.55, tmax=1.35):
    t = np.clip((rgb @ bg) / max(float(bg @ bg), 1e-6), tmin, tmax)
    return np.linalg.norm(rgb - t[:, None] * bg[None, :], axis=1)


def check(d, limit=3.0):
    """邊緣像素掃描:量「仲有幾多粒邊緣像素似返來源底色」。

    唔可以用「有冇綠」去判 —— 史萊姆成隻綠、treant 有綠葉、cultist 有綠法陣、
    狼 lv5 有綠火,一律會誤報(第一版就係咁,slime 報 100% 綠邊)。真正要捉嘅
    係**殘留底色**,所以拎返 monster_cutout 記低嗰張 sheet 嘅底色,用同一條射線
    距離去量:d < 44 就當佢係摳唔乾淨。
    """
    bgs = _bg_colors()
    rows, bad = [], 0
    for fam in FAMS:
        bg, mode, d_hi = bgs.get(fam, (None, "green", 50.0))
        for lv in LEVELS:
            p = os.path.join(d, "%s_%s.png" % (fam, lv))
            if not os.path.exists(p):
                rows.append((fam, lv, "MISSING", 0.0)); bad += 1; continue
            im = np.asarray(Image.open(p).convert("RGBA")).astype(float)
            a = im[:, :, 3]
            on = a > 16
            off = ~on
            nb = np.zeros_like(off)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nb |= np.roll(np.roll(off, dy, 0), dx, 1)
            edge = on & nb & (a > 128)          # 只計實色邊,唔計柔光暈
            if edge.sum() == 0:
                rows.append((fam, lv, "EMPTY", 0.0)); bad += 1; continue
            if bg is None:
                rows.append((fam, lv, "no-bg", 0.0)); continue
            px = im[:, :, :3][edge]
            # 綠幕張數用射線距離(影同底同色相,只係暗咗);灰底張數要用平面
            # 距離 —— 灰底嘅射線會掃埋成條由黑到白嘅灰階,連隻白色幽靈都當底色。
            dd = _ray_dist(px, bg) if mode == "green" else np.linalg.norm(px - bg, axis=1)
            # 門檻就係摳圖用嗰個 d_hi:低過佢嘅像素本來就應該被 key 走,
            # 仲留喺邊上就係漏網。灰底 d_hi=16,綠底 58 —— 一條規則兩張都啱。
            pct = 100.0 * (dd < d_hi).mean()
            ok = pct <= limit
            if not ok:
                bad += 1
            rows.append((fam, lv, "ok" if ok else "FRINGE", pct))
    print("%-9s %-5s %-8s %8s" % ("family", "lv", "verdict", "bgfringe%"))
    for r in rows:
        print("%s%-9s %-5s %-8s %8.2f" % ("  " if r[2] == "ok" else "!!", *r))
    print("failures: %d / %d  (fail if >%.1f%% of opaque edge px fall inside the sheet's own key threshold)"
          % (bad, len(rows), limit))
    return bad


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(ROOT, "qa", "monster_cutout", "out"))
    ap.add_argument("--sheet", default="")
    ap.add_argument("--zoom", default="")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.sheet:
        contact(a.dir, a.sheet)
    if a.zoom:
        fam, out = a.zoom.split("=")
        zoom(a.dir, fam, out)
    if a.check:
        sys.exit(1 if check(a.dir) else 0)
