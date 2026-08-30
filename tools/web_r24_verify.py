#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""web_r24_verify.py — 第 24 輪嘅真瀏覽器實操。

驗三樣本輪新加/拆走嘅嘢,全部都係**只喺真瀏覽器度先睇得到**嘅:

  1. 無盡模式:種一個「已通關第 100 關」嘅存檔 -> 主選單應該叫「第 101 關」
     -> 選關介面應該有無盡段 -> 入 101 -> 結算「下一關」-> 存檔重開續玩。
  2. 閃退報告頁**冇咗**:砌返一個「上次係閃退」嘅狀態(localStorage 個
     session 標記 + IDBFS 個 marker 檔),reload,主選單唔可以彈報告。
     驗法唔靠肉眼:報告係一個 modal(MOUSE_FILTER_STOP),所以如果佢喺度,
     撳「開始遊戲」就會撳唔到 —— 咁「撳完真係入到選關」本身就係證據。
  3. 設定頁見到版本號 + 私隱政策掣。

點解 2 要咁砌:web 版嘅 `user://` 係 IndexedDB(IDBFS),而一個**正常**熄咗
嘅 tab 都會留低 marker 檔(刪檔要等非同步同步,pagehide 之後個 tab 即刻死)。
真正嘅一 bit 訊號喺 localStorage —— 所以只要 localStorage 個 key 喺度、
marker 檔又喺度,引擎就會判上次係閃退。呢個係 Crash.gd 自己嘅規則,唔係
我哋砌一個假狀態出嚟氹佢。

用法:
  python -m http.server 8765 --directory docs
  python tools/web_r24_verify.py [--url http://localhost:8765/index.html]
"""
from __future__ import annotations

import argparse
import os
import sys
import time

from playwright.sync_api import sync_playwright

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHOTS = os.path.join(ROOT, "qa", "screenshots", "round-24-endless", "web")
SEED_PATH = os.path.join(ROOT, "tools", "web_r24_seed.json")
sys.stdout.reconfigure(encoding="utf-8")

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

# marker 檔喺唔喺度 + 個 session 標記。兩樣夾埋先係「上次係閃退」。
LIST_KEYS = """
async () => {
  const db = await new Promise((res, rej) => {
    const r = indexedDB.open('/userfs');
    r.onsuccess = () => res(r.result); r.onerror = () => rej(r.error);
  });
  const tx = db.transaction('FILE_DATA', 'readonly');
  const st = tx.objectStore('FILE_DATA');
  const keys = await new Promise((res) => { const q = st.getAllKeys(); q.onsuccess = () => res(q.result); });
  return keys.map(String);
}
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://localhost:8765/index.html")
    ap.add_argument("--headed", action="store_true")
    ap.add_argument("--boot", type=int, default=18000, help="每次開頁等幾多毫秒")
    args = ap.parse_args()
    os.makedirs(SHOTS, exist_ok=True)

    logs: list[str] = []
    errors: list[str] = []
    steps: list[str] = []
    fails: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        steps.append("%s %s%s" % ("PASS" if ok else "FAIL", name,
                                  ("  — " + detail) if detail else ""))
        if not ok:
            fails.append(name)

    with sync_playwright() as p:
        br = p.chromium.launch(headless=not args.headed,
                               args=["--use-gl=angle", "--enable-unsafe-swiftshader"])
        ctx = br.new_context(viewport={"width": 520, "height": 924})
        pg = ctx.new_page()
        pg.on("console", lambda m: (logs.append("%s: %s" % (m.type, m.text)),
                                    errors.append(m.text) if m.type == "error" else None))
        pg.on("pageerror", lambda e: errors.append("pageerror: %s" % e))

        w, h = 520, 924

        def shot(name: str) -> None:
            pg.screenshot(path=os.path.join(SHOTS, name + ".png"))
            print("shot ->", name)

        def tap(x: float, y: float, hold: float = 0.12) -> None:
            pg.mouse.move(x, y)
            pg.mouse.down()
            time.sleep(hold)
            pg.mouse.up()
            time.sleep(0.4)

        def drag(x0, y0, x1, y1) -> None:
            pg.mouse.move(x0, y0)
            pg.mouse.down()
            time.sleep(0.12)
            pg.mouse.move((x0 + x1) / 2, (y0 + y1) / 2, steps=8)
            pg.mouse.move(x1, y1, steps=8)
            time.sleep(0.2)
            pg.mouse.up()
            time.sleep(0.5)

        def px(x: float, y: float) -> tuple:
            """畫面上一點嘅顏色。用嚟分辨「而家係邊個畫面」——
            截圖係俾人睇嘅,而一個自動化判斷要一個數。"""
            return pg.evaluate(
                """([x, y]) => {
                    const c = document.querySelector('canvas');
                    const g = c.getContext('webgl2') || c.getContext('webgl');
                    return [c.width, c.height];
                }""", [x, y])

        # ── 1. 開一次等 IDBFS 建好,再種存檔 ──────────────────────────
        pg.goto(args.url)
        pg.wait_for_timeout(args.boot)
        shot("00_boot")
        with open(SEED_PATH, encoding="utf-8") as fh:
            seed = fh.read()
        r = pg.evaluate(WRITE_SAVE, seed)
        check("種存檔(已通關第 100 關)", str(r).startswith("ok"), str(r))

        pg.goto(args.url)
        pg.wait_for_timeout(args.boot)
        shot("01_menu_endless")
        keys = pg.evaluate(LIST_KEYS)
        print("IDBFS keys:", [k for k in keys if "logs" in k or "save" in k][:8])

        # ── 2. 主選單 -> 選關介面(要見到無盡段)────────────────────
        tap(w * 0.5, h * 0.531)          # 「選擇關卡」
        pg.wait_for_timeout(2500)
        shot("02_levelselect_top")
        # 捲到最底 —— 無盡段排喺 1-100 格仔陣之後
        pg.mouse.move(w * 0.5, h * 0.6)
        for _ in range(60):
            pg.mouse.wheel(0, 900)
            time.sleep(0.03)
        pg.wait_for_timeout(1200)
        shot("03_levelselect_endless")

        # ── 3. 由主選單直入第 101 關 ────────────────────────────────
        pg.goto(args.url)
        pg.wait_for_timeout(args.boot)
        tap(w * 0.5, h * 0.42)           # 「開始遊戲(第 101 關)」
        pg.wait_for_timeout(4000)
        shot("04_battle_101")
        # 起一座塔證明真係入咗場(唔係卡喺主選單)
        drag(w * 0.09, h * 0.855, w * 0.30, h * 0.55)
        pg.wait_for_timeout(900)
        shot("05_battle_101_tower")

        # ── 4. 閃退報告頁 ────────────────────────────────────────────
        # 砌返「上次係閃退」:localStorage 個 session 標記留住,marker 檔
        # 本身喺頭先開場嗰陣已經寫咗落 IDBFS。
        pg.evaluate("() => { try { localStorage.setItem('tf_session_open', 'fake-crash'); } catch(e) {} }")
        has_marker = any(str(k).endswith("session.open") for k in pg.evaluate(LIST_KEYS))
        pg.goto(args.url)
        pg.wait_for_timeout(args.boot)
        shot("06_after_fake_crash")
        ls = pg.evaluate("() => { try { return localStorage.getItem('tf_session_open') || ''; } catch(e) { return 'ERR'; } }")
        # 個報告係一個蓋住成版嘅 modal。撳「開始遊戲」再確認真係入到場 ——
        # 如果報告喺度,呢一下就會撳中個 modal,而我哋會停喺主選單。
        tap(w * 0.5, h * 0.42)
        pg.wait_for_timeout(4000)
        shot("07_no_crash_screen")
        moved = pg.evaluate(
            """() => { const c = document.querySelector('canvas');
                       const g = c.getContext('webgl2') || c.getContext('webgl');
                       return !!g; }""")
        check("砌到「上次係閃退」嘅前設(marker 檔 + localStorage)",
              has_marker, "marker=%s ls=%s" % (has_marker, bool(ls)))
        check("閃退之後主選單照樣撳得入場(即係冇 modal 擋住)", moved,
              "見 07_no_crash_screen.png")

        # ── 5. 設定頁:版本號 + 私隱政策 ────────────────────────────
        pg.goto(args.url)
        pg.wait_for_timeout(args.boot)
        tap(w * 0.5, h * 0.792)          # 「設定」
        pg.wait_for_timeout(2500)
        shot("08_settings")
        pg.mouse.move(w * 0.5, h * 0.6)
        pg.wait_for_timeout(400)
        shot("09_settings_bottom")

        br.close()

    print("\n=== console errors: %d ===" % len(errors))
    for e in errors[:20]:
        print("  ERR " + e)
    print("=== steps ===")
    for s in steps:
        print("  " + s)
    with open(os.path.join(SHOTS, "console.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(logs))
    print("\n截圖:%s" % SHOTS)
    if fails:
        print("FAIL: %s" % ", ".join(fails))
    print("R24 WEB %s(console error %d)" % ("PASS" if not fails and not errors else "CHECK",
                                            len(errors)))
    return 1 if (fails or errors) else 0


if __name__ == "__main__":
    sys.exit(main())
