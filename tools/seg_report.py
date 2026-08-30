# -*- coding: utf-8 -*-
"""分段勝率對照:一組 sweep-mode campaign 讀數 vs 一組對照。

第 24 輪 Part E 用嘅。校準一個「拖延稅」呢類掣,要睇嘅唔係一個數字係
Gate 5a,而係**成條曲線邊一段郁咗** —— 一個令 A2 71-99 跌到 12% 但同時
令 A3 71-99 跌穿 40% 嘅配置係一個失敗,而兩個數要並排先睇得出。

一個 pattern = 一組。pattern 入面用 `名=glob` 指定組名。

用法:
  python tools/seg_report.py "對照=qa/bench/gate/r24_ab/new_A*.txt" \\
                             "斜坡3.0/90=qa/sweeps/out/partE1/e1_*_r30_90_*.txt"
"""
import sys, glob, collections

sys.stdout.reconfigure(encoding="utf-8")

BANDS = [(1, 10), (11, 40), (41, 70), (71, 80), (81, 90), (91, 99), (71, 99)]
CONTRACT_EVERY = 7


def load(pattern):
    """(arch, lv) -> [win]; 再加 (arch, seed, lv) -> win 做成對比較。"""
    per = collections.defaultdict(list)
    cell = {}
    for f in sorted(glob.glob(pattern)):
        if f.endswith(".err.txt"):
            continue
        for line in open(f, encoding="utf-8", errors="replace"):
            p = line.split()
            if len(p) < 15 or p[0] != "GATE" or p[1] != "ROW" or not p[2].startswith("A"):
                continue
            arch, sd, lv, win = p[2], int(p[3]), int(p[4]), int(p[5])
            per[(arch, lv)].append(win)
            cell[(arch, sd, lv)] = win
    return per, cell


groups = []
for spec in sys.argv[1:]:
    name, _, pat = spec.partition("=")
    per, cell = load(pat)
    groups.append((name, per, cell, pat))

if not groups:
    print("要至少一組")
    sys.exit(2)

arches = sorted({a for _, per, _, _ in groups for a, _ in per})


def wr(per, arch, lo, hi):
    w = [x for lv in range(lo, hi + 1) for x in per.get((arch, lv), [])]
    return (100.0 * sum(w) / len(w), len(w)) if w else (float("nan"), 0)


print("=== 分段勝率 ===")
head = "%-4s %-8s" % ("原型", "區間") + "".join(("%14s" % g[0]) for g in groups)
print(head)
for arch in arches:
    for lo, hi in BANDS:
        cells = []
        any_n = 0
        for _, per, _, _ in groups:
            r, n = wr(per, arch, lo, hi)
            any_n = max(any_n, n)
            cells.append("           -" if n == 0 else "%13.1f%%" % r)
        if any_n == 0:
            continue
        print("%-4s %-8s" % (arch, "%d-%d" % (lo, hi)) + "".join(cells) + "   n=%d" % any_n)
    print()

print("=== Gate 判定(本輪相關嗰幾條)===")
for name, per, _, _ in groups:
    out = []
    for label, arch, lo, hi, lo_ok, hi_ok in [
            ("4b A2 41-70 >=30%", "A2", 41, 70, 30, 101),
            ("5a A2 71-99 <=12%", "A2", 71, 99, -1, 12),
            ("5b A3 71-99 >=28%", "A3", 71, 99, 28, 101),
            ("(本輪目標)A3 71-99 >=40%", "A3", 71, 99, 40, 101)]:
        r, n = wr(per, arch, lo, hi)
        if n == 0:
            continue
        ok = lo_ok <= r <= hi_ok
        out.append("%s %s (%.1f%%, n=%d)" % (label, "PASS" if ok else "FAIL", r, n))
    print("  [%s] %s" % (name, " | ".join(out) if out else "冇樣本"))

# ── 成對比較:同一個 seed 同一關,邊幾關由贏變輸 ──────────────────────
if len(groups) >= 2:
    base_name, _, base_cell, _ = groups[0]
    print()
    print("=== 成對翻轉(對照 = %s)===" % base_name)
    for name, _, cell, _ in groups[1:]:
        common = sorted(set(base_cell) & set(cell))
        flips = collections.Counter()
        w2l = l2w = 0
        for k in common:
            if base_cell[k] == cell[k]:
                continue
            if base_cell[k] == 1:
                w2l += 1
                flips[(k[0], k[2])] -= 1
            else:
                l2w += 1
                flips[(k[0], k[2])] += 1
        print("  [%s] 共同樣本 %d,贏->輸 %d,輸->贏 %d" % (name, len(common), w2l, l2w))
        late = [(lv, -v) for (a, lv), v in flips.items() if a == "A2" and 71 <= lv <= 99 and v < 0]
        if late:
            late.sort()
            print("      A2 71-99 由贏變輸嘅關: "
                  + ", ".join("lv%d x%d" % (lv, c) for lv, c in late))

# ── 逐關(71-99)——「孤島」係咪真係冧咗 ────────────────────────────
print()
print("=== A2 71-99 逐關勝率 ===")
print("%-5s" % "關" + "".join(("%14s" % g[0]) for g in groups))
for lv in range(71, 100):
    if lv % CONTRACT_EVERY == 0:
        continue
    cells = []
    show = False
    for _, per, _, _ in groups:
        v = per.get(("A2", lv), [])
        if not v:
            cells.append("           -")
            continue
        r = 100.0 * sum(v) / len(v)
        if r > 0:
            show = True
        cells.append("%13.0f%%" % r)
    if show:
        print("%-5d" % lv + "".join(cells))
