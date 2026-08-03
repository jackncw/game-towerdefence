# 第十一輪 — iOS Web 閃退 + 亂碼 + 進化數值/面板重制 + 圖鑑擴充

日期:2026-08-02 · tag `pre-round11` = 呢一輪之前嘅狀態

| 階段 | commit | 一句話 |
|---|---|---|
| B | `728e1fe` | 補返 149 個缺字入 bundled web 字型,加一條守門測試 |
| A | `3437a0c` | Web pack 瘦身 + iOS 記憶體防線 + 閃退報告畫面 |
| C | `1b424e0` | 升級介面每一個數字 = 引擎真正用緊嗰個(4680 項對數) |
| D | `4d67ee6` | 塔同魔法各有各嘅逐階倍率 + 效能面板跨三階刻度 |
| E | `e375e7d` | 拎走 5x,速度循環變 0.5x → 1x → 3x |
| F | `3b3f33c` | 圖鑑加塔頁同魔法頁 |
| G | `3f4f04c` | 全套測試 + web 重出 + 真瀏覽器驗證 + 部署 |

B 排喺 A 前面係因為佢先做完;letter 順序係 brief 嘅,唔係 commit 嘅。

---

## B — GitHub Pages 亂碼:root cause

**係豆腐方格(缺字),唔係 charset,亦都唔係 i18n key 露出。**

`docs/index.html` 一直有 `<meta charset="utf-8">`,而 `I18nTest` 由第九輪起就
已經守住「每條 key 喺兩種語言都解得到」。真正嘅成因喺字型:

`tools/subset_font.py` 舊版由**整份 .gd 原始碼**收字元 —— 連註解都收。呢個
codebase 嘅註解全部係粵語,所以嗰個「要保留嘅字元集」入面大部分係註解字,
而真正會上畫嘅字(i18n CSV 入面嗰啲)反而被埋喺噪音入面。量到嘅缺口係
**149 個真係會上畫嘅字元**。

點解躲得過十輪測試同無數次截圖:

* 桌面版行 `SystemFont` + `allow_system_fallback`,任何 subset 冇嘅字都由
  Microsoft JhengHei 補返。
* 網頁版**冇任何系統字型**,補唔到,直接畫豆腐。

即係話 desktop 截圖永遠乾淨,而 bug 只存在於出街嗰個版本。

**修法**:`tools/font_chars.py` 重新定義「會上畫嘅字元」—— i18n CSV 整份 +
`.gd`/`.tscn` 嘅**字串字面值**(剝走註解)+ 執行時砌出嚟嘅字元。subset 由
1046 glyph 變 1149 glyph(303 KB → 325 KB)。

**守門**:`I18nTest` 加咗一條 —— 兩種語言、每一條 key、每一個字元,問
bundled font 有冇 glyph。呢條 assertion 而家會爆,唔使等玩家發現。

---

## A — Web build 瘦身 + iOS 專項

### 1. Pack 內容(量出嚟,唔係假設)

新工具 `tools/pck_report.py` 讀 `.pck` 目錄,列出入面實際有乜。

| | 檔案數 | payload |
|---|---|---|
| 之前(出咗街嗰個 `docs/index.pck`) | 806 | 7193.1 KB |
| 之後 | 684 | 6819.3 KB |
| 差 | **−122** | **−373.8 KB (−5.2%)** |

割走咗嘅嘢,全部係一路跟住出街嘅:

| | 檔案 | 大細 |
|---|---|---|
| `test/`(包括 40 KB 嘅 BalanceSim) | 75 | 192.9 KB |
| `tools/`(art_export、gen_art…) | 15 | 37.7 KB |
| `tests/` | 3 | 6.4 KB |
| `godot_setting.jpg`(一張 Godot 設定視窗嘅截圖) | 1 | 146.3 KB |
| 對應嘅 `.scn` remap | ~28 | ~20 KB |

### 2. `icudt_godot.dat` — 4688 KB,而佢拎唔走

佢係 pack 嘅 **69%**,所以我試過拎走,而結論係**做唔到**,唔係「唔想做」:

* 設 `internationalization/locale/include_text_server_data=false` 之後重新匯出,
  匯出器照樣印 `Using text server data from export templates.`,而個檔照樣入 pack。
* 為咗確定唔係「入咗但冇用」,我用 Windows export template 起咗兩個版本
  (設定 true / false),各自量中英文喺 500px 闊之下斷幾多行:
  兩邊都係 CJK 3 行 / EN 4 行,`FEATURE_BREAK_ITERATORS` 兩邊都係 `true`。
  即係話呢個設定喺 4.7 根本冇被讀,ICU data 由 export template 無條件提供。

所以佢係引擎嘅,唔係我哋嘅。留低,而且記低咗點驗嘅。

### 3. iOS Safari 專項

| 做咗乜 | 點解 |
|---|---|
| `devicePixelRatio` 封頂 2 | `canvasResizePolicy=2` 用 DPR 定 backing store。iPhone DPR=3:一個 393×852 嘅視窗要 1179×2556 = **3.01M pixel**,色彩 + 深度 = **約 24 MB**。封頂 2 之下係 1.34M pixel ≈ **10.7 MB**,慳 **13.4 MB**。pixel art 用 NEAREST 放大,2x 同 3x 睇落一樣。 |
| 單線程 web export | `variant/thread_support=false` 本來就已經係(GitHub Pages 冇 COOP/COEP header,threads 版行唔正常)—— 呢一輪核實咗,冇改。 |
| WebGL context lost | 接住 `webglcontextlost`,喺**頁面自己嘅 DOM** 彈「畫面資源被系統回收」+ 重新載入掣。一定要係 DOM:context 一冇咗,Godot 連「我死咗」呢句都畫唔出。 |
| `visibilitychange` / `pagehide` | 暫停 scene tree + 靜音 master bus。返嚟還原返**玩家自己嗰個**暫停狀態同靜音設定,唔會幫佢取消咗暫停或者開返聲。 |
| 池上限收窄 | 網頁版 fx / 傷害數字 / 怪物池全部行桌面預算嘅 55%(`Battle.WEB_BUDGET`)。fx 硬上限 400 → 220 個同時存在嘅節點。桌面同 Android 一個字都冇變。 |

DPR 封頂一定要喺 `index.js` 行之前生效,所以佢住喺 `html/head_include` 而唔係
GDScript。可讀嘅原始碼喺 `web/head_include.js`,`tools/apply_head_include.py`
負責壓平同寫入 `.cfg`(嗰行係產物)。`StretchTest` 加咗四條 assertion 守住
呢段嘢仲喺 `.cfg` 入面。

### 4. 閃退證物行到出嚟畀人睇

`user://` 喺 iOS 網頁版收喺 **IndexedDB** 入面 —— 唔係資料夾,係瀏覽器內部
資料庫。玩家喺一部 iPhone 上面掘唔到。一份寫咗但冇人讀得到嘅記錄同冇寫係
一樣嘅。

所以:

* 麵包屑環形 buffer 每 **30 真實秒**加一個記憶體採樣
  (`static` / `video` / object / node / fps)。一單 OOM 死法唔會留低任何
  stack trace —— 個 process 係俾系統由外面熄咗 —— 所以死之前嗰條記憶體曲線
  就係唯一嘅證物。
* 開機偵測到上次係閃退 → 主選單彈一個報告畫面:裝置 / 引擎 / session、
  記憶體趨勢摺線(第一點 → 最後一點,最高點)、成串麵包屑、**「複製報告」**
  同「繼續遊戲」兩粒掣。

---

## C — 升級介面顯示錯:掃出 552 個

**Bug**:`Upgrade._now_next()` 叫 `GameData.effective_stats(def, levels)` 冇傳
`tier`,所以 tier 參數食咗預設值 **1**。即係話一件已經進化嘅嘢,升級欄報返嘅
係「如果佢仲係第一階」嗰個數。

用戶報上嚟嗰個實例:劇毒瘴氣「每秒毒傷」tier 1 十五級 = 130(正確),進化上
tier 2、六條軸歸零之後,升級欄寫住 **25 → 32**,而引擎實際用緊 **400 → 512**。
差 16 倍,而且方向係**倒退** —— 睇落好似進化整衰咗件嘢。

**點解冇人手測試捉得到**:呢個錯只喺已經進化嘅嘢上面出現,而進化要六條軸課滿
15 級 + 6000 魔晶。冇一個人手流程會行到嗰個狀態。

**自動化對數**(`test/StatDisplayTest.gd`):

* 20 塔 × 6 軸 + 15 魔法 × 3 軸,每件嘢 × 3 個 tier × 4 個等級向量
* 兩邊由**完全唔同嘅路**入:
  * 顯示側 = `Upgrade.now_next_values()`(UI 唯一嘅出數點)
  * 引擎側 = `Meta.tower_stats()` / `spell_stats()`(`Tower.gd` / `Spells.gd` 真正讀嗰個)
* 「下一級」嗰半邊係**真係買咗**再問引擎,唔係再計一次公式 —— 咁先分得出
  「公式啱」同「UI 啱」
* 合共 **4680 個數字**逐項對數

**量到嘅結果:用第十輪嗰條路,4680 個入面有 552 個係錯嘅。**(而家 0 個。)

順手一齊修:`fmt_value()` 變 static 而且四位數以上唔再拖個冇意義嘅小數點
(tier 3 之後成日出「2560.0」)。

---

## D — 三階曲線 + 效能面板

### 曲線:一個倍率服侍唔到兩邊

設計目標:**tier N+1 基礎 ≈ tier N 滿課 × 1.15**。呢個比例由兩樣嘢決定,而
只有一樣係揀嘅:`R`(課滿 / 基礎,由 ups 表決定)同 `STEP`(逐階倍率)。
`tier N+1 基礎 / tier N 滿課 = STEP / R`。

`tools/tier_curve.gd` 量咗成個分佈:

| | 件數 | R 最低 | R 中位 | R 最高 | 舊 STEP | 舊跳幅 | 新 STEP | 新跳幅 |
|---|---|---|---|---|---|---|---|---|
| 塔(六條軸) | 18 | 2.29 | **12.75** | 51.00 | 16 | 1.26 | **14.66** | **1.15** |
| 魔法(三條軸) | 10 | 4.10 | **4.88** | 6.00 | 16 | **3.27** | **5.64** | **1.16** |

魔法只得三條軸,而其中一條通常係冷卻(唔係輸出),所以佢哋課到盡都只係基礎值
嘅五倍左右。同一個 16 打落去,一個 tier 2 魔法**一出世就已經係佢 tier 1 課足
十五級嘅三倍幾** —— 之前課嗰十五級一鋪清袋,而「進化之後仲有嘢追」呢句話喺
魔法嗰邊由頭到尾都唔成立。

新倍率係由量出嚟嗰個中位數乘 1.15 得返,唔係揀:

```
TIER_JUMP       = 1.15
TOWER_AXIS_GAIN = 12.75 (量)  ->  塔  : 1, 14.66, 214.9
SPELL_AXIS_GAIN =  4.90 (量)  ->  魔法: 1,  5.64,  31.8
```

用邊一個由 def 自己嘅 `kind` 決定,唔使呼叫端記得傳。

### 驗證:`BalanceSim --evolve` 第 1-40 關(專精玩家)

| | 目標 | 量到 |
|---|---|---|
| tier 2 出現 | 第 20-26 關 | **第 24 關** |
| tier 3 出現 | 第 34-40 關 | **第 38 關** |
| 通關 | — | 39 / 40(一次過 38 關,95%) |
| 平均最深推進 1-20 | — | 9% |
| 平均最深推進 21-30 | 唔可以塌落 30% 以下 | **35%** |
| 平均最深推進 31-40 | 同上 | **31%** |

第 1-20 關嗰個 9% 唔係呢一輪造成 —— 嗰段路玩家全程 tier 1,倍率一個字都冇掂
到佢。佢係呢個 harness 本身嘅性質(專精玩家 + 塔數上限),第十輪已經係咁。
真正被呢一輪郁到嘅係第 21 關之後,而嗰兩段都留喺 30% 以上。

`EvolveTest` 嘅 D3 由「大過 1.1 就得」改成一條**帶**(1.05 – 1.35),而且加咗
魔法嗰半邊。舊嗰條單邊斷言擋唔到 3.27 倍嗰種跳幅 —— 而嗰個正正就係出咗事嗰邊。

### 面板:跨三階統一刻度

舊刻度嘅上限係「全部塔 tier 1 基礎值入面最大嗰個」,所以一座塔課到 tier 1
十級就已經滿格,一進化成塊面板頂爆。

新刻度:**bar 總長 = 該數值喺同類物件「tier 3 六軸滿課」嘅全遊戲上限**,而且
係**對數**。對數唔係美化 —— tier 3 滿課係 tier 1 基礎嘅三千幾倍,線性之下頭
兩階加埋畫唔到一個 pixel,而「仲有兩段路」正正就係呢條 bar 要講嘅嘢。每一階
本身就係一個固定倍率,而對數就係「將倍率變成距離」嗰個轉換,所以三段分區喺
對數之下自然係差唔多闊嘅三段。

* bar 底三段淺色分區 = 呢件嘢自己 tier 1 / 2 / 3 滿課落喺條刻度嘅邊,
  玩家而家嗰段用金色標亮
* 深色界線 + 羅馬數字 = 兩個進化門檻
* 每條 bar 旁邊照舊有實際數字(同 C 嘅真數規則同一個出數點)
* 面板標題旁有羅馬數字階級徽章
* 唔跟階放大嘅 stat(射程、機率、持續時間)照舊線性,而且**唔畫**分區

`art_export` 影咗三個狀態自查:`26_perf_t1_early` / `26b_perf_t1_maxed` /
`26c_perf_t2_mid`,中英各一套。

---

## E — 拎走 5x

速度循環:**0.5x → 1x → 3x**。

三個理由,冇一個係「太快唔好玩」:

1. 5x 之下一幀就係 83ms 嘅遊戲時間,而一支箭飛過成個射程都唔使 83ms ——
   即係話輸出唔再係「打中」而係「每幀結算一次」。
2. 全部效能預算(池上限、音效併發窗、soak 場景)都係為咗撐住 5x 而訂,而佢哋
   喺 3x 之下有大量鬆動 —— 呢個鬆動直接變成 A 嗰邊嘅網頁版記憶體餘裕。
3. 一個要撳三下先返到 1x 嘅循環同一個撳兩下嘅循環,喺電話上面係兩種手感。

清理咗:`tools/perf5x` → `tools/perf3x`(效能目標改成「3x boss 戰 ≥ 55fps」)、
SoakTest 兩個 5x 場景、AudioTest 嘅 time-scale case、以及十幾段引用 5x 做
worst case 嘅註解。

**守門測試**:`SpeedScaleTest` 加咗一條原始碼掃描 —— `scripts/` / `test/` /
`tests/` / `tools/` 底下冇一句**程式碼**可以再提 5x。掃嘅只係程式碼唔係註解:
一條連解釋都禁埋嘅規則會逼人刪走理由,而理由先係呢個 codebase 最值錢嘅嘢。
正規式排除咗 `0.5x` / `1.5x` / `3x5` / `0x5EED`,而測試檔本身跳過(佢係規則
嘅定義,一定要講得出 "5x")。

---

## F — 圖鑑:怪物 / 塔 / 魔法

三個分頁。怪物頁一個字都冇改(除咗成頁落咗 40px 讓位畀分頁掣)。

塔頁 / 魔法頁:一件一張卡,由上到下捲。每張卡答四條問題 ——

1. **佢做乜** — 名(跟階)、一句描述、當前階圖示
2. **佢而家幾強** — 實際數值摘要,由 `Meta.*_stats()` 經 `Upgrade.fmt_value()`
   出,所以圖鑑同升級介面唔可能為同一座塔印出兩個唔同嘅數
3. **我課到邊** — 全部軸嘅 `n/15`,滿咗嘅轉綠
4. **佢會變成乜** — 三階演進鏈橫排:已到嘅階全彩 + 該階新機制,未到嘅剪影

兩個「睇唔到」嘅原因分得清楚,唔會兩個都變成「???」:

* 第一階未買 → 「商店解鎖」+ 解鎖價
* 未進化到 → 「進化後解鎖」

因為嗰兩件事要玩家做嘅嘢完全相反(去商店 vs 課六條軸)。

撳一張卡跳去嗰件嘢嘅升級介面(`Flow.upgrade_focus`,讀完即清)。戰鬥入面
由暫停選單開嘅 overlay 唔會跳 —— 嗰個會炸咗場仗。

`BestiaryTest` 由 print 變成 pass/fail(20 條):三十五張卡喺每個擁有狀態
都砌得出、未解鎖卡有價冇數值、進化過嘅用返新名、跳轉落啱嗰件嘢而且拒絕
一件玩家冇嘅嘢。

---

## G — 收尾

### 全套測試

`powershell -File tools/run_tests.ps1` —— **26 run, 0 non-zero exit**。
一個測試一個 process,所以一單真閃退唔會扮成「後面嗰啲冇跑過」。

| 測試 | 結果 |
|---|---|
| AudioHookTest | PASS fails=0 |
| AudioTest | PASS fails=0 skips=1 |
| Autopilot | COMPLETE monsters=22 towers=18 kills=16 |
| BalanceSim | exit 0 |
| **BestiaryTest**(重寫) | **20 passed, 0 failed** |
| BossHealTest | PASS fails=0 |
| BossSpawnTest | PASS fails=0 |
| BottomBarTest | PASS fails=0 |
| CounterTest | PASS fails=0 |
| EconTest | PASS fails=0 |
| EvolveTest | PASS fails=0 |
| FlowTest | PASS fails=0 |
| **I18nTest**(加咗字型覆蓋) | **1040 passed, 0 failed** |
| InputProbe / Shots / SpellFlowTest / WinTest | exit 0 |
| LoseTest | PASS fails=0 |
| RegressionTest | PASS fails=0 |
| SceneCheck | ALL DONE |
| ScrollTest | PASS fails=0 |
| SoakTest(30 圈,1859s) | **PASS rounds=30 battles=36 flow=6** |
| **SpeedScaleTest**(加咗 5x 原始碼掃描) | **PASS fails=0** |
| **StatDisplayTest**(新) | **4683 passed, 0 failed;4680 個數字對過** |
| **StretchTest**(加咗 head_include 斷言) | **PASS fails=0** |
| WallTest | PASS fails=0 |

### 網頁版驗證:喺一個**真瀏覽器**入面影嘅

`tools/web_shots.py`(新)開一個本機 server 指住 `docs/`,用 Playwright +
Chromium 載入真正嗰個 build,兩種語言各行一次:主選單 → 圖鑑三個分頁 →
升級介面,每步影一張,同時收 console。

呢個唔係錦上添花。第十一輪嘅亂碼 bug 喺桌面版**睇唔到**(桌面有系統字型做
後備,網頁版冇),即係話任何「喺桌面截圖自查」嘅流程對呢一類 bug 完全盲。
之前十輪就係咁樣過咗關。

量到:

* 兩種語言、五個畫面,**零豆腐方格、零亂碼**
* console **零 error**
* `window.__tfDpr` 存在 → head_include 嘅 shim 真係行咗
* `typeof window.__tfVisibility === "function"` → `Web.gd` 真係掛到 JS 嗰邊。
  呢條線斷咗係**靜**嘅:遊戲照玩,只係切走之後唔會暫停,而嗰個正正就係 iOS
  收記憶體嗰一刻。所以佢要有一條斷言,唔係靠肉眼。

(Chromium headless 嘅 `devicePixelRatio` 係 1,所以封頂喺呢個環境入面係
no-op —— 佢驗到嘅係「段 shim 行緊」,唔係「喺 iPhone 上面慳咗幾多」。
後者係上面嗰條算術。)

### 完整流程實跑

`tools/walkthrough.tscn` —— 主選單 → 選關 → 第 1 關真打(真刷怪、真金、
真塔)→ boss → 收場。10 張圖,`level 1 cleared, ended=true`。

### 桌面美術自查

`tools/art_export.tscn` 中英各一套(`qa/r11_zh` / `qa/r11_en`),包括呢一輪
新加嘅七張:效能面板三態 + 圖鑑四態。

---

## 追加 — 收到第一份真閃退報告(2026-08-02 11:54)

出街之後即刻收到一份,而第一件要講嘅嘢係:**呢單閃退唔係呢個版本嘅**。

```
session: 1785656454-97798   started: 08:41:25   detected: 11:54:38
0.59 boot / 5.80 Shop / 7.63 MainMenu / 8.30 Upgrade / 15.86 MainMenu
17.58 Upgrade / 21.34 MainMenu / 22.76 Gallery / 31.04 MainMenu  <- 之後死
```

`docs/` 上一次重出係 05:13(第十輪),今次係 11:32。嗰個 session 08:41 開始,
即係話佢跑緊嘅係**第十輪**嘅 build。兩個結果:

1. 呢一輪嘅 DPR 封頂、池收窄、記憶體採樣**全部都唔喺入面**。
2. 報告冇記憶體曲線,唔係因為「閃退喺頭三十秒」(佢撐咗 31 秒),
   係因為**嗰個 build 冇採樣呢個功能**。閃退報告畫面本身係新嘅,
   佢讀到嘅係一個舊 build 留低嘅 marker —— 呢個機制照計行得啱。

### 麵包屑講到嘅嘢

**冇入過戰鬥。** 31 秒純選單瀏覽。即係話之前幾輪落喺戰場嘅功夫(池上限、
fx 預算,連同呢一輪嘅 web 收窄)同**呢一單**閃退無關 —— 嗰啲嘢喺選單入面
根本唔存在。

死之前最後一個唔尋常嘅畫面係**美術畫廊(除錯)**。

### 量度:選單流程有冇漏

`tools/menu_leak.gd`(新)用真 `change_scene_to_file` 重放同一串畫面六轉,
逐步量。結論係**冇漏**:

| 每轉收場時嘅主選單 | static | video | objects | nodes |
|---|---|---|---|---|
| 第 1 轉 | 137.58 MB | 136.19 MB | 1895 | 45 |
| 第 6 轉 | 137.61 MB | 136.19 MB | 1895 | 45 |

六轉之間 objects 同 nodes **一個都冇差**,static 飄咗 +0.04 MB(+8 KB/轉,
係雜訊)。美術畫廊開住嗰陣係 142.64 MB / 541 nodes(比主選單 **+5.03 MB /
+496 nodes**),但**收返晒**。

所以呢單唔似係「越玩越多」嘅漏,而係「**峰值**本身太高」——
baseline 加上 iPhone DPR 3 嘅畫布(約 24 MB),而畫廊嗰 +5 MB 係最後一浸。
呢一輪嘅 DPR 封頂正正就係打呢個(-13.4 MB)。

### 仲有一個唔可以排除嘅可能:根本唔係閃退

iOS Safari 會**主動掉走**背景 tab,返嚟自動重新載入 —— 而用戶原話係
「閃退後自動重開」,同呢個行為一模一樣。被系統掉走同真 OOM 喺 marker
上面睇落**完全一樣**(兩者都係 process 冇行過 `_close()`)。

呢一輪之後兩者分得開,而且唔使靠估:`Web.gd` 而家喺 `visibilitychange` /
`pagehide` 寫低一個 `web hidden` 麵包屑並即刻 flush。所以下一份報告 ——

* 最後一條係 `web hidden` → 係切走之後被系統掉走,唔係 OOM
* 麵包屑斷喺玩緊嘅中途,而 `mem` 曲線一路向上 → 係 OOM

採樣本身核實過:開機 1.16 秒一個、31.16 秒一個,
`static=125.7MB video=74.1MB obj=1674 node=44 fps=60`。

### 跟進:美術畫廊由正式版拎走(用戶決定)

主選單嗰粒「美術畫廊 (除錯)」掣除名。佢係一個開發工具,唔係玩家功能,
而佢峰值比主選單多 **+5.03 MB / +496 nodes** —— 喺一部已經貼住 Safari
tab 上限嘅 iPhone 上面呢個數唔細,而佢喺嗰單閃退嘅麵包屑入面正正就係
死之前最後去嗰個畫面。

**兩層,唔係一層:**

1. 主選單冇入口 —— 玩家撳唔到。
2. `export_presets.cfg` 兩個 preset 都唔再打包 `scenes/Gallery.tscn` 同
   `scripts/ui/Gallery.gd` —— 就算有人日後加返一粒掣,出貨版都冇嗰個檔。

淨做第一樣,下一個重排選單嘅人可以靜靜咁還原;淨做第二樣,還原完就變成
一粒載入失敗嘅掣。

畫廊本身**冇刪**:`tools/art_export.gd`、`SoakTest`、`SceneCheck`、`Shots`
仍然由原始碼開得到佢,而 `07_gallery` 嗰張自查圖照出。

pack:684 檔 / 6829 KB → **680 檔 / 6825 KB**。慳嘅唔係 4 KB,係一條
「一撳就入」嘅路。

**守門**(`FlowTest`):出貨腳本(`scripts/**`,8456 行程式碼)入面冇一句
提到 `Flow.GALLERY` 或者 `scenes/Gallery.tscn`,而且每一個 export preset
都隔走佢。註解唔算 —— `MainMenu.gd` 嗰段解釋點解拎走佢嘅字要留得低。

> 第一版守門係**假綠**:佢去撳主選單每一粒掣睇有冇切場景,但
> `Flow.goto()` 喺 `nav_enabled = false`(即係測試 harness)之下未行到
> 麵包屑就已經 return,所以量到零條路,而「冇路去畫廊」就喺零條路入面
> 成立咗。係嗰條「真係撳過幾多粒掣」嘅牙齒斷言捉返出嚟。改咗做掃 source。
> 兩個測試(呢個同 5x 嗰個)而家共用 `test/SourceScan.gd`。

---

### 未做嘅嘢 / 留返

* **`icudt_godot.dat` 4.69 MB 仲喺 pack 入面。** 上面 A-2 記低咗點驗證佢
  拎唔走(Godot 4.7 嘅 export template 無條件提供)。要再慳呢 4.69 MB,
  唯一嘅路係換 text server 或者改引擎,兩樣都超出呢一輪。
* ~~`scenes/Gallery.tscn`(美術畫廊,除錯用)仲喺 web pack 入面~~ —— 用戶
  決定咗拎走,已經做咗,見上面「跟進」嗰節。
* **DPR 封頂嘅實際效果冇喺一部真 iPhone 上面量過。** 呢個環境冇 iOS 裝置,
  亦都冇一部 DPR > 1 嘅瀏覽器。段 shim 行緊(量到),而慳幾多係算術。
  下一次用戶開 GitHub Pages 版嗰陣,如果再閃退,閃退報告畫面而家會自己彈
  出嚟連埋記憶體曲線 —— 呢個先係呢一輪對嗰個 bug 真正嘅答案:唔係
  「我修好咗」,係「下次佢再發生,我哋會有證據」。
