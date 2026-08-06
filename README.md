# 塔防要塞 Tower Fortress

直向 9:16 手機塔防遊戲,Godot 4.7(Forward+)。中文(zh_TW)/ English 雙語,
美術同音效由 `tools/gen_art.py` 同 `tools/gen_audio.py` 程式生成 —— 唯一例外係
60 張怪物圖,2026-08-06 起改為由 `art_reference/monster/` 嘅 sprite sheet 摳出嚟
(`tools/monster_cutout.py`,`--install` 寫入 assets)。

出街版本:**<https://jackncw.github.io/game-towerdefence/>**
(GitHub Pages,由 `main` branch 嘅 `/docs` 資料夾 serve。)

---

## 資料夾結構

### 遊戲本體(會入 build)

| 路徑 | 係乜 |
|---|---|
| `project.godot` | Godot 專案設定、autoload 名單、翻譯註冊 |
| `scenes/` | 11 個畫面場景(MainMenu / Battle / Shop / Upgrade …) |
| `scripts/autoload/` | 7 個 autoload:`Crash` `GameData` `Assets` `Meta` `Flow` `Audio` `Web` |
| `scripts/battle/` | 戰鬥邏輯(塔、怪、子彈、魔法、波次) |
| `scripts/ui/` | 各畫面嘅 UI 控制 |
| `assets/generated/` | 程式生成嘅美術(452 個檔) |
| `assets/generated_audio/` | 程式生成嘅音效(130 個檔) |
| `assets/fonts/` | `NotoSansTC-Subset.ttf` — 由 `tools/subset_font.py` subset 出嚟 |
| `i18n/game.csv` | 雙語字串,Godot importer 編譯做 `.translation` |
| `default_bus_layout.tres`, `icon.svg` | audio bus、app icon |

**平衡數值全部喺 `scripts/autoload/GameData.gd`。**

### 唔會入 build

| 路徑 | 係乜 |
|---|---|
| `docs/index.*` | **出街嘅 web build。呢啲檔案就係 GitHub Pages serve 緊嗰個網站,唔好手動郁。** |
| `docs/reports/` | 歷輪更新報告(`round-05` … `round-12`) |
| `docs/design/` | 設計文件同決策紀錄:`CONTRACT.md`(美術/資料契約)、`BALANCE_CHANGELOG.md`(每次平衡改動嘅 before/after + 理由)、各輪 design / plan |
| `test/` | 29 個 headless 自動測試場景 |
| `tools/` | 開發工具腳本(見下) |
| `web/` | web build 嘅 `head_include` 原始碼(JS/CSS) |
| `art_reference/` | Jack 提供嘅美術參考圖。**只准睇唔准抄像素**,見 `docs/design/CONTRACT.md` |
| `qa/` | 所有 QA 產物,唔入 repo(見下) |
| `build/` | APK 同其他 build 輸出,唔入 repo |

`qa/`、`art_reference/`、`docs/`、`build/` 各有一個 `.gdignore`:Godot 連 import
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

Android:`& $GODOT --headless --path . --export-release "Android" build/TowerFortress.apk`

---

## 工具腳本

| 腳本 | 用法 |
|---|---|
| `tools/run_tests.ps1` | `powershell -File tools/run_tests.ps1 [-Only SoakTest] [-SoakRounds 30]` — 跑晒 `test/` 每個場景,一個測試一個 process,log 落 `build/testlogs/` |
| `tools/gen_art.py` | 重新生成 `assets/generated/` 美術(怪物除外)。`--atlas-only` = 淨係重出 atlas |
| `tools/monster_cutout.py` | 由 `art_reference/monster/*.jfif` 摳出 60 張怪物 sprite(`--install` 寫入 assets) |
| `tools/monster_qa.py` / `monster_compare.py` | 摳圖驗收:邊緣殘底色掃描 / 接觸表 / 新舊同尺寸對照 |
| `tools/gen_audio.py` | 重新生成 `assets/generated_audio/` 全部音效 |
| `tools/art_export.tscn` | `& $GODOT --path . tools/art_export.tscn -- --out=round-NN-zh --locale=zh_TW` — 影晒每個畫面自查。輸出**永遠**落 `qa/screenshots/` 之下 |
| `tools/heal_shots.tscn` | 治療特效專項截圖 |
| `tools/walkthrough.tscn` | 由頭打到尾嘅過關錄影截圖 |
| `tools/subset_font.py` | 由完整 Noto Sans TC subset 出遊戲用嘅字型 |
| `tools/font_chars.py` | 掃全 project 用到嘅字,餵俾 `subset_font.py` |
| `tools/i18n_merge.py` | 合併翻譯 CSV |
| `tools/apply_head_include.py` | `--check` 可以淨係驗證 `.cfg` 有冇落後 |
| `tools/pck_report.py` | 拆開 `.pck` 睇入面有咩、幾大 |
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
