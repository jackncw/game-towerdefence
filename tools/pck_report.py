"""列出一個 Godot .pck 入面每個檔案嘅大細,按頂層資料夾滙總。

點解要有:web export 嘅 exclude_filter 係一條「寫咗就當佢生效」嘅設定 —— 冇人
睇得到佢實際隔走咗乜。第十一輪就係喺呢度發現 test/ 57 個檔、tools/ 17 個檔同
一張 godot_setting.jpg 一路都跟住出街。呢個腳本令「pack 入面有乜」變成一個
量得到嘅數,而唔係一個假設。

用法:  python tools/pck_report.py docs/index.pck [--top 20]
"""
import struct
import sys
from collections import defaultdict

MAGIC = 0x43504447  # "GDPC"


def read_pck(path):
    with open(path, "rb") as f:
        data = f.read()
    off = 0
    magic = struct.unpack_from("<I", data, off)[0]
    if magic != MAGIC:
        # PCK embedded at the end of an executable: the magic is repeated at EOF-4
        tail = struct.unpack_from("<I", data, len(data) - 4)[0]
        if tail != MAGIC:
            raise SystemExit("%s 唔係一個 Godot pck" % path)
        raise SystemExit("embedded pck 未支援")
    off += 4
    ver, vmaj, vmin, vpatch = struct.unpack_from("<4I", data, off)
    off += 16
    flags = 0
    if ver >= 2:
        flags = struct.unpack_from("<I", data, off)[0]
        off += 4
        off += 8  # files_base
    if ver >= 4:
        # 4.7 移咗個目錄去 pack 尾,header 第 32 byte 記住佢喺邊。
        off = struct.unpack_from("<Q", data, 32)[0]
    else:
        off += 16 * 4  # reserved
    count = struct.unpack_from("<I", data, off)[0]
    off += 4
    files = []
    for _ in range(count):
        (plen,) = struct.unpack_from("<I", data, off)
        off += 4
        raw = data[off:off + plen]
        off += plen
        name = raw.rstrip(b"\0").decode("utf-8", "replace")
        _fofs, size = struct.unpack_from("<QQ", data, off)
        off += 16
        off += 16  # md5
        if ver >= 2:
            off += 4  # per-file flags
        files.append((name, size))
    return ver, flags, files


## `.godot/exported/<hash>/export-<md5>-<原檔名>.scn` —— 匯出時 remap 過嘅場景。
## 用尾巴嗰個原檔名分組,唔係嘅話全部場景會堆晒喺 ".godot/exported" 一格,
## 而「test/ 嘅場景有冇出街」正正就係要問嘅問題。
def regroup(name):
    parts = name.replace("res://", "").split("/")
    if parts[0] == ".godot" and len(parts) > 1 and parts[1] == "exported":
        stem = parts[-1]
        if stem.startswith("export-") and "-" in stem[7:]:
            return "exported:" + stem[7:].split("-", 1)[1]
        return "exported:" + stem
    if len(parts) > 1:
        return parts[0] if parts[0] != ".godot" else ".godot/" + parts[1]
    return "(root)"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    top = 20
    for a in sys.argv[1:]:
        if a.startswith("--top="):
            top = int(a.split("=", 1)[1])
    if not args:
        raise SystemExit(__doc__)
    path = args[0]
    ver, flags, files = read_pck(path)
    total = sum(s for _, s in files)
    print("PCK %s  version=%d  files=%d  payload=%.1f KB" %
          (path, ver, len(files), total / 1024.0))
    groups = defaultdict(lambda: [0, 0])
    for name, size in files:
        key = regroup(name)
        groups[key][0] += 1
        groups[key][1] += size
    print("\n%-28s %6s %12s" % ("group", "files", "KB"))
    for key in sorted(groups, key=lambda k: -groups[k][1]):
        n, sz = groups[key]
        print("%-28s %6d %12.1f" % (key, n, sz / 1024.0))
    print("\ntop %d files:" % top)
    for name, size in sorted(files, key=lambda x: -x[1])[:top]:
        print("  %10.1f KB  %s" % (size / 1024.0, name))


if __name__ == "__main__":
    main()
