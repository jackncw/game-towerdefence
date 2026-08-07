#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""tower_cutout.py — 由 art_reference/tower/*.jfif 嘅 20 張 3 格 sheet 摳出
60 張有 alpha 嘅塔 PNG(20 座 × t1/t2/t3)。

第 19 輪 `monster_cutout.py` 嗰套照搬:邊框眾數底色集合、射線距離、
兩層 flood fill、由內向外補色 de-spill、premultiplied resize + alpha bleed。
下面淨係記**塔專屬**嗰幾樣同怪物唔同嘅嘢。

塔同怪物三個真正嘅分別
──────────────────────
1. **主體判定要放寬。** 塔嘅賣點好多都係發光元素:光束塔嘅稜鏡射線、聖光塔
   嘅光柱同日冕、傳送塔嘅星空門、磁力塔嘅電弧、鍊金塔嘅法陣。呢啲嘢喺
   alpha 上面係半透明,喺 round-19 嘅窄 d_soft(d_hi+16)之下會俾一刀切走。
   所以塔全部行**闊 d_soft**(ghost 嗰單放寬嘅同一個做法),再靠 ramp 淡出。
2. **衛星保留要加距離條件。** 每張 sheet 第三格右下角都有一粒裝飾用嘅四角
   星(✦)—— 佢喺主體 bbox 外擴 20% 嘅框入面,round-19 條規則會照撈埋,
   出街係塔嘅右下角浮住一粒無端端嘅星。真正要保嘅衛星(折射光線、日冕、
   碎片渦、蒸氣、彈殼)全部**貼住**主體,所以加一條「離主體 ≤ 30px」。
3. **錨點係接地點,唔係面積。** 怪物按視覺體積縮放;塔唔得 —— 塔要坐正一個
   建塔格,而三個 tier 嘅接地點要一模一樣,否則進化嗰下會跳位。所以
   **全部 60 張共用同一個縮放倍率**(源圖 20 張 sheet 用同一個格距同同一個
   石底座模板,所以相對大細本身就係啱嘅,郁佢反而係改美術),擺位就
   「石底座底邊 → 固定 y、石底座水平中心 → 固定 x」。

尺寸(同 GameData.TOWER_RENDER 綁死,改一個要改埋另一個)
──────────────────────────────────────────────
  PNG 128x128、`TOWER_RENDER = 88/128 = 0.6875` → 畫面上仍然係 88px,
  同舊圖一模一樣。源圖每格主體約 300x280,所以 128 係**真.縮細**,
  唔係放大空氣;而 camera 最大 zoom 2.0 之下畫面去到 176px,128 嘅
  oversample 啱啱夠。舊嘅 44px 源圖喺 zoom 2.0 之下係 4 倍放大,今輪就係
  要修呢樣。

  接地線 y=125 / 128 = 舊圖嘅 43 / 44 —— 舊 60 張 tower PNG **全部**
  實心像素底邊都喺 y=43(量過,60/60),所以照抄呢個數就等於射程圈、
  選中光圈、ghost 預覽、詛咒符文、聖光光柱全部一步都唔使郁。

用法:
  python tools/tower_cutout.py --measure     # 只量度,唔寫檔
  python tools/tower_cutout.py --debug       # 出 staging + alpha QA 圖
  python tools/tower_cutout.py --install     # 寫入 assets/generated/towers
"""
from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art_reference", "tower")
ASSETS = os.path.join(ROOT, "assets", "generated", "towers")
QA = os.path.join(ROOT, "qa", "tower_cutout")
STAGE = os.path.join(QA, "out")

sys.stdout.reconfigure(encoding="utf-8")

# --- 目標尺寸 ---------------------------------------------------------------
CANVAS = 128
GROUND_Y = 125          # 43/44 x 128 —— 舊 60 張 PNG 嘅接地線
TIERS = ["", "_t2", "_t3"]

# 全部 60 張共用嘅源圖 -> 畫布倍率。由 --measure 量返出嚟(最高嗰張啱啱好
# 填滿 128 - 上邊留白),寫死喺度先至可以「跑幾多次都一樣」。
GLOBAL_K = 0.0          # 0 = 由 --measure 即場計

# --- 逐張 sheet -------------------------------------------------------------
# 檔名 -> (tower id, 設定)。id 就係 GameData.TOWERS 嗰廿個。
# mode "green" = 綠幕(射線距離);"flat" = 平色底(RGB 距離)+ 順手清埋綠邊條
SHEETS = {
    "箭塔.jfif":       dict(tid=1,  mode="green", d_hi=58, glow="warm"),
    "加農砲台.jfif":    dict(tid=2,  mode="green", d_hi=58),
    "雷電塔.jfif":     dict(tid=3,  mode="green", d_hi=58, glow="warm"),
    "火球塔.jfif":     dict(tid=4,  mode="green", d_hi=58),
    # 冰霜塔張底係淺灰綠 #C9DBC5,格與格之間係鮮綠線,同 round-19 隻 ghost
    # 一模一樣。冰係「幾乎白」,所以門檻要低。
    "冰霜塔.jfif":     dict(tid=5,  mode="flat",  d_hi=18, d_soft=40),
    # 毒液塔成座都係綠 —— 綠藥水、綠苔、綠光球。射線距離之下佢哋離底色
    # 140+,唔受影響(round-19 史萊姆同一件事)。
    "毒液塔.jfif":     dict(tid=6,  mode="green", d_hi=56),
    "狙擊塔.jfif":     dict(tid=7,  mode="green", d_hi=58),
    "機槍塔.jfif":     dict(tid=8,  mode="green", d_hi=58),
    "迫擊砲.jfif":     dict(tid=9,  mode="green", d_hi=58),
    "光束塔.jfif":     dict(tid=10, mode="green", d_hi=56, d_soft=132),
    "緩速力場塔.jfif":  dict(tid=11, mode="green", d_hi=56, d_soft=120),
    "鍊金塔.jfif":     dict(tid=12, mode="green", d_hi=58, d_soft=120, glow="warm"),
    "兵營塔.jfif":     dict(tid=13, mode="green", d_hi=58, glow="warm"),
    "迴旋鏢塔.jfif":    dict(tid=14, mode="green", d_hi=58, d_soft=120, glow="warm"),
    # 荊棘塔:藤同葉都係綠。同毒液塔一樣靠射線距離。
    "荊棘塔.jfif":     dict(tid=15, mode="green", d_hi=56),
    # 導彈塔:黑色外框 + 黑色格線 + 底部 baked-in 英文名。文字量出嚟係
    # y=292..314(格高 338),289 以下冇塔身,所以界線落 0.855。
    "導彈塔.jfif":     dict(tid=16, mode="green", d_hi=58, text_band=(0.855, 1.0), glow="warm"),
    "詛咒塔.jfif":     dict(tid=17, mode="green", d_hi=56, d_soft=124),
    "聖光塔.jfif":     dict(tid=18, mode="green", d_hi=56, d_soft=140, glow="warm"),
    "磁力塔.jfif":     dict(tid=19, mode="green", d_hi=56, d_soft=128, glow="warm"),
    "傳送塔.jfif":     dict(tid=20, mode="green", d_hi=56, d_soft=124),
}


# ============================================================================
# 底色 / 距離場(round-19 原樣)
# ============================================================================
def sample_bg(rgb, mode):
    h, w, _ = rgb.shape
    b = np.concatenate([
        rgb[0:4].reshape(-1, 3), rgb[h - 4:h].reshape(-1, 3),
        rgb[:, 0:4].reshape(-1, 3), rgb[:, w - 4:w].reshape(-1, 3)])
    q = (b // 8 * 8 + 4)
    uniq, cnt = np.unique(q, axis=0, return_counts=True)
    order = np.argsort(-cnt)
    top = [(uniq[i].astype(float), int(cnt[i])) for i in order[:8]]
    total = float(len(b))

    def greenish(c):
        return c[1] - max(c[0], c[2]) > 60

    if mode == "green":
        greens = [c for c, n in top if greenish(c) and n / total > 0.012]
        if greens:
            return greens[0], greens[1:]
        return top[0][0], []
    main = None
    for c, _n in top:
        if not greenish(c):
            main = c
            break
    if main is None:
        main = top[0][0]
    extras = [c for c, n in top if greenish(c) and n / total > 0.02]
    return main, extras


def dist_ray(rgb, bg, tmin=0.55, tmax=1.35):
    bb = float(np.dot(bg, bg))
    t = np.clip((rgb @ bg) / max(bb, 1e-6), tmin, tmax)
    return np.linalg.norm(rgb - t[..., None] * bg[None, None, :], axis=2)


def dist_segment(rgb, a, b):
    ab = b - a
    denom = float(np.dot(ab, ab))
    s = np.clip(((rgb - a) @ ab) / max(denom, 1e-6), 0.0, 1.0)
    return np.linalg.norm(
        rgb - (a[None, None, :] + s[..., None] * ab[None, None, :]), axis=2)


def build_distance(rgb, cfg):
    bg, extras = sample_bg(rgb, cfg["mode"])
    if cfg["mode"] == "green":
        d = dist_ray(rgb, bg)
    else:
        d = np.linalg.norm(rgb - bg[None, None, :], axis=2)
    for ex in extras:
        d = np.minimum(d, dist_ray(rgb, ex))
        if cfg["mode"] == "flat":
            d = np.minimum(d, dist_segment(rgb, bg, ex))
    return d, bg


# ============================================================================
# 格線 / 外框
# ============================================================================
def kill_frame_lines(alpha, cells=3, max_w=7, cover=0.94, tol=0.05):
    """剷格線同外框。

    同 round-19 一樣,「幼 + 貫通」之外一定要有第三個條件,否則會斬開高過
    九成格高嘅塔(聖光塔 t3 光柱貫通成格、狙擊塔 t3 嘅雷射線)。第三個條件
    有兩款:坐喺格界位(k·W/3 ±5%),或者坐喺**圖邊**——導彈塔嗰張成張
    sheet 有一圈黑色外框,唔剷嘅話 flood fill 由邊界入唔到去,成格會變實心。
    """
    H, W = alpha.shape
    on = alpha > 0.5
    killed = np.zeros_like(on)
    ideal_x = [k * W / float(cells) for k in range(1, cells)]

    def runs(hot, limit):
        out, i = [], 0
        while i < limit:
            if not hot[i]:
                i += 1
                continue
            j = i
            while j < limit and hot[j]:
                j += 1
            out.append((i, j))
            i = j
        return out

    for a, b in runs(on.sum(0) / float(H) > cover, W):
        if b - a > max_w:
            continue
        c = (a + b) * 0.5
        at_edge = a <= 0.015 * W or b >= 0.985 * W
        if at_edge or min(abs(c - ix) for ix in ideal_x) <= tol * W:
            killed[:, a:b] = True
    for a, b in runs(on.sum(1) / float(W) > 0.94, H):
        if b - a <= max_w and (b < 0.06 * H or a > 0.94 * H):
            killed[a:b, :] = True
    out = alpha.copy()
    out[killed] = 0.0
    return out, killed


def split_cells(alpha, W, expect=3):
    col = (alpha > 0.25).sum(0)
    gap = col <= 1
    runs = []
    i = 0
    while i < W:
        if gap[i]:
            j = i
            while j < W and gap[j]:
                j += 1
            runs.append((i, j))
            i = j
        else:
            i += 1
    step = W / float(expect)
    bounds = [0]
    for k in range(1, expect):
        ideal = k * step
        cands = [r for r in runs if abs((r[0] + r[1]) * 0.5 - ideal) < 0.30 * step
                 and r[0] > 2 and r[1] < W - 2]
        if cands:
            best = max(cands, key=lambda r: r[1] - r[0])
            bounds.append((best[0] + best[1]) // 2)
        else:
            bounds.append(int(round(ideal)))
    bounds.append(W)
    return list(zip(bounds[:-1], bounds[1:]))


# ============================================================================
# 主流程
# ============================================================================
def _fill_from_border(passable):
    lbl, _ = ndimage.label(passable)
    edge = np.concatenate([lbl[0, :], lbl[-1, :], lbl[:, 0], lbl[:, -1]])
    return np.isin(lbl, np.unique(edge[edge > 0]))


# ============================================================================
# 第三格右下角嗰粒裝飾星 ✦
# ============================================================================
# 20 張 sheet **每一張**嘅第三格右下角都有同一粒半透明白色四角星,位置、
# 形狀、濃度一模一樣(量過:x 944..968 / y 257..282,峰值覆蓋率 0.32)。
# 佢係 sheet 嘅裝飾,唔係塔嘅一部分。
#
# 唔可以當佢係一嚿嘢剷走:五張 sheet 佢係實實貼住塔身(加農砲台 93%、
# 迫擊砲 79%、荊棘塔 79% 嘅框都俾塔身佔咗),連住主體,一 label 就同塔
# 黐埋一嚿。亦都唔可以靠顏色 key:佢係「白 × 綠」嘅混合,同聖光塔嘅光柱、
# 兵營塔嘅聖光十字喺色域上面分唔開。
#
# 所以反過嚟做:佢係一個**已知嘅疊加層**,咁就把佢反解出嚟。喺五張「框入面
# 淨係得粒星」嘅 sheet 上面量出覆蓋率 s(x,y),之後對每張 sheet 做
# C_orig = (C − s·White)/(1−s)。星喺綠底上面就還原返做綠底(跟住畀正常
# key 剷走),星喺石底座上面就還原返做石(嗰度佢本來就係一道白光斑)。
WM_BOX = (934, 247, 978, 292)
_WM = None


def watermark():
    global _WM
    if _WM is None:
        p = os.path.join(ROOT, "tools", "tower_watermark.npy")
        _WM = np.load(p).astype(np.float64) if os.path.exists(p) else None
    return _WM


def remove_watermark(rgb):
    s = watermark()
    if s is None:
        return rgb
    x0, y0, x1, y1 = WM_BOX
    box = rgb[y0:y1, x0:x1].astype(np.float64)
    s3 = np.clip(s, 0.0, 0.90)[..., None]
    out = (box - s3 * 255.0) / (1.0 - s3)
    rgb = rgb.copy()
    rgb[y0:y1, x0:x1] = np.clip(out, 0, 255)
    return rgb


def unmix_soft(rgb, alpha, bg, a_min=0.35):
    """柔光帶嘅反解 —— C = a·F + (1−a)·B  ->  F = (C − (1−a)B)/a。

    round-19 講過教科書 matting **喺實色邊緣**唔work(alpha 估唔準,細 alpha
    一除就將綠爆大),所以嗰度一直用「由內向外補色」。但柔光帶係另一件事:
    嗰度冇 core 可以補,而唔補嘅話出街係一撻**綠色**光暈 —— 鍊金塔 t3 嘅
    金色符文圈、兵營塔 t3 嘅聖光十字、迴旋鏢塔 t3 嘅氣旋、雷電塔 t3 嘅雲,
    源圖全部係金 / 白,摳完全部變咗螢光綠(睇過就知係硬傷)。

    分母鎖底 a_min 就係 round-19 嗰個爆綠問題嘅答案:a 細過 0.35 就用 0.35
    除,結果係「校得唔夠盡」(仲有少少灰)而唔係「校爆」。淡到 a<0.35 嘅
    像素本身就唔顯眼,寧願淡啲都唔好爆。
    """
    band = (alpha > 0.02) & (alpha < 0.98)
    if not band.any():
        return rgb
    a = np.clip(alpha[band], 0.0, 1.0)[:, None]
    div = np.maximum(a, a_min)
    out = rgb.copy()
    out[band] = np.clip((rgb[band] - (1.0 - a) * bg[None, :]) / div, 0, 255)

    # --- 殘綠守門 --------------------------------------------------------
    # alpha 係由距離場斜坡估出嚟嘅,唔係真.覆蓋率,所以反解校得唔盡 ——
    # 聖光塔 t3 條光柱同兵營塔 t3 個聖光十字校完仲有一圈綠。
    #
    # 但係「柔光帶唔准綠」呢條規唔可以一刀切:毒液塔嘅綠魔力光、荊棘塔嘅
    # 綠氣、光束塔 t2 嗰道彩虹射線入面條綠光,全部係**真.綠**。分辨方法係
    # 睇最近嗰粒**實色**像素:實色係綠(綠球 / 綠葉)就由得佢綠,實色係白
    # 石 / 金 / 雲就話明呢撻光暈本來唔係綠,壓返落去。
    solid = alpha > 0.9
    if solid.any() and not solid.all():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        core = out[iy, ix]
        core_green = core[:, :, 1] > np.maximum(core[:, :, 0], core[:, :, 2]) + 20
        cap = np.maximum(out[:, :, 0], out[:, :, 2]) + 25.0
        fix = band & ~core_green & (out[:, :, 1] > cap)
        out[:, :, 1] = np.where(fix, cap, out[:, :, 1])
    return out


def unmix_greenness(rgb, alpha, bg):
    """「綠度」反解 —— 淨係喺 `glow="warm"` 嘅 sheet 度行。

    上面條 matting 用距離場斜坡當 alpha,而**光**呢樣嘢佢估唔準:一撻白光
    溝五成綠底出嚟係 (156,218,85),距離底色 173,遠過 d_soft,所以佢當咗
    「實色」,連住嗰浸綠一齊出街(聖光塔 t3 條光柱、磁力塔嘅環、迴旋鏢塔
    嘅氣旋、兵營塔 t3 個聖光十字,全部一樣)。

    綠幕業界嗰條標準式先啱:前景本身冇綠度,所以像素剩低幾多綠度就等於
    底色仲佔幾多。  r = (G − max(R,B)) / (Bg 嘅同一個數),F = (C − r·B)/(1−r)。

    點解要逐張開關,唔一刀切全部行:呢條式**假設咗前景冇綠**。史萊姆咁樣
    嘅真.綠主體一行就變灰(毒液塔嘅綠藥水 r=0.65,一反解變中灰)。所以
    只准用喺色板入面根本冇綠嗰八張。青 / 藍綠唔使驚 —— (80,200,210) 嘅
    綠度係 −10,條式當佢完全乾淨。
    """
    gb = float(bg[1] - max(bg[0], bg[2]))
    if gb <= 1.0:
        return rgb
    m = alpha > 0.02
    if not m.any():
        return rgb
    c = rgb[m]
    r = np.clip((c[:, 1] - np.maximum(c[:, 0], c[:, 2])) / gb, 0.0, 0.85)[:, None]
    out = rgb.copy()
    out[m] = np.clip((c - r * bg[None, :]) / (1.0 - r), 0, 255)
    return out


def despill(rgb, alpha, cfg, rim=2, reach=4.0):
    """由內向外補色(round-19 原樣)。教科書 matting 反解喺呢種圖唔work。"""
    solid = alpha > 0.5
    core = ndimage.binary_erosion(solid, iterations=rim)
    outer = ((alpha > 0.02) if cfg["mode"] == "flat" else solid) & ~core
    out = rgb.copy()
    if core.any():
        dist, (iy, ix) = ndimage.distance_transform_edt(~core, return_indices=True)
        near = outer & (dist <= reach)
        out[near] = rgb[iy[near], ix[near]]
        thin = outer & (dist > reach)
    else:
        thin = outer
    if cfg["mode"] == "green" and thin.any():
        g = out[:, :, 1]
        cap = np.maximum(out[:, :, 0], out[:, :, 2]) * 1.08 + 8.0
        out[:, :, 1] = np.where(thin, np.minimum(g, cap), g)
    return out


def extract_cells(rgb, alpha, W, sat_reach=30):
    """成張 sheet 一次過 label,再按 x 重心分落 3 格。

    衛星規則 = round-19 嗰條(外擴 20% 框 + 唔可以係隔籬格嘅大嘢)**加**
    一條「離主體 ≤ sat_reach px」—— 專登用嚟踢走每張 sheet 第三格右下角
    嗰粒裝飾四角星,同時保住貼住塔身嘅折射光線 / 日冕 / 碎片 / 彈殼。
    """
    lbl, n = ndimage.label(alpha > 0.35)
    if n == 0:
        return [None] * 3
    sl = ndimage.find_objects(lbl)
    areas = ndimage.sum(np.ones_like(lbl), lbl, index=range(1, n + 1))
    cx = ndimage.center_of_mass(alpha > 0.35, lbl, index=range(1, n + 1))
    bounds = split_cells(alpha, W)

    buckets = [[] for _ in range(3)]
    for k in range(1, n + 1):
        x = cx[k - 1][1]
        for i, (a0, a1) in enumerate(bounds):
            if a0 <= x < a1:
                buckets[i].append(k)
                break

    out = []
    for i in range(3):
        if not buckets[i]:
            out.append(None)
            continue
        main = max(buckets[i], key=lambda k: areas[k - 1])
        my, mx = sl[main - 1]
        pad = max(8, int(0.20 * max(my.stop - my.start, mx.stop - mx.start)))
        keep = lbl == main
        far = ndimage.distance_transform_edt(~(lbl == main))
        for k in range(1, n + 1):
            if k == main or areas[k - 1] < 5:
                continue
            if k not in buckets[i] and areas[k - 1] > 0.12 * areas[main - 1]:
                continue
            sy, sx = sl[k - 1]
            if not (sy.start >= my.start - pad and sy.stop <= my.stop + pad
                    and sx.start >= mx.start - pad and sx.stop <= mx.stop + pad):
                continue
            if far[lbl == k].min() > sat_reach:
                continue
            keep |= lbl == k
        a = np.where(ndimage.binary_dilation(keep, iterations=2), alpha, 0.0)
        a = np.where(a < 0.06, 0.0, a)
        ys, xs = np.nonzero(a > 0.04)
        if len(ys) == 0:
            out.append(None)
            continue
        # 接地點 / 底座水平中心量喺**實心**主體上面(唔計柔光暈,否則
        # 聖光塔嘅光柱同磁力塔嘅電弧會拉低個接地點)
        solid = (np.where(lbl == main, alpha, 0.0) > 0.5)
        sy, sx = np.nonzero(solid)
        gy = int(sy.max()) + 1
        h_main = sy.max() - sy.min() + 1
        foot = solid[max(0, gy - max(4, int(0.12 * h_main))):gy]
        fx = np.nonzero(foot.any(0))[0]
        bcx = 0.5 * (fx.min() + fx.max()) if len(fx) else 0.5 * (sx.min() + sx.max())
        out.append(dict(
            rgba=np.dstack([np.clip(rgb, 0, 255), a * 255.0]).astype(np.uint8),
            bbox=(int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1),
            ground=gy, base_cx=float(bcx),
            base_w=float(fx.max() - fx.min() + 1) if len(fx) else 0.0))
    return out


def process_sheet(fname, cfg):
    im = Image.open(os.path.join(SRC, fname)).convert("RGB")
    rgb = remove_watermark(np.asarray(im).astype(np.float64))
    H, W, _ = rgb.shape

    d, bg = build_distance(rgb, cfg)
    d_hi = float(cfg["d_hi"])
    d_soft = float(cfg.get("d_soft", d_hi + 16.0))

    _, framed = kill_frame_lines((d >= d_hi).astype(float))
    d = np.where(framed, 0.0, d)

    outside_hard = _fill_from_border(d < d_hi)
    outside_soft = _fill_from_border(d < d_soft)
    band = outside_soft & ~outside_hard

    alpha = np.ones_like(d)
    alpha[band] = np.clip((d[band] - d_hi) / (d_soft - d_hi), 0.0, 1.0)
    alpha[d < d_hi] = 0.0
    alpha[framed] = 0.0

    tb = cfg.get("text_band")
    if tb:
        alpha[int(H * tb[0]):, :] = 0.0

    rgb = unmix_soft(rgb, alpha, bg)
    if cfg.get("glow") == "warm":
        rgb = unmix_greenness(rgb, alpha, bg)
    rgb = despill(rgb, alpha, cfg)
    cells = extract_cells(rgb, alpha, W)
    return dict(tid=cfg["tid"], cells=cells, bg=bg, alpha=alpha)


# ============================================================================
# 擺位 + 輸出
# ============================================================================
def resize_premul(arr, nw, nh):
    """Premultiplied 縮放 —— straight-alpha LANCZOS 會將透明像素嘅綠溝返
    入邊緣(round-19 陷阱一)。"""
    a = arr[:, :, 3:4] / 255.0
    pm = np.concatenate([arr[:, :, :3] * a, arr[:, :, 3:4]], axis=2)
    out = np.zeros((nh, nw, 4))
    for ch in range(4):
        out[:, :, ch] = np.asarray(
            Image.fromarray(pm[:, :, ch].astype(np.float32), "F")
                 .resize((nw, nh), Image.LANCZOS), dtype=np.float64)
    out = np.clip(out, 0, 255)
    oa = out[:, :, 3:4] / 255.0
    rgb = np.where(oa > 0.004, out[:, :, :3] / np.maximum(oa, 1e-6), 0.0)
    return Image.fromarray(
        np.dstack([np.clip(rgb, 0, 255), out[:, :, 3]]).astype(np.uint8), "RGBA")


def bleed_rgb(img):
    """透明像素嘅 RGB 填返最近嗰粒實色(GPU LINEAR filter 會抽色,
    離線 checker 影唔到 —— round-19 陷阱一嘅 GPU 半邊)。"""
    arr = np.asarray(img).astype(np.uint8).copy()
    solid = arr[:, :, 3] > 8
    if not solid.any() or solid.all():
        return img
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    filled = arr[:, :, :3][iy, ix]
    arr[:, :, :3] = np.where(solid[..., None], arr[:, :, :3], filled)
    return Image.fromarray(arr, "RGBA")


def place(cell, k):
    """縮放 + 擺位。

    高度**固定** 128:接地線一定要喺畫布入面,而佢就住 node 落 61px,
    所以任何一張嘅畫布半高都至少 61+3 —— 即係話高度根本冇得剪,60 張一律
    128。呢個副作用啱啱好係我哋想要嘅:UI 嗰邊 `STRETCH_KEEP_ASPECT_CENTERED`
    對住 60 張同高嘅圖,縮出嚟嘅大細先會一致。

    闊度就**逐張剪到啱剪**(round-19 嘅做法),因為闊度差好遠:雷電塔 t1
    得 46px,荊棘塔 t3 條根攤到 170px。一刀切 170 闊等於 60 張有 55 張
    用緊兩倍 VRAM 去畫空氣。

    三個 tier 用同一個 k,而擺位規則係「石底座底邊 -> GROUND_Y、
    石底座水平中心 -> 畫布中線」,所以進化換圖唔會跳位。
    """
    rgba = cell["rgba"]
    x0, y0, x1, y1 = cell["bbox"]
    arr = rgba[y0:y1, x0:x1].astype(np.float64)
    sh, sw = arr.shape[:2]
    nw, nh = max(1, int(round(sw * k))), max(1, int(round(sh * k)))
    sub = resize_premul(arr, nw, nh)

    gy = (cell["ground"] - y0) * k          # 接地點喺 sub 入面嘅 y
    bx = (cell["base_cx"] - x0) * k         # 底座中心喺 sub 入面嘅 x
    half = int(np.ceil(max(bx, nw - bx))) + 1
    cw = max(2 * half, 8)
    if cw % 2:
        cw += 1
    canvas = Image.new("RGBA", (cw, CANVAS), (0, 0, 0, 0))
    px = int(round(cw * 0.5 - bx))
    py = int(round(GROUND_Y - gy))
    canvas.paste(sub, (px, py))
    clipped = (px < 0 or py < 0 or px + nw > cw or py + nh > CANVAS)
    return bleed_rgb(canvas), clipped, (cw, CANVAS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true")
    ap.add_argument("--debug", action="store_true")
    ap.add_argument("--measure", action="store_true")
    ap.add_argument("--k", type=float, default=0.0)
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    dest = ASSETS if args.install else STAGE
    os.makedirs(dest, exist_ok=True)
    os.makedirs(QA, exist_ok=True)

    sheets = {}
    for fname, cfg in SHEETS.items():
        if args.only and str(cfg["tid"]) not in args.only.split(","):
            continue
        r = process_sheet(fname, cfg)
        got = sum(1 for c in r["cells"] if c)
        print("id=%-3d <- %-14s cells=%d/3 bg=%s" %
              (cfg["tid"], fname, got, [int(v) for v in r["bg"]]))
        if got != 3:
            print("   !! 切唔到 3 格 —— 停低,唔准估")
            continue
        sheets[fname] = r

    # --- 全域倍率 --------------------------------------------------------
    # 一個 k 走天下:最高嗰張啱啱好填到 GROUND_Y(上面留 3px),而每張
    # 嘅寬度都要入得晒 128。兩個約束取最緊嗰個。
    # 闊度冇約束(逐張剪),所以淨係兩條:接地點以上要入到畫布頂,
    # 接地點以下(影 / 根)要入到畫布底。
    kh = kb = 1e9
    tall = deep = ("", 0)
    for fname, r in sheets.items():
        for i, c in enumerate(r["cells"]):
            _x0, y0, _x1, y1 = c["bbox"]
            top = c["ground"] - y0
            hi = (GROUND_Y - 2.0) / max(top, 1)
            below = y1 - c["ground"]
            lo = (CANVAS - GROUND_Y - 1.0) / below if below > 0 else 1e9
            if hi < kh:
                kh, tall = hi, (fname, i)
            if lo < kb:
                kb, deep = lo, (fname, i)
    k = args.k or (GLOBAL_K if GLOBAL_K > 0 else min(kh, kb))
    print("\nglobal k = %.4f   (above-ground limit %s t%d -> %.4f;"
          " below-ground limit %s t%d -> %.4f)"
          % (k, tall[0], tall[1] + 1, kh, deep[0], deep[1] + 1, kb))

    if args.measure:
        for fname, r in sorted(sheets.items(), key=lambda kv: kv[1]["tid"]):
            for i, c in enumerate(r["cells"]):
                x0, y0, x1, y1 = c["bbox"]
                print("  id%-3d t%d  src %3dx%-3d  ground=%3d base_cx=%6.1f "
                      "base_w=%5.1f  -> %3dx%-3d"
                      % (r["tid"], i + 1, x1 - x0, y1 - y0, c["ground"],
                         c["base_cx"], c["base_w"],
                         round((x1 - x0) * k), round((y1 - y0) * k)))
        return

    report = {"k": k, "canvas": CANVAS, "ground_y": GROUND_Y, "towers": {}}
    for fname, r in sheets.items():
        tid = r["tid"]
        sizes, clips = [], []
        for i, suf in enumerate(TIERS):
            img, clipped, sz = place(r["cells"][i], k)
            img.save(os.path.join(dest, "tower_%d%s.png" % (tid, suf)))
            sizes.append(sz)
            clips.append(clipped)
        report["towers"][str(tid)] = dict(
            sheet=fname, mode=SHEETS[fname]["mode"], d_hi=SHEETS[fname]["d_hi"],
            bg=[int(v) for v in r["bg"]], drawn=sizes, clipped=clips,
            base_w=[round(c["base_w"] * k, 1) for c in r["cells"]])
        if any(clips):
            print("   !! id=%d 有格出咗界 %s" % (tid, clips))
        if args.debug:
            Image.fromarray((r["alpha"] * 255).astype(np.uint8), "L").save(
                os.path.join(QA, "alpha_%d.png" % tid))

    with open(os.path.join(QA, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("out -> " + dest)


if __name__ == "__main__":
    sys.exit(main())
