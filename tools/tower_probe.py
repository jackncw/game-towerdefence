#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tower_probe.py — 開工前量度 art_reference/tower 嘅 20 張 sheet。

唔改任何嘢,淨係報:邊框底色集合、格線位、有冇 baked-in 文字帶、
以及每格主體 / 石底座嘅位置,好等 tower_cutout.py 嘅參數有數據支撐。
"""
from __future__ import annotations

import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_reference", "tower")

sys.stdout.reconfigure(encoding="utf-8")


def sample_border(rgb, band=4, minfrac=0.010):
    h, w, _ = rgb.shape
    b = np.concatenate([
        rgb[0:band].reshape(-1, 3), rgb[h - band:h].reshape(-1, 3),
        rgb[:, 0:band].reshape(-1, 3), rgb[:, w - band:w].reshape(-1, 3)])
    q = (b // 8 * 8 + 4)
    uniq, cnt = np.unique(q, axis=0, return_counts=True)
    order = np.argsort(-cnt)
    total = float(len(b))
    return [(uniq[i].astype(int).tolist(), cnt[i] / total) for i in order[:6]
            if cnt[i] / total >= minfrac]


def main():
    for fname in sorted(os.listdir(SRC)):
        im = Image.open(os.path.join(SRC, fname)).convert("RGB")
        rgb = np.asarray(im).astype(np.float64)
        h, w, _ = rgb.shape
        cols = sample_border(rgb)
        # 「近白」像素分佈 —— baked-in 文字係白色粗體,佢會喺底部堆成一條帶
        white = (rgb.min(axis=2) > 195) & (np.ptp(rgb, axis=2) < 40)
        rowsw = white.sum(1)
        band = np.nonzero(rowsw > w * 0.012)[0]
        txt = ""
        if len(band) and band.min() > 0.60 * h:
            txt = "text_band y=%d..%d (%.3f..%.3f)" % (
                band.min(), band.max(), band.min() / h, band.max() / h)
        print("%-16s %dx%d" % (fname, w, h))
        print("   border:", " ".join("%s:%.3f" % (c, f) for c, f in cols))
        if txt:
            print("   " + txt)
        elif white.sum() > 0:
            print("   white px %d (rows %s)" % (
                white.sum(), (band.min(), band.max()) if len(band) else "-"))


if __name__ == "__main__":
    main()
