"""收集「真係會畫上螢幕」嘅字元集合。

subset_font.py 同 test/I18nTest.gd 共用同一個定義,所以「字型入面有嘅字」同
「畫得出嚟嘅字」唔會各自漂移。

點解要獨立一個檔:舊版 collect_chars() 由 .gd 原始碼**整份**收字,連註解都收。
呢個 codebase 嘅註解全部係粵語,所以個集合入面有幾百個永遠唔會出現喺畫面上
嘅字。表面上「收多咗好過收少咗」,但實情係反過嚟 —— 註解字混咗入去之後,
「呢個字係咪應該喺字型入面」就再冇一個答得到嘅定義,而第十一輪就係喺呢度
量到 345 個「缺字」入面大部分係註解。而真正缺嗰批(i18n CSV 入面嘅)就被
埋喺噪音入面冇人執。

而家嘅定義:
  * i18n/*.csv          —— 整份。呢個就係全部 UI 文字。
  * *.gd / *.tscn       —— 只取**字串字面值**,而且剝走註解。
  * project.godot       —— config/name(視窗標題 / PWA 名)。
  * ALWAYS              —— 執行時砌出嚟嘅嘢(數字、百分號、箭嘴…)。
"""

import pathlib
import re

PROJECT = pathlib.Path(__file__).resolve().parent.parent

# 一定要有:執行時 format() 砌出嚟嘅字元,唔會喺任何一句字面值入面出現。
ALWAYS = set(
    "0123456789"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    " !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~"
    "×÷…—–→←↑↓▲▼★☆·"
    "　、。（）「」：；，！？～％"
)

SKIP_DIRS = {".godot", "docs", "build", "art reference", "Claude art self improve"}

_STR = re.compile(r'"([^"\\\n]*(?:\\.[^"\\\n]*)*)"' r"|'([^'\\\n]*(?:\\.[^'\\\n]*)*)'")


def _strip_comments(line: str) -> str:
    """剝走 GDScript 嘅 `#` 註解,但唔可以斬斷字串入面嘅 `#`。"""
    out = []
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if c == quote:
                quote = ""
            out.append(c)
        elif c in "\"'":
            quote = c
            out.append(c)
        elif c == "#":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def _literals(text: str) -> str:
    chunks = []
    for line in text.splitlines():
        for m in _STR.finditer(_strip_comments(line)):
            chunks.append(m.group(1) if m.group(1) is not None else m.group(2))
    return "".join(chunks)


def _iter_files():
    for path in PROJECT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(PROJECT)
        if SKIP_DIRS & set(rel.parts):
            continue
        yield path, rel


def collect_chars() -> set:
    chars = set(ALWAYS)
    for path, rel in _iter_files():
        suffix = path.suffix.lower()
        if suffix not in {".csv", ".gd", ".tscn", ".tres", ".godot"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        if suffix == ".csv":
            chars |= set(text)
        elif suffix == ".godot":
            for line in text.splitlines():
                if line.startswith("config/name="):
                    chars |= set(line)
        else:
            chars |= set(_literals(text))
    # 控制字元同 Latin-1 以下嘅嘢唔使問字型攞 glyph
    return {c for c in chars if c.isprintable() and c not in "\t\n\r"}


def font_codepoints(font_path) -> set:
    from fontTools.ttLib import TTFont

    font = TTFont(str(font_path))
    cps = set()
    for table in font["cmap"].tables:
        cps |= set(table.cmap.keys())
    return cps


def missing(font_path) -> list:
    cps = font_codepoints(font_path)
    return sorted(c for c in collect_chars() if ord(c) > 0x7F and ord(c) not in cps)


if __name__ == "__main__":
    chars = collect_chars()
    print("on-screen characters: %d" % len(chars))
    f = PROJECT / "assets" / "fonts" / "NotoSansTC-Subset.ttf"
    miss = missing(f)
    print("missing from %s: %d" % (f.name, len(miss)))
    if miss:
        print("".join(miss))
