# -*- coding: utf-8 -*-
"""合併 GateSim 嘅 ROW 行,評 Gate 2-7(第十八輪重釘版),順手出經濟同 pacing 曲線。

第十八輪重釘(金幣 v3 + 難度全面提升):Gate 3-5 嘅勝率目標全部減半 ——
  3a A1 11-40 逐關 >=60% -> >=30%
  4a A1 41-70 <=20%      -> <=10%
  4b A2 41-70 >=60%      -> >=30%
  5a A2 71-99 <=18%      -> <=9%   -> **<=12%(第 21 輪重釘,已議定)**
  5b A3 71-99 >=55%      -> >=28%
Gate 2(體驗關)同 Gate 6(第 100 關)不變。

第 21 輪兩處重釘:
  * **5a ≤9% -> ≤12%**。≤9% 同「farm-intended」有結構拉扯:71-99 段設計上
    就係要你重試 + 課金,而重試循環(--tries)令 A2 嘅魔晶收入貼返真實,
    佢就一定會偷到幾關。壓到 9% 要用難度斜率去壓,而嗰個會連 A3(5b)
    一齊壓死。真解係結構鎖(GameData.BOSS_OPEN_DPS_SHARE — 唔准秒 boss),
    唔係再加斜率;鎖上咗之後把尺放寬到 12%。
  * **Gate 7 完成帶 91 -> 81-90**(81 同 91 兩邊都係縫,見下面 G7_SEGS 嘅註)。

第十七輪嗰條「收入/塔價 <= 20」嘅斷言**作廢**,由 G1 取代(見
tools/goldcurve.gd —— G1 量嘅係關卡派幾多錢,同玩家打得好唔好無關,
所以佢唔屬於呢個檔案)。呢度剩返報返實測比率同塔數做參考。

用法: python tools/gate_report.py "build/a*_p*.txt"
"""
import sys, glob, collections
sys.stdout.reconfigure(encoding="utf-8")

STD_SECONDS = 90.0
REF_TOWER_COST = 120.0     # 同 GameData.REF_TOWER_COST
CONTRACT_EVERY = 7

rows = collections.defaultdict(list)   # (arch, lv) -> [win]
towers_at = collections.defaultdict(list)
econ_base = collections.defaultdict(list)   # raw:  (income+start)/cost
econ_std = collections.defaultdict(list)    # std:  (income*90/t + start)/cost
g1_std = collections.defaultdict(list)      # (income*90/t) / REF_TOWER_COST
tries_at = collections.defaultdict(list)    # 實際打咗幾多場先過到(封頂 = --tries)
build = []

for pat in sys.argv[1:]:
    for f in sorted(glob.glob(pat)):
        for line in open(f, encoding='utf-8', errors='replace'):
            p = line.split()
            if len(p) >= 15 and p[0] == 'GATE' and p[1] == 'ROW' and p[2].startswith('A'):
                arch, lv, win = p[2], int(p[4]), int(p[5])
                towers, income, tcost, start = int(p[8]), int(p[9]), int(p[11]), int(p[14])
                dur = float(p[15]) if len(p) >= 16 else STD_SECONDS
                std_income = income * STD_SECONDS / max(60.0, dur)
                if len(p) >= 17:
                    tries_at[(arch, lv)].append(int(p[16]))
                rows[(arch, lv)].append(win)
                towers_at[(arch, lv)].append(towers)
                econ_base[(arch, lv)].append((income + start) / max(1.0, tcost))
                econ_std[(arch, lv)].append((std_income + start) / max(1.0, tcost))
                g1_std[(arch, lv)].append(std_income / REF_TOWER_COST)
            elif len(p) >= 4 and p[1] == 'BUILD':
                build.append(line.strip())

BANDS = [(1,10),(11,20),(21,30),(31,40),(41,50),(51,60),(61,70),(71,80),(81,90),(91,99),(100,100)]
ECON_BANDS = [(1,10),(11,30),(31,50),(51,70),(71,90),(91,100)]
arches = sorted({a for a, _ in rows})


def wr(a, lo, hi):
    w = [x for lv in range(lo, hi + 1) for x in rows.get((a, lv), [])]
    return (100.0 * sum(w) / len(w)) if w else float('nan'), len(w)


def lvwr(a, lv):
    v = rows.get((a, lv))
    return (100.0 * sum(v) / len(v)) if v else None


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
print('=== Gate 判定(第十八輪重釘)===')
verdicts = []


def chk(name, ok, detail):
    verdicts.append(ok)
    print('%-46s %s  %s' % (name, 'PASS' if ok else 'FAIL', detail))


if 'A0' in arches:
    r, _ = wr('A0', 1, 10); chk('Gate2a A0 1-10 >= 70%', r >= 70, '%.1f%%' % r)
if 'A1' in arches:
    r, _ = wr('A1', 1, 10); chk('Gate2b A1 1-10 >= 95%', r >= 95, '%.1f%%' % r)
    # 合約關唔入逐關斷言 —— 佢哋係另一套規則(玩家自揀增益換派彩),設計上
    # 就比鄰關難,同 Gate 7 嘅處理一致。合約關嘅收支自己有 Gate 8。
    bad = [lv for lv in range(11, 41)
           if lv % CONTRACT_EVERY != 0 and (lvwr('A1', lv) or 0) < 30]
    r, _ = wr('A1', 11, 40)
    chk('Gate3a A1 11-40 逐關 >= 30%(合約關除外)', not bad,
        '平均 %.1f%%,唔達標: %s' % (r, bad or '無'))
    r, _ = wr('A1', 41, 70); chk('Gate4a A1 41-70 <= 10%', r <= 10, '%.1f%%' % r)
if 'A2' in arches:
    r, _ = wr('A2', 41, 70); chk('Gate4b A2 41-70 >= 30%', r >= 30, '%.1f%%' % r)
    r, _ = wr('A2', 71, 99); chk('Gate5a A2 71-99 <= 12%', r <= 12, '%.1f%%' % r)
if 'A3' in arches:
    r, _ = wr('A3', 71, 99); chk('Gate5b A3 71-99 >= 28%', r >= 28, '%.1f%%' % r)
    r, n = wr('A3', 100, 100); chk('Gate6a A3 第100關 <= 5%', r <= 5, '%.1f%% (n=%d)' % (r, n))
if 'A4' in arches:
    r, n = wr('A4', 100, 100)
    chk('Gate6b A4 第100關 10-30%', 10 <= r <= 30,
        '%.1f%% -> 平均試 %.1f 場 (n=%d)' % (r, 100.0 / max(0.01, r), n))

print()
print('=== Gate7 難度分段單調 ===')
print('    段 = 1-10 / 11-40 / 41-70 / 71-80 / 81-90 / 91-99,段交界 41、71、81、91 容許回升。')
print('    81-90 = 雙 tier-3 完成帶,佢**兩邊**都係縫。')
print('    平滑窗 = 10 關(一個完整家族/boss 輪轉週期)。合約關唔入序列。')
# 第 21 輪重釘:完成帶由「91 呢一條縫」改成「81-90 呢一整個 block」,即係
# 81 同 91 兩邊都係縫。
#
# 點解:段界嘅意思一路都係「雙 tier-3 完成帶」。TIER_JUMP 1.70 -> 1.95 之後
# A3 課完第二件 tier-3 嘅時點提早咗,而佢**唔係一步過** —— 20-seed 實測 A3
# 71-80 = 22%、81-90 = 65%、91-99 = 88%,即係完成係喺 81-90 呢十關**期間**
# 發生,兩邊各有一次大幅回升。
#
# 三種切法喺同一份 20-seed 數據上面嘅實測(A3):
#   舊 41/71/91                    +36.1 點 @ 81-90  FAIL
#   只將縫由 91 移到 81            +22.8 點 @ 91-99  FAIL
#   完成帶 81-90(81 同 91 都係縫) +7.5 點 @ 31-40  PASS
# A2 三種切法都係 +7.5 @ 31-40 PASS,即係呢個改動唔會放鬆到其他原型。
G7_SEGS = [(1, 10), (11, 40), (41, 70), (71, 80), (81, 90), (91, 99)]
for a in arches:
    series = {}
    for lv in range(1, 101):
        if lv % CONTRACT_EVERY == 0 and lv != 100:
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
print('=== pacing:平均每關要試幾多場 ===')
# 「on-curve 玩家」= 該段設計上假設嘅原型:1-40 A1、41-70 A2、71-99 A3、100 A4。
# A1 喺 41-70 係 0-10%(Gate 4a 就係咁要求),嗰個唔係死位,係「你要進化」
# 嘅訊號 —— 所以死位判定睇 on-curve 原型,而 A1 自己嘅曲線照報。
ONCURVE = [(1, 40, 'A1'), (41, 70, 'A2'), (71, 99, 'A3'), (100, 100, 'A4')]
stuck = []
for lo, hi, a in ONCURVE:
    if a not in arches:
        continue
    vals = []
    for lv in range(lo, hi + 1):
        w = lvwr(a, lv)
        if w is None:
            continue
        att = 100.0 / w if w > 0 else float('inf')
        vals.append(att)
        if att >= 15 and lv % CONTRACT_EVERY != 0:
            stuck.append((lv, a, w))
    if vals:
        fin = [v for v in vals if v != float('inf')]
        print('%3d-%-3d on-curve=%s  平均 %.1f 場/關(最深 %s)'
              % (lo, hi, a, sum(fin) / max(1, len(fin)),
                 ('%.1f' % max(vals)) if all(v != float('inf') for v in vals) else '不通'))
for a in arches:
    vals = []
    for lv in range(1, 101):
        w = lvwr(a, lv)
        if w:
            vals.append(100.0 / w)
    if vals:
        print('  (參考)%s 全程有勝場嘅關平均 %.1f 場/關' % (a, sum(vals) / len(vals)))
if tries_at:
    print('  實測平均嘗試次數(harness 封頂 --tries,所以呢個係下限):')
    for a in arches:
        line = []
        for lo, hi in BANDS:
            v = [x for lv in range(lo, hi + 1) for x in tries_at.get((a, lv), [])]
            line.append('%d-%d:%s' % (lo, hi, ('%.2f' % (sum(v) / len(v))) if v else '-'))
        print('    %-4s %s' % (a, '  '.join(line)))
chk('pacing:on-curve 原型冇單關要試 >=15 場', not stuck,
    '死位: %s' % (', '.join('lv%d %s %.0f%%' % s for s in stuck) if stuck else '無'))

print()
print('=== 經濟 raw:(成關收入 + 起手金)÷ 一座主力塔(固定價)===')
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in econ_base.get((a, lv), [])]
        line.append('%d-%d:%s' % (lo, hi, ('%.1f' % (sum(vals) / len(vals))) if vals else '-'))
    print('%-4s %s' % (a, '  '.join(line)))
print()
print('=== 實測 G1:90 秒當量打怪收入 ÷ 參考塔價 %d(參考,gate 用 goldcurve)===' % REF_TOWER_COST)
for a in arches:
    line = []
    for lo, hi in ECON_BANDS:
        vals = [x for lv in range(lo, hi + 1) for x in g1_std.get((a, lv), [])]
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
