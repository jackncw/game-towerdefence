"""Fast Pillow-only contact sheets for towers / env / decos.

No Godot, no GPU: reads the PNGs gen_art.py just wrote and tiles them so a
review pass is one Read instead of a 4-minute art_export run.

    python tools/asset_sheet.py towers            -> scratch_towers.png
    python tools/asset_sheet.py towers --silhouette
    python tools/asset_sheet.py env
    python tools/asset_sheet.py compare           -> towers next to monsters
"""
import os
import sys
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "assets", "generated")
BG = (28, 26, 32, 255)
CELL_BG = (20, 19, 24, 255)


def load(*parts):
    p = os.path.join(GEN, *parts)
    return Image.open(p).convert("RGBA") if os.path.exists(p) else None


def silhouette(im):
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    px, op = im.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            if px[x, y][3] > 120:
                op[x, y] = (235, 235, 240, 255)
    return out


def sheet(items, cols, scale, cell, name, silh=False, label=True):
    rows = (len(items) + cols - 1) // cols
    lh = 16 if label else 0
    W, H = cols * (cell + 8) + 8, rows * (cell + 8 + lh) + 8
    img = Image.new("RGBA", (W, H), BG)
    d = ImageDraw.Draw(img)
    for i, (cap, im) in enumerate(items):
        cx = 8 + (i % cols) * (cell + 8)
        cy = 8 + (i // cols) * (cell + 8 + lh)
        d.rectangle([cx, cy, cx + cell - 1, cy + cell - 1], fill=CELL_BG)
        if im is None:
            continue
        s = im if not silh else silhouette(im)
        s = s.resize((s.width * scale, s.height * scale), Image.NEAREST)
        if s.width > cell or s.height > cell:
            f = min(cell / s.width, cell / s.height)
            s = s.resize((int(s.width * f), int(s.height * f)), Image.NEAREST)
        img.alpha_composite(s, (cx + (cell - s.width) // 2,
                                cy + (cell - s.height) // 2))
        if label:
            d.text((cx + 3, cy + cell + 1), cap, fill=(190, 186, 200, 255))
    out = os.path.join(ROOT, name)
    img.save(out)
    print("wrote", out, img.size)


TOWER_NAMES = ["arrow", "cannon", "lightning", "fireball", "frost", "poison",
               "sniper", "gatling", "mortar", "beam", "slowfield", "alchemy",
               "barracks", "boomerang", "thorn", "missile", "curse", "holy",
               "magnet", "teleport"]


def main():
    what = sys.argv[1] if len(sys.argv) > 1 else "towers"
    silh = "--silhouette" in sys.argv
    if what == "towers":
        items = [("%d %s" % (i + 1, n), load("towers", "tower_%d.png" % (i + 1)))
                 for i, n in enumerate(TOWER_NAMES)]
        sheet(items, 5, 4, 190, "scratch_towers.png", silh)
    elif what == "env":
        items = [("base", load("ui", "base.png")),
                 ("portal", load("tiles", "portal.png")),
                 ("soldier", load("ui", "soldier.png")),
                 ("ground", load("tiles", "ground.png")),
                 ("road", load("tiles", "road.png"))]
        items += [(n, load("tiles", "deco_%s.png" % n)) for n in
                  ("rock1", "rock2", "bones", "skull", "grass", "crack",
                   "bush", "pebbles", "stump", "banner")]
        sheet(items, 5, 3, 230, "scratch_env.png", silh)
    elif what == "compare":
        # towers beside monsters at the SAME on-screen scale (both render 2x)
        items = []
        for i, n in enumerate(TOWER_NAMES[:10]):
            items.append(("T%d" % (i + 1), load("towers", "tower_%d.png" % (i + 1))))
        for fam in ("goblin", "skeleton", "golem", "treant", "cultist"):
            for lv in (3, 5):
                items.append((fam[:4] + str(lv),
                              load("monsters", "%s_%d.png" % (fam, lv))))
        sheet(items, 5, 4, 190, "scratch_compare.png", silh)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
