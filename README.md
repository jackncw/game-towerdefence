# 塔防要塞 Tower Fortress

直向 9:16 手機塔防遊戲,Godot 4.7(Forward+)。中文(zh_TW)/ English 雙語,
美術同音效由 `tools/gen_art.py` 同 `tools/gen_audio.py` 程式生成 —— 例外係
**怪物 / 塔 / 魔法**三批,改為由 `art_reference/` 嘅 sprite sheet 摳出嚟:
60 張怪物圖(2026-08-06,`tools/monster_cutout.py`)、60 張塔圖同 41 張魔法 icon
(2026-08-07,`tools/tower_cutout.py` / `tools/magic_cutout.py`)。三個工具都係
`--install` 先寫入 assets。

出街版本:**<https://jackncw.github.io/game-towerdefence/>**
(GitHub Pages,由 `main` branch 嘅 `/docs` 資料夾 serve。)

Android 出貨名 **Towerbound**(`com.jatgaming.towerbound`)——
[私隱政策](https://jackncw.github.io/game-towerdefence/privacy.html) ·
出 aab/apk 見下面「點樣 build Android 版」。

---

## 資料夾結構

### 遊戲本體(會入 build)

| 路徑 | 係乜 |
|---|---|
| `project.godot` | Godot 專案設定、autoload 名單、翻譯註冊 |
| `scenes/` | 11 個畫面場景(MainMenu / Battle / Shop / Upgrade …) |
| `scripts/autoload/` | 8 個 autoload:`Crash` `GameData` `Assets` `Meta` `Flow` `Audio` `Web` `Mobile` |
| `scripts/battle/` | 戰鬥邏輯(塔、怪、子彈、魔法、波次) |
| `scripts/ui/` | 各畫面嘅 UI 控制 |
| `assets/generated/` | 程式生成嘅美術(452 個檔) |
| `assets/generated_audio/` | 程式生成嘅音效(130 個檔) |
| `assets/fonts/` | `NotoSansTC-Subset.ttf` — 由 `tools/subset_font.py` subset 出嚟 |
| `i18n/game.csv` | 雙語字串,Godot importer 編譯做 `.translation` |
| `default_bus_layout.tres` | audio bus |
| `icon.svg` | Godot 專案範本嗰隻藍色機械人,遊戲畫面從來冇用過。`export_presets.cfg` 已經隔走佢個 import(慳返 3.3 KB 嘅 `.ctex`),但 exporter 會照塞返 995 bytes 嘅原檔入 pck —— `application/config/icon` 係由 exporter 強制加,exclude_filter 攔唔到 |

**平衡數值全部喺 `scripts/autoload/GameData.gd`。**

### 唔會入 build

| 路徑 | 係乜 |
|---|---|
| `docs/index.*` | **出街嘅 web build。呢啲檔案就係 GitHub Pages serve 緊嗰個網站,唔好手動郁。** |
| `docs/reports/` | 歷輪更新報告(`round-05` … `round-12`) |
| `docs/design/` | 設計文件同決策紀錄:`CONTRACT.md`(美術/資料契約)、`BALANCE_CHANGELOG.md`(每次平衡改動嘅 before/after + 理由)、各輪 design / plan |
| `test/` | 46 個 headless 自動測試場景 |
| `tools/` | 開發工具腳本(見下) |
| `web/` | web build 嘅 `head_include` 原始碼(JS/CSS) |
| `art_reference/` | Jack 提供嘅美術參考圖。**只准睇唔准抄像素**,見 `docs/design/CONTRACT.md` |
| `qa/` | 所有 QA 產物,唔入 repo(見下) |
| `build/` | 測試 log 同其他 build 中間產物,唔入 repo |
| `dist/` | Android 出貨檔(aab / apk / keystore README / 真機 checklist),唔入 repo |
| `android/` | Godot 裝落嚟嘅 gradle build template,唔入 repo |
| `assets/android/` | launcher / adaptive icon + splash。**有 `.gdignore`** —— export 嗰陣 exporter 直接由檔案系統讀,所以入唔到 pck |

`qa/`、`art_reference/`、`docs/`、`build/`、`dist/`、`assets/android/` 各有一個 `.gdignore`:Godot 連 import
都唔會 import 佢哋,所以呢啲檔案**結構上冇可能**入到遊戲 build 度。
(第九輪試過 50 MB QA 截圖被打包入 web build,靠人手維護排除表係唔夠嘅。)

### QA 產物(本機,`.gitignore` 咗)

```
qa/
  screenshots/       每輪嘅自查截圖,一輪一個資料夾(round-03 … round-12)
  bench/
    sim/             BalanceSim 平衡模擬輸出
    perf/            perf3x / spellbench 效能量度
    crash/           閃退證物(crash witness、logcat、jdb dump)
    tables/          tier 曲線表
    runlogs/         art_export / web export / import 嘅執行 log
```

---

## 點樣 build web 版

```powershell
$GODOT = "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe"

# 1. 將 web/head_include.{js,css} 壓平入 export_presets.cfg(唔跑就會用舊嗰段)
python tools/apply_head_include.py

# 2. export 落 docs/ —— 呢個路徑就係 GitHub Pages 嘅 serve 路徑
& $GODOT --headless --path . --export-release "Web" docs/index.html

# 3. 睇下 pck 入面有冇唔應該入嘅嘢(QA 截圖、test、tools)
python tools/pck_report.py docs/index.pck

# 4. 喺真瀏覽器影返一套圖驗證(要 playwright + chromium)
python tools/web_shots.py --dir docs --out qa/screenshots/round-NN-web
```

`git push` 之後 GitHub Pages 會自動更新。**`export_path` 一定要係
`docs/index.html`** —— 寫漏就會喺 project root 掉一份 38 MB 嘅垃圾,而出街嗰個
網站唔會更新。

---

## 點樣 build Android 版

```powershell
powershell -File tools\android_build.ps1          # 出 aab + apk
powershell -File tools\android_build.ps1 -SkipApk # 淨係出 aab
```

出嚟嘅嘢喺 `dist\`(`.gitignore` 咗):

| 檔 | 做乜 |
|---|---|
| `Towerbound-<版本>.aab` | **上 Play Console 嗰個。** 部機裝唔到。版本號由 `export_presets.cfg` 嘅 `version/name` 讀返出嚟,唔喺 script 度寫死。 |
| `Towerbound-<版本>.apk` | sideload 真機測試用。同一條 key 簽。 |
| `SHA256SUMS.txt` | 上面兩個檔嘅 SHA-256 |
| `play-store-icon-512.png` | Play Console 上架表格要嗰張 512×512 |
| `KEYSTORE_BACKUP_README.md` | **Jack 一定要睇。** 條 upload key 唔見咗會點、要備份去邊 |
| `DEVICE_CHECKLIST.md` | 真機測試逐格清單 |

最後兩份嘅**正本**喺 `docs/android/`(入 repo),build script 每次 copy 一份落
`dist\` —— `dist\` 係 `.gitignore` 咗嘅,一 clone 落新機就會冇咗,而其中一份
正正就係「條 key 唔見咗會點」嘅指引。

簽名靠三個環境變數(`GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` /
`_PASSWORD`),由 `%USERPROFILE%\keystores\towerbound-upload.credentials.env`
讀。**`export_presets.cfg` 入面一個密碼字元都冇**,keystore 同密碼兩個檔都住喺
repo 以外。

環境要求(全部已裝,路徑寫喺 Godot 嘅 Editor Settings):

| 嘢 | 版本 | 路徑 |
|---|---|---|
| JDK | Temurin 17.0.19 | `C:\Program Files\Eclipse Adoptium\jdk-17.0.19.10-hotspot` |
| Android SDK | platform 36 / build-tools 36.0.0 / platform-tools 37 | `%LOCALAPPDATA%\Android\Sdk` |
| Export templates | 4.7.1.stable | `%APPDATA%\Godot\export_templates\4.7.1.stable` |
| Gradle build template | 4.7.1.stable | `android/build/`(`.gitignore` 咗,用 `--install-android-build-template` 重裝) |

Android 專項行為(返回鍵、切背景、閃退標記)喺
`scripts/autoload/Mobile.gd`,由 `test/MobileTest.tscn` 守住。
Icon / splash 由 `tools/android_icons.py` 用**現有遊戲美術**砌出嚟,
輸出落 `assets/android/`(有 `.gdignore`,所以入唔到 pck)。

---

## 工具腳本

| 腳本 | 用法 |
|---|---|
| `tools/run_tests.ps1` | `powershell -File tools/run_tests.ps1 [-Only SoakTest] [-SoakRounds 30]` — 跑晒 `test/` 每個場景,一個測試一個 process,log 落 `build/testlogs/` |
| `tools/gen_art.py` | 重新生成 `assets/generated/` 美術(怪物除外)。`--atlas-only` = 淨係重出 atlas |
| `tools/monster_cutout.py` | 由 `art_reference/monster/*.jfif` 摳出 60 張怪物 sprite(`--install` 寫入 assets) |
| `tools/monster_qa.py` / `monster_compare.py` | 摳圖驗收:邊緣殘底色掃描 / 接觸表 / 新舊同尺寸對照 |
| `tools/tower_cutout.py` | 由 `art_reference/tower/*.jfif` 摳出 60 張塔 sprite(`--measure` 只量度、`--install` 寫入 assets) |
| `tools/tower_qa.py` | 塔 / 魔法摳圖驗收:`--check` 邊緣掃描、`--sheet` 接觸表、`--zoom` 放大、`--ground` 接地線對齊圖 |
| `tools/tower_probe.py` | 開工前量 sheet 嘅底色集合 / 格線 / baked-in 文字帶 |
| `tools/magic_cutout.py` | 由 `art_reference/magic/magic.jfif` 切出魔法 icon;對唔到嘅格留舊圖並印待補清單 |
| `tools/tower_r20_shots.tscn` | 第 20 輪塔 / 魔法美術嘅專用截圖 harness(要開窗) |
| `tools/web_smoke.py` | 真瀏覽器行 web build:起塔 / 升級 / 進化 / 放魔法各一次 + 收 console(先 `python -m http.server 8765 --directory docs`) |
| `tools/gen_audio.py` | 重新生成 `assets/generated_audio/` 全部音效 |
| `tools/art_export.tscn` | `& $GODOT --path . tools/art_export.tscn -- --out=round-NN-zh --locale=zh_TW` — 影晒每個畫面自查。輸出**永遠**落 `qa/screenshots/` 之下 |
| `tools/heal_shots.tscn` | 治療特效專項截圖 |
| `tools/walkthrough.tscn` | 由頭打到尾嘅過關錄影截圖 |
| `tools/subset_font.py` | 由完整 Noto Sans TC subset 出遊戲用嘅字型 |
| `tools/font_chars.py` | 掃全 project 用到嘅字,餵俾 `subset_font.py` |
| `tools/i18n_merge.py` | 合併翻譯 CSV |
| `tools/apply_head_include.py` | `--check` 可以淨係驗證 `.cfg` 有冇落後 |
| `tools/pck_report.py` | 拆開 `.pck` 睇入面有咩、幾大 |
| `tools/android_build.ps1` | 出簽好名嘅 `.aab` + `.apk` 落 `dist\`,順手出 SHA-256 |
| `tools/layout_shots.tscn` | 喺 6 個真機解像度嘅**視窗**入面影圖(連黑邊),答「20:9 會唔會爆邊」——`art_export` 用固定 SubViewport,答唔到呢條 |
| `tools/pkg_report.py` | 拆開 `.apk`/`.aab` 睇 `assets/` 有乜、掃開發檔案殘留、逐檔對返 web 嘅 pck |
| `tools/android_icons.py` | 用現有遊戲美術砌 launcher / adaptive icon + splash + Play Store 512 |
| `tools/web_heap_probe.py` | 量 web build 嘅記憶體用量 |
| `tools/asset_sheet.py` / `mon_sheet.py` / `mon_deliverables.py` | 砌 contact sheet,一次 Read 睇晒全部 sprite |
| `test/BalanceSim.tscn` | `& $GODOT --headless --path . res://test/BalanceSim.tscn -- --towers` — 平衡模擬 |

---

## 慣例

- **每輪報告**擺 `docs/reports/round-NN-*.md`;設計/計劃擺 `docs/design/`。
  用 superpowers skill 嗰啲流程預設會寫落 `docs/superpowers/`,收工前記得
  搬入返上面兩個資料夾。
- **平衡改動**一定要喺 `docs/design/BALANCE_CHANGELOG.md` 寫低 before/after、
  理由同還原方法。
- **QA 截圖同 log** 一律落 `qa/`,唔好留喺 project root。
