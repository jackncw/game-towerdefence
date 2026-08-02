#!/usr/bin/env python3
"""
Procedural pixel-art generator for a mobile tower-defense game (Godot).
Pure standard-lib + Pillow. Run:  python tools/gen_art.py

Writes every PNG described in CONTRACT.md to assets/generated/ .
Style: draw on a small logical grid, hard-edged pixels (no AA), a uniform dark
outline around each silhouette (via alpha dilation) and 2-3 flat cel-shading
tones (base / shadow / highlight). Transparent background.

Organisation:
  * palette-ramp + colour helpers
  * a small Canvas wrapper with normalised-coordinate primitive drawers
    (ellipse / rounded-rect / polygon / line / eyes / horns / wings ...)
  * a FAMILIES table + one draw function per monster family
  * one function per tower and per spell
All output is original; reference art was used only for palette / silhouette
direction.
"""

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

def label(draw, x, y, text, col=(230, 230, 235, 255)):
    draw.text((x, y), text, fill=col)


def gen_contactsheet():
    pad = 6
    cell = 52          # 1x cell (fits 44 monster + margin)
    cols = 12
    tiles = []  # (image, caption)

    for name, fn, bossfn, basecol, accent in FAMILIES:
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
    qa = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "art_export")
    os.makedirs(qa, exist_ok=True)
    path = os.path.join(qa, "_contactsheet.png")
    sheet.save(path)
    return path


# ============================================================================
def main():
    counts = {}
    counts["monsters"] = gen_monsters()
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
    sheet = gen_contactsheet()
    total = sum(counts.values())
    print("Generated:")
    for k, v in counts.items():
        print(f"  {k:10s}: {v}")
    print(f"  TOTAL     : {total}")
    print(f"Contact sheet: {sheet}")


if __name__ == "__main__":
    main()
