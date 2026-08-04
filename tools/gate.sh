#!/bin/sh
# 跑一個 GateSim mode,輸出落 qa/bench/gate/<name>.txt。
# Godot 個 exe 路徑有空格,所以要引號;--path . 避開資料夾名嗰個空格。
G="C:/Users/User/Desktop/Jack/AI/Godot_v4.7.1-stable_win64.exe"
NAME="$1"; shift
"$G" --headless --path . res://test/GateSim.tscn -- "$@" > "qa/bench/gate/$NAME.txt" 2> "qa/bench/gate/$NAME.err"
echo "exit=$? $NAME"
