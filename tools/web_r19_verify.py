#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第十九輪(怪物美術)嘅真瀏覽器驗證。

要答嘅問題得三條:
  1. 新怪物圖喺 WebGL2 / Compatibility 渲染器之下畫唔畫得出(atlas 大咗一倍,
     而且怪物 sprite 係全場唯一用 LINEAR filter 嗰批)
  2. 零 console error
  3. 出街 build 體積

流程:注入一份「已通 30 關」嘅存檔入第 31 關(怪物種類夠雜、夠多),
落幾座塔,開 x3,連影幾張,順手量真瀏覽器幀時間。

用法:  python tools/web_r19_verify.py [--dir docs] [--out qa/screenshots/round-19-web]
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

MAXLV = 15


def save30(locale="zh_TW"):
    return {
        "version": 3, "crystals": 60000, "highest_level": 30,
        "cleared": {str(n): True for n in range(1, 31)},
        "unlocked_towers": list(range(1, 21)),
        "unlocked_spells": list(range(1, 16)),
        "tower_up": {"1": [MAXLV] * 6}, "spell_up": {"1": [MAXLV] * 3},
        "tower_tiers": {"1": 2}, "spell_tiers": {"1": 2},
        "settings": {"locale": locale},
        # 圖鑑全開 —— 唔開嘅話圖鑑頁全部黑色剪影,今輪最想睇嗰樣就影唔到
        "seen": {("%s_%s" % (f, s)): True
                 for f in ["goblin", "wolf", "skeleton", "golem", "ghost",
                           "bat", "treant", "beetle", "cultist", "slime"]
                 for s in ["1", "2", "3", "4", "5", "boss"]},
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


def drag_tower(page, card_css_x, spot):
    """落塔一定要用**拖**(down → move → up);兩下撳嗰個後備路徑對時序敏感好多。"""
    page.mouse.move(card_css_x, 819)
    page.mouse.down()
    page.wait_for_timeout(120)
    page.mouse.move(spot[0] * S, spot[1] * S, steps=10)
    page.wait_for_timeout(180)
    page.mouse.up()
    page.wait_for_timeout(300)


SPOTS = [(x, y) for y in (420, 672, 924, 1180)
         for x in (160, 310, 460, 610, 760, 900)]


def run(p, url, out):
    logs = []
    br = p.chromium.launch(args=["--use-gl=angle", "--enable-webgl",
                                 "--ignore-gpu-blocklist"])
    page = br.new_page(viewport={"width": VW, "height": VH},
                       device_scale_factor=1)
    page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
    page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))

    page.goto(url)
    page.wait_for_timeout(16000)
    page.screenshot(path=str(out / "01_menu.png"))

    for _ in range(10):
        r = page.evaluate(INJECT_JS, json.dumps(save30()))
        if r != "NO-SAVE-KEY":
            print("  inject:", r)
            break
        page.wait_for_timeout(4000)
    else:
        print("  inject: save key never appeared")

    page.goto(url)
    page.wait_for_timeout(15000)
    page.screenshot(path=str(out / "02_menu_loaded.png"))

    # 圖鑑:新怪物圖喺瀏覽器度嘅第一眼。主選單 VBox 由 y=620 起,
    # 開始(120)+ 選關 / 商店 / 升級 / 快捷列(各 110)之後先到圖鑑 ≈ y=1315。
    # 1180 嗰個位係「快捷列設定」(踩過)。
    click(page, 540, 1315, 4000)
    page.screenshot(path=str(out / "03_bestiary.png"))
    for _ in range(3):        # 揭幾族,睇多幾張圖
        click(page, 1008, 268, 1200)
    page.screenshot(path=str(out / "03b_bestiary_p4.png"))
    page.goto(url)
    page.wait_for_timeout(15000)

    # 開戰
    click(page, 540, 680, 6000)
    page.screenshot(path=str(out / "04_battle_start.png"))
    # **先影有怪嘅一張**:塔一鋪落去怪就死清光,之後每一張都係空路
    page.wait_for_timeout(9000)
    page.screenshot(path=str(out / "04b_monsters_x1.png"))
    for spot in SPOTS[:4]:
        drag_tower(page, 44, spot)
    page.wait_for_timeout(6000)
    page.screenshot(path=str(out / "04c_monsters_towers.png"))
    for spot in SPOTS[4:8]:
        drag_tower(page, 44, spot)
    page.screenshot(path=str(out / "05_towers.png"))
    click(page, 990, 63, 400)          # x1 -> x3
    for i in range(5):
        page.wait_for_timeout(14000)
        page.screenshot(path=str(out / ("06_fight_%d.png" % i)))
        for spot in SPOTS[8 + i * 3:11 + i * 3]:
            drag_tower(page, 44, spot)
    fr = page.evaluate(FRAME_JS)
    print("  幀時間 avg=%.2fms p95=%.2fms" % (fr["avg"], fr["p95"]))
    page.wait_for_timeout(14000)
    page.screenshot(path=str(out / "07_late.png"))

    br.close()
    errs = [l for l in logs
            if (l.startswith("error") or l.startswith("pageerror")
                or "ERROR" in l or "SCRIPT ERROR" in l)
            and "status of 404" not in l]
    print("  console lines: %d, errors: %d" % (len(logs), len(errs)))
    for e in errs[:20]:
        print("   !", e)
    return len(errs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--out", default="qa/screenshots/round-19-web")
    ap.add_argument("--port", type=int, default=8319)
    a = ap.parse_args()
    root = PROJECT / a.dir
    out = PROJECT / a.out
    out.mkdir(parents=True, exist_ok=True)

    total = 0
    for f in sorted(root.iterdir()):
        if f.is_file():
            total += f.stat().st_size
            if f.stat().st_size > 100_000:
                print("  %-28s %8.2f MB" % (f.name, f.stat().st_size / 1048576))
    print("  web build total: %.2f MB" % (total / 1048576))

    httpd = serve(root, a.port)
    try:
        from playwright.sync_api import sync_playwright
        with sync_playwright() as p:
            rc = run(p, "http://127.0.0.1:%d/index.html" % a.port, out)
    finally:
        httpd.shutdown()
    print("shots ->", out)
    return 1 if rc else 0


if __name__ == "__main__":
    sys.exit(main())
