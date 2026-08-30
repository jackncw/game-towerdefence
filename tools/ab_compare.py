# -*- coding: utf-8 -*-
"""逐關對兩組 GateSim campaign 讀數,證明「一個字都冇變」。

第 24 輪 Part A.5 用嘅:「通關第 100 關之後重玩派全額」呢條規則加落去之後,
1-100 進程中嘅每一個讀數都要同定版一模一樣。呢個工具就係嗰句說話嘅可執行
版本 —— 唔係「差唔多」,係**逐個 seed 逐關逐欄**對。

點解要對成行而唔係淨係對勝率:一條規則可以令勝率一樣但收入唔同(例如
敗仗獎勵減免飄咗),而嗰種漂移要幾輪之後先喺升級曲線度睇得出。ROW 行入面
有塔數、收入、起手金同戰鬥時間,全部一齊對就冇得匿。

用法:
  python tools/ab_compare.py qa/bench/gate/r24_ab base new
"""
import sys, os, glob, collections

sys.stdout.reconfigure(encoding="utf-8")

root = sys.argv[1] if len(sys.argv) > 1 else "qa/bench/gate/r24_ab"
arm_a = sys.argv[2] if len(sys.argv) > 2 else "base"
arm_b = sys.argv[3] if len(sys.argv) > 3 else "new"


def load(arm):
    """{(arch, seed, lv): [欄...]} —— 一個 seed 一關一行。"""
    out = {}
    files = sorted(glob.glob(os.path.join(root, arm + "_*.txt")))
    files = [f for f in files if not f.endswith(".err.txt")]
    for f in files:
        for line in open(f, encoding="utf-8", errors="replace"):
            p = line.split()
            if len(p) < 15 or p[0] != "GATE" or p[1] != "ROW" or not p[2].startswith("A"):
                continue
            out[(p[2], int(p[3]), int(p[4]))] = p[5:]
    return out, files


a, files_a = load(arm_a)
b, files_b = load(arm_b)
print("%s: %d 行 / %d 檔" % (arm_a, len(a), len(files_a)))
print("%s: %d 行 / %d 檔" % (arm_b, len(b), len(files_b)))

only_a = sorted(set(a) - set(b))
only_b = sorted(set(b) - set(a))
if only_a or only_b:
    print("!! 兩邊嘅 (原型, seed, 關) 對唔齊:只喺 %s 有 %d 行,只喺 %s 有 %d 行"
          % (arm_a, len(only_a), arm_b, len(only_b)))
    for k in (only_a + only_b)[:10]:
        print("   ", k)

common = sorted(set(a) & set(b))
diff_rows = []
diff_cols = collections.Counter()
win_diff = []
for k in common:
    ra, rb = a[k], b[k]
    if ra == rb:
        continue
    diff_rows.append(k)
    for i, (x, y) in enumerate(zip(ra, rb)):
        if x != y:
            diff_cols[i] += 1
    if ra[0] != rb[0]:          # 第一欄 = win
        win_diff.append((k, ra[0], rb[0]))

print()
print("共同樣本 %d 行(= 原型 x seed x 關)" % len(common))
print("逐欄完全一樣嘅行: %d" % (len(common) - len(diff_rows)))
print("有任何一欄唔同嘅行: %d" % len(diff_rows))
print("勝負唔同嘅行: %d" % len(win_diff))
if diff_cols:
    print("唔同嘅欄位分佈(欄索引由 win 算起 0): %s" % dict(diff_cols))
for k, x, y in win_diff[:20]:
    print("   勝負差異 %s seed%d lv%d: %s -> %s" % (k[0], k[1], k[2], x, y))

# 分段勝率(就算逐行一樣,呢張表都要印 —— 一份報告要睇得返讀數本身)
BANDS = [(1, 10), (11, 40), (41, 70), (71, 99), (100, 100)]
print()
print("=== 分段勝率對照 ===")
print("%-4s %-9s %9s %9s" % ("原型", "區間", arm_a, arm_b))
arches = sorted({k[0] for k in common})
for arch in arches:
    for lo, hi in BANDS:
        wa = [int(a[k][0]) for k in common if k[0] == arch and lo <= k[2] <= hi]
        wb = [int(b[k][0]) for k in common if k[0] == arch and lo <= k[2] <= hi]
        if not wa:
            continue
        print("%-4s %-9s %8.1f%% %8.1f%%   n=%d"
              % (arch, "%d-%d" % (lo, hi), 100.0 * sum(wa) / len(wa),
                 100.0 * sum(wb) / len(wb), len(wa)))

ok = not diff_rows and not only_a and not only_b and common
print()
print("A/B 判定: %s" % ("IDENTICAL — 逐個 seed 逐關逐欄一模一樣"
                        if ok else "有差異,見上面"))
sys.exit(0 if ok else 1)
