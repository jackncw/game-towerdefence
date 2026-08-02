# 第十輪報告 — 閃退修復 / 巫教反制 / 聖光重做 / 進化系統

日期:2026-08-02。還原點 tag:`pre-round10`(= `6ceaf81`)。

---

## TL;DR

| 階段 | 結果 |
|---|---|
| A 閃退 | **冇喺任何環境重現到**。查嘅過程、排除咗嘅假設、同埋而家常設嘅取證手段全部喺 §1。順手修好一個真 bug、剷咗 `.godot` 全量 reimport 驗過 cache 冇壞、關咗兩個 round 9 遺留項目。36 場連續戰鬥 exit 0。 |
| B 巫教反制 | 六個,塔三個魔法三個,全部係**削治療 / 熄光環**,冇一個係加傷害。36 條斷言。 |
| C 聖光塔 | 全圖光環 + 遞減疊加 + 新軸「聖光強度」+ 存檔 v2 全額退款 + 全場視覺表現。 |
| D 進化系統 | 105 項 tier 表(由資料 dump),**70 個新機制全部實裝**,40 塔 sprite + 30 魔法 icon,存檔欄位,升級介面進化區,儀式演出,專屬音效。 |
| E 收尾 | 25 個測試全綠,art_export 61 張自審,web 重建,BALANCE_CHANGELOG 續寫。 |

**三個平衡數字被量度改咗**(升級價曲線、敗仗獎勵擬合、第 21 關起嘅 wave scaling),
每個嘅 before/after 喺 §5 同 `BALANCE_CHANGELOG.md`。

---

## 1. 閃退 — 查唔到,但下一次一定捉得到

### 誠實嘅結論先講

**我喺呢一輪冇重現到嗰單閃退。** 唔係「應該修好咗」—— 係查唔到。
所以呢一節嘅重點唔係一個 root cause,係「下次再發生嗰陣,證據會自己留低」。

### 做過乜、排除咗乜

| 假設 | 點驗 | 結果 |
|---|---|---|
| `.godot/` import cache 被上輪 stray process 整污糟 | 全量 hash 1799 個 imported 檔 → 剷 `.godot/` → `--import` → 再 hash → 逐個對 | **證偽**。424 個差異全部係「之前有、而家冇」嘅舊 QA 截圖 import,冇一個檔嘅內容對唔上。 |
| 音效系統喺 5x 大量併發之下爆 | 36 場戰鬥,每場 40 座塔 + 5x + 魔法連放,windowed(真音效驅動)同 headless 各跑過 | 冇重現 |
| QuickBar 共用常量喺主選單 / 戰鬥兩邊 instantiate 嘅時序 | soak 每輪都入一次選單畫面,包括 QuickBar;真流程階段行 `change_scene_to_file` | 冇重現 |
| Android entropy 修補失效(上一輪嗰單 `/dev/random` → `/dev/urandom`) | 對 `%APPDATA%\Godot\export_templates\4.7.1.stable` 同 `tools/android_template_fix/*_orig.apk` 嘅檔案大細 | 兩個 template 都仲係改過嘅版本,修補冇甩 |

### 反而搵到嘅真 bug(soak 捉到)

離開戰鬥嗰陣如果圖鑑 overlay 仲開住,`tree_exited` 會喺一個**仲係 valid 但已經
唔喺 tree 入面**嘅 HUD 上面行,而 `get_tree()` 對一個冇 tree 嘅節點返 null ——
下一行就 index 咗 null 嘅 `paused`。`is_instance_valid(self)` 答緊嘅唔係
呢度真正要問嗰條問題。每次咁樣離開戰鬥都會喺引擎 log 度留低兩行 error。

### 常設嘅取證手段(唔係臨時工具)

1. **引擎 file logging** → `user://logs/godot.log`,有 `push_error` / 腳本錯誤嘅
   完整 stack trace。PC 本身預設就開,但 **Android / Web 唔係** —— 而報告嚟自
   嗰兩邊,所以要明寫落 `project.godot`。
2. **`Crash.gd` 未關門標記 + 麵包屑**。開場寫 marker,正常退出刪走;
   下次開場見到舊 marker = 上次非正常結束 → 抄入 `user://logs/crash.log`。
   麵包屑係事件唔係逐幀:場景切換、開場收場、放塔、轉速、語言切換。
   Marker 記住 pid,所以同機開兩個 instance 唔會報一單冇發生過嘅閃退
   (呢個假陽性我自己撞過一次)。

### Soak test

`test/SoakTest.gd`。同其餘測試相反 —— 唔手動餵 delta,行真幀、真 `_process`、
真 `Engine.time_scale`、真 `change_scene_to_file`。兩個階段:

* **A 孤立戰鬥**:40 座塔、5x、魔法連放、中途賣塔轉速加塔、開關抽屜、暫停、
  圖鑑 overlay,打到 boss 死或者 110 秒遊戲時間。
* **B 真流程**:主選單 → 選關 → 戰鬥 → 結算 → 主選單 → 選單畫面。
  `change_scene_to_file` 係延遲釋放成個現行場景,而戰鬥收場嗰陣仲有計時器、
  tween、pool 節點喺度 —— A 嗰種 `queue_free` 唔行同一條路。

**判斷標準係 exit code**,唔係腳本自己講嘅一句 PASS。

### Round 9 兩個遺留項目

* **`Tower._event_snd_at` 由 static 搬入 Battle**。static 即係時間戳跟住**腳本**
  活:離開再入返同一關,新一場開頭嗰下號角會被上一場最後嗰下靜靜咁丟;
  測試之間亦都會漏過去。
* **i18n placeholder 對齊檢查入咗測試套件**。比較嘅係**集合**唔係次數 ——
  同一個佔位符用兩次係譯者嘅正當選擇,但「一邊有、另一邊冇」就一定係漏。
  漏咗一個 `{n}` 會 format 出一句文法完整但冇數字嘅廢話,冇 error 冇 warning。
  I18nTest 由 688 條變 1003 條。

### 已知限制

呢一節冇答到「點解會閃退」。如果再發生:
`user://logs/crash.log` 會有最後幾十個麵包屑,`user://logs/godot*.log` 會有
stack trace。兩份證物擺埋同一個資料夾。

---

## 2. 巫教族反制

問題唔係「巫師血厚」,係「巫師令其他嘢唔會死」。對住一個回得返嘅目標加輸出係
一場冇終點嘅軍備競賽 —— 所以六個反制**冇一個係加傷害**。

| 方向 | 載體 | 效果 |
|---|---|---|
| 削治療 | 毒液塔「重傷」 | 中毒目標所受治療 −50%,跟「每層毒傷」軸加深,封頂 85% |
| 削治療 | 劇毒瘴氣 | 範圍內治療 −70% |
| 熄光環 | 磁暴脈衝 | 暈眩 / 凍結期間光環(治療 + 加速)完全失效 |
| 破減免 | 光束塔「融甲蝕魔」 | 護甲**同**魔抗一齊削,而唔係轉成易傷 |
| 點名 | 狙擊塔 / 導彈塔 | 射程內有支援型單位就先打佢 |
| 點名 | 天雷誅殺 | 對支援型單位增傷,而且目標亦優先揀支援型 |

三個實作決定:

* **治療減免係 `Monster` 上面一個通用狀態**,唔係逐個機制各寫一套。全部治療
  都經 `request_heal()`,所以將來加嘅任何治療來源自動受制。同 boss 回復上限
  一樣,一個 enforcement point。
* **兩個來源取最大值,唔係相加**。50% + 70% = 130% 唔係一個強 debuff,係一條
  免疫,而免疫會令呢一族由「難打」變成「冇存在意義」。
* **重傷跟嗰條軸嘅等級,唔係跟 `pstack` 嘅數值**。數值跟 tier 放大十六倍,
  所以跟數值就會令 tier 2 毒液塔白白撞到封頂 —— 進化順手偷埋一條軸嘅投資。
  **呢個係測試捉返嚟嘅。**
* **「優先巫師」係硬規則,唔係一個目標選單**。5x 之下冇人會逐座塔開下拉選單,
  而「後排治療者最重要」係一個永遠成立嘅答案,唔係一個情境判斷。

圖鑑巫教族頁加咗「剋制」一段(只喺有寫過剋制法嘅族出現 —— 一句對每一族都
成立嘅提示等於冇提示)。

**測試**:`test/CounterTest.tscn`,24 條。斷言嘅係行為唔係常數 —— 真係回一次血
再量返實際到帳幾多、真係電暈一個巫師再睇佢隊友有冇繼續回血、真係擺一隻肥
岩石巨像喺一隻瘦巫師隔籬再問狙擊塔揀邊個。

---

## 3. 聖光塔 — 全圖光環

* 攻速加成**冇範圍限制**,場上每一座塔受惠。
* 疊加遞減 `1.00 / 0.60 / 0.30 / 0.15 / 0.08`:兩座 1.6 倍、五座 2.13 倍。
  **呢條曲線就係呢座塔嘅全部平衡** —— 冇範圍之後唯一嘅決策係「擺幾多座」,
  而遞減曲線就係嗰個決策嘅內容。
* 舊「光環範圍」軸作廢(佢係一條純粹買覆蓋率嘅軸,入面冇任何決策),
  換成「聖光強度」:光環同時派攻擊力加成。六軸總數不變。
* **存檔遷移 v2**:嗰條軸課過嘅魔晶全額退,新軸由 0 起,其餘五軸原封不動 ——
  同詛咒塔嗰次唔同,呢座塔保住咗自己嘅身分,全部歸零就係攞走仲有意義嘅嘢。
* **視覺**:每座受惠塔頂三粒繞住轉嘅金色微光 + 聖光塔本體一條光柱。
  (`qa/r10b/25_battle_tier3.png` 睇得到。)
* 光環總量逐幀計一次,唔再係每座塔每次 `get_rate()` 行一次迴圈 —— 冇半徑要比
  之後,舊做法就係 43 座塔逐幀各自加一次同一條數。來源排序之後先乘遞減係數,
  唔排嘅話「邊座算第二座」會取決於擺塔次序。

---

## 4. 進化系統

### 規則

3 級 tier。條件 = 該項**全部**升級軸課滿 15 級 + 進化魔晶費。
進化後基礎大幅躍升、保留原特性、**加一個新機制**、外觀進化,
六條(魔法三條)軸重開 15 級,費用曲線接續。

### 三個唔顯然嘅決定

1. **倍率只打落「每秒輸出」類 stat**。射程、持續時間、機率、數量唔乘 ——
   一座 tier 3 塔覆蓋 256 倍地圖,或者一個 5% 暴擊變成必中,就唔係「長大咗」
   係「另一座塔」。
2. **升級步長跟住同一個倍率放大**。唔係嘅話 tier 3 箭塔基礎傷害 2560、
   而攻擊力軸每級仲係 +3,六條軸就變咗裝飾品。
3. **費用曲線接續,而且進化唔退錢**。`upgrade_cost` 收**全域**級數
   `lv + 15*(tier-1)`,所以 tier 2 嘅第一級貴過 tier 1 嘅第十五級。
   已經課落去嘅嘢化成 tier 躍升本身;退錢會令進化變成一個免費 respec。

### 系統接駁

* **升級介面**:進化區**永遠喺度**,唔係夠條件先出現 —— 一個只有夠條件先見到
  嘅區塊等於一個秘密。未夠條件係剪影 + 「差幾多」(3/6 條軸滿),夠條件亮起
  下一階嘅名同新機制一句,滿階換金印。
* **儀式演出**:全螢幕金光一閃 + 專屬音效 `sfx_evolve`(由 `sfx_unlock` 嗰個
  上行動機再延長一個八度,配一個**向上**嘅 shimmer —— 遊戲入面其餘每個獎勵聲
  都係衰減嘅,呢個係唯一一個喺最後一粒音之前越嚟越響嘅,所以佢聽落係「到咗」
  唔係「知道咗」)。
* **戰鬥**:塔按當前 tier 出貨(sprite / 數值 / 機制);塔卡、快捷槽、魔法卡
  加階級星星;魔法 icon 邊框跟階演進(銀邊 2 粒 → 金邊 3 粒 + 角花)。
* **存檔**:`tower_tiers` / `spell_tiers` 兩個欄位。冇呢兩個欄位嘅舊存檔一律
  當全部 tier 1 —— **冇遷移步驟**,因為「冇記錄 = 第一階」本身就係預設值。
  手改到離譜嘅值會被夾返 1..3。
* **美術**:40 塔 + 30 魔法。唔係 70 幅新畫,係 tier 1 嗰幅加一層**處理**,
  同怪物等級嗰套一樣(細節疊加 / 氣場 / 配色升華)—— 因為咁樣先讀得出
  「同一座塔,長大咗」而唔係「另一座名similar嘅塔」。三條通道:地基生長、
  光環同環繞光點(全部畫喺剪影**後面**)、每座塔一個專屬點綴。

---

## 5. 平衡 — 三個被量度改咗嘅數

完整推導喺 `BALANCE_CHANGELOG.md` 第十輪。

### 5.1 升級價曲線加第二段

`BalanceSim --evolve`(第 1-40 關,專精玩家)第一次量:

| | tier 2 出現 | tier 3 出現 |
|---|---|---|
| 未改 | 第 **32** 關 | 冇出現過 |
| 改咗 | 第 **24** 關 | 第 **37** 關 |
| 目標 | 15-25 | 30+ |

樽頸唔係進化費(6,000,佔 7%),係六條軸嘅尾巴(75,000,佔 88%)。
舊曲線 `base * 1.35^lv` 之下第 15 級單獨收 45 倍 base ——
**最後三級貴過頭十二級加埋**。冇任何嘢需要過「六條全部滿」,所以冇人望過。

頭 6 級照舊 1.35,之後轉 1.10。**頭六級一個仙都冇平過**,所以已經出過街嗰
二十關嘅節奏冇被掂到(`--playthrough` 重跑:20/20 一次過、冇卡關,同第八輪
記錄嘅基準一致)。

### 5.2 敗仗獎勵重新擬合,而且換咗模型

C(N)(玩家下一級升級嘅中位價)係量出嚟嘅,而敗仗獎勵釘住佢。曲線一改,
實測 C(N) 由 45→804 變成 45→439,舊擬合仍然以 1.1668 增長 —— 第 20 關嘅
敗仗會派 C(20) 嘅 **2.3 倍**,即係「贏」變成可選項。

| | 舊擬合 | 對數最小二乘 | **兩段擬合** |
|---|---|---|---|
| 對實測 45/199/439 | 47/188/804 | 55/170/528 | **45/199/438** |
| 「輸一場 >= 一級」 | — | 14/20 | **20/20** |
| 敗/C 比率 | 1.20-2.30 | 0.94-1.45 | **1.00-1.28** |

C(N) 之所以係凹嘅,係因為升級價曲線本身係兩段。模型跟返被模型嗰樣嘢嘅形狀。

### 5.3 wave scaling 第 21 關起 1.13 → 1.28

二十關嘅曲線係喺一個「冇進化、六條軸永遠課唔滿」嘅世界入面定嘅。進化上線
之後量到一次過通過率 40/40 —— 難度曲線唔係變淺,係由第 20 關開始就冇咗。
第 1-20 關嘅 `wave_scale` 一個字都冇變。

**量難度改用「贏嘅幅度」。** 通過率係飽和訊號(贏就係 1),而且呢個 harness
用金買塔、金收入又跟住 `wave_scale` 走 —— 敵人硬十倍佢就買十倍塔。所以
`--evolve` 加咗塔數上限(第 1 關 6 座 → 第 40 關 26 座),再用 `sim_max_frac`
(全場敵人行得最深嘅路程比例)做主指標:

| 關段 | 平均最深推進 |
|---|---|
| 1-20 | 9% |
| 21-30 | 26% |
| 31-40 | 27% |

**讀法**:每次進化之後嗰兩三關推進率跳上 40-65%(玩家啱啱食完力量),之後
隨住佢再課軸跌返落 5-15%,直到下一個斷層。呢個一升一跌就係「進化 → 再課 →
再進化」呢個循環喺數字上面嘅樣 —— 亦即係「唔准一 tier 通殺」成立嘅證據。

---

## 6. 測試

25 個測試場景,全部 headless、exit 0。新增三個。

| 測試 | 結果 |
|---|---|
| SoakTest(新) | `SOAK PASS rounds=30 battles=36 flow=6` |
| CounterTest(新) | `COUNTER PASS fails=0`(36 條) |
| EvolveTest(新) | `EVOLVE PASS fails=0`(49 條,包括介面實撳嘅完整流程) |
| I18nTest | `1003 passed, 0 failed`(round 9 係 688) |
| AudioHookTest | `PASS fails=0`(65 個註冊音全部有人派) |
| 其餘 20 個 | 全部 PASS |

`EvolveTest` 嘅 D7 係**由介面撳落去**:起返成個升級畫面、搵嗰粒進化掣、
emit `pressed`、再問返 Meta。前面五個 case 全部直接叫 API —— 而一個
「`Meta.evolve()` 啱但個掣冇接到」嘅世界喺嗰五個 case 底下係全綠嘅。

---

## 7. 視覺自審 + web

三次全量 art_export,每次 61 張:`qa/r10b/`(修正後)、`qa/r10_en/`、
`qa/r10_zh/`。兩種語言都逐張對過進化區、圖鑑剋制段、底欄階級星星 ——
冇一處爆框或者被切走。

**Web export** 重建:`docs/index.pck` 7.1 MB(round 9 修完之後係 6.9 MB;
多咗嗰 0.2 MB 就係 70 張進化圖 + 一個新音效)。驗過 pack 入面
`sfx_evolve` / `tower_1_t3` / `spell_13_t2` 三個都喺,而 `art_r*` / `*_shots/`
一個都唔喺 —— 排除規則仍然有效。

自審捉到同修好嘅:

1. **tier 3 光柱畫成咗實色**,一條硬柱直穿二十座塔嘅剪影 —— `ImageDraw` 係
   **覆蓋** alpha 唔係混合,所以半透明填色畫落去會變成不透明。改成合成喺
   下面(`Canvas.aura()` 本身已經解過同一個問題)。
2. **進化掣壓住「全部軸已滿」嗰句提示**最後半行(英文兩行、繁中一行)。
   高度按最長嗰個語言訂 —— 一句被切走一半嘅提示比冇提示更差,因為佢睇落
   好似完整咁。
3. **「新機制:」喺英文冇空格**(`New mechanic:Each hit...`)。改用破折號 ——
   繁中冒號後面唔加空格、英文一定要加,同一句 format 出唔到兩種標點習慣。
4. **環繞光點飛咗出塔身之外**變成兩粒散開嘅雜點,半徑由 0.42 收到 0.36。

---

## 8. 已知限制

1. **閃退冇重現到**(§1)。修好嘅係一個 soak 途中捉到嘅 error,唔一定係
   用戶見到嗰單。取證手段係常設嘅,下一次會有 log 有 stack 有麵包屑。
2. **平衡數字係模擬玩家量出嚟嘅,唔係真人**。`--evolve` 嗰個係一個**專精**
   玩家(全部魔晶灌落一座塔),即係「最快見到 tier 2」嗰種人 —— 佢見到嘅
   第 24 關係一條下限,唔係中位數。
3. **`--playthrough` 嘅塔使用率仍然係箭塔 + 冰霜塔兩座打天下**,呢個係
   harness 買嘢政策嘅老問題(只課三條核心軸),唔係呢一輪造成,亦都未修。
4. **`AudioTest` 嘅時間縮放 case 喺 headless 仍然 SKIP**(要一個真係郁得嘅
   音效驅動),同 round 9 一樣。
5. **70 個新機制嘅平衡未逐個 bench 過**。`--towers` / `--spells` 兩個 bench
   仍然只跑 tier 1。tier 2/3 有 `EvolveTest` 嘅「全部第三階打一場」做煙霧
   測試(冇腳本錯誤、打得死嘢),但「邊個 tier 3 機制過強」呢條問題未問過。

---

## 9. 每階段 commit

| 階段 | Commit | 標題 |
|---|---|---|
| A | `5f6467f` | Make a crash leave evidence, and give it 30 battles to happen in |
| B + C | `575fc76` | Answer the cultists by cutting healing, not by adding damage; make the Radiance aura cover the board |
| D | `676beec` | Give every tower and spell two more lives, and let the measurement pick the numbers |
| E | `be801c5` | Look at the evolution screen in both languages, and say plainly that the crash was not reproduced |

還原點:`pre-round10`(`6ceaf81`)。

---

## 10. 完整 tier 表(105 項)

下面呢張表由 `tools/dump_tiers.gd` 直接讀 `GameData.TOWER_TIERS` /
`SPELL_TIERS` 同真正嘅 `tr()` dump 出嚟。一份手寫嘅表由簽字嗰一刻就開始同
程式碼分家;呢張唔會。

## 塔 (20 x 3 = 60)

| # | 階 | 繁中 | English | 新機制 (繁中) | New mechanic (EN) |
|---|---|---|---|---|---|
| 1 | T1 | 箭塔 | Arrow Tower | — (基礎形態) | — (base form) |
| 1 | T2 | 鷹眼塔 | Hawkeye Bastion | 雙重射擊變三連;對同一目標連續命中會層層疊加傷害,換目標則歸零。 | The double shot becomes a triple, and every consecutive hit on the same target stacks bonus damage — switching targets resets it. |
| 1 | T3 | 神射殿 | Sagittarian Sanctum | 每第五支箭必定暴擊,並貫穿沿途所有敵人。 | Every fifth arrow always crits and punches through everything in its line. |
| 2 | T1 | 加農砲台 | Cannon Battery | — (基礎形態) | — (base form) |
| 2 | T2 | 雙管砲塔 | Twin Bombard | 每發砲彈在落點爆炸兩次,第二次範圍更大。 | Every shell detonates twice on impact, the second blast wider than the first. |
| 2 | T3 | 攻城巨砲 | Siege Colossus | 破城彈:爆炸範圍內的敵人永久失去護甲,可疊加。 | Breaching shot: everything caught in the blast permanently loses armor, and it stacks. |
| 3 | T1 | 雷電塔 | Thunder Spire | — (基礎形態) | — (base form) |
| 3 | T2 | 雷霆之柱 | Storm Pillar | 被閃電擊中的敵人成為導體,下一次連鎖必定經過牠並額外增傷。 | A struck enemy becomes a conductor: the next chain is guaranteed to route through it and hits harder for doing so. |
| 3 | T3 | 天罰穹頂 | Empyrean Dome | 連鎖結束後在最後一個目標頭頂再降一道落雷,範圍傷害兼麻痺。 | When the chain ends, a bolt falls on the last link — area damage and a guaranteed stun. |
| 4 | T1 | 火球塔 | Fireball Tower | — (基礎形態) | — (base form) |
| 4 | T2 | 煉獄塔 | Infernal Tower | 燃燒中的敵人死亡時原地留下一灘餘燼,持續灼燒。 | An enemy that dies while burning leaves a pool of embers behind it. |
| 4 | T3 | 炎魔祭壇 | Pyre of the Efreet | 引爆成功時,爆炸把燃燒狀態傳染給範圍內所有敵人。 | A successful detonation spreads the burn to everything inside the blast. |
| 5 | T1 | 冰霜塔 | Frost Tower | — (基礎形態) | — (base form) |
| 5 | T2 | 極寒塔 | Glacial Spire | 被減速的敵人累積凍傷層,凍結成立時一次過引爆為真實傷害。 | Slowed enemies accumulate frostbite, and a freeze detonates every stack at once as true damage. |
| 5 | T3 | 永冬王座 | Throne of Everwinter | 射程內的地面永久結冰,經過的敵人自帶額外減速。 | The ground inside its range freezes over for good — anything that walks it is slowed on top of everything else. |
| 6 | T1 | 毒液塔 | Venom Tower | — (基礎形態) | — (base form) |
| 6 | T2 | 瘟疫塔 | Plague Spire | 毒層滿的敵人死亡時,把整疊毒層傳染給附近的敵人。 | When an enemy dies at full stacks, the whole stack jumps to the nearest bodies. |
| 6 | T3 | 腐化聖殿 | Sanctum of Rot | 毒素崩解:每滿一定毒層,目標的生命上限永久下降。 | Rot: every full load of stacks permanently eats into the target's maximum health. |
| 7 | T1 | 狙擊塔 | Sniper Nest | — (基礎形態) | — (base form) |
| 7 | T2 | 鷹巢哨站 | Eagle Roost | 每次命中留下致命標記,標記越多下一發越痛,擊殺時清空。 | Each hit leaves a killing mark; the more marks, the harder the next shot lands. A kill wipes them. |
| 7 | T3 | 天罰狙擊台 | Judgement Perch | 處決線大幅提高,而且處決成功後下一發必定暴擊。 | The execute threshold climbs sharply, and a successful execute guarantees a crit on the next shot. |
| 8 | T1 | 機槍塔 | Gatling Tower | — (基礎形態) | — (base form) |
| 8 | T2 | 旋風機炮 | Cyclone Repeater | 熱度滿的瞬間釋放一圈環形彈幕,然後熱度減半繼續。 | The instant heat maxes out it sprays a ring of fire, then halves the heat and keeps going. |
| 8 | T3 | 風暴壁壘 | Storm Bastion | 換目標不再清空熱度,只減半;熱度同時提升散射機率。 | Switching targets no longer dumps the heat, only halves it — and heat now drives the spread chance too. |
| 9 | T1 | 迫擊砲 | Siege Mortar | — (基礎形態) | — (base form) |
| 9 | T2 | 重砲陣地 | Heavy Battery | 每次開火發射兩發彈道錯開的砲彈,覆蓋一整條線。 | Each shot puts two shells in the air on offset arcs, covering a whole line. |
| 9 | T3 | 軌道砲台 | Orbital Bastion | 校射:連續轟同一片區域會層層提升範圍與傷害,換區則歸零。 | Ranging: pounding the same patch stacks up both blast size and damage; move the impact and it resets. |
| 10 | T1 | 光束塔 | Beam Tower | — (基礎形態) | — (base form) |
| 10 | T2 | 稜鏡塔 | Prism Tower | 光束擊中後折射到附近另一個敵人身上。 | The beam refracts off its target onto whatever stands nearest. |
| 10 | T3 | 恆星核心 | Stellar Core | 蓄能滿後進入爆發模式,短時間內傷害倍增,然後重新蓄能。 | Once fully charged it overloads: damage multiplies for a few seconds, then the charge starts again. |
| 11 | T1 | 緩速力場塔 | Slowing Field | — (基礎形態) | — (base form) |
| 11 | T2 | 重力井 | Gravity Well | 場內敵人被持續拉向中心,飛行單位同樣受制。 | Everything inside is dragged back toward the centre — flyers included. |
| 11 | T3 | 時滯領域 | Chronal Domain | 每隔一段時間,場內所有敵人完全定身一瞬。 | At intervals the whole field simply stops for a moment. |
| 12 | T1 | 鍊金塔 | Alchemy Tower | — (基礎形態) | — (base form) |
| 12 | T2 | 鑄金坊 | Gilded Foundry | 場上每多一座鍊金系塔,產金效率就提升(遞減疊加)。 | Every other alchemy tower on the board raises this one's output, with diminishing returns. |
| 12 | T3 | 賢者之塔 | Philosopher's Spire | 射程內的敵人死亡時有機會直接煉成一筆額外橫財。 | An enemy dying in range may be transmuted outright into a windfall. |
| 13 | T1 | 兵營塔 | Barracks Tower | — (基礎形態) | — (base form) |
| 13 | T2 | 要塞營地 | Garrison Keep | 陣型:士兵互相靠近時同時獲得額外護甲與傷害。 | Formation: soldiers standing together gain armor and damage from each other. |
| 13 | T3 | 聖殿騎士團 | Templar Order | 不屈:士兵陣亡時原地爆發,造成範圍傷害並擊退。 | Undying: a fallen soldier detonates where it stood, damaging and throwing back everything around it. |
| 14 | T1 | 迴旋鏢塔 | Boomerang Tower | — (基礎形態) | — (base form) |
| 14 | T2 | 雙刃塔 | Twinblade Tower | 同時擲出兩把成夾角的迴旋鏢,交叉點的敵人吃兩次。 | Throws two blades on crossing arcs — anything at the intersection takes both. |
| 14 | T3 | 風暴之輪 | Tempest Wheel | 迴旋鏢回程後有機會立即再擲出,不消耗攻速。 | A returning blade may be flung straight back out at no cost to the fire rate. |
| 15 | T1 | 荊棘塔 | Bramble Tower | — (基礎形態) | — (base form) |
| 15 | T2 | 食人花巢 | Carnivore Nest | 纏繞:每次觸發把範圍內最前的敵人短暫定身。 | Ensnare: every trigger roots whichever enemy is furthest along the road. |
| 15 | T3 | 世界樹根 | Worldroot | 根系沿著道路蔓延,覆蓋範圍不再是一個圓而是一整段路。 | The roots run along the road itself — the reach stops being a circle and becomes a stretch of path. |
| 16 | T1 | 導彈塔 | Missile Tower | — (基礎形態) | — (base form) |
| 16 | T2 | 多管火箭 | Rocket Array | 追蹤鎖定:對同一目標連續命中,該目標受到的導彈傷害層層提升。 | Lock-on: consecutive hits make the same target take more and more missile damage. |
| 16 | T3 | 末日發射井 | Doomsday Silo | 每隔數次齊射改射一枚巨型彈頭,傷害與範圍暴增並必定擊退。 | Every few salvos becomes one enormous warhead: far more damage, far wider blast, guaranteed knockback. |
| 17 | T1 | 詛咒塔 | Curse Tower | — (基礎形態) | — (base form) |
| 17 | T2 | 夢魘之環 | Nightmare Ring | 恐懼:光環內的敵人會定期被嚇退一小段路。 | Dread: enemies inside the ring are periodically driven back down the road. |
| 17 | T3 | 虛空祭壇 | Voidspire | 獻祭:光環內的死亡累積虛空能量,滿了就對全場引爆真實傷害。 | Sacrifice: kills inside the aura charge the void, and a full charge detonates as true damage across the whole field. |
| 18 | T1 | 聖光塔 | Radiance Tower | — (基礎形態) | — (base form) |
| 18 | T2 | 黎明聖壇 | Dawn Sanctum | 全場光環額外附帶暴擊率;本塔對支援型敵人造成額外傷害. | The field-wide aura also grants crit chance, and this tower hits support casters harder. |
| 18 | T3 | 神諭光柱 | Oracle Beacon | 復甦之光:定期為全場補回一名陣亡士兵,並清除敵人的加速狀態。 | Rekindling: on a timer it restores a fallen soldier anywhere on the field and strips haste off every enemy. |
| 19 | T1 | 磁力塔 | Magnet Tower | — (基礎形態) | — (base form) |
| 19 | T2 | 斥力核心 | Repulsor Core | 磁軌:被推撞的敵人互相碰撞,擠得越密傷害越高。 | Railslam: shoved enemies collide with each other — the tighter the crowd, the more it hurts. |
| 19 | T3 | 極性風暴 | Polar Storm | 極性反轉:每隔幾次脈衝改為吸引,把敵人拉成一團。 | Polarity flip: every few pulses it pulls instead of pushes, packing the enemy into one heap. |
| 20 | T1 | 傳送塔 | Warp Tower | — (基礎形態) | — (base form) |
| 20 | T2 | 空間裂隙 | Rift Gate | 回溯:傳送成功時清除目標身上的所有增益。 | Rewind: a successful warp strips every buff off the target. |
| 20 | T3 | 時空樞紐 | Nexus of Aeons | 放逐:有機會把非 boss 敵人直接送回起點,次數有上限。 | Banish: a chance to send a non-boss enemy all the way back to the start, up to a limit. |

## 魔法 (15 x 3 = 45)

| # | 階 | 繁中 | English | 新機制 (繁中) | New mechanic (EN) |
|---|---|---|---|---|---|
| 1 | T1 | 隕石術 | Meteor Strike | — (基礎形態) | — (base form) |
| 1 | T2 | 隕石風暴 | Meteor Storm | 主隕石之後跟著三顆小隕石落下。 | Three smaller rocks follow the main impact down. |
| 1 | T3 | 天隕滅世 | Cataclysm | 著彈點留下一片熔岩地帶,持續灼燒經過的一切。 | The impact leaves a lava field burning everything that crosses it. |
| 2 | T1 | 閃電風暴 | Lightning Storm | — (基礎形態) | — (base form) |
| 2 | T2 | 雷神之怒 | Wrath of Thunder | 每一道閃電在落點小範圍濺射。 | Every bolt splashes over a small area where it lands. |
| 2 | T3 | 萬雷天罰 | Skyfall Judgement | 被雷擊中的敵人在數秒內承受的所有傷害都被放大。 | Anything struck takes amplified damage from every source for several seconds. |
| 3 | T1 | 冰凍新星 | Frost Nova | — (基礎形態) | — (base form) |
| 3 | T2 | 絕對零度 | Absolute Zero | 凍結期間的敵人承受的傷害大幅提高。 | Frozen enemies take substantially more damage. |
| 3 | T3 | 永凍紀元 | Age of Ice | 解凍後留下一片冰原,繼續拖慢走過的敵人。 | The thaw leaves an ice field that keeps slowing whatever walks it. |
| 4 | T1 | 劇毒瘴氣 | Toxic Miasma | — (基礎形態) | — (base form) |
| 4 | T2 | 腐蝕之霧 | Corrosive Fog | 霧中的敵人護甲被持續腐蝕。 | Armor corrodes away on anything standing in the fog. |
| 4 | T3 | 瘟疫爆發 | Pandemic | 在霧中死亡的敵人會再生出一團小型毒雲。 | An enemy that dies inside the cloud seeds a smaller one where it fell. |
| 5 | T1 | 召喚民兵 | Summon Militia | — (基礎形態) | — (base form) |
| 5 | T2 | 召喚聖騎 | Summon Paladins | 召喚出來的單位帶著護盾,可擋下第一次致命傷。 | The summoned come shielded and survive the first killing blow. |
| 5 | T3 | 英靈殿軍 | Einherjar Host | 陣亡時爆炸,並把剩餘時間分給其餘同袍。 | One that falls explodes, and hands its remaining time to the others. |
| 6 | T1 | 點金術 | Midas Touch | — (基礎形態) | — (base form) |
| 6 | T2 | 黃金洪流 | Golden Tide | 除了即時金幣,一段時間內所有擊殺額外掉金。 | On top of the lump sum, every kill for a while pays extra. |
| 6 | T3 | 邁達斯權柄 | Midas Dominion | 效果期間敵人每被打中一次就掉一點金。 | While it holds, enemies shed gold every time they are hit. |
| 7 | T1 | 時間扭曲 | Time Warp | — (基礎形態) | — (base form) |
| 7 | T2 | 時之枷鎖 | Chrono Shackles | 減速期間敵人的技能節奏一併被拖慢,boss 也不例外。 | Enemy ability timers drag as well as their feet — bosses included. |
| 7 | T3 | 時光倒流 | Rewind | 施放瞬間,全場敵人退回數秒前的位置。 | On cast, every enemy snaps back to where it stood seconds ago. |
| 8 | T1 | 戰吼 | War Cry | — (基礎形態) | — (base form) |
| 8 | T2 | 軍團號令 | Legion Command | 除了攻速,全場塔同時獲得攻擊力加成。 | Attack power rises alongside the fire rate, on every tower. |
| 8 | T3 | 戰神降臨 | Avatar of War | 期間所有塔的攻擊附帶真實傷害濺射。 | While it lasts every tower's shots splash true damage. |
| 9 | T1 | 守護結界 | Aegis Barrier | — (基礎形態) | — (base form) |
| 9 | T2 | 聖域屏障 | Sanctuary Ward | 結界存在期間,基地附近的敵人持續受到傷害。 | While the ward stands, anything near the keep is burned down. |
| 9 | T3 | 不滅堡壘 | Immortal Bulwark | 每擋下一名敵人就回復一層結界,直到上限。 | Every enemy it blocks gives a charge back, up to a ceiling. |
| 10 | T1 | 龍捲風 | Tornado | — (基礎形態) | — (base form) |
| 10 | T2 | 颶風之眼 | Eye of the Storm | 龍捲風原地停留數秒,持續推回進入的敵人。 | The funnel stays put for a few seconds, shoving back anything that enters. |
| 10 | T3 | 天災風暴 | Cataclysmic Gale | 被吹飛的敵人落地時承受一筆按生命上限計算的真實傷害。 | Whatever it throws takes true damage scaled to its own maximum health on landing. |
| 11 | T1 | 地震術 | Earthquake | — (基礎形態) | — (base form) |
| 11 | T2 | 大地撕裂 | Tectonic Rift | 地面裂開,數秒內經過的地面單位被大幅拖慢。 | The ground splits open and drags at every grounded unit that crosses it. |
| 11 | T3 | 世界崩塌 | World Shatter | 地面單位被震暈,飛行單位被震落地面。 | Grounded units are stunned outright, and flyers are shaken out of the air. |
| 12 | T1 | 烈焰之牆 | Wall of Flame | — (基礎形態) | — (base form) |
| 12 | T2 | 煉獄之牆 | Infernal Wall | 火牆會沿著道路向前推進一段距離。 | The wall advances along the road instead of standing still. |
| 12 | T3 | 不熄業火 | Everburning Pyre | 每有敵人死在火牆裡,火牆就燒得更久。 | Every enemy that dies in the flames makes them burn longer. |
| 13 | T1 | 天雷誅殺 | Heaven's Wrath | — (基礎形態) | — (base form) |
| 13 | T2 | 神罰之矛 | Spear of Judgement | 對支援型單位(巫師、大祭司)的傷害再大幅提升。 | Damage against support casters climbs sharply again. |
| 13 | T3 | 審判日 | Day of Reckoning | 目標死亡時,溢出的傷害轉移到最近的另一個敵人身上。 | When the target dies, the overkill jumps to whatever stands nearest. |
| 14 | T1 | 磁暴脈衝 | EMP Surge | — (基礎形態) | — (base form) |
| 14 | T2 | 癱瘓脈衝 | Paralysis Pulse | 暈眩範圍與時間大幅延長,光環封鎖同步加長。 | Both the radius and the duration of the silence climb sharply. |
| 14 | T3 | 系統崩潰 | Total Blackout | 範圍內敵人的增益全被清除,並且一段時間內無法再獲得。 | Every buff inside is wiped, and nothing there can be buffed again for a while. |
| 15 | T1 | 黑洞 | Black Hole | — (基礎形態) | — (base form) |
| 15 | T2 | 奇點 | Singularity | 吸力更強,被困住的敵人受到的傷害逐秒遞增。 | It pulls harder, and damage on anything trapped climbs the longer it is held. |
| 15 | T3 | 事件視界 | Event Horizon | 結束時內爆,把整段時間累積的傷害再打一次。 | On collapse it implodes, dealing a share of everything it absorbed all over again. |


**合共 105 項。**
