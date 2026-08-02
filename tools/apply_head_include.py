#!/usr/bin/env python3
"""將 web/head_include.js + web/head_include.css 寫入 export_presets.cfg。

點解要有呢個腳本:`html/head_include` 喺 .cfg 入面係**一行**引號字串,而我哋要
入面嗰段 JS 有註解、有換行、睇得明。兩個要求同時滿足唔到,所以原始碼擺喺
web/ 底下,呢度負責壓平同轉義,而 .cfg 嗰行係產物。

一定要跑咗先 export,唔係嘅話出街嗰個 shell 用緊舊嗰段。

用法:  python tools/apply_head_include.py [--check]
       --check 只係比較,唔寫檔(exit 1 = .cfg 落後咗)。
"""

import pathlib
import re
import sys

PROJECT = pathlib.Path(__file__).resolve().parent.parent
JS = PROJECT / "web" / "head_include.js"
CSS = PROJECT / "web" / "head_include.css"
CFG = PROJECT / "export_presets.cfg"

KEY = "html/head_include="


def strip_block_comments(src: str) -> str:
    return re.sub(r"/\*.*?\*/", "", src, flags=re.S)


def flatten_js(src: str) -> str:
    """剝走註解同縮排,再用單一空格接返一齊。

    唔用真正嘅 minifier:一個 100 行嘅 shim 唔值得多一個 build 依賴,而且保留
    得到嘅可讀性(語句之間有空格、字串原封不動)令產物仲有得肉眼核對。
    """
    src = strip_block_comments(src)
    out = []
    for line in src.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        out.append(line)
    return " ".join(out)


def flatten_css(src: str) -> str:
    """真係壓一壓,唔淨係接返一行。

    CSS 要壓到 `width:100%` 呢個形態(冒號後面冇空格):test/StretchTest.gd 就係
    咁樣核對 canvas 有冇填滿視窗,而一個「睇落一樣但多咗個空格」嘅字串會令
    嗰條 assertion 靜靜咁失效。
    """
    src = strip_block_comments(src)
    src = re.sub(r"\s+", " ", src)
    src = re.sub(r"\s*([{};:,])\s*", r"\1", src)
    return src.strip()


def build() -> str:
    parts = []
    if CSS.is_file():
        parts.append("<style>%s</style>" % flatten_css(CSS.read_text(encoding="utf-8")))
    parts.append("<script>%s</script>" % flatten_js(JS.read_text(encoding="utf-8")))
    return "".join(parts)


def main() -> int:
    value = build()
    if '"' in value:
        # .cfg 用雙引號包住,而 ConfigFile 唔食未轉義嘅雙引號。JS 一律用單引號
        # 就唔會撞到 —— 撞到就係寫錯咗,喺呢度停低好過出一個爛 shell。
        print("error: head_include 入面有雙引號,改用單引號")
        return 1
    line = '%s"%s"' % (KEY, value)
    text = CFG.read_text(encoding="utf-8")
    new, n = re.subn(r"^%s.*$" % re.escape(KEY), lambda _m: line, text,
                     count=1, flags=re.M)
    if n != 1:
        print("error: 喺 export_presets.cfg 搵唔到 %s" % KEY)
        return 1
    if "--check" in sys.argv:
        if new != text:
            print("export_presets.cfg 落後於 web/head_include.js")
            return 1
        print("head_include 係最新嘅")
        return 0
    if new == text:
        print("head_include 已經係最新 (%d bytes)" % len(value))
        return 0
    CFG.write_text(new, encoding="utf-8", newline="\n")
    print("寫入 export_presets.cfg:head_include %d bytes" % len(value))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
