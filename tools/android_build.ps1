# Towerbound 嘅 Android 出貨 build:.aab(上 Play)+ .apk(sideload 真機測試)。
#
# 兩個檔用**同一條 upload key** 簽名。點解要同一條:sideload 嗰個 apk 唔係一個
# 「差唔多嘅版本」,佢係用嚟答「呢一份 build 喺真機上面行唔行得」呢條問題,
# 而簽名唔同 = 兩份唔同嘅 build,答到嘅嘢就冇咁 tight。
#
# 密碼由 %USERPROFILE%\keystores\towerbound-upload.credentials.env 讀出嚟,
# 經環境變數餵俾 Godot。**export_presets.cfg 由頭到尾唔會有密碼** —— 嗰個檔
# 入 repo,而一條公開咗嘅 upload key 補救唔到(見 dist\KEYSTORE_BACKUP_README.md)。
#
# 用法:  powershell -File tools\android_build.ps1 [-SkipApk]
param(
  [switch]$SkipApk,
  [string]$Godot = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe",
  [string]$Credentials = "$env:USERPROFILE\keystores\towerbound-upload.credentials.env"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root

if (-not (Test-Path $Credentials)) {
  throw "搵唔到 credentials 檔:$Credentials`n(見 dist\KEYSTORE_BACKUP_README.md)"
}
foreach ($line in Get-Content $Credentials) {
  if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
  $k, $v = $line -split '=', 2
  Set-Item -Path ("Env:" + $k.Trim()) -Value $v.Trim()
}
if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) { throw "credentials 檔冇 keystore path" }
if (-not (Test-Path $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH)) {
  throw "keystore 唔喺度:$env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH"
}
Write-Host ("keystore : " + $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH)
Write-Host ("alias    : " + $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER)

New-Item -ItemType Directory -Force -Path (Join-Path $root "dist") | Out-Null

# 兩份出貨文件嘅**正本**住喺 docs\android\(入 repo),每次 build copy 一份落
# dist\。點解唔淨係擺 dist\:dist\ 係 .gitignore 咗嘅,一 clone 落新機就冇咗
# —— 而其中一份正正就係「條 key 唔見咗會點」嘅指引。
foreach ($doc in @("KEYSTORE_BACKUP_README.md", "DEVICE_CHECKLIST.md")) {
  Copy-Item (Join-Path $root "docs\android\$doc") (Join-Path $root "dist\$doc") -Force
}

# 版本號由 export_presets.cfg 讀返出嚟,唔喺呢度寫死。
$cfgPath = Join-Path $root "export_presets.cfg"
$ver = (Select-String -Path $cfgPath -Pattern '^version/name="(.+)"' |
        Select-Object -First 1).Matches[0].Groups[1].Value
if (-not $ver) { throw "export_presets.cfg 度讀唔到 version/name" }
Write-Host ("version  : " + $ver)

# 第 24 輪加咗**第三個**版本號來源:project.godot 嘅 application/config/version。
# 設定頁讀嗰個(唔准 hardcode),而佢同兩個 preset 嘅 version/name 一旦飄開,
# 玩家就會喺一隻 1.1.0 嘅 build 入面見到「版本 1.0.1」——「只會做錯唔會報錯」
# 嘅一等公民:冇 error、冇 crash,而且淨係喺一部真機上面睇得出。
# 所以三個數喺呢度對齊,對唔上即刻死。
$projPath = Join-Path $root "project.godot"
$projVerM = Select-String -Path $projPath -Pattern '^config/version="(.+)"' | Select-Object -First 1
if (-not $projVerM) { throw "project.godot 度讀唔到 application/config/version" }
$projVer = $projVerM.Matches[0].Groups[1].Value
if ($projVer -ne $ver) {
  throw "版本號對唔上:project.godot config/version = '$projVer',export_presets.cfg version/name = '$ver'"
}
# 兩個 preset 嘅 version/name 都要係同一個(唔係淨係第一個)
$allVer = @(Select-String -Path $cfgPath -Pattern '^version/name="(.+)"' |
            ForEach-Object { $_.Matches[0].Groups[1].Value })
foreach ($v in $allVer) {
  if ($v -ne $ver) { throw "export_presets.cfg 兩個 preset 嘅 version/name 唔一致:$($allVer -join ', ')" }
}
$allCode = @(Select-String -Path $cfgPath -Pattern '^version/code=(\d+)' |
             ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
foreach ($c in $allCode) {
  if ($c -ne $allCode[0]) { throw "export_presets.cfg 兩個 preset 嘅 version/code 唔一致:$($allCode -join ', ')" }
}
Write-Host ("code     : " + $allCode[0] + "   (project.godot / 兩個 preset 三處對齊)")

# **`--export-release <preset>` 唔收輸出路徑 —— Godot 寫去 preset 自己嗰個
# `export_path`。** 即係話呢個 script 講嘅檔名同真正寫出嚟嗰個係兩件事,
# 而佢哋一唔同步就會出一隻「版本係 1.0.1、個名叫 1.0.0」嘅檔(1.0.1 嗰輪
# 真係中過)。所以開工前逐個對一次,對唔上即刻死,唔好等出完先發現。
$paths = @(Select-String -Path $cfgPath -Pattern '^export_path="(dist/.+)"' |
           ForEach-Object { $_.Matches[0].Groups[1].Value })
foreach ($want in @("dist/Towerbound-$ver.aab", "dist/Towerbound-$ver.apk")) {
  if ($paths -notcontains $want) {
    throw "export_presets.cfg 嘅 export_path 冇 '$want'。而家有:$($paths -join ', ')`n(改版本號要改 version/name、version/code **同埋** export_path)"
  }
}

$targets = @(@{ Preset = "Android"; Out = "dist\Towerbound-$ver.aab" })
if (-not $SkipApk) {
  # preset 個名冇空格唔係美觀問題:PowerShell 5.1 嘅 `Start-Process
  # -ArgumentList` 對含空格嘅參數點加引號都靠唔住(手動加會被再包一層),
  # 結果 Godot 收到嘅 preset 名淨係得第一段。冇空格就冇呢條問題。
  $targets += @{ Preset = "AndroidAPK"; Out = "dist\Towerbound-$ver.apk" }
}

foreach ($t in $targets) {
  Write-Host ""
  Write-Host ("=== export " + $t.Preset + " -> " + $t.Out + " ===")
  if (Test-Path $t.Out) { Remove-Item $t.Out -Force }
  # **唔可以**用 `& $Godot ...`。`Godot_*.exe` 係一個 GUI-subsystem 執行檔,
  # 而 PowerShell 對 GUI 程式係「開完就返」—— 唔等佢做完,`$LASTEXITCODE`
  # 亦都唔會被設。量到嘅病徵:script 一秒之內就話「aab 唔喺度,export 失敗」,
  # 而三十秒之後個 aab 靜靜雞出現咗。`Start-Process -Wait` 先至真係等。
  # (tools\run_tests.ps1 因為同一個原因用同一個做法。)
  $p = Start-Process -FilePath $Godot -NoNewWindow -PassThru -Wait `
       -ArgumentList @('--headless', '--path', '.', '--export-release', $t.Preset)
  # 讀一次 .Handle 逼 PowerShell cache 住個 process handle,.ExitCode 先讀得返
  # (run_tests.ps1 有同一句同同一段解釋)。-Wait 之下佢唔會好似嗰邊咁報
  # 全部肥佬,但一個讀唔到嘅 ExitCode 會令下面嗰句錯誤訊息印一個空白數字
  # —— 而嗰個訊息係出貨失敗嗰陣唯一嘅線索。
  $null = $p.Handle
  $code = $p.ExitCode
  $abs = Join-Path $root $t.Out
  if (-not (Test-Path $abs)) {
    throw ($t.Preset + " export 失敗:" + $t.Out + " 唔喺度 (godot exit " + $code + ")")
  }
  Write-Host ("   ok  (godot exit " + $code + ")")
}

Write-Host ""
Write-Host "=== 出貨清單 ==="
$lines = @()
foreach ($f in Get-ChildItem (Join-Path $root "dist") -Include *.aab, *.apk -Recurse) {
  $sha = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
  $mb = [math]::Round($f.Length / 1MB, 2)
  Write-Host ("{0,-30} {1,8} MB  {2}" -f $f.Name, $mb, $sha)
  $lines += ("{0}  {1}  {2} bytes" -f $sha, $f.Name, $f.Length)
}
$lines | Set-Content -Path (Join-Path $root "dist\SHA256SUMS.txt") -Encoding utf8
Pop-Location
