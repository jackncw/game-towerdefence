# 通用平行 sweep runner(第 24 輪 Part D / E 校準用)。
#
# 一個「單位」= 一個 GateSim 進程 = 一個輸出檔。單位清單由一個 .txt 讀入,
# 一行一個:  <名>|<以空格分隔嘅 GateSim 參數>
# 咁樣一份 sweep 嘅定義就係一個可以入 repo 嘅檔,唔係一句打喺 shell 度嘅嘢。
param(
  [Parameter(Mandatory=$true)][string]$Units,
  [Parameter(Mandatory=$true)][string]$Out,
  [int]$Jobs = 16,
  [string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$list = @()
# **`-Encoding UTF8` 唔可以刪。** PowerShell 5.1 嘅 Get-Content 預設用系統
# ANSI codepage(呢部機係 cp950)讀檔,而一個有中文註解嘅 UTF-8 檔喺 cp950
# 之下會被食咗行尾:UTF-8 嘅多位元組序列被當成 cp950 雙位元組字,配對錯位
# 就會將行尾吞埋落去。實測病徵:一個 14 行嘅單位檔讀出嚟得 12 行,而少咗
# 嘅嗰個單位**冇任何錯誤訊息** —— 佢淨係冇跑,而個 sweep 報告入面就少咗
# 一格(第一次跑 Part D 嘅時候真係食咗 A3 嗰個 baseline)。
foreach ($line in (Get-Content $Units -Encoding UTF8)) {
  if ($line -match '^\s*#' -or $line -notmatch '\|') { continue }
  $name, $args = $line -split '\|', 2
  $list += [pscustomobject]@{ Name = $name.Trim(); Args = ($args.Trim() -split '\s+') }
}
Write-Host ("sweep: " + $list.Count + " 個單位,並行 " + $Jobs)
$queue = New-Object System.Collections.Queue
foreach ($u in $list) { $queue.Enqueue($u) | Out-Null }
$running = @()
$start = Get-Date
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
  while ($running.Count -lt $Jobs -and $queue.Count -gt 0) {
    $u = $queue.Dequeue()
    $f = Join-Path $Out ($u.Name + ".txt")
    $e = Join-Path $Out ($u.Name + ".err.txt")
    $p = Start-Process -FilePath $Godot -NoNewWindow -PassThru `
         -ArgumentList (@("--headless","--path",".","res://test/GateSim.tscn","--") + $u.Args) `
         -RedirectStandardOutput $f -RedirectStandardError $e
    $null = $p.Handle
    $running += [pscustomobject]@{ U = $u; P = $p; T = Get-Date }
    Write-Host ("  -> " + $u.Name)
  }
  Start-Sleep -Seconds 5
  $still = @()
  foreach ($r in $running) {
    if ($r.P.HasExited) {
      Write-Host ("  <- {0}  {1}m" -f $r.U.Name, [math]::Round(((Get-Date)-$r.T).TotalMinutes,1))
    } else { $still += $r }
  }
  $running = $still
}
Write-Host ("SWEEP DONE " + [math]::Round(((Get-Date)-$start).TotalMinutes,1) + " min")
Pop-Location
