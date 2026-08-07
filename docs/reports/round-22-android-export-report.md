# 第 22 輪 —— Android export:清場 → 出 Play 用嘅 AAB + 測試 APK

2026-08-07。目標:出一份上得 Google Play 嘅 `.aab`、一份 sideload 得嘅 `.apk`、
一版私隱政策,同埋喺出貨之前將「乜嘢入包」由一個假設變返一個量得到嘅數。

遊戲內容(數值、關卡、美術、UI 佈局)一個字都冇改。全部改動係打包同平台適配。

---

## 0. 一句話結論

| | |
|---|---|
| `dist/Towerbound-1.0.0.aab` | **32.24 MB**,`b87273d6…cf8b579b` —— 上 Play Console 嗰個 |
| `dist/Towerbound-1.0.0.apk` | **77.99 MB**,`4322b3de…c4b40a3db` —— sideload 真機測試嗰個 |
| 玩家實際落載(arm64 / xxhdpi / zh-TW) | **32.13 MB**(bundletool 量) |
| 權限清單 | **零。** manifest 入面一個 `<uses-permission>` 都冇,連 `INTERNET` 都冇 |
| 私隱政策 | <https://jackncw.github.io/game-towerdefence/privacy.html> |
| package / 版本 | `com.jatgaming.towerbound` · versionName 1.0.0 · versionCode 1 |
| min / target SDK | 24 / **36**(2026-08-31 起 Play 新 app 嘅門檻) |

---

## Part 0 —— export 前清場

### 三類盤點

| 類 | 有乜 | 入唔入包 |
|---|---|---|
| **必要** | `project.godot` · `scenes/`(11) · `scripts/`(74) · `assets/generated{,_audio}/` · `assets/fonts/` · `i18n/` · `default_bus_layout.tres` | 入 |
| **開發用** | `docs/`(48 MB,含出街嘅 web build 同歷輪報告) · `qa/`(412 MB QA 產物) · `tools/`(222 MB,大部分係 `android_template_fix/` 嗰兩個 227 MB 原版 template apk) · `test/`(44 個測試) · `art_reference/`(3.7 MB 參考圖) · `web/` · `README.md` · 各種 `.ps1`/`.py` | 唔入 |
| **產物** | `build/`(測試 log) · `dist/`(出貨檔) · `android/`(gradle build template) · `.godot/` cache · `assets/android/`(icon 來源) | 唔入 |

### Export filter 改動

原本嘅排除表係一份**目錄名單**。呢一輪加咗一層**副檔名**規則 —— 目錄靠
`.gdignore`,而 `.gdignore` 係一個檔,刪得走;副檔名規則刪唔走。
兩個 preset(而家係三個:Android AAB / AndroidAPK / Web)用**同一條**字串:

```
qa/*, test/*, tools/*, web/*, art_reference/*, art_*, *_shots/*,
build/*, docs/*, dist/*, android/*,
scenes/Gallery.tscn, scripts/ui/Gallery.gd,
assets/generated/{monsters,towers,spells}/*, assets/android/*, icon.svg,
*.md, *.py, *.pyc, *.ps1, *.sh, *.bat, *.npy, *.jfif, *.csv, *.log, *.err,
export_presets.cfg, export_credentials.cfg,
index.png, index.icon.png, index.apple-touch-icon.png
```

新加嘅重點:`docs/*`(出街嘅 web build 自己住喺嗰度 —— 一個 48 MB 嘅自我
遞迴風險)、`dist/*`、`android/*`(gradle template,214 MB)、同埋成組副檔名。

### 孤兒資源

掃咗 144 個入包嘅 asset,逐個喺 `scripts/` `scenes/` `project.godot`
`atlas_map.json` 度搵引用。**真孤兒得一個**:

- `icon.svg`(995 bytes)—— **Godot 專案範本嗰隻藍色機械人**,由 2026-07-24
  建 project 嗰日起冇改過,遊戲畫面從來冇用過。已經加咗入排除表,慳返佢個
  `.ctex`(3,426 bytes)同 `.import`(193 bytes)。
  ⚠️ 個 995 bytes 原檔仲喺 pck 入面:`application/config/icon` 係由 exporter
  **強制**加入 pack,`exclude_filter` 攔唔到。剷唔走。

七個「睇落似孤兒」嘅係假警報,全部係**動態串接路徑**引用,唔可以刪:

| 檔 | 點樣被引用 |
|---|---|
| `atlas_battle.png` / `atlas_ui.png` | `Assets._atlas_tex()` 用 `"atlas_%s.png" % page` 砌路徑 |
| `ui/bd_{arcane,fire,ice,poison,stone}.png` | `Upgrade.gd:318` 用 `"bd_%s" % _elem()` |

**決定唔到、所以冇刪嘅**:50 個已經砌入 atlas、但個別 `.ctex` 仍然入包嘅細圖
(合共約 50 KB)。佢哋係 `Assets._atlas_tex()` 嘅 fallback —— `atlas_map.json`
一日讀唔到,成個遊戲就靠佢哋。剷咗慳 0.5%,但換嚟一個「atlas 一炒就全黑」嘅
單點故障。唔值。

### pck 大細

| | 檔案大細 | payload | 檔數 |
|---|---|---|---|
| 改動前(Pages 上嗰個) | 9,553,236 bytes | 9,290.7 KB | 393 |
| 改動後 | 9,553,300 bytes | 9,290.9 KB | 392 |

**淨 +64 bytes(+0.0007%)。** 逐 byte 交代:

```
-3,426  icon.svg 個 .ctex        ← 清場慳返
-  193  icon.svg.import          ← 清場慳返
-   82  i18n/game.csv.import     ← *.csv 排除嘅副作用
+2,970  scripts/autoload/Mobile.gdc   ← 呢一輪新加嘅 Android 適配
+   50  Mobile.gd.remap
+  368  project.binary           ← 新設定(renderer.mobile / orientation / name_localized / boot splash)
+  403  BattleHUD.gdc            ← handle_back() / hold_paused()
+   80  兩個 .translation         ← TOAST_EXIT_CONFIRM 一句
+   28  Flow.gdc,-19 Bestiary.gdc
────────
+  166 bytes payload / +64 bytes 檔案
```

即係話:清場慳咗 3.7 KB,而簡報本身要求嘅四樣嘢(Compatibility renderer、
直版鎖定、返回鍵、切背景)加返 3.9 KB。**我冇為咗贏返呢 64 bytes 去郁任何
一樣有實際作用嘅嘢**(例如剷 fallback 貼圖或者關 ICU),因為嗰啲交易嘅另一
邊係真嘅功能。

### 評估過但**冇**做嘅:剷走 `icudt_godot.dat`(4,685 KB,佔 pck 一半)

呢個係 pck 入面最大嘅單一項目,關咗 `internationalization/locale/
include_text_server_data` 就冇。**唔可以關。** 官方 export template 編譯嗰陣
**冇** `ICU_STATIC_DATA`,所以 `TextServerAdvanced` 係 runtime 由
`res://icudt_godot.dat` 載嗰份資料;冇咗佢 `u_init()` 失敗,`ubrk` 斷行迭代器
開唔到,而遊戲全部長文字(圖鑑 lore、合約說明)用緊
`AUTOWRAP_WORD_SMART` —— 中文冇斷行資料就唔識斷,直接爆版。
export log 嗰句 `Using text server data from export templates.` 就係佢喺度嘅證據。

省 4.7 MB vs 出街版中文爆版,唔使諗。

---

## Part A —— 環境

全部裝喺標準路徑,Godot 嘅 Editor Settings 已經指住(`export/android/
java_sdk_path` / `android_sdk_path`)。Jack 日後更新照呢個表去搵。

| 嘢 | 版本(實測) | 路徑 |
|---|---|---|
| Godot | `4.7.1.stable.official.a13da4feb` | `C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe` |
| JDK | Temurin **17.0.19**(`openjdk 17.0.19 2026-04-21`) | `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot` |
| sdkmanager | 12.0 | `%LOCALAPPDATA%\Android\Sdk\cmdline-tools\latest` |
| Platform | android-36(rev 2) | `%LOCALAPPDATA%\Android\Sdk\platforms` |
| Build-tools | 34.0.0 / 35.0.0 / **36.0.0** | `%LOCALAPPDATA%\Android\Sdk\build-tools` |
| Platform-tools | 37.0.0(adb) | `%LOCALAPPDATA%\Android\Sdk\platform-tools` |
| SDK licenses | 7 個全部接受咗 | `%LOCALAPPDATA%\Android\Sdk\licenses` |
| Export templates | 4.7.1.stable | `%APPDATA%\Godot\export_templates\4.7.1.stable` |
| Gradle build template | 4.7.1.stable(`compileSdk 36 / minSdk 24 / targetSdk 36`) | `android/build/`(repo 內,`.gitignore` 咗) |
| bundletool | 1.18.3 | 驗證用,唔入 repo |

JDK 同 SDK 上一輪已經裝好;呢一輪補咗 **licenses 全接受** 同
**gradle build template**(`--install-android-build-template`)。

> ⚠️ 一個舊嘢嘅交代:`%APPDATA%\Godot\export_templates\4.7.1.stable\
> android_{debug,release}.apk` 係 **2026-07-24 改過嘅版本**(`/dev/random` →
> `/dev/urandom`,見 `tools/android_template_fix/`)。呢一輪行 gradle build,
> 用嘅係 `android_source.zip` 嗰份**未改過**嘅原始碼,即係話個 entropy 修補
> **冇**入到今次出嘅 aab/apk。實機上面唔應該有影響(Linux 5.6+ 之後
> `/dev/random` 唔再阻塞),但如果真機開場吊死喺 splash,呢度就係第一個要查
> 嘅位。

---

## Part B —— Export 設定

三個 preset,兩個 Android 用**同一份**設定,只差 `export_format`:

| | Android | AndroidAPK | Web |
|---|---|---|---|
| 格式 | AAB(`export_format=1`) | APK(`export_format=0`) | — |
| 輸出 | `dist/Towerbound-1.0.0.aab` | `dist/Towerbound-1.0.0.apk` | `docs/index.html` |
| gradle build | ✔ | ✔ | — |

出貨設定(全部由 `test/MobileTest.gd` 嘅 A 段守住,改錯即刻紅):

| 項 | 值 | 喺 manifest 度驗到 |
|---|---|---|
| package | `com.jatgaming.towerbound` | ✔ |
| 顯示名 | `Towerbound` | ✔ `application-label` + **每一個** locale(含 `en` / `zh-TW`)都係 `Towerbound` |
| versionName / Code | `1.0.0` / `1` | ✔ |
| minSdk / targetSdk | 24 / 36 | ✔ |
| 架構 | `arm64-v8a` 一個 | ✔ `native-code: 'arm64-v8a'` |
| renderer | Compatibility | ✔ `meta-data org.godotengine.rendering.method = gl_compatibility` |
| 方向 | sensor portrait | ✔ `screenOrientation=12`(見下) |
| immersive | 開 | ✔ |
| 備份 | 關 | ✔ `allowBackup=false` |
| 簽名 | upload key | ✔ `apksigner verify` 過,cert SHA-256 對得上 keystore |

**顯示名點解要 `config/name_localized`**:Godot 個 Android exporter 係逐個
locale 寫 `res/values-*/godot_project_name_string.xml`。唔喺 project 設定入面
畀 `en` / `zh_TW` 嘅值,嗰兩個檔就會留低 template 嘅佔位字串
(`godot-project-name-en`)—— 即係英文機上面個 app 名會叫
「godot-project-name-en」。而家兩個都明寫。
(`config/name_localized` 淨係影響 OS 顯示嘅名,唔會影響視窗標題、
網頁 `<title>`、或者遊戲入面嘅 `MENU_TITLE`——`塔防要塞 Tower Fortress` 冇變。)

**`screenOrientation=12` 唔係 7**:Godot 將 `SCREEN_SENSOR_PORTRAIT` 對應到
Android 嘅 `userPortrait` 而唔係 `sensorPortrait`。分別係 `userPortrait`
**跟埋玩家自己嗰個「自動旋轉」開關**:自動旋轉開住就正反兩個直版都跟,
熄咗就死鎖正直版。橫版永遠唔會出現。呢個係比 `sensorPortrait` 更加尊重
玩家設定嘅行為,所以照用。

### 架構:淨係出 arm64-v8a

量過個差價:一個 arm64 嘅 `libgodot_android.so` 未壓縮 69.4 MB、喺 aab 入面
壓縮後 23.5 MB。加返 armeabi-v7a 會令 **aab 大 ~20 MB**,而因為 AAB 係
per-ABI 切開派,arm64 用家**落載一個 byte 都唔會少**——即係話成本全部落喺
repo、build time 同測試面,收益係 0 個實際玩家:
- minSdk 24 = Android 7.0(2016),而 2016 年之後出嘅機基本上全部係 arm64;
- Play 由 2019 年起要求所有 app 有 64 位版本,32 位純機早就唔喺 Play 生態入面。

要加返:`export_presets.cfg` 兩個 Android preset 嘅
`architectures/armeabi-v7a=true`,一行搞掂。

### 權限:零

`aapt2 dump badging` 同 `dump xmltree` 兩邊都確認:**manifest 入面一個
`<uses-permission>` 元素都冇**。Play 嘅 Data safety 表格可以照答「唔收集
任何資料」。

有三樣嘢睇落似權限但**唔係**,先講清楚免得 Jack 見到嚇一跳:

| 見到嘅嘢 | 實際係乜 |
|---|---|
| `<receiver android:permission="android.permission.DUMP">` | 呢個係**保護**屬性,唔係申請。佢限制「邊個可以向呢個 receiver 派廣播」(只有 shell / system)。個 receiver 係 `androidx.profileinstaller.ProfileInstallReceiver`,負責裝 baseline profile 加快冷啟動。 |
| `<profileable android:shell="true">` | 容許用 `adb shell` 嘅 profiler 貼上去睇效能。**同 `debuggable` 係兩回事** —— `android:debuggable` 喺 manifest 入面完全冇出現。Google 自己建議 release build 加呢個。 |
| `<uses-feature android:glEsVersion=0x30000>` | OpenGL ES 3.0 要求,唔係權限。 |

### 簽名

用 `keytool` 生成:RSA 4096 / SHA384withRSA / 有效期到 **2053-12-23**。

```
keystore : %USERPROFILE%\keystores\towerbound-upload.keystore
密碼     : %USERPROFILE%\keystores\towerbound-upload.credentials.env
alias    : towerbound-upload
SHA-256  : BC:6F:8B:D0:AC:1A:BC:49:9C:CF:46:32:EE:DC:49:07:66:0B:21:01:41:2D:EB:F4:3B:7C:43:77:C9:44:FA:F9
```

兩個檔都**喺 repo 以外**。`export_presets.cfg` 入面一個密碼字元都冇 ——
`tools/android_build.ps1` 讀 credentials 檔,經
`GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}` 三個環境變數餵俾 Godot。
`.gitignore` 加咗 `*.keystore` / `*.jks` / `*.credentials.env` 做保險,而
`MobileTest` 有一條斷言:兩個 Android preset 嘅所有 `keystore/*` 欄位一定要係
空字串。

**Jack 必做嘅備份動作喺 `dist/KEYSTORE_BACKUP_README.md`**,五格 checklist。
最重要嗰格係「上載第一個 aab 嗰陣開 Play App Signing」—— 開咗,upload key
唔見咗係「申請重設,麻煩但有得救」;冇開,就係「呢個 app 完咗,連修一個
閃退都出唔到」。

### Icon / splash

`tools/android_icons.py`,**冇起新美術系統**,每一 pixel 都由兩張現有圖嚟:

- `assets/generated/ui/menu_bg.png` 上半截(星 + 月,平面幾何,放大唔散)
  → adaptive **背景**層。城堡同魔晶球特登切走:adaptive 背景會俾 launcher
  平移做視差,唔可以有「擺歪咗睇得出」嘅主體。
- `assets/generated/towers/tower_1_t3.png`(箭塔 T3,已經摳好圖有 alpha)
  → adaptive **前景**層,按 **2 倍整數**放大(128 → 256px)落安全區。
  用整數倍係因為遊戲本身行 NEAREST 濾鏡,小數倍會出半 pixel 鋸齒。

出:`icon_192.png`(舊式方形)、`icon_fg_432.png` / `icon_bg_432.png`
(adaptive 兩層)、`icon_mono_432.png`(Android 13+ themed icon)、
`splash.png`(512,boot splash),全部落 `assets/android/`——嗰個資料夾有
`.gdignore`,所以 Godot 由頭到尾唔會 import 佢哋,**入唔到 pck**;
但 exporter 讀 icon 係直接由檔案系統讀,所以照用得。已經喺 apk 度驗到
(`application-icon` 指住 `res/2r.xml`,即係 adaptive icon XML)。

`dist/play-store-icon-512.png` 係 Play Console 上架表格嗰張(唔入 apk)。

**Boot splash** 順手修咗一單:project 一直用 Godot 預設(藍色機械人 + 灰底),
即係開場會見到「暖深色 Android 開場畫面 → **灰色一閃** → 暖深色遊戲第一幀」。
而家 `boot_splash/bg_color` 設成 UI.BG、`show_image=false`,三段接得埋。

---

## Part C —— Android 平台適配

全部新 code 集中喺**一個**新 autoload:`scripts/autoload/Mobile.gd`(190 行)。
其餘改動係三處掛鈎。

**呢一輪特登冇將任何邏輯收喺 `OS.has_feature("android")` 之下。** 返回鍵行
`Mobile.request_back()`,而 Android 個 `NOTIFICATION_WM_GO_BACK_REQUEST` 同
桌面嘅 Esc 兩邊都淨係叫呢一句;切背景行 `Mobile._on_paused()` /
`_on_resumed()`,而 `NOTIFICATION_APPLICATION_PAUSED` 亦都淨係叫呢兩句。
所以喺 PC headless 上面直接叫佢哋,量到嘅就係部電話上面會發生嘅嘢 ——
冇部機喺手嗰陣,呢個係唯一一種**證得到**而唔係「應該冇事」嘅寫法。

### 1. 返回鍵 / 返回手勢

Godot 預設反應係**即刻退出 app**。而家逐層退,由一個
「深度大者先問」嘅 `back_handler` group 派:

| 你喺邊 | 撳返回 |
|---|---|
| 戰鬥中 | 開暫停選單(**唔會**離開戰鬥) |
| 暫停選單開住 | 收返暫停選單,繼續打 |
| 暫停 → 圖鑑 overlay | 退返**暫停選單**(唔係彈返主選單) |
| 選關 / 商店 / 升級 / 設定 / 圖鑑 | 退返主選單 |
| 主選單 | 彈「再撳一次返回離開遊戲」;2.5 秒內再撳先真係退 |

實作細節兩個:
- **250 ms 去彈跳**。一下實體返回鍵可能同時以 GO_BACK notification **同**
  `ui_cancel` 兩種形式到埗;冇呢個窗口,「開暫停選單」會即刻被第二次呼叫
  關返,睇落好似個掣壞咗。
- `Bestiary.gd` 原本自己接 `ui_cancel` 同 `NOTIFICATION_WM_GO_BACK_REQUEST`,
  已經拆走 —— 兩邊都接嘅話一下 Esc 會行兩次 `_go_back()`。

### 2. 切去背景

`NOTIFICATION_APPLICATION_PAUSED` → 暫停 scene tree + 靜音 master bus +
`Meta.flush_pending_save()`。

`NOTIFICATION_APPLICATION_RESUMED` → **唔會**自動幫玩家取消暫停。
戰鬥畫面停喺**暫停選單**(睇得見、有解釋),選單畫面就直接解封
(冇嘢好停,唔解封等於成個 app 死咗)。理由:玩家切走嗰陣可能係接電話,
眼唔喺部機度;一返嚟就恢復戰鬥等於幫佢玩咗一段,而嗰段可能就係佢輸嗰段。

靜音還原行 `Meta.apply_audio_settings()` 而唔係 `set_bus_mute(0, false)` ——
玩家自己撳咗靜音嘅話,返嚟唔應該幫佢開返聲。(有測試守住。)

### 3. 閃退標記喺 native 唔可以誤報 ★

呢個係最容易靜靜雞出事嗰單。`Crash.gd` 靠一個「開場落、正常收場刪」嘅
marker 檔判斷上次係咪閃退,而 `_close()` 掛喺 `NOTIFICATION_WM_CLOSE_REQUEST`
/ `EXIT_TREE` / `PREDELETE`。**Android 冇 `WM_CLOSE_REQUEST`** ——
玩家由最近應用清單掃走個 app,個 process 就咁被殺,`_close()` 永遠冇機會行。
即係話**每一次正常收工都會喺下次開場報一單假閃退**。

而家 `APPLICATION_PAUSED` 就係「由呢一刻起唔算閃退」嗰條線(同網頁版
`pagehide` 一樣嘅取捨,見 `Crash.disarm()` 嘅註解),`RESUMED` 上返膛。
一單真正喺前台發生嘅閃退照樣捉得到。

### 4. 中文字型

`Flow._ready()` 原本喺非 web 平台行 `SystemFont`,`font_names` 係一串
Windows 字型名。Android 上面各廠商嘅字型清單唔一樣,而 Godot 喺 Android
亦都冇 Windows 嗰種完整 family 查詢 —— 搵唔到就成版中文出豆腐格,
**而呢種失敗喺一部冇喺手嘅機上面睇唔到,只會由玩家嚟報**。

而家 Android 行同網頁版一模一樣嗰條路:掛打包咗嘅 `NotoSansTC-Subset.ttf`
(253 KB,本來就已經為咗網頁版入咗 pack,所以 0 成本)落預設 theme 每個
font 嘅 `fallbacks` 鏈。嗰條 code path 已經喺真瀏覽器度驗過。

### 5. FPS / 省電 / 存檔 / 佈局

- FPS cap 60(省電模式 30)行 `Flow.apply_frame_cap()`,本來就係平台無關,
  `MobileTest` 加咗斷言守住兩個模式都真係郁到 `Engine.max_fps`。
- `user://` 喺 Android native 路徑係
  `/Android/data/com.jatgaming.towerbound/files/` —— **未喺真機驗過讀寫**,
  見下面「冇做到嘅嘢」。
- **1080×2400 一類解像度嘅 layout 截圖**:新工具 `tools/layout_shots.tscn`。
  同 `art_export` 嘅分別好重要 —— art_export 用一個固定 1080×1920 嘅
  SubViewport,即係佢**由定義上面就冇邊**,答唔到「20:9 會唔會爆邊」。
  呢個影嘅係 **root viewport**,連 `stretch/aspect=keep` 留低嘅黑邊一齊影,
  而且個框嘅大細係問返引擎攞(`get_final_transform()`)唔係自己計。
  六個解像度 × 三個畫面 = 18 張圖,落 `qa/screenshots/round-22-layout/`:

  | 解像度 | 1080×1920 框 | 黑邊 | |
  |---|---|---|---|
  | 1080×2400(20:9,最常見) | 全寬 | 上下各 12.6% | OK |
  | 1080×2340(19.5:9) | 全寬 | 上下各 11.1% | OK |
  | 1440×3200(QHD 20:9) | 全寬 | 上下各 10.1% | OK |
  | 720×1600(HD 20:9) | 全寬 | 上下各 10.3% | OK |
  | 1080×1920(設計比例) | 全屏 | 冇 | OK |
  | 1200×2000(5:3 平板) | 全高 | 左右各 3.2% | OK |

  零剪裁、零爆邊,HUD 頂欄同底欄喺每一個比例都完整。
  `StretchTest` 嗰七種形狀嘅數學斷言照舊綠。
- **全部音效 smoke test**:新測試 `test/AudioSweepTest.tscn`,65 個檔逐個
  播一次(簡報講 64,實際數落去係 65:3 首 BGM + 3 個 jingle + 59 個 sfx/ui)。
  結果 **65 / 65 PASS**,headless 同開窗(真 WASAPI 後端)各跑過,四次連跑
  結果一致。

  呢個測試中途改過一次做法,值得記低:第一版問
  `AudioStreamPlayer.get_playback_position()` 有冇行過,結果**間歇性報假失敗**
  —— 同一份 code 連跑四次報 65/65、63/65、63/65、62/65,而每次「壞咗」嘅
  係邊幾個都唔同。原因係嗰個位置係由音訊執行緒按 mix block 更新,而五個
  最短嘅音效(`ui_click` 55ms、三個 hit、`sfx_gold_pop`)隨時喺兩次更新之間
  已經播完。改咗用一條自己嘅 bus + `AudioEffectCapture` 抽**實際混出嚟嘅
  樣本**,問題即刻消失 —— 而且個問題問得強咗:一個解碼成功但全靜音嘅檔
  依家一樣捉得到。

  **仲差嗰半**:Android 自己個音訊後端(AAudio/OpenSL)冇量過,要真機。

---

## Part D —— 出貨

```
dist/
  Towerbound-1.0.0.aab            33,809,941 bytes (32.24 MB)
                                  b87273d6c1c06f07390999aae8ebf05078a73e2aaab7f9d063120f37cf8b579b
  Towerbound-1.0.0.apk            81,783,193 bytes (77.99 MB)
                                  4322b3deb74e2612dfc437da612c2e6f7a3d21c895d401e436b6037c4b40a3db
  SHA256SUMS.txt
  play-store-icon-512.png
  KEYSTORE_BACKUP_README.md
  DEVICE_CHECKLIST.md
```

**點解 apk 比 aab 大成倍**:`extractNativeLibs=false`(現代做法,開場唔使
解壓),所以 apk 入面個 69.4 MB `.so` 係 **stored 唔壓縮**;aab 入面同一個檔
壓到 23.5 MB,而 Play 派落機嗰陣再按裝置切。玩家實際落載 **32.13 MB**。

### 驗證

| 驗證 | 結果 |
|---|---|
| `apksigner verify --print-certs` | ✔ v2 scheme 過,signer cert SHA-256 `bc6f8bd0…` = keystore 嗰條 |
| `bundletool validate --bundle` | ✔ 過,base module 列得出 |
| `bundletool build-apks` + device-spec | ✔ 出到 `base-arm64_v8a` / `base-en` / `base-zh` / `base-xxhdpi` / `assetPackInstallTime` 五個 split |
| `bundletool get-size total` | 33,693,409 bytes(32.13 MB) |
| `aapt2 dump badging` | ✔ package / 版本 / SDK / label / arm64 / 零權限 |
| `tools/pkg_report.py`(新工具) | ✔ 見下 |

### aab / apk 內容覆核(對返 Part 0 張表)

`python tools/pkg_report.py dist/Towerbound-1.0.0.apk`:

```
assets/ 檔數  396      未壓縮 9,327.4 KB   zip 後 6,891.7 KB

組別                                  檔數        KB   點解要入包
(根) icudt_godot.dat                     1    4685.0   ICU 斷行資料,硬依賴
.godot/imported (ctex)                  78    2562.8   全部貼圖(兩張 atlas 佔 96%)
.godot/imported (sample)                65    1312.2   65 個音效/BGM,已 QOA 壓縮
scripts                                 74     347.9   全部 GDScript,已編譯 .gdc
.godot/imported (fontdata)               1     253.5   NotoSansTC subset
i18n                                     2      64.3   zh_TW / en .translation
assets                                 145      40.0   .import remap stub
(根) assets.sparsepck                    1      35.2   【平台】散裝檔索引
.godot/uid_cache.bin                     1       9.3   UID → 路徑
.godot/exported (場景)                  11       8.4   10 個場景 + audio bus
… (其餘 < 4 KB)
合計                                   396    9327.4

開發檔案 / 產物殘留掃描:命中 0 個
只喺 package(唔預期):(冇)
只喺 pck(唔預期):(冇)
遊戲內容大細:package 9,290.9 KB vs pck 9,290.9 KB(差 +0 bytes)
```

**Android 包入面嘅遊戲內容同 web pck 一個 byte 都唔差。** 唯一嘅四個額外檔
係 Android 打包自己加(`assets.sparsepck` / `_cl_` / 兩個 baseline profile),
合共 36.6 KB。零開發檔案、零 `Gallery`、零 debug 殘留
(`android:debuggable` 喺 manifest 入面完全冇出現)。

---

## Part E —— 私隱政策

`docs/privacy.html`,中英雙語,自成一頁冇外部資源,樣式跟遊戲(暖深色 + 金)。

**URL(Play Console 直接填呢條):**
<https://jackncw.github.io/game-towerdefence/privacy.html>

寫咗:離線單機、零收集/傳輸、零權限(連 `INTERNET` 都冇,所以**技術上都做唔到**
傳嘢出去)、冇廣告、冇第三方 SDK、冇內購、冇帳戶、存檔只在裝置本地、解除安裝
即刪、兒童適用、網頁版嘅 GitHub Pages access log 屬寄存平台行為(Android 版
連呢一層都冇)、聯絡 `jatgaming.info@gmail.com`。

---

## 驗證讀數

| 驗證 | 結果 |
|---|---|
| 全套 regression | **`TESTS: 43 run, 0 non-zero exit, 0 冇 verdict`**(含 SoakTest 30 轉 / 36 場戰鬥,1863s)。`AudioSweepTest` 係跑到一半先加,所以行多咗一次:**`TESTS: 1 run, 0 non-zero exit, 0 冇 verdict`** —— 合共 44 個場景全綠 |
| `test/MobileTest.tscn`(新)| **PASS fails=0**,54 條斷言 |
| Web 真瀏覽器 smoke(Playwright) | **console errors: 0**,種存檔 / 起塔 / 放魔法 / 升級 / 進化 五步全部行到,中文冇豆腐格 |
| Web build 體積 | 9,553,236 → 9,553,300 bytes(+64) |
| `apply_head_include.py --check` | head_include 係最新嘅 |
| 全畫面截圖 pixel diff(zh / en 各 68 張) | 46 / 47 張完全一樣;有差異嗰啲全部係粒子特效同怪物位置嘅逐幀 RNG(`17_cast_*`、`02b_fx`、`sheet_spell_casts`),字型、佈局、文字一個 pixel 都冇郁 |

### 截圖差異嗰 22 張,點證明佢哋唔關改動事

用一個**對照組**:同一份改咗之後嘅 code,連續再影多一套(`after-zh2`),
再同 `after-zh` 對。

| 對比 | 完全一樣 |
|---|---|
| 改動前 vs 改動後 | **46 / 68** |
| 改動後 vs 改動後(**同一份 code**) | **6 / 68** |

同一份 code 自己同自己對,一樣嘅仲少過改動前後對 —— 即係話「有差異」呢件事
根本量唔到我嘅改動,佢量緊嘅係粒子 RNG、怪物位置同幀時序(而且呢輪特登
同時跑緊 SoakTest,CPU 有壓力,飄得更加勁)。逐張人手睇過嘅兩張:
- `13_pause.png`:暫停選單本身**一個 pixel 都冇差**,差嘅係背景郁緊嘅怪同
  魔法冷卻數字。
- `01_menu.png`:兩邊都係閃退報告 overlay(SoakTest 留低嘅 marker 令
  art_export 開場彈咗佢),佈局同字型完全一致,差嘅係入面嘅時間戳同麵包屑。

字型、佈局、文字換行冇一處郁過。

---

## 冇做到嘅嘢(唔係「做咗但驗唔到」,係「冇做」)

1. **冇 adb 裝置、冇 emulator**,所以以下全部只有邏輯層面嘅證據,冇真機證據:
   - notification 到底有冇派落嚟(邏輯收到之後做乜已經有測試)
   - `user://` 喺 native 路徑嘅實際讀寫 + 殺 app 重開驗進度
   - 65 個音效喺 **Android** 音效後端播唔播得到(Windows 後端已經驗咗 65/65)
   - 觸控、發熱、實際幀率
   呢啲全部逐格寫咗落 **`dist/DEVICE_CHECKLIST.md`**,Jack 一部機行一次就補齊。
2. **Audio focus 冇用 Android `AudioManager` API**。而家做嘅係「背景 = 暫停
   scene tree + 靜音 master bus」,實際效果係切走即刻冇聲。真正嘅
   `requestAudioFocus`(例如第三方音樂 app 播緊嗰陣自動閃避)要
   `JavaClassWrapper`,而呢個遊戲冇 ducking 需求,所以冇加。
3. **Entropy 修補冇入今次個 build**(見 Part A 嘅警告框)。

---

## Jack 下一步

1. **即刻做**:睇 `dist/KEYSTORE_BACKUP_README.md`,行嗰五格 checklist。
   條 upload key 係成個 repo 入面唯一一樣唔見咗補救唔到嘅嘢。
2. **真機測試**:sideload **`dist/Towerbound-1.0.0.apk`**(唔係 .aab —— 部機
   裝唔到 aab),對住 `dist/DEVICE_CHECKLIST.md` 行一次。
   最重要嗰三格有 ★:返回鍵逐層退、切背景返嚟停喺暫停畫面、
   掃走 app 重開**冇**彈假閃退報告。
3. **上 Play Console**:
   - 上載 **`dist/Towerbound-1.0.0.aab`**
   - 上載第一個 aab 嗰陣**確認 Play App Signing 開住**
   - Store listing 個 app icon 用 `dist/play-store-icon-512.png`
   - 私隱政策填 `https://jackncw.github.io/game-towerdefence/privacy.html`
   - Data safety 表格:全部答「唔收集、唔分享」——manifest 零權限撐得住
4. 之後出新版:改 `export_presets.cfg` 兩個 Android preset 嘅
   `version/code`(**每次上載一定要加**)同 `version/name`,再
   `powershell -File tools\android_build.ps1`。
