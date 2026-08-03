param([string]$Tag = "floor")

$godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"
$root = Split-Path -Parent $PSScriptRoot
New-Item -ItemType Directory -Force -Path (Join-Path $root "qa\bench\drawcalls") | Out-Null
Push-Location $root
try {
  foreach ($h in @("none", "hud", "deco", "env", "monsters", "hud,deco,env")) {
    $rel = "qa/bench/drawcalls/$Tag-hide-$($h.Replace(',','+')).log"
    $args = @("--path", ".", "tools/drawcalls.tscn", "--log-file", $rel, "--", "--scene=peak", "--tag=$Tag/$h", "--seconds=6")
    if ($h -ne "none") { $args += "--hide=$h" }
    Start-Process -FilePath $godot -Wait -NoNewWindow -ArgumentList $args
    $line = Select-String -Path $rel -Pattern "DRAWCALLS mode" | Select-Object -First 1
    if ($line) { Write-Output $line.Line.Trim() }
  }
}
finally { Pop-Location }
