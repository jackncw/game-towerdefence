# 跑晒 test/ 底下每一個測試場景,一個 process 一個,收集 exit code。
#
# 點解一個測試一個 process:一單真閃退會殺死成個 process,而如果全部測試共用
# 一個 process,第一單閃退之後嘅測試就變成「冇跑過」而唔係「跪低咗」——
# 兩者喺報告入面睇落一樣,但意思完全相反。
#
# 用法:  powershell -File tools/run_tests.ps1 [-Only SoakTest] [-SoakRounds 30]
param(
  [string]$Only = "",
  [int]$SoakRounds = 30,
  [string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
)

$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
$logdir = Join-Path $root "build/testlogs"
New-Item -ItemType Directory -Force -Path $logdir | Out-Null

$scenes = Get-ChildItem (Join-Path $root "test") -Filter "*.tscn" | Sort-Object Name
if ($Only -ne "") { $scenes = $scenes | Where-Object { $_.BaseName -like "*$Only*" } }

$results = @()
foreach ($s in $scenes) {
  $name = $s.BaseName
  $out = Join-Path $logdir ($name + ".out.txt")
  $err = Join-Path $logdir ($name + ".err.txt")
  # --path 用 "." 而唔係絕對路徑:專案資料夾個名有空格,而 Windows PowerShell
  # 5.1 嘅 Start-Process -ArgumentList 對引號嘅處理靠唔住(手動加引號一樣會被
  # 再包一層),結果 Godot 收到嘅 --path 淨係得第一段就 abort。Push-Location
  # 之後 "." 冇空格,問題根本唔存在。
  $cmdArgs = @('--headless', '--path', '.', ("res://test/" + $s.Name))
  if ($name -eq "SoakTest") { $cmdArgs = $cmdArgs + @('--', ("--rounds=" + $SoakRounds)) }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $p = Start-Process -FilePath $Godot -ArgumentList $cmdArgs -Wait -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  $sw.Stop()
  # 每個測試自己嗰行 PASS/FAIL 先係真信號;exit code 係「有冇死喺半路」。
  $hit = Select-String -Path $out -Pattern 'PASS|FAIL|ALL DONE|passed|COMPLETE' | Select-Object -Last 1
  $verdict = ""
  if ($hit) { $verdict = $hit.Line }
  $row = New-Object psobject
  $row | Add-Member NoteProperty Test $name
  $row | Add-Member NoteProperty Exit $p.ExitCode
  $row | Add-Member NoteProperty Sec ([math]::Round($sw.Elapsed.TotalSeconds, 1))
  $row | Add-Member NoteProperty Verdict $verdict
  $results += $row
  Write-Host ("{0,-18} exit={1} {2,7}s  {3}" -f $name, $p.ExitCode, $sw.Elapsed.TotalSeconds.ToString("0.0"), $verdict)
}

Pop-Location
# @() 唔可以刪。PowerShell 5.1 嘅 Where-Object 篩剩**一個**物件嗰陣返嘅唔係
# array 而係嗰個物件本身,而一個 psobject 冇 .Count —— 即係話 `$bad.Count` 係
# $null,`$null -gt 0` 係 $false,於是「啱啱有一個測試跪低」呢個情況會印出
# 「TESTS: 30 run,  non-zero exit」(個數係空白)然後 **exit 0**。
#
# 兩個以上就啱返,所以呢個 bug 淨係喺最容易發生嗰種情況(一個 fail)出現,
# 而佢嘅後果係成條驗證防線靜靜雞失效:2026-08-03 效能輪嗰次 I18nTest 真係
# fail 咗,而套件報全綠。
$bad = @($results | Where-Object { $_.Exit -ne 0 })
Write-Host ""
Write-Host ("TESTS: {0} run, {1} non-zero exit" -f @($results).Count, $bad.Count)
if ($bad.Count -gt 0) { $bad | Format-Table -AutoSize | Out-String -Width 200 | Write-Host; exit 1 }
exit 0
