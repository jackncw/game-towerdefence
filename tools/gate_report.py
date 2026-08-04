# -*- coding: utf-8 -*-
"""合併 GateSim 嘅 ROW 行,評 Gate 2-7,順手出經濟同 pacing 曲線。

用法: python tools/gate_report.py "qa/bench/gate/sweep_full_*.txt"
"""
import sys, glob, collections
sys.stdout.reconfigure(encoding="utf-8")

BUILD_COST_STEP = 1.03   # 同 GameData.BUILD_COST_STEP

rows = collections.defaultdict(list)   # (arch, lv) -> [win]
towers_at = collections.defaultdict(list)
econ_base = collections.defaultdict(list)
econ_marg = collections.defaultdict(list)
build = []

for pat in sys.argv[1:]:
    for f in sorted(glob.glob(pat)):
        for line in open(f, encoding='utf-8', errors='replace'):
            p = line.split()
            if len(p) >= 15 and p[0] == 'GATE' and p[1] == 'ROW' and p[2].startswith('A'):
                arch, lv, win = p[2], int(p[4]), int(p[5])
                towers, income, tcost, start = int(p[8]), int(p[9]), int(p[11]), int(p[14])
                rows[(arch, lv)].append(win)
                towers_at[(arch, lv)].append(towers)
                total = income + start
                econ_base[(arch, lv)].append(total / max(1.0, tcost))
                econ_marg[(arch, lv)].append(
                    total / max(1.0, tcost * (BUILD_COST_STEP ** towers)))
            elif len(p) >= 4 and p[1] == 'BUILD':
                build.append(line.strip())

BANDS = [(1,10),(11,20),(21,30),(31,40),(41,50),(51,60),(61,70),(71,80),(81,90),(91,99),(100,100)]
ECON_BANDS = [(1,10),(11,30),(31,50),(51,70),(71,90),(91,100)]
arches = sorted({a for a, _ in rows})


def wr(a, lo, hi):
    w = [x for lv in range(lo, hi + 1) for x in rows.get((a, lv), [])]
    return (100.0 * sum(w) / len(w)) if w else float('nan'), len(w)


print('=== 勝率表(%: 該區間全部關卡 x 全部 seed)===')
print('原型 ' + ''.join(('%d-%d' % b).rjust(9) for b in BANDS))
for a in arches:
    cells = []
    for lo, hi in BANDS:
        r, n = wr(a, lo, hi)
        cells.append(('-' if n == 0 else '%.0f' % r).rjust(9))
    print('%-4s ' % a + ''.join(cells))
if arches:
    print('(每格樣本 = 關數 x seed 數;1-10 格 = %d)' % wr(arches[0], 1, 10)[1])

print()
print('=== Gate 判定 ===')
verdicts = []


def chk(name, ok, detail):
    verdicts.append(ok)
    print('%-42s %s  %s' % (name, 'PASS' if ok else 'FAIL', detail))


if 'A0' in arches:
    r, _ = wr('A0', 1, 10); chk('Gate2a A0 1-10 >= 70%', r >= 70, '%.1f%%' % r)
if 'A1' in arches:
    r, _ = wr('A1', 1, 10); chk('Gate2b A1 1-10 >= 95%', r >= 95, '%.1f%%' % r)
    bad = [lv for lv in range(11, 41) if rows.get(('A1', lv)) and
           100.0 * sum(rows[('A1', lv)]) / len(rows[('A1', lv)]) < 60]
    r, _ = wr('A1', 11, 40)
    chk('Gate3a A1 11-40 逐關 >= 60%', not bad, '平均 %.1f%%,唔達標: %s' % (r, bad or '無'))
    r, _ = wr('A1', 41, 70); chk('Gate4a A1 41-70 <= 20%', r <= 20, '%.1f%%' % r)
if 'A2' in arches:
    r, _ = wr('A2', 41, 70); chk('Gate4b A2 41-70 >= 60%', r >= 60, '%.1f%%' % r)
    r, _ = wr('A2', 71, 99); chk('Gate5a A2 71-99 <= 15%', r <= 15, '%.1f%%' % r)
if 'A3' in arches:
    r, _ = wr('A3', 71, 99); chk('Gate5b A3 71-99 >= 55%', r >= 55, '%.1f%%' % r)
    r, n = wr('A3', 100, 100); chk('Gate6a A3 第100關 <= 5%', r <= 5, '%.1f%% (n=%d)' % (r, n))
if 'A4' in arches:
    r, n = wr('A4', 100, 100)
    chk('Gate6b A4 第100關 10-30%', 10 <= r <= 30,
        '%.1f%% -> 平均試 %.1f 場 (n=%d)' % (r, 100.0 / max(0.01, r), n))

print()
print('=== Gate7 難度單調(5 關移動平均,回升 > 8 點 = FAIL)===')
for a in arches:
    series = []
    for lv in range(1, 101):
        v = rows.get((a, lv))
        series.append(100.0 * sum(v) / len(v) if v else None)
    ma = []
    for i in range(len(series)):
        w = [x for x in series[max(0, i - 2):i + 3] if x is not None]
        ma.append(sum(w) / len(w) if w else None)
    worst, worst_lv = 0.0, 0
    for i in range(1, len(ma)):
        if ma[i] is None or ma[i - 1] is None:
            continue
        up = ma[i] - ma[i - 1]
        if up > worst:
            worst, worst_lv = up, i + 1
    ok = worst <= 8
    verdicts.append(ok)
    print('%-4s 最大回升 %+.1f 點 @ lv%-3d  %s' % (a, worst, worst_lv, 'PASS' if ok else 'FAIL'))

print()
print('=== 經濟 A:全場總金 ÷ 第一座主力塔(呢關嘅金鋪得起幾多座)===')
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in econ_base.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))
print()
print('=== 經濟 B:全場總金 ÷ 場末「再起一座」嘅價(遞增成本)===')
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in econ_marg.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))
print()
print('=== 平均塔數 ===')
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in towers_at.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))

print()
print('=== pacing:每十關嘅 build 狀態(seed 0)===')
for b in build:
    p = b.split()
    if len(p) > 3 and p[3] == '0':
        print(b)

print()
print('總判定: %s (%d/%d)' % ('ALL PASS' if all(verdicts) else 'HAS FAIL',
                              sum(1 for v in verdicts if v), len(verdicts)))
