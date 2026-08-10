# 第二十三輪(緊急修復輪)—— 第 100 關無限刷怪、永遠完成唔到

> 還原點:`9c610cc` (`level100-fix restore point`)。
> 修復範圍**只限**呢個 bug 同直接相關嘅嘢:一個平衡數字都冇郁。

---

## 0. 一句話

第 100 關嘅勝利判定係逐個問一啲**池化節點**「你死咗未」,而一隻死咗嘅 boss
個節點會即刻俾 pool 交返出嚟做雜兵 —— 於是條問題由一隻雜兵答,答「我仲生存」。
十隻 boss 真係死晒之後,關卡永遠唔結算,而第 100 關嘅雜兵 spawner 冇任何
終止條件,所以小怪一路出到天光。

---

## 1. 重現

新測試 `test/Level100CompletionTest.tscn`(下面第 4 節)喺**未修**嘅 code 上面
21 條斷言跪 6 條:

```
FAIL A 順序殺:boss 全滅之後 1.0 秒內要結算(而家 ended=false)
FAIL B 亂序殺:boss 全滅之後 1.0 秒內要結算(而家 ended=false)
FAIL D 拖長殺(每隻隔 20 秒):boss 全滅之後 1.0 秒內要結算(而家 ended=false)
FAIL E 逐潮清乾淨:boss 全滅之後 1.0 秒內要結算(而家 ended=false)
FAIL G 潮之間唔可以提早結算:第一潮清晒之後場上唔應該仲有 boss
FAIL F 池回收別名:十隻死晒之後,就算節點俾池回收咗做雜兵都要結算
```

### 觸發條件:**必然發生**(得一個逃生口)

| 殺法 | 未修 |
|---|---|
| 順序殺(每隻隔 3 秒) | 掛死 |
| 亂序殺(潮之間交叉) | 掛死 |
| 拖長殺(每隻隔 20 秒) | 掛死 |
| 逐潮清乾淨(真機報告嗰個玩法) | 掛死 |
| **極速殺(十隻喺同一幀死,中間一格模擬時間都冇)** | **正常結算** |

即係話:**唔係「殺得太快」有事,係「殺得慢過一幀」就有事。** 唯一唔中招嘅
情況係十隻 boss 喺同一幀死清光 —— 真人玩落唔可能。所以真機上面呢個 bug
係 100% 復現嘅,而 Jack 報嘅「打死前幾隻 boss 之後」只係佢**察覺到**嘅時點,
唔係觸發點。

### 直接證據(診斷探針,每隻之間隔 3 秒)

```
DIAG 出齊 10 隻 @ 160.0s  _final_wave_i=3 waves=3
DIAG 殺咗第  1 隻 → final_bosses 仲有 9 隻「生存」,其中 0 隻已經係雜兵  all_dead=false
DIAG 殺咗第  5 隻 → final_bosses 仲有 7 隻「生存」,其中 2 隻已經係雜兵  all_dead=false
DIAG 殺咗第 10 隻 → final_bosses 仲有 9 隻「生存」,其中 9 隻已經係雜兵  all_dead=false
DIAG 最終 ended=false monsters=75 spawned=279     ← 而且仲喺度加緊
```

十隻真係死晒之後,`final_bosses` 報住**九隻生存** —— 而嗰九隻全部
`is_boss == false`,即係佢哋已經係雜兵。

---

## 2. 根因

### 邊行 code

| # | 位置(修之前) | 做緊乜 |
|---|---|---|
| 1 | `Battle.gd` `_final_wave_logic()` — `final_bosses.append(m)` | 將十隻 boss 嘅**節點參照**擺入陣列,由頭到尾唔剔 |
| 2 | `Battle.gd` `_remove()` → `monster_pool.release(m)` | 一隻怪死咗,個節點還俾 pool(**唔係** `queue_free`) |
| 3 | `Pool.gd` `release()` / `acquire()` | free list 係 **LIFO**(`_free.append` / `_free.pop_back()`)—— 啱啱還返嘅節點就係下一個派出去嘅 |
| 4 | `Monster.gd` `setup()` — `alive = true` | 池化節點重用嗰陣,`alive` 設返 true |
| 5 | `Battle.gd` `final_all_dead()` — `for m in final_bosses: if is_instance_valid(m) and m.alive: return false` | **根因喺呢度。** 問一個身份已經換咗嘅節點「你死咗未」 |
| 6 | `Battle.gd` `on_boss_killed()` — 勝利判定**只**喺呢度跑 | 最後一隻 boss 死係全關唯一一個結算機會;漏咗就冇第二次 |
| 7 | `Battle.gd` `_spawn_logic()` | 第 100 關嘅雜兵 spawner **冇任何終止條件**,只靠 `ended = true` 令 `_process` 早返 |

### 點解會咁

1. 第 100 關由 30 / 92 / 160 秒放三潮共十隻 boss,同時雜兵**由頭到尾照出**
   (`GameData.FINAL_WAVES` 嗰段:「雜兵照出,俾玩家有金收入同鍊金塔有嘢做」)。
2. 一隻 boss 死 → `on_boss_killed()` → `_remove()` → `Pool.release()`,個節點
   坐喺 free stack **頂**。
3. 下一次雜兵 spawn(第 100 關間隔係 sub-second)→ `Pool.acquire()` →
   `pop_back()` → **攞返啱啱死嗰隻 boss 個節點** → `setup()` → `alive = true`。
4. `final_bosses` 入面嗰個參照由始至終指住同一個節點,而個節點而家係一隻
   生存緊嘅雜兵。`final_all_dead()` 見到「仲有嘢生存」→ 返 false。
5. 十隻死晒之後再冇 boss 會死 → `on_boss_killed()` 唔會再被叫 → **永遠冇人
   再問一次**。而 spawner 冇終止條件 → 無限刷怪。

`is_instance_valid()` 喺呢度**完全冇保護作用**:個節點由頭到尾都係有效嘅,
佢淨係換咗身份。呢個係典型嘅「只會做錯唔會報錯」—— 冇 error、冇 warning、
冇 crash,淨係一個永遠唔會 true 嘅條件。

### 逐個排查懷疑對象

| # | 懷疑 | 結論 |
|---|---|---|
| 1 | 完成條件係「boss 全滅」定「波次耗盡」?同 spawner 對唔對齊? | 完成條件係**boss 全滅**(`final_all_dead`),而 spawner **冇**「波次耗盡」呢回事 —— 雜兵無限出。兩者**設計上係對齊**嘅(spawner 靠 `ended = true` 收工),爛嘅係「boss 全滅」呢個判斷本身。 |
| 2 | boss 死晒之後邊個叫停 spawner? | 冇人專登叫停。`_win()` set `ended = true`,`Battle._process()` 第一行就 `if ended: return`。所以**成條停止鏈掛喺勝利判定上面** —— 判定唔成立,spawner 就冇嘢叫得停佢。 |
| 3 | 第 21 輪嘅「最終波豁免」有冇改咗 finale 嘅狀態流轉? | **冇。清白。** `m.floor_exempt = true` 只影響 `Monster._boss_absorb()` 嘅傷害吸收,一行狀態流轉都冇掂。證據:(a) bug 喺有豁免嘅 code 上面重現;(b) 第 21 輪報告記低嘅「完全冇鎖對照組 = 16.7%」同「第十七輪記錄嘅 16.7% 一模一樣」—— 即係呢個 bug **早過第 21 輪**,起碼由第十七輪已經喺度。 |
| 4 | Boss 死亡計數有冇漏計(同屍潮 / 分裂 / 召喚援兵撈亂)? | 事件**一單都冇漏** —— 十隻嘅 `on_boss_killed()` 全部有跑。問題係**根本冇一個計數** :每次都由節點身份重新推導狀態,而節點身份喺池化之下唔係穩定嘅。分裂 / 復活 / 召喚都唔涉事(`_die()` 對 boss 係 `limit = 0`,而 split 嗰段喺 `if is_boss: return` 之後)。 |

---

## 3. harness 條縫喺邊

### 縫一:「打輸」同「永遠打唔完」喺讀數上面一模一樣

`test/GateSim.gd` `_play()`:

```gdscript
while not b.ended and t < ATTEMPT_TIMEOUT:   # 兩個出口
    ...
var res := {"win": b.ended and Flow.last_result.get("win", false), ...}
```

兩個出口 —— `b.ended`(場結咗)同 `t >= ATTEMPT_TIMEOUT`(場**冇**結)——
出嚟嘅 `win` 都係 `false`。於是一個「關卡完成唔到」嘅遊戲缺陷,喺每一份 gate
報告入面都讀成「呢個 build 打唔低呢一關」。**一個遊戲缺陷偽裝成一個平衡讀數。**

用同一把尺(`--mode=final`)喺**未修**嘅 code 上面加返掛死偵測,量到:

| 原型 | 勝 | 掛死 | 真·敗仗 |
|---|---|---|---|
| A3 | 0 / 20 | **20 / 20** | **0** |
| A4 | 3 / 20 | **17 / 20** | **0** |

**一場真敗仗都冇。** 每一場「輸」都係掛死。而且嗰批 run 嘅
`sim_max_frac` 係 0.07–0.13(即係最深嗰隻怪只行咗成條路嘅 7–13%),
根本連基地邊都冇掂過 —— 一份「輸到 0%」嘅讀數,底下係一個由頭贏到尾嘅場。

所以 **Gate 6a「A3 ≤5% PASS」係 100% 掛死換返嚟嘅,Gate 6b「A4 16.7% PASS」
量緊嘅係一個競態嘅中獎率** ——「十隻 boss 死得夠唔夠密,密到冇一個死咗嘅節點
喺嗰一刻已經被回收成一隻生存緊嘅雜兵」。兩條 gate 由第十七輪起就冇量過難度。

### 縫二:第 100 關嘅狀態流轉從來冇被觀察過

全套測試入面掂過 `final_bosses` 嘅只有 `BossFloorTest._case_final_wave_exempt()`,
而佢淨係喺**出場嗰刻**攞 `final_bosses[0]` 驗豁免旗 —— 冇一個測試行過
「殺 → 剔走 → 結算」呢條鏈。ROW 行上面亦都冇任何一欄講得出「呢一場打死咗
幾多隻 boss」。

### 兩條縫點修

| 縫 | 修法 |
|---|---|
| 一 | `_play()` 加 `hang`(`not b.ended`)。`--mode=final` 嘅 ROW 由 4 欄變 7 欄:`arch seed win frac **hang bosses_killed time**`;`--mode=sweep` 嘅 ROW **尾**加一欄 `hang`(`gate_report.py` 全部用位置索引讀,加喺尾唔會郁到任何一欄嘅意思)。有掛死就額外印一行 `GATE HANG`。 |
| 一 | `tools/gate_report.py`:掛死喺**評 gate 之前**印,唔係一句腳註 —— 一份有掛死嘅報告入面每一格勝率都係污糟嘅。 |
| 一 | `tools/gate20.ps1`:Gate 6b 見到掛死 > 0 **直接判 FAIL**,唔會俾一個污糟嘅百分比混過去。(順手由 `-eq 6` 改 `-ge 6` 收新 ROW,舊檔照讀得。) |
| 二 | 新測試 `test/Level100CompletionTest`(下一節),入咗 regression 套件。 |

---

## 4. 修法

### 遊戲(`scripts/battle/Battle.gd`)

| # | 改動 | 點解 |
|---|---|---|
| 1 | `final_bosses` 由「十隻嘅名單」變成「**仲生存嗰啲**」—— `on_boss_killed()` 度即刻 `erase()` | 唔再靠節點身份推導狀態。個陣列變成一條不變式:入面每一個都一定係一隻未死嘅第 100 關 boss |
| 2 | `erase()` 一定要喺 `_remove()` **之前** | `_remove()` 一還節點,pool 就可以即刻交返出去,`alive` 再變 true。喺嗰之後先問「呢個節點係咪一隻死咗嘅 boss」已經冇意思 |
| 3 | `final_all_dead()` = 三潮放完 **&&** `final_bosses.is_empty()` | 兩個條件都要 —— 淨係「場上冇 boss」嘅話,第一潮同第二潮之間嗰段空窗就會即刻結算(測試 case G 守住) |
| 4 | 新 `final_boss_dead` 計數(`final_bosses.has(m)` 守住意思) | 一個明確嘅計數,俾測試同 harness 讀 |
| 5 | `_final_pick_bar()` 加 `m.is_boss` | 防禦深度:個陣列一旦漏咗剔,血條會靜靜咁跟住一隻雜兵行 |
| 6 | `_spawn_logic()` 加每幀安全網 `if final_all_dead(): _win()` | **主路仍然係 `on_boss_killed()`(同一幀結算,冇延遲)**;呢句係將「最後一隻 boss 死」由一個**一次過嘅事件**變成一個**每幀成立嘅不變式**。因為第 100 關嘅 spawner 冇終止條件,漏一次事件 = 關卡永遠完成唔到。成本:第 100 關每幀一個 int 比較 + 一個 `is_empty()` |

成條鏈:**十隻死晒 → `final_all_dead()` 成立 → `_win()` → `ended = true`
(spawner 即刻停,`_process` 第一行就返)→ `_clear_field()`(剩餘小怪清光)
→ 結算勝利。**

### harness / 工具

`test/GateSim.gd`、`tools/gate_report.py`、`tools/gate20.ps1`(見上一節)。

`tools/android_build.ps1` 嘅版本號改為由 `export_presets.cfg` 讀返。**呢度出過
一次真嘢**:`--export-release <preset>` **唔收輸出路徑** —— Godot 寫去 preset
自己嗰個 `export_path`。所以第一次出 1.0.1 嗰陣,script 印住
「export -> dist\Towerbound-1.0.1.aab」,而真正寫出嚟嘅係
`dist\Towerbound-1.0.0.aab`(內容係 1.0.1)。一隻「版本係 1.0.1、個名叫
1.0.0」嘅 aab 上到 Play Console 先發現就太遲。
修法兩層:(a) `export_presets.cfg` 兩個 preset 嘅 `export_path` 一齊改;
(b) script 開工前**逐個對**版本號同 `export_path`,對唔上即刻死,唔等出完先算。

---

## 5. 新測試覆蓋咗乜

`test/Level100CompletionTest.tscn` —— 46 條斷言,7 個 case。
每個 case 都驗成條鏈:**結算咗 + 係勝利 + 十隻都記低死咗 + `final_bosses` 清空
+ 場上零殘留怪 + 之後 5 秒 spawner 零產出**。

| Case | 情況 | 守住乜 |
|---|---|---|
| A | 順序殺(出齊十隻,每隻隔 3 秒) | 基本鏈 |
| B | 亂序殺(固定亂序,最後死嗰隻係第一潮第一隻) | 完成判定唔可以依賴殺嘅次序 |
| C | 極速殺(十隻同一幀死) | 唔可以有下限速度假設 |
| D | 拖長殺(每隻隔 20 秒,期間雜兵狂出) | 池churn 最勁嗰個極端 |
| E | 逐潮清乾淨(**真機報告嗰個玩法**) | 一潮清晒等下一潮 |
| F | **池回收別名**(逐隻死完即刻迫個池交返同一個節點做雜兵) | 唔靠時序運氣,直接砌返個 bug 嘅狀態 |
| G | **反面**:潮與潮之間唔可以提早結算 | 每幀安全網最容易錯嗰個方向 |

輔助:`_kill_boss()` 會清 `invuln_time` 再重試,因為岩石巨像個石化窗口令
`take_hit` 直接 return —— 第一版淨係打一下,喺石化窗口入面等於冇打過,而個
測試就會報一個**假**失敗(睇落同真 bug 一模一樣)。

**反向驗證做咗**:將 `Battle.gd` 還原做未修版再跑,6 條跪(見第 1 節);
還原返修好版,46/46 全過。即係呢個測試真係捉得到嗰個 bug,唔係一個
永遠會過嘅裝飾。

---

## 5b. 全 project 掃同一類 bug(補充指令 #1)

呢個 bug 唔係一單,係一**類**:「container / property 揸住一個池化節點嘅裸參照
跨越咗個節點嘅生命期」。全 project 逐個掃咗一次。

### 判定表

同一 frame 用完即棄 = 安全;跨 frame 持有 = 危險。

| # | 現場 | 判定 | 詳情 |
|---|---|---|---|
| 1 | `Battle.final_bosses` | ~~危險~~ **已修** | 本輪嘅主 bug |
| 2 | `Tower._streak_target`(鷹眼 / 鷹巢致命標記 / 多管火箭鎖定) | **危險** | 目標死咗俾池回收,而同一座塔再鎖到嗰個節點 → `tgt != _streak_target` 係 false → **層數過繼**,一隻啱啱出場嘅怪即刻食滿 `STREAK_MAX` 加成 |
| 3 | `Tower._conductor`(雷霆之柱導電) | **危險** | 原本淨係 `is_instance_valid() and .alive` —— 一個回收咗嘅節點兩樣都成立 → 條鏈優先跳去一隻從來未標記過嘅怪,仲送埋 `CONDUCTOR_BONUS` |
| 4 | `Tower.last_target`(機槍熱度 / 光束蓄能) | **危險** | 認錯人 → 熱度 / 蓄能**唔重置**,即係一個靜音嘅傷害加成 |
| 5 | `Tower.soldiers`(兵營名冊) | **危險** | 士兵一樣池化。名冊裝住一個已經轉世去第二座塔嘅士兵 → 呢座兵營名額永遠滿 → **永遠唔補兵**,而畫面上同正常兵營一模一樣 |
| 6 | `Battle.boss_ref` | **危險** | `BattleHUD` 用 `is_instance_valid() and .alive` 讀佢 → boss 血條跟住一隻雜兵跳;`boss_best_frac`(敗仗派彩)按雜兵血量計 |
| 7 | `Battle.skeleton_boss_alive` | **危險** | 過期就等於全場骷髏攞到 `AURA_REVIVE_MAX` 條命,而症狀係「怪好似死唔晒」 |
| 8 | `Projectile.target` | **本身已經啱** | 已經有 `target_serial`,`live_target()` 驗 —— 呢個就係本輪抄嘅範本 |
| 9 | `Boomerang._hit` | **本身已經啱** | 用 `m.serial` 做 key,唔係節點 |
| 10 | `Soldier.owner_tower` | 安全 | Tower **唔係**池化嘅(`queue_free`),`is_instance_valid()` 係啱嘅檢查 |
| 11 | `Battle.monsters` / `towers` / `alchemy_towers` / `holy_towers` / `curse_towers` | 安全 | `_remove()` 喺 release 之前 erase;towers 唔池化 |
| 12 | `Spells.gd` 全部 | 安全 | 純 static、無狀態 |
| 13 | `Tower._fire_magnet` 嘅 `caught`、`_fire_lightning` 嘅 `hit`、`monsters_in_radius()` 嘅 `out`、`MonsterOverlay`、`DamageField._buckets`(逐幀 clear) | 安全 | 全部同 frame 用完即棄 |
| 14 | `Hazard.extra`、`Tower._banished` / `_shot_count` / `_void_charge` / `_rangefind`、`Battle._curse_golds` / `_dbg` | 安全 | 裝嘅係數字 / 座標,唔係節點 |
| — | `Battle.selected_tower`、`Soldier` 嘅 `share_life` 掃描 | 安全 | 塔唔池化;`share_life` 係逐幀活體掃描 |

**#2–#7 六個全部修咗。** 用戶懷疑名單入面嘅「magnet 推撞對」同「black hole
困住名單」查實冇呢兩樣嘢 —— magnet 係同 frame 嘅 `caught` 陣列,而呢個 build
根本冇黑洞塔。

### 統一修法:generation counter

`Monster.serial` **本身已經存在**(第 14 輪為 `Projectile` 加嘅),`setup()`
每次 +1。本輪做嘅係:

1. `Soldier` 補返一個一模一樣嘅 `serial`(佢之前冇)。
2. `Pool.live(node, serial)` —— 一個 static helper,一條規則一個實現:
   `null / 唔 valid / serial 對唔上 / 唔 alive` 一律返 `null`。
3. 六個現場全部改成儲 `(node, serial)` 對,用嗰陣經 `Pool.live()`。
   `Tower.soldiers` 由「節點陣列」變成「`[節點, serial]` 對陣列」,加一個
   `live_soldiers()` 順手剷走過期名額。
4. `Battle.skeleton_lord()` getter —— 外面(`Monster._die`)唔再直接掂個欄位。

### `PooledRefTest`(新,77 條斷言)

三組:

* **A 機制**(10 條):`Pool.live()` 嘅契約。入面有兩條係專登驗**個 bug 嘅前提**
  仲成立:回收咗嘅節點 `is_instance_valid()` **仍然係 true**、`alive` **仍然係
  true** —— 即係話舊嗰個檢查喺呢度真係會中招。另外有一個 case 專門驗
  `Pool` 係 LIFO:如果將來改成 FIFO,呢批 test 會全部靜靜咁變成「乜都冇驗過」
  而仍然係綠色,嗰個係一個假嘅安全感。
* **B 逐個現場**(6 個 case):砌返「參照已經轉世」嗰個狀態,斷言唔會認錯人。
* **C 靜態掃描**:六個已知欄位喺 code 入面每一次被**讀取**都一定要見到
  `Pool.live(`。加多一條行為斷言釘住 `Pool.live` 呢個名 —— 佢一改名,成個
  白名單會靜靜咁全部通過。

**反向驗證做咗**:將 `Pool.live()` 嘅 serial 檢查閹咗(= 修之前嘅行為)再跑,
**啱啱好 8 條跪,一個現場一條**,而且讀數睇得出病徵(層數變 3 而唔係 1、
光束蓄能停喺 3.00 而唔係 0)。

### 過程中撞返出嚟嘅一個設計缺陷:「兩個欄位要一齊寫」本身就係個陷阱

改完之後 `BossHealTest` **跪咗兩條**:「光環下小兵最多復活 2 次(實際 1)」同
「boss 血條有綠色回復段(寬 0.0px)」—— 兩件表面上完全無關嘅事。

根因係同一件:嗰個 harness 自己砌狀態嗰陣寫 `b.boss_ref = m` /
`b.skeleton_boss_alive = m`,但**冇寫 serial**。於是 `Pool.live()` 由第一刻起
就當個參照已經死咗。呢個失敗係**完全靜音**嘅 —— 冇 error、冇 warning,
淨係兩個機制靜靜咁唔生效。

即係話「node + serial 一對」呢個設計,如果要求呼叫者記得寫兩句,佢本身就係
一個新嘅陷阱 —— 同原本嗰個 bug 同一個家族。所以加咗
`Battle.set_boss_ref()` / `set_skeleton_lord()` 兩個 setter,**全 project
(連 harness)所有寫入都經佢哋**,而 `PooledRefTest` 嘅靜態掃描多咗一組:
四個檔入面除咗 setter 自己,唔准再有 `boss_ref = ` / `skeleton_boss_alive = `。
呢組掃描亦都反向驗過(把一句改返直接寫,即刻捉到)。

`Tower` 嗰三個欄位唔使 setter:佢哋淨係喺同一個檔案入面寫,而且成對嘅兩句
永遠貼住,由 `_same_target()` 一條路讀 —— 但同一個道理,將來搬出去就要跟住加。

### 對平衡嘅影響:量咗,冇動

呢六個修正**方向上係 nerf**(塔唔再攞到過繼落嚟嘅加成),所以要量清楚:

| 量度 | 修之前(serial 唔驗) | 修之後 | 差 |
|---|---|---|---|
| 塔 bench(`BalanceSim --towers`,20 座) | — | — | **逐行 byte-identical** |
| A1 1–40 逐關勝負(8 seed × 40 關) | — | — | **逐關完全一樣** |
| Gate 6a A3 第 100 關(n=20) | 100%,平均 170.7 秒 | 100%,平均 170.7 秒 | 0 |
| Gate 6b A4 第 100 關(n=20) | 100%,平均 166.3 秒 | 100%,平均 166.5 秒 | +0.1% |

逐個 seed 睇係有**細微**差異(即係嗰條 code path 真係有行到),但加總落去
全部喺雜訊之內。**A1 1–40 嗰組要打個折扣**:A1 永遠唔進化,而 #2/#3/#4 三個
機制全部係 T2/T3 —— 所以嗰組「完全一樣」其實只證明咗「冇整爛低階」,證明唔到
高階冇變。真正對得上嘅係第 100 關嗰兩行(A3/A4 都係 tier-3,三個機制全部
live),而嗰兩行嘅差係 0 同 +0.1%。

**一個平衡數字都冇動。**

---

## 6. Gate 6a / 6b 重跑讀數 vs 定版

把尺:`--mode=final`(第 21 輪已經釘咗呢個係 Gate 6 嘅正確量法 ——
`--mode=sweep --from=91` 打到第 100 關嗰陣 RNG 狀態完全唔同)。

| Gate | 目標 | 定版(第 21 輪) | **本輪修完** | 判定 |
|---|---|---|---|---|
| 6a | A3 第 100 關 ≤5% | 0.0%(n=20,sweep) | **100%**(n=20,0 掛死) | **FAIL(太易)** |
| 6b | A4 第 100 關 10–30% | 16.7%(n=48,final) | **100%**(n=48,0 掛死) | **FAIL(太易)** |

同一把尺嘅未修 / 已修 A/B:

| 原型 | 未修(final mode) | 已修(final mode) |
|---|---|---|
| A3 | 0%,**掛死 20/20** | **100%**,掛死 0 |
| A4 | 15%(3/20),**掛死 17/20** | **100%**,掛死 0 |

**每一場已修嘅勝仗都殺齊十隻 boss**(`bosses_killed = 10`,A3 20/20、
A4 48/48),平均用時 A3 170.7 秒 / A4 166.4 秒 —— 第三潮 160 秒出場,即係
最後一潮出嚟之後大約十秒收工。冇一場係提早結算。

修完之後第 100 關嘅完整原型曲線(`--mode=final`,20 seed,0 掛死):

| A0 | A1 | A2 | A3 | A4 |
|---|---|---|---|---|
| 0% | 0% | 0% | **100%** | **100%** |

A0/A1/A2 三個原型係**真.敗仗**(`frac = 1.0`,50–80 秒就俾人衝到基地),
唔係掛死。即係第 100 關而家係一道「**冇雙 tier-3 就一定唔過,有咗就一定過**」
嘅硬門檻。

### 呢個位置我冇自行調平衡

按指示:**報數,唔調。** 但要講清楚件事嘅意思 ——

`FINAL_SCALE = 0.052` 呢個數,係第十八輪用「A4 實測 0/16」定出嚟嘅,而嗰個
`0/16` 而家知道係掛死唔係敗仗。同樣道理,第 21 輪嗰個 `16.7%` 亦都唔係難度,
係競態中獎率。**即係 Gate 6 由第十七輪起嘅每一個讀數都唔可以再引用**,
`FINAL_SCALE` 現時嘅值等於冇校準過。已經寫入 `BALANCE_CHANGELOG.md`。

要唔要重釘第 100 關(要唔要保住「多試幾場先過到」嘅手感、要唔要 A3/A4 之間
有距離)係一個設計決定,要 Jack 拍板。而家終於有一把量到嘢嘅尺。

**呢個唔阻住出貨**:1.0.0 出街嗰版係「打唔完」,1.0.1 係「打得完但收官戰偏易」。
後者係一個平衡議題,前者係一個 launch blocker。

---

## 7. 全套 regression

見第 9 節。

---

## 8. Jack 要驗乜

### 真機(APK)

1. 裝 `dist\Towerbound-1.0.1.apk`(1.0.0 要先移除 —— 同一條 key 簽,理論上
   蓋得過,但 versionCode 2 > 1 所以直接升級都得)。
2. **打到第 100 關**(或者用現有存檔直入)。三潮 boss 喺 30 / 92 / 160 秒出。
3. 用**四種殺法**各打一次,每次都要見到「十隻死晒 → 小怪即刻停 → 結算畫面」:
   - **順序**:見到邊隻就打邊隻。
   - **亂序**:專登跳住殺,最後先返轉頭清第一潮剩低嗰隻。
   - **極速**:囤晒魔法,第三潮一出就一次過清光。
   - **拖長**:第一潮清晒之後唔好急,等足第二潮、第三潮出齊先慢慢清。
4. 每次都要留意:**最後一隻 boss 死嗰一刻,小怪應該即刻唔再出**,而唔係
   「打完 boss 之後仲有一大堆怪要清」。
5. 順手睇下 boss 血條:應該永遠指住一隻**真 boss**,唔會跳去跟一隻普通小怪。

### 瀏覽器(GitHub Pages)

同上第 2–5 點,喺 <https://jackncw.github.io/game-towerdefence/>(push 之後
Pages 會自動更新)。
用 web 版可以直接用開發者存檔跳關,快好多。

### 一個「壞咗會點」嘅參照

未修嗰版嘅病徵係:十隻 boss 死晒之後,**小怪繼續一波一波咁出,結算畫面永遠
唔嚟**,而且場面會越積越多(實測 75 隻仲喺度加)。見到呢個就係 regression。

---

## 9. 檔案改動

| 檔 | 改動 |
|---|---|
| `scripts/battle/Battle.gd` | 第 100 關完成鏈六項(見第 4 節)+ `boss_ref` / `skeleton_boss_alive` 加 serial + `skeleton_lord()` getter |
| `scripts/battle/Pool.gd` | **新** `Pool.live(node, serial)` —— 跨幀池化參照嘅唯一檢查 |
| `scripts/battle/Tower.gd` | `_streak_target` / `_conductor` / `last_target` 加 serial;`soldiers` 改 `[節點, serial]` 對 + `live_soldiers()` |
| `scripts/battle/Soldier.gd` | 加 `serial`;`_formation_allies()` 經 `live_soldiers()` |
| `scripts/battle/Monster.gd` | 復活光環經 `battle.skeleton_lord()` |
| `scripts/ui/BattleHUD.gd` | boss 血條經 `Pool.live()` |
| `test/Level100CompletionTest.gd` / `.tscn` | **新** —— 7 個 case、46 條斷言 |
| `test/PooledRefTest.gd` / `.tscn` | **新** —— 77 條斷言,守住「跨幀池化參照一定要驗 serial」呢條規則 |
| `test/BossHealTest.gd` / `BalanceSim.gd` / `Autopilot.gd` | 改用 `set_boss_ref()` / `set_skeleton_lord()` setter |
| `tools/apply_head_include.py` | stdout 強制 utf-8 —— Windows cp950 console 令佢**做完嘢先死喺最後一句 print**,於是 `--check` 明明係「最新」都 exit 1 |
| `test/GateSim.gd` | `_play()` 加 `hang` / `fbd`;final + sweep 嘅 ROW 加欄;`GATE HANG` 行 |
| `tools/gate_report.py` | 讀 sweep ROW 第 18 欄;掛死喺評 gate 之前報 |
| `tools/gate20.ps1` | Gate 6b 收新 ROW + 掛死即 FAIL |
| `tools/android_build.ps1` | 版本號由 `export_presets.cfg` 讀;開工前驗 `export_path` 同版本號對得上 |
| `export_presets.cfg` | `version/code` 1→2、`version/name` 1.0.0→1.0.1、**`export_path` 一齊改**(Android + AndroidAPK 兩個 preset) |
| `docs/design/BALANCE_CHANGELOG.md` | 第 23 輪條目:零平衡改動,但 Gate 6 歷史讀數作廢 |
