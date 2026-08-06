#!/usr/bin/env python3
"""
Procedural pixel-art generator for a mobile tower-defense game (Godot).
Pure standard-lib + Pillow. Run:  python tools/gen_art.py

Writes every PNG described in docs/design/CONTRACT.md to assets/generated/ .
Style: draw on a small logical grid, hard-edged pixels (no AA), a uniform dark
outline around each silhouette (via alpha dilation) and 2-3 flat cel-shading
tones (base / shadow / highlight). Transparent background.

Organisation:
  * palette-ramp + colour helpers
  * a small Canvas wrapper with normalised-coordinate primitive drawers
    (ellipse / rounded-rect / polygon / line / eyes / horns / wings ...)
  * (怪物已經唔喺呢度畫 —— 見 MONSTER FAMILIES 段同 monster_cutout.py)
  * one function per tower and per spell
All output is original; reference art was used only for palette / silhouette
direction.
"""

import argparse
import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "generated")

# ----------------------------------------------------------------------------
# colour helpers / palette ramp
# ----------------------------------------------------------------------------

def clamp(v, lo=0, hi=255):
    return max(lo, min(hi, int(round(v))))


def shade(rgb, f):
    """Multiply an RGB(A) colour by factor f (darker <1, lighter >1)."""
    r, g, b = rgb[:3]
    a = rgb[3] if len(rgb) > 3 else 255
    return (clamp(r * f), clamp(g * f), clamp(b * f), a)


def mix(a, b, t):
    """Linear blend of two RGB(A) colours, t in 0..1 towards b."""
    aa = a[3] if len(a) > 3 else 255
    ba = b[3] if len(b) > 3 else 255
    return (clamp(a[0] + (b[0] - a[0]) * t),
            clamp(a[1] + (b[1] - a[1]) * t),
            clamp(a[2] + (b[2] - a[2]) * t),
            clamp(aa + (ba - aa) * t))


WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)


def ramp(base, deepen=1.0):
    """Return a cel-shading ramp dict from a base colour.
    deepen>1 pushes colours deeper/brighter for higher creature levels."""
    b = shade(base, deepen)
    return {
        "base": b,
        "shadow": shade(b, 0.68),
        "hi": mix(b, WHITE, 0.42),
        "line": mix(shade(b, 0.35), BLACK, 0.55),   # near-black tinted outline
    }


DARKLINE = (24, 20, 34, 255)     # generic outline colour


# ----------------------------------------------------------------------------
# Canvas: normalised-coordinate primitive drawers (0..1 space)
# ----------------------------------------------------------------------------

class Canvas:
    def __init__(self, size):
        self.s = size
        self.img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def _b(self, cx, cy, rx, ry):
        s = self.s
        return [(cx - rx) * s, (cy - ry) * s, (cx + rx) * s, (cy + ry) * s]

    # --- primitives (normalised coords) -----------------------------------
    def ellipse(self, cx, cy, rx, ry, fill):
        self.d.ellipse(self._b(cx, cy, rx, ry), fill=fill)

    def circle(self, cx, cy, r, fill):
        self.ellipse(cx, cy, r, r, fill)

    def rrect(self, x0, y0, x1, y1, r, fill):
        s = self.s
        self.d.rounded_rectangle([x0 * s, y0 * s, x1 * s, y1 * s],
                                 radius=r * s, fill=fill)

    def rect(self, x0, y0, x1, y1, fill):
        s = self.s
        self.d.rectangle([x0 * s, y0 * s, x1 * s, y1 * s], fill=fill)

    def poly(self, pts, fill):
        s = self.s
        self.d.polygon([(x * s, y * s) for x, y in pts], fill=fill)

    def line(self, pts, fill, w=1):
        s = self.s
        self.d.line([(x * s, y * s) for x, y in pts], fill=fill,
                    width=max(1, int(round(w * s))), joint="curve")

    def dot(self, cx, cy, r, fill):
        self.circle(cx, cy, r, fill)

    # --- shared feature drawers -------------------------------------------
    def shadow(self, cx=0.5, cy=0.92, rx=0.30, ry=0.07):
        self.ellipse(cx, cy, rx, ry, (0, 0, 0, 70))

    def eyes(self, lx, rx, y, r, pal=None, glow=None, pupil=True):
        """Two eyes. glow = colour for glowing (undead) eyes."""
        if glow is not None:
            for ex in (lx, rx):
                self.circle(ex, y, r * 1.5, mix(glow, BLACK, 0.4))
                self.circle(ex, y, r, glow)
                self.circle(ex, y, r * 0.45, mix(glow, WHITE, 0.6))
            return
        for ex in (lx, rx):
            self.circle(ex, y, r, WHITE)
            if pupil:
                self.circle(ex, y, r * 0.55, DARKLINE)
                self.circle(ex - r * 0.2, y - r * 0.2, r * 0.18, WHITE)

    def horns(self, cx, y, spread, length, col, curve=0.10, base=0.032):
        """Curved, tapered horns with a bony base knob that OVERLAPS the head
        outline so they never read as floating (fixes the detached-horn bug).
        `y` should sit a touch INSIDE the skull/crown, not above it."""
        line = mix(shade(col, 0.4), BLACK, 0.45)
        hi = mix(col, WHITE, 0.35)
        for sgn in (-1, 1):
            bx = cx + sgn * spread
            tipx = cx + sgn * (spread + curve)
            tipy = y - length
            midx = bx + sgn * curve * 0.35
            midy = y - length * 0.55
            # dark outline horn (slightly larger)
            self.poly([(bx - base * 1.05, y + 0.02),
                       (bx + base * 1.05, y + 0.005),
                       (midx + sgn * base * 0.4, midy),
                       (tipx, tipy)], line)
            # coloured horn body, tapered to the tip
            self.poly([(bx - base * 0.66, y + 0.008),
                       (bx + base * 0.66, y - 0.004),
                       (midx, midy),
                       (tipx - sgn * 0.012, tipy + 0.02)], col)
            # connective base knob sitting on the head
            self.ellipse(bx, y, base * 1.15, base * 0.85, col)
            self.ellipse(bx, y - base * 0.15, base * 0.72, base * 0.5, hi)
            # ridge highlight up the front edge
            self.line([(bx, y - 0.005), (tipx - sgn * 0.01, tipy + 0.03)],
                      hi, 0.008)

    def wings(self, cx, cy, span, col, up=0.16):
        line = mix(shade(col, 0.4), BLACK, 0.5)
        for sgn in (-1, 1):
            base = cx + sgn * 0.02
            pts = [(base, cy),
                   (cx + sgn * span, cy - up * 2.2),
                   (cx + sgn * span * 0.9, cy + up * 0.1),
                   (cx + sgn * span * 0.62, cy + up * 0.7),
                   (cx + sgn * span * 0.55, cy + up * 0.15),
                   (cx + sgn * span * 0.30, cy + up * 0.6),
                   (base, cy + up * 0.7)]
            self.poly(pts, line)
            inner = [(base, cy + 0.01),
                     (cx + sgn * span * 0.86, cy - up * 1.7),
                     (cx + sgn * span * 0.62, cy + up * 0.0),
                     (base, cy + up * 0.55)]
            self.poly(inner, col)

    def crown(self, cx, y, w, col=(240, 205, 60, 255)):
        line = mix(col, BLACK, 0.45)
        x0, x1 = cx - w, cx + w
        base = y
        pts = [(x0, base), (x0, base - 0.05),
               (cx - w * 0.5, base - 0.02),
               (cx, base - 0.09),
               (cx + w * 0.5, base - 0.02),
               (x1, base - 0.05), (x1, base)]
        self.poly(pts, col)
        self.line([(x0, base + 0.005), (x1, base + 0.005)], line, 0.02)
        for gx in (x0, cx, x1):
            self.circle(gx, base - 0.055 if gx == cx else base - 0.05,
                        0.016, (235, 80, 90, 255))

    def aura(self, cx, cy, r, col):
        # Subtle glow halo. ImageDraw overwrites alpha instead of blending, so
        # draw the aura on its own layer and composite it BEHIND everything
        # already on the canvas -> shows only as a halo around the silhouette.
        layer = Image.new("RGBA", (self.s, self.s), (0, 0, 0, 0))
        ld = ImageDraw.Draw(layer)
        for a, rr in ((36, r * 1.25), (60, r * 1.0), (80, r * 0.72)):
            ld.ellipse(self._b(cx, cy, rr, rr),
                       fill=(col[0], col[1], col[2], a))
        self.img = Image.alpha_composite(layer, self.img)
        self.d = ImageDraw.Draw(self.img)


# ----------------------------------------------------------------------------
# outline via alpha dilation  +  finalize/scale
# ----------------------------------------------------------------------------

def add_outline(img, color=DARKLINE, width=1):
    a = img.split()[3]
    # only solid body pixels get outlined; faint glow/shadow (alpha<130) do not
    abin = a.point(lambda v: 255 if v > 130 else 0)
    dil = abin
    for _ in range(width):
        dil = dil.filter(ImageFilter.MaxFilter(3))
    edge = ImageChops.subtract(dil, abin)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    solid = Image.new("RGBA", img.size, color)
    layer.paste(solid, (0, 0), edge)
    return Image.alpha_composite(layer, img)


def render(draw_fn, size, logical=None, outline=1, outline_col=DARKLINE):
    """Draw at a logical grid then integer-scale (nearest) to `size`."""
    if logical is None:
        logical = size
    c = Canvas(logical)
    draw_fn(c)
    img = add_outline(c.img, outline_col, outline)
    if logical != size:
        img = img.resize((size, size), Image.NEAREST)
    return img


def save(img, *parts):
    path = os.path.join(OUT, *parts)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


# ============================================================================
# MONSTER FAMILIES —— 【2026-08-06 起唔再由呢度生成】
# ============================================================================
# 怪物 sprite 而家係由 `art_reference/monster/` 嗰 10 張 sprite sheet 摳出嚟,
# 管線喺 `tools/monster_cutout.py`。舊嗰套程序畫法(10 個 draw fn + 10 個 boss
# fn + level_ramp / feats_for / chest_armor / pauldrons / helm / cape /
# back_spikes / insect_legs)成段搬咗去 `tools/deprecated/gen_art_monsters_v1.py`
# 封存。
#
# **唔好喺呢度再加返 gen_monsters()。** 佢一行就會用 32-44px 嘅程序圖冚走
# assets/generated/monsters/ 入面嗰 60 張新圖,而且冇聲冇氣。
FAMILY_IDS = ["goblin", "wolf", "skeleton", "golem", "ghost",
              "bat", "treant", "beetle", "cultist", "slime"]



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


# ============================================================================
# SPELL ICONS (64x64 rounded-square element-tinted frame + bold glyph)
# ============================================================================

def spell_frame(c, tint):
    # bevelled rounded square
    c.rrect(0.06, 0.06, 0.94, 0.94, 0.16, mix(tint, BLACK, 0.55))
    c.rrect(0.09, 0.09, 0.91, 0.91, 0.14, mix(tint, BLACK, 0.15))
    c.rrect(0.11, 0.11, 0.89, 0.55, 0.12, mix(tint, WHITE, 0.22))
    c.rrect(0.11, 0.55, 0.89, 0.89, 0.12, mix(tint, BLACK, 0.25))
    # inner vignette
    c.rrect(0.13, 0.13, 0.87, 0.87, 0.11, mix(tint, BLACK, 0.05))


def buff_arrow(c, x, y, col=(90, 220, 90, 255)):
    c.poly([(x, y - 0.10), (x - 0.06, y), (x - 0.02, y),
            (x - 0.02, y + 0.10), (x + 0.02, y + 0.10),
            (x + 0.02, y), (x + 0.06, y)], col)


def sp_meteor(c):
    spell_frame(c, (200, 90, 50, 255))
    c.line([(0.16, 0.14), (0.5, 0.5)], (255, 200, 90, 220), 0.05)
    c.line([(0.26, 0.12), (0.55, 0.46)], (255, 160, 60, 200), 0.03)
    c.circle(0.60, 0.60, 0.16, (120, 70, 50, 255))
    c.circle(0.55, 0.55, 0.09, (255, 150, 50, 255))
    c.circle(0.58, 0.58, 0.05, (255, 230, 120, 255))


def sp_lightning(c):
    spell_frame(c, (220, 200, 60, 255))
    for off in (-0.16, 0.06):
        c.poly([(0.5 + off, 0.16), (0.42 + off, 0.5), (0.5 + off, 0.5),
                (0.42 + off, 0.84), (0.62 + off, 0.42),
                (0.54 + off, 0.42), (0.6 + off, 0.16)],
               (255, 230, 70, 255))


def sp_frost(c):
    spell_frame(c, (80, 190, 220, 255))
    col = (200, 240, 255, 255)
    for a in range(0, 360, 60):
        rad = math.radians(a)
        ex, ey = 0.5 + 0.30 * math.cos(rad), 0.5 + 0.30 * math.sin(rad)
        c.line([(0.5, 0.5), (ex, ey)], col, 0.03)
        mx, my = 0.5 + 0.18 * math.cos(rad), 0.5 + 0.18 * math.sin(rad)
        c.line([(mx, my), (mx + 0.06 * math.cos(rad + 1),
                           my + 0.06 * math.sin(rad + 1))], col, 0.02)
    c.circle(0.5, 0.5, 0.05, WHITE)


def sp_poison(c):
    spell_frame(c, (100, 180, 60, 255))
    c.aura(0.5, 0.5, 0.24, (120, 210, 70))
    c.circle(0.5, 0.5, 0.16, (200, 235, 210, 255))  # skull
    c.rect(0.42, 0.56, 0.58, 0.66, (200, 235, 210, 255))
    for ex in (0.44, 0.56):
        c.circle(ex, 0.48, 0.035, (60, 110, 40, 255))
    c.poly([(0.5, 0.52), (0.47, 0.58), (0.53, 0.58)], (60, 110, 40, 255))


def sp_militia(c):
    spell_frame(c, (70, 130, 210, 255))
    for i, x in enumerate((0.30, 0.5, 0.70)):
        y = 0.5 if i == 1 else 0.56
        col = (200, 220, 245, 255)
        c.circle(x, y - 0.16, 0.07, col)
        c.rrect(x - 0.09, y - 0.08, x + 0.09, y + 0.24, 0.04, col)
    buff_arrow(c, 0.5, 0.5)


def sp_gold(c):
    spell_frame(c, (225, 190, 60, 255))
    gold = (245, 210, 70, 255)
    c.circle(0.5, 0.42, 0.18, gold)
    c.circle(0.5, 0.42, 0.13, mix(gold, WHITE, 0.3))
    c.line([(0.5, 0.34), (0.5, 0.50)], shade(gold, 0.6), 0.03)
    c.line([(0.44, 0.38), (0.56, 0.38)], shade(gold, 0.6), 0.022)
    c.line([(0.44, 0.46), (0.56, 0.46)], shade(gold, 0.6), 0.022)
    # hand
    c.rrect(0.34, 0.62, 0.66, 0.78, 0.04, (240, 200, 160, 255))


def sp_timewarp(c):
    spell_frame(c, (60, 170, 170, 255))
    gold = (230, 220, 200, 255)
    c.poly([(0.34, 0.20), (0.66, 0.20), (0.5, 0.5)], (150, 230, 230, 255))
    c.poly([(0.5, 0.5), (0.34, 0.80), (0.66, 0.80)], (150, 230, 230, 255))
    c.rect(0.30, 0.16, 0.70, 0.20, gold)
    c.rect(0.30, 0.80, 0.70, 0.84, gold)
    c.circle(0.5, 0.5, 0.03, (255, 240, 180, 255))


def sp_warcry(c):
    spell_frame(c, (210, 120, 50, 255))
    # horn
    c.d.arc(c._b(0.5, 0.55, 0.22, 0.22), 180, 340,
            fill=(230, 210, 120, 255), width=max(2, int(0.06 * c.s)))
    c.circle(0.72, 0.55, 0.06, (245, 225, 140, 255))
    buff_arrow(c, 0.40, 0.42, (255, 120, 60, 255))
    buff_arrow(c, 0.55, 0.36, (255, 160, 70, 255))


def sp_barrier(c):
    spell_frame(c, (90, 150, 220, 255))
    sh = (200, 220, 250, 255)
    c.poly([(0.5, 0.18), (0.78, 0.30), (0.72, 0.62),
            (0.5, 0.82), (0.28, 0.62), (0.22, 0.30)], sh)
    c.poly([(0.5, 0.18), (0.5, 0.82), (0.28, 0.62), (0.22, 0.30)],
           mix(sh, (120, 170, 230, 255), 0.5))
    c.line([(0.5, 0.28), (0.5, 0.70)], WHITE, 0.02)
    c.line([(0.34, 0.42), (0.66, 0.42)], WHITE, 0.02)


def sp_tornado(c):
    spell_frame(c, (110, 150, 120, 255))
    col = (210, 225, 210, 255)
    for i, (y, w) in enumerate([(0.24, 0.26), (0.36, 0.22), (0.48, 0.17),
                                (0.60, 0.12), (0.72, 0.07)]):
        c.d.arc(c._b(0.5, y, w, 0.05), 0, 360, fill=col,
                width=max(1, int(0.025 * c.s)))
    c.line([(0.5, 0.74), (0.44, 0.86)], col, 0.02)


def sp_earthquake(c):
    spell_frame(c, (150, 110, 60, 255))
    ground = (150, 110, 66, 255)
    c.rect(0.14, 0.56, 0.86, 0.82, ground)
    c.rect(0.14, 0.56, 0.86, 0.62, mix(ground, WHITE, 0.25))
    c.line([(0.5, 0.56), (0.44, 0.66), (0.54, 0.74), (0.48, 0.82)],
           (60, 44, 26, 255), 0.03)
    c.line([(0.30, 0.62), (0.26, 0.70)], (60, 44, 26, 255), 0.02)
    c.line([(0.70, 0.62), (0.74, 0.72)], (60, 44, 26, 255), 0.02)
    # debris
    for dx, dy in ((0.30, 0.42), (0.5, 0.36), (0.68, 0.44)):
        c.poly([(dx, dy), (dx + 0.05, dy + 0.03), (dx + 0.02, dy + 0.07)],
               shade(ground, 0.7))


def sp_flamewall(c):
    spell_frame(c, (210, 80, 50, 255))
    for i, x in enumerate((0.28, 0.44, 0.60, 0.74)):
        h = 0.30 + 0.06 * (i % 2)
        c.poly([(x - 0.08, 0.80), (x - 0.04, 0.80 - h),
                (x, 0.80 - h * 0.6), (x + 0.04, 0.80 - h),
                (x + 0.08, 0.80)], (240, 120, 40, 255))
        c.poly([(x - 0.04, 0.80), (x, 0.80 - h * 0.55),
                (x + 0.04, 0.80)], (255, 210, 90, 255))
    c.rect(0.18, 0.78, 0.82, 0.86, (120, 60, 30, 255))


def sp_heavenbolt(c):
    spell_frame(c, (230, 220, 120, 255))
    c.aura(0.5, 0.2, 0.14, (255, 245, 180))
    c.poly([(0.52, 0.10), (0.36, 0.52), (0.50, 0.52),
            (0.40, 0.90), (0.68, 0.40), (0.54, 0.40), (0.66, 0.10)],
           (255, 245, 120, 255))
    c.poly([(0.52, 0.10), (0.44, 0.44), (0.50, 0.44), (0.46, 0.70)],
           WHITE)


def sp_emp(c):
    spell_frame(c, (150, 90, 220, 255))
    col = (210, 170, 250, 255)
    for a in range(0, 360, 45):
        rad = math.radians(a)
        r = 0.30 if a % 90 == 0 else 0.18
        c.line([(0.5, 0.5), (0.5 + r * math.cos(rad),
                             0.5 + r * math.sin(rad))], col, 0.03)
    c.circle(0.5, 0.5, 0.10, (190, 140, 245, 255))
    # z
    c.line([(0.44, 0.44), (0.56, 0.44), (0.44, 0.56), (0.56, 0.56)],
           WHITE, 0.022)


def sp_blackhole(c):
    spell_frame(c, (90, 60, 130, 255))
    for i, r in enumerate((0.34, 0.26, 0.18)):
        col = mix((150, 90, 220, 255), BLACK, 0.2 + i * 0.25)
        c.d.arc(c._b(0.5, 0.5, r, r), i * 100, i * 100 + 300, fill=col,
                width=max(2, int(0.05 * c.s)))
    c.circle(0.5, 0.5, 0.10, (12, 8, 20, 255))
    c.circle(0.5, 0.5, 0.10, None)
    c.d.ellipse(c._b(0.5, 0.5, 0.10, 0.10), outline=(180, 120, 240, 255),
                width=max(1, int(0.02 * c.s)))


SPELLS = [sp_meteor, sp_lightning, sp_frost, sp_poison, sp_militia, sp_gold,
          sp_timewarp, sp_warcry, sp_barrier, sp_tornado, sp_earthquake,
          sp_flamewall, sp_heavenbolt, sp_emp, sp_blackhole]


# --- evolved spell icons ----------------------------------------------------
# A spell icon is a FRAME plus a GLYPH, and the glyph is the spell's identity —
# so evolution upgrades the frame and lifts the glyph, it does not redraw it.
# The player has to tell tier apart in the quick bar at 44px while a fight is
# running, which rules out anything subtle: the tier reads from the BORDER
# (studded silver -> ornate gold) and from the corner pips (2 -> 3), both of
# which survive being shrunk and both of which sit outside the glyph area.

SPELL_TIER_RIM = {2: (206, 218, 236, 255), 3: (250, 208, 96, 255)}


def _spell_tier_frame(c, tier):
    rim = SPELL_TIER_RIM[tier]
    # outer bevelled ring
    c.d.rounded_rectangle([0.02 * c.s, 0.02 * c.s, 0.98 * c.s, 0.98 * c.s],
                          radius=0.17 * c.s, outline=mix(rim, BLACK, 0.45),
                          width=max(2, int(0.055 * c.s)))
    c.d.rounded_rectangle([0.035 * c.s, 0.035 * c.s, 0.965 * c.s, 0.965 * c.s],
                          radius=0.16 * c.s, outline=rim,
                          width=max(2, int(0.030 * c.s)))
    # corner studs: the tier count, placed where no glyph ever reaches
    for cx_, cy_ in ((0.10, 0.10), (0.90, 0.10), (0.10, 0.90), (0.90, 0.90)):
        c.circle(cx_, cy_, 0.052, mix(rim, BLACK, 0.35))
        c.circle(cx_, cy_, 0.032, mix(rim, WHITE, 0.45))
    if tier >= 3:
        # ornate mid-edge fleurons + an inner gold hairline
        for cx_, cy_ in ((0.5, 0.045), (0.5, 0.955), (0.045, 0.5), (0.955, 0.5)):
            c.circle(cx_, cy_, 0.055, mix(rim, BLACK, 0.30))
            c.circle(cx_, cy_, 0.032, WHITE)
        c.d.rounded_rectangle([0.115 * c.s, 0.115 * c.s, 0.885 * c.s, 0.885 * c.s],
                              radius=0.11 * c.s, outline=mix(rim, WHITE, 0.30),
                              width=max(1, int(0.014 * c.s)))
    # tier pips along the bottom edge — countable even at 44px
    pips = tier
    for k in range(pips):
        px_ = 0.5 + (k - (pips - 1) / 2.0) * 0.13
        c.circle(px_, 0.915, 0.040, mix(rim, BLACK, 0.55))
        c.circle(px_, 0.910, 0.026, mix(rim, WHITE, 0.55))


def gen_spells():
    n = 0
    for i, fn in enumerate(SPELLS, 1):
        # frame drawn edge-to-edge, no silhouette outline needed
        c = Canvas(264)
        fn(c)
        img = c.img.resize((44, 44), Image.NEAREST)
        save(img, "spells", f"spell_{i}.png")
        n += 1
        for tier in (2, 3):
            tc = Canvas(264)
            fn(tc)
            _spell_tier_frame(tc, tier)
            timg = _tier_lift(tc.img, tier).resize((44, 44), Image.NEAREST)
            save(timg, "spells", f"spell_{i}_t{tier}.png")
            n += 1
    return n


# ============================================================================
# UI / WORLD
# ============================================================================

def gen_coin():
    def draw(c):
        c.shadow(0.5, 0.9, 0.28, 0.05)
        gold = (245, 205, 60, 255)
        c.circle(0.5, 0.5, 0.40, shade(gold, 0.7))
        c.circle(0.5, 0.5, 0.35, gold)
        c.circle(0.5, 0.5, 0.26, mix(gold, WHITE, 0.25))
        c.circle(0.5, 0.5, 0.26, None)
        c.d.ellipse(c._b(0.5, 0.5, 0.26, 0.26), outline=shade(gold, 0.7),
                    width=max(1, int(0.02 * c.s)))
        # star motif
        c.line([(0.5, 0.34), (0.5, 0.66)], shade(gold, 0.65), 0.03)
        c.line([(0.36, 0.5), (0.64, 0.5)], shade(gold, 0.65), 0.03)
        # glint
        c.circle(0.40, 0.38, 0.05, WHITE)
    img = render(draw, 40, logical=160, outline=3)
    save(img, "ui", "coin.png")
    return 1


def gen_crystal():
    def draw(c):
        c.shadow(0.5, 0.92, 0.22, 0.05)
        c.aura(0.5, 0.46, 0.34, (150, 120, 240))
        base = (140, 110, 235, 255)
        # faceted gem (diamond)
        c.poly([(0.5, 0.10), (0.74, 0.40), (0.5, 0.86), (0.26, 0.40)], base)
        c.poly([(0.5, 0.10), (0.74, 0.40), (0.5, 0.42)],
               mix(base, WHITE, 0.35))
        c.poly([(0.5, 0.10), (0.26, 0.40), (0.5, 0.42)],
               mix(base, WHITE, 0.15))
        c.poly([(0.26, 0.40), (0.5, 0.42), (0.5, 0.86)], shade(base, 0.7))
        c.poly([(0.74, 0.40), (0.5, 0.42), (0.5, 0.86)], shade(base, 0.55))
        c.line([(0.5, 0.42), (0.5, 0.86)], mix(base, WHITE, 0.4), 0.02)
        c.circle(0.44, 0.30, 0.04, WHITE)
    img = render(draw, 40, logical=160, outline=3, outline_col=(40, 24, 70, 255))
    save(img, "ui", "crystal.png")
    return 1


def gen_base():
    # The fortress you defend: a stone keep / altar ring with a big glowing
    # crystal core + banners. Reads as a place with presence (ref: gameUI altar).
    def draw(c):
        stone = (138, 140, 150, 255)
        sdk = shade(stone, 0.66)
        shi = mix(stone, WHITE, 0.3)
        c.shadow(0.5, 0.95, 0.44, 0.05)
        # isometric stone platform
        c.poly([(0.5, 0.58), (0.92, 0.75), (0.5, 0.93), (0.08, 0.75)], stone)
        c.poly([(0.5, 0.58), (0.92, 0.75), (0.5, 0.82), (0.08, 0.75)], shi)
        c.poly([(0.08, 0.75), (0.5, 0.93), (0.5, 0.99), (0.08, 0.81)], sdk)
        c.poly([(0.92, 0.75), (0.5, 0.93), (0.5, 0.99), (0.92, 0.81)],
               shade(stone, 0.52))
        # crenellated back wall (little battlement teeth)
        for i in range(-3, 4):
            bx = 0.5 + i * 0.11
            c.rrect(bx - 0.048, 0.40, bx + 0.048, 0.60, 0.01, stone)
            c.rrect(bx - 0.048, 0.40, bx + 0.048, 0.46, 0.01, shi)
            c.rrect(bx - 0.048, 0.40, bx - 0.012, 0.60, 0.01, shi)
        c.rect(0.20, 0.54, 0.80, 0.68, sdk)  # wall base band
        c.rect(0.20, 0.54, 0.80, 0.575, mix(stone, WHITE, 0.18))
        # arched gate where the road meets the keep
        c.rrect(0.42, 0.58, 0.58, 0.72, 0.05, (36, 30, 44, 255))
        c.rrect(0.435, 0.60, 0.565, 0.72, 0.045, (74, 62, 52, 255))
        # altar pillars flanking the crystal
        for sgn in (-1, 1):
            px = 0.5 + sgn * 0.24
            c.rrect(px - 0.05, 0.40, px + 0.05, 0.72, 0.02, stone)
            c.rrect(px - 0.05, 0.40, px, 0.72, 0.02, shi)
            c.rrect(px - 0.06, 0.38, px + 0.06, 0.42, 0.01, sdk)
        # big glowing crystal core
        _tglow(c, 0.5, 0.40, 0.26, (150, 120, 240))
        base = (150, 120, 240, 255)
        c.poly([(0.5, 0.10), (0.68, 0.40), (0.5, 0.66), (0.32, 0.40)], base)
        c.poly([(0.5, 0.10), (0.68, 0.40), (0.5, 0.40)], mix(base, WHITE, 0.42))
        c.poly([(0.5, 0.10), (0.32, 0.40), (0.5, 0.40)], mix(base, WHITE, 0.18))
        c.poly([(0.32, 0.40), (0.5, 0.40), (0.5, 0.66)], shade(base, 0.68))
        c.poly([(0.68, 0.40), (0.5, 0.40), (0.5, 0.66)], shade(base, 0.52))
        c.line([(0.5, 0.40), (0.5, 0.66)], mix(base, WHITE, 0.4), 0.015)
        c.circle(0.44, 0.26, 0.035, WHITE)
        # banners on the pillars
        for sgn in (-1, 1):
            px = 0.5 + sgn * 0.24
            c.line([(px, 0.40), (px, 0.24)], (96, 80, 62, 255), 0.016)
            c.poly([(px, 0.25), (px + sgn * 0.11, 0.29), (px, 0.35)],
                   (70, 150, 220, 255))
            c.poly([(px, 0.25), (px + sgn * 0.09, 0.285), (px, 0.33)],
                   (110, 180, 235, 255))
    img = render(draw, 96, logical=576, outline=6, outline_col=(30, 24, 42, 255))
    save(img, "ui", "base.png")
    return 1


def gen_soldier():
    def draw(c):
        c.shadow(0.5, 0.9, 0.22, 0.05)
        # helmet head
        c.circle(0.5, 0.30, 0.16, (200, 210, 225, 255))
        c.rect(0.34, 0.28, 0.66, 0.34, (150, 160, 180, 255))  # visor band
        # body / armor
        c.rrect(0.34, 0.42, 0.66, 0.78, 0.06, (90, 130, 200, 255))
        c.rrect(0.34, 0.42, 0.5, 0.78, 0.06, mix((90, 130, 200, 255), WHITE, 0.25))
        # sword
        c.line([(0.70, 0.80), (0.82, 0.30)], (210, 214, 224, 255), 0.05)
        c.line([(0.62, 0.44), (0.78, 0.44)], (150, 110, 60, 255), 0.04)
        # legs
        c.rect(0.40, 0.78, 0.48, 0.90, (70, 90, 140, 255))
        c.rect(0.52, 0.78, 0.60, 0.90, (70, 90, 140, 255))
    img = render(draw, 20, logical=120, outline=3)
    save(img, "ui", "soldier.png")
    return 1


def gen_militia():
    """魔法召喚民兵 — deliberately NOT the barracks soldier.

    The two used to share ui/soldier.png and were indistinguishable on the field,
    which matters because one is permanent and the other expires. They are now
    separated by SILHOUETTE first, colour second, so the difference survives the
    20px source size: the soldier is a helmeted block with two legs and a sword
    sticking out; the militia is a hooded, legless robe that tapers to a ragged
    vapour hem, with nothing held. Even as a black shape they read apart.
    """
    ROBE = (150, 196, 246, 255)
    HOOD = (198, 228, 255, 255)
    VOID = (26, 42, 76, 255)
    GLOW = (156, 228, 255, 255)

    def draw(c):
        # a halo where the soldier has a ground shadow: this one floats. Kept
        # tight — a wide one turns into a visible box at 20px.
        c.aura(0.5, 0.52, 0.26, GLOW)
        # robe: narrow shoulders -> flare -> three-pointed vapour hem. No legs,
        # no feet, nothing held.
        body = [(0.50, 0.26), (0.66, 0.40), (0.75, 0.68), (0.68, 0.80),
                (0.61, 0.97), (0.55, 0.82), (0.50, 0.99), (0.45, 0.82),
                (0.39, 0.97), (0.32, 0.80), (0.25, 0.68), (0.34, 0.40)]
        c.poly(body, ROBE)
        # lit left side
        c.poly([(0.50, 0.26), (0.34, 0.40), (0.25, 0.68), (0.32, 0.80),
                (0.39, 0.97), (0.45, 0.82), (0.50, 0.99)],
               mix(ROBE, WHITE, 0.32))
        # tall peaked cowl — the shape a round helmet never makes
        c.poly([(0.50, 0.01), (0.60, 0.16), (0.66, 0.42), (0.34, 0.42),
                (0.40, 0.16)], HOOD)
        # An empty cowl shadow, centred. NOT two eyes: at a 20px source each eye
        # would be under two pixels and the pair merges into one blob, and NOT a
        # wide band either — that downscales into the barracks soldier's visor
        # slit, the one cue we cannot afford to duplicate. The rune glow the
        # design calls for is drawn per-frame in Soldier._draw() instead, where
        # it can pulse; baking it here would just be a static light smudge.
        c.rect(0.42, 0.26, 0.58, 0.35, VOID)
        # chest rune (a cross-slash), thick enough to survive the downscale
        c.line([(0.50, 0.52), (0.50, 0.68)], GLOW, 0.07)
        c.line([(0.41, 0.60), (0.59, 0.60)], GLOW, 0.07)

    img = render(draw, 20, logical=120, outline=3)
    save(img, "ui", "militia.png")
    return 1


def _noise(seed):
    import random
    return random.Random(seed)


def gen_ground():
    # Dark rocky battlefield floor (seamless). Round 5: the old tile scattered
    # 24 big soft ellipses that tiled into obvious "oil stains", and its grain
    # sat on a 1px grid while every sprite renders at 2x -> two different pixel
    # densities on screen. Now drawn at 64 and nearest-doubled to 128 so one
    # texel == one sprite texel, with fine even grain instead of blobs.
    half = 64
    img = Image.new("RGBA", (half, half), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    base = (56, 54, 65, 255)
    d.rectangle([0, 0, half, half], fill=base)
    rng = _noise(11)
    tones = [shade(base, 0.86), shade(base, 0.94), shade(base, 1.10),
             mix(base, (74, 70, 86, 255), 0.55)]
    for _ in range(700):
        d.point((rng.randint(0, half - 1), rng.randint(0, half - 1)),
                fill=rng.choice(tones))
    # small embedded stones: 2-tone, top-lit, never bigger than 4px
    for _ in range(26):
        x, y = rng.randint(2, half - 5), rng.randint(2, half - 5)
        r = rng.randint(1, 2)
        d.ellipse([x, y, x + r + 1, y + r + 1], fill=shade(base, 1.22))
        d.point((x, y), fill=shade(base, 1.45))
    # a few hairline cracks for large-scale interest (still low contrast)
    # kept few and very low contrast: at 4 cracks x 0.74 shade the shapes were
    # distinctive enough to read as a repeating wallpaper glyph once tiled
    for _ in range(3):
        x, y = rng.randint(4, half - 6), rng.randint(4, half - 6)
        for k in range(rng.randint(2, 4)):
            nx, ny = x + rng.randint(-2, 2), y + rng.randint(0, 2)
            d.line([x, y, nx, ny], fill=shade(base, 0.88))
            x, y = nx % half, ny % half
    img = img.resize((128, 128), Image.NEAREST)
    save(img, "tiles", "ground.png")
    return 1


def gen_road():
    # Dirt path tile for the Line2D road. LINE_TEXTURE_TILE maps the texture's
    # V axis ACROSS the road width and tiles U along its length, so this tile is
    # authored as a road CROSS-SECTION: packed dark shoulders at the top/bottom
    # edges, a lighter crowned centre with ruts and pebbles between them. That
    # turns the old "corrugated streaks" artefact into the road's own shading,
    # and lets Battle drop one of the three stacked Line2D layers.
    half = 64                      # authored at 1x then doubled (see gen_ground)
    img = Image.new("RGBA", (half, half), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    mid = (124, 104, 78, 255)
    edge = (70, 56, 42, 255)
    rng = _noise(23)
    for y in range(half):
        t = abs(y - (half - 1) / 2.0) / ((half - 1) / 2.0)   # 0 centre -> 1 edge
        if t > 0.86:
            col = shade(edge, 0.78)
        elif t > 0.70:
            col = edge
        elif t > 0.52:
            col = mix(edge, mid, 0.55)
        else:
            col = mix(mid, shade(mid, 1.10), 1.0 - t * 1.6)
        d.line([0, y, half, y], fill=col)
    # grain
    for _ in range(900):
        x, y = rng.randint(0, half - 1), rng.randint(0, half - 1)
        t = abs(y - (half - 1) / 2.0) / ((half - 1) / 2.0)
        f = rng.choice([0.86, 0.93, 1.08, 1.14])
        px = img.getpixel((x, y))
        d.point((x, y), fill=shade(px, f if t < 0.7 else (f + 1.0) * 0.5))
    # two wheel ruts running along the road
    for ry in (int(half * 0.36), int(half * 0.64)):
        for x in range(half):
            if rng.random() < 0.72:
                d.point((x, ry), fill=shade(mid, 0.72))
                d.point((x, ry + 1), fill=shade(mid, 0.86))
    # pebbles, kept off the very edge so the shoulder stays clean
    for _ in range(16):
        x = rng.randint(1, half - 4)
        y = rng.randint(int(half * 0.18), int(half * 0.82))
        d.ellipse([x, y, x + 2, y + 2], fill=shade(mid, 0.66))
        d.point((x, y), fill=mix(mid, WHITE, 0.35))
    img = img.resize((128, 128), Image.NEAREST)
    save(img, "tiles", "road.png")
    return 1


# --- scatter decorations (sprites placed off-road, purely cosmetic) ----------
def _deco_rock(c, tone=(126, 128, 142)):
    col = (tone[0], tone[1], tone[2], 255)
    c.shadow(0.5, 0.86, 0.32, 0.07)
    c.poly([(0.20, 0.80), (0.28, 0.42), (0.50, 0.30), (0.74, 0.44),
            (0.82, 0.80)], col)
    c.poly([(0.28, 0.42), (0.50, 0.30), (0.50, 0.64), (0.32, 0.68)],
           mix(col, WHITE, 0.30))
    c.poly([(0.50, 0.30), (0.74, 0.44), (0.74, 0.74), (0.50, 0.64)],
           shade(col, 0.68))
    c.line([(0.50, 0.34), (0.50, 0.76)], shade(col, 0.52), 0.035)


def _deco_rock2(c):
    # a low split boulder — clearly a different shape from rock1, not a re-tint
    col = (104, 102, 118, 255)
    c.shadow(0.5, 0.88, 0.36, 0.06)
    c.poly([(0.10, 0.82), (0.18, 0.58), (0.40, 0.50), (0.46, 0.82)], col)
    c.poly([(0.18, 0.58), (0.40, 0.50), (0.40, 0.70), (0.22, 0.74)],
           mix(col, WHITE, 0.30))
    c.poly([(0.50, 0.82), (0.58, 0.44), (0.82, 0.54), (0.88, 0.82)],
           shade(col, 0.88))
    c.poly([(0.58, 0.44), (0.82, 0.54), (0.82, 0.70), (0.60, 0.64)],
           mix(col, WHITE, 0.22))


def _deco_bones(c):
    # legible: one long bone + a rib pair + a jaw, instead of the old scribble
    bone = (214, 210, 194, 255)
    dk = shade(bone, 0.62)
    c.shadow(0.5, 0.84, 0.34, 0.06)
    # femur lying across
    c.line([(0.20, 0.62), (0.78, 0.54)], bone, 0.10)
    c.circle(0.20, 0.60, 0.085, bone)
    c.circle(0.20, 0.68, 0.075, bone)
    c.circle(0.79, 0.52, 0.080, bone)
    c.circle(0.79, 0.60, 0.070, bone)
    c.line([(0.24, 0.585), (0.74, 0.515)], mix(bone, WHITE, 0.45), 0.032)
    # two ribs behind
    c.d.arc(c._b(0.42, 0.40, 0.20, 0.16), 200, 340, fill=dk,
            width=max(2, int(0.05 * c.s)))
    c.d.arc(c._b(0.58, 0.34, 0.17, 0.14), 200, 340, fill=dk,
            width=max(2, int(0.045 * c.s)))


def _deco_skull(c):
    bone = (220, 216, 200, 255)
    c.shadow(0.5, 0.86, 0.26, 0.06)
    c.ellipse(0.5, 0.44, 0.26, 0.24, bone)
    c.ellipse(0.42, 0.38, 0.14, 0.11, mix(bone, WHITE, 0.4))
    c.rrect(0.37, 0.58, 0.63, 0.76, 0.03, bone)
    c.ellipse(0.40, 0.45, 0.085, 0.095, (30, 26, 38, 255))
    c.ellipse(0.60, 0.45, 0.085, 0.095, (30, 26, 38, 255))
    c.poly([(0.5, 0.52), (0.455, 0.62), (0.545, 0.62)], (30, 26, 38, 255))
    for gx in (0.42, 0.5, 0.58):
        c.line([(gx, 0.66), (gx, 0.76)], shade(bone, 0.62), 0.028)


def _deco_grass(c):
    g = (96, 142, 72, 255)
    c.shadow(0.5, 0.86, 0.22, 0.05)
    for x, h, sh in ((0.32, 0.34, 0.72), (0.44, 0.48, 1.0), (0.56, 0.40, 0.86),
                     (0.68, 0.30, 0.66)):
        col = shade(g, sh)
        c.poly([(x - 0.05, 0.82), (x + 0.02, 0.82 - h), (x + 0.05, 0.82)], col)
    c.poly([(0.44 - 0.05, 0.82), (0.44 + 0.02, 0.34), (0.44, 0.82)],
           mix(g, WHITE, 0.30))


def _deco_crack(c):
    lav = (36, 33, 42, 255)
    hi = (78, 74, 90, 255)
    c.line([(0.12, 0.48), (0.36, 0.56), (0.56, 0.44), (0.88, 0.52)], lav, 0.055)
    c.line([(0.36, 0.56), (0.44, 0.78)], lav, 0.04)
    c.line([(0.56, 0.44), (0.62, 0.24)], lav, 0.04)
    c.line([(0.14, 0.44), (0.36, 0.52)], hi, 0.02)


def _deco_bush(c):
    g = (62, 96, 58, 255)
    c.shadow(0.5, 0.86, 0.30, 0.06)
    c.ellipse(0.38, 0.58, 0.24, 0.20, g)
    c.ellipse(0.62, 0.62, 0.22, 0.18, shade(g, 0.78))
    c.ellipse(0.50, 0.46, 0.26, 0.21, mix(g, WHITE, 0.16))
    c.ellipse(0.42, 0.40, 0.13, 0.10, mix(g, WHITE, 0.38))
    c.circle(0.62, 0.50, 0.035, (188, 62, 74, 255))
    c.circle(0.34, 0.62, 0.030, (188, 62, 74, 255))


def _deco_pebbles(c):
    col = (118, 116, 130, 255)
    c.shadow(0.5, 0.80, 0.32, 0.05)
    for px, py, r in ((0.28, 0.62, 0.10), (0.52, 0.70, 0.075),
                      (0.70, 0.56, 0.09), (0.44, 0.50, 0.06)):
        c.circle(px, py, r, shade(col, 0.82))
        c.circle(px - r * 0.25, py - r * 0.28, r * 0.55, mix(col, WHITE, 0.34))


def _deco_stump(c):
    w = (112, 82, 52, 255)
    c.shadow(0.5, 0.88, 0.30, 0.06)
    c.rect(0.30, 0.44, 0.70, 0.84, w)
    c.rect(0.30, 0.44, 0.44, 0.84, mix(w, WHITE, 0.26))
    c.ellipse(0.5, 0.44, 0.20, 0.10, (156, 122, 78, 255))
    c.ellipse(0.5, 0.44, 0.12, 0.058, (128, 96, 60, 255))
    c.ellipse(0.5, 0.44, 0.05, 0.024, (156, 122, 78, 255))
    c.poly([(0.30, 0.62), (0.16, 0.72), (0.30, 0.74)], shade(w, 0.72))


def _deco_banner(c):
    # a broken standard stuck in the ground: the one tall silhouette in the set
    pole = (108, 88, 62, 255)
    c.shadow(0.5, 0.90, 0.20, 0.05)
    c.line([(0.46, 0.12), (0.52, 0.88)], pole, 0.055)
    c.line([(0.455, 0.14), (0.505, 0.60)], mix(pole, WHITE, 0.3), 0.018)
    cloth = (150, 60, 60, 255)
    c.poly([(0.50, 0.18), (0.84, 0.26), (0.80, 0.50), (0.50, 0.44)], cloth)
    c.poly([(0.50, 0.18), (0.68, 0.22), (0.66, 0.46), (0.50, 0.44)],
           mix(cloth, WHITE, 0.26))
    c.poly([(0.80, 0.50), (0.84, 0.42), (0.74, 0.46)], shade(cloth, 0.6))
    c.circle(0.46, 0.10, 0.045, (216, 186, 92, 255))


DECOS = [("rock1", _deco_rock), ("rock2", _deco_rock2), ("bones", _deco_bones),
         ("skull", _deco_skull), ("grass", _deco_grass), ("crack", _deco_crack),
         ("bush", _deco_bush), ("pebbles", _deco_pebbles),
         ("stump", _deco_stump), ("banner", _deco_banner)]


def gen_decorations():
    n = 0
    for name, fn in DECOS:
        img = render(lambda c, fn=fn: fn(c), 20, logical=120,
                     outline=(0 if name == "crack" else 6))
        save(img, "tiles", "deco_%s.png" % name)
        n += 1
    return n


def gen_menu_bg():
    # Shared menu backdrop for EVERY non-battle screen. Round 5: the old one was
    # a cool navy starfield with a grey moon — the one cold-palette asset left
    # after the warm UI redo, and it clashed with the bronze/wood frames laid on
    # top of it. Now a warm ember night: brown-maroon sky, drifting embers, a
    # low amber moon, warm hills and the keep silhouette (the purple crystal
    # stays — it is the game's currency accent).
    W, H = 360, 640
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)],
               fill=mix((30, 20, 22, 255), (74, 46, 38, 255), t ** 0.85))
    rng = _noise(7)
    # embers drifting in the upper sky (warm, not white stars)
    for _ in range(110):
        x = rng.randint(0, W - 1)
        y = rng.randint(0, int(H * 0.52))
        v = rng.randint(140, 250)
        d.point((x, y), fill=(v, int(v * 0.62), int(v * 0.3), 255))
    # low amber moon, fully inside the frame (the old one was cropped by the
    # screen edge and read as a stray grey dome behind the title)
    mx, my, mr = int(W * 0.78), int(H * 0.255), 28
    for a, rr in ((40, mr + 16), (70, mr + 8), (120, mr + 3)):
        d.ellipse([mx - rr, my - rr, mx + rr, my + rr], fill=(240, 160, 80, a))
    d.ellipse([mx - mr, my - mr, mx + mr, my + mr], fill=(248, 214, 150, 255))
    d.ellipse([mx - mr + 6, my - mr + 5, mx + 6, my + 4], fill=(255, 236, 190, 255))
    # warm hill ranges
    hz = int(H * 0.50)
    d.polygon([(0, hz), (55, hz - 66), (130, hz - 18), (210, hz - 84),
               (300, hz - 26), (W, hz - 74), (W, H), (0, H)], fill=(58, 36, 32, 255))
    hz2 = int(H * 0.60)
    d.polygon([(0, hz2), (90, hz2 - 52), (185, hz2 - 12), (285, hz2 - 58),
               (W, hz2 - 22), (W, H), (0, H)], fill=(44, 28, 25, 255))
    # central fortress silhouette on a mound
    fx = W // 2
    base_y = int(H * 0.62)
    sil = (28, 18, 18, 255)
    d.polygon([(fx - 120, base_y + 40), (fx - 70, base_y - 6),
               (fx + 70, base_y - 6), (fx + 120, base_y + 40)], fill=sil)
    d.rectangle([fx - 60, base_y - 70, fx + 60, base_y], fill=sil)
    for i in range(-3, 4):
        bx = fx + i * 18
        d.rectangle([bx - 7, base_y - 82, bx + 7, base_y - 66], fill=sil)
    for tx in (fx - 58, fx + 44):
        d.rectangle([tx - 12, base_y - 104, tx + 12, base_y], fill=sil)
        d.polygon([(tx - 16, base_y - 104), (tx, base_y - 128),
                   (tx + 16, base_y - 104)], fill=sil)
        # lit windows
        d.rectangle([tx - 3, base_y - 92, tx + 3, base_y - 84], fill=(236, 158, 62, 255))
    # glowing crystal above the keep (brand accent, kept purple)
    cy = base_y - 96
    for a, rr in ((40, 34), (70, 22), (110, 13)):
        d.ellipse([fx - rr, cy - rr, fx + rr, cy + rr],
                  fill=(150, 120, 240, a))
    d.polygon([(fx, cy - 20), (fx + 12, cy), (fx, cy + 22), (fx - 12, cy)],
              fill=(180, 150, 250, 255))
    d.polygon([(fx, cy - 20), (fx + 12, cy), (fx, cy)], fill=(210, 190, 255, 255))
    # foreground ground
    d.rectangle([0, int(H * 0.72), W, H], fill=(34, 24, 22, 255))
    for _ in range(400):
        x = rng.randint(0, W - 1)
        y = rng.randint(int(H * 0.72), H - 1)
        d.point((x, y), fill=shade((34, 24, 22, 255), rng.choice([0.7, 1.4])))
    img = img.resize((W * 3, H * 3), Image.NEAREST)
    save(img, "ui", "menu_bg.png")
    return 1


def gen_scrim():
    # Soft top-to-bottom darkening used over menu_bg so button text stays
    # readable. Replaces MainMenu's hard-edged ColorRect, which drew a visible
    # horizontal seam straight across the backdrop at y=500.
    W, H = 8, 256
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1.0)
        # transparent for the top third, then ease into a deep warm shadow
        a = 0.0 if t < 0.30 else min(1.0, (t - 0.30) / 0.34) ** 1.4
        d.line([(0, y), (W, y)], fill=(14, 10, 12, int(a * 205)))
    save(img.resize((W * 8, H * 8), Image.NEAREST), "ui", "scrim.png")
    return 1


def gen_title_plate():
    # Ornate wide banner the CJK title sits on: dark stone bar, gold metal frame,
    # crystal gems at the ends. Drawn crisp (used as a stretched 9-patch-ish plate).
    W, H = 96, 40
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    gold = (214, 176, 74, 255)
    goldd = shade(gold, 0.6)
    goldl = mix(gold, WHITE, 0.4)
    # outer gold frame
    d.rounded_rectangle([1, 3, W - 2, H - 4], radius=8, fill=goldd)
    d.rounded_rectangle([2, 4, W - 3, H - 6], radius=7, fill=gold)
    d.rounded_rectangle([2, 4, W - 3, H // 2], radius=7, fill=goldl)
    # inner dark stone
    d.rounded_rectangle([6, 8, W - 7, H - 9], radius=5, fill=(52, 34, 26, 255))
    d.rounded_rectangle([7, 9, W - 8, 17], radius=4, fill=(70, 46, 34, 255))
    d.rounded_rectangle([1, 3, W - 2, H - 4], radius=8, outline=(24, 18, 30, 255),
                        width=1)
    # crystal gems at both ends
    for gx in (7, W - 8):
        d.polygon([(gx, 10), (gx + 5, 20), (gx, 30), (gx - 5, 20)],
                  fill=(150, 120, 235, 255))
        d.polygon([(gx, 10), (gx + 5, 20), (gx, 20)], fill=(200, 180, 250, 255))
    img = img.resize((W * 4, H * 4), Image.NEAREST)
    save(img, "ui", "title_plate.png")
    return 1


def gen_portal():
    # Where the monsters come from. The old one was a flat grey donut with a
    # purple crescent — no threat, no presence. Now: a broken rune arch with a
    # dark maw and a violet vortex, sized to hold the top of the map.
    def draw(c):
        stone = (104, 100, 118, 255)
        hi = mix(stone, WHITE, 0.30)
        dk = shade(stone, 0.62)
        c.shadow(0.5, 0.93, 0.40, 0.06)
        # rocky mound the arch is set into
        c.poly([(0.06, 0.92), (0.16, 0.62), (0.5, 0.50), (0.84, 0.62),
                (0.94, 0.92)], dk)
        c.poly([(0.16, 0.62), (0.5, 0.50), (0.5, 0.74), (0.22, 0.80)],
               shade(stone, 0.78))
        # the maw
        c.ellipse(0.5, 0.56, 0.30, 0.34, (14, 10, 20, 255))
        # vortex inside
        _tglow(c, 0.5, 0.56, 0.30, (158, 92, 240))
        for i, r in enumerate((0.245, 0.175, 0.105)):
            col = mix((150, 88, 232, 255), WHITE, i * 0.26)
            c.d.arc(c._b(0.5, 0.56, r, r * 1.1), 20 + i * 96, 260 + i * 96,
                    fill=col, width=max(2, int(0.038 * c.s)))
        c.circle(0.5, 0.56, 0.062, (226, 206, 255, 255))
        # standing stones framing the maw (silhouette breakers)
        for sgn in (-1, 1):
            px = 0.5 + sgn * 0.36
            c.poly([(px - 0.085, 0.86), (px - 0.10, 0.36),
                    (px + 0.02, 0.26), (px + 0.09, 0.40), (px + 0.075, 0.86)],
                   stone)
            c.poly([(px - 0.10, 0.36), (px + 0.02, 0.26), (px + 0.01, 0.60),
                    (px - 0.09, 0.66)], hi if sgn < 0 else shade(stone, 0.8))
            c.circle(px, 0.50, 0.045, (176, 118, 250, 255))
        # cracked lintel
        c.poly([(0.10, 0.28), (0.42, 0.16), (0.46, 0.28), (0.14, 0.38)], stone)
        c.poly([(0.90, 0.28), (0.58, 0.16), (0.54, 0.28), (0.86, 0.38)],
               shade(stone, 0.82))
        c.circle(0.30, 0.26, 0.035, (176, 118, 250, 255))
        c.circle(0.70, 0.26, 0.032, (176, 118, 250, 255))
    img = render(draw, 72, logical=432, outline=6, outline_col=(26, 20, 36, 255))
    save(img, "tiles", "portal.png")
    return 1


# ============================================================================
# UI THEME  — stone/metal framed 9-patch panels, buttons, cards + pixel icons.
# Language after gameUI.jpg: chunky dark stone body, a lit top/left bevel, a
# shadowed bottom/right, a near-black keyline and forged metal rivets in the
# corners. All drawn crisp at final size (no scale) so borders stay sharp when
# used as StyleBoxTexture 9-patches (center + edges stretch, corners fixed).
# ============================================================================

# Warm frame palette (after gameUI.jpg / upgradeUI.jpg): a forged bronze-gold
# edge over deep-brown wood, warm parchment / warm-stone interiors, gold studs.
WOOD    = (104, 72, 42, 255)     # wood body
WOOD_D  = (62, 42, 24, 255)      # wood shadow
WOOD_L  = (156, 110, 62, 255)    # wood highlight (top-lit)
BRONZE  = (194, 150, 82, 255)    # metal edge band
BRONZE_D = (118, 86, 42, 255)
BRONZE_L = (244, 208, 132, 255)
GOLDSTUD = (248, 210, 104, 255)  # corner rivet/stud
WARMLINE = (32, 20, 12, 255)     # keyline (warm near-black)
PARCH   = (206, 178, 128, 255)   # parchment (light plates)
PARCH_D = (150, 122, 82, 255)


def _stud(d, cx, cy, r, col=GOLDSTUD):
    """A domed gold rivet/stud with a warm socket ring."""
    d.ellipse([cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1], fill=WARMLINE)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=shade(col, 0.62))
    d.ellipse([cx - r, cy - r, cx + r - 1, cy + r - 1], fill=col)
    d.ellipse([cx - r * 0.55, cy - r * 0.7, cx + r * 0.1, cy], fill=mix(col, WHITE, 0.7))


def _frame9(size, border, base, center, light, dark, line=WARMLINE,
            studs=True, stud_col=GOLDSTUD, radius=16, edge=None,
            center_top=None, grain=True, glow=False):
    """A warm rounded beveled frame for a 9-patch StyleBoxTexture.
    ALL decoration is confined to the `border` ring so the center tile is a
    clean vertical-gradient fill that stretches without smearing. The paired
    StyleBoxTexture must use texture_margin == border (see UI._TEX_MARGIN)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    b = border
    m = size - 1
    r = radius
    if edge is None:
        edge = mix(base, BRONZE, 0.5)
    # soft outer glow (fixed corner halo on important buttons)
    if glow:
        for i, gcol in enumerate(((*mix(stud_col, WHITE, 0.25)[:3], 55),
                                  (*stud_col[:3], 95))):
            gg = max(0, 3 - i * 2)
            d.rounded_rectangle([gg, gg, m - gg, m - gg], radius=r, fill=gcol)
    # rounded wood body
    d.rounded_rectangle([2, 2, m - 2, m - 2], radius=r, fill=base)
    # wood grain — only within the border band (never the stretch center)
    if grain:
        gs = shade(base, 0.86)
        for gx in range(6, size - 6, 6):
            d.line([(gx, 4), (gx, b - 2)], fill=gs)
            d.line([(gx, m - b + 2), (gx, m - 4)], fill=gs)
        for gy in range(6, size - 6, 6):
            d.line([(4, gy), (b - 2, gy)], fill=gs)
            d.line([(m - b + 2, gy), (m - 4, gy)], fill=gs)
    # raised outer bevel (rounded corners stay in fixed corner cells)
    d.arc([2, 2, m - 2, m - 2], 90, 270, fill=light, width=3)
    d.arc([2, 2, m - 2, m - 2], 270, 450, fill=dark, width=3)
    # bronze edge band — sharp rectangle just inside the ring (9-patch safe)
    eb = max(4, b - 8)
    d.rectangle([eb, eb, m - eb, m - eb], outline=edge, width=3)
    d.line([(eb + 2, eb + 1), (m - eb - 2, eb + 1)], fill=mix(edge, WHITE, 0.5), width=1)
    # flat sunken center (stretch region) with a soft top-lit vertical gradient
    ctop = center_top if center_top is not None else mix(center, WHITE, 0.06)
    for yy in range(b, m - b + 1):
        t = (yy - b) / max(1, (m - 2 * b))
        d.line([(b, yy), (m - b, yy)], fill=mix(ctop, center, t))
    # inner sunken bevel — straight lines on the center boundary (9-patch safe)
    d.line([(b, b), (m - b, b)], fill=shade(center, 0.5), width=2)
    d.line([(b, b), (b, m - b)], fill=shade(center, 0.5), width=2)
    d.line([(b, m - b), (m - b, m - b)], fill=mix(center, WHITE, 0.2), width=1)
    d.line([(m - b, b), (m - b, m - b)], fill=mix(center, WHITE, 0.2), width=1)
    # warm keyline
    d.rounded_rectangle([1, 1, m - 1, m - 1], radius=r, outline=line, width=2)
    # corner gold studs (fixed corner cells)
    if studs:
        rr = max(3, border // 5)
        off = border // 2
        for cx, cy in ((off, off), (m - off, off), (off, m - off), (m - off, m - off)):
            _stud(d, cx, cy, rr, stud_col)
    return img


def gen_ui_frames():
    n = 0
    P, PB = 96, 30      # panels: size / border(=texture_margin)
    # main wood panel (screens / tower panel)
    save(_frame9(P, PB, WOOD, (58, 47, 38, 255), WOOD_L, WOOD_D,
                 center_top=(78, 64, 52, 255)), "ui", "panel9.png"); n += 1
    # darker recessed panel (headers, stat blocks)
    save(_frame9(P, PB, WOOD_D, (46, 37, 30, 255), WOOD, (40, 26, 16, 255),
                 center_top=(62, 51, 41, 255)), "ui", "panel_dark9.png"); n += 1
    # parchment plate (light header banners / stat sheet)
    save(_frame9(P, PB, WOOD, (176, 150, 104, 255), WOOD_L, WOOD_D,
                 center_top=(206, 180, 130, 255)), "ui", "panel_parch9.png"); n += 1
    # raised wood button (normal) — bronze edge, top-lit
    save(_frame9(80, 24, WOOD, (122, 86, 50, 255), WOOD_L, WOOD_D,
                 center_top=(152, 108, 62, 255), edge=BRONZE), "ui", "btn9.png"); n += 1
    # accent (warm green — confirm / go) with glow
    save(_frame9(80, 24, (56, 96, 52, 255), (74, 126, 64, 255),
                 (140, 200, 110, 255), (30, 56, 28, 255),
                 center_top=(100, 160, 80, 255), edge=(150, 210, 120, 255),
                 stud_col=(210, 240, 150, 255), glow=True), "ui", "btn_accent9.png"); n += 1
    # danger (warm red — sell / quit)
    save(_frame9(80, 24, (140, 60, 44, 255), (172, 80, 56, 255),
                 (230, 140, 100, 255), (78, 30, 20, 255),
                 center_top=(198, 102, 68, 255), edge=(224, 150, 100, 255)),
         "ui", "btn_danger9.png"); n += 1
    # gold banner / important button — glowing gold
    save(_frame9(80, 24, (152, 110, 48, 255), (188, 138, 60, 255),
                 (246, 210, 120, 255), (86, 58, 22, 255),
                 center_top=(230, 184, 96, 255), edge=BRONZE_L,
                 stud_col=(255, 232, 150, 255), glow=True), "ui", "banner_gold9.png"); n += 1
    # tower card slot — wood product frame with bronze edge
    save(_frame9(80, 22, WOOD, (60, 48, 38, 255), WOOD_L, WOOD_D,
                 center_top=(80, 66, 52, 255), edge=BRONZE), "ui", "card9.png"); n += 1
    # spell slot — darker wood, thin frame
    save(_frame9(72, 20, WOOD_D, (50, 40, 32, 255), WOOD, (38, 26, 16, 255),
                 center_top=(66, 54, 44, 255), edge=BRONZE_D), "ui", "slot9.png"); n += 1
    # stat-bar track — warm recessed groove (small, uniform, stretch-safe)
    img = Image.new("RGBA", (32, 24), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, 31, 23], radius=10, fill=(30, 20, 12, 255))
    d.rounded_rectangle([2, 2, 29, 21], radius=8, fill=(52, 42, 32, 255))
    save(img, "ui", "bar_track9.png"); n += 1
    return n


def _bar_fill(name, c0, c1):
    """A horizontal gradient stat-bar fill (glossy, warm), for StyleBoxTexture."""
    w, h = 48, 24
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=8, fill=c1)
    for yy in range(h):
        t = yy / (h - 1)
        col = mix(mix(c0, WHITE, 0.25), c1, t)   # top-lit gloss
        d.line([(1, yy), (w - 2, yy)], fill=col)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=8, outline=shade(c1, 0.6), width=1)
    d.line([(3, 3), (w - 4, 3)], fill=(*mix(c0, WHITE, 0.6)[:3], 150), width=1)
    save(img, "ui", name)


def gen_bar_fills():
    _bar_fill("bar_gold9.png", (255, 214, 110, 255), (214, 150, 40, 255))
    _bar_fill("bar_green9.png", (150, 224, 120, 255), (72, 150, 60, 255))
    _bar_fill("bar_crystal9.png", (196, 150, 250, 255), (120, 78, 210, 255))
    _bar_fill("bar_red9.png", (255, 130, 96, 255), (196, 54, 44, 255))
    return 4


def _icon(size=48):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def _ic_stroke(d, pts, col, w):
    d.line(pts, fill=col, width=w, joint="curve")


def gen_ui_icons():
    n = 0
    W = (250, 244, 228, 255)      # warm cream icon ink
    OUT = (26, 16, 10, 255)
    s = 48

    def finish(img, name):
        # dark outline via dilation for the pixel "sticker" look
        out = add_outline(img, OUT, 2)
        save(out.resize((s, s), Image.NEAREST) if out.size != (s, s) else out,
             "ui", name)

    # pause ‖
    img, d = _icon(s)
    d.rounded_rectangle([14, 12, 21, 36], radius=2, fill=W)
    d.rounded_rectangle([27, 12, 34, 36], radius=2, fill=W)
    finish(img, "ic_pause.png"); n += 1
    # play ▶
    img, d = _icon(s)
    d.polygon([(16, 11), (16, 37), (38, 24)], fill=W)
    finish(img, "ic_play.png"); n += 1
    # fast-forward ▶▶
    img, d = _icon(s)
    d.polygon([(8, 13), (8, 35), (26, 24)], fill=W)
    d.polygon([(24, 13), (24, 35), (42, 24)], fill=W)
    finish(img, "ic_ff.png"); n += 1
    # sound ))
    img, d = _icon(s)
    d.polygon([(12, 20), (20, 20), (28, 12), (28, 36), (20, 28), (12, 28)], fill=W)
    d.arc([26, 14, 40, 34], -60, 60, fill=W, width=3)
    d.arc([22, 18, 34, 30], -60, 60, fill=W, width=3)
    finish(img, "ic_sound.png"); n += 1
    # mute (speaker + x)
    img, d = _icon(s)
    d.polygon([(10, 20), (18, 20), (26, 12), (26, 36), (18, 28), (10, 28)], fill=W)
    _ic_stroke(d, [(31, 17), (43, 31)], (235, 90, 80, 255), 4)
    _ic_stroke(d, [(43, 17), (31, 31)], (235, 90, 80, 255), 4)
    finish(img, "ic_mute.png"); n += 1
    # back arrow
    img, d = _icon(s)
    d.polygon([(22, 10), (8, 24), (22, 38)], fill=W)
    d.rounded_rectangle([20, 20, 40, 28], radius=3, fill=W)
    finish(img, "ic_back.png"); n += 1
    # shop (cart)
    img, d = _icon(s)
    _ic_stroke(d, [(9, 12), (15, 12), (20, 32), (38, 32)], W, 4)
    _ic_stroke(d, [(15, 18), (40, 18), (37, 30), (20, 30)], W, 3)
    d.ellipse([20, 35, 27, 42], fill=W)
    d.ellipse([32, 35, 39, 42], fill=W)
    finish(img, "ic_shop.png"); n += 1
    # skull (skills / bestiary)
    img, d = _icon(s)
    d.ellipse([12, 10, 36, 34], fill=W)
    d.rectangle([18, 28, 30, 40], fill=W)
    d.ellipse([16, 18, 24, 26], fill=OUT)
    d.ellipse([24, 18, 32, 26], fill=OUT)
    finish(img, "ic_skull.png"); n += 1
    # stats (bars)
    img, d = _icon(s)
    d.rectangle([10, 26, 18, 38], fill=W)
    d.rectangle([20, 18, 28, 38], fill=W)
    d.rectangle([30, 10, 38, 38], fill=W)
    finish(img, "ic_stats.png"); n += 1
    # upgrade (up chevrons)
    img, d = _icon(s)
    d.polygon([(24, 8), (10, 22), (18, 22), (18, 40), (30, 40), (30, 22), (38, 22)], fill=W)
    finish(img, "ic_up.png"); n += 1

    # --- upgrade-row stat icons (mapped by stat in Upgrade.gd) ---------------
    GOLDINK = (250, 214, 120, 255)
    # sword (damage / attack)
    img, d = _icon(s)
    d.polygon([(24, 6), (30, 12), (20, 32), (16, 28)], fill=W)          # blade
    d.polygon([(24, 6), (30, 12), (28, 14), (24, 10)], fill=(210, 216, 226, 255))
    _ic_stroke(d, [(12, 30), (22, 40)], (176, 132, 70, 255), 5)         # hilt guard
    d.rectangle([17, 33, 27, 43], fill=(150, 108, 60, 255))            # grip
    finish(img, "ic_sword.png"); n += 1
    # speed (double chevron — fire rate / attack speed)
    img, d = _icon(s)
    for ox in (0, 12):
        d.polygon([(10 + ox, 10), (24 + ox, 24), (10 + ox, 38),
                   (6 + ox, 34), (16 + ox, 24), (6 + ox, 14)], fill=W)
    finish(img, "ic_speed.png"); n += 1
    # scope (range — crosshair ring)
    img, d = _icon(s)
    d.ellipse([10, 10, 38, 38], outline=W, width=4)
    _ic_stroke(d, [(24, 4), (24, 14)], W, 3)
    _ic_stroke(d, [(24, 34), (24, 44)], W, 3)
    _ic_stroke(d, [(4, 24), (14, 24)], W, 3)
    _ic_stroke(d, [(34, 24), (44, 24)], W, 3)
    d.ellipse([21, 21, 27, 27], fill=W)
    finish(img, "ic_scope.png"); n += 1
    # star (crit / probability specials)
    img, d = _icon(s)
    pts = []
    for i in range(10):
        ang = math.radians(-90 + i * 36)
        rad = 18 if i % 2 == 0 else 8
        pts.append((24 + rad * math.cos(ang), 24 + rad * math.sin(ang)))
    d.polygon(pts, fill=GOLDINK)
    finish(img, "ic_star.png"); n += 1
    # spark (misc special — diamond burst)
    img, d = _icon(s)
    d.polygon([(24, 6), (32, 24), (24, 42), (16, 24)], fill=W)
    _ic_stroke(d, [(8, 24), (16, 24)], W, 3)
    _ic_stroke(d, [(32, 24), (40, 24)], W, 3)
    finish(img, "ic_spark.png"); n += 1
    # shield (durability / defensive)
    img, d = _icon(s)
    d.polygon([(24, 6), (40, 12), (40, 26), (24, 42), (8, 26), (8, 12)], fill=W)
    d.polygon([(24, 12), (34, 15), (34, 25), (24, 35), (14, 25), (14, 15)],
              fill=(176, 132, 70, 255))
    finish(img, "ic_shield.png"); n += 1
    # gold coin (economy)
    img, d = _icon(s)
    d.ellipse([8, 8, 40, 40], fill=GOLDINK)
    d.ellipse([8, 8, 40, 40], outline=(176, 120, 40, 255), width=2)
    d.ellipse([14, 14, 34, 34], outline=(176, 120, 40, 255), width=2)
    finish(img, "ic_coin.png"); n += 1
    # prev / next chevrons (tower navigation)
    img, d = _icon(s)
    d.polygon([(28, 10), (14, 24), (28, 38), (32, 34), (22, 24), (32, 14)], fill=W)
    finish(img, "ic_prev.png"); n += 1
    img, d = _icon(s)
    d.polygon([(20, 10), (34, 24), (20, 38), (16, 34), (26, 24), (16, 14)], fill=W)
    finish(img, "ic_next.png"); n += 1
    return n


def gen_ui_badges():
    """MAX seal (gold starburst medallion) for maxed upgrade rows."""
    s = 96
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = cy = s / 2
    # starburst rays
    for i in range(16):
        ang = math.radians(i * 22.5)
        r0, r1 = 30, 44
        x0, y0 = cx + r0 * math.cos(ang), cy + r0 * math.sin(ang)
        x1, y1 = cx + r1 * math.cos(ang), cy + r1 * math.sin(ang)
        d.line([(x0, y0), (x1, y1)], fill=(226, 170, 50, 255), width=4)
    d.ellipse([cx - 34, cy - 34, cx + 34, cy + 34], fill=(214, 150, 40, 255))
    d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], fill=(248, 210, 104, 255))
    d.ellipse([cx - 30, cy - 34, cx + 24, cy + 6], fill=(255, 234, 160, 255))  # top gloss
    d.ellipse([cx - 30, cy - 30, cx + 30, cy + 30], outline=(150, 100, 30, 255), width=2)
    save(img, "ui", "badge_max.png")
    return 1


# ---- upgrade showcase backdrops (per tower element) ------------------------
# Each: a moody vertical-gradient sky, distant ruined silhouette, a ground band
# and light atmospheric flecks. Used behind the big tower render in Upgrade.gd.
BACKDROPS = {
    # key:      (sky_top,          sky_horizon,      ground,           fleck)
    "fire":   ((44, 18, 14, 255), (150, 60, 26, 255), (58, 26, 18, 255), (255, 170, 70, 255)),
    "ice":    ((26, 40, 60, 255), (120, 160, 196, 255), (70, 90, 110, 255), (226, 244, 255, 255)),
    "poison": ((20, 38, 24, 255), (70, 120, 52, 255), (36, 52, 30, 255), (170, 226, 96, 255)),
    "arcane": ((34, 20, 42, 255), (110, 62, 140, 255), (48, 34, 52, 255), (206, 160, 255, 255)),
    "stone":  ((38, 26, 22, 255), (118, 84, 58, 255), (56, 42, 32, 255), (226, 190, 140, 255)),
}


def _backdrop(key, W=1024, H=560):
    top, horizon, ground, fleck = BACKDROPS[key]
    img = Image.new("RGBA", (W, H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    gh = int(H * 0.72)
    for y in range(H):
        if y < gh:
            t = y / gh
            col = mix(top, horizon, t * t)
        else:
            t = (y - gh) / (H - gh)
            col = mix(mix(ground, horizon, 0.25), shade(ground, 0.55), t)
        d.line([(0, y), (W, y)], fill=col)
    # translucent layers composited so they blend (PIL draw overwrites alpha)
    ov = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(ov)
    od.ellipse([W * 0.18, gh - 150, W * 0.82, gh + 70],
               fill=(*mix(horizon, WHITE, 0.5)[:3], 70))          # horizon glow
    # distant ruined silhouettes (a few crumbling towers)
    sil = (*shade(mix(top, horizon, 0.45), 0.62)[:3], 235)
    for bx, bw, bh in ((0.12, 0.10, 0.30), (0.72, 0.13, 0.42), (0.87, 0.08, 0.24)):
        x0 = int(W * bx); w = int(W * bw); y1 = gh
        y0 = int(gh - H * bh)
        od.rectangle([x0, y0, x0 + w, y1], fill=sil)
        for k in range(x0, x0 + w, max(6, w // 5)):              # battlements
            od.rectangle([k, y0 - 12, k + max(4, w // 8), y0], fill=sil)
    # atmospheric flecks (embers / snow / spores)
    rnd = 12345 + sum(top)
    for _i in range(110):
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        fx = rnd % W
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        fy = rnd % H
        rnd = (rnd * 1103515245 + 12345) & 0x7fffffff
        r = 1 + rnd % 3
        a = 50 + (rnd % 130)
        od.ellipse([fx, fy, fx + r, fy + r], fill=(*fleck[:3], a))
    img = Image.alpha_composite(img, ov)
    save(img, "ui", "bd_%s.png" % key)


def gen_upgrade_backdrops():
    for k in BACKDROPS:
        _backdrop(k)
    return len(BACKDROPS)


def gen_platform():
    """A decorative stone dais the showcased tower stands on."""
    W, H = 360, 150
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = W / 2
    # cast shadow
    d.ellipse([cx - 150, H - 44, cx + 150, H - 4], fill=(0, 0, 0, 90))
    # stacked stone tiers
    tiers = [(150, 96, (150, 132, 104, 255)),
             (120, 72, (172, 152, 118, 255)),
             (92, 52, (196, 176, 138, 255))]
    y = H - 30
    for rx, ry, col in tiers:
        d.ellipse([cx - rx, y - ry * 0.5, cx + rx, y + ry * 0.5], fill=shade(col, 0.6))
        d.ellipse([cx - rx, y - ry * 0.72, cx + rx, y + ry * 0.36], fill=col)
        d.ellipse([cx - rx, y - ry * 0.72, cx + rx, y + ry * 0.1],
                  fill=mix(col, WHITE, 0.22))
        # rim stones
        for a in range(0, 360, 30):
            sx = cx + rx * 0.94 * math.cos(math.radians(a))
            sy = y - ry * 0.18 + ry * 0.5 * math.sin(math.radians(a))
            d.ellipse([sx - 5, sy - 4, sx + 5, sy + 4], fill=shade(col, 0.82))
        y -= 26
    # top gold trim ring
    d.ellipse([cx - 92, y + 6, cx + 92, y + 6 + 26], outline=(214, 170, 70, 255), width=3)
    save(img, "ui", "platform.png")
    return 1


# ============================================================================
# CONTACT SHEET
# ============================================================================

# ============================================================================
# FX / 光環貼圖(合批輪)
# ============================================================================
# 呢一批唔係像素美術 —— 佢哋係本來由 GDScript `_draw()` 逐幀畫出嚟嘅圓、弧、
# 線,而家預繪成貼圖,喺遊戲入面用 Sprite2D / MultiMesh 畫。所以:
#   * 用 4x 超取樣再縮細(BOX = 純平均,唔會好似 LANCZOS 咁喺硬邊起振鈴),
#     出嚟係平滑邊,同 draw_circle / draw_arc 嘅 antialiased 一致
#   * 遊戲側要用 TEXTURE_FILTER_LINEAR(唔係 NEAREST)—— 呢啲係光暈唔係像素
#   * 每張貼圖記住「幾多 texture px = 幾多 world px」,GDScript 靠嗰個算 scale
#
# 一個貫穿全組嘅手法:**顏色由 modulate 帶,貼圖淨係帶形狀同相對 alpha**。
# 例如爆炸嘅煙圈原本係 Color(col.r*0.35, col.g*0.30, col.b*0.30, a*0.42),
# 貼圖就寫死 (0.35, 0.30, 0.30, 0.42) 嗰個像素,再乘上 modulate = (col, a) ——
# 乘出嚟同原本逐幀計嗰條式一模一樣,而一張貼圖服務得晒所有顏色嘅爆炸。
FX_SS = 4          # 超取樣倍數


def _fx_new(w, h):
    return Image.new("RGBA", (w * FX_SS, h * FX_SS), (0, 0, 0, 0))


def _fx_disc(base, cx, cy, r, col):
    """半透明圓 —— PIL 嘅 fill 會**覆寫** alpha,所以每一層要自己一張再合成。"""
    lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).ellipse([cx - r, cy - r, cx + r, cy + r], fill=col)
    return Image.alpha_composite(base, lay)


def _fx_poly(base, pts, col):
    lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).polygon(pts, fill=col)
    return Image.alpha_composite(base, lay)


def _fx_line(base, p0, p1, col, width):
    lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).line([p0, p1], fill=col, width=int(round(width)))
    return Image.alpha_composite(base, lay)


def _fx_ring(base, cx, cy, r, col, width):
    lay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).ellipse([cx - r, cy - r, cx + r, cy + r],
                                outline=col, width=int(round(width)))
    return Image.alpha_composite(base, lay)


def _fx_save(img, w, h, name):
    return save(img.resize((w, h), Image.BOX), "fx", name + ".png")


def _a(col, alpha):
    """RGB + 0..1 alpha -> RGBA"""
    return (col[0], col[1], col[2], clamp(alpha * 255.0))


CURSE_VIOLET = (158, 66, 219)


def gen_fx():
    n = 0
    S = FX_SS

    # --- 詛咒塔地面符文 ------------------------------------------------------
    # 兩隻實心碟。實心碟按比例放大係**完全準確**嘅(冇線寬呢個問題),所以
    # 一張 256 嘅貼圖服務得晒所有射程嘅詛咒塔。
    # 約定:貼圖代表 world 半徑 128 → sprite.scale = range / 128
    img = _fx_new(256, 256)
    c = 128 * S
    img = _fx_disc(img, c, c, 128 * S, _a(CURSE_VIOLET, 0.055))
    img = _fx_disc(img, c, c, 128 * 0.55 * S, _a(CURSE_VIOLET, 0.040))
    _fx_save(img, 256, 256, "curse_haze"); n += 1

    # 一粒符文:一條指向圓心嘅短劃 + 一粒亮點。世界尺寸 32x16,圓點喺正中,
    # 短劃向 -X 伸 —— sprite.rotation = 該粒符文喺圓周上嘅角度,劃就自然指向圓心。
    # alpha 用 0.80 做基準(原本嘅 0.55 + 0.25*pulse 嘅上限),遊戲側再乘返
    # (0.55 + 0.25*pulse) / 0.80。
    img = _fx_new(32, 16)
    cx, cy = 16 * S, 8 * S
    img = _fx_line(img, (cx, cy), (cx - 9 * S, cy), _a(CURSE_VIOLET, 0.80), 3 * S)
    img = _fx_disc(img, cx, cy, 2.6 * S, _a((219, 168, 255), 0.70))
    _fx_save(img, 128, 64, "curse_rune"); n += 1

    # 由符文陣飄上嚟嗰粒金點(掉金加成嗰半個身份)
    img = _fx_new(16, 16)
    img = _fx_disc(img, 8 * S, 8 * S, 3.4 * S, _a((255, 214, 77), 1.0))
    _fx_save(img, 64, 64, "curse_mote"); n += 1

    # 中咗詛咒嘅怪身上嗰個六角印(六角線 + 火苗 + 白點)。
    # 世界尺寸 16x24,原點(0,0)喺六角中心,火苗向上。
    img = _fx_new(16, 24)
    ox, oy = 8 * S, 16 * S
    hexpts = []
    for i in range(6):
        ang = math.tau * i / 6.0 - math.pi / 2.0
        hexpts.append((ox + math.cos(ang) * 7 * S, oy + math.sin(ang) * 7 * S))
    lay = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(lay).line(hexpts + [hexpts[0]], fill=_a((184, 92, 242), 0.90),
                             width=int(2 * S), joint="curve")
    img = Image.alpha_composite(img, lay)
    img = _fx_poly(img, [(ox, oy - 15 * S), (ox - 4.5 * S, oy - 4 * S),
                         (ox + 4.5 * S, oy - 4 * S)], _a((219, 133, 255), 0.85))
    img = _fx_disc(img, ox, oy - 6 * S, 2.2 * S, _a((255, 235, 255), 0.90))
    _fx_save(img, 64, 96, "curse_mark"); n += 1

    # --- 聖光 ---------------------------------------------------------------
    # 繞行光點:外暈 + 內核,兩層嘅半徑同 alpha 都跟同一個 k 走,所以貼圖烘
    # k=1,遊戲側 scale=k、modulate.a=k。
    img = _fx_new(16, 16)
    img = _fx_disc(img, 8 * S, 8 * S, 3.4 * S, _a((255, 235, 148), 0.75))
    img = _fx_disc(img, 8 * S, 8 * S, 1.6 * S, _a((255, 252, 224), 0.90))
    _fx_save(img, 64, 64, "holy_mote"); n += 1

    # 聖光塔本體嗰條向上散開嘅光柱(兩塊梯形疊埋)。
    # 世界尺寸 52x172,對應原本 y = -18 .. -190、x = -26 .. 26。
    img = _fx_new(52, 172)
    def _trap(w, alpha, im):
        pts = [((-w * 0.45 + 26) * S, (-18 + 190) * S),
               ((w * 0.45 + 26) * S, (-18 + 190) * S),
               ((w + 26) * S, 0.0),
               ((-w + 26) * S, 0.0)]
        return _fx_poly(im, pts, _a((255, 242, 184), alpha))
    img = _trap(26.0, 0.10, img)
    img = _trap(13.0, 0.16, img)
    _fx_save(img, 208, 688, "holy_pillar"); n += 1

    # 光柱腳嗰粒光核(半徑跟 pulse 走)
    img = _fx_new(32, 32)
    img = _fx_disc(img, 16 * S, 16 * S, 12 * S, _a((255, 247, 204), 0.35))
    _fx_save(img, 128, 128, "holy_core"); n += 1

    # --- Fx 粒子 ------------------------------------------------------------
    # 火星:暗暈(col*0.4, a*0.5)+ 本體(col, a)。貼圖存返嗰兩個比例,
    # modulate = (col.rgb, a) 一乘就完全還原。
    img = _fx_new(64, 64)
    img = _fx_disc(img, 32 * S, 32 * S, 32 * S, (102, 102, 102, 128))
    img = _fx_disc(img, 32 * S, 32 * S, 25.6 * S, (255, 255, 255, 255))
    _fx_save(img, 64, 64, "spark"); n += 1

    # 火星嘅白色高光 —— 分開一張,因為佢係**白色**唔跟 col 走,一張貼圖乘
    # 一個顏色係做唔到「本體染色、高光唔染色」嘅。
    img = _fx_new(64, 64)
    img = _fx_disc(img, (32 - 6.4) * S, (32 - 6.4) * S, 8.96 * S, (255, 255, 255, 179))
    _fx_save(img, 64, 64, "spark_hi"); n += 1

    # 金幣:菱形 + 高光
    img = _fx_new(64, 64)
    r = 25.6 * S
    img = _fx_poly(img, [(32 * S, 32 * S - r), (32 * S + r, 32 * S),
                         (32 * S, 32 * S + r), (32 * S - r, 32 * S)],
                   (255, 255, 255, 255))
    _fx_save(img, 64, 64, "coin"); n += 1
    img = _fx_new(64, 64)
    img = _fx_disc(img, (32 - 6.4) * S, (32 - 6.4) * S, 7.68 * S, (255, 255, 255, 230))
    _fx_save(img, 64, 64, "coin_hi"); n += 1

    # 爆炸本體:煙圈 + 五嚿唔規則嘅火 + 熱核 + 亮邊。
    # 約定:br_ref = 100 texture px,半邊 128 px → sprite.scale = br / 100。
    img = _fx_new(256, 256)
    C = 128 * S
    BR = 100 * S
    img = _fx_disc(img, C, C, BR * 1.06, (89, 77, 77, 107))          # 0.35/0.30/0.30 @ 0.42
    jitter = [(0.31, 0.55), (0.42, 0.63), (0.18, 0.49), (0.60, 0.71), (0.05, 0.58)]
    for i, (jang, jrad) in enumerate(jitter):
        ang = math.tau * i / 5.0 + jang * 0.7
        d = BR * jrad
        img = _fx_disc(img, C + math.cos(ang) * d, C + math.sin(ang) * d,
                       BR * 0.58, (255, 255, 255, 173))              # a*0.68
    img = _fx_disc(img, C, C, BR * 0.62, (255, 255, 255, 242))       # a*0.95
    img = _fx_ring(img, C, C, BR * 1.1, (255, 255, 255, 255), 3 * S)
    _fx_save(img, 256, 256, "burst"); n += 1

    # 爆炸嘅白色核心(半徑收縮得比本體快,所以佢係自己一個 sprite)
    img = _fx_new(128, 128)
    img = _fx_disc(img, 64 * S, 64 * S, 56 * S, (255, 255, 255, 230))
    _fx_save(img, 128, 128, "burst_core"); n += 1

    # 毒霧 / 氣團:五嚿散開嘅波 + 核 + 一點高光。orr_ref = 80 texture px。
    img = _fx_new(192, 192)
    C = 96 * S
    OR = 80 * S
    jit2 = [(0.62, 0.51), (0.19, 0.60), (0.88, 0.47), (0.34, 0.55), (0.71, 0.58)]
    for i, (jang, jrad) in enumerate(jit2):
        ang = math.tau * i / 5.0 + jang * 1.4
        off = OR * 0.41
        img = _fx_disc(img, C + math.cos(ang) * off, C + math.sin(ang) * off,
                       OR * jrad, (255, 255, 255, 107))              # a*0.42
    img = _fx_disc(img, C, C, OR * 0.55, (255, 255, 255, 140))       # a*0.55
    img = _fx_disc(img, C - OR * 0.18, C - OR * 0.20, OR * 0.24, (255, 255, 255, 71))
    _fx_save(img, 192, 192, "orb"); n += 1

    # 一條純白嘅棒 —— 爆炸碎片用。世界尺寸由 instance transform 決定,所以
    # 貼圖本身只需要係一格白。
    img = _fx_new(8, 8)
    img = _fx_disc(img, 4 * S, 4 * S, 8 * S, (255, 255, 255, 255))
    _fx_save(img, 8, 8, "bar"); n += 1
    return n


# ============================================================================
# TEXTURE ATLAS(合批輪)
# ============================================================================
# 量到嘅事實:高峰戰鬥一幀 1053 個 draw call 入面,單係「換貼圖」就佔咗
# 大約 270 個 —— 143 隻怪(60 張唔同嘅圖)124 個、43 座塔 37 個、120 個
# 地面裝飾 109 個。每一次換貼圖就斷一次 batch,即係話一隻哥布林同一隻骷髏
# 排喺一齊嗰陣,渲染器一定要出兩個 draw call,唔理佢哋幾細。
#
# 解法就係將佢哋放埋同一張圖 —— 咁樣所有怪物 sprite 用嘅係同一個 texture
# RID,合埋一個 batch。
#
# 三個實作決定:
#   * **分組跟「同時上畫」**,唔係跟資料夾。戰鬥入面同一幀會出現嘅嘢
#     (怪、塔、特效、裝飾、基地)入 battle 頁;介面嘅圖示同魔法卡入 ui 頁。
#     混埋一齊嘅話兩頁都要常駐,而分開就可以各自係一頁。
#   * **大圖唔入**。menu_bg / bd_* 呢啲全屏背景一張就食晒成頁,而且佢哋
#     同時最多得一張喺畫面上,本來就冇 batch 可言。
#   * **每格四邊向外擠出(extrude)**。texture_filter=NEAREST 加上鏡頭
#     縮放(0.5x-2x)之後,取樣點會落喺格邊上,一個 pixel 都會滲到隔籬格。
#     每格外圍 2px 複製返邊緣像素,滲出嚟嘅就係自己嘅邊,唔係人哋嘅身。
ATLAS_PAD = 2
## 呢啲唔可以入 atlas:佢哋靠 texture_repeat / Line2D 平鋪,而平鋪係對成張
## texture 講嘅,入咗 atlas 就會鋪埋隔籬格。
ATLAS_NEVER = {"tiles/ground.png", "tiles/road.png", "tiles/road_x.png"}
## 太大嘅唔入(一張就食晒成頁,而且冇 batch 可言)。
ATLAS_MAX_SIDE = 256


def _atlas_group(rel):
    """rel = 'monsters/goblin_1.png' -> 'battle' / 'ui' / None(唔入)"""
    folder, name = rel.split("/", 1)
    if rel in ATLAS_NEVER:
        return None
    # 9-patch 唔入:佢哋經 StyleBoxTexture 拉伸,而拉伸嘅取樣範圍係成張圖。
    # **只限 ui/** —— 9-patch 全部住喺嗰度,而「檔名尾係 9」呢個規則掃全場
    # 嘅話會順手剔走 tower_9 / tower_19 / spell_9 三張普通圖(踩過,由
    # test/AtlasTest 抓返出嚟)。
    if folder == "ui" and name.endswith("9.png"):
        return None
    if folder in ("monsters", "towers", "fx"):
        return "battle"
    if folder == "tiles":
        return "battle"
    if folder == "spells":
        return "ui"
    if folder == "ui":
        # 金幣同魔晶主要係介面圖示(主選單、商店、結算都有),放 battle 頁
        # 就等於一入主選單就為咗一粒 40px 嘅圖示載入成頁戰鬥圖 —— 實測
        # 主選單嘅 texture memory 因為咁多咗 2.6MB。
        if name.split(".")[0] in ("base", "soldier", "militia"):
            return "battle"
        return "ui"
    return None


def _extrude(im, pad):
    w, h = im.size
    out = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    out.paste(im, (pad, pad))
    out.paste(im.crop((0, 0, 1, h)).resize((pad, h), Image.NEAREST), (0, pad))
    out.paste(im.crop((w - 1, 0, w, h)).resize((pad, h), Image.NEAREST), (w + pad, pad))
    strip = out.crop((0, pad, w + 2 * pad, pad + 1))
    out.paste(strip.resize((w + 2 * pad, pad), Image.NEAREST), (0, 0))
    strip = out.crop((0, h + pad - 1, w + 2 * pad, h + pad))
    out.paste(strip.resize((w + 2 * pad, pad), Image.NEAREST), (0, h + pad))
    return out


def _shelf(items, page_w):
    """棚式排版(按高度由大到小)。回傳 (擺位, 用到嘅高度)。"""
    x = y = shelf_h = 0
    placed = []
    for rel, im in items:
        w = im.width + 2 * ATLAS_PAD
        h = im.height + 2 * ATLAS_PAD
        if x + w > page_w:
            x = 0
            y += shelf_h
            shelf_h = 0
        placed.append((rel, im, x, y))
        x += w
        shelf_h = max(shelf_h, h)
    return placed, y + shelf_h


def _pow2(v):
    p = 64
    while p < v:
        p *= 2
    return p


def gen_atlas():
    import json
    groups = {}
    for folder in sorted(os.listdir(OUT)):
        d = os.path.join(OUT, folder)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".png"):
                continue
            rel = folder + "/" + name
            g = _atlas_group(rel)
            if g is None:
                continue
            im = Image.open(os.path.join(d, name)).convert("RGBA")
            if max(im.size) > ATLAS_MAX_SIDE:
                continue
            groups.setdefault(g, []).append((rel, im))

    amap = {}
    pages = []
    for g, items in sorted(groups.items()):
        items.sort(key=lambda kv: (-kv[1].height, kv[0]))
        # 試多個頁闊,揀面積最細嗰個。高度唔湊夠 2 嘅次方 —— Godot 4 唔要求
        # POT,而湊夠嘅話最壞情況白白多一倍 VRAM。
        best = None
        widths = [256, 320, 384, 448, 512, 640, 768, 896, 1024, 1280, 1536, 2048]
        for pw in widths:
            placed, used_h = _shelf(items, pw)
            if placed and max(p[2] + p[1].width + 2 * ATLAS_PAD for p in placed) > pw:
                continue          # 有一格根本闊過成頁
            area = pw * used_h
            if best is None or area < best[0]:
                best = (area, pw, used_h, placed)
        area, pw, ph, placed = best
        page = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        for rel, im, x, y in placed:
            page.paste(_extrude(im, ATLAS_PAD), (x, y))
            amap[rel] = {"page": g, "x": x + ATLAS_PAD, "y": y + ATLAS_PAD,
                         "w": im.width, "h": im.height}
        save(page, "atlas", "atlas_%s.png" % g)
        fill = sum(im.width * im.height for _, im, _, _ in placed) / float(pw * ph)
        pages.append("%s %dx%d (%d 格, 填充率 %.0f%%)" % (g, pw, ph, len(placed), fill * 100))

    path = os.path.join(OUT, "atlas", "atlas_map.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(amap, f, separators=(",", ":"), sort_keys=True)
    for p in pages:
        print("  atlas: " + p)
    return len(pages)


def label(draw, x, y, text, col=(230, 230, 235, 255)):
    draw.text((x, y), text, fill=col)


def gen_contactsheet():
    pad = 6
    cell = 52          # 1x cell (fits 44 monster + margin)
    cols = 12
    tiles = []  # (image, caption)

    for name in FAMILY_IDS:
        for lvl in range(1, 6):
            p = os.path.join(OUT, "monsters", f"{name}_{lvl}.png")
            tiles.append((Image.open(p), f"{name[:4]}{lvl}"))
        tiles.append((Image.open(os.path.join(OUT, "monsters",
                                               f"{name}_boss.png")),
                      f"{name[:4]}B"))
    for i in range(1, 21):
        tiles.append((Image.open(os.path.join(OUT, "towers", f"tower_{i}.png")),
                      f"T{i}"))
    for i in range(1, 16):
        tiles.append((Image.open(os.path.join(OUT, "spells", f"spell_{i}.png")),
                      f"S{i}"))
    for nm in ("coin", "crystal", "base", "soldier", "militia"):
        tiles.append((Image.open(os.path.join(OUT, "ui", f"{nm}.png")), nm))
    # 2x nearest versions of coin/crystal/base
    for nm in ("coin", "crystal", "base"):
        im = Image.open(os.path.join(OUT, "ui", f"{nm}.png"))
        im2 = im.resize((im.width * 2, im.height * 2), Image.NEAREST)
        tiles.append((im2, nm + "2x"))

    rows = (len(tiles) + cols - 1) // cols
    cellw = cell + pad
    cellh = cell + pad + 10
    W = cols * cellw + pad
    H = rows * cellh + pad
    sheet = Image.new("RGBA", (W, H), (44, 46, 58, 255))
    d = ImageDraw.Draw(sheet)
    # checker so transparency + light sprites are visible
    for gy in range(0, H, 8):
        for gx in range(0, W, 8):
            if (gx // 8 + gy // 8) % 2 == 0:
                d.rectangle([gx, gy, gx + 7, gy + 7], fill=(52, 54, 68, 255))

    for idx, (im, cap) in enumerate(tiles):
        r = idx // cols
        cc = idx % cols
        cx = pad + cc * cellw
        cy = pad + r * cellh
        # cell bg
        d.rectangle([cx, cy, cx + cell, cy + cell], fill=(30, 32, 42, 255))
        im = im.convert("RGBA")
        ox = cx + (cell - im.width) // 2
        oy = cy + (cell - im.height) // 2
        if im.width > cell or im.height > cell:
            scale = min(cell / im.width, cell / im.height)
            im = im.resize((max(1, int(im.width * scale)),
                            max(1, int(im.height * scale))), Image.NEAREST)
            ox = cx + (cell - im.width) // 2
            oy = cy + (cell - im.height) // 2
        sheet.alpha_composite(im, (ox, oy))
        label(d, cx + 2, cy + cell + 1, cap)

    # QA artefact only — keep it OUT of assets/generated/ so it never gets
    # imported as a game resource and shipped inside the build.
    qa = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "qa", "screenshots", "contactsheets")
    os.makedirs(qa, exist_ok=True)
    path = os.path.join(qa, "_contactsheet.png")
    sheet.save(path)
    return path


# ============================================================================
def main():
    ap = argparse.ArgumentParser(description="塔防要塞 美術生成")
    ap.add_argument("--atlas-only", action="store_true",
                    help="只重出 atlas(換完怪物圖之後行呢個就夠,唔會掂其他資產)")
    args = ap.parse_args()
    if args.atlas_only:
        gen_atlas()
        print("atlas rebuilt")
        return

    counts = {}
    # NOTE: 冇 counts["monsters"] —— 怪物圖 2026-08-06 之後由
    # tools/monster_cutout.py 出,唔再喺呢度生成(見上面 MONSTER FAMILIES 段)。
    counts["towers"] = gen_towers()
    counts["spells"] = gen_spells()
    ui = 0
    ui += gen_coin()
    ui += gen_crystal()
    ui += gen_base()
    ui += gen_soldier()
    ui += gen_militia()
    ui += gen_ui_frames()
    ui += gen_bar_fills()
    ui += gen_ui_icons()
    ui += gen_ui_badges()
    ui += gen_upgrade_backdrops()
    ui += gen_platform()
    ui += gen_menu_bg()
    ui += gen_title_plate()
    counts["ui"] = ui
    counts["tiles"] = (gen_ground() + gen_road() + gen_decorations()
                       + gen_portal() + gen_scrim())
    counts["fx"] = gen_fx()
    counts["atlas"] = gen_atlas()
    sheet = gen_contactsheet()
    total = sum(counts.values())
    print("Generated:")
    for k, v in counts.items():
        print(f"  {k:10s}: {v}")
    print(f"  TOTAL     : {total}")
    print(f"Contact sheet: {sheet}")


if __name__ == "__main__":
    main()
