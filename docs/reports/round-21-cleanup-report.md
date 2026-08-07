# 第二十一輪(收官輪)報告 — 待補 icon + 測試債清算 + boss 血量下限

還原點:`b3f6816`(commit message `cleanup-round restore point`)。
還原方法:`git checkout b3f6816 -- scripts/ test/ tools/ assets/`。

---

## Part A — 四個待補魔法 icon 入遊戲

### 對號結果

| 源檔(中文檔名連空格) | 對到 | 內容 | 框 |
|---|---|---|---|
| `地震術 T1.jfif` | spell 11 tier 1 | 裂地塵煙:一道向下裂開嘅地縫 + 兩團揚起嘅塵煙,褐色土調 | T1 淨色底(冇金屬框) |
| `地震術 T2.jfif` | spell 11 tier 2 | 熔岩裂谷:裂開嘅岩板中間一條橙紅熔岩柱 | T2 銀框 + 四粒鉚釘 |
| `烈焰之牆 T3.jfif` | spell 12 tier 3 | 白藍業火:藍白色核心嘅火牆,帶飄升嘅鬼火 | T3 金框 + 捲草角 |
| `龍捲風 T3.jfif` | spell 10 tier 3 | 紫黑風暴:紫黑漏斗 + 紫電 + 俾捲起嘅碎石 | T3 金框 + 捲草角 |

四個都同 Jack 講嘅內容對得上,冇一個要換位。**待補清單由 4 格清到 0 格。**

### 管線(`tools/magic_cutout.py` 新增 `SINGLES` 段)

呢四張同原本嗰張 15×3 sheet 係**兩條唔同嘅管線**:sheet 嗰邊唔使摳圖(格與格
之間先係綠坑,格本身有自己底色),呢四張係 1024×1024 綠幕底、一張一個完整
badge。所以要摳綠,但唔使切格、唔使剷 label。

摳綠照 round-19 / round-20 嗰套:

1. **alpha 用「到 t·bg 射線嘅距離」,唔用 RGB 距離。** 量出嚟背景 d<6、
   badge 內部 d>200、過渡帶 8–12px(1024 尺度,縮到 64 之後係 0.75px),
   所以門檻 `KEY_LO=12 / KEY_HI=64`。用射線嘅原因:badge 底下嗰浸投影係
   暗綠(同一條射線、t<1),RGB 距離會當佢係前景而留低一圈黑邊。
2. **溢色用「core 向內縮 3px + 最近 core 補色」**,唔用教科書 matting 反解
   (round-19 量過:alpha 估唔準,細 alpha 一除就將綠爆大)。
3. **縮圖一定要 premultiply**(round-19 陷阱 1:PIL 對 straight-alpha 做
   LANCZOS 會將透明像素嘅底色溝返入邊緣,60 張中 58 張中招)。
4. **alpha bleed 填滿成張圖**,唔係擴散兩圈 —— GPU 嘅 LINEAR filter 照樣採樣
   到 alpha=0 嘅像素。

### ✦ 浮水印:摳綠**摳唔走**佢,呢個係本輪唯一一個真陷阱

Jack 個 brief 講「佢喺背景上,摳綠應該連佢一齊走」。**實測係走唔到嘅**,而且
唔止走唔到,仲會搞亂 crop:

* ✦ 係半透明**白**疊喺綠底上面,所以佢仍然「好綠」(G − max(R,B) 有 160)——
  用「夠唔夠綠」去摳係摳唔走佢。
* 但佢**離開咗** t·bg 條射線(d≈102 > `KEY_HI`=64),所以 matting 嗰條式反而
  俾佢 alpha = **1.0**。
* 後果:第一版摳完,四張 icon 右下角全部有一粒螢光綠星,而且 crop bbox 俾佢
  撐大咗(地震術 T2 由 686px 變 759px),即係成張 icon 縮細咗 10%。

處理:**唔使用 round-20 嗰套「反解一個已知疊加層」** —— 嗰套係因為塔嘅浮水印
貼實塔身剷唔到,而呢度量到 ✦ 同 badge 之間有 40px 以上嘅純背景(四張都係)。
所以做法係 `drop_islands()`:主體填窿之後向外放 3px = `near`,`near` 以外一律
清零。

**中間踩過一次坑並且改咗做法**:第一版係「留最大一嚿,其餘逐嚿 dilate 完
清零」,結果剷走咗 40–70 嚿 1–2px 嘅幼絲 —— 嗰啲係 JPEG 喺「黑描邊 vs 螢光綠」
呢種高反差邊界出嘅色度 ringing,佢哋貼實 badge 邊,逐嚿 dilate 落去會連 badge
自己條邊一齊剷。改成 `near` 之後,四張各自淨係剷走**一嚿**,而且四張都喺同一個
位置:`[880,880]–[927,927]`,823–831px。就係嗰粒 ✦。

### 驗收(`python tools/magic_cutout.py --install`)

```
  spell_10 t3  crop 750x750 @(137,137)  殘綠 0  剷走 823px @[880,880,927,927]  半透明 5.7%  OK
  spell_11 t1  crop 554x554 @(235,235)  殘綠 0  剷走 825px @[880,880,927,927]  半透明 5.9%  OK
  spell_11 t2  crop 686x686 @(169,169)  殘綠 0  剷走 831px @[880,880,927,927]  半透明 6.1%  OK
  spell_12 t3  crop 752x752 @(135,130)  殘綠 0  剷走 826px @[880,880,927,927]  半透明 5.9%  OK
residue check: 0 個問題
wrote 45 / 45 icons
待補 0 格 —— 清單清零
```

四項驗收:(a) 出街 icon **全圖**冇殘留來源底色 —— 連 alpha=0 嗰啲都驗,因為
GPU LINEAR 會採樣到;(b) 剷走嘅 island 唔可以大過 3000px(大過就係剷咗 badge
一部分);(c) crop bbox 唔可以掂到源圖邊界;(d) 半透明像素比例 <16%。
邊緣 checker 沿用 round-19 嗰個原則:量「殘留**來源底色**」唔係量「有冇綠」。

### 一個要解釋嘅決定:**唔疊**程序階級框

其餘 41 張嘅銀 / 金階級框係 `magic_cutout.tier_frame()` 疊上去嘅。呢四張唔疊,
原因喺 `qa/magic_cutout/frame_ab.png`(上排 = 出街版,下排 = 疊咗框):疊落去
會將畫好嘅金色捲草角完全冚住,而且程序框係硬邊像素框,擺喺手繪 badge 上面好
突兀,內容區仲要細一圈。而「階級讀得出」呢個功能 painted 框自己已經做到 ——
T1 淨色 / T2 銀 / T3 金,同其餘 41 張同一套色碼。

淨低嘅差異係底邊嗰排**階級點**(45 張入面得呢四張冇),所以補返
`tier_pips()`:只畫點,唔畫框。咁「數點」呢個 affordance 45 張都仲在。

### 入場範圍

`assets/generated/spells/` 45 張全部 64×64(之前四張係 44×44),atlas 重出。
戰鬥魔法列 / 商店 / 升級 / 進化預覽 / 圖鑑全部行同一個 `Assets.spell(id, tier)`,
所以一次過跟。三處同步點全部清空:

| 位置 | 之前 | 而家 |
|---|---|---|
| `tools/magic_cutout.py` `MISSING` | 4 格 | `{}` |
| `tools/gen_art.py` `PROCEDURAL_SPELLS` | `{(10,3),(11,1),(11,2),(12,3)}` | `frozenset()` |
| `test/TowerArtTest` `STILL_PROCEDURAL` | 4 格 | `[]`(而且新增一條斷言:呢個清單要係空) |

`TowerArtTest` 順手加咗一條**唔靠尺寸**嘅斷言:手繪 badge 一定有透明角,程序圖
係四四方方填滿。將來有人改咗 44→64 再畫程序圖,尺寸嗰項呃得過,呢項呃唔過。

截圖:`qa/screenshots/round-21-cleanup/{before,after}/`(中英各一套)。

---

## Part B — Bestiary NEAREST 手尾

`Bestiary.gd` 兩個怪物頭像位(格仔頭像 `_slot_button`、詳情大圖 `_detail_panel`)
之前叫 `UI.tex_rect(tex, ...)` 冇傳 `smooth`,所以行 NEAREST。而顯示尺寸係
110px / 270px,源圖係 66–189px 嘅手繪圖 —— 非整數縮放之下 NEAREST 會逐格食走
一行像素,手繪線條起格。改成 `smooth=true`,同 round-20 塔 / 魔法一致
(`UI.tex_rect` 自己按源圖大細揀:>48px 先至 LINEAR,所以剩返嘅程序像素圖
唔會受影響)。

前後對比:`qa/screenshots/round-21-cleanup/cmp_05_bestiary_mon_goblin_slot5.png`
(左 = 改之前,右 = 改之後)。哥布林王嘅骨盔尖角同肩甲邊喺左邊有明顯階梯狀
斷行,右邊順滑。

### 全 project 掃描結果

掃咗兩類:所有 `UI.tex_rect(` 呼叫端(41 個),同所有直接寫 `texture_filter`
嘅地方(16 個)。

| 位置 | 判定 |
|---|---|
| `Bestiary.gd` 格仔頭像 / 詳情大圖 | **漏咗,已修** |
| `Battle.gd` `_Placer` 建塔 ghost | **漏咗,已修** —— 佢唔係 `TextureRect` 而係 `draw_texture_rect`,所以 `tex_rect` 嗰個掃描捉唔到佢;`project.godot` 嘅 `default_texture_filter=0`(Nearest)之下佢畫 128px 手繪塔圖 @0.6875 |
| `Battle.gd` ground / portal / base / road、`MainMenu` title_plate、`UI.gd` bg、全部 `Assets.ui()` / `Assets.tile()` 圖示 | NEAREST **啱** —— 佢哋係 gen_art.py 嘅程序像素圖 |
| `Monster.gd` / `Tower.gd` sprite | 已經 LINEAR(round-19/20 做咗) |
| `Result.gd` 嗰兩個 `tex_rect` | 傳嘅係 coin / crystal / star,程序圖,NEAREST 啱 |

### 新守門:`test/ArtFilterTest.tscn`(241 項)

呢類 bug 嘅症狀係**畫面起格** —— 冇 error、冇 warning、冇 crash。所以加咗一個
掃**真正砌好嘅場景**嘅測試(唔係掃 source code:呼叫端傳唔傳 `smooth` 只係手段,
呢度問嘅係結果)。

認「邊張圖係手繪」用嘅係 **instance 身份**唔係尺寸:`Assets._load()` 有 path
cache,同一個路徑永遠返同一個 `Texture2D` instance,所以掃出嚟嗰張同 `Assets`
俾嘅嗰張係同一個物件。**唔可以用「源圖大過 48px」做判斷** —— 升級介面嗰啲
元素背板同平台係 360px 嘅程序像素圖,佢哋照舊 NEAREST 先啱(第一版就係咁樣
報咗六個假失敗)。

驗過個 test 真係捉到嘢:把 `Bestiary.gd` 嗰行改返去冇 `smooth`,即刻報
「圖鑑/monster 嘅「怪物 goblin lv1」行緊 texture_filter=1,手繪圖一定要
LINEAR(=2)」。

---

## Part C — 測試債清算

### C1. 完整 30-round soak(round-20 只行到 12)

`powershell -File tools/run_tests.ps1 -SoakRounds 30`。結果:
**`SOAK PASS rounds=30 battles=36 flow=6`**,`LEAK PASS fails=0`,**孤兒節點 0**。
原始 log:`qa/bench/runlogs/r21_soak30_pre_bossfloor.txt`。

「曲線照平」點量:soak 嘅關數用 7 做步長行勻 1..20,所以第 1–20 輪同第 21–30 輪
會**重覆打同一批關**。同一關喺第一次同第二次之間應該冇分別 —— 有分別就係狀態
漏咗過去。逐關對:

| 關 | 第一次(輪 / 秒 / 殺 / 塔 / 峰) | 第二次 | 差 |
|---|---|---|---|
| lv1 | 1 / 70s / 74 / 67 / 8 | 21 / 69s / 75 / 58 / 7 | 秒 −1 |
| lv8 | 2 / 86s / 89 / 58 / 24 | 22 / 84s / 86 / 62 / 22 | 秒 −2 |
| lv15 | 3 / 110s / 83 / 71 / 49 | 23 / 110s / 85 / 71 / 52 | 秒 0 |
| lv2 | 4 / 63s / 64 / 57 / 6 | 24 / 63s / 64 / 58 / 8 | 秒 0 |
| lv9 | 5 / 78s / 79 / 62 / 12 | 25 / 71s / 72 / 62 / 8 | 秒 −7 |
| lv16 | 6 / 105s / 28 / 62 / 81 | 26 / 110s / 30 / 66 / 90 | 秒 +5 |
| lv3 | 7 / 67s / 70 / 67 / 4 | 27 / 66s / 70 / 57 / 5 | 秒 −1 |
| lv10 | 8 / 89s / 107 / 58 / 22 | 28 / 93s / 111 / 66 / 23 | 秒 +4 |
| lv17 | 9 / 110s / 68 / 58 / 96 | 29 / 110s / 70 / 61 / 98 | 秒 0 |
| lv4 | 10 / 90s / 134 / 58 / 25 | 30 / 89s / 128 / 66 / 25 | 秒 −1 |

冇單調漂移(差有正有負,幅度 ≤7 秒 = RNG),**冇一關喺第二次變慢或者變快到
睇得出係累積效應**。同 round-19 嘅 12-round 基線比:同樣冇漂移、孤兒 0,
分別淨係樣本由 12 輪變 30 輪。

### C2. 20-seed 定版 job

工具:**`tools/gate20.ps1`**(可斷點續跑)+ **`tools/續跑定版job.bat`**(Jack
雙擊就續跑)+ **`tools/定版job出報告.bat`**(出 Gate 表)。

**工作單位 = 一個進程 = 一個輸出檔**(`qa/bench/gate/r21/<arch>_s<NN>.txt`)。
一個單位跑完會喺檔尾印 `GATE DONE`(呢行係本輪新加落 GateSim 嘅 —— 之前一個
喺第 87 關俾人 Ctrl-C 咗嘅分片同一個跑完嘅分片,喺輸出檔上面**分唔出**,而
斷點續跑就會由一個殘缺 campaign 上面接落去,勝率會偏向前段)。再開一次
script:有 `GATE DONE` 嘅跳過,冇嘅整個刪走重跑。零手工步驟。

原型次序係特登排嘅:**A2 → A3 → A1 → A0 → A4**。個 job 十幾個鐘、好可能要分
幾次跑完,而 Gate 5a / 5b 就係本輪要答嘅嗰兩條,佢哋嘅樣本要最早齊。

**全部分片行 `--nosave`(本輪新加,`Meta.disk_enabled`)。** 之前十幾個分片
一齊 `reset_save()` + 逐關寫檔,全部指住同一個 `user://save.json`;分片之間
唔互相讀所以佢哋自己冇事,但**任何同時跑嘅測試**讀到嘅存檔就係垃圾
(memory 有記:RegressionTest / I18nTest 會報一堆假失敗)。而家:
(a) Jack 自己個存檔一條毛都唔會郁 —— 實測 15 個分片跑咗成粒鐘,
`save.json` 嘅 mtime 完全冇變;(b) 跑緊定版 job 嘅同時照樣可以 `run_tests.ps1`。

跑到邊、讀數同對照:見下面「定版讀數」一節。

### C3. TimeScaleTest 併行資源競態 —— 根因

**先講結論:「save.json 搶寫」呢個最順口嘅假設,實測係錯嘅;真正嘅缺陷喺
`run_tests.ps1` 度,而佢令呢個症狀由頭到尾都查唔到。**

#### 試過而且否定咗嘅假設

寫咗 `tools/race_probe.ps1`:開 8 個「寫存檔寫到癲」嘅 GateSim 分片做背景噪音
(每個逐關 `_spend()` 都 `FileAccess.WRITE` 截斷一次 `save.json`),再喺噪音底下
跑 TimeScaleTest,兩個配置各一次,唯一分別係分片有冇 `--nosave`:

| 配置 | TimeScaleTest exit | verdict | 用時 |
|---|---|---|---|
| A 分片搶住寫 save.json | 0 | `TIMESCALE PASS fails=0 (60 個組合)` | 161.3s |
| B 分片 `--nosave` | 0 | `TIMESCALE PASS fails=0 (60 個組合)` | 161.2s |

兩次都出到 verdict。所以存檔搶寫**唔係**「冇 verdict」嘅成因。
(順帶量到一個有用嘅數:同一個測試單獨跑 89.6 秒,喺 8-way CPU 壓力底下
161 秒 —— **慢 1.8 倍**。呢個數下面有用。)

#### 真正嘅缺陷:套裝分唔出「冇 verdict」同「呢個測試永遠冇 verdict」

`run_tests.ps1` 抽 verdict 嘅方法係喺 stdout 度搵最後一行對得上
`PASS|FAIL|ALL DONE|passed|COMPLETE` 嘅嘢。實測**六個場景由寫出嚟嗰日起就
從來冇印過一行對得上嘅嘢**:

| 場景 | 佢實際印乜 | 套裝見到 |
|---|---|---|
| `InputProbe` | `PROBE[3 ACTION] ... : OK` | (空白) |
| `SpellFlowTest` | `SFLOW targeted cast on tap: ... -> OK` | (空白) |
| `WinTest` | `WINTEST ended win=true ...` | (空白) |
| `Shots` | `SHOTS: DONE` | (空白 —— pattern 係 `ALL DONE`) |
| `BalanceSim` | `SIM 總共擺咗 580 座` | (空白) |
| `StratDiag` | `DIAG DEAD cur=0/14` | (空白) |

即係話報告入面「一格空白」本身就係常態,所以**一個真係冇出到 verdict 嘅
TimeScaleTest 睇落同佢哋一模一樣**,而且套裝照報綠(exit code 係 0)。
呢個就係點解呢個症狀兩輪都「撞到」但兩輪都查唔落去 —— 佢冇留低任何可以查
嘅嘢,而且下一次跑又會「好返」(其實係之前嗰次都未必真係壞)。

仲有更差嘅一層:**嗰六個場景入面有三個係有斷言但無論肥唔肥佬都 `quit(0)`。**
`InputProbe` 五項、`SpellFlowTest` 四項、`WinTest` 嘅「贏咗冇」,全部肥晒都會
報綠。即係話呢三個測試由寫出嚟嗰日起冇守過任何嘢。

#### 修法(四項)

1. **`run_tests.ps1`:「冇 verdict」而家係一單失敗。** 報告多一欄
   `冇 verdict`,而且套裝 exit 1。空白格唔再係可以捱過去嘅嘢。
2. **六個場景全部印一行明確結論。** 有斷言嘅(`InputProbe` / `SpellFlowTest` /
   `WinTest`)數埋 fails、印 `PASS/FAIL`,而且**真係 set exit code**;
   純 bench 嘅(`BalanceSim` / `StratDiag` / `Shots`)印 `REPORT-ONLY`,
   pattern 加咗呢個字,咁「我冇斷言」同「我肥咗」就分得開。
3. **`TimeScaleTest` 加看門狗 900 秒**(`ignore_time_scale`,因為佢自己會將
   `Engine.time_scale` 推到 3.0)。以前佢**冇任何時限** —— 一掛死就靜靜企喺度。
   900 秒 = 單獨跑 90 秒 × 10,而實測最壞嘅 CPU 壓力只係令佢慢 1.8 倍,
   所以呢個門檻夾得住「真係慢」同「真係死」。
4. **`run_tests.ps1` 逐個測試加 `-TimeoutSec`(預設 3600)**,超時就殺 + 標
   `**TIMEOUT**`。以前一個掛死嘅測試會令成套跑停喺度冇聲冇息。

修完之後嘅套裝報告見下面「全套 regression」。

---

## Part D — BOSS 開場傷害上限(Gate 5a 嘅真解)

### D1. 機制

設計、常數同理由已經寫入 `docs/design/BALANCE_CHANGELOG.md`(第二十一輪段)同
`GameData.BOSS_OPEN_DPS_SHARE` 上面嗰段註。摘要:

| 常數 | 值 | 意思 |
|---|---|---|
| `BOSS_OPEN_DPS_SHARE` | 2.0 | 開場容許 DPS = 期望 DPS × 2 = **12.5% max_hp/s** |
| `BOSS_OPEN_BANK_SECONDS` | 2.0 | 漏桶最多儲 2 秒額度 = **25% max_hp**,boss 一出場滿桶 |
| (推論)最短 boss 戰 | **6.0 秒** | (1 − 0.25) ÷ 0.125 |

**點解係漏桶唔係乘數:**乘數會按比例扣走每一個玩家嘅傷害,即係「拖時間懲罰
正常火力」。漏桶只會咬「一秒之內想食超過 12.5% 血」嗰種輸出 —— 一個 on-curve
玩家係 6.25%/s,**打得好一倍嘅玩家都仲喺上限之下**。

**點解一出場就滿桶:**第一炮照樣打甩四分一血條,爆發嘅**手感**留返。桶封頂,
所以「唔開火儲一大舊再一次過爆」呢條路都封死 —— 儲極都係 25%。

**執行點只有一個。** `Monster._boss_absorb()`,由 `take_hit()` 同 `_deal_dot()`
兩處呼叫,而呢兩條就係全遊戲所有扣 boss 血嘅路。同 `BOSS_HEAL_CAP` 一樣係
結構鎖:將來新加嘅塔 / 魔法 / 進化機制自動受制,唔使有人記得。

**回饋:**食走咗嘅傷害唔會靜靜雞冇咗 —— 出一個鋼藍色格擋光環(節流 0.35 秒,
因為一次爆發可以喺同一幀撞十幾下),而且傷害數字唔會印一個誤導嘅「0」。

**A/B 開關:**`--nobossfloor`(`GameData.boss_floor_enabled`)。唔係遊戲設定,
冇任何 UI 掂得到佢 —— 佢淨係為咗「同一個 build 關咗個鎖再跑一次」呢個對照組
而存在,因為冇對照組就講唔出個鎖郁咗幾多。

### D2. 全 20 塔 × 魔法組合冇其他「秒 boss 捷徑」

掃咗三層:

1. **API 層。** `Monster` 上面所有會扣血嘅入口:`take_hit`(phys / magic / true)、
   `take_true`(直接叫 `take_hit`)、`_deal_dot`(灼燒 / 劇毒 / 戰吼 T3 濺射)。
   兩個扣 `hp` 嘅位而家都經 `_boss_absorb`。`try_execute`(狙擊塔斬殺)本身
   已經 boss 免疫;冇任何「放逐 / 移走目標」類機制存在。
2. **呼叫端層。** 全 `scripts/battle/` 33 個扣血呼叫點逐個睇過,全部行上面
   三個 API。爆發魔法逐個確認:天雷誅殺(`bossdmg + bosspct × max_hp`)、
   龍捲風 T3(`GALE_TRUE_FRAC × max_hp` 真傷)、地震術(boss 走
   `bossdmg + bosspct × max_hp`)、黑洞(經 `Hazard` → `take_hit`)、
   天罰濺射、審判日溢傷轉移、屏障反傷 —— 全部匯入同一道門。
3. **不變式層(自動守門)。** `test/BossFloorTest` 有一個 case 掃
   `scripts/battle/*.gd` 嘅原始碼,斷言除咗 `Monster.gd` 自己之外冇任何檔案
   直接寫 `.hp -=` / `.hp =`(白名單:第 100 關十隻 boss 減血之後補滿嗰句)。
   下一輪加新塔嘅時候,呢條會捉到「有人繞過咗個鎖」而唔使人記得去試。

### D3. `test/BossFloorTest.tscn`(22 項,PASS)

```
BOSSFLOOR INFO 保證窗口 6.0 秒,boss 喺窗口入面行咗:
  lv12 4.1% / lv40 5.7% / lv71 4.8% / lv84 4.1% / lv99 4.1%
BOSSFLOOR PASS fails=0 (22 項)
```

案例:六條扣血路逐條試一炮 `1e9`(全部殺唔死,而且**啱啱好**打甩滿桶 25%,
少過就係鎖得太緊、多過就係漏)、無限傷害之下要行足 6.00 秒先死、
擺十秒唔打個桶都唔會儲多過 25%、1× 同 2× on-curve 火力零損耗、
雜兵一炮照死、常數自洽、原始碼不變式。

「行出開場區」呢句嘢用嗰行 INFO 講:6 秒之內 boss 行咗成條路嘅 **4.1–5.7%**
(換算約 100–150 world px,即係由出怪口行到第一段有塔守嘅路面)。呢個數係
報返出嚟嘅,唔係目標 —— 想 boss 行遠啲就要調大 `BOSS_OPEN_BANK_SECONDS` 或者
調細 `BOSS_OPEN_DPS_SHARE`,而兩者都會開始咬到「打得好一倍」嗰批玩家。

### D4. Gate 段界重釘

* **Gate 5a:A2 71–99 ≤9% → ≤12%**(已議定)。寫入 `tools/gate_report.py` 嘅
  判定同檔頭說明、`docs/design/BALANCE_CHANGELOG.md` 嘅 gate 表。
* **Gate 7 段界:41 / 71 / **91** → 41 / 71 / **81****,即係段變成
  1–10 / 11–40 / 41–70 / **71–80 / 81–99**。理由:段界嘅意思一路都係「雙
  tier-3 完成帶」,而 `TIER_JUMP` 1.70 → 1.95 之後 A3 課完第二件 tier-3 嘅
  時點提早咗一個 block(第十七輪實測 85–95)。縫擺喺完成點**之後**,嗰個回升
  就會落喺 81–90 呢個 block 入面被當成段內回升而肥佬,而佢其實同 41
  (tier-2 入口)/ 71(tier-3 入口)完全同一性質。同樣寫入 `gate_report.py`
  嘅 `G7_SEGS` + 印出嚟嗰行說明 + changelog(舊段落加咗指返新定義嘅註)。

### D5. 實裝前後嘅 Gate 5a 讀數 —— **個鎖做到咗佢承諾嘅嘢,但佢郁唔到 Gate 5a**

A/B 用**同一個 build、同一批 seed(0–7)、同一條命令**,唯一分別係
`--nobossfloor`。兩邊各 8 個完整 100 關 campaign(232 個 71–99 樣本)。

| | Gate 5a(A2 71–99) | Gate 4b(A2 41–70) | Gate 7 段內回升 |
|---|---|---|---|
| 關咗個鎖(對照組) | **19.8%** | 78.3% PASS | +4.7 點 PASS |
| 開咗個鎖 | **19.4%** | 77.9% PASS | +4.7 點 PASS |

**19.8% → 19.4%,即係冇郁過**(0.4 點,遠細過 8-seed 嘅雜訊)。呢個係本輪
最重要嘅一個讀數,所以逐關拆開睇(只列有分別嗰啲):

| 關 | 關咗鎖 | 開咗鎖 | Δ | 平均戰鬥秒數(前 → 後) |
|---|---|---|---|---|
| 71 | 100% | 100% | 0 | 102.1 → 101.3 |
| **75** | 87.5% | **50.0%** | **−37.5** | 113.5 → 106.9 |
| 78 | 100% | 100% | 0 | 115.0 → 114.2 |
| 81 | 100% | 100% | 0 | 102.5 → 101.3 |
| **84** | 87.5% | **75.0%** | **−12.5** | 116.7 → 116.0 |
| 90 / 93 / 98 | 0 / 0 / 37.5% | 12.5 / 12.5 / 50% | +12.5 各 | (各 1 個 seed = 雜訊) |

#### 診斷:71 / 78 / 81 唔係「秒 boss」贏返嚟嘅

Jack 個 brief 點名嘅五關係 71 / 75 / 78 / 81 / 84。實測**個鎖只咬到 75 同 84**
(合共 −5 場),而 71 / 78 / 81 **一場都冇跌**。

點解知道唔係鎖唔夠狠:呢三關喺**兩邊**嘅平均戰鬥時間都係 101–115 秒,
即係打足成個波次直到接近時限先收 —— 換句話講,A2 喺嗰三關嘅勝利由頭到尾
都唔係「boss 一出場就冇咗」,而係**佢捱得住成個波次**。個鎖只管 boss 出場
之後嗰 6 秒,所以佢喺嗰三關**冇嘢可以做**。調大鎖(拉長窗口 / 收窄上限)
一樣郁唔到佢哋,只會開始咬到「打得好一倍」嗰批玩家。

反過來,75 同 84 嘅戰鬥時間喺兩邊都係 106–117 秒,但**勝率跌咗** —— 呢兩關
先係「boss 就係嗰個決勝點」嗰種,而個鎖正正咬中咗佢哋。所以個鎖**唔係冇用**,
佢係**用啱咗地方但地方唔夠多**。

#### 所以 Gate 5a 嘅剩餘部分係難度曲線問題,唔係 boss 爆發問題

19.4% 入面,71 / 78 / 81 三關(全勝)自己就貢獻咗 3 × 8 = 24 場,
即係 232 個樣本入面嘅 **10.3 點**。淨低 9.1 點分散喺 72 / 74 / 75 / 84 / 98。
即係話:**就算 boss 爆發嘅路完全封死,單靠嗰三關 A2 都已經過唔到 ≤12%**
(10.3 點加任何嘢都貼住條線)。要 5a 落到 12% 以下,要郁嘅係 71 / 78 / 81
嗰三關對 A2 嘅波次壓力 —— 而嗰個係難度曲線嘅決定。

**照 brief 嘅規定,呢度停手,唔自行重新調平衡。** 可以郁嘅掣同佢哋嘅副作用
(供 Jack 決定):

| 掣 | 郁佢會點 | 副作用 |
|---|---|---|
| `WAVE_BANDS` 71–99 段(而家 1.054) | 直接壓 71–99 全段 | A3(Gate 5b ≥28%)一齊跌,而 5b 而家就係靠呢一段 |
| `path_factor` / `fam_mix_norm` 喺 71+ 嘅權重 | 專門修 71 / 78 / 81 呢啲「A2 專贏」孤島 | 第十七輪已經做過一次歸一化,再加係加第二層修正器 |
| `BOSS_SPAWN` rate(圍城部隊) | 令「拖長」有代價 | 第十七輪試過,單獨唔夠殺孤島 |
| 接受 5a ~19% | — | 71–99 段本來就係 farm-intended;≤12% 呢個目標本身係咪啱要 Jack 判 |

**要留意:對照組自己量到 19.8%,而 brief 講嘅係 14.9%。** 兩個數唔同 sample
(8 seed vs 之前嗰輪嘅樣本),所以定版 20-seed 嘅數先係要釘落去嗰個。
但兩個數都 > 12%,而 A/B 嘅**差**(0.4 點)先係本節嘅結論,佢同絕對值無關。

### D6. Gate 5b(A3 ≥28%)有冇跌穿

個鎖對 A3 一樣生效,但 A3 唔靠秒 boss 贏,佢靠持續火力(on-curve DPS 遠低過
12.5%/s 嘅上限),所以理論上唔受影響。實測數字喺定版表(A3 20 seed)——
見下面「定版讀數」。

---
