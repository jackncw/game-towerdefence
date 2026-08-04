#!/bin/sh
# 並行跑 5 個原型 x N 個 seed。A4 由 --from 起(佢個 build 唔靠歷史)。
# 用法: sh tools/gate_sweep.sh <seeds> <shards> <tag> [a4from]
S=${1:-2}; K=${2:-1}; TAG=${3:-fast}; A4FROM=${4:-91}
rm -f qa/bench/gate/sweep_${TAG}_*.txt
for A in A0 A1 A2 A3 A4; do
  i=0
  while [ $i -lt $K ]; do
    EXTRA=""
    [ "$A" = "A4" ] && EXTRA="--from=$A4FROM"
    sh tools/gate.sh "sweep_${TAG}_${A}_${i}" --arch=$A --seeds=$S --seed0=$((i*S)) $EXTRA &
    i=$((i+1))
  done
done
wait
echo "sweep done"
