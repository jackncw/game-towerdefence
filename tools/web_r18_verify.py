#!/usr/bin/env python3
"""第十八輪嘅真瀏覽器驗證:早期張力 + 20 關後 20+ 座塔 + 塔位/效能。

流程:
  A. 早期關(fresh 存檔,第 1 關):唔注入任何嘢,量「開場買得起幾多座 +
     打一陣之後再買得起幾多座」。要睇到嘅係「起邊座要諗」,唔係鋪滿。
  B. 第 21 關(注入「已通 20 關 + 強力 build」存檔):連續拖 24 座塔落場,
     每 6 座影一張,驗塔位夠 + 卡面固定價 + 金幣跟得上。
  C. 全程收 console,一個 error 都唔准有;順手用 requestAnimationFrame
     量真瀏覽器嘅幀時間(塔多咗之後有冇跌)。

用法:  python tools/web_r18_verify.py [--dir docs] [--out qa/screenshots/round-18-web]
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

APP_DIR = "/userfs/godot/app_userdata/塔防要塞 Tower Fortress"

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
          const rec = g.result;
          rec.contents = enc;
          rec.timestamp = new Date(Date.now() + 60000);
          const pu = st.put(rec, key);
          pu.onsuccess = () => { db.close(); resolve('OK ' + key); };
          pu.onerror = () => { db.close(); reject(pu.error); };
        };
        g.onerror = () => { db.close(); reject(g.error); };
      };
      ks.onerror = () => { db.close(); reject(ks.error); };
    };
    req.onerror = () => reject(req.error);
  });
}"""

# 真瀏覽器幀時間:連續 120 幀嘅 rAF 間隔,取平均同 p95。
FRAME_JS = """() => new Promise((resolve) => {
  const ts = []; let last = performance.now();
  function tick(now) {
    ts.push(now - last); last = now;
    if (ts.length < 120) requestAnimationFrame(tick);
    else {
      const s = ts.slice(10).sort((a, b) => a - b);
      const avg = s.reduce((a, b) => a + b, 0) / s.length;
      resolve({avg: avg, p95: s[Math.floor(s.length * 0.95)]});
    }
  }
  requestAnimationFrame(tick);
})"""


def strong_save(locale):
    """一份打到第 59 關嘅存檔(B 段用)。

    點解係 59 唔係 20:呢個 build(箭塔 T3 滿課)喺第 21 關十幾秒就贏晒,
    根本冇時間鋪到 20 座塔 —— 影出嚟四張全部係結算畫面。第 60 關嘅怪硬到
    要真係鋪陣先打得郁,而 (60-1)%6 = 5 同 (21-1)%6 = 2 一樣係五條橫掃,
    所以下面嗰啲塔位座標唔使改。
    """
    return {
        "version": 3,
        "crystals": 90000,
        "highest_level": 59,
        "cleared": {str(n): True for n in range(1, 60)},
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


def drag_tower(page, card_css_x, spot_design):
    """由塔卡拖去 design 座標嘅位。"""
    page.mouse.move(card_css_x, 819)
    page.mouse.down()
    page.wait_for_timeout(120)
    page.mouse.move(spot_design[0] * S, spot_design[1] * S, steps=10)
    page.wait_for_timeout(180)
    page.mouse.up()
    page.wait_for_timeout(320)


# 第 21 關 path_idx = (21-1)%6 = 2 -> 五條橫掃,行喺 y≈298/550/802/1054/1306。
# 揀行與行之間嘅帶(y≈420/670/930/1180)同兩邊嘅邊欄,每帶六個 x。
SPOTS_21 = [(x, y) for y in (420, 672, 924, 1180)
            for x in (160, 310, 460, 610, 760, 900)]


def run(p, url, out):
    logs = []
    br = p.chromium.launch(args=["--use-gl=angle", "--enable-webgl",
                                 "--ignore-gpu-blocklist"])
    page = br.new_page(viewport={"width": VW, "height": VH},
                       device_scale_factor=1)
    page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
    page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))

    # ---- A. 早期關:fresh 存檔,直接入第 1 關 ----------------------------
    page.goto(url)
    page.wait_for_timeout(16000)
    page.screenshot(path=str(out / "a_01_menu.png"))
    click(page, 540, 680, 5000)
    page.screenshot(path=str(out / "a_02_lv01_start.png"))     # 開場金 200
    # 開場買得起幾多座:一路拖到拖唔郁為止(每座箭塔 60)
    for i, spot in enumerate(SPOTS_21[:6]):
        drag_tower(page, 44, spot)
    page.screenshot(path=str(out / "a_03_lv01_opening.png"))
    # 打一陣(x3)再影 —— 呢張就係「早期張力」嗰張
    click(page, 990, 63, 300)
    page.wait_for_timeout(25000)
    page.screenshot(path=str(out / "a_04_lv01_mid.png"))
    for i, spot in enumerate(SPOTS_21[6:14]):
        drag_tower(page, 44, spot)
    page.wait_for_timeout(20000)
    page.screenshot(path=str(out / "a_05_lv01_late.png"))
    fa = page.evaluate(FRAME_JS)
    print("  A 早期關幀時間 avg=%.2fms p95=%.2fms" % (fa["avg"], fa["p95"]))

    # ---- B. 第 21 關:注入強力存檔 --------------------------------------
    for _ in range(10):
        r = page.evaluate(INJECT_JS, json.dumps(strong_save("zh_TW")))
        if r != "NO-SAVE-KEY":
            print("  inject:", r)
            break
        page.wait_for_timeout(4000)
    else:
        print("  inject: save key never appeared")
    page.goto(url)
    page.wait_for_timeout(14000)
    click(page, 540, 680, 5000)
    page.screenshot(path=str(out / "b_01_lv60_start.png"))
    # 一次過拖 24 座係唔得嘅 —— 起手金只夠 ~9 座,之後要等掉落。真人就係
    # 「起幾座 → 打一陣 → 再起幾座」,所以呢度分四批,每批之間開 x3 等收入。
    click(page, 990, 63, 300)         # x1 -> x3
    built = 0
    for batch in range(4):
        for spot in SPOTS_21[batch * 6:(batch + 1) * 6]:
            drag_tower(page, 44, spot)
            built += 1
        page.screenshot(path=str(out / ("b_04_towers_%02d.png" % built)))
        page.wait_for_timeout(16000)
    # 收尾:剩返嘅金再鋪一轉
    for spot in SPOTS_21:
        drag_tower(page, 44, spot)
    page.screenshot(path=str(out / "b_05_towers_full.png"))
    fb = page.evaluate(FRAME_JS)
    print("  B 第21關(%d 次落塔)幀時間 avg=%.2fms p95=%.2fms"
          % (built, fb["avg"], fb["p95"]))
    click(page, 990, 63, 300)         # x3 -> x5
    for i in range(6):
        page.wait_for_timeout(15000)
        page.screenshot(path=str(out / ("b_06_progress_%d.png" % i)))
    page.screenshot(path=str(out / "b_07_end.png"))

    br.close()
    errs = [l for l in logs
            if (l.startswith("error") or l.startswith("pageerror")
                or "ERROR" in l or "SCRIPT ERROR" in l)
            and "status of 404" not in l]
    return logs, errs, fa, fb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--out", default="qa/screenshots/round-18-web")
    ap.add_argument("--port", type=int, default=8798)
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
    with sync_playwright() as p:
        logs, errs, fa, fb = run(p, url, out)
    print("%d 條 console,%d 個 error" % (len(logs), len(errs)))
    for e in errs[:10]:
        print("   " + e)
    if errs:
        print("WEB_R18 FAIL")
        return 1
    print("WEB_R18 OK — console 零 error")
    return 0


if __name__ == "__main__":
    sys.exit(main())
