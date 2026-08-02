#!/usr/bin/env python3
"""喺一個真瀏覽器入面問:網頁版**攞唔攞到**真正嘅 wasm heap 大細?

點解要有:第二份真閃退報告入面 `static=` 由頭到尾都係 `0.0MB`。量過之後
確定咗 `Performance.MEMORY_STATIC` 喺 release template 之下係硬編碼 0
(debug 78.8MB / release 0,同一份 code 同一部機)。即係話閃退報告嘅記憶體
曲線 —— 唯一一件用嚟分「OOM」定「被系統掉走」嘅證物 —— 一直都係一條貼住零
嘅平線。

要補返嗰個數,就要一個喺 Safari 上面都攞得到嘅 heap 數字。`performance.memory`
係 Chromium 專有,`measureUserAgentSpecificMemory()` 要 crossOriginIsolated
(GitHub Pages 冇 COOP/COEP,呢個專案本身就係因為咁行單線程),所以兩個都唔得。

剩返嗰條路係 emscripten 自己嘅 linear memory:`engine.rtenv.HEAP8.length`。
wasm 嘅 memory 只增不減,即係話佢正正就係「呢個 tab 問作業系統攞咗幾多」——
iOS 殺 tab 睇嘅就係呢個數。

呢個腳本唔係推論佢攞唔攞到,係喺真 Chromium 入面行真 build 問一次。

用法:  python tools/web_heap_probe.py [--dir docs] [--port 8792]
"""

import argparse
import http.server
import json
import pathlib
import socketserver
import sys
import threading
import time

PROJECT = pathlib.Path(__file__).resolve().parent.parent

## 同 Web.gd 將來要用嗰條 expression **一模一樣**。喺呢度改咗就要喺嗰邊改。
## 三層 fallback,而且一定要返一個 number(唔係 null),因為 GDScript 嗰邊
## 靠 0 嚟分「攞唔到」同「攞到但係零」。
HEAP_EXPR = """(function () {
  try {
    if (typeof engine !== 'undefined' && engine && engine.rtenv
        && engine.rtenv.HEAP8) { return engine.rtenv.HEAP8.length; }
  } catch (e) { /* fall through */ }
  try {
    if (window.performance && performance.memory
        && performance.memory.usedJSHeapSize) {
      return performance.memory.usedJSHeapSize;
    }
  } catch (e) { /* fall through */ }
  return 0;
})()"""


def serve(root: pathlib.Path, port: int):
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(root), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", port), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def run(args):
    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("需要 playwright:  pip install playwright && playwright install chromium")
        return 2

    root = PROJECT / args.dir
    if not (root / "index.html").exists():
        print("搵唔到 %s/index.html" % args.dir)
        return 2
    httpd = serve(root, args.port)
    url = "http://127.0.0.1:%d/index.html" % args.port
    fails = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(args=["--use-gl=swiftshader",
                                              "--enable-unsafe-swiftshader"])
            page = browser.new_page(viewport={"width": 540, "height": 960})
            errors = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.goto(url, wait_until="load")
            # 等引擎真係起身 —— rtenv 要 callMain 之後先存在。
            page.wait_for_timeout(12000)

            probe = page.evaluate("""() => ({
                hasEngine: typeof engine !== 'undefined',
                hasRtenv: typeof engine !== 'undefined' && !!(engine && engine.rtenv),
                hasHeap8: typeof engine !== 'undefined'
                    && !!(engine && engine.rtenv && engine.rtenv.HEAP8),
                hasPerfMemory: !!(window.performance && performance.memory),
                crossOriginIsolated: !!window.crossOriginIsolated,
            })""")
            print("--- 環境 ---")
            for k, v in probe.items():
                print("  %-20s %s" % (k, v))

            # 關鍵一步:`engine` 係 index.html 頂層嘅 `const`,即係一個
            # **lexical binding**,唔係 window 嘅 property。Godot 嘅
            # `JavaScriptBridge.eval(code, true)` 行嘅係 *indirect* eval
            # (global scope),而 window.__tfDpr 嗰條路證明唔到呢一種 ——
            # 佢係 property,property 一定見到。所以呢度照 Godot 嗰個做法
            # 行一次 indirect eval,問佢見唔見到個 const。
            indirect = page.evaluate("""() => {
                const geval = eval;
                try { return String(geval("typeof engine")); }
                catch (e) { return "THREW: " + e.message; }
            }""")
            indirect_heap = page.evaluate("""() => {
                const geval = eval;
                try { return geval(%s); } catch (e) { return "THREW: " + e.message; }
            }""" % json.dumps(HEAP_EXPR))
            print("  %-20s %s" % ("indirect eval sees", indirect))
            print("  %-20s %s" % ("indirect heap", indirect_heap))
            if indirect != "object":
                fails.append("indirect eval 見唔到 `engine`(%s)—— Godot 就係咁樣 eval,"
                             "即係 GDScript 嗰邊會攞唔到" % indirect)
            if not isinstance(indirect_heap, (int, float)) or not indirect_heap:
                fails.append("indirect eval 攞唔到 heap:%s" % indirect_heap)

            print("--- heap 採樣(同 Web.gd 將來用嗰條 expression) ---")
            samples = []
            for i in range(4):
                v = page.evaluate("() => " + HEAP_EXPR)
                samples.append(v)
                print("  t=%2ds  heap=%s bytes  (%.1f MB)"
                      % (i * 3, v, (v or 0) / 1048576.0))
                page.wait_for_timeout(3000)

            if not probe["hasHeap8"]:
                fails.append("engine.rtenv.HEAP8 攞唔到 —— 呢條路唔通,要換第二個做法")
            if not samples or not samples[0]:
                fails.append("expression 返 0/None —— 攞唔到 heap")
            elif samples[0] < 16 * 1048576:
                fails.append("heap 得 %.1f MB,細得唔合理(唔似係 wasm linear memory)"
                             % (samples[0] / 1048576.0))
            # ---------------------------------------------------------------
            # 全鏈路:GDScript 讀到 heap -> 寫入麵包屑 -> flush 落 user://。
            #
            # 上面量嘅係「條 JS expression 喺瀏覽器度返到數」。呢一段量嘅係
            # 「個遊戲真係攞到,而且真係寫低咗」—— 中間隔住 JavaScriptBridge、
            # Crash.mem_line() 同 IndexedDB,而每一段都斷得。
            #
            # user:// 喺網頁版係 IDBFS,即係一個 IndexedDB。marker 嘅路徑係
            # user://logs/session.open。
            marker = page.evaluate("""async () => {
                const dbs = await indexedDB.databases();
                for (const info of dbs) {
                    const db = await new Promise((res, rej) => {
                        const r = indexedDB.open(info.name);
                        r.onsuccess = () => res(r.result);
                        r.onerror = () => rej(r.error);
                    });
                    if (!db.objectStoreNames.contains('FILE_DATA')) { db.close(); continue; }
                    const store = db.transaction('FILE_DATA', 'readonly')
                        .objectStore('FILE_DATA');
                    const keys = await new Promise((res) => {
                        const r = store.getAllKeys();
                        r.onsuccess = () => res(r.result);
                        r.onerror = () => res([]);
                    });
                    const hit = keys.find((k) => String(k).indexOf('session.open') >= 0);
                    if (!hit) { db.close(); continue; }
                    const rec = await new Promise((res) => {
                        const r = store.get(hit);
                        r.onsuccess = () => res(r.result);
                        r.onerror = () => res(null);
                    });
                    db.close();
                    const bytes = rec && (rec.contents || rec);
                    if (!bytes) { continue; }
                    return { path: String(hit),
                             text: new TextDecoder().decode(new Uint8Array(bytes)) };
                }
                return null;
            }""")

            print("--- 全鏈路:遊戲自己寫低嘅麵包屑 ---")
            if not marker:
                fails.append("搵唔到 user://logs/session.open —— 遊戲冇 flush 過麵包屑")
            else:
                print("  marker: %s" % marker["path"])
                mem_lines = [ln.strip().strip('",')
                             for ln in marker["text"].splitlines()
                             if " mem " in ln]
                for ln in mem_lines[:4]:
                    print("    " + ln)
                if not mem_lines:
                    fails.append("marker 入面一條 mem 採樣都冇")
                else:
                    joined = "\\n".join(mem_lines)
                    if "static=" in joined:
                        fails.append("麵包屑仲印緊 static= —— 出街版嗰個數永遠係 0")
                    if "heap=" not in joined:
                        fails.append("麵包屑冇 heap=")
                    if "heap=n/a" in joined:
                        fails.append("遊戲攞唔到 heap(寫咗 n/a)—— JavaScriptBridge 嗰邊斷咗")

            if errors:
                print("--- page errors ---")
                for e in errors[:5]:
                    print("  " + e)
            browser.close()
    finally:
        httpd.shutdown()

    print()
    if fails:
        for f in fails:
            print("FAIL: " + f)
        return 1
    print("PASS: 真瀏覽器攞到 wasm heap,%.1f MB" % (samples[0] / 1048576.0))
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="docs")
    ap.add_argument("--port", type=int, default=8792)
    sys.exit(run(ap.parse_args()))
