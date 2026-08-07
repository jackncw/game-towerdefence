# TimeScaleTest 併行資源競態嘅根因探針(第 21 輪)。
#
# 症狀(兩輪都撞過):TimeScaleTest 喺**整套**跑嘅時候冇 verdict,單獨跑 PASS。
# 假設:唔關 TimeScaleTest 事,係「同時有第二個 Godot 進程喺度寫
# user://save.json」。run_tests.ps1 自己係逐個測試順住跑嘅,所以「整套跑」
# 嗰陣通常同時有另一件嘢喺度跑(GateSim 分片 / 手動量度),而佢哋全部
# 共用同一個 user://。
#
# 呢個 script 開 N 個「寫存檔寫到癲」嘅 GateSim 分片做背景噪音,再喺噪音底下
# 跑 TimeScaleTest,兩個配置各跑一次:
#   A  分片**唔加** --nosave  -> 一齊搶住寫 user://save.json
#   B  分片**加咗** --nosave  -> 分片完全唔掂個檔
# 兩次之間唯一嘅分別就係嗰個 flag,所以結果直接答到「係咪佢」。
#
# 用法: powershell -File tools/race_probe.ps1 [-Noise 8]
param(
  [int]$Noise = 8,
  [string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
$dir = Join-Path $root "qa\bench\runlogs\race"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

function Run-Case($label, $extra) {
  Write-Host ""
  Write-Host ("=== " + $label + " ===")
  $procs = @()
  for ($i = 0; $i -lt $Noise; $i++) {
    # --to=25 = 一個短 campaign。GateSim 逐關 _spend() 都寫一次存檔,所以
    # 呢啲分片就係一部「不停開 FileAccess.WRITE 截斷 save.json」嘅機器。
    $a = @("--headless", "--path", ".", "res://test/GateSim.tscn", "--",
           "--mode=sweep", "--arch=A1", "--seeds=2", "--seed0=$i", "--to=25") + $extra
    $procs += Start-Process -FilePath $Godot -ArgumentList $a -NoNewWindow -PassThru `
              -RedirectStandardOutput (Join-Path $dir ("noise_{0}_{1}.txt" -f $label, $i)) `
              -RedirectStandardError (Join-Path $dir ("noise_{0}_{1}.err.txt" -f $label, $i))
  }
  Start-Sleep -Seconds 8      # 等噪音真係開始寫檔
  $o = Join-Path $dir ("ts_{0}.txt" -f $label)
  $e = Join-Path $dir ("ts_{0}.err.txt" -f $label)
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", ".",
       "res://test/TimeScaleTest.tscn") -Wait -NoNewWindow -PassThru `
       -RedirectStandardOutput $o -RedirectStandardError $e
  $sw.Stop()
  $hit = Select-String -Path $o -Pattern 'PASS|FAIL' | Select-Object -Last 1
  $verdict = ""
  if ($hit) { $verdict = $hit.Line }
  Write-Host ("TimeScaleTest exit={0} {1}s  verdict=[{2}]" -f $p.ExitCode, [math]::Round($sw.Elapsed.TotalSeconds, 1), $verdict)
  $errTxt = Get-Content $e -Raw -ErrorAction SilentlyContinue
  if ($errTxt) { Write-Host ("stderr 頭 400 字: " + $errTxt.Substring(0, [Math]::Min(400, $errTxt.Length))) }
  foreach ($q in $procs) { if (-not $q.HasExited) { $q.Kill() } }
  Start-Sleep -Seconds 2
  return @{ Exit = $p.ExitCode; Verdict = $verdict }
}

$a = Run-Case "A_nosave_off" @()
$b = Run-Case "B_nosave_on" @("--nosave")

Write-Host ""
Write-Host "=== 結論 ==="
Write-Host ("A(分片搶住寫 save.json): exit={0} verdict=[{1}]" -f $a.Exit, $a.Verdict)
Write-Host ("B(分片 --nosave):        exit={0} verdict=[{1}]" -f $b.Exit, $b.Verdict)
Pop-Location
