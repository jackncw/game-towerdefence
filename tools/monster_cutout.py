#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""monster_cutout.py — 由 art_reference/monster/*.jfif 嘅 sprite sheet 摳出
60 張有 alpha 嘅怪物 PNG(10 族 × lv1-5 + boss)。

原始 .jfif 唔會被改動。預設出去 qa/monster_cutout/out/ 畀人肉眼驗,
`--install` 先寫入 assets/generated/monsters/。

點解唔一刀切 #00FF00:
  * 10 張 sheet 底色都唔同 —— 大部分係鮮綠(#04FC04 上下),史萊姆嗰張係暗綠
    (#049C04),cultist 嗰張係啞綠(#34C42C)加漸變,ghost 嗰張係淺灰
    (#BCC4B4)加綠間隔線,bat 嗰張係灰綠(#B4CCAC)加近白分隔線同上下綠邊條。
  * 同一張都唔止一款綠 —— goblin 有四個亮度、beetle 每格外面一圈暗綠框、slime
    暗綠底但格與格之間係亮綠。所以底色係一個**集合**(邊框眾數,>1.5%),
    距離取集合入面嘅最小值。
  * 綠底仲有暗度 —— treant 每格地下有一撻投影,同底色同色相但暗三成幾。所以
    唔用 RGB 距離,用**射線距離**:到 t·bg(t 夾喺 0.55–1.35)嘅距離。影同底
    一齊消失,而黑色描邊(要 t≈0.1 先掂到射線,俾下限頂住)距離大,保得住。
  * 綠色主體要保住 —— 史萊姆成隻綠、treant 有綠葉、cultist 有綠法陣、wolf lv5
    有綠火。上面條射線距離已經幫佢哋全部拉到 d>140,同底色(d<10)差好遠。

Pipeline(逐張):
  1. 邊框取樣底色集合(唔 hardcode 任何色值)
  2. 距離場 d(x,y)
  3. 剷格線 / 邊條 —— 要幼(≤4px)、要貫通(≥94%),而且要**坐喺格界位**
     (±5% 闊)。冇第三個條件就會斬開高過九成格高嘅怪。
  4. 兩層 flood fill 出 alpha:d<d_hi 一律透明(連被手臂圍住嗰啲底色窿),
     d_hi..d_soft 之間而且由邊界掃得到嘅係柔光暈(cultist boss 綠魔力光、
     treant boss 法陣輝光),用 ramp 淡出;其餘全不透明。
  5. de-spill:主體向內縮 2px 嗰嚿係乾淨 core,外面兩層由最近嘅 core 補色;
     幼過 4px 嘅嘢(骷髏 boss 骨環、cultist 法陣線、bat boss 風線)搵唔到
     core,改用壓綠通道嘅傳統 de-spill,保住條線唔會消失。
  6. 成張 sheet 一次過 connected-component,再按 x 重心分落 6 格 —— **唔可以
     先切格再 label**,有幾隻怪畫到過咗格界,硬切會削走佢隻手臂。
     每格留主體 + 主體 bbox 外擴 20% 內嘅衛星(slime boss 嘅細史萊姆、goblin
     boss 嘅魔法 wisp、bat boss 嘅風線、skeleton boss 嘅地面光環)。
  7. bat 嗰張剷走底部文字帶("Level 1"…"The BOSS",量出嚟係 y=145..159)
  8. 縮放對齊:大細跟舊 sprite 嘅**實心像素面積**,擺位跟舊 sprite 嘅接地點
     同水平中心。畫布就住主體剪到啱剪(唔再係正方形)。
  9. Premultiplied 縮放 + alpha bleed —— 兩者都係為咗「透明像素嘅 RGB」唔會
     喺 resize(離線)同 LINEAR filter(GPU)嗰陣溝返入邊緣。

驗收:`python tools/monster_qa.py --check`(邊緣殘底色掃描)、`--sheet`(棋盤
接觸表)、`--zoom <族>`;`tools/monster_compare.py` 出新舊同尺寸對照。

用法:
  python tools/monster_cutout.py --debug        # 出去 staging + alpha QA 圖
  python tools/monster_cutout.py --install      # 寫入 assets/generated/monsters
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
SRC = os.path.join(ROOT, "art_reference", "monster")
ASSETS = os.path.join(ROOT, "assets", "generated", "monsters")
QA = os.path.join(ROOT, "qa", "monster_cutout")
STAGE = os.path.join(QA, "out")
ANCHOR = os.path.join(ROOT, "tools", "monster_anchor.json")

# --- 目標尺寸 -----------------------------------------------------------------
# 遊戲入面怪物嘅**顯示**尺寸 = MON_SIZES[lv] × GameData.RENDER_SCALE(2.0),
# 即 64/70/76/82/88,boss 192。呢個數今輪一步都冇郁。
#
# 源圖解像度上限:每格 ~171×167,主體大約佔 130–150px。所以:
#   * lv1-5 用 SS=2.5(PNG = 顯示尺寸 × 1.25)—— 主體高度出到 81..131px,啱啱
#     好坐喺源圖原生解像度上面少少。
#   * boss 用 SS=1.5(PNG = 顯示尺寸 × 0.75)—— boss 顯示到 220px 闊,但源圖
#     淨係得 ~150px;儲成 272px 唔會多一格細節出嚟,淨係多食 VRAM。
#
# 就係因為咁,冇跟「一律 2 倍顯示解像度」:60 張全部 2 倍要 10.6MB,超咗 6MB
# 硬線一大截,而超出源圖原生解像度嗰部分係放大空氣。而家 3.2MB(淨增 2.5MB),
# 每一 byte 都係源圖真係有嘅細節。
MON_SIZES = {1: 32, 2: 35, 3: 38, 4: 41, 5: 44}
BOSS_SIZE = 96
SS_LEVEL = 2.5
SS_BOSS = 1.5

LEVELS = ["1", "2", "3", "4", "5", "boss"]

# --- 逐張 sheet 嘅特性 --------------------------------------------------------
# mode: "green" = 綠幕(射線距離);"flat" = 平色底(RGB 距離)+ 順手清埋綠邊條
# d_hi:   低過佢一律當底色(唔理掃唔掃得到)
# d_soft: d_hi..d_soft 而且由邊界掃得到嘅係柔光暈,用 ramp 淡出。
#         預設 d_hi+16(窄),得 cultist / treant 兩張真係有柔光要保。
# text_band: (y0, y1) 相對格高 —— 呢個範圍入面嘅嘢一律當文字剷走
# d_soft 預設好窄(d_hi+16)—— 佢係**柔光暈**用嘅,唔係羽化用。開得闊(試過
# 105)會令深色部位變半透明:甲蟲六隻深藍腳 d≈81,喺 58..105 之間,出街得
# 49% 不透明度,睇落似蒸發緊。真係有柔光要保嘅得 cultist(boss 綠魔力光)同
# treant(boss 法陣輝光)兩張。
SHEETS = {
    "goblin.jfif":   dict(family="goblin",   mode="green", d_hi=58),
    "wolf.jfif":     dict(family="wolf",     mode="green", d_hi=58),
    "skeleton.jfif": dict(family="skeleton", mode="green", d_hi=58),
    "golem.jfif":    dict(family="golem",    mode="green", d_hi=58),
    "treant.jfif":   dict(family="treant",   mode="green", d_hi=60, d_soft=96),
    "beetle.jfif":   dict(family="beetle",   mode="green", d_hi=58),
    "cultist.jfif":  dict(family="cultist",  mode="green", d_hi=52, d_soft=108),
    "monster1.jfif": dict(family="slime",    mode="green", d_hi=50),
    # ghost 張底係淺灰 #BCC4B4,而 lv1 隻鬼「幾乎白」—— 身上有啲位同底色只差
    # d≈31。所以呢張門檻要拉到最低,唔係隻鬼會蛀窿(用 46 跑過,lv1/lv2 蛀到
    # 剩返半隻)。
    "ghost.jfif":    dict(family="ghost",    mode="flat",  d_hi=16, d_soft=27),
    # 文字帶量出嚟係 y=145..159(格高 167)。142-144 仲有隻蝠嘅腳趾,所以界線
    # 落 0.862 —— 早期用 0.74 剷埋 lv5 對腳。
    "bat.jfif":      dict(family="bat",      mode="flat",  d_hi=24, d_soft=46,
                          text_band=(0.862, 1.00)),
}


# ============================================================================
# 底色偵測
# ============================================================================
def sample_bg(rgb, mode):
    """由四邊取樣。回傳 (主底色, [要一併剷走嘅副底色…])。

    唔 hardcode 任何色值:邊框像素量化落 8 級再數眾數。綠幕張數主底色一定係
    綠;ghost / bat 張數主底色係灰,而綠(間隔線 / 邊條)變副底色。
    """
    h, w, _ = rgb.shape
    b = np.concatenate([
        rgb[0:3].reshape(-1, 3), rgb[h - 3:h].reshape(-1, 3),
        rgb[:, 0:3].reshape(-1, 3), rgb[:, w - 3:w].reshape(-1, 3)])
    q = (b // 8 * 8 + 4)
    uniq, cnt = np.unique(q, axis=0, return_counts=True)
    order = np.argsort(-cnt)
    top = [(uniq[i].astype(float), int(cnt[i])) for i in order[:8]]
    total = float(len(b))

    def greenish(c):
        return c[1] - max(c[0], c[2]) > 60

    if mode == "green":
        greens = [c for c, n in top if greenish(c) and n / total > 0.015]
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


# ============================================================================
# 距離場
# ============================================================================
def dist_ray(rgb, bg, tmin=0.55, tmax=1.35):
    """到「底色射線 t·bg」嘅距離。t 夾喺 [tmin, tmax]。"""
    bb = float(np.dot(bg, bg))
    t = np.clip((rgb @ bg) / max(bb, 1e-6), tmin, tmax)
    return np.linalg.norm(rgb - t[..., None] * bg[None, None, :], axis=2)


def dist_segment(rgb, a, b):
    """到「A 同 B 之間嗰條線段」嘅距離(s 夾喺 [0,1])。

    ghost 嗰張兩種底色貼住:淺灰格底 + 純綠間隔線。兩者中間有一條 2-3px 嘅
    漸變帶,每一粒都係「兩種底色溝埋」—— 對灰嘅距離同對綠嘅距離兩邊都唔夠
    近,結果成個綠框留咗喺 lv3/4/5/boss 度。將條線段本身當底色就一次過解決。
    """
    ab = b - a
    denom = float(np.dot(ab, ab))
    s = np.clip(((rgb - a) @ ab) / max(denom, 1e-6), 0.0, 1.0)
    return np.linalg.norm(rgb - (a[None, None, :] + s[..., None] * ab[None, None, :]), axis=2)


def build_distance(rgb, cfg):
    """到「任何一款底色」嘅最短距離。

    每張 sheet 都唔止一款綠:goblin 有 4 個亮度、beetle 每格外面有一圈暗綠框
    (0,144,0)、slime 底係暗綠(0,152,0)但格與格之間有亮綠間隔線。淨係用一款
    綠嘅話,第一次跑就係咁:亮綠間隔線變咗「主體」,slime / beetle 成行變綠柱。
    """
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
# 格線
# ============================================================================
def kill_frame_lines(alpha, cells=6, max_w=4, cover=0.94, tol=0.05):
    """剷走格線 / 邊條 —— 但淨係喺**格界位**先剷。

    要剷:bat 嗰張格與格之間嘅近白色分隔線(#F9FFFA)、ghost 嗰張綠間隔線兩
    邊嘅淺綠過渡帶、上下嘅邊條。呢啲都唔會俾色彩門檻 key 走。
    唔可以剷:怪嘅身。treant lv5 / golem lv5 / goblin boss 高過九成格高,淨靠
    「幼 + 貫通」兩個條件會連佢哋一齊斬開,出街係一條垂直直線切口(踩過)。

    所以第三個條件係位置:真格線一定坐喺 k·W/6 附近(±5% 闊),怪唔會。
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
        if min(abs(c - ix) for ix in ideal_x) <= tol * W:
            killed[:, a:b] = True
    for a, b in runs(on.sum(1) / float(W) > 0.97, H):
        # 橫線只認上下兩條邊條,唔認怪身
        if b - a <= max_w and (b < 0.10 * H or a > 0.90 * H):
            killed[a:b, :] = True
    out = alpha.copy()
    out[killed] = 0.0
    return out, killed


# ============================================================================
# 切格
# ============================================================================
def split_cells(alpha, W, expect=6):
    """逐列 alpha 總和搵空隙,再對返六等分嘅理想位(容差 ±0.45 格)。"""
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
        cands = [r for r in runs if abs((r[0] + r[1]) * 0.5 - ideal) < 0.45 * step
                 and r[0] > 2 and r[1] < W - 2]
        if cands:
            best = max(cands, key=lambda r: r[1] - r[0])
            bounds.append((best[0] + best[1]) // 2)
        else:
            bounds.append(int(round(ideal)))
    bounds.append(W)
    return list(zip(bounds[:-1], bounds[1:]))


# ============================================================================
# 主流程(逐張 sheet)
# ============================================================================
def process_sheet(fname, cfg):
    im = Image.open(os.path.join(SRC, fname)).convert("RGB")
    rgb = np.asarray(im).astype(np.float64)
    H, W, _ = rgb.shape

    d, bg = build_distance(rgb, cfg)
    d_hi = float(cfg["d_hi"])
    d_soft = float(cfg.get("d_soft", d_hi + 16.0))

    # 格線要喺 flood fill 之前打通,否則 fill 入唔到格入面
    _, framed = kill_frame_lines((d >= d_hi).astype(float))
    d = np.where(framed, 0.0, d)

    # 兩層 flood fill:
    #   hard  —— 行得過 d < d_hi 嘅像素。掃唔到嘅 = 主體(連被描邊包住嘅綠肉,
    #            所以史萊姆成隻綠、treant 綠葉、cultist 綠法陣都保得住)
    #   soft  —— 行得過 d < d_soft。兩層之間嗰條帶 = 柔光暈(cultist boss 嘅
    #            綠色魔力光、treant boss 嘅法陣輝光),用 ramp 淡出,唔好一刀切
    outside_hard = _fill_from_border(d < d_hi)
    outside_soft = _fill_from_border(d < d_soft)
    band = outside_soft & ~outside_hard

    alpha = np.ones_like(d)
    alpha[band] = np.clip((d[band] - d_hi) / (d_soft - d_hi), 0.0, 1.0)
    # 最後先一刀切:**唔理掃唔掃得到**,夠似底色就係底色。冇呢句嘅話,手臂同
    # 身體之間嗰啲被圍住嘅綠(golem 每級都有一撻)會當咗做主體,出街變螢光綠斑。
    alpha[d < d_hi] = 0.0
    alpha[framed] = 0.0

    tb = cfg.get("text_band")
    if tb:
        # bat 張每格底下有 baked-in 嘅 "Level 1"…"The BOSS"。喺呢度就剷,
        # 遲啲揀 component 嗰陣連睇都唔會睇到佢哋。
        alpha[int(H * tb[0]):, :] = 0.0

    rgb = despill(rgb, alpha, d, cfg)
    cells = extract_cells(rgb, alpha, W)
    return dict(family=cfg["family"], cells=cells, bg=bg, alpha=alpha)


def _fill_from_border(passable):
    lbl, _ = ndimage.label(passable)
    edge = np.concatenate([lbl[0, :], lbl[-1, :], lbl[:, 0], lbl[:, -1]])
    return np.isin(lbl, np.unique(edge[edge > 0]))


def despill(rgb, alpha, d, cfg, rim=2, reach=4.0):
    """邊緣 de-spill。

    JPEG 冇 alpha,所以主體最外嗰一兩層像素本身就係「主體 × 底色」溝出嚟嘅,
    綠底就綠、灰底就灰。試過用 matting 反解(F=(C−(1−a)B)/a)—— 唔得,因為
    alpha 估唔準,細 alpha 一除就將綠爆大,60 張有 58 張出咗一圈死綠邊。

    而家改用**由內向外補色**:主體向內縮 2px 嗰嚿叫 core,core 係乾淨嘅;外
    面兩層像素如果搵到 3px 內嘅 core,就用最近嗰粒 core 嘅顏色蓋過去。搵唔到
    core 嘅(幼過 4px 嘅嘢 —— 骷髏 boss 嘅骨環、cultist 嘅法陣線、bat boss 嘅
    風線)唔補色,改用傳統 de-spill 公式壓返個綠,保住條線唔會消失。
    """
    solid = alpha > 0.5
    core = ndimage.binary_erosion(solid, iterations=rim)
    # 灰底(ghost / bat)冇「本身就係灰」以外嘅柔光元素,所以連半透明帶都一齊
    # 補色;綠底就唔可以 —— cultist boss 嘅綠魔力光、treant boss 嘅法陣輝光都
    # 住喺半透明帶入面,補咗色就變成袍色嘅一嚿嘢。
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
        # 保線用嘅溫和 de-spill:綠通道唔准高過 max(R,B) 太多
        g = out[:, :, 1]
        cap = np.maximum(out[:, :, 0], out[:, :, 2]) * 1.08 + 8.0
        out[:, :, 1] = np.where(thin, np.minimum(g, cap), g)
    # 半透明帶(柔光暈)同樣壓綠,唔好留一圈螢光綠
    if cfg["mode"] == "green":
        soft = (alpha > 0.02) & (alpha <= 0.5)
        if soft.any():
            g = out[:, :, 1]
            cap = np.maximum(out[:, :, 0], out[:, :, 2]) * 1.15 + 14.0
            out[:, :, 1] = np.where(soft, np.minimum(g, cap), g)
    return out


def extract_cells(rgb, alpha, W):
    """成張 sheet 一次過 label,再按 x 重心分落 6 格。

    **唔可以逐格切完先 label** —— 好幾隻怪(golem lv5、treant lv5、beetle lv3)
    畫到過咗格界,硬切就會削走佢隻手臂,而且削口係一條垂直直線,一眼睇得出。
    改成先分 component 再認格,每隻怪嘅裁切框係佢自己 component 嘅 bbox,
    同格界完全無關。
    """
    lbl, n = ndimage.label(alpha > 0.35)
    if n == 0:
        return [None] * 6
    sl = ndimage.find_objects(lbl)
    areas = ndimage.sum(np.ones_like(lbl), lbl, index=range(1, n + 1))
    cx = ndimage.center_of_mass(alpha > 0.35, lbl, index=range(1, n + 1))
    bounds = split_cells(alpha, W)

    buckets = [[] for _ in range(6)]
    for k in range(1, n + 1):
        x = cx[k - 1][1]
        for i, (a0, a1) in enumerate(bounds):
            if a0 <= x < a1:
                buckets[i].append(k)
                break

    out = []
    for i in range(6):
        if not buckets[i]:
            out.append(None)
            continue
        main = max(buckets[i], key=lambda k: areas[k - 1])
        my, mx = sl[main - 1]
        # 外擴範圍 = 主體尺寸嘅 20%(至少 8px)。slime boss 嘅細史萊姆、goblin
        # boss 嘅魔法 wisp、bat boss 嘅風線、skeleton boss 嘅地面光環全部靠呢步
        # 保住;隔籬格嘅怪離得夠遠,唔會被順手撈埋。
        pad = max(8, int(0.20 * max(my.stop - my.start, mx.stop - mx.start)))
        keep = lbl == main
        for k in range(1, n + 1):
            if k == main or areas[k - 1] < 5:
                continue
            # 衛星要麼同主體同一格,要麼細過主體一成二 —— 唔加呢個條件嘅話,
            # beetle 隔籬格隻甲蟲(佢哋畫到差唔多貼住格界)會被外擴框撈埋,
            # lv3 出咗兩隻疊埋一齊。
            if k not in buckets[i] and areas[k - 1] > 0.12 * areas[main - 1]:
                continue
            sy, sx = sl[k - 1]
            if (sy.start >= my.start - pad and sy.stop <= my.stop + pad
                    and sx.start >= mx.start - pad and sx.stop <= mx.stop + pad):
                keep |= lbl == k
        a = np.where(ndimage.binary_dilation(keep, iterations=2), alpha, 0.0)
        a = np.where(a < 0.06, 0.0, a)      # JPEG ringing 嘅雜邊
        ys, xs = np.nonzero(a > 0.04)
        if len(ys) == 0:
            out.append(None)
            continue
        out.append(dict(rgba=np.dstack([np.clip(rgb, 0, 255), a * 255.0]).astype(np.uint8),
                        bbox=(int(xs.min()), int(ys.min()),
                              int(xs.max()) + 1, int(ys.max()) + 1)))
    return out


# ============================================================================
# 對齊 + 輸出
# ============================================================================
def load_anchors():
    """舊 sprite 嘅擺位基準。第一次跑會由 assets 量返出嚟再寫低 —— 之後 assets
    已經換成新圖,再量就會漂,所以一定要有呢個快照檔。

    記三樣:normalized bbox(接地點 / 水平中心)、實心像素佔方格嘅比例
    (= 視覺體積),同埋方格邊長。
    """
    if os.path.exists(ANCHOR):
        with open(ANCHOR, encoding="utf-8") as f:
            return json.load(f)
    out = {}
    for fam in sorted({c["family"] for c in SHEETS.values()}):
        for lv in LEVELS:
            p = os.path.join(ASSETS, "%s_%s.png" % (fam, lv))
            if not os.path.exists(p):
                continue
            al = np.asarray(Image.open(p).convert("RGBA"))[:, :, 3]
            hh, ww = al.shape
            ys, xs = np.nonzero(al > 8)
            out["%s_%s" % (fam, lv)] = dict(
                bbox=[xs.min() / ww, ys.min() / hh,
                      (xs.max() + 1) / ww, (ys.max() + 1) / hh],
                area=float((al > 8).sum()) / float(ww * hh), side=int(ww))
    with open(ANCHOR, "w", encoding="utf-8") as f:
        json.dump(out, f, indent=1)
    return out


def resize_premul(arr, nw, nh):
    """**Premultiplied** 縮放。

    直接用 PIL 對 straight-alpha RGBA 做 LANCZOS 係一個經典陷阱:全透明像素
    嗰陣仍然帶住原本嘅底色(綠),縮放核會將嗰啲綠溝返入邊緣像素度 —— 摳得
    幾乾淨都好,一 resize 就返晒一圈綠光暈出嚟(第一次跑 60 張有 58 張中招)。
    所以要先乘 alpha、縮完再除返。
    """
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
    res = np.dstack([np.clip(rgb, 0, 255), out[:, :, 3]]).astype(np.uint8)
    return Image.fromarray(res, "RGBA")


def place(cell, disp, ss, anchor, max_w=1.20, max_h=1.15):
    """縮放 + 擺位。

    大細以**實心像素面積**為準,唔係以舊 bbox 為準。試過「塞入舊 bbox」——
    唔得:新圖同舊圖嘅長寬比差好遠,蝠類開晒翼係 2.2:1,塞入一個 0.82 闊嘅框
    之後高度剩返舊嘅四成半,細到認唔出。面積(= 視覺體積)先係「隻怪睇落幾
    大」嘅正確量度,而 1.28 / 1.20 兩個上限保住佢唔會爆出路面。

    畫布唔再係正方形,係就住主體剪到啱剪 —— 錨點靠計:
      腳底離 sprite 中心 f = (舊 bbox 底 − 0.5) × 顯示邊長。
    Sprite2D 係 centered,所以只要畫布半高 ≥ f,腳就一定落返舊嗰個位:
    行路唔會浮亦唔會沉,飛行族(bat)嘅舊高度 offset 亦都原封不動繼承。
    """
    rgba, (bx0, by0, bx1, by1) = cell["rgba"], cell["bbox"]
    arr = rgba[by0:by1, bx0:bx1].astype(np.float64)
    sh, sw = arr.shape[:2]
    area0 = float((arr[:, :, 3] > 8).sum())
    if area0 < 1:
        area0 = 1.0

    k = (anchor["area"] * disp * disp / area0) ** 0.5      # source px -> display px
    k = min(k, max_w * disp / sw, max_h * disp / sh)
    w, h = sw * k, sh * k

    ax0, _ay0, ax1, ay1 = anchor["bbox"]
    f = (ay1 - 0.5) * disp                                  # 腳底喺中心以下幾多
    dx = ((ax0 + ax1) * 0.5 - 0.5) * disp                   # 水平中心偏移
    half_w = max(w * 0.5 + abs(dx), w * 0.5) + 1.5
    half_h = max(f, h - f) + 1.5

    pw = int(round(2 * half_w * ss)) | 1 ^ 1                # 湊雙數
    ph = int(round(2 * half_h * ss)) | 1 ^ 1
    pw, ph = max(pw, 4), max(ph, 4)
    nw = max(1, int(round(w * ss)))
    nh = max(1, int(round(h * ss)))
    sub = resize_premul(arr, nw, nh)

    canvas = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    px = int(round(pw * 0.5 + dx * ss - nw * 0.5))
    py = int(round(ph * 0.5 + f * ss - nh))
    canvas.paste(sub, (max(0, min(pw - nw, px)), max(0, min(ph - nh, py))))
    return bleed_rgb(canvas)


def bleed_rgb(img):
    """全透明像素嘅 RGB 填返最近嗰粒不透明像素嘅色(alpha bleed)。

    唔做嘅話,引擎行 LINEAR filter 嗰陣一樣會由透明像素度抽色出嚟溝落邊緣
    —— 同上面 resize 個陷阱一模一樣,只不過發生喺 GPU 度,離線 checker 影都
    影唔到。atlas 嘅 2px extrude 只顧格與格之間,顧唔到格內嘅透明區。
    """
    arr = np.asarray(img).astype(np.uint8).copy()
    solid = arr[:, :, 3] > 8
    if not solid.any() or solid.all():
        return img
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    filled = arr[:, :, :3][iy, ix]
    arr[:, :, :3] = np.where(solid[..., None], arr[:, :, :3], filled)
    return Image.fromarray(arr, "RGBA")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--install", action="store_true",
                    help="寫入 assets/generated/monsters(預設只出 staging)")
    ap.add_argument("--debug", action="store_true", help="另外出 alpha QA 圖")
    ap.add_argument("--only", default="")
    args = ap.parse_args()

    dest = ASSETS if args.install else STAGE
    os.makedirs(dest, exist_ok=True)
    os.makedirs(QA, exist_ok=True)
    anchors = load_anchors()

    report = {}
    for fname, cfg in sorted(SHEETS.items()):
        if args.only and cfg["family"] not in args.only.split(","):
            continue
        r = process_sheet(fname, cfg)
        fam = r["family"]
        got = sum(1 for c in r["cells"] if c)
        print("%-9s <- %-14s cells=%d/6 bg=%s" %
              (fam, fname, got, [int(v) for v in r["bg"]]))
        if got != 6:
            print("   !! 切唔到 6 格 —— 跳過呢一族,唔准估")
            report[fam] = dict(sheet=fname, ok=False, cells=got)
            continue
        sizes = []
        for i, lv in enumerate(LEVELS):
            ss = SS_BOSS if lv == "boss" else SS_LEVEL
            base = BOSS_SIZE if lv == "boss" else MON_SIZES[i + 1]
            disp = base * 2.0        # GameData.RENDER_SCALE —— 今輪一步冇郁
            anc = anchors.get("%s_%s" % (fam, lv),
                              dict(bbox=[0.03, 0.15, 0.97, 1.0], area=0.5, side=base))
            img = place(r["cells"][i], disp, ss / 2.0, anc)
            img.save(os.path.join(dest, "%s_%s.png" % (fam, lv)))
            sizes.append(list(img.size))
        report[fam] = dict(sheet=fname, ok=True, sizes=sizes, mode=cfg["mode"],
                           d_hi=cfg["d_hi"], bg=[int(v) for v in r["bg"]])
        if args.debug:
            Image.fromarray((r["alpha"] * 255).astype(np.uint8), "L").save(
                os.path.join(QA, "alpha_%s.png" % fam))

    with open(os.path.join(QA, "report.json"), "w", encoding="utf-8") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print("out -> " + dest)


if __name__ == "__main__":
    sys.exit(main())
