#!/usr/bin/env python3
"""改造前後截圖嘅逐像素對比。

用法:  python tools/shot_diff.py <before_dir> <after_dir> [out_dir]

每一對圖出三個數:
  diff%   有幾多百分比嘅像素唔完全一樣
  mean    平均 RGB 差(0-255),即係「差幾多」而唔係「有幾多處差」
  max     最大單通道差

點解要三個數:一個 sub-pixel 嘅抗鋸齒差會令 diff% 好高但 mean 好細(例如
99% 像素差咗 1),而一個真正嘅走樣係 diff% 細但 max 頂天(一嚿嘢唔見咗)。
淨睇其中一個都會得出錯嘅結論。

有差異嘅會出一張 before | after | diff(放大 8 倍)嘅並排圖。
"""
import os
import sys
from PIL import Image, ImageChops


def main():
    bdir, adir = sys.argv[1], sys.argv[2]
    out = sys.argv[3] if len(sys.argv) > 3 else os.path.join(adir, "..", "diff")
    os.makedirs(out, exist_ok=True)
    names = sorted(n for n in os.listdir(bdir) if n.endswith(".png"))
    print("%-20s %8s %8s %6s" % ("shot", "diff%", "mean", "max"))
    rows = []
    for n in names:
        pb, pa = os.path.join(bdir, n), os.path.join(adir, n)
        if not os.path.exists(pa):
            print("%-20s  MISSING AFTER" % n)
            continue
        a = Image.open(pb).convert("RGB")
        b = Image.open(pa).convert("RGB")
        if a.size != b.size:
            print("%-20s  SIZE %s vs %s" % (n, a.size, b.size))
            continue
        d = ImageChops.difference(a, b)
        bbox = d.getbbox()
        px = a.width * a.height
        gray = d.convert("L")
        hist = gray.histogram()
        nz = px - hist[0]
        total = sum(i * c for i, c in enumerate(hist))
        mean = total / float(px)
        mx = max(i for i, c in enumerate(hist) if c) if nz else 0
        rows.append((n, 100.0 * nz / px, mean, mx))
        print("%-20s %8.3f %8.3f %6d" % (n, 100.0 * nz / px, mean, mx))
        if bbox is not None:
            # 並排:before | after | diff(放大對比度)
            amp = d.point(lambda v: min(255, v * 8))
            sheet = Image.new("RGB", (a.width * 3, a.height), (0, 0, 0))
            sheet.paste(a, (0, 0))
            sheet.paste(b, (a.width, 0))
            sheet.paste(amp, (a.width * 2, 0))
            sheet.thumbnail((1620, 960), Image.LANCZOS)
            sheet.save(os.path.join(out, n))
    ident = [r for r in rows if r[1] == 0.0]
    print("\n完全一樣: %d / %d" % (len(ident), len(rows)))
    worst = sorted(rows, key=lambda r: -r[2])[:6]
    print("平均差最大嘅六張:")
    for n, d, m, mx in worst:
        print("  %-20s diff%%=%.3f mean=%.3f max=%d" % (n, d, m, mx))


if __name__ == "__main__":
    main()
