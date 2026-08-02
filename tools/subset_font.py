#!/usr/bin/env python3
"""Build the bundled CJK UI font from the upstream Noto Sans TC variable font.

The web export has no system fonts to fall back on, so Flow.gd loads a bundled
FontFile there instead of a SystemFont. A full Noto Sans TC is ~11 MB, which is
far too heavy to ship, so this subsets it down to the characters the game
actually renders.

Re-run this whenever new on-screen text introduces characters that aren't in the
subset yet -- an uncovered character renders as a tofu box (missing glyph) on the
web build only, because desktop still has the system font to fall back on. That
asymmetry is what let round 11 ship 149 uncovered on-screen characters: the
desktop screenshots were clean and the web build was full of boxes.

test/I18nTest.gd now fails on an uncovered character, so this is no longer
something anyone has to remember.

The character set comes from tools/font_chars.py, shared with that test so the
two definitions cannot drift apart.

Usage:
    python tools/subset_font.py path/to/NotoSansTC[wght].ttf

Upstream font (SIL OFL 1.1), deliberately NOT committed (11 MB):
    https://github.com/google/fonts/tree/main/ofl/notosanstc
"""

import pathlib
import sys

from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from font_chars import PROJECT, collect_chars  # noqa: E402

OUT = PROJECT / "assets" / "fonts" / "NotoSansTC-Subset.ttf"


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

    # 唔可以「跑完就當成功」:subsetter 對一個字型冇 glyph 嘅 codepoint 係靜靜
    # 略過嘅,而嗰個正正就係豆腐方格嘅來源。所以出完之後即刻返轉頭對一次。
    from font_chars import missing

    miss = missing(OUT)
    if miss:
        print("WARNING: 上游字型都冇呢 %d 個字:%s" % (len(miss), "".join(miss)))
        return 1
    print("coverage: 全部 on-screen 字元都有 glyph")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
