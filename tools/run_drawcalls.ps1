param([string]$Tag = "before", [string]$Scenes = "menu,battle,peak")

$ErrorActionPreference = "Continue"
$godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $root "qa\bench\drawcalls") | Out-Null

# 個專案資料夾個名有空格,而 Start-Process -ArgumentList 會再包一層引號 ——
# 所以 Push-Location 之後全部用相對路徑(見 tower-fortress-testing memory)。
Push-Location $root
try {
  foreach ($s in $Scenes.Split(",")) {
    $s = $s.Trim()
    $rel = "qa/bench/drawcalls/$Tag-$s.log"
    if (Test-Path $rel) { Remove-Item $rel -Force }
    Start-Process -FilePath $godot -Wait -NoNewWindow -ArgumentList @(
      "--path", ".", "tools/drawcalls.tscn", "--log-file", $rel,
      "--", "--scene=$s", "--tag=$Tag")
    if (Test-Path $rel) {
      $line = Select-String -Path $rel -Pattern "DRAWCALLS mode" | Select-Object -First 1
      if ($line) { Write-Output $line.Line.Trim() } else { Write-Output "DRAWCALLS $s : NO RESULT (see $rel)" }
    } else { Write-Output "DRAWCALLS $s : NO LOG" }
  }
}
finally { Pop-Location }
