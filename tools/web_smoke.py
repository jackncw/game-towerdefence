#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""web_smoke.py — 用真瀏覽器行一次 web build,做四個實操再收 console。

點解要有:web 出街嘅 bug 有一整類喺 desktop 度**冇可能**出現(CJK 字型
fallback、thread_support、IndexedDB 存檔、WebGL 貼圖上限),而呢一輪換咗
105 張圖同一個 texture filter,啱啱好就係嗰類嘢會炒嘅地方。

四個實操 = 簡報要求嘅「起塔 / 升級 / 進化 / 放魔法各一次」。
升級同進化要魔晶,而一個乾淨嘅瀏覽器 profile 係零魔晶,所以第一步係
**種存檔**:Godot 4 嘅 web build 將 user:// 放喺 IndexedDB(Emscripten
IDBFS,DB 名 "/userfs",store "FILE_DATA",key "/userfs/save.json"),
所以開一次頁等佢建好個 DB,再由外面覆寫 save.json,reload 就當係一個
已經玩到有錢嘅玩家。

用法:
  python -m http.server 8765 --directory docs
  python tools/web_smoke.py [--url http://localhost:8765/index.html]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "qa", "screenshots",
                     os.environ.get("WEB_SMOKE_OUT", "round-20-tower-magic-art"), "web")
sys.stdout.reconfigure(encoding="utf-8")

# 種落去嘅存檔。**由真存檔導出**(tools/web_smoke_seed.json)而唔係手寫 —— 個
# schema 有 `tower_up` / `spell_up` / `cleared` / `version` 呢啲欄位,手寫漏一個
# Meta 就會靜靜咁當佢係舊存檔行遷移,而個 bug 會扮成「web 版壞咗」。
SEED_PATH = os.path.join(ROOT, "tools", "web_smoke_seed.json")

WRITE_SAVE = """
async (payload) => {
  const enc = new TextEncoder().encode(payload);
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('/userfs');
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const names = Array.from(db.objectStoreNames);
  if (!names.includes('FILE_DATA')) return 'no FILE_DATA store: ' + names.join(',');
  const tx = db.transaction('FILE_DATA', 'readwrite');
  const st = tx.objectStore('FILE_DATA');
  const keys = await new Promise((res) => { const q = st.getAllKeys(); q.onsuccess = () => res(q.result); });
  const key = keys.find(k => String(k).endsWith('save.json'));
  if (!key) return 'no save.json among: ' + keys.join(',');
  const cur = await new Promise((res) => { const q = st.get(key); q.onsuccess = () => res(q.result); });
  cur.contents = enc;
  cur.timestamp = new Date();
  await new Promise((res, rej) => { const q = st.put(cur, key); q.onsuccess = res; q.onerror = () => rej(q.error); });
  return 'ok ' + key;
}
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8765/index.html")
    ap.add_argument("--headed", action="store_true")
    args = ap.parse_args()
    os.makedirs(SHOTS, exist_ok=True)

    logs: list[str] = []
    errors: list[str] = []
    steps: list[str] = []

    with sync_playwright() as p:
        br = p.chromium.launch(headless=not args.headed,
                               args=["--use-gl=angle", "--enable-unsafe-swiftshader"])
        ctx = br.new_context(viewport={"width": 520, "height": 924})
        pg = ctx.new_page()
        pg.on("console", lambda m: (logs.append("%s: %s" % (m.type, m.text)),
                                    errors.append(m.text) if m.type == "error" else None))
        pg.on("pageerror", lambda e: errors.append("pageerror: %s" % e))

        def shot(name: str) -> None:
            pg.screenshot(path=os.path.join(SHOTS, name + ".png"))
            print("shot ->", name)

        def tap(x: float, y: float, hold: float = 0.12) -> None:
            """Godot 收嘅係 touch(emulate_touch_from_mouse),而卡片係 drag-
            from-card,所以按落去要停一陣先放,唔可以 click 一嘢。"""
            pg.mouse.move(x, y)
            pg.mouse.down()
            time.sleep(hold)
            pg.mouse.up()
            time.sleep(0.35)

        def drag(x0: float, y0: float, x1: float, y1: float) -> None:
            pg.mouse.move(x0, y0)
            pg.mouse.down()
            time.sleep(0.12)
            pg.mouse.move((x0 + x1) / 2, (y0 + y1) / 2, steps=8)
            pg.mouse.move(x1, y1, steps=8)
            time.sleep(0.20)
            pg.mouse.up()
            time.sleep(0.5)

        # --- 開一次等 IDBFS 建好 -------------------------------------------
        pg.goto(args.url)
        pg.wait_for_timeout(18000)
        shot("00_boot")
        with open(SEED_PATH, encoding="utf-8") as fh:
            seed = fh.read()
        r = pg.evaluate(WRITE_SAVE, seed)
        steps.append("種存檔:%s" % r)
        print("seed:", r)

        # --- reload,由主選單行落去 ---------------------------------------
        pg.goto(args.url)
        pg.wait_for_timeout(18000)
        shot("01_menu")

        w, h = 520, 924
        # 主選單「開始遊戲」大約喺畫面 42% 高度中間
        tap(w * 0.5, h * 0.42)
        pg.wait_for_timeout(2500)
        shot("02_levelselect")
        # 關卡格:左上第一格
        tap(w * 0.17, h * 0.30)
        pg.wait_for_timeout(3500)
        shot("03_battle")
        return_code = 0
        return_code |= _battle_steps(pg, w, h, tap, drag, shot, steps)

        # --- 升級 + 進化 ---------------------------------------------------
        # 由主選單重入升級介面,唔行戰鬥嘅暫停選單 —— reload 之後主選單嘅
        # 掣位固定,而暫停選單要先撳暫停再撳返回,多兩個會飄嘅坐標。
        pg.goto(args.url)
        pg.wait_for_timeout(18000)
        tap(w * 0.50, h * 0.569)          # 主選單「升級介面」
        pg.wait_for_timeout(2500)
        shot("06_upgrade_open")
        return_code |= _upgrade_steps(pg, w, h, tap, shot, steps)
        br.close()

    print("\n=== console errors: %d ===" % len(errors))
    for e in errors[:20]:
        print("  ERR " + e)
    print("=== steps ===")
    for s in steps:
        print("  " + s)
    with open(os.path.join(SHOTS, "console.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(logs))
    return 1 if errors else 0


def _upgrade_steps(pg, w, h, tap, shot, steps) -> int:
    """升級介面:魔法課一級(升級),再返塔頁撳進化。

    種存檔嗰陣特登整咗一個「箭塔六條軸全滿、魔法全部零級」嘅狀態,所以
    兩個掣都一定係可撳嘅 —— 唔使靠運氣撞啱一個啱嘅存檔。
    """
    # 魔法頁 -> 捲到升級列 -> 撳第一條軸嘅升級掣
    tap(w * 0.50, h * 0.036)              # 上面「魔法」分頁
    pg.wait_for_timeout(1200)
    pg.mouse.move(w * 0.5, h * 0.6)
    for _ in range(8):
        pg.mouse.wheel(0, 500)
        time.sleep(0.12)
    pg.wait_for_timeout(600)
    shot("07_upgrade_spell_rows")
    # 升級:隕石術「傷害」嗰行嘅升級掣
    tap(w * 0.803, h * 0.433)
    pg.wait_for_timeout(1200)
    shot("08_spell_upgraded")
    steps.append("升級:隕石術傷害 0 -> 1 級(-55 魔晶)")

    # 進化:轉塔頁,箭塔六條軸已經滿,捲到最底撳進化
    tap(w * 0.31, h * 0.036)
    pg.wait_for_timeout(1500)
    pg.mouse.move(w * 0.5, h * 0.6)
    for _ in range(18):
        pg.mouse.wheel(0, 500)
        time.sleep(0.10)
    pg.wait_for_timeout(800)
    shot("09_tower_evolve_ready")
    tap(w * 0.73, h * 0.887)
    pg.wait_for_timeout(1800)
    shot("10_tower_evolved")
    steps.append("進化:箭塔第 1 階 -> 第 2 階")
    return 0


def _battle_steps(pg, w, h, tap, drag, shot, steps) -> int:
    # 起塔:由第一張塔卡拖去場中一個空位
    drag(w * 0.09, h * 0.855, w * 0.30, h * 0.55)
    pg.wait_for_timeout(800)
    shot("04_built_tower")
    steps.append("起塔:由塔卡拖落場")
    # 放魔法:第一張魔法卡(隕石)拖去路上。
    # 魔法列有兩行,第一行嘅圓心量出嚟係 y≈834 / 924、x≈71 / 520 —— 用
    # 「卡片列頂 + 一個估數」會落喺兩行之間嘅坑度,撳極都冇反應(踩過)。
    drag(w * 0.1365, h * 0.9026, w * 0.54, h * 0.40)
    pg.wait_for_timeout(900)
    shot("05_cast_spell")
    steps.append("放魔法:隕石術由魔法卡拖落場")
    return 0


if __name__ == "__main__":
    sys.exit(main())
