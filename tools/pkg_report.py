#!/usr/bin/env python3
"""列出一個 Android .apk / .aab 入面有乜,同埋逐項對返 web 嘅 .pck。

點解要有(同 `pck_report.py` 一模一樣嘅理由,唔同平台):`exclude_filter` 係
一條「寫咗就當佢生效」嘅設定。Web 嗰邊 round 9 出過事(50 MB QA 截圖跟住
出街),而 Android 呢邊個風險更加高 —— gradle build 唔係出一個 pck,係將
**每一個檔散裝擺入 apk 嘅 assets/**,所以任何一條漏咗嘅排除規則都會直接
變成一個上咗 Play 嘅檔案。

呢個腳本答三條問題:
  1. 個 package 入面每一類嘢佔幾多(壓縮前 / 壓縮後)
  2. `assets/` 入面有冇任何開發檔案或者產物殘留(應該係零)
  3. 同 web 嘅 pck 逐個檔對,兩邊嘅差異列出嚟 —— 差異應該淨係得
     平台自己嗰幾個(sparsepck / baseline profile / _cl_)

用法:
    python tools/pkg_report.py dist/Towerbound-1.0.0.apk
    python tools/pkg_report.py dist/Towerbound-1.0.0.aab --pck docs/index.pck
"""
import argparse
import collections
import os
import re
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pck_report import read_pck  # noqa: E402

## 一個都唔准出現喺 assets/ 入面。同 export_presets.cfg 嘅 exclude_filter 對應,
## 但**唔係**由嗰度讀 —— 呢度要獨立咁問「結果啱唔啱」,唔係「設定寫咗乜」。
FORBIDDEN = re.compile(
    r"^(qa|test|tools|web|docs|build|dist|android|art_reference)/"
    r"|\.(md|py|pyc|ps1|sh|bat|npy|jfif|csv|log|err)$"
    r"|Gallery"
    r"|^assets/generated/(monsters|towers|spells)/"
    r"|^assets/android/",
    re.I,
)

## Android 打包自己加嘅嘢,唔係遊戲內容 —— 同 pck 對數嗰陣要扣返出嚟。
PLATFORM_EXTRA = {
    "assets.sparsepck",          # Godot 散裝檔案嘅索引
    "_cl_",                      # Godot 嘅 command-line 覆寫檔
    "dexopt/baseline.prof",      # AndroidX baseline profile(冷啟動加速)
    "dexopt/baseline.profm",
}


def assets_of(path):
    """apk 同 aab 擺遊戲檔案嘅位唔同,兩個都收。"""
    z = zipfile.ZipFile(path)
    for prefix in ("assets/", "assetPackInstallTime/assets/"):
        got = {i.filename[len(prefix):]: (i.file_size, i.compress_size)
               for i in z.infolist() if i.filename.startswith(prefix)}
        if got:
            return z, got
    raise SystemExit("%s 入面搵唔到 assets/" % path)


def group_of(name):
    parts = name.split("/")
    if parts[0] == ".godot":
        if len(parts) > 1 and parts[1] == "imported":
            return ".godot/imported (%s)" % name.rsplit(".", 1)[-1]
        if len(parts) > 1 and parts[1] == "exported":
            return ".godot/exported (場景)"
        return ".godot/" + (parts[1] if len(parts) > 1 else "")
    return parts[0] if len(parts) > 1 else "(根) " + name


WHY = {
    "(根) icudt_godot.dat":
        "ICU 斷行資料。export template 冇 static ICU,冇咗佢 ubrk 開唔到,"
        "中文 AUTOWRAP_WORD_SMART 會唔斷行爆版。硬依賴,剷唔得。",
    ".godot/imported (ctex)":
        "全部貼圖。兩張 atlas 佔 96%,其餘 77 個係九宮格同 atlas 落唔到嗰啲。",
    ".godot/imported (sample)":
        "65 個音效 / BGM,已經係 QOA 壓縮(compress/mode=2)。",
    ".godot/imported (fontdata)":
        "NotoSansTC subset。Android 同 web 都靠佢出中文,冇咗就成版豆腐格。",
    "scripts": "遊戲全部 GDScript,已編譯做 .gdc。",
    "i18n": "zh_TW / en 兩個 .translation。原始 game.csv 已經隔走。",
    "assets": "144 個 .import remap stub —— `load(\"res://assets/…\")` 靠佢揾到 .ctex。",
    ".godot/exported (場景)": "10 個畫面場景 + audio bus,已編譯做 .scn/.res。",
    ".godot/uid_cache.bin": "UID → 路徑對照,引擎開場要。",
    ".godot/global_script_class_cache.cfg": "class_name 註冊表(UI 呢類)。",
    "(根) project.binary": "project.godot 編譯版。",
    "(根) icon.svg": "Godot 範本 icon。exporter 由 config/icon 強制加,"
                     "exclude_filter 攔唔到;995 bytes。",
    "(根) assets.sparsepck": "【平台】Godot 散裝檔索引,唔係遊戲內容。",
    "dexopt": "【平台】AndroidX baseline profile,加快冷啟動。",
    "(根) _cl_": "【平台】Godot 嘅 command-line 覆寫檔(--fullscreen 等)。",
    "scenes": "10 個場景嘅 remap stub。",
    "(根) default_bus_layout.tres.remap": "audio bus 嘅 remap stub。",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package")
    ap.add_argument("--pck", default="docs/index.pck",
                    help="攞嚟對數嘅 web pck(預設 docs/index.pck)")
    a = ap.parse_args()

    z, assets = assets_of(a.package)
    total_raw = sum(v[0] for v in assets.values())
    print("PACKAGE %s" % a.package)
    print("  檔案本身      %.2f MB" % (os.path.getsize(a.package) / 1048576))
    print("  assets/ 檔數  %d" % len(assets))
    print("  assets/ 大細  %.1f KB(未壓縮) / %.1f KB(zip 之後)"
          % (total_raw / 1024, sum(v[1] for v in assets.values()) / 1024))

    print("\n=== 內容盤點 ===")
    g = collections.defaultdict(lambda: [0, 0])
    for k, (raw, _c) in assets.items():
        key = group_of(k)
        g[key][0] += 1
        g[key][1] += raw
    print("%-38s %5s %10s  %s" % ("組別", "檔數", "KB", "點解要入包"))
    for k in sorted(g, key=lambda k: -g[k][1]):
        print("%-38s %5d %10.1f  %s" % (k, g[k][0], g[k][1] / 1024,
                                        WHY.get(k, "(未有說明 — 補返落 pkg_report.py)")))
    print("%-38s %5d %10.1f" % ("合計", len(assets), total_raw / 1024))

    print("\n=== 開發檔案 / 產物殘留掃描 ===")
    bad = sorted(k for k in assets if FORBIDDEN.search(k))
    if bad:
        for k in bad:
            print("  !! %9.1f KB  %s" % (assets[k][0] / 1024, k))
    print("  命中 %d 個" % len(bad))

    if os.path.exists(a.pck):
        print("\n=== 同 %s 對數 ===" % a.pck)
        pck = dict(read_pck(a.pck)[2])
        only_pkg = sorted(set(assets) - set(pck) - PLATFORM_EXTRA)
        only_pck = sorted(set(pck) - set(assets))
        plat = sorted(set(assets) & PLATFORM_EXTRA)
        print("  平台自己加(預期):%s" % (", ".join(plat) or "(冇)"))
        print("  只喺 package(唔預期):%s" % (", ".join(only_pkg) or "(冇)"))
        print("  只喺 pck(唔預期):%s" % (", ".join(only_pck) or "(冇)"))
        game_only = total_raw - sum(assets[k][0] for k in plat)
        print("  遊戲內容大細:package %.1f KB vs pck %.1f KB(差 %+d bytes)"
              % (game_only / 1024, sum(pck.values()) / 1024,
                 game_only - sum(pck.values())))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
