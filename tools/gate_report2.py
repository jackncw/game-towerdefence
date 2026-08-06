# -*- coding: utf-8 -*-
"""Gate 3b(凍結升級)同 Gate 8(合約經濟)嘅合併報告。

用法:
  python tools/gate_report2.py "qa/bench/gate/frozen_*.txt" "qa/bench/gate/contract_*.txt"
"""
import sys, glob, collections
sys.stdout.reconfigure(encoding="utf-8")

live = collections.defaultdict(list)     # lv -> [win]
frozen = collections.defaultdict(list)   # lv -> [win]  (N-5)
frozen15 = collections.defaultdict(list) # lv -> [win]  (N-15)
# contract: (strat, kind) -> [crystals], 同埋 (strat, kind) -> [win]
cry = collections.defaultdict(list)
cwin = collections.defaultdict(list)
cry_lv = collections.defaultdict(list)

for pat in sys.argv[1:]:
    for f in sorted(glob.glob(pat)):
        for line in open(f, encoding='utf-8', errors='replace'):
            p = line.split()
            if len(p) == 7 and p[1] == 'ROW' and p[0] == 'GATE' and p[4] in ('contract', 'normal'):
                # seed lv kind strat win crystals frac  -> 7 欄之後仲有 frac
                pass
            if p[:2] != ['GATE', 'ROW']:
                continue
            if len(p) == 7 and p[4].isdigit():
                # frozen: seed lv live_win frozen5_win frozen15_win
                lv, lw, f5, f15 = int(p[3]), int(p[4]), int(p[5]), int(p[6])
                live[lv].append(lw)
                if f5 >= 0:
                    frozen[lv].append(f5)
                if f15 >= 0:
                    frozen15[lv].append(f15)
            elif len(p) == 9 and p[4] in ('contract', 'normal'):
                lv, kind, strat, win, crystals = int(p[3]), p[4], p[5], int(p[6]), int(p[7])
                cry[(strat, kind)].append(crystals)
                cwin[(strat, kind)].append(win)
                cry_lv[(strat, kind, lv)].append(crystals)

if live:
    print('=== Gate 3b 凍結升級測試(第十七輪重釘:窗口 = 15 關)===')
    print('區間      實時勝率   凍5關勝率  凍15關勝率  樣本')
    for lo, hi in [(16, 25), (26, 35), (36, 40), (16, 40)]:
        lw = [x for lv in range(lo, hi + 1) for x in live.get(lv, [])]
        fw = [x for lv in range(lo, hi + 1) for x in frozen.get(lv, [])]
        f15 = [x for lv in range(lo, hi + 1) for x in frozen15.get(lv, [])]
        if not fw:
            continue
        print('%2d-%-3d  %7.1f%%  %8.1f%%  %9s   %d' %
              (lo, hi, 100.0 * sum(lw) / max(1, len(lw)),
               100.0 * sum(fw) / len(fw),
               ('%.1f%%' % (100.0 * sum(f15) / len(f15))) if f15 else '-', len(fw)))
    g = [x for lv in range(16, 41) for x in frozen15.get(lv, [])]
    r15 = 100.0 * sum(g) / max(1, len(g))
    # 第十八輪重釘:25% -> 12%(Gate 3-5 一律減半)
    print('Gate3b 凍結 N-15 於 16-40 <= 12%%: %s (%.1f%%)' % ('PASS' if r15 <= 12 else 'FAIL', r15))
    fw = [x for lv in range(16, 41) for x in frozen.get(lv, [])]
    if fw:
        print('(診斷)凍結 N-5 於 16-40: %.1f%%(v1 窗口,唔係 gate)'
              % (100.0 * sum(fw) / len(fw)))

if cry:
    print()
    print('=== Gate 8 合約經濟 ===')
    print('策略    關卡類型    平均入袋魔晶   勝率    樣本')
    for strat in ('safe', 'greedy'):
        for kind in ('normal', 'contract'):
            v = cry.get((strat, kind), [])
            w = cwin.get((strat, kind), [])
            if not v:
                continue
            print('%-7s %-10s %12.0f  %5.0f%%  %d'
                  % (strat, kind, sum(v) / len(v), 100.0 * sum(w) / len(w), len(v)))
    for strat in ('safe', 'greedy'):
        n = cry.get((strat, 'normal'), [])
        c = cry.get((strat, 'contract'), [])
        if not n or not c:
            continue
        ratio = (sum(c) / len(c)) / max(1e-9, (sum(n) / len(n)))
        # 方差:合約關嘅入袋魔晶標準差 / 平均
        m = sum(c) / len(c)
        sd = (sum((x - m) ** 2 for x in c) / max(1, len(c) - 1)) ** 0.5
        mn = sum(n) / len(n)
        sdn = (sum((x - mn) ** 2 for x in n) / max(1, len(n) - 1)) ** 0.5
        print('%-7s 合約/普通 = %.3f    合約變異係數 %.2f  vs 普通 %.2f'
              % (strat, ratio, sd / max(1e-9, m), sdn / max(1e-9, mn)))
        if strat == 'safe':
            print('  Gate8a 穩陣 1.1-1.3: %s' % ('PASS' if 1.1 <= ratio <= 1.3 else 'FAIL'))
        else:
            print('  Gate8b 貪心 <= 1.5: %s' % ('PASS' if ratio <= 1.5 else 'FAIL'))
