param([string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe")
$ErrorActionPreference = "Stop"
$new  = "C:\Users\User\Desktop\Jack\AI\Claude\016 game - tower defence"
$base = "C:\Users\User\AppData\Local\Temp\claude\tf_baseline"
$out  = Join-Path $new "qa\bench\gate\r24_ab"
$units = @()
foreach ($arm in @(@{n="base"; p=$base}, @{n="new"; p=$new})) {
  foreach ($a in @("A2","A3")) {
    for ($s = 0; $s -lt 4; $s++) {
      $units += [pscustomobject]@{
        Name = ("{0}_{1}_s{2}" -f $arm.n, $a, $s)
        Path = $arm.p
        Args = @("--mode=sweep", "--arch=$a", "--seeds=1", "--seed0=$s", "--nosave")
      }
    }
  }
}
$running = @()
$queue = New-Object System.Collections.Queue
foreach ($u in $units) { $queue.Enqueue($u) | Out-Null }
$start = Get-Date
while ($queue.Count -gt 0 -or $running.Count -gt 0) {
  while ($running.Count -lt 16 -and $queue.Count -gt 0) {
    $u = $queue.Dequeue()
    $f = Join-Path $out ($u.Name + ".txt")
    $e = Join-Path $out ($u.Name + ".err.txt")
    Push-Location $u.Path
    $p = Start-Process -FilePath $Godot -ArgumentList (@("--headless","--path",".","res://test/GateSim.tscn","--") + $u.Args) `
         -NoNewWindow -PassThru -RedirectStandardOutput $f -RedirectStandardError $e
    Pop-Location
    $null = $p.Handle
    $running += [pscustomobject]@{ U = $u; P = $p }
    Write-Host ("  -> " + $u.Name)
  }
  Start-Sleep -Seconds 10
  $still = @()
  foreach ($r in $running) { if ($r.P.HasExited) { Write-Host ("  <- " + $r.U.Name) } else { $still += $r } }
  $running = $still
}
Write-Host ("AB DONE " + [math]::Round(((Get-Date)-$start).TotalMinutes,1) + " min")
