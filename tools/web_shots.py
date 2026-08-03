#!/usr/bin/env python3
"""喺一個**真瀏覽器**入面開 web build,兩種語言各影一套圖。

點解要有:第十一輪嘅亂碼 bug 喺桌面版係睇唔到嘅(桌面有系統字型做後備,
網頁版冇)。即係話任何「喺桌面截圖自查」嘅流程,對呢一類 bug 完全盲。
呢個腳本影嘅係 GitHub Pages 上面真真正正嗰個畫面。

用法:
    python tools/web_shots.py [--dir docs] [--out qa/screenshots/round-13-web] [--port 8791]

需要 playwright + chromium(`pip install playwright && playwright install
chromium`)。冇就 exit 2,唔會扮成功。
"""

import argparse
import http.server
import pathlib
import socketserver
import sys
import threading
import time

PROJECT = pathlib.Path(__file__).resolve().parent.parent

## 遊戲以 1080x1920 設計,而 stretch=canvas_items/keep 之下 canvas 填滿視窗。
## 用一個剛好一半嘅視窗,設計座標除二就係 CSS 座標 —— 唔使猜。
VW, VH = 540, 960
SCALE = 0.5


def design(x, y):
    return x * SCALE, y * SCALE


## 主選單掣嘅設計座標(見 MainMenu.gd:VBox 由 y=620 起,separation 26)。
MENU = {}
_y = 620.0
for _name, _h in [("play", 120), ("level", 110), ("shop", 110), ("upgrade", 110),
                  ("quick", 110), ("bestiary", 110), ("settings", 110), ("gallery", 90)]:
    MENU[_name] = (540.0, _y + _h / 2.0)
    _y += _h + 26.0

## 圖鑑分頁掣(Bestiary.gd:x = 40 + i*(300+20),闊 300,y = 116,高 84)。
TABS = {"monster": (190.0, 158.0), "tower": (510.0, 158.0), "spell": (830.0, 158.0)}


def serve(root: pathlib.Path, port: int):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(root), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    return httpd


def run(args):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("error: 冇 playwright,影唔到真瀏覽器嘅圖")
        return 2

    root = PROJECT / args.dir
    out = PROJECT / args.out
    out.mkdir(parents=True, exist_ok=True)
    httpd = serve(root, args.port)
    url = "http://127.0.0.1:%d/index.html" % args.port
    print("serving %s at %s" % (root, url))
    problems = []
    try:
        with sync_playwright() as p:
            for locale, tag in [("zh-TW", "zh"), ("en-US", "en")]:
                browser = p.chromium.launch(args=[
                    "--use-gl=angle", "--use-angle=swiftshader",
                    "--enable-unsafe-swiftshader",
                ])
                ctx = browser.new_context(locale=locale,
                                          viewport={"width": VW, "height": VH})
                page = ctx.new_page()
                logs = []
                page.on("console", lambda m: logs.append("%s: %s" % (m.type, m.text)))
                page.on("pageerror", lambda e: logs.append("pageerror: %s" % e))
                page.goto(url)
                # 38MB wasm 要編譯,慢機要幾十秒。等到 status overlay 消失為止。
                deadline = time.time() + args.timeout
                ready = False
                while time.time() < deadline:
                    gone = page.evaluate(
                        "() => !document.getElementById('status')")
                    if gone:
                        ready = True
                        break
                    time.sleep(0.5)
                if not ready:
                    problems.append("[%s] 遊戲喺 %ds 之內載入唔到" % (tag, args.timeout))
                time.sleep(3.0)

                dpr = page.evaluate("() => window.__tfDpr || null")
                print("[%s] __tfDpr = %s" % (tag, dpr))
                if dpr is None:
                    problems.append("[%s] head_include 冇行到(__tfDpr 唔存在)" % tag)
                # Web.gd 掛上去嘅暫停 callback。呢個係 GDScript ↔ JS 之間唯一
                # 一條線,而佢斷咗係**靜**嘅:遊戲照玩,只係切走之後唔會暫停,
                # 而嗰個正正就係 iOS 收記憶體嗰一刻。
                hooked = page.evaluate("() => typeof window.__tfVisibility")
                print("[%s] window.__tfVisibility = %s" % (tag, hooked))
                if hooked != "function":
                    problems.append("[%s] Web.gd 冇掛到暫停 callback(%s)" % (tag, hooked))

                shots = [("01_menu", None)]
                page.screenshot(path=str(out / ("%s_01_menu.png" % tag)))
                _tap(page, MENU["bestiary"])
                time.sleep(1.5)
                page.screenshot(path=str(out / ("%s_02_compendium_monster.png" % tag)))
                _tap(page, TABS["tower"])
                time.sleep(1.5)
                page.screenshot(path=str(out / ("%s_03_compendium_tower.png" % tag)))
                _tap(page, TABS["spell"])
                time.sleep(1.5)
                page.screenshot(path=str(out / ("%s_04_compendium_spell.png" % tag)))
                # 返主選單 -> 升級介面
                _tap(page, (124.0, 74.0))          # 「返回」
                time.sleep(1.5)
                _tap(page, MENU["upgrade"])
                time.sleep(1.5)
                page.screenshot(path=str(out / ("%s_05_upgrade.png" % tag)))
                _tap(page, MENU["shop"])           # (主選單已經走咗,呢下係無害嘅)
                time.sleep(0.5)

                errs = [l for l in logs if l.startswith(("error", "pageerror"))]
                if errs:
                    problems.append("[%s] console 有錯:%s" % (tag, errs[:4]))
                for line in logs[-12:]:
                    print("[%s] %s" % (tag, line))
                ctx.close()
                browser.close()
                print("[%s] %d shots -> %s" % (tag, len(shots) + 4, out))
    finally:
        httpd.shutdown()

    if problems:
        print("WEBSHOTS FAIL")
        for pr in problems:
            print("  " + pr)
        return 1
    print("WEBSHOTS OK")
    return 0


def _tap(page, pt):
    x, y = design(*pt)
    page.mouse.click(x, y)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--out", default="qa/screenshots/web")
    ap.add_argument("--port", type=int, default=8791)
    ap.add_argument("--timeout", type=int, default=180)
    return run(ap.parse_args())


if __name__ == "__main__":
    sys.exit(main())
