#!/usr/bin/env python3
"""診斷:開一次 web build,dump IndexedDB 嘅 database 名 + key + 條目形狀。"""
import http.server
import json
import pathlib
import socketserver
import sys
import threading

PROJECT = pathlib.Path(__file__).resolve().parent.parent

DUMP_JS = """async () => {
  const dbs = await indexedDB.databases();
  const out = {databases: dbs};
  for (const d of dbs) {
    try {
      const db = await new Promise((res, rej) => {
        const r = indexedDB.open(d.name);
        r.onsuccess = () => res(r.result);
        r.onerror = () => rej(r.error);
      });
      out[d.name] = {version: db.version, stores: [...db.objectStoreNames]};
      for (const s of db.objectStoreNames) {
        const keys = await new Promise((res, rej) => {
          const tx = db.transaction(s, 'readonly');
          const r = tx.objectStore(s).getAllKeys();
          r.onsuccess = () => res(r.result);
          r.onerror = () => rej(r.error);
        });
        out[d.name]['keys_' + s] = keys.slice(0, 40);
        if (keys.length) {
          const v = await new Promise((res, rej) => {
            const tx = db.transaction(s, 'readonly');
            const r = tx.objectStore(s).get(keys[keys.length - 1]);
            r.onsuccess = () => res(r.result);
            r.onerror = () => rej(r.error);
          });
          out[d.name]['sample'] = {key: keys[keys.length - 1],
            fields: v ? Object.keys(v) : null,
            mode: v ? v.mode : null,
            type: v && v.contents ? v.contents.constructor.name : null};
        }
      }
      db.close();
    } catch (e) { out[d.name] = 'err: ' + e; }
  }
  return JSON.stringify(out, null, 1);
}"""


def main():
    from playwright.sync_api import sync_playwright
    handler = lambda *a, **kw: http.server.SimpleHTTPRequestHandler(
        *a, directory=str(PROJECT / "docs"), **kw)
    httpd = socketserver.TCPServer(("127.0.0.1", 8799), handler)
    httpd.allow_reuse_address = True
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    with sync_playwright() as p:
        br = p.chromium.launch(args=["--use-gl=angle"])
        page = br.new_page(viewport={"width": 540, "height": 960})
        page.goto("http://127.0.0.1:8799/index.html")
        page.wait_for_timeout(16000)
        print(page.evaluate(DUMP_JS))
        br.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
