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
  # 5400 唔係求其揀:SoakTest 30 轉單獨跑 1949 秒,而實測 8-way CPU 壓力之下
  # 一個測試會慢 1.8 倍(見 tools/race_probe.ps1 量到嘅 89.6s -> 161s),
  # 即係最壞 ~3500 秒。5400 留返一半餘裕。
  [int]$TimeoutSec = 5400,
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
  $p = Start-Process -FilePath $Godot -ArgumentList $cmdArgs -NoNewWindow -PassThru `
       -RedirectStandardOutput $out -RedirectStandardError $err
  # **呢一句唔可以刪。** `Start-Process -PassThru` 冇 `-Wait` 嘅時候,
  # PowerShell 唔會保住個 process handle,於是 process 一收工 `$p.ExitCode`
  # 就係 $null。而 `$null -ne 0` 係 $true —— 即係「全部測試都當肥佬」。
  # 讀一次 `.Handle` 會迫佢 cache 住個 handle,之後 ExitCode 先讀得返。
  $null = $p.Handle
  # 掛住等,但有上限。一個掛死咗嘅測試以前會令成套跑停喺度冇聲冇息,而
  # 「跑咗成晚都未完」同「跪低咗」喺輸出上面分唔出。
  $timedOut = $false
  if (-not $p.WaitForExit($TimeoutSec * 1000)) {
    $timedOut = $true
    try { $p.Kill() } catch { }
    $p.WaitForExit(10000) | Out-Null
  }
  $sw.Stop()
  # 每個測試自己嗰行 PASS/FAIL 先係真信號;exit code 係「有冇死喺半路」。
  #
  # **第 21 輪:「冇 verdict」而家係一個失敗,唔再係一格空白。**
  # 之前 InputProbe / SpellFlowTest / WinTest / Shots / BalanceSim / StratDiag
  # 六個場景由頭到尾都唔會印一行對得上呢個 pattern 嘅嘢,所以佢哋喺報告入面
  # 永遠係一格空白 —— 而一個**真係**冇出到 verdict 嘅測試(例如 TimeScaleTest
  # 喺整套跑嘅時候)睇落一模一樣。分唔出,即係嗰個症狀永遠查唔到。
  # 而家六個場景全部會印一行明確結論(有斷言嘅印 PASS/FAIL 兼且真係 set
  # exit code,純 bench 嘅印 REPORT-ONLY),而呢度一格空白就係一單失敗。
  $hit = Select-String -Path $out -Pattern 'PASS|FAIL|ALL DONE|passed|COMPLETE|REPORT-ONLY' | Select-Object -Last 1
  $verdict = ""
  if ($hit) { $verdict = $hit.Line }
  if ($timedOut) { $verdict = ("**TIMEOUT >" + $TimeoutSec + "s** " + $verdict) }
  $row = New-Object psobject
  $row | Add-Member NoteProperty Test $name
  $row | Add-Member NoteProperty Exit $p.ExitCode
  $row | Add-Member NoteProperty Sec ([math]::Round($sw.Elapsed.TotalSeconds, 1))
  $row | Add-Member NoteProperty Verdict $verdict
  $row | Add-Member NoteProperty NoVerdict ([bool](-not $hit))
  $row | Add-Member NoteProperty TimedOut $timedOut
  $results += $row
  $tag = ""
  if (-not $hit) { $tag = "  << 冇 verdict" }
  Write-Host ("{0,-18} exit={1} {2,7}s  {3}{4}" -f $name, $p.ExitCode, $sw.Elapsed.TotalSeconds.ToString("0.0"), $verdict, $tag)
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
$noverdict = @($results | Where-Object { $_.NoVerdict })
Write-Host ""
Write-Host ("TESTS: {0} run, {1} non-zero exit, {2} 冇 verdict" -f @($results).Count, $bad.Count, $noverdict.Count)
if ($bad.Count -gt 0) { $bad | Format-Table -AutoSize | Out-String -Width 200 | Write-Host }
if ($noverdict.Count -gt 0) {
  Write-Host "冇 verdict(即係個測試冇講過自己過唔過到,同肥佬一樣要查):"
  $noverdict | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
}
if ($bad.Count -gt 0 -or $noverdict.Count -gt 0) { exit 1 }
exit 0
