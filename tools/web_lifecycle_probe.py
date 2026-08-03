#!/usr/bin/env python3
"""喺一個**真瀏覽器**入面驗:邊四種離開方式會被當成閃退。

點解要有:crash marker 靠 `_close()` 刪,而 `_close()` 掛喺 Godot 嘅
WM_CLOSE_REQUEST / EXIT_TREE / PREDELETE 上面。網頁版熄 tab 一個都唔會派 ——
個 process 係俾瀏覽器直接殺。所以修完之後要答嘅唔係「code 睇落啱唔啱」,
而係「瀏覽器真係會派嗰啲事件嗎,而我哋真係接到嗎」。

四種情況,每種做完之後重新開一次個頁,睇 console 有冇嗰句
`[Crash] 偵測到上一次啟動非正常結束`:

    A 熄 tab        page.close()            -> 唔應該報
    B 切 tab        visibilitychange hidden -> 唔應該報
    C 返轉頭        pagehide 之後 pageshow  -> 唔應該報(而且要重新上膛)
    D 真 crash      CDP Page.crash          -> **應該報**

D 用 CDP 嘅 Page.crash:佢直接殺 renderer,唔會派任何 lifecycle 事件 ——
即係一單真閃退嘅樣。呢個係唯一一種「唔靠扮」嘅做法。

marker 住喺 IndexedDB(emscripten IDBFS),而 IDBFS 係**定期**同步落去嘅,
所以每種情況都要俾個遊戲行一陣先郁佢,唔係嘅話 D 會因為 marker 根本未寫得入
去而變成假陰性。

用法:  python tools/web_lifecycle_probe.py [--dir docs] [--port 8796]
"""

import argparse
import http.server
import pathlib
import socketserver
import subprocess
import sys
import tempfile
import threading

PROJECT = pathlib.Path(__file__).resolve().parent.parent
CRASH_LINE = "偵測到上一次啟動非正常結束"
## 開場之後行幾多秒先郁佢。要夠 IDBFS 同步一次。
SETTLE_S = 9.0


def serve(directory: str, port: int):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=directory, **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--port", type=int, default=8796)
    args = ap.parse_args()
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("error: 要 playwright + chromium("
              "pip install playwright && playwright install chromium)")
        return 2

    root = str((PROJECT / args.dir).resolve())
    serve(root, args.port)
    url = f"http://127.0.0.1:{args.port}/index.html"
    profile = tempfile.mkdtemp(prefix="tf-lifecycle-")
    results = []

    with sync_playwright() as pw:
        # persistent context:四種情況要共用同一個 IndexedDB,唔係嘅話
        # 每次開場都係「全新裝機」,永遠見唔到上一次留低嘅 marker。
        ctx = pw.chromium.launch_persistent_context(profile, headless=True)

        def open_page():
            page = ctx.new_page()
            seen = {"crash": False}
            page.on("console", lambda m: seen.__setitem__(
                "crash", seen["crash"] or CRASH_LINE in m.text))
            page.goto(url, wait_until="load")
            page.wait_for_timeout(int(SETTLE_S * 1000))
            return page, seen

        def check(label, expect_crash, action):
            page, seen = open_page()
            try:
                action(page)
            except Exception as e:
                # D 之後隻 page 係真係死咗嘅 —— 任何再掂佢嘅呼叫都會throw。
                # 嗰個係預期之內,唔應該拖冧成個 probe。
                print(f"  ({label}: {type(e).__name__} — 預期之內)")
            try:
                if not page.is_closed():
                    page.close()
            except Exception:
                pass
            # 再開一次新頁,睇佢點判上一次
            page2, seen2 = open_page()
            got = seen2["crash"]
            ok = (got == expect_crash)
            results.append((label, expect_crash, got, ok))
            try:
                page2.close()
            except Exception:
                pass

        # A 熄 tab —— page.close() 會派 pagehide
        check("A 熄 tab (page.close)", False, lambda p: p.close())

        # B 切 tab —— 淨係 visibilitychange,個頁仲喺度
        def bg(p):
            p.evaluate("""() => {
                Object.defineProperty(document, 'visibilityState',
                    {get: () => 'hidden', configurable: true});
                Object.defineProperty(document, 'hidden',
                    {get: () => true, configurable: true});
                document.dispatchEvent(new Event('visibilitychange'));
            }""")
            p.wait_for_timeout(2000)
            p.close()
        check("B 切 tab (visibilitychange hidden)", False, bg)

        # C 返轉頭 —— pagehide 之後 pageshow(bfcache 恢復嘅樣),再玩一陣
        def back(p):
            p.evaluate("() => window.dispatchEvent(new PageTransitionEvent('pagehide', {persisted: true}))")
            p.wait_for_timeout(1500)
            p.evaluate("() => window.dispatchEvent(new PageTransitionEvent('pageshow', {persisted: true}))")
            p.wait_for_timeout(4000)
            p.close()
        check("C 返轉頭 (pagehide -> pageshow)", False, back)

        ctx.close()

    # D 真 crash —— 直接殺 browser process,一個 lifecycle 事件都唔會派。
    #
    # 唔用 CDP 嘅 Page.crash:喺 persistent context 之下佢會連個 browser
    # 一齊拉冧,之後 new_page() 就 "Connection closed while reading from
    # the driver",成個 probe 死埋。而且「殺 process」本身就係最貼近
    # iOS Safari 收 tab 嗰件事嘅做法 —— 冇 pagehide,冇 unload,乜都冇。
    with sync_playwright() as pw:
        ctx = pw.chromium.launch_persistent_context(profile, headless=True)
        page = ctx.new_page()
        page.goto(url, wait_until="load")
        page.wait_for_timeout(int(SETTLE_S * 1000))
        subprocess.run(["taskkill", "/IM", "chrome-headless-shell.exe", "/F"],
                       capture_output=True)
        try:
            ctx.close()
        except Exception:
            pass

    with sync_playwright() as pw:
        ctx = pw.chromium.launch_persistent_context(profile, headless=True)
        page = ctx.new_page()
        seen = {"crash": False}
        page.on("console", lambda m: seen.__setitem__(
            "crash", seen["crash"] or CRASH_LINE in m.text))
        page.goto(url, wait_until="load")
        page.wait_for_timeout(int(SETTLE_S * 1000))
        results.append(("D 真 crash (殺 browser process)", True, seen["crash"],
                        seen["crash"] is True))
        ctx.close()

    print()
    print(f"{'情況':<34}{'應該報?':<10}{'實際報咗?':<12}{'判定'}")
    for label, want, got, ok in results:
        print(f"{label:<34}{str(want):<10}{str(got):<12}{'OK' if ok else 'WRONG'}")
    bad = [r for r in results if not r[3]]
    print()
    if bad:
        print(f"LIFECYCLE FAIL {len(bad)}/{len(results)}")
        return 1
    print(f"LIFECYCLE OK {len(results)}/{len(results)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
