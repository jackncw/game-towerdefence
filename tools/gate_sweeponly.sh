#!/bin/sh
rm -f qa/bench/gate/sweep_full_*.txt
for A in A0 A1 A2 A3 A4; do
  i=0
  while [ $i -lt 5 ]; do
    EXTRA=""
    [ "$A" = "A4" ] && EXTRA="--from=61"
    sh tools/gate.sh "sweep_full_${A}_${i}" --mode=sweep --arch=$A --seeds=4 --seed0=$((i*4)) $EXTRA &
    i=$((i+1))
  done
done
wait
echo SWEEPDONE
