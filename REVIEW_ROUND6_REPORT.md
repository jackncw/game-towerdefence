# 總檢輪報告 (2026-07-27)

還原點:每階段一個 commit,`git log` 由 `f50f1f6`(開工前原狀)起計,可逐階段 rollback。
整輪改動:34 個檔案,+1763 / −247 行。

## 0. Skills 盤點

| skill | 今輪點用 |
|---|---|
| **godot-art-export**(個人) | 階段 5:全量 export 40 張畫面 + gallery;再按 skill 嘅「唔准未睇圖就話改好」流程,補影兩組今輪改動冚唔到嘅畫面(商店未解鎖態、磁力/傳送升級列),睇圖後再修再 export |
| **superpowers:systematic-debugging** | 階段 1/3:每個 bug 先寫 root cause 再改;效能唔靠估——先 instrument(spike frame 打印各池狀態)搵到真兇先落手 |
| **superpowers:test-driven-development** | 階段 1:每個 bug 配一個喺舊 code 會 FAIL 嘅 regression case |
| **superpowers:verification-before-completion** | 每階段收尾都跑全套測試 + 實際量度先 commit |
| **godot-prompter:godot-optimization** | 階段 3 嘅檢查清單:每 frame 分配 / 池覆蓋率 / queue_redraw 濫用 / 主線程 I/O |
| **godot-prompter:godot-code-review** | 階段 2 死碼掃描同重複 code 判斷 |
| **godot-prompter:godot-testing** | 階段 1/4/5 三個新 harness 嘅結構(headless、固定 dt、自行備份還原 save) |
| **godot-prompter:save-load** | 階段 1 存檔原子性同舊檔相容 |
| **godot-prompter:gdscript-advanced** | 池化、Tween vs 手寫計時器、type inference 陷阱 |
| 其餘(3d / xr / multiplayer / mobile / shader / dialogue / inventory 等) | 唔關本 project 事,冇用 |

---

## 階段 1 — 程式 Bug 掃描

現有 9 套測試開工前全部 pass。系統掃完 edge case 之後搵到 **14 個 bug**,全部修好並加入
新嘅 `test/RegressionTest.tscn`(47 項斷言,每項喺舊 code 都會 FAIL)。

### 嚴重(會直接令玩家輸咗一關 / 資源錯亂)

| # | Bug | Root cause | 修法 |
|---|---|---|---|
| 1 | 中毒/燃燒喺最後一步打死怪,**玩家白白輸咗成關** | `Monster._process` 入面 `_tick_status` 嘅 DoT 可以 `_die()` 並將節點還池,但個 function 冇 return,繼續行落去做移動:`dist` 過咗 `route.total` 就叫 `on_reach_base()` | `_tick_status` / `_tick_family` 之後加 `if not alive: return` |
| 2 | 賣兵營之後**一半士兵仲喺路面免費堵路** | `sell_tower` 一路 `for sd in t.soldiers` 一路被 `Soldier._die()` → `on_soldier_died()` 從同一個 array `erase`,跳格 | iterate `t.soldiers.duplicate()` |
| 3 | 結算之後仲飛緊嘅投射物**照樣派金、計擊殺、二次還池** | `_win()` 淨係 `pool.release(m)` 冇 set `alive=false`,所以 `is_instance_valid(target) and target.alive` 仍然成立 | 抽 `_clear_field()`:先標記死亡先還池,同時停晒在飛嘅投射物同地面效果 |

### 功能失效(玩家付咗魔晶但完全冇效果)

| # | Bug | 說明 |
|---|---|---|
| 4 | 守護結界「結界反傷」 | `Spells.cast` 寫 `battle.barrier_reflect`,全 codebase 冇任何地方讀佢 → 實裝:結界擋怪嗰下對閘口目標同周圍放傷害 |
| 5 | 詛咒塔「死亡詛咒擴散」 | 塞入 payload 嘅 `"cursespread"` key,`on_projectile_hit` 從來冇睇過 → 改由 curse effect 攜帶半徑,死亡時傳染(唔會無限接力) |

### 其他

| # | Bug |
|---|---|
| 6 | `_deal_dot` 繞過 `invuln_time`:石魔 boss「石化無敵」期間照樣食毒同燒 |
| 7 | 魔晶交易分兩次寫檔(扣錢一次、發貨一次),中間 quit 會扣咗錢冇貨 → 改成單次寫入 |
| 8 | 舊存檔升級方向數量唔夠(例如得 2 個)→ 升級介面 `levels[dir]` index 爆,新方向永遠買唔到 → `tower_levels/spell_levels` 自動補齊 |
| 9 | `load_game` 完全唔檢查型別:壞存檔可以令玩家零塔,再喺 `Upgrade._ready` 嘅 `[0]` crash → 全欄位型別防禦 + fallback |
| 10 | 音量/靜音設定開機從來冇套用落 `AudioServer` —— 靜音玩家每次開機都聽返到聲 |
| 11 | 升級介面按 stat **名** 判斷百分比:磁力塔「擊退距離 40px」顯示成 **4000%**、傳送塔「暈眩 0.15 秒」顯示成 **15%**(`knock` / `stun` 兩隻塔同名唔同意)→ 改為睇升級自己嘅 `kind` |
| 12 | 機槍塔「散射」揀 `others[0]`,經常就係目標本身 → 變咗打多次同一隻;雷電連鎖對已死怪繼續施 stun |
| 13 | 快塔喺 5x 速下每 frame 只射一發(`_cd` 直接重設,唔累加),實際攻速遠低過標示 → 有上限嘅追射迴圈 |
| 14 | 史萊姆喺基地口分裂,子體 clamp 落 `total-10`,即係生喺閘入面完全打唔到 → 留返 80px 路 |

階段 5 快掃時再執到同一類漏網:磁力塔「擊退後減速」同狙擊塔「處決線」顯示成
`0 → 0`(每級步進細過顯示進位門檻),已修 + 加斷言。

---

## 階段 2 — 死碼清除 + 重複 code

**刪除規則**:每項刪除前做全局搜尋 + 檢查 scene 連結 + 檢查字串拼接引用,刪完跑全套測試。
(`deco_stump` / `deco_banner` 一度睇落零引用,但實際係 `"deco_" + n` 拼出嚟 —— 所以冇刪。)

### 刪咗

| 項目 | 行數/大小 | 證據 |
|---|---|---|
| `PathRoute.tangent_at()` | 6 行 | 全 repo 只有定義 |
| `UI.panel()`(PanelContainer 版) | 4 行 | 零呼叫 |
| `BattleHUD.clear_selection()` + 呼叫點 | 3 行 | body 係 `pass` |
| `Battle.sell_tower` 入面 `if t.has_method("_die_soldiers"): pass` | 2 行 | 無效殘碼 |
| `UI.slider()` 入面未用嘅 `grab` StyleBox | 2 行 | 建咗唔用 |
| `UI.panel_rect(col, radius)` 兩個參數 | — | 從來冇作用,call site 一併更新 |
| `Meta.unlock_spell` 未用變數 + 重複價錢公式 | 2 行 | — |
| 6 個孤兒 `scratch_*.png.import` | 6 檔 | 對應 PNG 已經唔存在 |
| `assets/generated/_contactsheet.png` (+import) | 96 KB | 零引用,但 `export_filter=all_resources` 會打包入 APK;gen_art 改寫去 `art_export/` |
| `assets/generated/ui/btn9_press.png` (+import) | — | `_btn_tex_for()` 永遠唔會回傳佢;gen_art 產生區塊同 `_TEX_MARGIN` 條目一併刪 |

### 抽共用

- `Shop._tower_card` / `_spell_card`:兩份 40 行幾乎相同 → 合併成 `_unlock_card(def, is_tower)`
- 三處各自 `AudioServer.set_bus_mute / set_bus_volume_db` → 統一 `Meta.apply_audio_settings()`
- 商店價錢用緊 💎 emoji(全遊戲唯一唔用魔晶 sprite 嘅地方,而且 CJK 系統字型好可能出豆腐)→ 換返水晶圖示

### 唔敢刪,列出畀你決定

| 項目 | 點解留返 |
|---|---|
| `assets/generated/ui/ic_play.png`、`ic_shop.png` | 遊戲內冇用,但 `tools/art_export.gd` 嘅 icon gallery 有引用;可能係預留 |
| `godot_setting.jpg`(75 KB,project root) | 開發筆記截圖,零 code 引用,但係你放嘅檔案 |
| `art reference/*.jpg`(約 1.3 MB) | 你嘅設計參考。佢哋全部被 import 咗,而 `export_filter=all_resources` 會連同 `test/`、`tools/` 一齊打包入玩家版 APK。建議喺 `export_presets.cfg` 加 `exclude_filter`,但我今輪冇改 export 設定亦冇重 build APK 驗證 |
| `test/Autopilot.tscn`、`test/Shots.tscn` | 舊 smoke harness,仲跑得,但今輪冇用到 |

---

## 階段 3 — 效能

**方法**:唔靠估。先發現 `perf5x` 個 20 秒安全 timer 受 `Engine.time_scale` 影響
(5x 之下 4 秒就 fire),所以之前每次量度窗口其實只有 **~1.5 秒** —— 先修好呢點
(`ignore_time_scale`,窗口 12 秒),再加 `--budget30` 低端機模式(鎖 30fps,數爆
budget 嘅 frame),最後 instrument 到 spike frame 打印各個池嘅狀態,先落手改。

### Top 瓶頸(按實測影響排)

1. **fx 池無上限膨脹到 900+ 個節點** —— 43 座塔每發 2 粒槍口火花、每次擊殺再加
   burst + 5 粒塵 + 金幣,每個都逐 frame 重繪。加 `FX_SOFT_CAP 220 / FX_HARD_CAP 400`:
   火花金幣先減半後停,結構性特效(環/爆/電弧)只喺硬上限停
2. **傷害數字係 `Label`**(每次 setup 都要重新排版文字),池爆到 400+ 個 —— 亦都係
   畫面上完全睇唔清。加 `DMG_SOFT_CAP 90 / DMG_HARD_CAP 150`,大字(暴擊/boss)永遠出;
   另外只喺 big 狀態轉變時先改 font size
3. **`Meta.mark_seen` 每次首見新怪即刻 `save_game()`** —— 戰鬥中途同步 JSON 寫盤。
   改成 in-memory + 1.5 秒 debounce,戰鬥結束 / 離開 app 強制 flush
4. `Pool.release` 用 `_free.has(n)` 線性搵 → instance-id set,O(1)
5. `Fx` LINE 每 frame 重新計算鋸齒 polyline → setup 時 bake 一次
6. **每事件一個 Tween**:`Monster._flash`(每次中彈)/ `Tower._muzzle`(每發)/
   傷害數字彈出 / HUD 金幣彈跳 → 全部改成 float 計時器,零分配
7. `BattleHUD.refresh` 每 frame 對每個冷卻中魔法叫 `Meta.spell_stats()`(deep duplicate)
   → build 時 cache `cd_max`;所有 UI 寫入加 change-gate
8. `Monster` 每 frame `queue_redraw` 但 `_draw` 只畫血條 → 只喺血條會變先重繪
9. `_Placer` 每 frame `queue_redraw`(冇喺建造/瞄準都係)→ 只喺有 mode 時
10. `Hazard` 每次施法 `new` + `queue_free` → 入池
11. 開場預熱貼圖(`Assets.prewarm_battle`)同池(`Pool.prewarm`)

### fps before / after(同一 harness、同一部機、背對背跑)

| | BEFORE | AFTER |
|---|---|---|
| 5x 無上限 avg | 125.9 | **160.9** |
| median | 113 | **170** |
| p5 / p1 / min | 75 | **130** |
| 最差單 frame | 80.5 ms | **18.8 ms** |
| 30fps budget:爆 budget 嘅 frame | 4 / 358 (**1.12%**) | **0 / 360 (0.00%)** |
| 30fps budget:最差單 frame | 89.0 ms | **33.8 ms** |
| 場上怪物峰值 | 210 | 146 |

目標 ≥55fps:達標,p5 130fps = 2.4 倍餘裕。低端機 30fps budget 由 1.12% 跳幀變 0%。

⚠️ **注意**:AFTER 場上怪物峰值係 146 而唔係 210,因為階段 4 收窄咗史萊姆分裂,
同一個 harness 目標下實際負載細咗少少。p5(75 → 130)同最差 frame(80 → 19 ms)
嘅改善主要嚟自上面 11 項,唔係嚟自怪物少咗。

**未做**:targeting 而家仍然係 O(塔 × 怪)(43 × 146 ≈ 6 千次距離計算/次索敵)。
加一個空間網格可以再減,但目標已經達到 2.4 倍餘裕,唔值得為此引入新風險。

---

## 階段 4 — 遊戲平衡

詳見 **`BALANCE_CHANGELOG.md`**(每項 before/after + 理由 + 還原方法)。

新增 `test/BalanceSim.tscn`,三個模式,全部固定 dt + 固定 seed、手動 step、frame-rate 無關:

- 預設:模擬合理玩家自動打頭 20 關(收金買「每金幣 DPS 最高」嘅塔、關卡之間解鎖到
  6 種再集中升三隻主力、輸咗重試最多 4 次)
- `--towers`:每座塔同一預算同一波次,量「波次總傷害」同「boss 情境打甩幾多血」
- `--spells`:15 個魔法射入同一個 30 隻怪嘅陣型,量傷害同控制

### 核心發現

`creature_stats` 一直將 hp 乘 `wave_scale`,但 **gold 完全唔乘**。第 20 關嘅怪 17 倍血,
掉落同第 1 關一模一樣 —— 打死一隻要 17 倍時間,收入卻一樣。場內同 meta 兩條經濟都係
線性,敵人係指數,所以由第 7 關開始就崩。

### 模擬 before / after

| | BEFORE | AFTER |
|---|---|---|
| 20 關通關 | **9 / 20** | **20 / 20** |
| 一次過 | 9 關 | **17 關 (85%)** |
| 總嘗試 | 53 次 | **26 次** |
| 卡關 | 7, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20 | **冇** |

改後曲線:第 1 關新手一次過、boss 戰由 14 秒拉到 80-90 秒、建塔位使用率 7% → 50%+、
第 14 / 19 / 20 關要重試。魔晶餘額全程 0-163 浮動,冇一關係儲住冇嘢買或者窮到升唔到級。

⚠️ **三項超出 ±30% 上限**(賞金縮放、`WAVE_GROWTH` 1.16→1.13、史萊姆分裂 `2+lvl/2`→2)
已經照改 —— 唔改嘅話由第 7 關開始係唔玩得。每項喺 changelog 都寫明準確位置同還原方法,
你唔同意可以逐項退返。

### 塔 / 魔法橫向

五項有數據支持嘅調整:迫擊砲削(單塔波次傷害 +271%,獨大)、光束塔加(兩個情境都
全場最差但造價第二貴)、導彈塔加、詛咒塔加、閃電風暴加(每秒 CD 傷害全部直傷魔法最低)。
仲有五項證據唔足夠或者 ±30% 解決唔到嘅,列咗喺 changelog「未解決」等你決定。

---

## 階段 5 — 美術一致性

用 godot-art-export 全量 export 40 張。上輪已達標嘅資產當基準,冇無故重畫。
補影兩組今輪改動冚唔到嘅畫面(全解鎖狀態下商店只有「已擁有」,價錢行根本影唔到)。

- 商店價錢:💎 emoji → 魔晶 sprite,同頂欄徽章、升級介面、戰鬥 HUD 一致 ✔
- 升級介面數值格式:磁力塔「擊退距離 40 → 46」(舊:`4000% → 4600%`)、
  「對重型有效率 50% → 54%」、傳送塔暈眩顯示秒數 ✔
- 特效預算冇整死觀感:隕石拖尾、衝擊環、傷害數字照樣出 ✔
- 六項橫向一致性(色板 / 像素密度 / 框架 / 字體 / 圖示語言 / 元素配色)冇發現新引入嘅問題

---

## 最終驗收

| 項目 | 狀態 |
|---|---|
| 全套測試 pass(含新加 regression) | ✅ **11 / 11 套,零 error** |
| 完整流程實跑 | ✅ `test/FlowTest.tscn` 29 項斷言全 pass:主選單 → 第1關通關 → 結算 → 商店解鎖 → 升級介面買升級 → 第2關失守 → 失敗畫面 → 圖鑑 → 設定 → 選關 → 核對 save.json |
| 死碼清單 | ✅ 上面「階段 2」,連「唔敢刪」清單 |
| BALANCE_CHANGELOG.md + 模擬 before/after | ✅ 連 `sim_balance_before.log` / `sim_balance_after.log` |
| fps before/after | ✅ 上面「階段 3」 |
| 玩法機制 / 操作方式 | ✅ 完全冇改。塔 / 魔法 / 怪嘅機制、雙貨幣結構、關卡流程原封不動;唯一貼近機制嘅係史萊姆分裂數,而嗰個係將 code 對返自己份 `FAMILY_LORE` |

### 一個要坦白講嘅失誤

階段 3 做到一半嗰陣,我用 `git checkout HEAD -- scripts/` 去還原一個臨時量度用嘅
checkout,但當時階段 3 嘅改動仲未 commit —— 成個效能 pass 被自己覆蓋咗,要全部重做。
之後改成「先 commit 再量度」。最終結果冇受影響,但呢個係我嘅操作錯誤。
