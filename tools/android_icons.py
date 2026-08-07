#!/usr/bin/env python3
"""砌 Android 嘅 launcher icon / adaptive icon / boot splash。

**冇新美術。** 每一 pixel 都由 project 入面已經有嘅兩張圖嚟:

    assets/generated/ui/menu_bg.png        主選單背景(1080x1920,平面幾何,
                                           放大唔會散)—— 出天空 + 月 + 星
    assets/generated/towers/tower_1_t3.png 箭塔 T3(76x128,已經摳好圖有 alpha)
                                           —— 出前景個主體

點解揀呢兩張:
  * menu_bg 係玩家開 app 第一眼見到嘅嘢,個 icon 同佢一致
  * 箭塔係第一座塔、全部人都有嘅嗰座,亦都係 store icon 上面認得出「呢隻係
    塔防」嘅最短路徑

Adaptive icon 嘅安全區:432x432 入面淨係中間約 66%(~285px)保證唔會被
launcher 個 mask 剪走。前景個塔按 2 倍(128 -> 256)整數放大 —— 唔用
2.1 倍咁嘅小數,因為遊戲本身用 NEAREST 濾鏡,整數倍放大先至同遊戲入面
睇落一樣,唔會有半個 pixel 嘅鋸齒。

輸出(全部落 assets/android/,嗰個資料夾有 .gdignore,所以 Godot 由頭到尾
唔會 import 佢哋,亦即係話佢哋唔會入 pck —— 但 export 嗰陣個 exporter 係
直接由檔案系統讀,所以照用得):

    assets/android/icon_192.png            launcher_icons/main_192x192
    assets/android/icon_fg_432.png         adaptive_foreground_432x432
    assets/android/icon_bg_432.png         adaptive_background_432x432
    assets/android/icon_mono_432.png       adaptive_monochrome_432x432(themed icon)
    assets/android/splash.png              splash_screen/icon
    dist/play-store-icon-512.png           Play Console 上載嗰張(唔入 apk)

用法:  python tools/android_icons.py
"""
import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "android"
DIST = ROOT / "dist"

MENU_BG = ROOT / "assets" / "generated" / "ui" / "menu_bg.png"
TOWER = ROOT / "assets" / "generated" / "towers" / "tower_1_t3.png"

## UI.BG。天空頂部、splash 背景、letterbox 全部係佢。
BG = (28, 22, 17, 255)


def sky_square(size: int) -> Image.Image:
    """menu_bg 最上面嗰個正方形:星、月、山頂,冇城堡。

    城堡刻意唔要 —— adaptive icon 個背景層會俾 launcher 平移同縮放(視差),
    所以背景唔可以有「擺歪咗會睇得出」嘅主體。星同漸層點移都仲係啱。
    """
    # (280,0)-(1080,800):月光整個入曬鏡,城堡同魔晶球(y>800)一個都唔入。
    # 兩者都喺畫面正中,而前景個塔都係喺正中 —— 兩舊嘢疊埋一齊會變一嚿。
    src = Image.open(MENU_BG).convert("RGBA")
    crop = src.crop((280, 0, 1080, 800))
    return crop.resize((size, size), Image.LANCZOS).convert("RGBA")


def tower_layer(canvas: int, height: int) -> Image.Image:
    """塔擺喺一塊透明布中間,底邊對齊安全區下沿。

    唔置中垂直置中:一座塔嘅視覺重心喺下半部(地台),幾何置中會睇落「浮起」。
    """
    src = Image.open(TOWER).convert("RGBA")
    scale = max(1, round(height / src.height))
    tw, th = src.width * scale, src.height * scale
    tower = src.resize((tw, th), Image.NEAREST)
    layer = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    x = (canvas - tw) // 2
    y = (canvas - th) // 2 + int(canvas * 0.02)
    layer.alpha_composite(tower, (x, y))
    return layer


def flatten(im: Image.Image) -> Image.Image:
    base = Image.new("RGBA", im.size, BG)
    base.alpha_composite(im)
    return base


def monochrome(fg: Image.Image) -> Image.Image:
    """Themed icon(Android 13+)。淨係要形,唔要色 —— 系統自己上色。"""
    out = Image.new("RGBA", fg.size, (0, 0, 0, 0))
    px = fg.load()
    op = out.load()
    for y in range(fg.height):
        for x in range(fg.width):
            a = px[x, y][3]
            if a > 24:
                op[x, y] = (255, 255, 255, a)
    return out


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    DIST.mkdir(parents=True, exist_ok=True)
    (OUT / ".gdignore").write_text("", encoding="utf-8")
    # dist/ 一有 .png 就會俾 editor import 咗做 .ctex,而嗰個 .import 檔會
    # 走返入 project 樹入面。dist/ 係出貨資料夾,唔係素材資料夾。
    (DIST / ".gdignore").write_text("", encoding="utf-8")

    # --- adaptive:背景 + 前景兩層,432x432 -------------------------------
    bg432 = sky_square(432)
    bg432.save(OUT / "icon_bg_432.png")

    fg432 = tower_layer(432, 256)          # 128 * 2,啱啱好落安全區
    fg432.save(OUT / "icon_fg_432.png")
    monochrome(fg432).save(OUT / "icon_mono_432.png")

    # --- 舊式方形 icon:兩層壓埋,192x192 --------------------------------
    flat = bg432.copy()
    flat.alpha_composite(fg432)
    flat.convert("RGB").resize((192, 192), Image.LANCZOS).save(OUT / "icon_192.png")

    # --- Play Console 個 512(唔入 apk,係上架表格用) ---------------------
    big_bg = sky_square(512)
    # 512 冇 launcher mask(Play Console 自己剪圓角),所以個塔食得盡啲:
    # 128 * 3 = 384,即係佔成張圖 75%。
    big_fg = tower_layer(512, 384)
    big = big_bg.copy()
    big.alpha_composite(big_fg)
    big.convert("RGB").save(DIST / "play-store-icon-512.png")

    # --- boot splash:塔擺中間,背景係 UI.BG(同 default_clear_color 一樣) ---
    # Godot 個 splash 自己會用 splash_screen/background_color 填底,所以呢張
    # 淨係要主體 + 透明。512 係俾佢喺高 DPI 機上面唔使放大。
    splash = tower_layer(512, 384)
    splash.save(OUT / "splash.png")

    for p in sorted(OUT.glob("*.png")) + [DIST / "play-store-icon-512.png"]:
        im = Image.open(p)
        print(f"{p.relative_to(ROOT)}  {im.size[0]}x{im.size[1]}  {p.stat().st_size / 1024:.1f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
