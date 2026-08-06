#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_art_monsters_v1.py — 【已封存,唔再用】程序生成怪物 sprite 嘅舊管線。

2026-08-06 嘅怪物美術升級輪之後,60 張怪物圖改為由 Jack 自己生成嘅 sprite
sheet 摳出嚟(見 `tools/monster_cutout.py` 同 `art_reference/monster/`)。
呢一份係第三輪重畫嗰套 Pillow 程序畫法嘅完整存檔 —— 唔會再行,亦唔會再入
build:`gen_art.py` 嘅 `main()` 冇再叫 `gen_monsters()`,所以 `assets/generated/
monsters/` 唔會再俾佢覆蓋。

呢個檔淨係讀嘅。要行返嘅話要自己由 gen_art.py 借返 Canvas / render / save /
shade / mix / WHITE 等等 helper —— 呢度冇 import,係刻意嘅:唔想有人一時手快
`python tools/deprecated/...` 就冚咗成套新美術。
"""

# ---------------------------------------------------------------------------
# 以下由 tools/gen_art.py 原封不動搬過嚟(2026-08-06)
# ---------------------------------------------------------------------------

# ============================================================================
# MONSTER FAMILIES
# ============================================================================
# Each family draw fn signature: fn(c, lvl, feats, pal)
#   lvl   : 1..5 ; boss handled separately
#   feats : dict of legacy booleans (still passed, kept for compatibility)
#   pal   : level_ramp() dict — main body colour ladder for this level
#
# Progression design (rounds 3): every family climbs a clear ladder —
#   colour   pal deepens + shifts toward a striking family accent by lv5
#   kit      one accessory ADDED per level (no jumps), family-appropriate
#   size     +~8%/level via MON_SIZES (visual scale)
# Bosses are redesigned for THREAT: forward/predatory posture, silhouette
# broken by horns/claws/spikes/tattered cloth, glowing eyes, aura — never a
# plain fat oval.

def feats_for(lvl):
    return {"horns": lvl >= 3, "armor": lvl >= 4, "elite": lvl >= 5}


def level_ramp(basecol, accent, lvl):
    """Graded colour for level 1..5: interpolate base->accent and deepen so
    the family reads pale/plain at lv1 and richest/most-saturated at lv5."""
    t = (lvl - 1) / 4.0
    col = mix(basecol, accent, t)
    deepen = 1.0 + (lvl - 1) * 0.05
    return ramp(col, deepen)


# --- shared kit drawers (top-lit, outlined by the global dilation pass) ------

def chest_armor(c, cx, cy, w, h, steel=(158, 166, 182, 255), studs=True):
    """A fitted breastplate that hugs the torso (curved, not a floating box)."""
    dark = shade(steel, 0.6)
    c.poly([(cx - w, cy - h * 0.8), (cx, cy - h),
            (cx + w, cy - h * 0.8), (cx + w * 0.9, cy + h),
            (cx, cy + h * 1.15), (cx - w * 0.9, cy + h)], steel)
    c.poly([(cx - w, cy - h * 0.8), (cx, cy - h),
            (cx + w, cy - h * 0.8), (cx + w * 0.6, cy - h * 0.1),
            (cx, cy), (cx - w * 0.6, cy - h * 0.1)], mix(steel, WHITE, 0.4))
    c.line([(cx, cy - h), (cx, cy + h * 1.05)], dark, 0.014)
    if studs:
        for sx in (cx - w * 0.72, cx + w * 0.72):
            c.circle(sx, cy - h * 0.35, 0.016, mix(steel, WHITE, 0.5))
            c.circle(sx, cy - h * 0.35, 0.008, dark)


def pauldrons(c, cx, cy, spread, r, steel=(158, 166, 182, 255)):
    for sgn in (-1, 1):
        sx = cx + sgn * spread
        c.circle(sx, cy, r, steel)
        c.ellipse(sx, cy - r * 0.35, r * 0.8, r * 0.5, mix(steel, WHITE, 0.4))
        c.poly([(sx - r * 0.35, cy - r * 0.9), (sx, cy - r * 1.5),
                (sx + r * 0.35, cy - r * 0.9)], shade(steel, 0.7))  # spike


def helm(c, cx, y, w, h, steel=(158, 166, 182, 255)):
    dark = shade(steel, 0.6)
    c.rrect(cx - w, y - h, cx + w, y + h * 0.5, 0.04, steel)
    c.rrect(cx - w, y - h, cx + w, y - h * 0.2, 0.04, mix(steel, WHITE, 0.4))
    c.rect(cx - w, y + h * 0.1, cx + w, y + h * 0.28, dark)  # visor slot
    c.line([(cx, y - h), (cx, y - h * 1.4)], dark, 0.02)     # nose guard up
    c.poly([(cx - 0.02, y - h), (cx, y - h * 1.5),
            (cx + 0.02, y - h)], mix(steel, WHITE, 0.3))


def cape(c, cx, cy, w, drop, col):
    """Draw BEFORE the body: a torn cloak fanning out behind."""
    dark = shade(col, 0.7)
    c.poly([(cx - w, cy), (cx - w * 1.25, cy + drop * 0.75),
            (cx - w * 0.55, cy + drop * 0.6), (cx - w * 0.75, cy + drop),
            (cx - w * 0.2, cy + drop * 0.62),
            (cx, cy + drop * 0.95), (cx + w * 0.2, cy + drop * 0.62),
            (cx + w * 0.75, cy + drop), (cx + w * 0.55, cy + drop * 0.6),
            (cx + w * 1.25, cy + drop * 0.75), (cx + w, cy)], col)
    c.poly([(cx - w, cy), (cx - w * 0.5, cy + drop * 0.5),
            (cx, cy + drop * 0.3), (cx + w * 0.5, cy + drop * 0.5),
            (cx + w, cy)], mix(col, WHITE, 0.12))
    for dx in (-w * 0.5, 0, w * 0.5):
        c.line([(cx + dx, cy), (cx + dx * 0.7, cy + drop * 0.7)], dark, 0.01)


def back_spikes(c, xs, y, h, col):
    """A ridge of raised spikes (hackles / bone spurs) along a back."""
    line = mix(shade(col, 0.4), BLACK, 0.4)
    for i, bx in enumerate(xs):
        hh = h * (0.7 + 0.3 * (1 - abs(i - (len(xs) - 1) / 2.0) /
                               max(1, (len(xs) / 2.0))))
        c.poly([(bx - 0.045, y), (bx, y - hh), (bx + 0.045, y)], line)
        c.poly([(bx - 0.028, y - 0.005), (bx, y - hh * 0.9),
                (bx + 0.028, y - 0.005)], col)


def insect_legs(c, cx, top, bot, spread_in, spread_out, col, phase=0):
    """3 jointed legs per side sprouting from the BODY SIDE (not the belly).
    Each leg: coxa out to a knee, then a tapered shin angling down to a foot.
    `phase` shifts the two sides for a mid-stride alternating gait."""
    line = col
    ys = [top + (bot - top) * f for f in (0.12, 0.5, 0.86)]
    for si, sgn in enumerate((-1, 1)):
        stride = phase if sgn < 0 else -phase
        for i, ry in enumerate(ys):
            hipx = cx + sgn * spread_in
            kneex = cx + sgn * (spread_out * 0.72)
            kneey = ry - 0.06 + (0.02 if i == 1 else 0)
            footx = cx + sgn * (spread_out + 0.02 * (i - 1))
            footy = ry + 0.14 + stride * (1 if i % 2 == 0 else -1)
            # femur (thicker) then tibia (thinner) — clear knee joint
            c.line([(hipx, ry), (kneex, kneey)], line, 0.026)
            c.line([(kneex, kneey), (footx, footy)], line, 0.02)
            c.circle(kneex, kneey, 0.02, line)          # knee node
            c.circle(footx, footy, 0.015, line)         # foot


def armor_plate(c, cx, cy, w, h):  # legacy shim -> fitted breastplate
    chest_armor(c, cx, cy, w, h * 1.1)


# ---- 1 goblin --------------------------------------------------------------
# Ladder: grunt(bare) -> raider(club) -> cutthroat(hide+dagger) ->
#         soldier(iron plate+helm) -> warchief(full armour+horned helm+cape)
def _gob_tusks(c, cy, grow):
    for sgn in (-1, 1):
        bx = 0.5 + sgn * 0.045
        c.poly([(bx - 0.014, cy), (bx + 0.014, cy),
                (bx + sgn * 0.006, cy - 0.03 - grow)], WHITE)


def draw_goblin(c, lvl, feats, pal):
    body = pal["base"]
    hide = (122, 84, 46, 255)
    if lvl >= 5:
        cape(c, 0.5, 0.50, 0.20, 0.40, (150, 34, 44, 255))
    c.shadow()
    # crouched, hunched body (wider chest than belly = attitude, not a ball)
    c.poly([(0.30, 0.62), (0.5, 0.54), (0.70, 0.62),
            (0.66, 0.80), (0.5, 0.84), (0.34, 0.80)], body)
    c.ellipse(0.5, 0.60, 0.15, 0.10, pal["hi"])
    c.ellipse(0.5, 0.76, 0.17, 0.09, pal["shadow"])
    # loincloth
    c.poly([(0.40, 0.74), (0.60, 0.74), (0.57, 0.87),
            (0.5, 0.81), (0.43, 0.87)], hide)
    # bandy legs + clawed feet
    c.rrect(0.37, 0.80, 0.45, 0.92, 0.03, pal["shadow"])
    c.rrect(0.55, 0.80, 0.63, 0.92, 0.03, pal["shadow"])
    for fx in (0.41, 0.59):
        c.poly([(fx - 0.03, 0.92), (fx - 0.05, 0.95), (fx - 0.02, 0.93)],
               pal["shadow"])
    # arms: left hand claws forward, right hand holds weapon (lv>=2)
    c.line([(0.32, 0.62), (0.24, 0.74)], body, 0.05)
    for k in (-1, 0, 1):
        c.line([(0.24, 0.74), (0.20 + k * 0.02, 0.80)], pal["shadow"], 0.014)
    c.line([(0.68, 0.62), (0.76, 0.70)], body, 0.05)
    # head (jutting jaw, heavy brow)
    c.ellipse(0.5, 0.41, 0.185, 0.16, body)
    c.ellipse(0.5, 0.36, 0.13, 0.09, pal["hi"])
    # big swept-back ears
    for sgn in (-1, 1):
        c.poly([(0.5 + sgn * 0.15, 0.37), (0.5 + sgn * 0.40, 0.31),
                (0.5 + sgn * 0.18, 0.47)], body)
        c.poly([(0.5 + sgn * 0.16, 0.38), (0.5 + sgn * 0.31, 0.34),
                (0.5 + sgn * 0.18, 0.44)], pal["hi"])
    # heavy scowling brow
    c.poly([(0.34, 0.35), (0.5, 0.33), (0.66, 0.35),
            (0.64, 0.40), (0.5, 0.375), (0.36, 0.40)], pal["shadow"])
    # snarling snout + jagged mouth
    c.ellipse(0.5, 0.48, 0.10, 0.055, pal["shadow"])
    c.poly([(0.42, 0.49), (0.46, 0.51), (0.5, 0.49),
            (0.54, 0.51), (0.58, 0.49), (0.54, 0.53), (0.46, 0.53)], DARKLINE)
    _gob_tusks(c, 0.49, min(0.03, lvl * 0.006))
    # angry glaring eyes (yellow at higher levels)
    eg = (250, 210, 70, 255) if lvl >= 4 else None
    c.eyes(0.43, 0.57, 0.40, 0.030, glow=eg)
    # --- weapon ladder ---
    wood = (120, 82, 46, 255)
    if lvl == 2:                                   # wooden club
        c.line([(0.74, 0.70), (0.84, 0.48)], wood, 0.05)
        c.circle(0.85, 0.45, 0.07, wood)
        c.circle(0.83, 0.43, 0.028, (150, 108, 66, 255))
    elif lvl >= 3:                                 # curved iron blade
        c.line([(0.74, 0.70), (0.80, 0.56)], wood, 0.035)  # grip
        steel = (176, 184, 196, 255)
        c.poly([(0.78, 0.58), (0.94, 0.34), (0.98, 0.40),
                (0.86, 0.56), (0.82, 0.58)], steel)
        c.line([(0.80, 0.57), (0.93, 0.37)], mix(steel, WHITE, 0.5), 0.01)
    # --- armour ladder ---
    if lvl == 3:                                   # single hide pauldron
        c.circle(0.34, 0.60, 0.07, hide)
        c.ellipse(0.34, 0.58, 0.05, 0.03, mix(hide, WHITE, 0.3))
    if lvl >= 4:                                   # iron plate + pauldrons
        chest_armor(c, 0.5, 0.66, 0.15, 0.11)
        pauldrons(c, 0.5, 0.60, 0.20, 0.06)
    if lvl >= 4:                                   # helm
        helm(c, 0.5, 0.30, 0.12, 0.07)
    if lvl >= 5:                                   # warchief horns on helm + paint
        c.horns(0.5, 0.28, 0.11, 0.13, (60, 30, 34, 255), curve=0.12)
        c.line([(0.40, 0.45), (0.46, 0.47)], (210, 40, 46, 255), 0.02)
        c.line([(0.60, 0.45), (0.54, 0.47)], (210, 40, 46, 255), 0.02)


def draw_goblin_boss(c):
    pal = ramp((52, 168, 44), 1.12)
    hide = (116, 40, 44, 255)
    c.shadow(0.5, 0.95, 0.40, 0.06)
    # tattered war-banner cape behind
    cape(c, 0.5, 0.42, 0.30, 0.52, (150, 32, 40, 255))
    # broad-shouldered, forward-leaning brute (wide chest, tucked waist)
    c.poly([(0.22, 0.56), (0.5, 0.44), (0.78, 0.56),
            (0.70, 0.82), (0.5, 0.90), (0.30, 0.82)], pal["base"])
    c.poly([(0.28, 0.54), (0.5, 0.46), (0.72, 0.54),
            (0.62, 0.66), (0.5, 0.70), (0.38, 0.66)], pal["hi"])
    c.ellipse(0.5, 0.84, 0.24, 0.10, pal["shadow"])
    # massive arms, fists forward
    c.line([(0.24, 0.56), (0.14, 0.78)], pal["base"], 0.10)
    c.circle(0.14, 0.80, 0.08, pal["base"])
    c.line([(0.76, 0.56), (0.88, 0.74)], pal["base"], 0.10)
    # iron gauntlet fist + spiked mace
    c.circle(0.88, 0.76, 0.075, (150, 158, 172, 255))
    c.line([(0.86, 0.72), (0.80, 0.30)], (110, 78, 46, 255), 0.04)
    c.circle(0.79, 0.24, 0.10, (120, 128, 140, 255))
    for a in range(8):
        ang = a * math.pi / 4
        c.poly([(0.79 + math.cos(ang) * 0.08, 0.24 + math.sin(ang) * 0.08),
                (0.79 + math.cos(ang) * 0.14, 0.24 + math.sin(ang) * 0.14),
                (0.79 + math.cos(ang + 0.3) * 0.08,
                 0.24 + math.sin(ang + 0.3) * 0.08)], (150, 158, 172, 255))
    # heavy iron chestplate
    chest_armor(c, 0.5, 0.64, 0.22, 0.16)
    c.rect(0.34, 0.78, 0.66, 0.83, hide)
    c.line([(0.34, 0.805), (0.66, 0.805)], (240, 210, 70, 255), 0.016)
    # legs
    c.rrect(0.36, 0.86, 0.47, 0.96, 0.02, pal["shadow"])
    c.rrect(0.53, 0.86, 0.64, 0.96, 0.02, pal["shadow"])
    # low-slung snarling head
    c.ellipse(0.5, 0.40, 0.22, 0.19, pal["base"])
    c.ellipse(0.5, 0.35, 0.15, 0.10, pal["hi"])
    for sgn in (-1, 1):
        c.poly([(0.5 + sgn * 0.19, 0.36), (0.5 + sgn * 0.46, 0.28),
                (0.5 + sgn * 0.22, 0.48)], pal["base"])
    c.poly([(0.30, 0.34), (0.5, 0.31), (0.70, 0.34),
            (0.67, 0.40), (0.5, 0.365), (0.33, 0.40)], pal["shadow"])
    # jagged fanged maw
    c.ellipse(0.5, 0.49, 0.13, 0.07, (40, 20, 22, 255))
    for tx in (0.40, 0.46, 0.54, 0.60):
        c.poly([(tx - 0.02, 0.46), (tx, 0.52), (tx + 0.02, 0.46)], WHITE)
    for tx in (0.43, 0.5, 0.57):
        c.poly([(tx - 0.02, 0.53), (tx, 0.47), (tx + 0.02, 0.53)], WHITE)
    c.eyes(0.41, 0.59, 0.37, 0.05, glow=(255, 200, 60, 255))
    # horned war-helm + crown
    helm(c, 0.5, 0.28, 0.16, 0.09)
    c.horns(0.5, 0.24, 0.15, 0.20, (46, 26, 28, 255), curve=0.16)
    c.crown(0.5, 0.15, 0.16)


# ---- 2 wolf ----------------------------------------------------------------
# Ladder: pup -> hunter(darker) -> raised hackles -> scarred+collar ->
#         frost alpha(mane+aura). Stalking side profile, low head — a predator.
def draw_wolf(c, lvl, feats, pal):
    fur = pal["base"]
    if lvl >= 5:
        c.aura(0.5, 0.58, 0.32, (150, 200, 245))
    c.shadow(0.5, 0.9, 0.34, 0.06)
    # long lean torso, chest higher than haunch (stalking)
    c.poly([(0.18, 0.66), (0.26, 0.54), (0.50, 0.52),
            (0.72, 0.56), (0.80, 0.66), (0.70, 0.72),
            (0.30, 0.72)], fur)
    c.ellipse(0.46, 0.58, 0.22, 0.08, pal["hi"])
    c.ellipse(0.5, 0.70, 0.26, 0.06, pal["shadow"])
    # 4 long legs (front pair forward, hind pair back) with paws
    for lx, fwd in ((0.30, 0.02), (0.40, -0.01), (0.60, 0.01), (0.70, 0.03)):
        c.line([(lx, 0.68), (lx + fwd, 0.90)], pal["shadow"], 0.032)
        c.circle(lx + fwd, 0.90, 0.024, pal["shadow"])
    # bushy low tail
    c.poly([(0.18, 0.62), (0.05, 0.70), (0.10, 0.56), (0.22, 0.60)], fur)
    c.poly([(0.16, 0.60), (0.09, 0.62), (0.13, 0.57)], pal["hi"])
    # lowered head reaching forward
    c.ellipse(0.74, 0.52, 0.15, 0.13, fur)
    c.ellipse(0.73, 0.48, 0.10, 0.07, pal["hi"])
    # pinned-back ears
    for sgn in (-1, 1):
        c.poly([(0.70 + sgn * 0.04, 0.42), (0.66 + sgn * 0.05, 0.30),
                (0.74 + sgn * 0.03, 0.42)], fur)
    # long snout, slightly open, bared fang
    c.poly([(0.80, 0.48), (0.99, 0.52), (0.97, 0.58), (0.80, 0.58)],
           pal["shadow"])
    c.circle(0.985, 0.505, 0.026, DARKLINE)          # nose
    c.line([(0.84, 0.555), (0.97, 0.565)], DARKLINE, 0.01)
    c.poly([(0.86, 0.555), (0.875, 0.60), (0.845, 0.585)], WHITE)  # fang
    c.poly([(0.92, 0.56), (0.935, 0.60), (0.905, 0.585)], WHITE)
    c.eyes(0.70, 0.79, 0.49, 0.026, glow=(250, 220, 90, 255)
           if lvl < 5 else (150, 210, 245, 255))
    # --- ladder ---
    if lvl >= 3:                                   # raised hackles along spine
        back_spikes(c, [0.32, 0.42, 0.52, 0.62], 0.53, 0.14, pal["shadow"])
    if lvl >= 4:                                   # spiked bone collar + scar
        for a in range(5):
            sx = 0.60 + (a - 2) * 0.04
            c.poly([(sx - 0.02, 0.58), (sx, 0.63), (sx + 0.02, 0.58)],
                   (210, 205, 190, 255))
        c.line([(0.70, 0.45), (0.78, 0.55)], (232, 220, 220, 255), 0.012)
    if lvl >= 5:                                   # frost breath
        for fx, fy, r in ((1.0, 0.55, 0.02), (1.03, 0.52, 0.015),
                          (1.02, 0.58, 0.012)):
            c.circle(fx, fy, r, (200, 235, 250, 200))


def draw_wolf_boss(c):
    pal = ramp((104, 122, 156), 1.08)
    fur = pal["base"]
    c.shadow(0.5, 0.94, 0.44, 0.06)
    c.aura(0.5, 0.54, 0.40, (155, 205, 248))
    # huge lunging dire-wolf: haunches coiled low-left, head lunging up-right
    c.poly([(0.10, 0.74), (0.20, 0.54), (0.42, 0.44),
            (0.66, 0.42), (0.84, 0.52), (0.88, 0.66),
            (0.72, 0.74), (0.28, 0.78)], fur)
    c.ellipse(0.44, 0.54, 0.26, 0.10, pal["hi"])
    c.ellipse(0.5, 0.72, 0.32, 0.07, pal["shadow"])
    # powerful legs + claws
    for lx, fwd in ((0.22, -0.02), (0.36, -0.03), (0.64, 0.04), (0.78, 0.06)):
        c.line([(lx, 0.70), (lx + fwd, 0.94)], pal["shadow"], 0.05)
        for k in (-1, 0, 1):
            c.poly([(lx + fwd + k * 0.02, 0.94), (lx + fwd + k * 0.02, 0.98),
                    (lx + fwd + k * 0.02 + 0.012, 0.95)], DARKLINE)
    # towering frost mane
    back_spikes(c, [0.24, 0.32, 0.40, 0.48, 0.56], 0.44, 0.26,
                mix(fur, (150, 195, 240, 255), 0.4))
    # tail
    c.poly([(0.10, 0.70), (-0.02, 0.82), (0.02, 0.60), (0.16, 0.66)], fur)
    # massive head, jaws agape
    c.ellipse(0.74, 0.46, 0.21, 0.19, fur)
    c.ellipse(0.72, 0.40, 0.14, 0.10, pal["hi"])
    for sgn in (-1, 1):
        c.poly([(0.70 + sgn * 0.06, 0.32), (0.66 + sgn * 0.08, 0.16),
                (0.76 + sgn * 0.04, 0.32)], fur)
    # gaping fanged maw
    c.poly([(0.82, 0.40), (1.02, 0.44), (1.0, 0.52), (0.82, 0.52)],
           pal["shadow"])
    c.circle(1.01, 0.43, 0.03, DARKLINE)
    c.poly([(0.83, 0.52), (1.0, 0.56), (0.98, 0.66), (0.84, 0.62)],
           (60, 30, 40, 255))  # open lower jaw / mouth
    for tx in (0.86, 0.92, 0.98):
        c.poly([(tx - 0.02, 0.52), (tx, 0.60), (tx + 0.02, 0.52)], WHITE)
        c.poly([(tx - 0.015, 0.62), (tx, 0.55), (tx + 0.015, 0.62)], WHITE)
    c.eyes(0.68, 0.80, 0.42, 0.045, glow=(150, 215, 250, 255))
    c.line([(0.66, 0.34), (0.76, 0.50)], (235, 225, 225, 255), 0.016)  # scar
    # frost breath plume
    for fx, fy, r in ((1.05, 0.5, 0.05), (1.12, 0.46, 0.035),
                      (1.1, 0.56, 0.03), (1.16, 0.52, 0.02)):
        c.circle(fx, fy, r, (200, 235, 250, 190))


# ---- 3 skeleton ------------------------------------------------------------
# Ladder: rattler -> shiv-wielder -> horned(A2 fix) -> rusted armour+blade ->
#         necromancer(soul crown+aura). Horns grow FROM the skull, never float.
def _skull(c, cx, cy, r, bone, glow):
    bsh = shade(bone, 0.74)
    c.ellipse(cx, cy, r, r, bone)
    c.ellipse(cx, cy - r * 0.32, r * 0.72, r * 0.55, mix(bone, WHITE, 0.3))
    # brow ridge for a grim look
    c.line([(cx - r * 0.7, cy - r * 0.05), (cx - r * 0.15, cy - r * 0.2)],
           bsh, r * 0.12)
    c.line([(cx + r * 0.7, cy - r * 0.05), (cx + r * 0.15, cy - r * 0.2)],
           bsh, r * 0.12)
    # jaw
    c.rrect(cx - r * 0.62, cy + r * 0.5, cx + r * 0.62, cy + r * 0.95,
            r * 0.12, bone)
    for jx in (cx - r * 0.3, cx, cx + r * 0.3):
        c.line([(jx, cy + r * 0.5), (jx, cy + r * 0.9)], bsh, r * 0.08)
    # deep glowing sockets
    for sgn in (-1, 1):
        ex = cx + sgn * r * 0.42
        c.circle(ex, cy + r * 0.12, r * 0.28, DARKLINE)
        c.circle(ex, cy + r * 0.12, r * 0.15, glow)
        c.circle(ex, cy + r * 0.08, r * 0.06, mix(glow, WHITE, 0.6))
    c.poly([(cx, cy + r * 0.2), (cx - r * 0.12, cy + r * 0.42),
            (cx + r * 0.12, cy + r * 0.42)], DARKLINE)  # nose


def draw_skeleton(c, lvl, feats, pal):
    bone = mix(pal["base"], (234, 232, 218, 255), 0.55)
    bsh = shade(bone, 0.74)
    glow = (150, 130, 235, 255) if lvl >= 5 else (120, 235, 190, 255)
    if lvl >= 5:
        c.aura(0.5, 0.5, 0.46, (120, 90, 205))
        # tattered shroud over shoulders
        c.poly([(0.28, 0.52), (0.22, 0.86), (0.34, 0.72),
                (0.5, 0.88), (0.66, 0.72), (0.78, 0.86),
                (0.72, 0.52)], (58, 46, 92, 235))
    c.shadow()
    # hunched shoulders
    c.line([(0.34, 0.54), (0.66, 0.54)], bone, 0.05)
    c.circle(0.34, 0.54, 0.035, bone)
    c.circle(0.66, 0.54, 0.035, bone)
    # ribcage
    c.ellipse(0.5, 0.65, 0.15, 0.16, bsh)
    c.line([(0.5, 0.54), (0.5, 0.76)], bone, 0.028)   # spine
    for ry in (0.58, 0.64, 0.70):
        c.line([(0.40, ry), (0.60, ry - 0.005)], bone, 0.024)
    # pelvis + legs
    c.line([(0.44, 0.76), (0.42, 0.92)], bone, 0.03)
    c.line([(0.56, 0.76), (0.58, 0.92)], bone, 0.03)
    for fx in (0.42, 0.58):
        c.line([(fx, 0.92), (fx + 0.03, 0.93)], bone, 0.02)
    # left arm hangs; right arm raised with weapon at lv>=2
    c.line([(0.34, 0.55), (0.28, 0.74)], bone, 0.024)
    if lvl >= 2:
        c.line([(0.66, 0.55), (0.74, 0.44)], bone, 0.024)   # raised forearm
    else:
        c.line([(0.66, 0.55), (0.72, 0.74)], bone, 0.024)
    # skull
    _skull(c, 0.5, 0.40, 0.15, bone, glow)
    # --- weapon / armour ladder ---
    if lvl == 2:                                   # jagged bone shiv
        c.poly([(0.74, 0.44), (0.80, 0.24), (0.78, 0.44)], bone)
    elif lvl >= 4:                                 # rusted curved blade
        c.line([(0.74, 0.44), (0.78, 0.34)], (110, 84, 60, 255), 0.03)
        rust = (150, 120, 120, 255)
        c.poly([(0.76, 0.36), (0.90, 0.14), (0.94, 0.20),
                (0.82, 0.36)], rust)
    if lvl >= 4:                                   # rusted shoulder pauldron
        c.circle(0.34, 0.54, 0.07, (128, 108, 96, 255))
        c.poly([(0.30, 0.50), (0.34, 0.42), (0.38, 0.50)], (150, 120, 120, 255))
    if lvl >= 3:                                   # bone horns rooted in skull
        c.horns(0.5, 0.27, 0.11, 0.15, bone, curve=0.11)
    if lvl >= 5:                                   # soul crown
        c.crown(0.5, 0.22, 0.13, (170, 140, 240, 255))


def draw_skeleton_boss(c):
    bone = (236, 234, 220, 255)
    bsh = shade(bone, 0.72)
    glow = (150, 255, 210, 255)
    c.shadow(0.5, 0.95, 0.38, 0.06)
    c.aura(0.5, 0.5, 0.54, (110, 70, 195))
    # ragged death-shroud framing the silhouette
    c.poly([(0.16, 0.44), (0.10, 0.94), (0.26, 0.72),
            (0.38, 0.96), (0.5, 0.74), (0.62, 0.96),
            (0.74, 0.72), (0.90, 0.94), (0.84, 0.44)], (48, 38, 82, 240))
    c.poly([(0.24, 0.46), (0.20, 0.80), (0.34, 0.64),
            (0.5, 0.70), (0.66, 0.64), (0.80, 0.80),
            (0.76, 0.46)], (70, 56, 112, 235))
    # broad bone shoulders
    c.line([(0.28, 0.50), (0.72, 0.50)], bone, 0.06)
    for sgn in (-1, 1):
        c.circle(0.5 + sgn * 0.22, 0.50, 0.06, bone)
        c.poly([(0.5 + sgn * 0.26, 0.48), (0.5 + sgn * 0.30, 0.34),
                (0.5 + sgn * 0.20, 0.48)], bsh)   # spur
    # ribcage
    c.ellipse(0.5, 0.68, 0.20, 0.20, bsh)
    c.line([(0.5, 0.52), (0.5, 0.82)], bone, 0.04)
    for ry in (0.58, 0.66, 0.74):
        c.line([(0.34, ry), (0.66, ry - 0.006)], bone, 0.03)
    # clawed arms — right hand raises a bone scythe
    c.line([(0.28, 0.50), (0.18, 0.74)], bone, 0.035)
    c.line([(0.72, 0.50), (0.82, 0.34)], bone, 0.035)
    c.line([(0.80, 0.36), (0.86, 0.10)], (110, 84, 60, 255), 0.03)  # snath
    c.poly([(0.86, 0.12), (0.60, 0.06), (0.70, 0.16), (0.86, 0.20)],
           mix(bone, (200, 235, 220, 255), 0.4))  # curved blade
    # legs
    c.line([(0.42, 0.82), (0.40, 0.96)], bone, 0.04)
    c.line([(0.58, 0.82), (0.60, 0.96)], bone, 0.04)
    # commanding skull with horns rooted in the crown of the skull
    _skull(c, 0.5, 0.38, 0.20, bone, glow)
    c.horns(0.5, 0.26, 0.16, 0.26, bsh, curve=0.20, base=0.038)
    c.crown(0.5, 0.18, 0.18, (170, 140, 245, 255))


# ---- 4 golem ---------------------------------------------------------------
# Ladder: rubble -> mossy -> shoulder shards -> molten cracks -> lava core+crown
def draw_golem(c, lvl, feats, pal):
    rock = pal["base"]
    crack = (255, 168, 60, 255)
    if lvl >= 5:
        c.aura(0.5, 0.62, 0.30, (255, 150, 55))
    c.shadow(0.5, 0.93, 0.34, 0.05)
    # hunched: massive shoulders, narrower waist, big fists low
    c.poly([(0.24, 0.50), (0.5, 0.42), (0.76, 0.50),
            (0.70, 0.82), (0.5, 0.86), (0.30, 0.82)], rock)
    c.poly([(0.28, 0.48), (0.5, 0.44), (0.72, 0.48),
            (0.64, 0.60), (0.5, 0.62), (0.36, 0.60)], pal["hi"])
    c.rrect(0.32, 0.74, 0.68, 0.84, 0.05, pal["shadow"])
    # arms + boulder fists resting near the ground
    c.rrect(0.10, 0.52, 0.24, 0.78, 0.05, rock)
    c.rrect(0.76, 0.52, 0.90, 0.78, 0.05, rock)
    c.circle(0.16, 0.82, 0.10, rock)
    c.circle(0.84, 0.82, 0.10, rock)
    c.ellipse(0.16, 0.79, 0.06, 0.04, pal["hi"])
    c.ellipse(0.84, 0.79, 0.06, 0.04, pal["hi"])
    # stumpy legs
    c.rrect(0.36, 0.84, 0.47, 0.94, 0.03, pal["shadow"])
    c.rrect(0.53, 0.84, 0.64, 0.94, 0.03, pal["shadow"])
    # heavy brow block head, sunk between shoulders
    c.rrect(0.38, 0.26, 0.62, 0.48, 0.05, rock)
    c.rrect(0.38, 0.26, 0.62, 0.34, 0.05, pal["hi"])
    c.rect(0.38, 0.36, 0.62, 0.40, pal["shadow"])  # brow shadow
    c.eyes(0.45, 0.55, 0.42, 0.028,
           glow=(255, 190, 70, 255) if lvl >= 4 else (250, 235, 130, 255))
    # --- ladder ---
    if lvl in (2, 3):                              # moss patches
        moss = (86, 132, 66, 255)
        for mx, my, r in ((0.34, 0.50, 0.05), (0.66, 0.66, 0.045),
                          (0.5, 0.44, 0.04)):
            c.ellipse(mx, my, r, r * 0.6, moss)
    if lvl >= 3:                                   # jagged shoulder shards
        for sgn in (-1, 1):
            bx = 0.5 + sgn * 0.24
            c.poly([(bx - 0.07, 0.50), (bx, 0.30), (bx + 0.07, 0.50)],
                   pal["shadow"])
            c.poly([(bx - 0.04, 0.49), (bx + sgn * 0.01, 0.34),
                    (bx + 0.04, 0.49)], rock)
    if lvl >= 4:                                   # molten cracks
        c.line([(0.42, 0.52), (0.5, 0.66), (0.44, 0.80)], crack, 0.02)
        c.line([(0.60, 0.52), (0.56, 0.70)], crack, 0.016)
    if lvl >= 5:                                   # exposed lava core + crown
        c.circle(0.5, 0.62, 0.06, (255, 140, 40, 255))
        c.circle(0.5, 0.62, 0.03, (255, 235, 150, 255))
        for sgn in (-1, 1):                        # crystal spikes as a crown
            c.poly([(0.5 + sgn * 0.03, 0.26), (0.5 + sgn * 0.06, 0.14),
                    (0.5 + sgn * 0.09, 0.26)], (150, 210, 235, 255))
        c.poly([(0.47, 0.26), (0.5, 0.10), (0.53, 0.26)], (170, 225, 245, 255))


def draw_golem_boss(c):
    pal = ramp((150, 116, 92), 1.02)
    crack = (255, 150, 45, 255)
    c.shadow(0.5, 0.95, 0.46, 0.05)
    c.aura(0.5, 0.60, 0.34, (255, 130, 40))
    # colossus hunched forward, knuckle-planted — a mountain about to swing
    c.poly([(0.16, 0.44), (0.5, 0.34), (0.84, 0.44),
            (0.78, 0.80), (0.5, 0.86), (0.22, 0.80)], pal["base"])
    c.poly([(0.22, 0.42), (0.5, 0.36), (0.78, 0.42),
            (0.68, 0.56), (0.5, 0.58), (0.32, 0.56)], pal["hi"])
    c.rrect(0.28, 0.70, 0.72, 0.82, 0.06, pal["shadow"])
    # enormous arms + boulder fists on the ground
    c.rrect(0.02, 0.46, 0.20, 0.82, 0.06, pal["base"])
    c.rrect(0.80, 0.46, 0.98, 0.82, 0.06, pal["base"])
    c.circle(0.11, 0.86, 0.13, pal["base"])
    c.circle(0.89, 0.86, 0.13, pal["base"])
    c.ellipse(0.11, 0.82, 0.08, 0.05, pal["hi"])
    c.ellipse(0.89, 0.82, 0.08, 0.05, pal["hi"])
    # jagged mountain shards across the shoulders/back
    for sgn in (-1, 1):
        for dx, h in ((0.30, 0.22), (0.22, 0.16), (0.14, 0.12)):
            bx = 0.5 + sgn * dx
            c.poly([(bx - 0.06, 0.44), (bx, 0.44 - h),
                    (bx + 0.06, 0.44)], pal["shadow"])
    # head with heavy brow
    c.rrect(0.36, 0.20, 0.64, 0.44, 0.06, pal["base"])
    c.rrect(0.36, 0.20, 0.64, 0.30, 0.06, pal["hi"])
    c.rect(0.36, 0.33, 0.64, 0.38, pal["shadow"])
    c.eyes(0.43, 0.57, 0.40, 0.05, glow=(255, 205, 90, 255))
    # blazing molten core + cracks (the threat glow, not a muddy halo)
    c.circle(0.5, 0.60, 0.09, (255, 130, 35, 255))
    c.circle(0.5, 0.60, 0.05, (255, 240, 170, 255))
    c.line([(0.34, 0.46), (0.44, 0.60), (0.36, 0.80)], crack, 0.02)
    c.line([(0.66, 0.46), (0.56, 0.62), (0.64, 0.80)], crack, 0.02)
    c.line([(0.5, 0.44), (0.5, 0.52)], crack, 0.016)
    # crystal crown
    for k in (-2, -1, 0, 1, 2):
        c.poly([(0.5 + k * 0.05 - 0.03, 0.20), (0.5 + k * 0.05, 0.08 + abs(k) * 0.02),
                (0.5 + k * 0.05 + 0.03, 0.20)], (160, 220, 240, 255))


# ---- 5 ghost ---------------------------------------------------------------
# ---- 5 ghost ---------------------------------------------------------------
# Ladder: wisp -> haunt(glow) -> flame-crowned -> clawed wraith(aura) ->
#         shackled spectre(crown+chains). Jagged tattered hem, hollow eyes.
def draw_ghost(c, lvl, feats, pal):
    body = (pal["base"][0], pal["base"][1], pal["base"][2], 235)
    hi = mix(body, WHITE, 0.4)
    hollow = mix(body, DARKLINE, 0.82)
    if lvl >= 4:
        c.aura(0.5, 0.44, 0.4, (150, 232, 242))
    c.shadow(0.5, 0.9, 0.18, 0.04)
    # hooded upper body
    c.ellipse(0.5, 0.42, 0.22, 0.24, body)
    c.ellipse(0.5, 0.33, 0.14, 0.12, hi)
    # jagged tattered hem (sharper with level)
    teeth = 5 + lvl
    pts = [(0.28, 0.52)]
    for i in range(teeth + 1):
        x = 0.28 + 0.44 * i / teeth
        y = 0.62 + (0.16 if i % 2 else 0.04) + lvl * 0.006
        pts.append((x, y))
    pts.append((0.72, 0.52))
    c.poly(pts, mix(body, (110, 185, 210, 235), 0.35))
    # spectral arms — wisps at low level, clawed hands at high
    for sgn in (-1, 1):
        ax = 0.5 + sgn * 0.22
        if lvl >= 4:
            c.line([(0.5 + sgn * 0.14, 0.44), (ax, 0.58)], body, 0.05)
            for k in (-1, 0, 1):                 # three claws
                c.poly([(ax + k * 0.03, 0.58), (ax + k * 0.03 + sgn * 0.01, 0.66),
                        (ax + k * 0.03 + 0.012, 0.59)], hollow)
        else:
            c.ellipse(ax + sgn * 0.02, 0.48, 0.055, 0.09, body)
    # hollow glowing eyes + wailing mouth
    for ex in (0.43, 0.57):
        c.ellipse(ex, 0.40, 0.038, 0.055, hollow)
        c.circle(ex, 0.395, 0.016, mix(body, WHITE, 0.7))
    c.ellipse(0.5, 0.51, 0.032, 0.05, hollow)
    # --- ladder ---
    if lvl >= 3:                                   # soul-flame crown (connected)
        for sgn in (-1, 0, 1):
            fx = 0.5 + sgn * 0.13
            c.poly([(fx - 0.05, 0.24), (fx, 0.10 - abs(sgn) * 0.02),
                    (fx + 0.05, 0.24)], body)
            c.poly([(fx - 0.025, 0.23), (fx, 0.15),
                    (fx + 0.025, 0.23)], mix(body, (150, 250, 255, 235), 0.5))
    if lvl >= 5:                                   # spectral crown + hanging chain
        c.crown(0.5, 0.14, 0.13, (160, 245, 255, 255))
        for lx in (0.36, 0.42, 0.48):
            c.circle(lx, 0.72 + (lx - 0.36) * 0.3, 0.014, (150, 160, 168, 220))


def draw_ghost_boss(c):
    body = (150, 226, 238, 232)
    hi = mix(body, WHITE, 0.4)
    dark = mix(body, (70, 130, 165, 225), 0.55)
    hollow = (14, 30, 40, 255)
    c.shadow(0.5, 0.94, 0.22, 0.05)
    c.aura(0.5, 0.36, 0.42, (150, 235, 248))
    # reaching skeletal claws BEHIND the cowl (drawn first)
    for sgn in (-1, 1):
        hx = 0.5 + sgn * 0.34
        c.line([(0.5 + sgn * 0.14, 0.40), (hx, 0.30)], body, 0.045)
        for k in (-1, 0, 1):
            c.poly([(hx + k * 0.035, 0.30),
                    (hx + sgn * 0.05 + k * 0.035, 0.14),
                    (hx + k * 0.035 + sgn * 0.014, 0.31)], body)
    # towering pointed cowl — tall, angular, NOT round
    c.poly([(0.5, 0.05), (0.30, 0.34), (0.28, 0.50),
            (0.5, 0.44), (0.72, 0.50), (0.70, 0.34)], body)
    c.poly([(0.5, 0.09), (0.38, 0.32), (0.5, 0.30), (0.62, 0.32)], hi)
    # long jagged shroud falling to sharp tendrils
    pts = [(0.28, 0.46)]
    for i in range(11):
        x = 0.28 + 0.44 * i / 10
        y = 0.70 + (0.26 if i % 2 else 0.04)
        pts.append((x, y))
    pts.append((0.72, 0.46))
    c.poly(pts, dark)
    c.poly([(0.34, 0.46), (0.34, 0.66), (0.5, 0.60), (0.66, 0.66),
            (0.66, 0.46)], body)
    # deep hood void with angled, wrathful glowing eyes
    c.poly([(0.36, 0.24), (0.5, 0.20), (0.64, 0.24),
            (0.62, 0.42), (0.5, 0.46), (0.38, 0.42)], hollow)
    for sgn in (-1, 1):
        ex = 0.5 + sgn * 0.10
        # slanted angry eye (triangle wedge)
        c.poly([(ex - sgn * 0.06, 0.28), (ex + sgn * 0.05, 0.31),
                (ex - sgn * 0.02, 0.37)], (170, 255, 255, 255))
        c.poly([(ex - sgn * 0.04, 0.30), (ex + sgn * 0.02, 0.32),
                (ex - sgn * 0.02, 0.35)], WHITE)
    # gaping wail
    c.poly([(0.46, 0.40), (0.54, 0.40), (0.52, 0.50), (0.5, 0.52),
            (0.48, 0.50)], hollow)
    c.crown(0.5, 0.05, 0.15, (170, 250, 255, 255))


# ---- 6 bat -----------------------------------------------------------------
# Ladder: bat -> broad-wing -> horned -> fur-ruff+claws -> vampire(crown+aura)
def draw_bat(c, lvl, feats, pal):
    body = pal["base"]
    if lvl >= 5:
        c.aura(0.5, 0.5, 0.42, (180, 90, 180))
    c.shadow(0.5, 0.88, 0.18, 0.04)
    # wings grow span with level
    span = 0.36 + lvl * 0.015
    c.wings(0.5, 0.48, span, body, up=0.16 + lvl * 0.006)
    # clawed wing thumbs at higher level
    if lvl >= 4:
        for sgn in (-1, 1):
            tx = 0.5 + sgn * span
            c.poly([(tx, 0.34), (tx + sgn * 0.03, 0.28), (tx - sgn * 0.01, 0.36)],
                   pal["shadow"])
    # body (tapered, not a ball)
    c.poly([(0.40, 0.44), (0.60, 0.44), (0.56, 0.62), (0.5, 0.70),
            (0.44, 0.62)], body)
    c.ellipse(0.5, 0.46, 0.08, 0.07, pal["hi"])
    # tall pointed ears
    c.poly([(0.42, 0.40), (0.39, 0.24), (0.49, 0.38)], body)
    c.poly([(0.58, 0.40), (0.61, 0.24), (0.51, 0.38)], body)
    c.poly([(0.43, 0.39), (0.41, 0.29), (0.47, 0.38)], pal["hi"])
    c.poly([(0.57, 0.39), (0.59, 0.29), (0.53, 0.38)], pal["hi"])
    # glaring eyes (redden with level)
    eg = (255, 110, 90, 255) if lvl >= 4 else (250, 210, 90, 255)
    c.eyes(0.45, 0.55, 0.46, 0.030, glow=eg)
    # snarl + fangs (bigger with level)
    fl = 0.05 + lvl * 0.006
    c.poly([(0.47, 0.55), (0.485, 0.55 + fl), (0.455, 0.54 + fl * 0.8)], WHITE)
    c.poly([(0.53, 0.55), (0.515, 0.55 + fl), (0.545, 0.54 + fl * 0.8)], WHITE)
    # clawed feet
    for fx in (0.45, 0.55):
        c.line([(fx, 0.68), (fx, 0.74)], pal["shadow"], 0.016)
        c.poly([(fx - 0.02, 0.74), (fx, 0.78), (fx + 0.02, 0.74)], pal["shadow"])
    # --- ladder ---
    if lvl >= 3:                                   # horns rooted on the head
        c.horns(0.5, 0.30, 0.07, 0.09, pal["shadow"], curve=0.06, base=0.02)
    if lvl >= 4:                                   # fur ruff / collar (not a box)
        ruff = shade(body, 0.75)
        for k in (-2, -1, 0, 1, 2):
            rx = 0.5 + k * 0.045
            c.poly([(rx - 0.03, 0.56), (rx, 0.63), (rx + 0.03, 0.56)], ruff)
    if lvl >= 5:                                   # vampire crown
        c.crown(0.5, 0.20, 0.10, (225, 160, 250, 255))


def draw_bat_boss(c):
    pal = ramp((150, 54, 150), 1.05)
    c.shadow(0.5, 0.92, 0.26, 0.05)
    c.aura(0.5, 0.5, 0.5, (185, 70, 185))
    # vast cape-like wings enveloping the frame (draped, membranous)
    for sgn in (-1, 1):
        c.poly([(0.5 + sgn * 0.03, 0.40),
                (0.5 + sgn * 0.46, 0.30),
                (0.5 + sgn * 0.42, 0.56),
                (0.5 + sgn * 0.46, 0.60),
                (0.5 + sgn * 0.30, 0.62),
                (0.5 + sgn * 0.34, 0.74),
                (0.5 + sgn * 0.18, 0.66),
                (0.5 + sgn * 0.20, 0.80),
                (0.5 + sgn * 0.06, 0.68)], pal["base"])
        # wing finger struts
        for fx in (0.30, 0.42):
            c.line([(0.5 + sgn * 0.05, 0.44),
                    (0.5 + sgn * fx, 0.34 + fx * 0.4)],
                   shade(pal["base"], 0.7), 0.012)
        c.poly([(0.5 + sgn * 0.46, 0.30), (0.5 + sgn * 0.52, 0.24),
                (0.5 + sgn * 0.44, 0.34)], pal["shadow"])  # wing claw
    # lean upright body
    c.poly([(0.42, 0.42), (0.58, 0.42), (0.55, 0.66), (0.5, 0.76),
            (0.45, 0.66)], pal["base"])
    c.ellipse(0.5, 0.46, 0.09, 0.10, pal["hi"])
    # tall ears + rooted horns
    c.poly([(0.40, 0.36), (0.36, 0.14), (0.48, 0.34)], pal["base"])
    c.poly([(0.60, 0.36), (0.64, 0.14), (0.52, 0.34)], pal["base"])
    c.horns(0.5, 0.32, 0.10, 0.12, pal["shadow"], curve=0.08, base=0.028)
    # burning eyes + fanged snarl
    c.eyes(0.44, 0.56, 0.44, 0.045, glow=(255, 70, 70, 255))
    c.ellipse(0.5, 0.55, 0.06, 0.035, (40, 16, 30, 255))
    c.poly([(0.45, 0.54), (0.47, 0.64), (0.43, 0.60)], WHITE)
    c.poly([(0.55, 0.54), (0.53, 0.64), (0.57, 0.60)], WHITE)
    # clawed feet
    for fx in (0.44, 0.56):
        c.poly([(fx - 0.03, 0.74), (fx, 0.82), (fx + 0.03, 0.74)], pal["shadow"])
    c.crown(0.5, 0.12, 0.15, (230, 170, 255, 255))


# ---- 7 treant --------------------------------------------------------------
# Ladder: sapling -> leafed -> antlered -> bark-armour+roots -> blossom elder
def draw_treant(c, lvl, feats, pal):
    bark = pal["base"]
    barks = shade(bark, 0.72)
    barkh = mix(bark, (180, 140, 90, 255), 0.5)
    leaf = mix((96, 168, 62, 255), (44, 118, 44, 255), (lvl - 1) * 0.2)
    if lvl >= 5:
        c.aura(0.5, 0.4, 0.48, (120, 205, 95))
    c.shadow(0.5, 0.92, 0.28, 0.06)
    # trunk (widens a touch with level)
    tw = 0.11 + lvl * 0.006
    c.rrect(0.5 - tw, 0.46, 0.5 + tw, 0.86, 0.05, bark)
    c.rrect(0.5 - tw, 0.46, 0.5 - tw * 0.35, 0.86, 0.05, barkh)
    c.line([(0.5, 0.50), (0.5, 0.84)], barks, 0.018)
    # roots (more at lv>=4)
    c.poly([(0.5 - tw, 0.84), (0.30, 0.95), (0.5 - tw + 0.06, 0.88)], barks)
    c.poly([(0.5 + tw, 0.84), (0.70, 0.95), (0.5 + tw - 0.06, 0.88)], barks)
    if lvl >= 4:
        c.poly([(0.44, 0.88), (0.40, 0.96), (0.48, 0.90)], barks)
        c.poly([(0.56, 0.88), (0.60, 0.96), (0.52, 0.90)], barks)
    # gnarled twig arms (raise with level)
    ay = 0.56 - lvl * 0.01
    c.line([(0.5 - tw, 0.56), (0.24, ay)], bark, 0.022)
    c.line([(0.5 + tw, 0.56), (0.76, ay)], bark, 0.022)
    for sgn in (-1, 1):
        ex = 0.5 + sgn * 0.26
        c.line([(ex, ay), (ex + sgn * 0.06, ay - 0.06)], bark, 0.014)
        c.line([(ex, ay), (ex + sgn * 0.04, ay + 0.05)], bark, 0.012)
    # leaf crown (fuller with level)
    cr = 0.24 + lvl * 0.014
    c.ellipse(0.5, 0.28, cr, cr * 0.74, leaf)
    c.ellipse(0.5 - cr * 0.4, 0.24, cr * 0.5, cr * 0.42, mix(leaf, WHITE, 0.3))
    c.ellipse(0.5 + cr * 0.4, 0.32, cr * 0.45, cr * 0.36, shade(leaf, 0.75))
    # carved face
    eg = (250, 210, 90, 255) if lvl >= 4 else None
    c.eyes(0.45, 0.57, 0.58, 0.030, glow=eg)
    c.poly([(0.44, 0.67), (0.5, 0.71), (0.56, 0.67),
            (0.5, 0.69)], barks)                    # frown mouth
    # --- ladder ---
    if lvl >= 3:                                    # branch antlers from canopy
        for sgn in (-1, 1):
            bx = 0.5 + sgn * 0.14
            c.line([(bx, 0.16), (bx + sgn * 0.10, 0.04)], bark, 0.016)
            c.line([(bx + sgn * 0.05, 0.10), (bx + sgn * 0.02, 0.03)], bark, 0.01)
    if lvl >= 4:                                    # bark armour plate
        c.rrect(0.5 - tw * 0.7, 0.60, 0.5 + tw * 0.7, 0.74, 0.03, barks)
        c.circle(0.5, 0.67, 0.02, barkh)
    if lvl >= 5:                                    # golden blossoms
        for fx, fy in ((0.36, 0.22), (0.60, 0.20), (0.5, 0.13), (0.48, 0.30)):
            c.circle(fx, fy, 0.028, (245, 215, 80, 255))
            c.circle(fx, fy, 0.012, (255, 245, 190, 255))


def draw_treant_boss(c):
    pal = ramp((104, 66, 38), 1.0)
    bark = pal["base"]
    barks = shade(bark, 0.68)
    barkh = mix(bark, (170, 128, 82, 255), 0.5)
    leaf = (56, 132, 48, 255)
    c.shadow(0.5, 0.95, 0.44, 0.06)
    c.aura(0.5, 0.36, 0.54, (120, 205, 95))
    # massive gnarled trunk, buttress roots, hunched forward
    c.poly([(0.30, 0.40), (0.5, 0.36), (0.70, 0.40),
            (0.74, 0.86), (0.5, 0.92), (0.26, 0.86)], bark)
    c.poly([(0.30, 0.40), (0.42, 0.38), (0.44, 0.86),
            (0.30, 0.84)], barkh)
    for ry in (0.5, 0.6, 0.7, 0.8):
        c.line([(0.34, ry), (0.66, ry + 0.02)], barks, 0.012)
    # buttress roots
    for rx, dx in ((0.30, -0.16), (0.44, -0.06), (0.56, 0.06), (0.70, 0.16)):
        c.poly([(rx, 0.84), (rx + dx, 0.98), (rx + dx * 0.4, 0.87)], barks)
    # huge reaching branch-arms with clawed twigs
    for sgn in (-1, 1):
        c.line([(0.5 + sgn * 0.18, 0.50), (0.5 + sgn * 0.42, 0.34)], bark, 0.035)
        tip = (0.5 + sgn * 0.42, 0.34)
        for a in (-0.10, 0, 0.10):
            c.line([tip, (tip[0] + sgn * 0.08, tip[1] - 0.10 + a)], bark, 0.014)
    # towering canopy
    c.ellipse(0.5, 0.22, 0.42, 0.24, leaf)
    c.ellipse(0.30, 0.18, 0.17, 0.13, mix(leaf, WHITE, 0.3))
    c.ellipse(0.68, 0.26, 0.17, 0.12, shade(leaf, 0.72))
    c.ellipse(0.5, 0.12, 0.16, 0.12, mix(leaf, WHITE, 0.2))
    # wrathful carved face — glowing eyes, gaping maw with wooden teeth
    c.eyes(0.42, 0.58, 0.54, 0.05, glow=(255, 200, 70, 255))
    c.poly([(0.40, 0.66), (0.60, 0.66), (0.56, 0.78), (0.5, 0.80),
            (0.44, 0.78)], (34, 22, 14, 255))
    for tx in (0.44, 0.5, 0.56):
        c.poly([(tx - 0.02, 0.66), (tx, 0.72), (tx + 0.02, 0.66)], barkh)
    # golden blossoms in canopy
    for fx, fy in ((0.30, 0.14), (0.66, 0.12), (0.5, 0.04), (0.44, 0.20)):
        c.circle(fx, fy, 0.032, (245, 215, 80, 255))
        c.circle(fx, fy, 0.014, (255, 245, 190, 255))


# ---- 8 beetle --------------------------------------------------------------
# Ladder: grub -> hardshell -> rhino-horn -> ridged carapace -> gilded scarab
# A4 fix: 3 jointed legs per side sprouting from the BODY SIDE with a knee bend
# and a mid-stride stagger (via insect_legs), NOT thin lines poking randomly.
def draw_beetle(c, lvl, feats, pal):
    shell = pal["base"]
    legcol = mix(shade(shell, 0.5), BLACK, 0.35)
    if lvl >= 5:
        c.aura(0.5, 0.56, 0.42, (70, 195, 185))
    c.shadow(0.5, 0.9, 0.28, 0.06)
    # legs first so the coxae tuck under the carapace edge; reach well past it
    insect_legs(c, 0.5, 0.48, 0.78, 0.14, 0.46, legcol, phase=0.03)
    # head + antennae between the front legs
    c.ellipse(0.5, 0.32, 0.13, 0.11, shade(shell, 0.82))
    for sgn in (-1, 1):
        c.line([(0.5 + sgn * 0.06, 0.26), (0.5 + sgn * 0.14, 0.16)],
               legcol, 0.012)
        c.circle(0.5 + sgn * 0.14, 0.16, 0.014, legcol)
    c.eyes(0.45, 0.55, 0.31, 0.026, glow=(235, 205, 95, 255))
    # mandibles
    c.poly([(0.45, 0.38), (0.38, 0.44), (0.47, 0.40)], legcol)
    c.poly([(0.55, 0.38), (0.62, 0.44), (0.53, 0.40)], legcol)
    # domed carapace with elytra split + shine
    c.ellipse(0.5, 0.58, 0.29, 0.25, shell)
    c.ellipse(0.41, 0.49, 0.13, 0.10, mix(shell, WHITE, 0.45))
    c.line([(0.5, 0.36), (0.5, 0.81)], shade(shell, 0.6), 0.02)
    c.ellipse(0.5, 0.58, 0.29, 0.25, None)  # (outline handled globally)
    # --- ladder ---
    if lvl >= 3:                                    # rhino horn from the head
        c.poly([(0.465, 0.30), (0.5, 0.12), (0.535, 0.30)], shade(shell, 0.7))
        c.poly([(0.485, 0.28), (0.5, 0.16), (0.515, 0.28)], mix(shell, WHITE, 0.2))
    if lvl >= 4:                                    # carapace ridges / studs
        for hx, hy in ((0.36, 0.60), (0.64, 0.60), (0.42, 0.72), (0.58, 0.72)):
            c.circle(hx, hy, 0.028, shade(shell, 0.62))
            c.circle(hx - 0.008, hy - 0.008, 0.01, mix(shell, WHITE, 0.3))
    if lvl >= 5:                                    # gilded scarab markings
        c.line([(0.5, 0.44), (0.42, 0.56)], (240, 205, 90, 255), 0.014)
        c.line([(0.5, 0.44), (0.58, 0.56)], (240, 205, 90, 255), 0.014)
        c.crown(0.5, 0.14, 0.10, (245, 210, 75, 255))


def draw_beetle_boss(c):
    pal = ramp((22, 118, 128), 1.05)
    shell = pal["base"]
    legcol = mix(shade(shell, 0.45), BLACK, 0.4)
    c.shadow(0.5, 0.92, 0.42, 0.06)
    c.aura(0.5, 0.58, 0.5, (70, 200, 190))
    # six powerful jointed legs, wide planted stance
    insect_legs(c, 0.5, 0.44, 0.84, 0.18, 0.52, legcol, phase=0.05)
    # forward-tilted head bearing gigantic stag pincers (the silhouette)
    c.ellipse(0.5, 0.34, 0.17, 0.14, shade(shell, 0.82))
    for sgn in (-1, 1):
        # huge curved pincer sweeping forward with inner serrations
        c.poly([(0.5 + sgn * 0.10, 0.30),
                (0.5 + sgn * 0.44, 0.06),
                (0.5 + sgn * 0.30, 0.10),
                (0.5 + sgn * 0.34, 0.20),
                (0.5 + sgn * 0.14, 0.28)], shade(shell, 0.68))
        for t in (0.2, 0.45, 0.7):
            px = 0.5 + sgn * (0.14 + t * 0.22)
            py = 0.28 - t * 0.14
            c.poly([(px, py), (px + sgn * 0.02, py + 0.03),
                    (px - sgn * 0.01, py + 0.04)], legcol)
    c.eyes(0.44, 0.56, 0.30, 0.04, glow=(245, 205, 85, 255))
    # antennae
    for sgn in (-1, 1):
        c.line([(0.5 + sgn * 0.08, 0.24), (0.5 + sgn * 0.20, 0.12)], legcol, 0.014)
    # massive domed carapace with ridges
    c.ellipse(0.5, 0.60, 0.38, 0.30, shell)
    c.ellipse(0.39, 0.48, 0.16, 0.12, mix(shell, WHITE, 0.4))
    c.line([(0.5, 0.32), (0.5, 0.88)], shade(shell, 0.58), 0.025)
    for hx, hy in ((0.34, 0.62), (0.66, 0.62), (0.4, 0.78), (0.6, 0.78)):
        c.circle(hx, hy, 0.035, shade(shell, 0.6))
    # gilded crown
    c.crown(0.5, 0.05, 0.13, (245, 210, 75, 255))


# ---- 9 cultist -------------------------------------------------------------
# Ladder: acolyte -> staff-bearer -> horned+amulet -> greater orb -> archon
def draw_cultist(c, lvl, feats, pal):
    robe = pal["base"]
    robes = shade(robe, 0.66)
    orb = (170, 110, 235, 255)
    if lvl >= 5:
        c.aura(0.5, 0.42, 0.4, (170, 110, 235))
    c.shadow(0.5, 0.92, 0.24, 0.05)
    # robe (triangle) with torn hem
    c.poly([(0.5, 0.30), (0.26, 0.88), (0.34, 0.90), (0.40, 0.86),
            (0.5, 0.90), (0.60, 0.86), (0.66, 0.90), (0.74, 0.88)], robe)
    c.poly([(0.5, 0.32), (0.34, 0.86), (0.5, 0.86)], mix(robe, WHITE, 0.16))
    c.line([(0.5, 0.40), (0.5, 0.86)], robes, 0.014)
    # sleeved arms / clasped hands
    c.poly([(0.40, 0.52), (0.30, 0.72), (0.44, 0.66)], robe)
    c.poly([(0.60, 0.52), (0.70, 0.72), (0.56, 0.66)], robe)
    c.ellipse(0.5, 0.66, 0.05, 0.04, (210, 200, 205, 255))  # pale hands
    # hood
    c.ellipse(0.5, 0.34, 0.17, 0.19, robe)
    c.poly([(0.5, 0.14), (0.31, 0.42), (0.69, 0.42)], robe)
    c.poly([(0.5, 0.16), (0.36, 0.40), (0.5, 0.40)], mix(robe, WHITE, 0.12))
    # dark face void + glowing eyes
    c.ellipse(0.5, 0.38, 0.10, 0.12, (16, 10, 22, 255))
    eg = (150, 110, 240, 255) if lvl >= 5 else (250, 210, 70, 255)
    for ex in (0.46, 0.54):
        c.circle(ex, 0.38, 0.020, eg)
        c.circle(ex, 0.375, 0.008, WHITE)
    # --- ladder ---
    if lvl >= 2:                                    # staff (orb tops it lv>=4)
        c.line([(0.72, 0.40), (0.80, 0.90)], (110, 80, 50, 255), 0.028)
        if lvl >= 4:
            c.circle(0.76, 0.34, 0.06, orb)
            c.circle(0.745, 0.32, 0.022, mix(orb, WHITE, 0.6))
        else:
            c.circle(0.77, 0.36, 0.035, orb)
    if lvl >= 3:                                    # horns on hood + amulet
        c.horns(0.5, 0.24, 0.10, 0.11, robes, curve=0.06, base=0.022)
        c.circle(0.5, 0.56, 0.035, (240, 210, 70, 255))
        c.circle(0.5, 0.56, 0.016, (200, 60, 80, 255))
    if lvl >= 5:                                    # arch-cultist crown
        c.crown(0.5, 0.13, 0.11, (205, 155, 245, 255))


def draw_cultist_boss(c):
    robe = (104, 40, 150, 255)
    robes = shade(robe, 0.6)
    orb = (180, 120, 245, 255)
    c.shadow(0.5, 0.95, 0.34, 0.05)
    c.aura(0.5, 0.62, 0.22, (170, 100, 240))
    # towering torn robe
    c.poly([(0.5, 0.20), (0.14, 0.90), (0.24, 0.94), (0.32, 0.88),
            (0.42, 0.94), (0.5, 0.88), (0.58, 0.94), (0.68, 0.88),
            (0.76, 0.94), (0.86, 0.90)], robe)
    c.poly([(0.5, 0.22), (0.28, 0.90), (0.5, 0.90)], mix(robe, WHITE, 0.14))
    c.line([(0.5, 0.34), (0.5, 0.88)], robes, 0.02)
    # wide sleeves reaching to cradle the orb
    c.poly([(0.38, 0.44), (0.22, 0.66), (0.44, 0.62)], robe)
    c.poly([(0.62, 0.44), (0.78, 0.66), (0.56, 0.62)], robe)
    for hx in (0.40, 0.60):                          # skeletal hands
        c.ellipse(hx, 0.62, 0.045, 0.035, (206, 198, 205, 255))
    # huge hood + horns
    c.ellipse(0.5, 0.28, 0.25, 0.25, robe)
    c.poly([(0.5, 0.02), (0.22, 0.38), (0.78, 0.38)], robe)
    c.horns(0.5, 0.20, 0.16, 0.18, robes, curve=0.12, base=0.03)
    c.ellipse(0.5, 0.32, 0.14, 0.16, (14, 8, 20, 255))
    for ex in (0.44, 0.56):
        c.circle(ex, 0.32, 0.028, (255, 90, 90, 255))
        c.circle(ex, 0.315, 0.011, WHITE)
    # great arcane orb cradled in front
    c.circle(0.5, 0.64, 0.11, orb)
    c.circle(0.46, 0.61, 0.038, mix(orb, WHITE, 0.65))
    for a in range(6):                               # orbiting runes
        ang = a * math.pi / 3
        c.circle(0.5 + math.cos(ang) * 0.15, 0.64 + math.sin(ang) * 0.15,
                 0.012, (220, 180, 255, 235))
    c.crown(0.5, 0.04, 0.16, (215, 165, 250, 255))


# ---- 10 slime --------------------------------------------------------------
# Ladder: droplet -> ooze -> spiked -> cored -> toxic king(crown ON dome+fangs)
def draw_slime(c, lvl, feats, pal):
    base = (pal["base"][0], pal["base"][1], pal["base"][2], 226)
    if lvl >= 5:
        c.aura(0.5, 0.62, 0.4, (150, 235, 80))
    c.shadow(0.5, 0.86, 0.26, 0.05)
    # wobbling blob, a couple of drips
    c.poly([(0.22, 0.82), (0.23, 0.54), (0.33, 0.40),
            (0.5, 0.34), (0.67, 0.40), (0.77, 0.54),
            (0.78, 0.82)], base)
    c.ellipse(0.5, 0.80, 0.28, 0.10, shade(base, 0.85))
    c.circle(0.30, 0.60, 0.03, base)                 # side drip
    # gel highlight
    c.ellipse(0.40, 0.50, 0.10, 0.13, mix(base, WHITE, 0.5))
    c.circle(0.60, 0.46, 0.04, mix(base, WHITE, 0.55))
    # face — angrier with level
    c.circle(0.42, 0.58, 0.036, DARKLINE)
    c.circle(0.58, 0.58, 0.036, DARKLINE)
    c.circle(0.412, 0.57, 0.013, WHITE)
    c.circle(0.572, 0.57, 0.013, WHITE)
    if lvl >= 3:                                     # angry brows
        c.line([(0.38, 0.53), (0.46, 0.56)], shade(base, 0.6), 0.014)
        c.line([(0.62, 0.53), (0.54, 0.56)], shade(base, 0.6), 0.014)
    if lvl >= 4:                                     # fanged grin
        c.line([(0.44, 0.68), (0.56, 0.68)], DARKLINE, 0.016)
        c.poly([(0.46, 0.68), (0.48, 0.72), (0.44, 0.70)], WHITE)
        c.poly([(0.54, 0.68), (0.52, 0.72), (0.56, 0.70)], WHITE)
    else:
        c.line([(0.46, 0.68), (0.54, 0.68)], DARKLINE, 0.014)
    # --- ladder ---
    if lvl >= 3:                                     # crystalline spikes
        for sgn in (-1, 0, 1):
            sx = 0.5 + sgn * 0.16
            c.poly([(sx - 0.03, 0.38), (sx, 0.24 - abs(sgn) * 0.02),
                    (sx + 0.03, 0.38)], shade(base, 0.8))
    if lvl >= 4:                                     # inner cores
        c.circle(0.5, 0.70, 0.05, mix(base, (60, 150, 40, 255), 0.6))
        c.circle(0.62, 0.64, 0.03, mix(base, (60, 150, 40, 255), 0.5))
    if lvl >= 5:                                     # crown resting ON the dome
        c.crown(0.5, 0.37, 0.12, (245, 215, 75, 255))


def draw_slime_boss(c):
    base = (118, 226, 44, 228)
    c.shadow(0.5, 0.9, 0.44, 0.06)
    c.aura(0.5, 0.6, 0.5, (150, 240, 80))
    # big menacing ooze, uneven dripping crown of the dome
    c.poly([(0.12, 0.86), (0.13, 0.48), (0.26, 0.30),
            (0.40, 0.24), (0.5, 0.28), (0.60, 0.24),
            (0.74, 0.30), (0.87, 0.48), (0.88, 0.86)], base)
    c.ellipse(0.5, 0.84, 0.40, 0.12, shade(base, 0.85))
    c.ellipse(0.34, 0.42, 0.13, 0.17, mix(base, WHITE, 0.45))
    # drips down the sides
    c.circle(0.16, 0.66, 0.04, base)
    c.circle(0.85, 0.70, 0.035, base)
    # swallowed victims / cores inside
    for bx, by, r in ((0.62, 0.62, 0.08), (0.44, 0.72, 0.06), (0.68, 0.78, 0.05)):
        c.circle(bx, by, r, mix(base, (60, 150, 40, 255), 0.55))
        c.circle(bx - r * 0.3, by - r * 0.3, r * 0.35, mix(base, WHITE, 0.4))
    # glaring eyes + big fanged maw
    c.circle(0.40, 0.50, 0.055, DARKLINE)
    c.circle(0.60, 0.50, 0.055, DARKLINE)
    c.circle(0.384, 0.485, 0.02, WHITE)
    c.circle(0.584, 0.485, 0.02, WHITE)
    c.line([(0.36, 0.45), (0.46, 0.49)], shade(base, 0.55), 0.02)   # brows
    c.line([(0.64, 0.45), (0.54, 0.49)], shade(base, 0.55), 0.02)
    c.ellipse(0.5, 0.66, 0.12, 0.06, (30, 60, 16, 255))            # maw
    for tx in (0.42, 0.5, 0.58):
        c.poly([(tx - 0.02, 0.61), (tx, 0.66), (tx + 0.02, 0.61)], WHITE)
        c.poly([(tx - 0.02, 0.71), (tx, 0.66), (tx + 0.02, 0.71)], WHITE)
    # jagged crown sitting on the dome
    c.crown(0.5, 0.30, 0.16, (245, 215, 75, 255))


# (name, level-draw, boss-draw, lv1 base colour, lv5 striking accent colour)
FAMILIES = [
    ("goblin",  draw_goblin,   draw_goblin_boss,   (96, 156, 74),  (52, 168, 44)),
    ("wolf",    draw_wolf,     draw_wolf_boss,     (150, 156, 166), (92, 112, 148)),
    ("skeleton", draw_skeleton, draw_skeleton_boss, (222, 220, 206), (196, 206, 216)),
    ("golem",   draw_golem,    draw_golem_boss,    (140, 132, 120), (150, 116, 92)),
    ("ghost",   draw_ghost,    draw_ghost_boss,    (210, 236, 244), (140, 224, 236)),
    ("bat",     draw_bat,      draw_bat_boss,      (150, 120, 190), (150, 54, 150)),
    ("treant",  draw_treant,   draw_treant_boss,   (128, 92, 56),  (104, 66, 38)),
    ("beetle",  draw_beetle,   draw_beetle_boss,   (46, 112, 112), (22, 118, 128)),
    ("cultist", draw_cultist,  draw_cultist_boss,  (128, 52, 66),  (104, 40, 150)),
    ("slime",   draw_slime,    draw_slime_boss,    (150, 220, 90), (118, 226, 44)),
]

MON_SIZES = {1: 32, 2: 35, 3: 38, 4: 41, 5: 44}


def gen_monsters():
    n = 0
    for name, fn, bossfn, basecol, accent in FAMILIES:
        for lvl in range(1, 6):
            size = MON_SIZES[lvl]
            pal = level_ramp(basecol, accent, lvl)
            feats = feats_for(lvl)
            # draw at a bigger logical grid (4x) for smoother features, then
            # scale to the small target with nearest-neighbour.
            logical = size * 4
            img = render(lambda c, fn=fn, lvl=lvl, feats=feats, pal=pal:
                         fn(c, lvl, feats, pal), size, logical=logical,
                         outline=4)
            save(img, "monsters", f"{name}_{lvl}.png")
            n += 1
        # boss 96
        img = render(lambda c, bossfn=bossfn: bossfn(c), 96, logical=96 * 3,
                     outline=6)
        save(img, "monsters", f"{name}_boss.png")
        n += 1
    return n
