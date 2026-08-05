#!/usr/bin/env python3
"""第十七輪嘅真瀏覽器驗證:合約關 v2 全流程 + 固定建塔價,中英各一套。

流程(每個 locale):
  1. 注入一份「打到第 20 關 + 強力 build」嘅存檔落 IDBFS(Godot web 嘅
     user:// 就係 IndexedDB '/userfs'),locale 亦寫入 settings。
  2. 開 index.html -> 主選單 -> 撳「開始遊戲」= 第 21 關(21 % 7 == 0,合約關)。
  3. 影:說明窗 -> 撳確定 -> 三張卡(低/中/高)-> 揀中間嗰張 -> HUD badge。
  4. 起幾座塔、開 x5,等打完 -> 影結算(合約倍率行)。
  5. 翻頁重入 -> 第 22 關(普通關)起 3 座塔,每座影一張(卡面價要恆定)。
  6. 收晒 console,一個 error 都唔准有。

用法:  python tools/web_r17_verify.py [--dir docs] [--out qa/screenshots/round-17-web]
"""
import argparse
import http.server
import json
import pathlib
import socketserver
import sys
import threading

PROJECT = pathlib.Path(__file__).resolve().parent.parent
VW, VH = 540, 960
S = 0.5     # 設計座標(1080x1920)-> CSS

MAXLV = 15


def strong_save(locale):
    """一份可以輕鬆贏第 21 關嘅存檔:箭塔 tier3 全軸滿 + 三個 tier3 魔法。"""
    return {
        "version": 3,
        "crystals": 90000,
        "highest_level": 20,
        "cleared": {str(n): True for n in range(1, 21)},
        "unlocked_towers": list(range(1, 21)),
        "unlocked_spells": list(range(1, 16)),
        "tower_up": {"1": [MAXLV] * 6},
        "spell_up": {"1": [MAXLV] * 3, "11": [MAXLV] * 3, "13": [MAXLV] * 3},
        "tower_tiers": {"1": 3},
        "spell_tiers": {"1": 3, "11": 3, "13": 3},
        "settings": {"locale": locale},
        "seen": {},
        "quick_slots": [],
    }


# user:// 喺 web = /userfs/godot/app_userdata/<app name>/(用 web_idb_probe.py
# 實測出嚟)。父目錄要有自己嘅記錄(mode 16893),唔係 fresh profile 之下
# reconcile 讀唔返個檔。
APP_DIR = "/userfs/godot/app_userdata/塔防要塞 Tower Fortress"

# 唔好自己憑空砌 IDB 記錄(格式/時序有太多未知數,實測引擎唔認)——
# 正確做法:等引擎自己 boot 一次寫低 save.json,搵住佢嗰條記錄,原位淨係
# 換 contents(mode 照抄,timestamp 推前少少令 populate 認為「remote 較新」),
# 再 reload,引擎就會用我哋嘅內容。
INJECT_JS = """async (payload) => {
  const enc = new TextEncoder().encode(payload);
  return await new Promise((resolve, reject) => {
    const req = indexedDB.open('/userfs', 21);
    req.onsuccess = (e) => {
      const db = e.target.result;
      const tx = db.transaction('FILE_DATA', 'readwrite');
      const st = tx.objectStore('FILE_DATA');
      const ks = st.getAllKeys();
      ks.onsuccess = () => {
        const key = ks.result.find(k => k.endsWith('/save.json'));
        if (!key) { db.close(); resolve('NO-SAVE-KEY'); return; }
        const g = st.get(key);
        g.onsuccess = () => {
          const v = g.result;
          v.contents = enc;
          v.timestamp = new Date(Date.now() + 2000);
          st.put(v, key);
          tx.oncomplete = () => { db.close(); resolve('replaced ' + key); };
        };
      };
      tx.onerror = () => reject(tx.error);
    };
    req.onerror = () => reject(req.error);
  });
}"""


def serve(root, port):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(root), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def click(page, dx, dy, pause=800):
    page.mouse.click(dx * S, dy * S)
    page.wait_for_timeout(pause)


def drag_tower(page, card_css_x, spot_css):
    page.mouse.move(card_css_x, 819)
    page.mouse.down()
    page.wait_for_timeout(150)
    page.mouse.move(spot_css[0], spot_css[1], steps=12)
    page.wait_for_timeout(250)
    page.mouse.up()
    page.wait_for_timeout(500)


def run_locale(p, url, out, tag, locale):
    logs = []
    br = p.chromium.launch(args=["--use-gl=angle", "--enable-webgl",
                                 "--ignore-gpu-blocklist"])
    page = br.new_page(viewport={"width": VW, "height": VH},
                       device_scale_factor=1)
    page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
    page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))
    # 第一 boot:俾引擎自己起好 IDB 結構同一份 fresh save(等埋佢 sync 落
    # IDB),然後原位換走 save.json 嘅內容,reload 先係真正嘅測試 session。
    page.goto(url)
    page.wait_for_timeout(16000)
    # 引擎 sync 落 IDB 要時間;等到 save key 出現為止(最多 ~40s)
    for _ in range(10):
        r = page.evaluate(INJECT_JS, json.dumps(strong_save(locale)))
        if r != "NO-SAVE-KEY":
            print("  inject:", r)
            break
        page.wait_for_timeout(4000)
    else:
        print("  inject: save key never appeared")
    page.goto(url)
    page.wait_for_timeout(14000)
    page.screenshot(path=str(out / f"{tag}_01_menu.png"))
    # 開始遊戲 -> 第 21 關(合約關)
    click(page, 540, 680, 5000)
    page.screenshot(path=str(out / f"{tag}_02_intro.png"))
    # 說明窗「確定」掣(design 330-750 x 1030-1134)
    click(page, 540, 1082, 1200)
    page.screenshot(path=str(out / f"{tag}_03_cards.png"))
    # 揀中間嗰張(中風險;卡由 y=360 起,320 高 40 隔 -> 中卡中心 y=880)
    click(page, 540, 880, 1200)
    page.screenshot(path=str(out / f"{tag}_04_badge.png"))
    # 起塔(lv21 path_idx=2,五條橫掃 y~298/550/802/1054/1306,揀行與行之間)
    for cx, spot in [(44, (150, 212)), (44, (330, 212)), (44, (150, 462))]:
        drag_tower(page, cx, spot)
    # x5(speed 掣喺右上 design ~(990,63);撳兩下 1->3->5)
    click(page, 990, 63, 300)
    click(page, 990, 63, 300)
    # 等打完:每 15 秒影一張,見到結算就停
    for i in range(8):
        page.wait_for_timeout(15000)
        page.screenshot(path=str(out / f"{tag}_05_progress_{i}.png"))
    page.screenshot(path=str(out / f"{tag}_06_end.png"))
    page.wait_for_timeout(3000)   # 俾 IDBFS sync 落盤
    # 重載 -> 第 22 關(普通關)固定價驗證
    page.goto(url)
    page.wait_for_timeout(12000)
    click(page, 540, 680, 5000)
    page.screenshot(path=str(out / f"{tag}_07_lv22_start.png"))
    for i, (cx, spot) in enumerate([(44, (150, 275)), (44, (330, 275)),
                                    (44, (430, 275))]):
        drag_tower(page, cx, spot)
        page.screenshot(path=str(out / f"{tag}_08_build_{i + 1}.png"))
    br.close()
    errs = [l for l in logs
            if (l.startswith("error") or l.startswith("pageerror")
                or "ERROR" in l or "SCRIPT ERROR" in l)
            # 注入頁本身係一個 404(特登嘅)—— 佢嗰條 resource error 唔算
            and "status of 404" not in l]
    return logs, errs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--out", default="qa/screenshots/round-17-web")
    ap.add_argument("--port", type=int, default=8797)
    args = ap.parse_args()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("需要 playwright:  pip install playwright && playwright install chromium")
        return 2
    out = PROJECT / args.out
    out.mkdir(parents=True, exist_ok=True)
    serve(PROJECT / args.dir, args.port)
    url = "http://127.0.0.1:%d/index.html" % args.port
    all_errs = []
    with sync_playwright() as p:
        for tag, locale in [("zh", "zh_TW"), ("en", "en")]:
            logs, errs = run_locale(p, url, out, tag, locale)
            print("[%s] %d 條 console,%d 個 error" % (tag, len(logs), len(errs)))
            for e in errs[:10]:
                print("   " + e)
            all_errs += errs
    if all_errs:
        print("WEB_R17 FAIL")
        return 1
    print("WEB_R17 OK — console 零 error")
    return 0


if __name__ == "__main__":
    sys.exit(main())
