# 第 19 輪 — 怪物美術升級(Gemini sprite sheet 入遊戲)

2026-08-06。純美術替換輪:遊戲邏輯、數值、hitbox、行為一步都冇郁,
改動只喺視覺資產同顯示層。還原點 commit `acd2705`(`monster-art-v2 restore point`)。

---

## 1. 檔名 → 族 id 對照

逐張打開睇圖入面畫咗乜先對族,冇靠檔名。

| 檔案 | 族 id | 圖入面係乜(認嘅根據) |
|---|---|---|
| `goblin.jfif` | goblin | 綠皮尖耳哥布林,由棍 → 雙刀 → 板甲 → 紅冠 → 骷髏圖騰 boss |
| `wolf.jfif` | wolf | 四足奔跑狼,灰 → 啡 → 黑,boss 一身熔岩裂紋加火焰 |
| `skeleton.jfif` | skeleton | 骷髏戰士,胸腔有綠光,boss 戴王冠 + 地面骨環 |
| `golem.jfif` | golem | 石人,lv2-3 身上有藍色符文,boss 係水晶白石加六芒星 |
| `ghost.jfif` | ghost | 幽靈,由白 → 青 → 鎖鏈 → 鐮刀 → 甲冑,boss 係紫色戴冠拖尾 |
| `bat.jfif` | bat | 蝙蝠展翼,由啡 → 紫 → 紅魔,boss 俯衝加風線 |
| `treant.jfif` | treant | 樹人,樹冠 / 蘑菇 / 花逐級加,boss 有鹿角 + 綠色法陣 |
| `beetle.jfif` | beetle | 獨角仙側面,啡 → 藍綠 → 鋼甲 → 鍍鉻 boss |
| `cultist.jfif` | cultist | 兜帽術士,腳下法陣逐級變複雜,boss 戴牛角冠 |
| **`monster1.jfif`** | **slime** | **綠色啫喱 blob**,水晶 / 骷髏 / 尖刺 / 戴冠 boss(周圍一圈細史萊姆) |

`monster1.jfif` 就係題目講嗰個檔名陷阱。佢同 `art_reference/` 根目錄嗰張舊參考圖
`monster1.jpg` 冇關係 —— 呢張係綠幕史萊姆 sheet,另一張係舊參考圖,冇撈亂。

**10 族全部切到 6 格,冇一族要停低。**

---

## 2. 摳圖 pipeline

管線 `tools/monster_cutout.py`(Python + Pillow + numpy + scipy)。
原始 `.jfif` 一個 byte 都冇改;預設出去 `qa/monster_cutout/out/` 畀人驗,
`--install` 先寫入 `assets/generated/monsters/`。

### 2.1 背景偵測(唔 hardcode #00FF00)

底色由**邊框像素嘅眾數**取樣,而且係一個**集合**唔係一隻色。量到嘅底色:

| sheet | 主底色 | 副底色 / 特殊 |
|---|---|---|
| goblin | `#14CC14` | 4 個亮度嘅綠(每格底色都唔同) |
| wolf | `#04F404` | — |
| skeleton | `#0CEC0C` | 每格一圈深色框線 |
| golem | `#04FC04` | 格界有貫通全高嘅綠分隔線 |
| treant | `#04FC04` | **每格地下有一撻暗綠投影** |
| beetle | `#2CE42C` | 每格外面一圈暗綠框 `#009000` |
| cultist | `#34C42C` | 啞綠 + 漸變(vignette) |
| slime | `#049C04` | **暗綠底**,但格與格之間係**亮綠**分隔線 |
| ghost | `#BCC4B4`(淺灰) | 綠間隔線 + 灰↔綠之間嘅漸變帶 |
| bat | `#B4CCAC`(灰綠) | 近白分隔線 + 上下綠邊條 + **baked-in 文字** |

### 2.2 距離場:用射線唔用點

綠底判斷唔可以用「同 bg 嘅 RGB 距離」,因為 treant 每格地下嗰撻投影同底色**同一個
色相**,只係暗咗三成幾。改用**到射線 `t·bg` 嘅距離**(`t` 夾喺 0.55–1.35):

* 投影 `t≈0.63`,喺射線上面 → 距離 ~27 → 當底色剷走 ✓
* 黑色描邊要 `t≈0.1` 先掂到射線,俾下限 0.55 頂住 → 距離 ~112 → 保得住 ✓
* 綠色**主體**(史萊姆身 145、treant 綠葉 154、狼 lv5 綠火 228、cultist 綠法陣)
  全部離射線好遠 → 保得住 ✓

灰底兩張(ghost / bat)用平面距離,另外加埋「灰↔綠**線段**」——
ghost 嘅綠間隔線同灰格底之間有一條 2-3px 漸變帶,每一粒都係兩種底色溝埋,
對灰對綠兩邊距離都唔夠近,唔加呢條就成個綠框留咗喺 lv3/4/5/boss 度。

### 2.3 逐張特殊處理

| 情況 | 點做 |
|---|---|
| **bat 嘅 baked-in 文字** | 量到文字帶係 y=145..159(格高 167),而怪嘅腳趾去到 y=144。所以界線落 `0.862` 硬剷。早期試過 `0.74`,連 lv5 對腳一齊剷咗。**bat 六格逐格用 NEAREST 放大三倍睇過(`monster_qa.py --zoom bat`),零文字殘留;其餘九族喺 60 格棋盤接觸表上面一齊睇過。** |
| **ghost 淺灰底** | lv1 隻鬼「幾乎白」,身上有啲位同底色只差 d≈31。門檻要拉到 `d_hi=16`(綠幕張數係 58)。用 46 跑過,lv1/lv2 蛀到剩返半隻。 |
| **treant 地面投影** | 靠射線距離自動消失(見 2.2),唔使特別開關。 |
| **半透明族(ghost / slime)** | 冇做真正嘅半透明 matting —— 實色化 + 柔邊,遊戲入面嘅虛化交返俾現有 `modulate`。呢個係題目容許嘅策略,亦都係唯一唔會出綠邊光暈嘅做法。 |
| **cultist / treant boss 嘅柔光暈** | 呢兩張開闊 `d_soft`(108 / 96),兩層 flood fill 之間嗰條帶用 ramp 淡出。其餘八張 `d_soft = d_hi+16`(窄)—— 開闊咗會令深色部位變半透明(甲蟲六隻深藍腳 d≈81,曾經淨係得 49% 不透明度,睇落似蒸發緊)。 |
| **格線 / 邊條** | 剷,但要三個條件同時成立:幼(≤4px)、貫通(≥94%)、**而且坐喺格界位**(±5% 闊)。冇第三條就會斬開高過九成格高嘅怪 —— treant lv5 / golem lv5 / goblin boss 曾經俾人斬開兩橛,切口係一條垂直直線。 |

### 2.4 衛星元素

主體 = 最大嗰嚿 connected component;衛星 = **主體 bbox 外擴 20%** 之內嘅
component。靠呢步保住嘅:slime boss 一圈細史萊姆、goblin boss 嘅魔法 wisp、
bat boss 嘅俯衝風線、skeleton boss 嘅地面骨環、cultist 嘅浮空符牌。

衛星仲要「同主體同一格,或者細過主體一成二」—— 甲蟲畫到差唔多貼住格界,
冇呢個條件 lv3 會撈埋隔籬格隻甲蟲入嚟,一格出兩隻。

另外:成張 sheet **一次過** label 再按 x 重心分格,**唔係**先切格再 label。
有幾隻怪畫到過咗格界,硬切會削走佢隻手臂。

### 2.5 De-spill(踩過一次大鑊)

第一版用教科書 matting 反解:`F = (C − (1−a)·B) / a`。**唔得** —— alpha 估唔準,
細 alpha 一除就將綠爆大,60 張有 58 張出咗一圈死綠邊,而且係比原本底色仲鮮嘅綠。

而家改用**由內向外補色**:主體向內縮 2px 嗰嚿叫 core(乾淨),外面兩層像素如果
搵到 3-4px 內嘅 core 就用最近嗰粒 core 嘅顏色蓋過去。搵唔到 core 嘅(幼過 4px:
骷髏 boss 骨環、cultist 法陣線、bat boss 風線)唔補色,改用傳統壓綠通道公式,
保住條線唔會消失。

另外兩個「唔會報錯,只會畫錯」嘅陷阱:

1. **PIL 對 straight-alpha RGBA 做 LANCZOS** —— 全透明像素仍然帶住原本底色,
   縮放核會將綠溝返入邊緣。摳得幾乾淨都好,一 resize 就返一圈綠光暈。
   → 先乘 alpha、縮完再除返(premultiplied resize)。
2. **透明像素嘅 RGB 喺 GPU 度一樣會被 LINEAR filter 抽出嚟** ——
   離線 checker 影都影唔到。→ 出檔前做 alpha bleed(全透明像素填最近嘅實色)。
   atlas 嘅 2px extrude 只顧格與格之間,顧唔到格內嘅透明區。

---

## 3. 尺寸、錨點、面向

**顯示尺寸一步都冇郁**:`GameData.RENDER_SCALE` 仍然 2.0,`size`(血條 /
特效半徑 / 傷害數字位置)仍然由佢計。改嘅係「檔案解像度」同對應嘅 sprite scale。

| | 舊 | 新 |
|---|---|---|
| PNG 形狀 | 正方形 32/35/38/41/44,boss 96 | **就住主體剪到啱剪**,66..189px(非正方形) |
| PNG 解像度 | 顯示尺寸 × 0.5 | lv1-5 = 顯示尺寸 × **1.25**;boss = 顯示尺寸 × **0.75** |
| sprite scale | `RENDER_SCALE` = 2.0 | `MON_ART_SCALE` = **0.8** / `MON_ART_SCALE_BOSS` = **4/3** |
| filter | NEAREST | **LINEAR**(只限怪物 sprite;塔 / 地面 / 裝飾照舊 NEAREST) |

**點解唔跟「一律 2 倍顯示解像度」:** 源圖每格得 171×167,主體大約佔 130–150px。
60 張全部做 2 倍顯示解像度要 10.6MB,超咗 6MB 硬線一大截,而且超出源圖原生
解像度嗰部分係「放大空氣」—— 唔會多一格細節出嚟。而家嘅數(lv 1.25×、boss
0.75×)啱啱好坐喺源圖原生解像度上下,每一 byte 都係源圖真係有嘅細節。

**錨點**:每張圖嘅擺位由舊 sprite 量返出嚟(`tools/monster_anchor.json` 快照)。
`腳底離 sprite 中心 f = (舊 bbox 底 − 0.5) × 顯示邊長`,新圖畫布半高 ≥ f,
所以接地點**逐張對到 ±0.5px**。飛行族(bat)嘅舊高度 offset 一樣繼承落嚟,
所以佢仲係飛喺路面上面。

**大細**:以**實心像素面積**為準(= 視覺體積),再夾上限 1.20 闊 / 1.15 高。
一開始試過「塞入舊 bbox」—— 唔得:新圖長寬比同舊圖差好遠,蝠類開晒翼係 2.2:1,
塞入去之後高度剩返舊嘅四成半,細到認唔出。

**面向**:sheet 全部面左,同舊圖一致,現有翻轉邏輯原封不動。

---

## 4. VRAM / 體積

| | before | after | Δ |
|---|---|---|---|
| `atlas_battle.png`(解壓後 VRAM) | 768×886 = **2.60 MB** | 896×1588 = **5.43 MB** | **+2.83 MB** |
| `atlas_ui.png` | 384×492 = 0.72 MB | 384×492 = 0.72 MB | 0 |
| 60 張怪物 sprite 原始像素 | 0.63 MB | 3.01 MB | +2.38 MB |
| **`RENDER_TEXTURE_MEM_USED`(battle)** | **10.88 MB** | **13.95 MB** | **+3.07 MB** |
| **`RENDER_TEXTURE_MEM_USED`(peak)** | **11.45 MB** | **14.51 MB** | **+3.06 MB** |
| pck(`docs/index.pck`) | 6.93 MB | 8.00 MB | +1.07 MB |
| web build 總體積 | 44.94 MB | 46.01 MB | +1.07 MB |

「before」係喺還原點 `acd2705` 開一個 `git worktree` 度量嘅,同一部機、同一個
harness(`tools/run_drawcalls.ps1`),唔係靠估。

**≤ 6MB 硬線:過(+3.07 MB,用咗一半)。** 60 張新 sprite 全部 ≤189px,冇一張
跌出 atlas(`ATLAS_MAX_SIDE` 256 冇改),battle 頁填充率 82%。

順手做埋一件事:`export_presets.cfg` 兩個 preset 都加咗
`assets/generated/monsters/*` 落 exclude_filter。60 張圖全部行 atlas
(`Assets._atlas_tex()` 攔喺 `_load()` 前面),散圖入埋出貨包就係同一份資料
擺兩次 —— pck 由 +2.22 MB 變返 +1.07 MB。守呢件事嘅係 `test/AtlasTest`:
佢逐張問「係咪真係返一個 AtlasTexture」,有一張跌返落原檔就即刻紅。

**draw call / 幀時間:冇郁。**

| | before | after |
|---|---|---|
| battle draw_avg / ms_avg | 107 / 0.94ms | 107 / 0.94ms |
| peak draw_avg / ms_avg | 193 / 8.39ms | 194 / 8.36ms |

意料之內:圖換咗,但仲係同一頁 atlas、同一個 sprite-per-monster 嘅畫法,
第十四輪嘅合批成果一分都冇蝕返。

---

## 5. 舊程序生成管線

`tools/gen_art.py` 入面成段怪物繪圖碼(10 個 draw fn + 10 個 boss fn +
`level_ramp` / `feats_for` / `chest_armor` / `pauldrons` / `helm` / `cape` /
`back_spikes` / `insect_legs`,合共 1115 行)搬咗去
**`tools/deprecated/gen_art_monsters_v1.py`** 封存,`main()` 唔再叫
`gen_monsters()`。

呢個唔係「順手清理」—— 唔搬嘅話,下一次有人行 `python tools/gen_art.py`
就會用 32-44px 嘅程序圖靜靜雞冚走成套新美術。封存檔刻意冇 import 任何嘢
(唔會行得到),`gen_art.py` 嗰度亦都留低咗一段「唔好加返」嘅註解。

`gen_art.py` 新增 `--atlas-only`:換完怪物圖之後淨係重出 atlas,唔會掂其他資產。

Python 側其餘工具:`tools/monster_qa.py`(邊緣掃描 / 棋盤接觸表 / 逐族放大)、
`tools/monster_compare.py`(新舊真實顯示尺寸對照)。

---

## 6. 驗證

| 項目 | 結果 |
|---|---|
| 自動邊緣檢查(60 張) | **0 / 60 fail**(`python tools/monster_qa.py --check`) |
| 完整性(10 族 × 6 = 60 張齊、尺寸、錨點) | 60/60,接地點逐張對到 ±0.5px |
| bat 文字殘留 | bat 六格放大逐格確認,6/6 乾淨 |
| 逐族戰鬥尺寸截圖 | `qa/screenshots/round-19-monster-art/10_<族>.png` |
| 高峰戰鬥全景 | `20_peak.png` |
| 精英 affix 標記 | `21_elite.png` |
| 圖鑑中 / 英 | `30_bestiary_zh_TW.png` / `31_bestiary_en.png`(+ 詳情頁 32/33) |
| 全套 regression | **38 run, 0 non-zero exit**(SoakTest 30 rounds / 36 battles 都 PASS) |
| draw call / 幀時間 | 冇變化(見 §4) |
| web build 真瀏覽器 | **0 console error**,真瀏覽器 rAF avg 16.67ms / p95 16.80ms(= 貼住 60fps vsync)|
| web 截圖 | `qa/screenshots/round-19-web/`:`04b_monsters_x1.png`(戰鬥入面嘅新怪)、`03_bestiary.png`(圖鑑) |

**門檻定咗 3.0%,唔係 0%,呢個要講清楚。** 灰底嗰張(ghost)隻鬼本身就有
「同底色好近」嘅色 —— lv4 隻鐮刀鬼把刀刃係灰白,量到 2.26% 邊緣像素落喺
`d_hi=16` 入面。放大睇過:係刀,唔係殘底。所以門檻放到 3.0% 而唔係扮 0。
其餘 59 張全部 ≤1.1%,大部分係 0.00%。

### 邊緣檢查點樣量

第一版 checker 問「邊緣有冇綠」—— 錯:史萊姆成隻綠、treant 有綠葉、cultist 有
綠法陣、狼 lv5 有綠火,slime 報 100% 綠邊。真正要捉嘅係**殘留底色**,所以
checker 拎返 `monster_cutout` 記低嗰張 sheet 嘅底色,用**同一條射線距離**同
**同一個 `d_hi`** 去量:一粒實色邊緣像素如果落返摳圖門檻入面,佢就係漏網。

---

## 7. Jack 要驗乜

1. **全景協調感** —— `20_peak.png`:新怪(手繪、線稿、飽和度高)同現有塔 /
   地面 / UI(程序像素風)企埋一齊夾唔夾。呢個係今輪最主觀、最需要你判斷嘅一項。
   如果覺得唔夾,方向係塔嗰邊追上嚟,唔係怪嗰邊退返落去。
2. **逐族縮細辨識度** —— `10_<族>.png` 十張:每族 lv1→lv5→boss 喺真實戰鬥
   尺寸同一條路上面。lv1 得 64px 高,睇下認唔認得出係邊一族、級數分唔分得開。
3. **有冇綠邊** —— 自動 checker 已經 0/60,但機器同眼唔一定同意。
   特別睇史萊姆同 ghost(半透明族)、狼 lv5(佢身上真係有綠火,唔係殘底)。
4. **行路接地感** —— `10_<族>.png` 睇腳有冇浮起或者陷落路面;bat 應該仲係飛喺
   路面上面(佢用返舊嗰個高度 offset)。
5. **精英怪睇唔睇得清** —— `21_elite.png`:四個 affix 各一隻,旁邊夾住一隻冇
   affix 嘅同族做對照。新圖色彩豐富咗,`modulate` tint 會唔會蓋唔住。
6. **圖鑑排版** —— 中英兩版,睇大頭像有冇撞穿右邊嗰段文字(新圖大好多,
   舊嗰條「×4 / ×2」硬乘式已經換咗做塞框式)。
