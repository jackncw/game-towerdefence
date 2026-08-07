# 20-seed 定版 job(第 21 輪)—— 可斷點續跑。
#
# 一次過跑齊定版 Gate 1-8 所需嘅全部量度:
#   * A2/A3/A1/A0 × seed 0-19 × 第 1-100 關 campaign(Gate 2-5、7、pacing、經濟)
#   * A4 × seed 0-19 × 第 91-100 關(Gate 6b —— A4 個 build 係授予嘅,唔靠歷史)
#   * frozen × 20 seed(Gate 3b)、contract × 20 seed(Gate 8)
# G1 / G2 唔喺呢度(tools/goldcurve.tscn / goldsrc.tscn,純算術,幾秒就跑完)。
#
# 原型次序係**特登**咁排嘅:A2 同 A3 行先。呢個 job 十幾個鐘,好可能要分幾次
# 跑完,而 Gate 5a / 5b 就係本輪要答嘅嗰兩條 —— 佢哋嘅樣本要最早齊。
#
# ── 斷點續跑點樣做 ──────────────────────────────────────────────
# 一個「工作單位」= 一個進程 = 一個輸出檔。跑完嘅單位喺檔尾有 "GATE DONE"。
# 再開一次呢個 script,佢只會跑**未有完成標記**嗰啲單位;跑到一半俾人殺咗嘅
# 檔會被刪走重跑(唔可以由一個殘缺 campaign 接落去 —— 勝率會偏向前段)。
# 所以隨時 Ctrl-C、隨時再開,冇任何手工步驟。
#
# ── 點解每個單位一個進程 ────────────────────────────────────────
# 一個 seed 一個 campaign 係 10-40 分鐘。單位切得細啲,一次中斷最多蝕一個
# 單位;切得粗啲(例如一個 arch 一個進程跑 20 seed)中斷就蝕成十個鐘。
#
# ── --nosave ────────────────────────────────────────────────────
# 全部分片都行 `--nosave`(見 Meta.disk_enabled):十幾個進程唔會搶住寫同一個
# user://save.json,所以 (a) Jack 自己個存檔一條毛都唔會郁,(b) 跑緊呢個 job
# 嘅同時照樣可以 run_tests.ps1,唔會出假失敗。
#
# 用法:
#   powershell -File tools/gate20.ps1                  # 開跑 / 續跑
#   powershell -File tools/gate20.ps1 -Jobs 6          # 自己指定並行數
#   powershell -File tools/gate20.ps1 -Status          # 淨係睇進度,唔跑
#   powershell -File tools/gate20.ps1 -Report          # 出 gate 報告
#   # A/B 對照組(關咗 boss 開場傷害上限):
#   powershell -File tools/gate20.ps1 -Tag nofloor -Arches A2 -Seeds 8 -NoBossFloor -NoExtras
# Jack 雙擊:tools/續跑定版job.bat
param(
  [int]$Seeds = 20,
  [int]$Jobs = 0,
  [string]$Tag = "r21",
  [string[]]$Arches = @("A2", "A3", "A1", "A0", "A4"),
  [switch]$NoExtras,
  [switch]$NoBossFloor,
  [switch]$Status,
  [switch]$Report,
  [string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
$out = Join-Path $root ("qa\bench\gate\" + $Tag)
New-Item -ItemType Directory -Force -Path $out | Out-Null

if ($Jobs -le 0) {
  # 留兩粒核俾機器做人事。GateSim 係純 CPU 單線程,所以並行數 = 核數 - 2。
  $Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 2)
}
$extraArgs = @()
if ($NoBossFloor) { $extraArgs += "--nobossfloor" }

# ---------------------------------------------------------------------------
# 工作單位清單
# ---------------------------------------------------------------------------
$units = @()
foreach ($a in $Arches) {
  for ($s = 0; $s -lt $Seeds; $s++) {
    # A4 個 build 係直接授予嘅,唔靠歷史,所以由第 91 關開波就夠 Gate 6b 用。
    $ar = @("--mode=sweep", "--arch=$a", "--seeds=1", "--seed0=$s", "--nosave")
    if ($a -eq "A4") { $ar += "--from=91" }
    $units += [pscustomobject]@{
      Name = ("{0}_s{1:d2}" -f $a, $s)
      Args = $ar + $extraArgs
      Done = "GATE DONE"
    }
  }
}
if (-not $NoExtras) {
  # Gate 6b(A4 第 100 關)嘅**正確量法係 `--mode=final`,唔係 sweep 嘅第 100
  # 關嗰行。** 第十七輪量過:第 100 關嘅勝率對初始條件混沌敏感(同一個難度
  # 24-seed 之間 15%↔42%),而 sweep 去到第 100 關之前已經打咗九關,RNG 狀態
  # 同 final mode 完全唔同。實測差別唔細:同一個 build,sweep-from-91 讀到
  # 0/20,final mode 讀到 2/20 —— 兩個都係真數,但 6b 嗰個窗口(10-30%)係
  # 用 final mode 定出嚟嘅,所以要用返同一把尺。
  # 48 seed 分三片(final mode 收 --seed0)。
  foreach ($s0 in @(0, 16, 32)) {
    $units += [pscustomobject]@{
      Name = ("final_A4_s{0:d2}" -f $s0)
      Args = @("--mode=final", "--arch=A4", "--seeds=16", "--seed0=$s0", "--nosave") + $extraArgs
      Done = "GATE FINAL" }
  }
  # Gate 3b / Gate 8。呢兩個 mode 唔收 --seed0,所以一個進程包晒 20 seed。
  $units += [pscustomobject]@{
    Name = "frozen"
    Args = @("--mode=frozen", "--seeds=$Seeds", "--nosave") + $extraArgs
    Done = "GATE DONE" }
  $units += [pscustomobject]@{
    Name = "contract"
    Args = @("--mode=contract", "--seeds=$Seeds", "--nosave") + $extraArgs
    Done = "GATE DONE" }
}

function Test-UnitDone($u) {
  $f = Join-Path $out ($u.Name + ".txt")
  if (-not (Test-Path $f)) { return $false }
  $txt = Get-Content $f -Raw -ErrorAction SilentlyContinue
  if ($null -eq $txt) { return $false }
  return $txt.Contains($u.Done)
}

$doneList = @($units | Where-Object { Test-UnitDone $_ })
$todo = @($units | Where-Object { -not (Test-UnitDone $_) })

Write-Host ("[{0}] {1} 個單位,已完成 {2},未完成 {3}(並行 {4})" -f $Tag, @($units).Count, $doneList.Count, $todo.Count, $Jobs)
if ($Status) {
  foreach ($u in $todo) { Write-Host ("  todo  " + $u.Name) }
  Pop-Location; exit 0
}

if ($Report) {
  python tools/gate_report.py (Join-Path $out "A*.txt")
  # Gate 6b 要用 final mode 嗰批(見上面 final_A4 嗰段嘅註)。gate_report.py
  # 讀唔到 final mode 嘅 ROW(得 5 欄),所以喺呢度自己數。
  $fin = @(Get-ChildItem (Join-Path $out "final_A4_*.txt") -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -notlike "*.err.txt" })
  if ($fin.Count -gt 0) {
    $w = 0; $n = 0
    foreach ($f in $fin) {
      foreach ($line in (Get-Content $f.FullName)) {
        $p = $line -split '\s+'
        if ($p.Count -eq 6 -and $p[0] -eq 'GATE' -and $p[1] -eq 'ROW' -and $p[2] -eq 'A4') {
          $w += [int]$p[4]; $n++
        }
      }
    }
    if ($n -gt 0) {
      $r = 100.0 * $w / $n
      $ok = ($r -ge 10) -and ($r -le 30)
      Write-Host ""
      Write-Host ("Gate6b A4 第100關 10-30%(final mode, n={0})  {1}  {2:N1}%" -f $n, $(if ($ok) { "PASS" } else { "FAIL" }), $r)
    }
  }
  if (Test-Path (Join-Path $out "frozen.txt")) {
    python tools/gate_report2.py (Join-Path $out "frozen.txt") (Join-Path $out "contract.txt")
  }
  Pop-Location; exit 0
}

# ---------------------------------------------------------------------------
# 跑
# ---------------------------------------------------------------------------
# 一個殘檔(跑到一半俾人殺咗)一定要刪 —— 一個殘缺 campaign 嘅 ROW 行會
# 靜靜咁被 gate_report 當成真數據,而勝率就會偏向前段。
foreach ($u in $todo) {
  $f = Join-Path $out ($u.Name + ".txt")
  if (Test-Path $f) { Remove-Item $f -Force }
}

$running = @()
$startAll = Get-Date
$finished = 0
$total = $todo.Count
$queue = New-Object System.Collections.Queue
foreach ($u in $todo) { $queue.Enqueue($u) | Out-Null }

while ($queue.Count -gt 0 -or $running.Count -gt 0) {
  while ($running.Count -lt $Jobs -and $queue.Count -gt 0) {
    $u = $queue.Dequeue()
    $f = Join-Path $out ($u.Name + ".txt")
    $e = Join-Path $out ($u.Name + ".err.txt")
    $cmdArgs = @("--headless", "--path", ".", "res://test/GateSim.tscn", "--") + $u.Args
    $p = Start-Process -FilePath $Godot -ArgumentList $cmdArgs -NoNewWindow -PassThru `
         -RedirectStandardOutput $f -RedirectStandardError $e
    $running += [pscustomobject]@{ U = $u; P = $p; T = Get-Date }
    Write-Host ("  -> 開 " + $u.Name)
  }
  Start-Sleep -Seconds 5
  $still = @()
  foreach ($r in $running) {
    if ($r.P.HasExited) {
      $finished++
      $ok = Test-UnitDone $r.U
      $mins = [math]::Round(((Get-Date) - $r.T).TotalMinutes, 1)
      Write-Host ("  <- {0} {1} {2}m  ({3}/{4})" -f $r.U.Name, $(if ($ok) { "OK" } else { "**冇完成標記**" }), $mins, $finished, $total)
    } else {
      $still += $r
    }
  }
  $running = $still
}

$mins = [math]::Round(((Get-Date) - $startAll).TotalMinutes, 1)
$left = @($units | Where-Object { -not (Test-UnitDone $_) })
Write-Host ""
Write-Host ("用咗 {0} 分鐘。仲未完成:{1}" -f $mins, $left.Count)
if ($left.Count -gt 0) {
  foreach ($u in $left) { Write-Host ("  todo  " + $u.Name) }
  Write-Host "再開一次呢個 script(或者雙擊 tools/續跑定版job.bat)就會由呢度接落去。"
  Pop-Location; exit 1
}
Write-Host "全部單位完成。出報告:powershell -File tools/gate20.ps1 -Report"
Pop-Location
exit 0
