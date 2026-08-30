# -*- coding: utf-8 -*-
"""總結一次 `--mode=final` 嘅 sweep(第 24 輪 Part D 校準用)。

讀 tools/sweep.ps1 出嘅一堆檔,每個檔一個配置,印一張
「配置 x 原型 -> 勝率 / 掛死 / 平均用時 / 平均打死幾多隻 boss」嘅表。

**掛死唔係輸。** 一場打到 ATTEMPT_TIMEOUT 都冇結算過嘅 run 係一個無效樣本
(第 23 輪就係俾呢個瞞咗成輪),所以掛死喺呢度獨立一欄,而且有掛死嘅配置
會被標出嚟 —— 佢嘅勝率唔可以攞去比較。

用法:
  python tools/sweep_report.py "qa/sweeps/out/partD1/d1_*.txt"
"""
import sys, glob, os, re, collections

sys.stdout.reconfigure(encoding="utf-8")

rows = collections.OrderedDict()   # unit -> dict
for pat in sys.argv[1:]:
    for f in sorted(glob.glob(pat)):
        if f.endswith(".err.txt"):
            continue
        unit = os.path.basename(f)[:-4]
        wins = hangs = n = 0
        times, fbd = [], []
        arch = "?"
        override = []
        for line in open(f, encoding="utf-8", errors="replace"):
            if line.startswith("GAMEDATA OVERRIDE"):
                override.append(line.split(None, 2)[2].strip())
                continue
            p = line.split()
            if p[:2] != ["GATE", "ROW"] or len(p) < 7:
                continue
            arch = p[2]
            n += 1
            wins += int(p[4])
            hangs += int(p[6]) if len(p) >= 7 else 0
            if len(p) >= 8:
                fbd.append(int(p[7]))
            if len(p) >= 9:
                times.append(float(p[8]))
        if n == 0:
            rows[unit] = None
            continue
        rows[unit] = {
            "arch": arch, "n": n, "wins": wins, "hangs": hangs,
            "wr": 100.0 * wins / n,
            "time": sum(times) / len(times) if times else float("nan"),
            "fbd": sum(fbd) / len(fbd) if fbd else float("nan"),
            "cfg": " ".join(override),
        }

print("%-22s %-4s %6s %6s %6s %8s %6s  %s"
      % ("單位", "原型", "n", "勝", "勝率", "平均秒", "殺boss", "override"))
for unit, r in rows.items():
    if r is None:
        print("%-22s  —— 冇 ROW 行(未跑完 / 死咗喺半路)" % unit)
        continue
    flag = "  !!掛死 %d" % r["hangs"] if r["hangs"] else ""
    print("%-22s %-4s %6d %6d %5.1f%% %8.1f %6.1f  %s%s"
          % (unit, r["arch"], r["n"], r["wins"], r["wr"], r["time"], r["fbd"],
             r["cfg"], flag))

print()
print("Gate 6a = A3 第100關 <= 5%%;Gate 6b = A4 第100關 10-30%%(平均試 3.3-10 場)")
for unit, r in rows.items():
    if r is None or r["hangs"]:
        continue
    if r["arch"] == "A3":
        print("  %-22s 6a %s (%.1f%%)" % (unit, "PASS" if r["wr"] <= 5 else "FAIL", r["wr"]))
    elif r["arch"] == "A4":
        att = 100.0 / r["wr"] if r["wr"] > 0 else float("inf")
        print("  %-22s 6b %s (%.1f%% -> 平均試 %.1f 場)"
              % (unit, "PASS" if 10 <= r["wr"] <= 30 else "FAIL", r["wr"], att))
