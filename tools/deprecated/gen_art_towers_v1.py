#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""gen_art_towers_v1.py — 【已封存,唔再用】程序生成塔 sprite 嘅舊管線。

2026-08-07 嘅塔 / 魔法美術收官輪之後,60 張塔圖改為由 Jack 自己生成嘅 sprite
sheet 摳出嚟(見 `tools/tower_cutout.py` 同 `art_reference/tower/`)。呢一份係
第五輪重畫 + 第十輪進化階嗰套 Pillow 程序畫法嘅完整存檔 —— 唔會再行,亦唔會
再入 build:`gen_art.py` 嘅 `main()` 冇再叫 `gen_towers()`,所以
`assets/generated/towers/` 唔會再俾佢覆蓋,atlas 入面亦都淨係得新圖。

同 `gen_art_monsters_v1.py` 一樣,呢個檔冇任何 import,係刻意嘅:唔想有人
一時手快 `python tools/deprecated/...` 就冚咗成套新美術。要行返嘅話要自己由
gen_art.py 借返 Canvas / render / save / shade / mix / clamp / ramp / WHITE
等等 helper。`_tglow` 同 `_tier_lift` 兩個 helper **仲留喺 gen_art.py**
(魔晶圖示同魔法 icon 仲用緊),下面呢份為咗自足抄多咗一份 `_tglow`。
"""

# ---------------------------------------------------------------------------
# 以下由 tools/gen_art.py 原封不動搬過嚟(2026-08-07)
# ---------------------------------------------------------------------------

# ============================================================================
# TOWERS  (44x44 sprite, drawn on a 6x logical grid, unified pad at the bottom)
# ============================================================================
# Round-5 redraw. The old set was "a flat icon standing on a grey plinth" and
# sat a whole quality tier below the round-3 monsters. Rules now shared with
# the monsters so the two read as one game:
#   * light comes from the TOP-LEFT; every form gets base / shadow / highlight
#     (3-tone cel shading, no gradients) and the shadow falls bottom-right
#   * one uniform dark outline (1 source pixel = 2 screen px at TOWER_RENDER 2)
#   * the PAD is identical in shape for all 20 towers (so the set reads as a
#     system) and only its tint + a small accent changes per element
#   * the BODY is silhouette-first: no two towers share an outline shape, and
#     each says what it does (cannon = fat muzzle, frost = shards, alchemy =
#     coins, barracks = tent + spears ...)

TOWER_SIZE = 44
TOWER_LOGICAL = TOWER_SIZE * 6      # 6x supersample, integer-downscaled

# element tints for the shared pad (kept close together so the pads still
# read as one material — the difference is a hint, not a different stone)
ELEM_PAD = {
    "stone":  (150, 148, 154, 255),
    "fire":   (162, 132, 116, 255),
    "ice":    (154, 172, 186, 255),
    "poison": (132, 150, 122, 255),
    "arcane": (144, 134, 168, 255),
    "gold":   (168, 154, 118, 255),
    "wood":   (156, 140, 116, 255),
}


def tower_pad(c, elem="stone"):
    """The shared isometric stone pad every tower stands on."""
    col = ELEM_PAD.get(elem, ELEM_PAD["stone"])
    topL = mix(col, WHITE, 0.34)      # lit half (light from top-left)
    topR = mix(col, WHITE, 0.12)
    rimL = shade(col, 0.72)
    rimR = shade(col, 0.50)
    # top face, split down the middle so the light direction reads
    c.poly([(0.5, 0.605), (0.5, 0.875), (0.09, 0.74)], topL)
    c.poly([(0.5, 0.605), (0.91, 0.74), (0.5, 0.875)], topR)
    # front skirt (the pad has thickness)
    c.poly([(0.09, 0.74), (0.5, 0.875), (0.5, 0.955), (0.09, 0.82)], rimL)
    c.poly([(0.91, 0.74), (0.5, 0.875), (0.5, 0.955), (0.91, 0.82)], rimR)
    # chiselled block seams on the skirt
    c.line([(0.27, 0.795), (0.27, 0.875)], shade(col, 0.42), 0.018)
    c.line([(0.73, 0.795), (0.73, 0.875)], shade(col, 0.36), 0.018)
    # inner rim on the top face
    c.line([(0.09, 0.74), (0.5, 0.605)], mix(col, WHITE, 0.55), 0.016)
    # element accent: two small tokens embedded in the pad corners
    acc = {
        "fire": (226, 118, 52, 255), "ice": (150, 226, 244, 255),
        "poison": (128, 206, 74, 255), "arcane": (176, 118, 240, 255),
        "gold": (246, 206, 78, 255), "wood": (120, 168, 84, 255),
    }.get(elem)
    if acc is not None:
        c.circle(0.235, 0.775, 0.026, acc)
        c.circle(0.765, 0.775, 0.026, shade(acc, 0.8))


def _plinth(c, x0, x1, ytop, ybot, col):
    """Squat mounting block between pad and body (kept small and consistent)."""
    c.rrect(x0, ytop, x1, ybot, 0.03, col)
    c.rrect(x0, ytop, x0 + (x1 - x0) * 0.45, ybot, 0.03, mix(col, WHITE, 0.30))
    c.line([(x0, ybot - 0.012), (x1, ybot - 0.012)], shade(col, 0.6), 0.022)


def _cyl(c, cx, halfw, ytop, ybot, col, cap_r=0.30):
    """Vertical cylinder: lit left band, base, shadow right band, elliptical cap."""
    c.rect(cx - halfw, ytop, cx + halfw, ybot, col)
    c.rect(cx - halfw, ytop, cx - halfw * 0.25, ybot, mix(col, WHITE, 0.30))
    c.rect(cx + halfw * 0.55, ytop, cx + halfw, ybot, shade(col, 0.66))
    c.ellipse(cx, ytop, halfw, halfw * cap_r, mix(col, WHITE, 0.16))
    c.ellipse(cx, ytop, halfw * 0.62, halfw * cap_r * 0.62, shade(col, 0.62))


def _barrel(c, ax, ay, bx, by, w, col, muzzle=True):
    """A thick barrel from a->b with a top highlight and a dark muzzle ring."""
    c.line([(ax, ay), (bx, by)], shade(col, 0.55), w)
    c.line([(ax, ay), (bx, by)], col, w * 0.78)
    # highlight rides the upper-left edge
    dx, dy = bx - ax, by - ay
    ln = max(1e-5, math.hypot(dx, dy))
    nx, ny = -dy / ln, dx / ln
    off = w * 0.26
    c.line([(ax + nx * off, ay + ny * off), (bx + nx * off, by + ny * off)],
           mix(col, WHITE, 0.34), w * 0.22)
    if muzzle:
        c.circle(bx, by, w * 0.62, shade(col, 0.45))
        c.circle(bx, by, w * 0.34, (26, 24, 30, 255))



def _tglow(c, cx, cy, r, col):
    """Tight halo for towers. Canvas.aura() spreads to r*1.25 with alpha 80 —
    on a 44px sprite that reads as an opaque disc covering the pad, so towers
    use this much smaller/fainter version instead."""
    layer = Image.new("RGBA", (c.s, c.s), (0, 0, 0, 0))
    ld = ImageDraw.Draw(layer)
    for a, rr in ((22, r), (34, r * 0.74), (46, r * 0.5)):
        ld.ellipse(c._b(cx, cy, rr, rr), fill=(col[0], col[1], col[2], a))
    c.img = Image.alpha_composite(layer, c.img)
    c.d = ImageDraw.Draw(c.img)


def _orb(c, cx, cy, r, col, glow=True):
    """Glowing sphere: dark rim, body, lit crescent, white glint."""
    if glow:
        _tglow(c, cx, cy, r * 1.35, col[:3])
    c.circle(cx, cy, r, shade(col, 0.55))
    c.circle(cx, cy, r * 0.86, col)
    c.circle(cx - r * 0.22, cy - r * 0.24, r * 0.52, mix(col, WHITE, 0.45))
    c.circle(cx - r * 0.30, cy - r * 0.32, r * 0.22, WHITE)


def _post(c, cx, ytop, ybot, w, col):
    c.rect(cx - w, ytop, cx + w, ybot, col)
    c.rect(cx - w, ytop, cx - w * 0.15, ybot, mix(col, WHITE, 0.28))
    c.rect(cx + w * 0.5, ytop, cx + w, ybot, shade(col, 0.65))


STEEL = (162, 168, 182, 255)
IRON = (86, 90, 100, 255)
WOOD = (146, 104, 60, 255)
STONEC = (150, 148, 154, 255)


# --- 1 arrow: twin-limb ballista, wide V top --------------------------------
def t_arrow(c):
    tower_pad(c, "wood")
    _plinth(c, 0.36, 0.64, 0.545, 0.655, (108, 78, 48, 255))
    # rotating deck
    c.rrect(0.33, 0.47, 0.67, 0.57, 0.04, WOOD)
    c.rrect(0.33, 0.47, 0.50, 0.57, 0.04, mix(WOOD, WHITE, 0.30))
    # recurve bow: one thick arc bulging up, tips flicked outward
    limb = (122, 86, 46, 255)
    c.d.arc(c._b(0.5, 0.46, 0.38, 0.24), 200, 340, fill=shade(limb, 0.6),
            width=max(3, int(0.075 * c.s)))
    c.d.arc(c._b(0.5, 0.455, 0.38, 0.24), 202, 338, fill=limb,
            width=max(2, int(0.052 * c.s)))
    c.d.arc(c._b(0.5, 0.445, 0.38, 0.24), 205, 270,
            fill=mix(limb, WHITE, 0.34), width=max(2, int(0.022 * c.s)))
    # straight bowstring between the tips
    c.line([(0.145, 0.375), (0.855, 0.375)], (238, 234, 216, 255), 0.026)
    # loaded bolt pointing up
    c.line([(0.5, 0.44), (0.5, 0.12)], (182, 176, 160, 255), 0.036)
    c.line([(0.5, 0.44), (0.5, 0.12)], (232, 228, 214, 255), 0.014)
    c.poly([(0.5, 0.04), (0.40, 0.20), (0.60, 0.20)], (86, 190, 88, 255))
    c.poly([(0.5, 0.04), (0.40, 0.20), (0.5, 0.20)], (150, 228, 142, 255))
    c.poly([(0.42, 0.40), (0.5, 0.30), (0.58, 0.40)], (96, 68, 42, 255))


# --- 2 cannon: fat stubby muzzle, heaviest gun silhouette -------------------
def t_cannon(c):
    tower_pad(c, "stone")
    _plinth(c, 0.30, 0.70, 0.545, 0.665, (72, 74, 82, 255))
    # swivel body
    c.rrect(0.28, 0.44, 0.62, 0.60, 0.07, IRON)
    c.rrect(0.28, 0.44, 0.44, 0.60, 0.07, mix(IRON, WHITE, 0.26))
    c.circle(0.36, 0.52, 0.045, shade(IRON, 0.6))
    # fat barrel up-right
    _barrel(c, 0.50, 0.53, 0.83, 0.30, 0.155, (62, 64, 72, 255))
    # reinforcing bands
    c.line([(0.61, 0.455), (0.68, 0.505)], (34, 34, 40, 255), 0.03)
    # cannonball pile
    c.circle(0.24, 0.61, 0.055, (48, 48, 56, 255))
    c.circle(0.225, 0.595, 0.022, (120, 122, 132, 255))


# --- 3 lightning: tall tesla mast + ball, tallest thin silhouette -----------
def t_lightning(c):
    tower_pad(c, "arcane")
    _plinth(c, 0.38, 0.62, 0.535, 0.655, (68, 76, 108, 255))
    _post(c, 0.5, 0.30, 0.55, 0.045, (156, 160, 174, 255))
    # coil rings climbing the mast
    for cy, rr in ((0.50, 0.115), (0.42, 0.095), (0.35, 0.075)):
        c.ellipse(0.5, cy, rr, rr * 0.34, (188, 192, 204, 255))
        c.ellipse(0.5, cy + 0.012, rr * 0.8, rr * 0.22, (96, 100, 116, 255))
    _orb(c, 0.5, 0.22, 0.105, (92, 168, 244, 255))
    # arcs leaping off the ball
    c.line([(0.44, 0.16), (0.34, 0.09), (0.40, 0.12)], (176, 226, 255, 255), 0.022)
    c.line([(0.57, 0.15), (0.68, 0.07), (0.61, 0.11)], (176, 226, 255, 255), 0.022)


# --- 4 fireball: brazier bowl with a flame plume ----------------------------
def t_fireball(c):
    tower_pad(c, "fire")
    _plinth(c, 0.36, 0.64, 0.555, 0.665, (110, 66, 46, 255))
    # stone bowl
    bowl = (154, 96, 66, 255)
    c.poly([(0.24, 0.44), (0.76, 0.44), (0.66, 0.60), (0.34, 0.60)], bowl)
    c.poly([(0.24, 0.44), (0.50, 0.44), (0.42, 0.60), (0.34, 0.60)],
           mix(bowl, WHITE, 0.30))
    c.ellipse(0.5, 0.44, 0.26, 0.075, shade(bowl, 0.55))
    c.ellipse(0.5, 0.445, 0.20, 0.052, (58, 32, 24, 255))
    # flame: three cel-shaded tongues
    c.poly([(0.5, 0.13), (0.34, 0.40), (0.66, 0.40)], (232, 96, 36, 255))
    c.poly([(0.5, 0.19), (0.39, 0.41), (0.61, 0.41)], (250, 158, 46, 255))
    c.poly([(0.5, 0.27), (0.44, 0.42), (0.56, 0.42)], (254, 226, 122, 255))
    c.circle(0.34, 0.34, 0.028, (250, 158, 46, 255))
    c.circle(0.68, 0.30, 0.022, (232, 96, 36, 255))


# --- 5 frost: cluster of angular ice shards ---------------------------------
def t_frost(c):
    tower_pad(c, "ice")
    _plinth(c, 0.36, 0.64, 0.565, 0.665, (96, 132, 154, 255))
    ice = (140, 218, 244, 255)
    # side shards first (behind)
    c.poly([(0.28, 0.62), (0.22, 0.40), (0.36, 0.34), (0.38, 0.62)],
           shade(ice, 0.74))
    c.poly([(0.72, 0.62), (0.80, 0.44), (0.66, 0.36), (0.62, 0.62)],
           shade(ice, 0.62))
    # main spire
    c.poly([(0.5, 0.07), (0.34, 0.44), (0.5, 0.64), (0.66, 0.44)], ice)
    c.poly([(0.5, 0.07), (0.34, 0.44), (0.5, 0.52)], mix(ice, WHITE, 0.48))
    c.poly([(0.5, 0.07), (0.66, 0.44), (0.5, 0.52)], shade(ice, 0.78))
    c.line([(0.5, 0.14), (0.5, 0.58)], mix(ice, WHITE, 0.75), 0.018)
    # frost sparkles
    c.circle(0.30, 0.30, 0.022, (226, 248, 255, 255))
    c.circle(0.74, 0.26, 0.018, (226, 248, 255, 255))


# --- 6 poison: bubbling cauldron with a drip nozzle -------------------------
def t_poison(c):
    tower_pad(c, "poison")
    _plinth(c, 0.34, 0.66, 0.585, 0.675, (66, 84, 58, 255))
    pot = (92, 96, 88, 255)
    # cauldron belly
    c.ellipse(0.5, 0.47, 0.27, 0.20, pot)
    c.ellipse(0.42, 0.43, 0.17, 0.12, mix(pot, WHITE, 0.26))
    c.ellipse(0.5, 0.34, 0.27, 0.075, shade(pot, 0.55))
    # brew surface + bubbles
    c.ellipse(0.5, 0.335, 0.225, 0.058, (108, 208, 62, 255))
    c.ellipse(0.46, 0.328, 0.10, 0.026, (176, 240, 116, 255))
    c.circle(0.40, 0.27, 0.035, (140, 224, 84, 255))
    c.circle(0.58, 0.23, 0.026, (176, 240, 116, 255))
    c.circle(0.50, 0.185, 0.020, (140, 224, 84, 255))
    # side nozzle dripping
    c.rect(0.74, 0.44, 0.86, 0.50, shade(pot, 0.7))
    c.circle(0.855, 0.545, 0.028, (108, 208, 62, 255))
    # rim handles
    c.line([(0.24, 0.40), (0.19, 0.47)], shade(pot, 0.5), 0.026)
    c.line([(0.76, 0.40), (0.81, 0.47)], shade(pot, 0.5), 0.026)


# --- 7 sniper: very long thin barrel + big scope, low profile ---------------
def t_sniper(c):
    tower_pad(c, "stone")
    _plinth(c, 0.32, 0.62, 0.565, 0.675, (86, 76, 64, 255))
    # low chassis + bipod
    c.rrect(0.28, 0.48, 0.60, 0.59, 0.04, (112, 98, 78, 255))
    c.rrect(0.28, 0.48, 0.42, 0.59, 0.04, mix((112, 98, 78, 255), WHITE, 0.28))
    c.line([(0.36, 0.58), (0.28, 0.68)], (74, 66, 56, 255), 0.026)
    c.line([(0.46, 0.58), (0.52, 0.68)], (74, 66, 56, 255), 0.026)
    # extremely long barrel to the upper right
    _barrel(c, 0.44, 0.525, 0.94, 0.14, 0.062, (128, 134, 146, 255))
    # scope on top
    c.rrect(0.40, 0.395, 0.60, 0.455, 0.025, (52, 54, 62, 255))
    c.rect(0.42, 0.405, 0.58, 0.42, (152, 158, 172, 255))
    c.circle(0.60, 0.425, 0.038, (60, 62, 70, 255))
    c.circle(0.60, 0.425, 0.020, (128, 214, 232, 255))


# --- 8 gatling: bundled barrels + fat ammo drum -----------------------------
def t_gatling(c):
    tower_pad(c, "stone")
    _plinth(c, 0.30, 0.66, 0.555, 0.665, (66, 70, 78, 255))
    # ammo drum (the recognisable part)
    c.circle(0.32, 0.48, 0.135, (94, 98, 108, 255))
    c.circle(0.32, 0.48, 0.095, (130, 134, 146, 255))
    c.circle(0.295, 0.455, 0.038, mix(STEEL, WHITE, 0.4))
    for a in range(0, 360, 60):
        rx = 0.32 + 0.115 * math.cos(math.radians(a))
        ry = 0.48 + 0.115 * math.sin(math.radians(a))
        c.circle(rx, ry, 0.022, (56, 58, 66, 255))
    # receiver + three stubby barrels
    c.rrect(0.42, 0.42, 0.60, 0.56, 0.04, IRON)
    for i, off in enumerate((-0.085, 0.0, 0.085)):
        col = mix(IRON, WHITE, 0.26 - i * 0.13)
        _barrel(c, 0.58, 0.49 + off * 0.7, 0.93, 0.40 + off, 0.038, col)


# --- 9 mortar: short wide tube pointing straight up, braced legs ------------
def t_mortar(c):
    tower_pad(c, "stone")
    olive = (124, 130, 70, 255)
    # heavy baseplate
    c.poly([(0.18, 0.72), (0.82, 0.72), (0.74, 0.61), (0.26, 0.61)],
           (84, 86, 64, 255))
    c.poly([(0.18, 0.72), (0.50, 0.72), (0.50, 0.61), (0.26, 0.61)],
           (120, 122, 92, 255))
    # bipod
    c.line([(0.44, 0.64), (0.24, 0.50)], (72, 74, 52, 255), 0.042)
    c.line([(0.44, 0.64), (0.30, 0.72)], (72, 74, 52, 255), 0.036)
    # short fat tube, tilted up-right
    _barrel(c, 0.46, 0.66, 0.70, 0.26, 0.20, olive, muzzle=False)
    c.line([(0.52, 0.56), (0.60, 0.42)], shade(olive, 0.6), 0.038)
    # wide muzzle mouth with a deep bore
    c.ellipse(0.70, 0.245, 0.185, 0.085, shade(olive, 0.46))
    c.ellipse(0.70, 0.255, 0.135, 0.060, (26, 28, 18, 255))
    c.ellipse(0.685, 0.245, 0.075, 0.030, (66, 70, 44, 255))
    # a shell resting against the pad
    c.rrect(0.15, 0.50, 0.25, 0.62, 0.03, (178, 152, 76, 255))
    c.poly([(0.15, 0.50), (0.20, 0.42), (0.25, 0.50)], (210, 186, 104, 255))


# --- 10 beam: crystal lens on a tripod, vertical light column ---------------
def t_beam(c):
    tower_pad(c, "stone")
    _plinth(c, 0.36, 0.64, 0.575, 0.675, (104, 104, 116, 255))
    # tripod
    for sgn in (-1, 1):
        c.line([(0.5 + sgn * 0.04, 0.50), (0.5 + sgn * 0.20, 0.66)],
               (118, 120, 132, 255), 0.034)
    c.line([(0.5, 0.50), (0.5, 0.66)], (96, 98, 110, 255), 0.03)
    # emitter housing
    c.rrect(0.34, 0.36, 0.66, 0.52, 0.05, (146, 148, 160, 255))
    c.rrect(0.34, 0.36, 0.50, 0.52, 0.05, mix(STEEL, WHITE, 0.34))
    c.line([(0.34, 0.485), (0.66, 0.485)], (92, 94, 106, 255), 0.026)
    # lens + a narrow hard-edged light column (reads as a beam, not a flame)
    c.rect(0.435, 0.02, 0.565, 0.36, (252, 226, 118, 120))
    c.rect(0.468, 0.02, 0.532, 0.36, (255, 250, 206, 210))
    c.circle(0.5, 0.37, 0.115, (128, 132, 146, 255))
    c.circle(0.5, 0.37, 0.088, (250, 232, 132, 255))
    c.circle(0.5, 0.37, 0.05, WHITE)


# --- 11 slowfield: hovering rune ring over a pillar -------------------------
def t_slowfield(c):
    tower_pad(c, "arcane")
    teal = (86, 222, 210, 255)
    _post(c, 0.5, 0.34, 0.66, 0.075, (118, 126, 132, 255))
    c.rrect(0.36, 0.60, 0.64, 0.68, 0.03, (98, 106, 112, 255))
    # floating ring (torus) — the distinctive silhouette
    _tglow(c, 0.5, 0.30, 0.22, teal[:3])
    c.ellipse(0.5, 0.30, 0.32, 0.135, shade(teal, 0.5))
    c.ellipse(0.5, 0.30, 0.24, 0.085, (0, 0, 0, 0))
    c.d.ellipse(c._b(0.5, 0.30, 0.28, 0.112), outline=teal,
                width=max(2, int(0.05 * c.s)))
    c.d.ellipse(c._b(0.5, 0.30, 0.28, 0.112),
                outline=mix(teal, WHITE, 0.55), width=max(1, int(0.018 * c.s)))
    for a in (0, 90, 180, 270):
        rx = 0.5 + 0.28 * math.cos(math.radians(a))
        ry = 0.30 + 0.112 * math.sin(math.radians(a))
        c.circle(rx, ry, 0.032, mix(teal, WHITE, 0.3))
    c.circle(0.5, 0.30, 0.05, (196, 250, 244, 200))


# --- 12 alchemy: little furnace/still with a coin stack ---------------------
def t_alchemy(c):
    tower_pad(c, "gold")
    gold = (244, 202, 66, 255)
    brick = (150, 112, 78, 255)
    # furnace body
    c.rrect(0.26, 0.38, 0.68, 0.66, 0.05, brick)
    c.rrect(0.26, 0.38, 0.44, 0.66, 0.05, mix(brick, WHITE, 0.28))
    c.line([(0.26, 0.52), (0.68, 0.52)], shade(brick, 0.62), 0.022)
    # glowing furnace mouth
    c.rrect(0.34, 0.55, 0.52, 0.64, 0.02, (58, 34, 24, 255))
    c.rrect(0.36, 0.575, 0.50, 0.635, 0.02, (246, 150, 52, 255))
    # chimney with a puff
    c.rect(0.56, 0.24, 0.68, 0.40, shade(brick, 0.8))
    c.rect(0.56, 0.24, 0.61, 0.40, mix(brick, WHITE, 0.22))
    c.circle(0.62, 0.18, 0.055, (168, 162, 172, 170))
    c.circle(0.70, 0.11, 0.038, (168, 162, 172, 130))
    # coin stack + a flying coin
    for i, cy in enumerate((0.635, 0.60, 0.565)):
        c.ellipse(0.79, cy, 0.085, 0.032, shade(gold, 0.72))
        c.ellipse(0.79, cy - 0.012, 0.085, 0.028, gold)
    c.circle(0.26, 0.28, 0.062, shade(gold, 0.7))
    c.circle(0.26, 0.28, 0.046, gold)
    c.circle(0.245, 0.265, 0.016, (255, 246, 200, 255))


# --- 13 barracks: tent + spear rack (asymmetric) ----------------------------
def t_barracks(c):
    tower_pad(c, "wood")
    tent = (188, 96, 72, 255)
    # spears leaning at the right (breaks the symmetry)
    for sx, sy in ((0.78, 0.20), (0.86, 0.26)):
        c.line([(sx, sy), (sx - 0.10, 0.66)], (132, 98, 62, 255), 0.024)
        c.poly([(sx, sy - 0.06), (sx - 0.035, sy + 0.02),
                (sx + 0.035, sy + 0.02)], (198, 204, 216, 255))
    # tent
    c.poly([(0.44, 0.18), (0.16, 0.68), (0.72, 0.68)], tent)
    c.poly([(0.44, 0.18), (0.16, 0.68), (0.44, 0.68)], mix(tent, WHITE, 0.26))
    c.poly([(0.44, 0.30), (0.32, 0.68), (0.56, 0.68)], (86, 48, 40, 255))
    c.poly([(0.44, 0.34), (0.36, 0.68), (0.52, 0.68)], (58, 34, 30, 255))
    c.line([(0.16, 0.68), (0.72, 0.68)], shade(tent, 0.5), 0.024)
    # banner pole on the peak
    c.line([(0.44, 0.18), (0.44, 0.04)], (120, 96, 70, 255), 0.02)
    c.poly([(0.44, 0.05), (0.66, 0.11), (0.44, 0.17)], (72, 150, 224, 255))
    c.poly([(0.44, 0.05), (0.58, 0.086), (0.44, 0.13)], (128, 194, 246, 255))


# --- 14 boomerang: thrower arm + spinning blade above -----------------------
def t_boomerang(c):
    tower_pad(c, "wood")
    _plinth(c, 0.36, 0.64, 0.555, 0.665, (104, 78, 48, 255))
    # throwing arm (a slanted lever)
    c.line([(0.34, 0.60), (0.66, 0.44)], (128, 94, 54, 255), 0.055)
    c.line([(0.34, 0.60), (0.66, 0.44)], mix(WOOD, WHITE, 0.30), 0.02)
    c.circle(0.34, 0.60, 0.05, (86, 62, 38, 255))
    # the boomerang itself, mid-spin (big V)
    bl = (186, 138, 78, 255)
    c.poly([(0.5, 0.08), (0.16, 0.30), (0.24, 0.40), (0.5, 0.24),
            (0.76, 0.40), (0.84, 0.30)], bl)
    c.poly([(0.5, 0.08), (0.16, 0.30), (0.24, 0.40), (0.5, 0.24)],
           mix(bl, WHITE, 0.34))
    c.line([(0.5, 0.13), (0.26, 0.30)], mix(bl, WHITE, 0.6), 0.022)
    c.circle(0.5, 0.18, 0.036, shade(bl, 0.58))
    # spin arcs
    c.d.arc(c._b(0.5, 0.26, 0.38, 0.20), 196, 344,
            fill=(230, 226, 216, 150), width=max(2, int(0.022 * c.s)))


# --- 15 thorn: briar mound bristling with spikes ----------------------------
def t_thorn(c):
    tower_pad(c, "poison")
    dark = (44, 78, 40, 255)
    leaf = (78, 142, 58, 255)
    # spikes radiating out first so they sit behind the mound
    for ax, ay in ((0.14, 0.42), (0.24, 0.24), (0.5, 0.13), (0.76, 0.24),
                   (0.87, 0.44), (0.20, 0.60), (0.80, 0.60)):
        c.line([(0.5, 0.50), (ax, ay)], dark, 0.03)
        c.circle(ax, ay, 0.026, (188, 210, 150, 255))
    # briar mound
    c.ellipse(0.5, 0.52, 0.30, 0.22, leaf)
    c.ellipse(0.42, 0.47, 0.19, 0.13, mix(leaf, WHITE, 0.30))
    c.ellipse(0.62, 0.58, 0.14, 0.09, shade(leaf, 0.68))
    # woody stem + berries
    c.line([(0.5, 0.62), (0.5, 0.70)], (92, 66, 40, 255), 0.05)
    c.circle(0.36, 0.56, 0.034, (206, 62, 82, 255))
    c.circle(0.62, 0.46, 0.028, (206, 62, 82, 255))
    c.circle(0.352, 0.552, 0.012, (250, 170, 180, 255))


# --- 16 missile: boxy launcher with two angled missiles ---------------------
def t_missile(c):
    tower_pad(c, "stone")
    _plinth(c, 0.32, 0.68, 0.575, 0.675, (96, 62, 58, 255))
    box = (124, 74, 70, 255)
    c.rrect(0.24, 0.44, 0.76, 0.60, 0.05, box)
    c.rrect(0.24, 0.44, 0.44, 0.60, 0.05, mix(box, WHITE, 0.28))
    c.line([(0.24, 0.545), (0.76, 0.545)], shade(box, 0.6), 0.024)
    # two missiles, angled (not vertical) so the silhouette leans
    for mx, tilt in ((0.38, -0.05), (0.60, -0.05)):
        c.line([(mx, 0.46), (mx + tilt, 0.16)], (214, 74, 62, 255), 0.085)
        c.line([(mx, 0.46), (mx + tilt, 0.16)], (248, 138, 120, 255), 0.028)
        c.poly([(mx + tilt - 0.055, 0.19), (mx + tilt, 0.07),
                (mx + tilt + 0.055, 0.19)], (238, 234, 226, 255))
        c.poly([(mx + tilt - 0.055, 0.19), (mx + tilt, 0.07),
                (mx + tilt, 0.19)], WHITE)
        c.rect(mx - 0.05, 0.35, mx + 0.05, 0.385, (238, 226, 214, 255))
    c.circle(0.5, 0.52, 0.032, (250, 196, 92, 255))


# --- 17 curse: skull totem on a staff, purple wisps -------------------------
def t_curse(c):
    tower_pad(c, "arcane")
    _post(c, 0.5, 0.38, 0.70, 0.072, (96, 74, 58, 255))
    _tglow(c, 0.5, 0.28, 0.20, (168, 96, 236))
    # bound bones crossing the staff
    c.line([(0.30, 0.50), (0.70, 0.44)], (214, 208, 192, 255), 0.026)
    # skull
    bone = (232, 228, 214, 255)
    c.ellipse(0.5, 0.26, 0.19, 0.175, bone)
    c.ellipse(0.44, 0.22, 0.11, 0.09, mix(bone, WHITE, 0.45))
    c.rrect(0.40, 0.36, 0.60, 0.44, 0.02, bone)
    c.poly([(0.40, 0.40), (0.60, 0.40), (0.58, 0.44), (0.42, 0.44)],
           shade(bone, 0.7))
    for ex in (0.435, 0.565):
        c.ellipse(ex, 0.25, 0.055, 0.062, (34, 20, 46, 255))
        c.circle(ex, 0.255, 0.028, (198, 118, 250, 255))
        c.circle(ex - 0.008, 0.248, 0.012, (240, 216, 255, 255))
    c.poly([(0.5, 0.30), (0.47, 0.35), (0.53, 0.35)], (34, 20, 46, 255))
    # wisps
    c.circle(0.24, 0.34, 0.030, (168, 96, 236, 200))
    c.circle(0.78, 0.30, 0.024, (168, 96, 236, 200))


# --- 18 holy: radiant sunburst monument -------------------------------------
def t_holy(c):
    tower_pad(c, "gold")
    gold = (248, 214, 96, 255)
    _tglow(c, 0.5, 0.32, 0.22, (255, 232, 140))
    # sun rays behind
    for a in range(0, 360, 45):
        rx = 0.5 + 0.30 * math.cos(math.radians(a))
        ry = 0.32 + 0.30 * math.sin(math.radians(a))
        c.line([(0.5 + 0.14 * math.cos(math.radians(a)),
                 0.32 + 0.14 * math.sin(math.radians(a))), (rx, ry)],
               (250, 224, 132, 220), 0.028)
    # marble plinth
    c.poly([(0.34, 0.66), (0.66, 0.66), (0.60, 0.50), (0.40, 0.50)],
           (222, 214, 190, 255))
    c.poly([(0.34, 0.66), (0.50, 0.66), (0.50, 0.50), (0.40, 0.50)],
           (246, 242, 228, 255))
    # sun disc + cross
    c.circle(0.5, 0.32, 0.155, shade(gold, 0.66))
    c.circle(0.5, 0.32, 0.125, gold)
    c.circle(0.455, 0.28, 0.05, (255, 248, 206, 255))
    c.rect(0.475, 0.20, 0.525, 0.44, (255, 250, 224, 255))
    c.rect(0.40, 0.295, 0.60, 0.345, (255, 250, 224, 255))


# --- 19 magnet: horseshoe magnet on a coil housing --------------------------
def t_magnet(c):
    tower_pad(c, "stone")
    _plinth(c, 0.32, 0.68, 0.565, 0.675, (86, 74, 74, 255))
    # coil housing with copper windings
    c.rrect(0.30, 0.48, 0.70, 0.58, 0.03, (94, 90, 96, 255))
    for wx in (0.36, 0.44, 0.56, 0.64):
        c.line([(wx, 0.485), (wx, 0.575)], (196, 132, 66, 255), 0.022)
    # horseshoe (thick U, open downward)
    red = (214, 68, 60, 255)
    w = max(3, int(0.115 * c.s))
    c.d.arc(c._b(0.5, 0.32, 0.24, 0.24), 180, 360, fill=shade(red, 0.6), width=w)
    c.d.arc(c._b(0.5, 0.31, 0.24, 0.24), 185, 300, fill=red,
            width=max(2, int(0.085 * c.s)))
    c.d.arc(c._b(0.5, 0.295, 0.24, 0.24), 190, 250,
            fill=mix(red, WHITE, 0.42), width=max(2, int(0.035 * c.s)))
    # steel pole tips
    c.rect(0.20, 0.32, 0.32, 0.48, (196, 200, 210, 255))
    c.rect(0.20, 0.32, 0.26, 0.48, (232, 236, 244, 255))
    c.rect(0.68, 0.32, 0.80, 0.48, (168, 172, 182, 255))
    # field spark between the poles
    c.line([(0.30, 0.44), (0.42, 0.40), (0.58, 0.44), (0.70, 0.40)],
           (152, 216, 255, 210), 0.02)


# --- 20 teleport: standing stone arch with a swirling void ------------------
def t_teleport(c):
    tower_pad(c, "arcane")
    stone = (140, 134, 150, 255)
    # the void inside the arch (drawn first)
    _tglow(c, 0.5, 0.42, 0.20, (146, 88, 236))
    c.ellipse(0.5, 0.44, 0.215, 0.26, (48, 26, 74, 255))
    for i, r in enumerate((0.175, 0.115, 0.06)):
        col = mix((138, 82, 226, 255), WHITE, i * 0.28)
        c.d.arc(c._b(0.5, 0.44, r, r * 1.22), 30 + i * 110, 300 + i * 110,
                fill=col, width=max(2, int(0.038 * c.s)))
    c.circle(0.5, 0.44, 0.035, (238, 224, 255, 255))
    # arch: slim legs + a ROUND top so it reads as a gate, not a screen
    stone_hi = mix(stone, WHITE, 0.30)
    for sgn in (-1, 1):
        px = 0.5 + sgn * 0.30
        c.rect(px - 0.058, 0.34, px + 0.058, 0.70, stone)
        c.rect(px - 0.058, 0.34, px - 0.012, 0.70,
               stone_hi if sgn < 0 else shade(stone, 0.76))
        c.rect(px - 0.075, 0.70, px + 0.075, 0.745, shade(stone, 0.6))
        c.rect(px - 0.072, 0.30, px + 0.072, 0.35, shade(stone, 0.82))
    c.d.arc(c._b(0.5, 0.335, 0.36, 0.30), 182, 358, fill=stone,
            width=max(3, int(0.108 * c.s)))
    c.d.arc(c._b(0.5, 0.325, 0.36, 0.30), 186, 268, fill=stone_hi,
            width=max(2, int(0.038 * c.s)))
    # glowing keystone runes
    for rx, ry in ((0.5, 0.045), (0.235, 0.235), (0.765, 0.235)):
        c.circle(rx, ry, 0.030, (182, 124, 252, 255))
        c.circle(rx, ry, 0.014, (238, 224, 255, 255))


TOWERS = [t_arrow, t_cannon, t_lightning, t_fireball, t_frost, t_poison,
          t_sniper, t_gatling, t_mortar, t_beam, t_slowfield, t_alchemy,
          t_barracks, t_boomerang, t_thorn, t_missile, t_curse, t_holy,
          t_magnet, t_teleport]


# ----------------------------------------------------------------------------
# EVOLUTION TIERS (round 10)
#
# 40 evolved tower sprites are NOT 40 new drawings. They are the tier-1 drawing
# plus a TREATMENT, exactly the way the monster levels work (feats_for / colour
# ramp / cumulative kit) — because that is what makes a tier read as "the same
# tower, grown" rather than "a different tower with a similar name". Forty
# hand-authored evolutions would drift apart from each other and from the tier-1
# silhouette that the player has already learned to recognise on a 44px sprite.
#
# Three channels, applied cumulatively:
#   1. FOUNDATION  a taller, richer base under the tower — tier 2 gets a stone
#      collar and buttresses, tier 3 gets a second stepped tier and corner
#      pillars. This is the part that reads at a glance in the build bar.
#   2. AURA + LIGHT  a halo behind the silhouette, and for tier 3 a light column
#      through the body. Drawn BEHIND (Canvas.aura composites underneath), so it
#      never eats the shape.
#   3. SIGNATURE  one per-tower flourish per tier, so evolution is not a uniform
#      badge. Kept to two or three primitives — anything bigger fights the
#      tier-1 silhouette instead of extending it.
#
# Plus a global colour lift (see `_tier_lift`) so the palette climbs the way the
# monster ladder does: deeper and more saturated, never just brighter.
# ----------------------------------------------------------------------------

TIER_ACCENT = {2: (196, 214, 240, 255), 3: (250, 214, 108, 255)}
TIER_GLOW = {2: (120, 190, 255), 3: (255, 208, 96)}


def _tier_lift(img, tier):
    """Palette climb. Tier 2 cools and brightens (refined / forged); tier 3
    warms toward gold and raises contrast (ascended). Applied to the finished
    sprite so every tower climbs the same ladder without 20 palette tables.

    Deliberately WEAK. The first attempt pushed tier 3 by +16% red / +16 flat
    and every tower came out the same mustard colour — a palette lift that
    erases the differences between twenty towers is not a lift, it is a tint.
    It also only touches near-opaque pixels: run over the halo as well and the
    glow turns into a coloured film across the whole 44px cell."""
    if tier <= 1:
        return img
    px = img.load()
    w, h = img.size
    warm = tier >= 3
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a < 200:
                continue
            if warm:
                r = clamp(r * 1.07 + 6)
                g = clamp(g * 1.03 + 3)
                b = clamp(b * 0.98)
            else:
                r = clamp(r * 1.01)
                g = clamp(g * 1.03 + 2)
                b = clamp(b * 1.06 + 5)
            px[x, y] = (r, g, b, a)
    return img


def _behind(c, fn):
    """Draw on a fresh layer and composite it UNDERNEATH what is already on the
    canvas. ImageDraw REPLACES alpha instead of blending, so a translucent fill
    drawn straight onto `c` comes out opaque — which is how the first tier-3
    light column ended up as a solid bar through the middle of all twenty
    towers. Canvas.aura() already solves this for halos; this is the general
    form of the same trick."""
    layer = Canvas(c.s)
    fn(layer)
    c.img = Image.alpha_composite(layer.img, c.img)
    c.d = ImageDraw.Draw(c.img)


def _tier_foundation(c, tier, accent):
    """Channel 1 — the base grows. Drawn BEFORE the tower body so the tower
    still sits on top of it."""
    stone = (128, 124, 132, 255)
    c.poly([(0.5, 0.575), (0.96, 0.735), (0.5, 0.90), (0.04, 0.735)],
           shade(stone, 0.82))
    c.poly([(0.5, 0.60), (0.90, 0.735), (0.5, 0.87), (0.10, 0.735)],
           mix(stone, WHITE, 0.22))
    # buttresses at the two lit corners
    for bx in (0.135, 0.865):
        c.rrect(bx - 0.045, 0.70, bx + 0.045, 0.80, 0.02, stone)
        c.circle(bx, 0.695, 0.030, accent)
    if tier >= 3:
        # a second stepped tier plus four corner pillars
        c.poly([(0.5, 0.66), (0.99, 0.80), (0.5, 0.955), (0.01, 0.80)],
               shade(stone, 0.68))
        for px_, py_ in ((0.075, 0.80), (0.925, 0.80), (0.30, 0.875), (0.70, 0.875)):
            c.rrect(px_ - 0.032, py_ - 0.105, px_ + 0.032, py_, 0.014,
                    mix(stone, WHITE, 0.10))
            c.circle(px_, py_ - 0.118, 0.026, accent)


def _tier_flourish(c, tier, accent, glow):
    """Channel 2 — halo, orbiting motes, and (tier 3) a light column.

    Everything atmospheric goes BEHIND the tower. The rule this enforces: at
    44px the silhouette is the only thing a player can actually read in the
    build bar, so nothing decorative is allowed in front of it."""
    if tier >= 3:
        def col(l):
            for hw, al in ((0.075, 30), (0.038, 52)):
                l.rect(0.5 - hw, 0.0, 0.5 + hw, 0.78,
                       (glow[0], glow[1], glow[2], al))
        _behind(c, col)
    # orbiting motes: four for tier 2, six for tier 3, on a squashed ring so
    # they read as circling the tower rather than stuck to it
    n = 6 if tier >= 3 else 4
    for k in range(n):
        a = math.tau * k / n + (0.4 if tier >= 3 else 0.0)
        # 0.36, not 0.42: at 0.42 the two side motes land in the empty margin of
        # the 44px cell and read as detached specks next to the tower instead of
        # as something orbiting it.
        mx = 0.5 + 0.36 * math.cos(a)
        my = 0.42 + 0.15 * math.sin(a)
        c.circle(mx, my, 0.026 if tier >= 3 else 0.021, accent)
        c.circle(mx - 0.007, my - 0.007, 0.010, WHITE)
    # _tglow, not Canvas.aura(): aura's 36/60/80 alphas over r*1.25 read as an
    # opaque disc on a 44px sprite (the same reason towers already had _tglow).
    _tglow(c, 0.5, 0.46, 0.34 if tier >= 3 else 0.30, glow)


def _sig_banner(c, x, ytop, col):
    c.rect(x - 0.010, ytop, x + 0.010, ytop + 0.30, (96, 78, 58, 255))
    c.poly([(x, ytop + 0.02), (x + 0.19, ytop + 0.07),
            (x, ytop + 0.13)], col)


def _sig_ring(c, cx, cy, r, col, w=0.020):
    c.d.arc(c._b(cx, cy, r, r * 0.42), 0, 360, fill=col,
            width=max(2, int(w * c.s)))


# One flourish per tower per tier. Deliberately small: the job is to say WHICH
# tower evolved, not to redraw it. `c` is the same canvas the tier-1 body was
# drawn on, so these land on top of the existing shape.
def _sig_towers(idx, c, tier, accent, glow):
    A, G = accent, (glow[0], glow[1], glow[2], 255)
    if idx == 1:      # 箭塔 -> 鷹眼 -> 神射殿: extra bow limbs, then a halo of arrows
        for sgn in (-1, 1):
            c.line([(0.5 + sgn * 0.10, 0.42), (0.5 + sgn * 0.40, 0.30)], A, 0.030)
        if tier >= 3:
            for k in range(5):
                ax = 0.16 + k * 0.17
                c.line([(ax, 0.18), (ax, 0.06)], G, 0.020)
    elif idx == 2:    # 加農 -> 雙管 -> 攻城巨砲
        _barrel(c, 0.36, 0.40, 0.80, 0.28, 0.075, IRON)
        if tier >= 3:
            _barrel(c, 0.36, 0.52, 0.86, 0.44, 0.090, shade(IRON, 0.8))
    elif idx == 3:    # 雷電 -> 雷霆之柱 -> 天罰穹頂
        _sig_ring(c, 0.5, 0.24, 0.34, G)
        if tier >= 3:
            _sig_ring(c, 0.5, 0.13, 0.44, A, 0.026)
    elif idx == 4:    # 火球 -> 煉獄 -> 炎魔祭壇
        for k, r in enumerate((0.075, 0.055)):
            c.circle(0.30 + k * 0.40, 0.30, r, (250, 140, 48, 255))
        if tier >= 3:
            c.poly([(0.5, 0.02), (0.36, 0.26), (0.5, 0.18), (0.64, 0.26)],
                   (255, 190, 70, 255))
    elif idx == 5:    # 冰霜 -> 極寒 -> 永冬王座
        for sgn in (-1, 1):
            c.poly([(0.5 + sgn * 0.30, 0.16), (0.5 + sgn * 0.20, 0.44),
                    (0.5 + sgn * 0.38, 0.40)], (200, 240, 255, 255))
        if tier >= 3:
            c.rrect(0.30, 0.06, 0.70, 0.20, 0.05, (176, 228, 250, 255))
    elif idx == 6:    # 毒液 -> 瘟疫 -> 腐化聖殿
        for k in range(3):
            c.circle(0.28 + k * 0.22, 0.20 - (k % 2) * 0.06, 0.045,
                     (140, 220, 90, 235))
        if tier >= 3:
            _sig_ring(c, 0.5, 0.30, 0.40, (150, 235, 110, 255), 0.024)
    elif idx == 7:    # 狙擊 -> 鷹巢 -> 天罰狙擊台
        c.line([(0.20, 0.40), (0.88, 0.22)], A, 0.036)
        if tier >= 3:
            _sig_ring(c, 0.80, 0.20, 0.14, G, 0.024)
    elif idx == 8:    # 機槍 -> 旋風 -> 風暴壁壘
        for k in range(4):
            c.circle(0.30 + k * 0.14, 0.34, 0.030, shade(STEEL, 1.0))
        if tier >= 3:
            _sig_ring(c, 0.5, 0.36, 0.40, G, 0.024)
    elif idx == 9:    # 迫擊 -> 重砲陣地 -> 軌道砲台
        c.rrect(0.10, 0.58, 0.30, 0.70, 0.03, IRON)
        if tier >= 3:
            c.line([(0.5, 0.34), (0.5, 0.02)], (255, 236, 170, 200), 0.045)
    elif idx == 10:   # 光束 -> 稜鏡 -> 恆星核心
        c.poly([(0.5, 0.14), (0.62, 0.34), (0.38, 0.34)], (230, 246, 255, 255))
        if tier >= 3:
            _orb(c, 0.5, 0.26, 0.13, (255, 226, 140, 255))
    elif idx == 11:   # 力場 -> 重力井 -> 時滯領域
        _sig_ring(c, 0.5, 0.52, 0.44, G, 0.024)
        if tier >= 3:
            _sig_ring(c, 0.5, 0.40, 0.30, A, 0.020)
    elif idx == 12:   # 鍊金 -> 鑄金坊 -> 賢者之塔
        for k in range(3):
            c.circle(0.24 + k * 0.10, 0.62 - k * 0.05, 0.038, (246, 206, 78, 255))
        if tier >= 3:
            _orb(c, 0.5, 0.20, 0.12, (255, 226, 120, 255))
    elif idx == 13:   # 兵營 -> 要塞 -> 聖殿騎士團
        _sig_banner(c, 0.20, 0.28, (208, 76, 68, 255))
        if tier >= 3:
            _sig_banner(c, 0.80, 0.24, (246, 214, 96, 255))
    elif idx == 14:   # 迴旋鏢 -> 雙刃 -> 風暴之輪
        _sig_ring(c, 0.5, 0.26, 0.30, A, 0.026)
        if tier >= 3:
            _sig_ring(c, 0.5, 0.26, 0.42, G, 0.020)
    elif idx == 15:   # 荊棘 -> 食人花 -> 世界樹根
        for k in range(5):
            bx = 0.14 + k * 0.18
            c.line([(bx, 0.62), (bx + 0.04, 0.34)], (120, 190, 90, 255), 0.024)
        if tier >= 3:
            c.circle(0.5, 0.26, 0.10, (168, 226, 110, 255))
    elif idx == 16:   # 導彈 -> 多管火箭 -> 末日發射井
        for k in range(3):
            c.line([(0.26 + k * 0.20, 0.52), (0.30 + k * 0.20, 0.20)],
                   (222, 92, 74, 255), 0.030)
        if tier >= 3:
            c.circle(0.5, 0.14, 0.075, (255, 120, 80, 255))
    elif idx == 17:   # 詛咒 -> 夢魘之環 -> 虛空祭壇
        _sig_ring(c, 0.5, 0.34, 0.38, (188, 120, 250, 255), 0.024)
        if tier >= 3:
            c.circle(0.5, 0.24, 0.12, (28, 14, 44, 255))
            _sig_ring(c, 0.5, 0.24, 0.20, (208, 150, 255, 255), 0.020)
    elif idx == 18:   # 聖光 -> 黎明聖壇 -> 神諭光柱
        _sig_ring(c, 0.5, 0.30, 0.42, (255, 238, 180, 255), 0.026)
        if tier >= 3:
            # its own, wider light column — this tower's whole identity is the
            # beacon, so it gets a bigger one than the generic tier-3 shaft
            def beacon(l):
                for hw, al in ((0.150, 34), (0.085, 60)):
                    l.rect(0.5 - hw, 0.0, 0.5 + hw, 0.60, (255, 240, 190, al))
            _behind(c, beacon)
    elif idx == 19:   # 磁力 -> 斥力核心 -> 極性風暴
        for sgn in (-1, 1):
            c.circle(0.5 + sgn * 0.28, 0.32, 0.055,
                     (226, 96, 88, 255) if sgn < 0 else (96, 156, 240, 255))
        if tier >= 3:
            _sig_ring(c, 0.5, 0.32, 0.40, G, 0.022)
    elif idx == 20:   # 傳送 -> 空間裂隙 -> 時空樞紐
        _sig_ring(c, 0.5, 0.34, 0.32, (186, 128, 252, 255), 0.026)
        if tier >= 3:
            _sig_ring(c, 0.5, 0.34, 0.44, (232, 208, 255, 255), 0.020)


def _draw_tower_tier(c, idx, fn, tier):
    accent = TIER_ACCENT[tier]
    glow = TIER_GLOW[tier]
    _tier_foundation(c, tier, accent)
    fn(c)
    _sig_towers(idx, c, tier, accent, glow)
    _tier_flourish(c, tier, accent, glow)


def gen_towers():
    n = 0
    for i, fn in enumerate(TOWERS, 1):
        img = render(lambda c, fn=fn: fn(c), TOWER_SIZE,
                     logical=TOWER_LOGICAL, outline=6)
        save(img, "towers", f"tower_{i}.png")
        n += 1
        for tier in (2, 3):
            timg = render(lambda c, i=i, fn=fn, t=tier: _draw_tower_tier(c, i, fn, t),
                          TOWER_SIZE, logical=TOWER_LOGICAL, outline=6)
            save(_tier_lift(timg, tier), "towers", f"tower_{i}_t{tier}.png")
            n += 1
    return n
