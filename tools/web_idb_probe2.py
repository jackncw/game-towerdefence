#!/usr/bin/env python3
"""診斷 2:注入 -> 讀返 -> boot -> 再讀,睇 save.json 喺邊一步走樣。"""
import http.server
import json
import pathlib
import socketserver
import sys
import threading

PROJECT = pathlib.Path(__file__).resolve().parent.parent
APP_DIR = "/userfs/godot/app_userdata/塔防要塞 Tower Fortress"

sys.path.insert(0, str(PROJECT / "tools"))
from web_r17_verify import INJECT_JS, strong_save  # noqa: E402

READ_JS = """async (filePath) => {
  return await new Promise((resolve) => {
    const req = indexedDB.open('/userfs', 21);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains('FILE_DATA'))
        db.createObjectStore('FILE_DATA');
    };
    req.onsuccess = (e) => {
      const db = e.target.result;
      const tx = db.transaction('FILE_DATA', 'readonly');
      const r = tx.objectStore('FILE_DATA').get(filePath);
      r.onsuccess = () => {
        const v = r.result;
        if (!v) { db.close(); resolve('MISSING'); return; }
        const txt = v.contents ? new TextDecoder().decode(v.contents) : '(no contents)';
        db.close();
        resolve('mode=' + v.mode + ' len=' + txt.length + ' head=' + txt.slice(0, 120));
      };
      r.onerror = () => { db.close(); resolve('ERR'); };
    };
  });
}"""


def main():
    from playwright.sync_api import sync_playwright
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(PROJECT / "docs"), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", 8803), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    url = "http://127.0.0.1:8803/index.html"
    with sync_playwright() as p:
        br = p.chromium.launch(args=["--use-gl=angle"])
        page = br.new_page(viewport={"width": 540, "height": 960})
        page.on("console", lambda m: None)
        page.goto(url.replace("index.html", "__blank__"))
        dirs = ["/userfs/godot", "/userfs/godot/app_userdata", APP_DIR]
        print("inject:", page.evaluate(
            INJECT_JS, [dirs, APP_DIR + "/save.json",
                        json.dumps(strong_save("zh_TW"))]))
        print("read-back (pre-boot):",
              page.evaluate(READ_JS, APP_DIR + "/save.json"))
        page.goto(url)
        page.wait_for_timeout(16000)
        page.screenshot(path=str(PROJECT / "qa/screenshots/round-17-web/_probe_menu.png"))
        print("read-back (post-boot):",
              page.evaluate(READ_JS, APP_DIR + "/save.json"))
        br.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
