r"""Repoint mbedtls_platform_dev_random from /dev/random to /dev/urandom
inside libgodot_android.so, and verify that no unpatched reference survives.

點解要做呢件事
--------------
Godot 嘅 Android export template 入面嗰個 mbedtls 係 build 咗
`MBEDTLS_PLATFORM_STD_DEV_RANDOM` 嘅,即係話個 entropy source 開嘅係
**`/dev/random`** 而唔係 `/dev/urandom`。喺 Linux 5.6 之前嘅 kernel,
`/dev/random` 係一個**會阻塞**嘅裝置:entropy pool 唔夠就吊喺 `read()`
度唔返。

Godot 引擎啟動嗰陣(`Main::setup()` 入面)會 seed 一次 CTR-DRBG。喺一部
kernel 4.x 嘅機上面,如果嗰刻 entropy pool 得幾十 bit,呢個 read 就會
**永遠**返唔到 —— 個 app 卡死喺 Android splash,**冇 crash、冇 ANR、
logcat 一句 error 都冇**。實測(第 25 輪,HUAWEI STK-L22 / Android 10 /
kernel 4.14.116):最後一句 log 係 `Setting up native layer with params`,
之後成個 process 就靜咗,行幾多次都一樣。

呢個修補改一個 relocation 嘅 addend,令個 pointer 指去 `/dev/urandom`
—— 同一個 CSPRNG,一開機 CRNG init 完就唔會再阻塞。

邊個檔要 patch
--------------
**唔係 export template 嘅 apk。** `export_presets.cfg` 開咗
`gradle_build/use_gradle_build=true`,而 gradle build 攞 native lib 嘅地方係
`android/build/libs/{debug,release}/godot-lib.template_*.aar`,唔係
`%APPDATA%\Godot\export_templates\...\android_release.apk`。第 22 輪就係
因為淨係 patch 咗後者,個修補完全冇入到出貨嘅 build。

Strategy
--------
 1. Find file offsets of the NUL-terminated strings "/dev/random" and
    "/dev/urandom"; map them to virtual addresses via PT_LOAD segments.
 2. Find every reference to vaddr("/dev/random"):
    a. RELA relocations (e.g. R_AARCH64_RELATIVE) whose addend == vaddr
    b. raw pointer-sized little-endian words in the file equal to vaddr
       (covers RELR / ARM32 REL relocations, whose addend is stored in place)
 3. Rewrite them to vaddr("/dev/urandom").

Usage
-----
    python patch_entropy.py <file> [--verify] [--quiet]

`<file>` 收 `.so`(原地改)、或者 `.aar` / `.apk` / `.aab`(入面每一個
`libgodot_android.so` 都會 patch,個 archive 會重新寫過)。

`--verify` = 唔改嘢,淨係檢查。仲有未 patch 嘅 reference 就 exit 1。
出貨 script (`tools\android_build.ps1`) 兩邊都用:export 之前 patch 個 aar,
export 之後 `--verify` 個 aab / apk。
"""

import io
import os
import struct
import sys
import zipfile

from elftools.elf.elffile import ELFFile

# Windows 嘅 console 預設係 cp950,呢個檔啲訊息係中文。唔 reconfigure 就會喺
# 印錯誤訊息嗰一刻 UnicodeEncodeError —— 即係話「修補甩咗」呢個警告本身會
# 變成一個睇唔明嘅 traceback。
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except Exception:
        pass

SO_NAME = "libgodot_android.so"
ARCHIVE_SUFFIXES = (".aar", ".apk", ".aab", ".zip")


def _find_string(blob, s):
    """Return offsets of exact NUL-terminated string (preceded by NUL)."""
    hits = []
    start = 0
    needle = s + b"\x00"
    while True:
        i = blob.find(needle, start)
        if i < 0:
            break
        if i == 0 or blob[i - 1] == 0:
            hits.append(i)
        start = i + 1
    return hits


def patch_so(data, verify=False, log=print, label=""):
    """Patch (or, with verify=True, just count) /dev/random references.

    `data` is a bytearray. Returns the number of references found; when
    verify is False they have been rewritten in place.
    """
    elf = ELFFile(io.BytesIO(bytes(data)))
    ptr = 8 if elf.elfclass == 64 else 4
    segs = [
        (s["p_offset"], s["p_filesz"], s["p_vaddr"])
        for s in elf.iter_segments()
        if s["p_type"] == "PT_LOAD"
    ]

    def off2va(off):
        for o, fsz, va in segs:
            if o <= off < o + fsz:
                return va + (off - o)
        return None

    rnd_offs = _find_string(data, b"/dev/random")
    urnd_offs = _find_string(data, b"/dev/urandom")
    if not rnd_offs or not urnd_offs:
        # 冇 "/dev/random" 呢個字串本身就係一個乾淨嘅狀態(例如 Godot 將來
        # 改咗 build flag)。冇 "/dev/urandom" 就冇嘢可以指過去,要出聲。
        if not urnd_offs:
            raise SystemExit("%s: 搵唔到 /dev/urandom 字串,唔敢改" % label)
        log("%s  冇 /dev/random 字串 —— 唔使 patch" % label)
        return 0

    rnd_va = off2va(rnd_offs[0])
    urnd_va = off2va(urnd_offs[0])
    if rnd_va is None or urnd_va is None:
        raise SystemExit("%s: 字串唔喺任何 PT_LOAD segment 入面" % label)

    hits = []

    # a) RELA relocations with matching addend
    for secname in (".rela.dyn", ".rela.plt"):
        sec = elf.get_section_by_name(secname)
        if sec is None:
            continue
        ent = sec["sh_entsize"]
        base = sec["sh_offset"]
        for i in range(sec.num_relocations()):
            r = sec.get_relocation(i)
            if r.entry.get("r_addend") == rnd_va:
                # r_offset + r_info, then addend
                hits.append(("RELA " + secname, base + i * ent + 2 * ptr))

    # b) raw in-place pointer words (RELR / ARM32 REL style)
    needle = struct.pack("<Q" if ptr == 8 else "<I", rnd_va)
    start = 0
    while True:
        i = data.find(needle, start)
        if i < 0:
            break
        hits.append(("raw pointer", i))
        start = i + ptr

    # 一條 RELA 嘅 addend 本身就係一個 pointer-sized word,所以上面 (a) 同 (b)
    # 會喺同一個 offset 各中一次。唔 dedupe 就會報「2 個 reference」,而下面
    # `--verify` 嘅數字係要俾人信嘅。
    seen = {}
    for kind, off in hits:
        seen.setdefault(off, kind)

    for off, kind in sorted(seen.items()):
        log("%s  %s @file 0x%x" % (label, kind, off))
        if not verify:
            struct.pack_into("<Q" if ptr == 8 else "<I", data, off, urnd_va)

    return len(seen)


def _run_file(path, verify, quiet):
    log = (lambda *a: None) if quiet else print
    total = 0

    if path.lower().endswith(ARCHIVE_SUFFIXES):
        zin = zipfile.ZipFile(path)
        members = [n for n in zin.namelist() if n.endswith("/" + SO_NAME)]
        if not members:
            raise SystemExit("%s: 入面搵唔到任何 %s" % (path, SO_NAME))
        patched = {}
        for n in members:
            data = bytearray(zin.read(n))
            found = patch_so(data, verify=verify, log=log, label="  [%s]" % n)
            total += found
            if found and not verify:
                patched[n] = bytes(data)
        if patched:
            tmp = path + ".tmp"
            zout = zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED)
            for info in zin.infolist():
                blob = patched.get(info.filename)
                if blob is None:
                    blob = zin.read(info.filename)
                # 保住原本嘅 compress_type:.apk 入面啲 .so 通常係 STORED
                # (extractNativeLibs=false 要求),重新壓縮會令部機載入唔到。
                ni = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                ni.compress_type = info.compress_type
                ni.external_attr = info.external_attr
                ni.internal_attr = info.internal_attr
                ni.create_system = info.create_system
                zout.writestr(ni, blob)
            zout.close()
            zin.close()
            os.replace(tmp, path)
            log("重寫咗 %s(%d 個 %s)" % (path, len(patched), SO_NAME))
        else:
            zin.close()
    else:
        data = bytearray(open(path, "rb").read())
        total = patch_so(data, verify=verify, log=log, label="  [%s]" % os.path.basename(path))
        if total and not verify:
            open(path, "wb").write(bytes(data))
            log("寫返 %s" % path)

    return total


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    flags = {a for a in argv[1:] if a.startswith("--")}
    if len(args) != 1:
        raise SystemExit(__doc__)
    verify = "--verify" in flags
    quiet = "--quiet" in flags
    path = args[0]

    total = _run_file(path, verify, quiet)

    if verify:
        if total:
            print(
                "ENTROPY 修補甩咗:%s 入面仲有 %d 個 /dev/random reference。\n"
                "  呢個 build 喺 kernel < 5.6 嘅機上面會卡死喺 splash。\n"
                "  行 `python tools\\android_template_fix\\patch_entropy.py "
                "<aar>` 再 export。" % (path, total)
            )
            return 1
        if not quiet:
            print("entropy ok:%s 冇 /dev/random reference" % path)
        return 0

    if not quiet:
        print("total patched:", total)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
