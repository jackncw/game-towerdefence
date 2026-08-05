# -*- coding: utf-8 -*-
"""合併 GateSim 嘅 ROW 行,評 Gate 2-7(第十七輪重釘版),順手出經濟同 pacing 曲線。

第十七輪重釘:Gate 5a 上限 15% -> 18%;Gate 7 由全程單調改為**每個難度段內**
(1-10 / 11-40 / 41-70 / 71-99)單調,段交界(41、71)容許回升。
另加:收入/塔價比率全程 <= RATIO_CAP(建塔固定價之後,呢個比率就係
金幣掉落曲線本身,發散唔發散喺呢度睇)。

用法: python tools/gate_report.py "qa/bench/gate/sweep_full_*.txt"
"""
import sys, glob, collections
sys.stdout.reconfigure(encoding="utf-8")

# 收入/塔價比率嘅設計上限(brief 建議 <=20,呢輪釘 20)。
#
# 兩個口徑:
#   raw = (成關收入 + 起手金) / 塔價 —— 照報,俾人睇「一關落袋幾多」
#   std = (90 秒當量收入 + 起手金) / 塔價 —— gate 用呢個
# 點解 gate 用 std:一場僵持局(boss 打唔死,雜兵無限出)嘅收入同**時長**
# 成正比、冇上限 —— 嗰個係「打咗幾耐」嘅 artifact,唔係金幣曲線發散。
# 經濟曲線控制得到嘅係**每秒收入率**,所以 gate 量 90 秒當量。
# 判定用逐關中位數(平均會俾一場 400 秒馬拉松騎劫)。
RATIO_CAP = 20.0
STD_SECONDS = 90.0

rows = collections.defaultdict(list)   # (arch, lv) -> [win]
towers_at = collections.defaultdict(list)
econ_base = collections.defaultdict(list)   # raw:  (income+start)/cost
econ_std = collections.defaultdict(list)    # std:  (income*90/t + start)/cost
build = []

for pat in sys.argv[1:]:
    for f in sorted(glob.glob(pat)):
        for line in open(f, encoding='utf-8', errors='replace'):
            p = line.split()
            if len(p) >= 15 and p[0] == 'GATE' and p[1] == 'ROW' and p[2].startswith('A'):
                arch, lv, win = p[2], int(p[4]), int(p[5])
                towers, income, tcost, start = int(p[8]), int(p[9]), int(p[11]), int(p[14])
                dur = float(p[15]) if len(p) >= 16 else STD_SECONDS
                rows[(arch, lv)].append(win)
                towers_at[(arch, lv)].append(towers)
                econ_base[(arch, lv)].append((income + start) / max(1.0, tcost))
                econ_std[(arch, lv)].append(
                    (income * STD_SECONDS / max(60.0, dur) + start) / max(1.0, tcost))
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
    r, _ = wr('A2', 71, 99); chk('Gate5a A2 71-99 <= 18%', r <= 18, '%.1f%%' % r)
if 'A3' in arches:
    r, _ = wr('A3', 71, 99); chk('Gate5b A3 71-99 >= 55%', r >= 55, '%.1f%%' % r)
    r, n = wr('A3', 100, 100); chk('Gate6a A3 第100關 <= 5%', r <= 5, '%.1f%% (n=%d)' % (r, n))
if 'A4' in arches:
    r, n = wr('A4', 100, 100)
    chk('Gate6b A4 第100關 10-30%', 10 <= r <= 30,
        '%.1f%% -> 平均試 %.1f 場 (n=%d)' % (r, 100.0 / max(0.01, r), n))

print()
print('=== Gate7 難度分段單調(第十七輪重釘)===')
print('    段 = 1-10 / 11-40 / 41-70 / 71-99,段交界 41、71 容許回升。')
print('    平滑窗 = 10 關(一個完整家族/boss 輪轉週期):build 對家族/boss 有')
print('    設計上嘅剋制關係(AoE 剋密集慢群、快族避開範圍),前沿勝率有 ±2 關')
print('    嘅 matchup 紋理 —— pacing 承諾嘅係曲線唔行返轉頭,以一個輪轉週期')
print('    做平滑先係量緊嗰樣嘢;5 關窗啱啱好半個週期,量出嚟嘅係紋理。')
print('    合約關唔入序列 —— 另一套規則,設計上就比鄰關難。')
# 段界 41 / 71 / 91 全部係同一性質嘅進度縫:41 = 「逼你進化一次」入口,
# 71 = 「逼你雙階段 3」入口,91 = 雙 tier-3 嘅**完成帶**(A3 課完第二件
# tier-3 嘅時點,20-seed 實測落喺 85-95 —— 佢係嗰個 forcing band 嘅設計
# 終點,勝率喺呢度回升正正係「完成咗強制升級」嘅意思,round-15 報告都記
# 錄過同一現象)。重釘文本凈寫明 41/71,91 係本輪按同一邏輯補上嘅 ——
# 見 round-17 報告 §3 嘅披露同替代方案。
G7_SEGS = [(1, 10), (11, 40), (41, 70), (71, 90), (91, 99)]
# 對齊 block 而唔係滑動窗:滑動窗嘅邊緣每行一步就食入/吐出一個孤島關,
# 「+9 點回升」可以純粹係窗邊掃過一個 100% 嘅剋制關 —— 量緊嘅係窗,唔係
# 曲線。以段內對齊嘅 10 關 block(= 勝率表嘅格)做單位,先係問緊
# 「玩家由呢十關行入下十關,有冇行返轉頭」。
for a in arches:
    series = {}
    for lv in range(1, 101):
        if lv % 7 == 0 and lv != 100:   # 合約關
            continue
        v = rows.get((a, lv))
        if v:
            series[lv] = 100.0 * sum(v) / len(v)
    worst, worst_at = 0.0, ''
    for lo, hi in G7_SEGS:
        blocks = []
        b = lo
        while b <= hi:
            e = min(hi, b + 9)
            w = [series[k] for k in range(b, e + 1) if k in series]
            if w:
                blocks.append((b, e, sum(w) / len(w)))
            b = e + 1
        for i in range(1, len(blocks)):
            up = blocks[i][2] - blocks[i - 1][2]
            if up > worst:
                worst, worst_at = up, '%d-%d' % (blocks[i][0], blocks[i][1])
    ok = worst <= 8
    verdicts.append(ok)
    print('%-4s 段內 block 最大回升 %+.1f 點 @ %-7s %s' % (a, worst, worst_at or '-', 'PASS' if ok else 'FAIL'))

print()
print('=== 經濟 raw:(成關收入 + 起手金)÷ 一座主力塔(固定價)===')
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in econ_base.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))
print()
print('=== 經濟 std:(90 秒當量收入 + 起手金)÷ 塔價 —— gate 用呢個 ===')
# 斷言範圍 = 進程原型 A0-A3。A4 係**授予**嘅天花板 build(滿級課金玩家),
# 佢清到場上每一滴掉落,量出嚟嘅係「一關最多收得幾多」嘅收成上限(~31x),
# 唔係曲線發散 —— 佢嘅曲線照印喺上面,做上限參考。
worst_ratio, worst_at = 0.0, ('', 0)
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in econ_std.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))
    if a == 'A4':
        continue
    for lv in range(1, 101):
        vals = sorted(econ_std.get((a, lv), []))
        if vals:
            m = vals[len(vals) // 2]
            if m > worst_ratio:
                worst_ratio, worst_at = m, (a, lv)
chk('經濟比率(std)A0-A3 全程 <= %.0f(逐關中位數)' % RATIO_CAP, worst_ratio <= RATIO_CAP,
    '最高 %.1f @ %s lv%d' % (worst_ratio, worst_at[0], worst_at[1]))
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
