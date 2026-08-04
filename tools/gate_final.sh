#!/bin/sh
# 最終驗收:5 原型 x 20 seed(A4 由第 61 關起)+ frozen(Gate 3b)+ contract(Gate 8)。
rm -f qa/bench/gate/sweep_full_*.txt qa/bench/gate/frozen_*.txt qa/bench/gate/contract_*.txt
for A in A0 A1 A2 A3 A4; do
  i=0
  while [ $i -lt 5 ]; do
    EXTRA=""
    [ "$A" = "A4" ] && EXTRA="--from=61"
    sh tools/gate.sh "sweep_full_${A}_${i}" --arch=$A --seeds=4 --seed0=$((i*4)) $EXTRA &
    i=$((i+1))
  done
done
i=0
while [ $i -lt 5 ]; do
  sh tools/gate.sh "frozen_$i" --mode=frozen --seeds=4 --seed0=$((i*4)) &
  i=$((i+1))
done
i=0
while [ $i -lt 3 ]; do
  sh tools/gate.sh "contract_$i" --mode=contract --seeds=2 --seed0=$((i*2)) &
  i=$((i+1))
done
wait
echo "FULL SWEEP DONE"
