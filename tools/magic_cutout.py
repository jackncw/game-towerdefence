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
# 2026-08-07:四格全部補齊(見下面 SINGLES),清單清零。
MISSING = {}

# ---------------------------------------------------------------------------
# 單張 badge(第 21 輪補嘅四格)
# ---------------------------------------------------------------------------
# 同上面 15x3 嗰張 sheet **唔同管線**:呢四張係 1024x1024、一張一個完整 badge、
# 綠幕底。所以要摳綠(sheet 嗰邊唔使),但唔使切格、唔使剷 label,亦**唔可以
# 再疊 gen_art 嗰個程序階級框** —— 底板同銀 / 金框已經畫咗喺圖入面。
#
# 疊唔疊框呢個決定試過兩邊(qa/magic_cutout/frame_ab.png):疊上去會將畫好嘅
# 金色捲草角完全冚住,而且程序框係硬邊像素框,喺手繪 badge 上面好突兀;而
# 「階級讀得出」呢個功能painted 框本身已經做到(T1 淨色、T2 銀、T3 金,同其餘
# 41 張同一套色碼)。淨低嘅差異係底邊嗰排階級點 —— 由 `tier_pips()` 補返,
# 咁「數點」呢個 affordance 45 張都仲在。
SINGLES = {
    (10, 3): "龍捲風 T3.jfif",
    (11, 1): "地震術 T1.jfif",
    (11, 2): "地震術 T2.jfif",
    (12, 3): "烈焰之牆 T3.jfif",
}

# 綠幕 -> alpha 嘅兩條界(距離「t·bg 射線」嘅色距,見 round-19 嗰個陷阱 3)。
# 量出嚟:背景 d<6、badge 內部 d>200、過渡帶 8-12px(1024 尺度,縮到 64 之後
# 係 0.75px)。用射線唔用 RGB 距離,所以 badge 嘅投影(暗綠,t<1)會同底一齊
# 消失,唔會變一圈黑邊。
KEY_LO = 12.0
KEY_HI = 64.0


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


# ============================================================================
# 單張 badge 摳綠(第 21 輪)
# ============================================================================
def chroma_alpha(rgb):
    """綠幕 -> alpha。回傳 (alpha 0..1, 背景色)。

    唔用 RGB 距離,用「到 t·bg 射線嘅距離」—— badge 底下嗰浸投影係暗綠
    (同一條射線、t<1),RGB 距離會當佢係前景,留低一圈黑邊;射線距離會連佢
    一齊當背景。呢個係 round-19 摳怪物嗰陣執出嚟嘅同一條式。
    """
    corners = np.concatenate([rgb[:40, :40].reshape(-1, 3), rgb[:40, -40:].reshape(-1, 3),
                              rgb[-40:, :40].reshape(-1, 3), rgb[-40:, -40:].reshape(-1, 3)])
    bg = np.median(corners, axis=0)
    u = bg / np.linalg.norm(bg)
    n = np.linalg.norm(bg)
    t = np.clip(rgb @ u, 0.40 * n, 1.45 * n)
    d = np.linalg.norm(rgb - t[..., None] * u, axis=2)
    return np.clip((d - KEY_LO) / (KEY_HI - KEY_LO), 0.0, 1.0), bg


def drop_islands(a):
    """只留最大嗰嚿,其餘 alpha 清零。回傳 (alpha, 剷走咗嘅嚿 [(px, bbox)])。

    **呢步唔係潔癖,係四張圖都中招嗰個坑。** 右下角嗰粒 ✦ 浮水印係半透明**白**
    疊喺綠底上面 —— 佢仍然「好綠」(G−max(R,B) 有 160),所以用「夠唔夠綠」去
    摳係摳唔走佢嘅;但佢離開咗 t·bg 條射線(d≈102 > KEY_HI 64),所以 matting
    嗰條式反而俾佢 alpha=1.0。結果係:摳完 ✦ 唔單止仲喺度,仲會撐大 crop
    bbox,四張 icon 右下角全部有一粒螢光綠星。
    量過:✦ 同 badge 之間有 40px 以上嘅純背景,四張都係,所以「淨係留最大
    一嚿」就乾乾淨淨解決 —— 唔使用 round-20 嗰套「反解一個已知疊加層」
    (嗰套係因為浮水印貼實塔身,剷唔到;呢度剷得到)。
    """
    from scipy import ndimage as ndi
    lab, n = ndi.label(a > 0.5)
    if n <= 1:
        return a, []
    sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
    main = ndi.binary_fill_holes(lab == int(np.argmax(sizes)) + 1)
    # **唔可以逐嚿 island 各自 dilate 完清零。** JPEG 喺「黑描邊 vs 螢光綠」呢種
    # 高反差邊界會出色度 ringing,ringing 離開咗綠射線,所以會變成一堆貼住
    # badge 邊嘅 1-2px 幼絲 island。逐嚿 dilate 落去會連 badge 自己條邊一齊剷。
    # 改為「main 向外放 3px = near,near 以外一律清零」—— ✦ 離 badge 40px 以上,
    # 一定喺 near 以外;ringing 幼絲喺 near 以內,原樣保留(佢哋摳完之後由
    # decontaminate 補返 badge 色,而且 alpha 好細,睇唔到)。
    near = ndi.binary_dilation(main, np.ones((3, 3), bool), iterations=3)
    kill = (~near) & (a > 0.02)
    dropped = []
    klab, kn = ndi.label(a * (~near) > 0.5)
    for k in range(1, kn + 1):
        ys, xs = np.nonzero(klab == k)
        dropped.append((int(len(xs)),
                        [int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())]))
    out = a.copy()
    out[kill] = 0.0
    return out, dropped


def decontaminate(rgb, a, shrink=3):
    """剷走邊緣嘅綠色溢色。

    唔用教科書 matting 反解 —— round-19 量過,alpha 估唔準嗰陣細 alpha 一除
    就將綠爆大。改用「主體向內縮 shrink px 做 core,core 以外由最近嘅 core
    像素補色」。呢度 badge 邊緣係一條硬描邊,所以 core 收窄 3px 已經完全乾淨。
    """
    from scipy import ndimage as ndi
    core = a > 0.92
    core = ndi.binary_erosion(core, np.ones((3, 3), bool), iterations=shrink)
    idx = ndi.distance_transform_edt(~core, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


def resize_rgba(rgb, a, size):
    """縮圖。**一定要 premultiply** —— PIL 對 straight-alpha RGBA 做 LANCZOS
    會將透明像素嘅底色溝返入邊緣(round-19 陷阱 1,60 張中 58 張中招)。"""
    pm = Image.fromarray(np.clip(rgb * a[..., None], 0, 255).astype(np.uint8), "RGB")
    pm = pm.resize((size, size), Image.LANCZOS)
    am = Image.fromarray((a * 255).astype(np.uint8), "L").resize((size, size), Image.LANCZOS)
    p = np.asarray(pm).astype(float)
    av = np.asarray(am).astype(float) / 255.0
    out = np.zeros((size, size, 4), np.uint8)
    nz = av > 1.0 / 255.0
    rgbo = np.zeros_like(p)
    rgbo[nz] = np.clip(p[nz] / av[nz][:, None], 0, 255)
    out[..., :3] = rgbo.astype(np.uint8)
    out[..., 3] = (av * 255).astype(np.uint8)
    return out


def alpha_bleed(px):
    """把顏色填滿**成張圖**嘅透明區域(唔止一圈)。

    GPU 嘅 LINEAR filter 會照樣採樣到 alpha=0 嘅像素,佢哋帶乜色就會混乜色入
    邊緣。填滿而唔係「擴散兩圈」係因為呢啲 icon 出街之後最外圈仲會俾
    `magic_cutout` 自己個殘留檢查用 `.convert("RGB")` 讀 —— 留低原本嗰浸綠
    喺 alpha=0 底下,個檢查會報「最外兩圈有坑綠」,而嗰個報告係啱嘅:
    佢真係一浸綠,只不過而家睇唔到。
    """
    from scipy import ndimage as ndi
    rgb = px[..., :3].astype(float)
    a = px[..., 3].astype(float) / 255.0
    m = a > 0.02
    if not m.all() and m.any():
        idx = ndi.distance_transform_edt(~m, return_distances=False, return_indices=True)
        rgb = np.where(m[..., None], rgb, rgb[idx[0], idx[1]])
    out = px.copy()
    out[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    return out


def tier_pips(img, tier):
    """底邊嗰排階級點。

    Painted 框已經有 T1 淨色 / T2 銀 / T3 金,所以階級**讀得出**;但其餘 41 張
    仲有一排「數得到」嘅點,少咗呢四張就會喺 45 張入面自己一個樣。只補點,
    唔補框 —— 框會冚住畫好嘅捲草角。
    """
    if tier <= 1:
        return img
    s = img.size[0]
    rim = (208, 214, 222, 255) if tier == 2 else (240, 196, 72, 255)
    dark = tuple(int(v * 0.55) for v in rim[:3]) + (255,)
    light = tuple(min(255, int(v * 0.55 + 140)) for v in rim[:3]) + (255,)
    lay = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(lay)
    for k in range(tier):
        px = 0.5 + (k - (tier - 1) / 2.0) * 0.13
        d.ellipse([(px - 0.040) * s, (0.915 - 0.040) * s,
                   (px + 0.040) * s, (0.915 + 0.040) * s], fill=dark)
        d.ellipse([(px - 0.026) * s, (0.910 - 0.026) * s,
                   (px + 0.026) * s, (0.910 + 0.026) * s], fill=light)
    return Image.alpha_composite(img, lay)


def cut_single(path, tier, size=SIZE):
    """一張綠幕 badge -> 一張 size x size RGBA icon。回傳 (img, crop 尺寸, ✦ 記錄)"""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(float)
    a, _bg = chroma_alpha(rgb)
    a, dropped = drop_islands(a)
    ys, xs = np.nonzero(a > 0.5)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    # 剪成正方形:badge 本身就係方,但 JPEG 邊緣會差一兩 px,硬撐成方形先至
    # 保證 KEEP_ASPECT_CENTERED 之下同其餘 41 張一樣大。
    cy, cx = (y0 + y1) / 2.0, (x0 + x1) / 2.0
    h = max(y1 - y0, x1 - x0) / 2.0
    y0, y1 = int(round(cy - h)), int(round(cy + h))
    x0, x1 = int(round(cx - h)), int(round(cx + h))
    sub_rgb = rgb[y0:y1, x0:x1]
    sub_a = a[y0:y1, x0:x1]
    sub_rgb = decontaminate(sub_rgb, sub_a)
    px = resize_rgba(sub_rgb, sub_a, size)
    px = alpha_bleed(px)
    img = Image.fromarray(px, "RGBA")
    return tier_pips(img, tier), (x1 - x0, y1 - y0, x0, y0), dropped


def install_singles(dest, report):
    written = 0
    for (sid, tier), fname in sorted(SINGLES.items()):
        src = os.path.join(ROOT, "art_reference", "magic", fname)
        if not os.path.exists(src):
            raise SystemExit("搵唔到 %s" % src)
        img, box, dropped = cut_single(src, tier)
        suf = "" if tier == 1 else "_t%d" % tier
        img.save(os.path.join(dest, "spell_%d%s.png" % (sid, suf)))
        report["singles"]["%d_t%d" % (sid, tier)] = dict(
            src=fname, crop=[box[2], box[3], box[0], box[1]],
            dropped_islands=[dict(px=p, bbox=b) for p, b in dropped])
        written += 1
    return written


def check_singles(dest, report):
    """四項驗收,全部係「只會畫錯唔會報錯」嗰種,所以要逐項量:
      (a) 出街 icon 冇殘留來源底色(綠)—— **連 alpha=0 嗰啲都要驗**,因為
          GPU LINEAR 會採樣到佢哋;
      (b) ✦ 浮水印:確認佢真係俾 drop_islands 剷走咗,而且剷嗰嚿係喺右下角
          嘅細嚿(<3000px),唔係剷咗 badge 嘅一部分;
      (c) crop bbox 唔可以掂到源圖邊界(掂到即係摳穿咗,或者仲拉住浮水印);
      (d) alpha 邊界要收得乾淨(唔准成張圖都係半透明)。
    """
    bad = 0
    for (sid, tier), fname in sorted(SINGLES.items()):
        suf = "" if tier == 1 else "_t%d" % tier
        key = "%d_t%d" % (sid, tier)
        p = os.path.join(dest, "spell_%d%s.png" % (sid, suf))
        px = np.asarray(Image.open(p).convert("RGBA")).astype(float)
        rgb, al = px[..., :3], px[..., 3] / 255.0
        # (a) 殘留綠 —— 全圖,唔理 alpha
        ng = int(((rgb[..., 1] > 150) &
                  ((rgb[..., 1] - np.maximum(rgb[..., 0], rgb[..., 2])) > 60)).sum())
        # (b) 剷走咗嘅嚿
        isl = report["singles"][key]["dropped_islands"]
        big = [i for i in isl if i["px"] > 3000]
        wm = "; ".join("%dpx @%s" % (i["px"], i["bbox"]) for i in isl) or "none"
        # (c) crop 唔掂邊
        cx, cy, cw, ch = report["singles"][key]["crop"]
        edge = cx <= 1 or cy <= 1 or cx + cw >= 1023 or cy + ch >= 1023
        # (d) 半透明比例
        soft = float(((al > 0.05) & (al < 0.95)).mean())
        ok = ng == 0 and not big and not edge and 0 < soft < 0.16 and len(isl) >= 1
        bad += 0 if ok else 1
        print("  spell_%d t%d  crop %dx%d @(%d,%d)  殘綠 %d  剷走 %s  半透明 %.1f%%  %s"
              % (sid, tier, cw, ch, cx, cy, ng, wm, soft * 100,
                 "OK" if ok else "<< 有問題"))
    return bad


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
    report = {"spells": {}, "unused": {}, "missing": {}, "singles": {}}
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
    written += install_singles(dest, report)
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
    print("單張 badge(綠幕摳圖)驗收:")
    bad += check_singles(dest, report)
    print("residue check: %d 個問題" % bad)

    with open(os.path.join(QA, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("wrote %d / 45 icons -> %s" % (written, dest))
    print("待補 %d 格%s" % (len(MISSING), ":" if MISSING else " —— 清單清零"))
    for (sid, tier), v in sorted(MISSING.items()):
        print("   spell id=%d tier=%d  %s" % (sid, tier, v))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
