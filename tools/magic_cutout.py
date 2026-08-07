#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""magic_cutout.py — 由 art_reference/magic/magic.jfif(15x3 grid)切出魔法 icon。

同塔/怪物嗰兩條管線最大嘅分別:**呢張唔使摳圖**。每一格本身就係一塊有自己
底色(深綠 / 金 / 紅 / 藍 / 米)嘅方形 icon,鮮綠色只係格與格之間嘅坑。要做嘅
係「切啱格 + 剷走 baked-in 英文名 + 出返方形」,唔係去背。

三個唔可以靠估嘅嘢
──────────────────
1. **格位唔係規則格網。** 1024/15 = 68.27,但真正嘅格闊由 56 到 86 都有
   (FROST NOVA 嗰格闊 86)。硬切 68.27 會斬到隔籬格。所以格位係**量返出嚟**:
   喺每行嘅中間取一條橫切片,鮮綠(G>170 且 G−max(R,B)>90)嘅就係坑,
   坑與坑之間就係格。呢個門檻同時分得開「鮮綠坑」同「深綠格底」(G≈115)。
2. **文字帶喺格入面,唔係格外面。** 第 0 行嘅英文名寫喺格**上面**嘅綠坑度
   (切格就自然唔要),但第 1、2 行嘅名係印喺格**入面**最頂 —— 量出嚟係
   格頂起計 8 行(y 72..77 / 139..145)。唔剷嘅話出街係 icon 頂住住半行白字。
3. **格位對唔到魔法。** 呢張 sheet 有錯位:SUMMON MILITIA 有 6 格、
   TOXIC MIASMA 嘅 label 貼咗喺一個頭盔上面、EARTHQUAKE 嘅 label 貼咗喺一個
   龍捲風上面、TORNADO 得 2 格、EARTHQUAKE 得 1 格、WALL OF FLAME 得 2 格,
   仲有一格「冰柱噴發」掛住 HEAVEN'S WRATH 個名但邊個魔法都唔似。
   所以對號係**逐格讀圖 + 讀 label 之後人手寫死喺 GRID 表**,唔准靠格位算。
   對唔到嘅寧缺莫濫 —— 留返舊 icon,寫入待補清單。

輸出:64x64(源圖可用區約 56x54,所以係 1.14 倍,唔係放大空氣),
圓角 alpha 同現有 icon 一致,第二/三階疊返 gen_art 原本嗰個銀/金框
—— 戰鬥卡片冇位擺文字,階級一直都係靠嗰個框讀,唔可以淨低。
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_reference", "magic", "magic.jfif")
ASSETS = os.path.join(ROOT, "assets", "generated", "spells")
QA = os.path.join(ROOT, "qa", "magic_cutout")
STAGE = os.path.join(QA, "out")

sys.stdout.reconfigure(encoding="utf-8")

SIZE = 64
ROW_CORE = [(35, 55), (100, 122), (168, 190)]     # 一定落喺格入面嘅橫切片
ROW_BAND = [(4, 68), (70, 136), (138, 204)]       # 格喺邊個 y 範圍搵
# 格頂要剷幾多行 baked-in 文字。第 0 行嘅名寫喺格外面(綠坑上),所以係 0;
# 第 1、2 行印喺格入面,量到白字去到格頂起計第 8 行、黑描邊第 9 行,所以 11
# (留兩行安全邊)。用過 8 —— 冰凍新星第二階頂住一條黑色虛線,就係描邊嗰行。
LABEL_ROWS = [0, 11, 11]

# ---------------------------------------------------------------------------
# 對號表 —— (col, row) -> (spell id, tier)
# ---------------------------------------------------------------------------
# 逐格睇圖 + 讀 label 之後寫死。理由記喺 docs/reports 嗰份報告,同埋下面
# 每一行嘅註。冇上表嘅格 = 唔用(重複 / 對唔到),見 UNUSED。
GRID = {
    # meteor / stormbolt / freezenova / miasma —— label 同內容一致,行序即階序
    (0, 0): (1, 1), (0, 1): (1, 2), (0, 2): (1, 3),
    (1, 0): (2, 1), (1, 1): (2, 2), (1, 2): (2, 3),
    (2, 0): (3, 1), (2, 1): (3, 2), (2, 2): (3, 3),
    (3, 0): (4, 1), (3, 1): (4, 2), (3, 2): (4, 3),
    # 召喚民兵有 6 格候選(col 4 同 col 5 畫嘅係同一件事)。揀 col 5:
    # 三格同係金底,而且遞進最清楚 —— 劍+號角 -> 發光頭盔 -> 生翼頭盔。
    # col 5 第 2 行個 label 印住 "MIDAS TOUCH",但圖係生翼頭盔,以內容為準。
    (5, 0): (5, 1), (5, 1): (5, 2), (5, 2): (5, 3),
    (6, 0): (6, 1), (6, 1): (6, 2), (6, 2): (6, 3),
    (7, 0): (7, 1), (7, 1): (7, 2), (7, 2): (7, 3),
    (8, 0): (8, 1), (8, 1): (8, 2), (8, 2): (8, 3),
    (9, 0): (9, 1), (9, 1): (9, 2), (9, 2): (9, 3),
    # col 10 第 1 行個 label 印住 "EARTHQUAKE",但畫面正中央係一條龍捲風
    # 漏斗(地裂只係佢腳下嘅背景),以內容為準 -> 龍捲風第二階。
    (10, 0): (10, 1), (10, 1): (10, 2),
    # 淨返一格真.地裂(地面爆開 + 碎石 + 俾拋起嘅飛行怪),最終極,落第三階。
    (10, 2): (11, 3),
    (11, 0): (12, 1), (11, 1): (12, 2),
    (12, 0): (13, 1), (12, 1): (13, 2), (12, 2): (13, 3),
    (13, 0): (14, 1), (13, 1): (14, 2), (13, 2): (14, 3),
    (14, 0): (15, 1), (14, 1): (15, 2), (14, 2): (15, 3),
}

# 用唔着嘅格 + 點解
UNUSED = {
    (4, 0): "召喚民兵重複格(戰號 + 盾),col 5 嗰三格底色一致,揀咗嗰邊",
    (4, 1): "召喚民兵重複格(頭盔 + 青光環);label 印住 TOXIC MIASMA,錯配",
    (4, 2): "召喚民兵重複格(頭盔 + 金光爆)",
    (11, 2): "冰柱噴發;label 印住 HEAVEN'S WRATH 但圖係冰。烈焰之牆用唔到,"
             "冰凍新星自己三格已經齊而且藍底一致,呢格係橙底,夾硬用會突兀",
}

# 對唔到 icon、要留返舊圖嘅格(魔法 id, tier) -> 要 Jack 補乜
MISSING = {
    (10, 3): "龍捲風 第三階：一條吞掉整條路嘅巨型風暴柱，帶飛起嘅怪物剪影與雷光",
    (11, 1): "地震術 第一階：地面裂開一道細縫，幾粒碎石彈起，褐色土色調",
    (11, 2): "地震術 第二階：交錯的地裂網 + 隆起的岩板，塵霧揚起",
    (12, 3): "烈焰之牆 第三階：藍白色核心的地獄火牆，火舌沖天並帶火星漩渦",
}


# ============================================================================
# 切格
# ============================================================================
def tile_rects(rgb):
    """量返 15x3 個格嘅位置。回傳 {(col,row): (x0,y0,x1,y1)}(已經剷咗文字帶)"""
    H, W, _ = rgb.shape
    key = (rgb[:, :, 1] > 170) & (
        (rgb[:, :, 1] - np.maximum(rgb[:, :, 0], rgb[:, :, 2])) > 90)
    out = {}
    for r, ((c0, c1), (b0, b1)) in enumerate(zip(ROW_CORE, ROW_BAND)):
        gutter = key[c0:c1].mean(0) > 0.8
        runs, i = [], 0
        while i < W:
            if not gutter[i]:
                j = i
                while j < W and not gutter[j]:
                    j += 1
                if j - i >= 40:
                    runs.append((i, j))
                i = j
            else:
                i += 1
        if len(runs) != 15:
            raise SystemExit("row %d 切到 %d 格,唔係 15 —— 停低" % (r, len(runs)))
        ys = []
        for x0, x1 in runs:
            rows = [y for y in range(b0, b1) if (~key[y, x0:x1]).mean() > 0.97]
            ys.append((min(rows), max(rows) + 1))
        # 上下界取**中位數**,唔可以逐格各有各。長 label(LIGHTNING STORM、
        # HEAVEN'S WRATH)橫住寫過成格闊,嗰幾行對「非綠比例」嚟講一樣係
        # 「成行都唔係綠」,逐格量就會將個 label 帶當咗格頂,出街 icon 頂住
        # 半行白字。一行入面十五格本來就對齊,所以中位數就係真.格界。
        y0 = int(np.median([a for a, _ in ys])) + LABEL_ROWS[r]
        y1 = int(np.median([b for _, b in ys]))
        for c, (x0, x1) in enumerate(runs):
            out[(c, r)] = (x0, y0, x1, y1)
    return out


def square_pad(arr):
    """補成正方形 —— 用**邊緣複製**,唔用純色。

    格底係一浸暈影漸變,補純色會見到一條硬邊;複製邊緣就順住漸變延伸落去。
    唔剪係因為剪就會削走內容(FROST NOVA 嗰格闊 86,雪花畫到貼晒兩邊)。
    """
    h, w = arr.shape[:2]
    s = max(h, w)
    top, left = (s - h) // 2, (s - w) // 2
    return np.pad(arr, ((top, s - h - top), (left, s - w - left), (0, 0)), mode="edge")


def round_mask(size, inset=2, radius=10):
    """同 gen_art 嗰批 icon 一樣嘅圓角輪廓(inset 3%、圓角半徑 15.6%)。"""
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle(
        [inset, inset, size - 1 - inset, size - 1 - inset], radius=radius, fill=255)
    return m


def tier_frame(img, tier):
    """疊返 gen_art 嗰個銀 / 金階級框。

    唔可以慳呢步:戰鬥嘅魔法卡冇位擺一行字,玩家一直都係靠呢個框(加四粒角釘
    同底邊嘅點數)讀階級。新圖本身有遞進,但遞進係**跨圖**先睇得出,卡片上
    一次只見到一張。
    """
    if tier <= 1:
        return img
    s = img.size[0]
    rim = (208, 214, 222, 255) if tier == 2 else (240, 196, 72, 255)
    dark = tuple(int(v * 0.55) for v in rim[:3]) + (255,)
    light = tuple(min(255, int(v * 0.55 + 140)) for v in rim[:3]) + (255,)
    lay = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    d.rounded_rectangle([0.02 * s, 0.02 * s, 0.98 * s, 0.98 * s],
                        radius=0.17 * s, outline=dark, width=max(2, int(0.055 * s)))
    d.rounded_rectangle([0.035 * s, 0.035 * s, 0.965 * s, 0.965 * s],
                        radius=0.16 * s, outline=rim, width=max(2, int(0.030 * s)))
    for cx, cy in ((0.10, 0.10), (0.90, 0.10), (0.10, 0.90), (0.90, 0.90)):
        d.ellipse([(cx - 0.052) * s, (cy - 0.052) * s,
                   (cx + 0.052) * s, (cy + 0.052) * s], fill=dark)
        d.ellipse([(cx - 0.032) * s, (cy - 0.032) * s,
                   (cx + 0.032) * s, (cy + 0.032) * s], fill=light)
    if tier >= 3:
        for cx, cy in ((0.5, 0.045), (0.5, 0.955), (0.045, 0.5), (0.955, 0.5)):
            d.ellipse([(cx - 0.055) * s, (cy - 0.055) * s,
                       (cx + 0.055) * s, (cy + 0.055) * s], fill=dark)
            d.ellipse([(cx - 0.032) * s, (cy - 0.032) * s,
                       (cx + 0.032) * s, (cy + 0.032) * s], fill=(255, 255, 255, 255))
        d.rounded_rectangle([0.115 * s, 0.115 * s, 0.885 * s, 0.885 * s],
                            radius=0.11 * s, outline=light, width=max(1, int(0.014 * s)))
    for k in range(tier):
        px = 0.5 + (k - (tier - 1) / 2.0) * 0.13
        d.ellipse([(px - 0.040) * s, (0.915 - 0.040) * s,
                   (px + 0.040) * s, (0.915 + 0.040) * s], fill=dark)
        d.ellipse([(px - 0.026) * s, (0.910 - 0.026) * s,
                   (px + 0.026) * s, (0.910 + 0.026) * s], fill=light)
    return Image.alpha_composite(img, lay)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--measure", action="store_true")
    args = ap.parse_args()

    dest = ASSETS if args.install else STAGE
    os.makedirs(dest, exist_ok=True)
    os.makedirs(QA, exist_ok=True)

    rgb = np.asarray(Image.open(SRC).convert("RGB")).astype(np.float64)
    rects = tile_rects(rgb)
    if args.measure:
        for r in range(3):
            print("row %d: %s" % (r, " ".join(
                "%dx%d" % (rects[(c, r)][2] - rects[(c, r)][0],
                           rects[(c, r)][3] - rects[(c, r)][1]) for c in range(15))))
        return

    mask = round_mask(SIZE)
    report = {"spells": {}, "unused": {}, "missing": {}}
    written = 0
    for (c, r), (sid, tier) in sorted(GRID.items()):
        x0, y0, x1, y1 = rects[(c, r)]
        arr = np.asarray(Image.open(SRC).convert("RGB")).astype(np.uint8)[y0:y1, x0:x1]
        sq = Image.fromarray(square_pad(arr), "RGB").resize(
            (SIZE, SIZE), Image.LANCZOS).convert("RGBA")
        sq.putalpha(mask)
        sq = tier_frame(sq, tier)
        suf = "" if tier == 1 else "_t%d" % tier
        sq.save(os.path.join(dest, "spell_%d%s.png" % (sid, suf)))
        written += 1
        report["spells"]["%d_t%d" % (sid, tier)] = dict(
            cell=[c, r], src=[x1 - x0, y1 - y0])
    for k, v in UNUSED.items():
        report["unused"]["c%d_r%d" % k] = v
    for (sid, tier), v in MISSING.items():
        report["missing"]["%d_t%d" % (sid, tier)] = v
    # --- 驗收 -----------------------------------------------------------
    # (a) 零文字殘留。**唔可以**喺出街嘅 icon 上面用「一行入面幾段白色」去
    #     捉字 —— 試過,41 張報咗 8 張,全部係真.內容(天罰嘅白雲、龍捲風嘅
    #     風柱、召喚民兵嘅白光)。所以改為喺**源圖**度驗一條硬不變式:
    #     真.文字帶(白字 + 黑描邊)一定要完全喺剪走咗嗰段入面,而且留夠
    #     兩行安全邊。文字帶量法係「一行入面四段以上白色、橫跨過半格闊」,
    #     喺格頂 16 行入面搵 —— 呢個範圍入面除咗 label 冇第二樣嘢係咁。
    # (b) 零鮮綠坑殘留:切完之後最外兩圈唔准仲有坑嗰隻鮮綠。
    src = np.asarray(Image.open(SRC).convert("RGB")).astype(float)
    wh = (src.min(axis=2) > 170) & (np.ptp(src, axis=2) < 62)
    dk = src.max(axis=2) < 85
    bad = 0
    def texty(y, x0, x1):
        idx = np.nonzero(wh[y, x0:x1])[0]
        return (len(idx) >= 5 and 1 + int((np.diff(idx) > 1).sum()) >= 4
                and (idx.max() - idx.min()) > 0.50 * (x1 - x0))

    for r in range(3):
        y0 = rects[(0, r)][1]
        raw = y0 - LABEL_ROWS[r]          # 格頂(未剷文字)
        worst = -1e9
        for c in range(15):
            x0, _, x1, _ = rects[(c, r)]
            # 由格頂**向下數第一段連續**嘅字行 —— 只有 label 會由格頂起連住,
            # icon 內容(白雲 / 風柱 / 白光)一定係喺下面另起一段,所以呢個
            # 「第一段」條件就係區分 label 同內容嗰件事。搵唔到就當 -inf。
            run = None
            for y in range(raw - 12 if r == 0 else raw, raw + 14):
                if texty(y, x0, x1):
                    if run is None:
                        run = [y, y]
                    elif y - run[1] <= 1:
                        run[1] = y
                    else:
                        break
                elif run is not None and y - run[1] > 1:
                    break
            # label 一定由格頂數落嚟頭四行之內起(第 0 行嗰啲喺格外面,所以
            # 起點係負數)。起得低過咁就唔係 label,係 icon 內容 —— 第 2 行
            # 有三格根本冇 label(紫電、冰晶、金劍),唔加呢句佢哋嘅白色內容
            # 會當咗 label,報一個假嘅 y=151。
            if run is None or not (-12 <= run[0] - raw <= 4):
                continue
            end = run[1] + 1 if dk[run[1] + 1, x0:x1].sum() >= 6 else run[1]
            worst = max(worst, end)
        margin = y0 - worst - 1
        ok = margin >= 2
        bad += 0 if ok else 1
        print("  row %d: 格頂 y=%d,label 尾行 y=%d,裁切由 y=%d 起,"
              "safety margin %d 行 %s"
              % (r, raw, worst, y0, margin, "" if ok else "<< 唔夠"))
    for name in sorted(os.listdir(dest)):
        if not name.endswith(".png"):
            continue
        a = np.asarray(Image.open(os.path.join(dest, name)).convert("RGB")).astype(float)
        if a.shape[0] != SIZE:
            continue          # --install 之下同一個資料夾仲有四張 44px 舊 icon
        ring = np.zeros((SIZE, SIZE), bool)
        ring[2:4, 2:-2] = ring[-4:-2, 2:-2] = True
        ring[2:-2, 2:4] = ring[2:-2, -4:-2] = True
        green = ((a[:, :, 1] > 170) &
                 ((a[:, :, 1] - np.maximum(a[:, :, 0], a[:, :, 2])) > 90))[ring].sum()
        if green:
            bad += 1
            print("   !! %s 最外兩圈仲有 %d 粒坑綠" % (name, green))
    print("residue check: %d 個問題" % bad)

    with open(os.path.join(QA, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("wrote %d / 45 icons -> %s" % (written, dest))
    print("待補 %d 格:" % len(MISSING))
    for (sid, tier), v in sorted(MISSING.items()):
        print("   spell id=%d tier=%d  %s" % (sid, tier, v))


if __name__ == "__main__":
    sys.exit(main())
