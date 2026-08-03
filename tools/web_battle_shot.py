#!/usr/bin/env python3
"""喺一個真瀏覽器度入到一場戰鬥再影相 + 收 console。

`tools/web_shots.py` 影嘅係選單 / 圖鑑 / 升級 —— 全部係靜態 UI。合批輪改嘅
係戰鬥入面點樣畫,所以要一張**戰鬥**嘅網頁截圖先驗得到。

用法:
    python tools/web_battle_shot.py [--dir docs] [--out qa/screenshots/round-14-batching/web]
"""
import argparse
import http.server
import pathlib
import socketserver
import sys
import threading
import time

PROJECT = pathlib.Path(__file__).resolve().parent.parent
VW, VH = 540, 960
SCALE = 0.5
PLAY_BTN = (540.0, 680.0)     # MainMenu 第一個掣嘅中心(設計坐標)


def serve(root, port):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(root), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--out", default="qa/screenshots/round-14-batching/web")
    ap.add_argument("--port", type=int, default=8793)
    ap.add_argument("--battle-seconds", type=float, default=25.0)
    args = ap.parse_args()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("需要 playwright:  pip install playwright && playwright install chromium")
        return 2
    root = PROJECT / args.dir
    out = PROJECT / args.out
    out.mkdir(parents=True, exist_ok=True)
    serve(root, args.port)
    url = "http://127.0.0.1:%d/index.html" % args.port
    logs = []
    with sync_playwright() as p:
        br = p.chromium.launch(args=["--use-gl=angle", "--enable-webgl",
                                     "--ignore-gpu-blocklist"])
        page = br.new_page(viewport={"width": VW, "height": VH},
                           device_scale_factor=1)
        page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
        page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))
        page.goto(url)
        page.wait_for_timeout(12000)          # wasm + pck + 第一個畫面
        page.mouse.click(PLAY_BTN[0] * SCALE, PLAY_BTN[1] * SCALE)
        page.wait_for_timeout(4000)
        page.screenshot(path=str(out / "zh_06_battle_start.png"))
        # 落幾座塔 —— 冇塔就冇炮彈、冇特效、冇傷害數字,而嗰三樣正正就係
        # 合批輪改得最多嘅嘢。唔落塔嘅網頁截圖驗唔到 MultiMesh 嗰條路。
        # 用**拖**唔用兩下撳:拖卡落場係主要嘅落塔路徑(見 Battle 嘅
        # card_press / card_drag / card_release),而兩下撳嗰個後備路徑
        # 對時序敏感好多。
        for card_x, spot in [(44, (150, 250)), (120, (350, 250)),
                             (196, (150, 300)), (44, (350, 300))]:
            page.mouse.move(card_x, 819)
            page.mouse.down()
            page.wait_for_timeout(120)
            page.mouse.move(spot[0], spot[1], steps=12)
            page.wait_for_timeout(200)
            page.mouse.up()
            page.wait_for_timeout(600)
        # 行一段時間先有怪、有塔開火、有特效
        page.wait_for_timeout(int(args.battle_seconds * 1000))
        page.screenshot(path=str(out / "zh_07_battle_mid.png"))
        br.close()
    errs = [l for l in logs
            if l.startswith("error") or l.startswith("pageerror")
            or "ERROR" in l or "SCRIPT ERROR" in l]
    for l in logs:
        if l.startswith("log: Godot") or l.startswith("log: OpenGL"):
            print("  " + l)
    if errs:
        print("WEBBATTLE FAIL — console 有錯:")
        for e in errs[:10]:
            print("   " + e)
        return 1
    print("WEBBATTLE OK — %d 條 console 訊息,0 個錯" % len(logs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
