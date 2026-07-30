#!/usr/bin/env python3
"""Build the bundled CJK UI font from the upstream Noto Sans TC variable font.

The web export has no system fonts to fall back on, so Flow.gd loads a bundled
FontFile there instead of a SystemFont. A full Noto Sans TC is ~11 MB, which is
far too heavy to ship, so this subsets it down to the characters the game
actually renders.

Re-run this whenever new on-screen text introduces characters that aren't in the
subset yet -- an uncovered character renders as a tofu box (missing glyph).

Usage:
    python tools/subset_font.py path/to/NotoSansTC[wght].ttf

Upstream font (SIL OFL 1.1):
    https://github.com/google/fonts/tree/main/ofl/notosanstc
"""

import sys
import pathlib

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

PROJECT = pathlib.Path(__file__).resolve().parent.parent
OUT = PROJECT / "assets" / "fonts" / "NotoSansTC-Subset.ttf"

# Files whose string literals can reach the screen.
SCAN_SUFFIXES = {".gd", ".tscn", ".tres", ".godot", ".cfg"}
SKIP_DIRS = {".godot", "docs", "build", "art_export", "art_export_round6"}

# Always include these regardless of what the sources happen to use today, so
# runtime-formatted output (numbers, percentages, separators) never tofus.
ALWAYS = set(
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "×÷…→←↑↓▲▼★☆"  # ×÷…→←↑↓▲▼★☆
    "　、。（）：；，！？～"  # 、。（）：；，！？～
)


def collect_chars() -> set:
    chars = set(ALWAYS)
    for path in PROJECT.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in SCAN_SUFFIXES:
            continue
        if SKIP_DIRS & set(path.relative_to(PROJECT).parts):
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        # Anything above Latin-1 is a glyph the default font can't be trusted for.
        chars |= {c for c in text if ord(c) > 0x00A0}
    return chars


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    src = pathlib.Path(sys.argv[1])
    if not src.is_file():
        print(f"error: source font not found: {src}")
        return 1

    chars = collect_chars()
    print(f"characters to keep: {len(chars)}")

    font = TTFont(src)
    if "fvar" in font:
        # Pin to Regular; the game never varies weight at runtime.
        font = instancer.instantiateVariableFont(
            font, {"wght": 400}, inplace=True, updateFontNames=True
        )

    subsetter = subset.Subsetter(
        options=subset.Options(
            layout_features=["kern", "liga", "locl", "ccmp", "vert", "vrt2"],
            drop_tables=["DSIG"],
            notdef_outline=True,
            recalc_bounds=True,
        )
    )
    subsetter.populate(text="".join(sorted(chars)))
    subsetter.subset(font)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    kb = OUT.stat().st_size / 1024
    print(f"wrote {OUT.relative_to(PROJECT)} ({kb:.0f} KB, {len(font.getGlyphOrder())} glyphs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
