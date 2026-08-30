# 第 25 輪 —— 真機除錯:Android 版開唔到(卡死喺 splash)

**日期**:2026-08-30
**觸發**:Jack 由 Play internal testing 落載嘅 1.1.0「未能正確載入」。
**出貨**:`1.1.1` / versionCode `4`

---

## 一句話

Godot 4.7.1 Android template 入面嗰個 mbedtls 讀 **`/dev/random`** 攞
entropy。喺 kernel < 5.6 嘅 Android 機上面呢個裝置**會阻塞**,引擎啟動嗰陣
seed CTR-DRBG 就吊死喺 `read()` 度 —— 卡喺 splash、**冇 crash、冇 ANR、
logcat 一句 error 都冇**。

**唔關 AAB 事,唔關 Play 拆件事。** sideload 嘅 `.apk` 喺同一部機一模一樣壞。
第 7 輪已經搵到呢個 bug 亦都寫咗個修補,但個修補 patch 錯咗一層檔案,由
1.0.0 到 1.1.0 **一次都冇入過出貨 build**。

---

## Part A —— 部機

| | |
|---|---|
| 型號 | **HUAWEI STK-L22**(Y9 Prime 2019),`ro.product.device=HWSTK-HF` |
| Android | **10**(API 29),EMUI 12.0.0 |
| Build | `STK-L22 10.0.0.270(C636E4R6P1)` |
| **Kernel** | **Linux 4.14.116** ← 呢個數就係成單嘢嘅重心 |
| SoC / GPU | HiSilicon **Kirin 710** / ARM **Mali-G51** |
| GL | OpenGL ES **3.2**(`v1.r18p0-01rel0`),`ro.opengles.version=196610` |
| ABI | `arm64-v8a`(abilist:`arm64-v8a, armeabi-v7a, armeabi`) |
| 螢幕 | 1080 × 2340,density **480**(xxhdpi) |
| Locale | `zh-Hant-HK` |
| RAM | 3.87 GB |
| Play Store | 52.8.55-29 |

`ro.config.low_ram` 空,`android.hardware.ram.normal`。Vulkan 1.1 有,但個
遊戲行 `gl_compatibility`,用唔著。

---

## Part B —— 症狀,同 logcat 到底講咗乜

### B.1 確認部機裝住嘅係 Play 版

```
installerPackageName=com.android.vending
versionCode=3 minSdk=24 targetSdk=36   versionName=1.1.0
splits=[base, assetPackInstallTime, config.arm64_v8a, config.xxhdpi, config.zh]
apkSigningVersion=3
```

五個 split 全部落齊,冇一個少:

| split | bytes |
|---|---:|
| `base.apk` | 5,550,481 |
| `split_assetPackInstallTime.apk` | 9,723,833 |
| `split_config.arm64_v8a.apk` | 72,544,760 |
| `split_config.xxhdpi.apk` | 45,971 |
| `split_config.zh.apk` | 45,465 |

### B.2 症狀確實係乜

**卡死喺 Android 嘅 splash(箭塔 icon),永遠唔會入到遊戲。** 唔係黑屏、
唔係閃退、唔係載入到一半停 —— 個 process 一直生存,一直冇畫過第一幀。

```
$ am start -W -n com.jatgaming.towerbound/com.godot.game.GodotAppLauncher
Status: timeout
LaunchState: UNKNOWN (-1)
WaitTime: 10106
```

### B.3 logcat 關鍵段落

全個 app 嘅輸出到此為止,**最後一句之後乜都冇**:

```
16:55:40.910 19673 19673 V ActivityThread: callActivityOnCreate
16:55:40.935 19673 19673 D GodotActivity: Project command line parameters:
                                          [--xr_mode_regular, --xr-mode, off,
                                           --fullscreen, --background_color, #1c1611]
16:55:40.946 19673 19673 V GodotActivity: Creating new Godot fragment instance.
16:55:40.964 19673 19673 V Godot   : Initializing Godot plugin registry
16:55:40.966 19673 19673 V Godot   : InitEngine with params: [...]
16:55:40.992 19673 19673 V Godot   : Godot native layer initialization completed: true
16:55:40.992 19673 19673 V Godot   : Setting up native layer with params: [--xr-mode, off, --fullscreen]
                                      ← 之後永遠冇下一句
```

正常開機應該接落去嘅五句(呢一輪修好之後量到)一句都冇出現:

```
V Godot : Godot native layer setup completed
D Godot : renderingDevice: opengl3 (ProjectSettings)
I godot : Godot Engine v4.7.1.stable.official.a13da4feb
I godot : OpenGL API OpenGL ES 3.2 ... Mali-G51
V Godot : OnGodotMainLoopStarted
```

**四樣嘢冇出現過**,逐樣都係一條線索:

| 冇乜 | 講緊乜 |
|---|---|
| 冇 native crash / tombstone | 唔係 signal,唔使解 stack |
| 冇 ANR | 冇人 send input 落去,Huawei 唔會自己開 ANR |
| 冇 EGL / GL error | 根本未行到起 GL context 嗰步 |
| 冇資源載入 error | 唔係搵唔到檔 —— 搵唔到檔 Godot 會嘈 |

**「冇 error」本身就係最大條線索:呢個係一個 hang,唔係一個 failure。**

### B.4 佢卡喺邊

`am start -W` 之後 10 秒,系統打咗一句
`ActivityTaskManager: handleMessage: IDLE_TIMEOUT_MSG` —— 即係話個 activity
一直冇報 idle,系統夾硬當佢 idle。配合「`onCreate` 之後冇下一句」,結論係
**主線程喺 `GodotLib.setup()`(native `Main::setup()`)入面冇返過嚟**。

`/proc/<pid>/task/` 睇到 22 條線程,包括 `WorkerThread 0` 到 `7`。
(`wchan` / `io` / `maps` 喺 user build 上面 shell 讀唔到,所以攞唔到 syscall
級嘅直接證據 —— 呢一點下面用另一個方法補返。)

---

## Part C —— 分流:逐層洗脫嫌疑

指令入面 A/B/C/D/E 五條線,證據行落去係咁:

| 線 | 判定 | 憑乜 |
|---|---|---|
| C 即閃退 | **否** | process 一直生存,冇 tombstone |
| B 黑屏 / EGL fail | **否** | 冇任何 EGL log,未行到嗰步 |
| D 資源缺失 / AAB 拆件 | **否** | 見 C.1 |
| E 對照實驗 | **推翻咗前提** | 見 C.2 |
| **A 卡 splash 冇 error → entropy** | **就係佢** | 見 Part D |

### C.1 AAB 唔關事(D 線)

用 Python 逐個 entry 對 `dist/Towerbound-1.1.0.aab` 同
`dist/Towerbound-1.1.0.apk`:

```
aab asset entries: 394    apk asset entries: 396
--- 喺 APK 有、AAB 冇 ---
   dexopt/baseline.prof
   dexopt/baseline.profm
--- 喺 AAB 有、APK 冇 ---
   (冇)
```

多出嗰兩個係 ART baseline profile,同遊戲資源冇關。**394 個遊戲檔一個唔少**
(`assets.sparsepck`、`project.binary`、`icudt_godot.dat`、
`.godot/imported/*` 全部齊)。

而且:

| | AAB | APK | |
|---|---|---|---|
| `libgodot_android.so` | 71,110,440 B | 71,110,440 B | **SHA-256 完全一樣** `91e166de…` |
| `classes.dex` | 5,135,336 B | 5,135,336 B | **SHA-256 完全一樣** `ece0b7e9…` |

**兩份出貨檔嘅原生碼係同一份 byte。** 即係話「aab 壞 apk 好」呢件事,喺
機制上根本冇路可以發生。

### C.2 對照實驗:sideload APK 都一樣壞(E 線,必做嗰格)

移除 Play 版,`adb install -r dist/Towerbound-1.1.0.apk`(`splits=[base]`,
一個 apk,冇任何拆件):

```
Status: timeout
WaitTime: 10113
...
V Godot : Setting up native layer with params: [--xr-mode, off, --fullscreen]
                                                ← 一模一樣停喺呢度
```

畫面同 Play 版**逐個 pixel 一樣**:同一格 splash、同一個箭塔。

> **前提被推翻。** 「sideload apk 好、Play 版壞」喺呢部機唔成立。
> Jack 原話講明係「(同一 / 另一)部機」—— 大機會係另一部機,而嗰部機嘅
> kernel ≥ 5.6(見 Part D)。
>
> 呢一格係成單嘢嘅轉捩點:唔行呢個對照,跟住落去就會一直喺 bundletool /
> Play 拆件度掘,而個 bug 根本唔喺嗰度。

---

## Part D —— 根因

### D.1 機制

Godot 嘅 Android export template 入面嗰個 mbedtls 係開住
`MBEDTLS_PLATFORM_STD_DEV_RANDOM` build 嘅,即係話 `mbedtls_platform_entropy_poll`
開嘅係 **`/dev/random`**,唔係 `/dev/urandom`。

喺 **Linux 5.6 之前**,`/dev/random` 係一個**會阻塞**嘅裝置:entropy pool
唔夠就吊喺 `read()` 度等。(5.6 之後 `/dev/random` 同 `/dev/urandom` 行為
睇齊,一開機 CRNG init 完就唔再阻塞 —— 所以近幾年嘅機完全冇事。)

Godot 喺 `Main::setup()` 入面 seed 一次 CTR-DRBG。喺呢部機:

```
$ dd if=/dev/random of=/dev/null bs=1 count=32     # 32 bytes
Terminated                                          ← 15 秒都返唔到
elapsed=15s

$ dd if=/dev/urandom of=/dev/null bs=1 count=32
32 bytes copied, 0.000192 s                         ← 0.2 毫秒
```

entropy pool 嘅實測讀數(`poolsize` = 4096 bit):

```
entropy_avail 取樣:22  44  4  26  47  58  ...       ← 長期喺 4–60 之間浮
```

而個 hang 住嘅 app 自己就係抽緊 pool:launch 之前 201、20 秒之後 40;
另一次 launch 之前 112、之後 4。

**最直接嗰格證據**:開一個 `dd if=/dev/random` 落去,睇佢喺 kernel 邊度等:

```
$ ps -A | grep dd
shell  24808  ...  _random_read  S  dd
                   ^^^^^^^^^^^^ kernel wait channel
```

`_random_read` 就係 `/dev/random` 嗰個阻塞讀嘅 wait channel。

### D.2 決定性驗證:唔改任何其他嘢

攞 **`dist/Towerbound-1.1.0.apk` 本身**,喺 zip 入面原地改嗰個 STORED 嘅
`.so`(改一條 RELA relocation 嘅 addend,由 `/dev/random` 個 vaddr 改做
`/dev/urandom` 個 vaddr,檔案大細一個 byte 都冇變),修返 CRC-32,用**同一條
upload key** 重簽,裝返落**同一部機**:

```
=== entropy before launch === 26        ← 比失敗嗰幾次仲要低
Status: ok
TotalTime: 2945
...
V Godot : Godot native layer setup completed
I godot : Godot Engine v4.7.1.stable.official.a13da4feb
I godot : OpenGL API OpenGL ES 3.2 ... ARM - Mali-G51
V Godot : OnGodotMainLoopStarted
```

**2.9 秒入到主選單。** 同一個 APK、同一部機、更低嘅 entropy、只差一條
relocation。根因到此釘死。

### D.3 邊一層出事

| 層 | 有冇事 |
|---|---|
| 遊戲邏輯 / GDScript | 冇事 |
| Export 設定 | 冇事 |
| Bundle(aab)結構 | 冇事 |
| Play 拆件 / 重簽 | 冇事 |
| **Godot Android export template 嘅 native 層** | **就係呢層** |

---

## Part E —— 點解個修補冇入到 build

第 7 輪已經搵到呢個 bug,亦都寫咗 `tools/android_template_fix/patch_entropy.py`。
第 10 輪仲驗過個修補「冇甩」。但兩輪驗嘅都係**同一個唔啱嘅檔**。

`.so` 嘅身分證:

| 來源 | SHA-256 |
|---|---|
| **出貨 1.1.0 `.apk` / `.aab`** | `91e166de14c14270dfd0f83b…` |
| **`android/build/libs/release/godot-lib.template_release.aar`** | `91e166de14c14270dfd0f83b…` |
| `tools/android_template_fix/android_release_orig.apk`(**未修補原版**) | `91e166de14c14270dfd0f83b…` |
| `%APPDATA%\Godot\export_templates\4.7.1.stable\android_release.apk`(**第 7 輪修補過**) | `a1bc0580158ec6b56b174e1a…` |

**出貨嗰個 `.so` 同未修補原版逐個 byte 一樣。**

原因:`export_presets.cfg` 開咗 `gradle_build/use_gradle_build=true`。gradle
build 攞 native lib 嘅地方係 **`android/build/libs/{debug,release}/godot-lib.template_*.aar`**,
唔係 `%APPDATA%\Godot\export_templates\…\android_{debug,release}.apk`。第 7 輪
patch 咗後者 —— 一個 gradle build 由頭到尾唔會掂嘅檔。

第 22 輪報告 Part A 個警告框其實已經寫低咗呢件事(「entropy 修補冇入今次個
build」),仲寫咗「如果真機開場吊死喺 splash,呢度就係第一個要查嘅位」。
**個判斷完全啱,只係當時冇機驗。** 呢一輪部機一到,第一條線索就係佢。

順帶一提,呢個亦解釋咗點解 `patch_entropy.py` 嘅 `--verify` 一定要驗**出貨檔
本身**而唔係驗中間產物:第 7 / 10 兩輪驗嘅係一個真係改過、但根本冇上船嘅檔。

---

## Part F —— 修法

### F.1 `tools/android_template_fix/patch_entropy.py` 改寫

由「淨係食一個 `.so`」擴到食 `.so` / `.aar` / `.apk` / `.aab`,而且:

- **32-bit 都做到**。原本淨係 pack 8-byte word,ARM32 用 `.rel.dyn`(REL,
  addend 存喺原地)完全捉唔到。而家跟 ELF class 決定 pointer size,
  RELA addend + 原地 pointer word 兩路都掃。實測 release aar 四個 ABI:
  arm64-v8a 同 x86_64 各中一條 RELA,armeabi-v7a 同 x86 中原地 pointer。
- **`--verify` 模式**:唔改嘢,仲有未 patch 嘅 reference 就 exit 1。
- **idempotent**:已經 patch 咗就 `total patched: 0`,乜都唔做。
- dedupe:一條 RELA 嘅 addend 本身就係一個 pointer word,兩路會喺同一個
  offset 各中一次。唔 dedupe 就會報「2 個 reference」——而 `--verify` 個
  數字係要俾人信嘅。
- Windows console 強制 UTF-8。唔加嘅話個「修補甩咗」警告會喺 cp950 度
  `UnicodeEncodeError`,即係話**個警告本身會變成一個睇唔明嘅 traceback**。

### F.2 `tools/android_build.ps1` 加兩格閘

```
export 之前 →  python patch_entropy.py <release aar>
               python patch_entropy.py <debug aar>
export 之後 →  python patch_entropy.py <出貨 aab/apk> --verify   ← 唔乾淨就 throw
```

**兩格都要,原因唔同:**

- 前面嗰格係**做嘢**。`android/build/` 係 `.gitignore` 咗嘅,而且 Godot 一
  re-install build template 就會覆蓋返晒 —— 所以唔可以「patch 一次就算」,
  每次 build 都要行。
- 後面嗰格係**唔信自己**。patch 咗個 aar 唔代表個修補入到出貨檔:gradle 有
  cache、Godot 可能揀第二個 template、流程將來會變。第 7 輪就係死喺
  「我 patch 咗嘞」呢個假設上面。呢一格直接問**玩家部機真正會裝嘅嗰個檔**。

呢個 build 上唔上到 Play 唔會出聲、Play Console 唔會出聲、Play Protect 唔會
出聲 —— 佢係卡喺 splash 嗰種死法。所以一定要喺 build 嗰刻死。

實測新 gate 喺舊檔上面真係會紅:

```
$ python tools/android_template_fix/patch_entropy.py dist/Towerbound-1.1.0.apk --verify
  [lib/arm64-v8a/libgodot_android.so]  RELA .rela.dyn @file 0x3a7450
ENTROPY 修補甩咗:dist/Towerbound-1.1.0.apk 入面仲有 1 個 /dev/random reference。
exit=1
```

### F.3 版本

`1.1.1` / versionCode `4`,三處(`project.godot` 嘅 `config/version` + 兩個
preset 嘅 `version/name`)照舊由 `android_build.ps1` 對齊。

---

## Part G —— 真機驗證

全部喺 **同一部 STK-L22** 上面,同一個 session,冇 reboot。
「拆件」= 用 bundletool 按呢部機嘅 device spec 由 `.aab` 出 `.apks` 再裝,
即係 **Play 送落嚟嗰個一模一樣嘅形狀**:

```
splits/base-master.apk  splits/base-arm64_v8a.apk  splits/base-xxhdpi.apk
splits/base-zh.apk      asset-slices/assetPackInstallTime-master.apk
```
(對返 Play 實際裝落機嗰五個 split,一個對一個。)

| # | 裝乜 | 形狀 | entropy_avail | 結果 |
|---|---|---|---:|---|
| 1 | 1.1.0 **Play 落載** | 5 split | 56 | **吊死** (timeout 10106) |
| 2 | 1.1.0 `dist` apk | 單 apk | 450 | **吊死** (timeout 10113) |
| 3 | 1.1.0 `dist` apk | 單 apk | 201 | **吊死** (timeout 10107) |
| 4 | 1.1.0 `dist` apk | 單 apk | 112 | **吊死** |
| 5 | 1.1.0 `dist` apk | 單 apk | 266 | **吊死** |
| 6 | 1.1.0 apk **手改 entropy** | 單 apk | **26** | ✅ 2,945 ms 入主選單 |
| 7 | **1.1.1** bundletool device-spec | **5 split** | 3419 | ✅ 2,936 ms |
| 8 | **1.1.1** bundletool device-spec | **5 split** | **31 → 26**,而且有個 `dd` 喺度爭住抽 | ✅ **721 ms** |
| 9 | **1.1.1** bundletool device-spec | **5 split** | — | ✅ 2,226 ms,入到第 1 關打機 |

未修補版本 **5 次 launch、5 次吊死**,連喺 240 MB 寫入之後 pool 升到 266
都一樣。我試唔到一次令佢開到 —— 即係話喺呢部機佢係**必然**壞,唔係間唔中。

第 9 行唔淨係開到主選單:撳「開始遊戲」→ 入到第 1 關 → 拖卡起塔(金 200 →
176)→ 怪物出隊行路、血條、BOSS 倒數 24 秒、射程圈全部正常,30 秒之後
process 仲喺度,logcat 零 `godot: ERROR`。

裝落機嗰個 1.1.1 確認係:

```
versionName=1.1.1
splits=[base, assetPackInstallTime, config.arm64_v8a, config.xxhdpi, config.zh]
```

---

## Part H —— 一個順手見到、**未修**嘅嘢

開場第一格畫面係**白色**嘅系統 starting window,之後即刻轉暖深色
(量到 `(33,22,23)`,`splash_screen/background_color` 係 `#1c1611` =
`(28,22,17)`)。1.1.0 卡死嗰陣因為佢永遠停喺嗰格,所以嗰張白色 splash 睇得
好清楚;1.1.1 開得返之後佢淨係得**一格**。

`dist/DEVICE_CHECKLIST.md` 第 1 節本身就有一格係問呢件事(「冇一閃灰色」)。
**呢一輪冇修**:一格畫面嘅證據分唔開「theme 設定甩咗」定係「EMUI 自己嘅
轉場動畫」,而呢一輪嘅範圍係開唔到機。留返俾 Jack 喺 checklist 度落實。

---

## Part I —— 出貨

`dist\`:

| 檔 | 大細 | SHA-256 |
|---|---:|---|
| `Towerbound-1.1.1.aab` | 33,834,359 B (32.27 MB) | `d28c120b8629e743b5840d8bf5db510b3668ca84ae4c7c67de4c03d9ce359f8d` |
| `Towerbound-1.1.1.apk` | 81,807,609 B (78.02 MB) | `26315c7f1a5b7555bb0677bd390c1ecf943a9196fa58039ffd9d6ea82c2c4d83` |

簽名:同一條 upload key,cert SHA-256
`bc6f8bd0ac1abc499ccf4632eedc4907660b2101412debf43b7c4377c944faf9`
(對得返 `dist/KEYSTORE_BACKUP_README.md` 記低嗰個指紋)。

### Regression

```
TESTS: 48 run, 0 non-zero exit, 0 冇 verdict
```

全綠,包括 `SoakTest`(30 轉 A + 6 轉 B,1891 秒)、`MobileTest`(守出貨設定)、
`Level100CompletionTest`、`EndlessTest`。**呢一輪冇改過一行遊戲邏輯**,所以
呢個「全綠」係一個「冇整爛嘢」嘅證明,唔係一個「修好咗」嘅證明 —— 修好咗
嗰個證明喺 Part G 部真機度。

### Web build

受影響(設定頁嘅版本號由 `project.godot` 嘅 `config/version` 讀,唔准
hardcode),所以一齊出:

- `docs/index.pck` SHA-256 `0E511EC1…` → `B1E811B7…`(**真係換咗**,唔係只有
  `index.js` / `index.wasm` 冇變嗰種假 MATCH —— 第 24 輪踩過)
- pck 入面 `1.1.1` 出現 1 次、`1.1.0` 出現 0 次
- `pck_report.py`:392 個檔,冇 `test/` / `tools/` / `qa/` 殘留
- `tools/web_smoke.py`:起塔 / 放魔法 / 升級 / 進化 四個實操全過,**console
  error 0**
- `tools/web_r24_verify.py`:無盡模式三步 + 閃退報告頁冇咗 + 設定頁,
  **console error 0**;截圖 `09_settings_bottom.png` 見到「**版本 1.1.1**」

Pages 上嗰隻可落載 apk 由 `Towerbound-1.1.0.apk` 換做 `Towerbound-1.1.1.apk`
(`.gitignore` 嗰條逐檔名嘅例外一齊改)。

---

## Jack 下一步

1. **上載 `dist\Towerbound-1.1.1.aab` 去 Play Console 嘅 internal testing
   track。** versionCode 4,Play 收得。
2. Play 處理完(通常幾分鐘到半個鐘)之後,**喺同一部 Y9 Prime 更新一次**,
   開一開 —— 呢一步係最後嗰格印:上面第 7/8/9 行已經證明咗「Play 送落嚟嗰個
   形狀」開得到,但由 Play 真係派一次落嚟先算完。
3. 順手行埋 `dist\DEVICE_CHECKLIST.md`。Part H 嗰格(開場冇一閃灰 / 白)
   同返回鍵嗰三格 ★ 特別值得留意。
