# Round 9 設計 — 音效補完 / 難度牆 / 一手勢起塔

三個互不依賴嘅部分,分三個 commit。共用一次驗收(全套測試 + art_export + push)。

---

## Part 1 — 音效系統補完

### 現況

`tools/gen_audio.py` 有 11 個音(4 UI + 6 塔攻擊 archetype + 1 BGM),`scripts/autoload/Audio.gd`
用名稱前綴決定 bus(`ui_` → UI,`bgm_` → BGM,其餘 → SFX),有 pool / dedup / pitch spread。
接駁點得 6 處:Battle 開場 BGM、Tower 攻擊、抽屜開關、UI 按鈕、UI 錯誤。

呢部分**唔改架構**,只係按同一套 primitives 補音 + 補接駁點。

### 新增音效清單(53 個,總數 64)

| 組 | 數 | 名 | 備註 |
|---|---|---|---|
| 怪物死亡 | 10 | `sfx_die_{fam}` × goblin/wolf/skeleton/golem/ghost/bat/treant/beetle/cultist/slime | 按族性格:骷髏散骨(乾木 rattle)、史萊姆黏爆(低通 splat + 尾巴)、石魔碎裂(碎石 noise burst)、幽靈消散(反向 swell,無 attack)、樹妖折斷、甲蟲脆殼、信徒吟唱斷掉、哥布林尖叫、狼嗥、蝠吱 |
| 受擊 | 3 | `sfx_hit_soft` / `sfx_hit_hard` / `sfx_hit_magic` | Monster 按 armor / mres 揀;pitch 隨機 ±6% |
| 魔法 | 15 | `sfx_spell_{mech}` × meteor / stormbolt / freezenova / miasma / summon / midas / timewarp / warcry / barrier / tornado / quake / firewall / smite / emp / blackhole | 大魔法(meteor / blackhole / freezenova / quake)0.5–0.8s,有下沉低頻份量;細魔法 <0.25s |
| 塔補完 | 8 | `sfx_atk_poison` / `_boomerang` / `_thorn` / `_magnet` / `_teleport`、`sfx_tower_barracks` / `sfx_aura_curse` / `sfx_field_slow` | 前五個由「借 archetype 改 pitch」升做專屬;後三個係兵營/詛咒/緩速力場 —— 之前因為冇離散攻擊而無聲 |
| 系統 | 15 | `sfx_gold_pop` / `sfx_gold_bank` / `sfx_crystal_gain` / `sfx_upgrade` / `sfx_unlock` / `sfx_boss_warning` / `sfx_base_danger` / `jingle_win` / `jingle_lose` / `jingle_first_clear` / `sfx_teleport_hit` / `sfx_knockback` / `sfx_summon_circle` / `sfx_place_tower` / `sfx_sell_tower` | 金幣 = 金屬短亮(~0.08s),魔晶 = 玻璃長尾(~0.35s + shimmer),呼應雙貨幣視覺區分 |
| BGM | 2 | `bgm_menu` / `bgm_boss` | menu:大調、90bpm、閒適;boss:132bpm A小調,同 `bgm_battle` 同 BPM 同 key |

`LOUDNESS` 表補齊:死亡聲同受擊聲坐低(0.075–0.09,5x 之下每秒幾十次),jingle 同警號坐高
(0.16–0.18),BGM 維持 0.085。

### battle → boss BGM 無縫過渡

`Audio.gd` 加一個 `BGM_META` 表(每首:bpm / beats-per-bar / bars)同 `queue_bgm(name)`:

- `queue_bgm` 唔即刻切,只係記低 `_bgm_pending`
- `_process` 讀 `_bgm.get_playback_position()`,計出小節長度 `60/bpm * beats`
  (132bpm × 4 拍 = 1.818s),等播放位置跨過下一條小節線先至 `play_bgm(pending)`
- 兩首同 BPM 同 key,新曲由自己 bar 0 入,聽落係同一首歌換段而唔係換歌

觸發點:`Battle._spawn_boss()` 叫 `Audio.queue_bgm("bgm_boss")`。最壞情況延遲 1.82 秒。
`Battle._win/_lose` 停 BGM 播 jingle;`MainMenu._ready` 播 `bgm_menu`。

### 接駁點

| 事件 | 位置 |
|---|---|
| 怪物死亡 | `Battle.on_monster_killed` → `sfx_die_{fam}` |
| 怪物受擊 | `Monster.take_damage` → `sfx_hit_*`(dedup 60ms 已經頂住 5x) |
| 魔法施放 | `Spells.cast` 開頭統一派,按 mech 查表 |
| 起塔 / 賣塔 | `Battle.place_tower` / `sell_tower` |
| 金幣 / 魔晶 | `Battle.add_gold`(dedup 令佢變成節奏而唔係雜音)/ `Meta.add_crystals` |
| 升級 / 解鎖 | `Meta.buy_tower_upgrade` / `buy_spell_upgrade` / `unlock_tower` / `unlock_spell` |
| boss 出場 | `Battle._spawn_boss` → `sfx_boss_warning` + `queue_bgm` |
| 基地危險 | `Battle.on_reach_base`,`base_shield` 跌穿 30% 時派一次 |
| 勝 / 敗 / 首通 | `Battle._win` / `_lose`,首通再疊 `jingle_first_clear` |
| 傳送 / 擊退 / 召喚 | `Battle.on_projectile_hit`(teleport / knock)、`spawn_soldier` |

塔嗰邊:`TOWER_SOUND` 表更新 —— poison / boomerang / thorn / magnet / teleport 指去自己嘅新
檔案而唔再係 pitch-shifted 借用;barracks / curse / slowfield 加入表中,由各自嘅事件
(出兵 / 光環刷新 / 力場脈衝)派聲,唔係逐幀。

### 技術自查

- `python tools/gen_audio.py --verify` 出表:每個音嘅時長 / peak / RMS / 有冇 clipping
  (|x| ≥ 0.999 嘅取樣數)/ loop 接口首尾差值
- `test/AudioTest.gd` 擴充:每個 `SOUNDS` 名都要有實檔、bus 對、`TOWER_SOUND` /
  死亡表 / 魔法表入面每個引用嘅名都存在(防止改名之後靜音)

---

## Part 2 — 難度牆

### 背景

上輪獎勵曲線改咗之後,模擬 20 關零卡關,「輸 → 升級 → 過到」循環冇機會觸發。

### 位置

第 **7 / 13 / 18** 關,之後**週期 20** 重複:27 / 33 / 38、47 / 53 / 58…
間距 6-5-9 固定循環。判定:`(n - 7) % 20 ∈ {0, 6, 11}`。

### 三幅牆嘅成份 —— 全部係機制,唔郁 `wave_scale`

`level_config(n)` 嘅家族輪換由 `base_i = (n-1) % 10` 決定,所以三關嘅 boss 已經係定咗嘅,
牆嘅成份要同 boss 夾:

| 關 | boss(已定) | 牆改乜 | 考乜 |
|---|---|---|---|
| 7 | 遠古樹妖 `root_heal`,ambient 有 `minion_regen` | spawn pool 加 `bat`(飛行)+ `cultist`(群療光環) | **對空 + 治療壓力**。開局四座塔(箭/加農/冰霜/兵營)入面兵營攔唔到飛行,冰霜對空有效但傷害唔夠;信徒光環令零碎傷害補返晒 |
| 13 | 骷髏君主 `revive_aura` | 加 `slime`(分裂);`spawn_interval_min` 0.45 → 0.30 | **AoE**。「分裂 × 復活」令屍體數量翻倍,單體塔追唔切 |
| 18 | 甲蟲皇 `reflect` | 加 `ghost`(魔抗 25)。該關本身已有 beetle(硬殼)+ golem(甲 12) | **傷害類型**。護甲同魔抗同場出現,單一傷害類型過唔到 |

### 實作 —— 100% 喺 GameData.gd

```gdscript
var WALLS := {
    7:  {"add_fams": ["bat", "cultist"],  "hint": "WALL_HINT_7"},
    13: {"add_fams": ["slime"], "spawn_min": 0.30, "hint": "WALL_HINT_13"},
    18: {"add_fams": ["ghost"], "hint": "WALL_HINT_18"},
}

func wall_def(n: int) -> Dictionary   # 處理週期 20,冇牆返 {}
func is_wall(n: int) -> bool
func wall_hint_key(n: int) -> String
```

`level_config()` 喺最後 merge `wall_def(n)`:`add_fams` append 落 `families`,
`spawn_min` 覆寫 `spawn_interval_min`。

**Battle.gd 零改動** —— 佢照讀 `cfg.families` / `cfg.spawn_interval_min`。

### 驗收模擬

`BalanceSim.gd` 加 `--walls` mode:

- 每關(1..20)跑 **12 個 seed**,每個 seed 最多 3 次嘗試,嘗試之間行返
  現有嘅 `_spend_crystals()`(即係真嘅「輸 → 買升級 → 再試」)
- 出表:每關 `首次通過率` / `≤3 次通過率` / `平均嘗試次數`
- 門檻:
  - 牆關 首次通過率 **≤30%**(即失敗率 ≥70%)
  - 牆關 ≤3 次通過率 **≥90%**
  - 非牆關 首次通過率 **≥85%**

**已知風險**:12 seed × 20 關 × 最多 3 次 ≈ 500 場,比現有 playthrough 慢約 10 倍。
先計時;如果單次跑 >15 分鐘就降到 8 seed,並喺報告寫明實際用咗幾多 seed。

### 玩家溝通

- **選關畫面**(`LevelSelect.gd`):`is_wall(n)` 嘅卡加骷髏 icon + 紅框 + 「危險」字樣
- **失敗畫面**(`Fail.gd`):牆關輸咗,喺現有 `FAIL_MSG_*` 之下多加一行剋制方向:
  - L7 `WALL_HINT_7` — 「呢關嘅怪會互相治療」
  - L13 `WALL_HINT_13` — 「怪多過你嘅子彈」
  - L18 `WALL_HINT_18` — 「護甲同魔抗各佔一半」
  一句就夠,唔講具體塔名或魔法名

i18n:三個 hint key + `LEVELSEL_DANGER` 落 `i18n/game.csv`(繁中 + English),
之後跑 `tools/subset_font.py` 補字型 subset。

`BALANCE_CHANGELOG.md` 續寫呢一輪。

---

## Part 3 — 一手勢起塔

### 問題

抽屜設計令起塔 = 開抽屜 + 拖放,兩個動作。

### 新底欄佈局(1080×1920,已實測有位)

```
1470‥1580   塔資訊 / 賣塔面板          (不變)
1584        抽屜停喺呢度                (不變,DRAWER_BOTTOM)
1586‥1688   ★ 常駐快捷列 — 7 格         (取代舊嘅「建造」把手)
1690‥1912   魔法 grid(15 個 = 8+7)     (不變)
```

快捷列:7 格 = 6 個塔槽 + 「更多」。左右邊距 20,格間距 8
→ 格闊 `(1080 - 40 - 6×8) / 7 = 141`,格高 `102`。

- 觸控目標最短邊 **102px ≥ 88** ✓
- 格內:塔 icon 60×60 置頂置中 + 金幣 22 × 價錢 24 喺下 = 94 ≤ 102,合身,**唔使收埋價錢**
- 空槽 = 暗色「+」,撳即開抽屜
- 抽屜依然由「更多」開,做全塔倉庫,入面照樣一手勢拖放

### 一手勢

快捷槽 Button 嘅 `gui_input` 直接接返現有嘅
`_card_gui → Battle.card_press / card_drag / card_release` 鏈。

因為快捷列**唔係**抽屜,所以冇 `_over_drawer` 否決、冇 `_set_drawer(false)`:
**按住 → 拖出地圖 → 放手 = 一個手勢完成**。Tap 一下照樣 arm 兩段式模式。

抽屜嗰邊嘅行為完全不變(包括「拖返落面板 = 取消」)。

### 釘選 —— 喺主選單,唔喺戰鬥

新畫面 `Flow.QUICKBAR`(`scenes/QuickBar.tscn` + `scripts/ui/QuickBar.gd`),
主選單加一個「快捷列」掣(擺喺「升級」同「圖鑑」之間)。

畫面結構:

```
快捷列設定
─────────────────────────────────────
 戰鬥底欄實際樣：          ← 1:1 畫出真嘅 141×102 格
 ┌───┬───┬───┬───┬───┬───┬────┐
 │🏹 │💣 │❄️ │⚔️ │ + │ + │更多│   ← 撳槽 = 選中(高亮)
 └───┴───┴───┴───┴───┴───┴────┘
─────────────────────────────────────
 已解鎖嘅塔：
 ┌─────┬─────┬─────┬─────┐
 │🏹★  │💣★  │⚡   │🔥   │   ★ = 已喺快捷列
 ├─────┼─────┼─────┼─────┤
 │❄️★  │☠️   │🎯   │⚔️★  │
 └─────┴─────┴─────┴─────┘
```

操作:
- **撳槽 → 撳塔** = 指派(塔本來喺第 N 槽嘅話,兩槽對調而唔係出現兩次)
- **撳已選中嘅槽再撳同一座塔** = 清空該槽
- **拖槽** = 重排
- 「更多」格喺呢度只係示意,唔可以指派

持久化:`save.json` 頂層 `quick_slots: [6 ints]`(0 = 空)。
預設 `[1, 2, 5, 13, 0, 0]`;解鎖新塔時自動填第一個空槽(即「最新解鎖 2 座」),
六格滿咗之後唔再自動取代 —— 之後全部由玩家喺呢個畫面決定。

`Meta.gd` 加:`quick_slots` 變數、`to_dict` / `load_game` 讀寫 + 缺省填充、
`set_quick_slot(i, id)` / `swap_quick_slots(a, b)`、`unlock_tower()` 入面嘅自動填充。
載入時要過濾未解鎖 / 唔存在嘅 id(舊存檔 + 手改存檔)。

### 測試

`test/BottomBarTest.gd` 加 `Q` 組:

- `Q 快捷列佈局` — 7 格全部 ≥88px、唔重疊、唔出界、唔同魔法 grid 相交
- `Q 一手勢起塔` — 由快捷槽 press → 拖去合法空地 → release,`towers.size()` +1 且扣金,
  **全程冇開過抽屜**(`hud._drawer_open` 一路 false)
- `Q 空槽開抽屜` — 撳「+」槽 → `_drawer_open` 變 true
- `Q 更多掣` — 撳「更多」→ 抽屜開;再撳 → 收
- `Q 抽屜照舊` — 現有 `P` 組(拖出去起塔 / 拖返落面板取消 / 兩段式)全部照樣 pass

現有 `O` 組要改:佢而家撳 `HANDLE_RECT` 中心開抽屜,而把手已經冇咗 ——
改為撳「更多」格。`HANDLE_RECT` 常數由 `MORE_RECT` 取代。
- `Q 釘選 round-trip` — `Meta.set_quick_slot()` → `save_game()` → `load_game()` 之後保留;
  未解鎖 id 會被濾走

最迫佈局(15 魔法 + 6 塔槽 + 更多)行 `tools/art_export.gd` 影圖自查。

---

## 驗收清單

- [ ] 音效總數 64(首批 11 + 新批 53),`gen_audio.py --verify` 全綠(無 clipping、
      loop 接口差值 < 0.01)
- [ ] 遊戲由主選單到 boss 戰全程有聲;5x 之下 dedup + pool 頂得住(AudioTest 壓力 case)
- [ ] battle → boss BGM 喺小節線上切換、無縫
- [ ] `--walls` 表:三幅牆首次通過率 ≤30%、≤3 次 ≥90%;非牆關首次 ≥85%(附每關表)
- [ ] 選關危險標記 + 失敗剋制提示,繁中 / English 都有
- [ ] `Q` 組測試全 pass;一手勢起塔全程冇開抽屜
- [ ] 最迫佈局截圖自查完成
- [ ] 釘選重開遊戲保留
- [ ] 全套測試 pass,push GitHub,commit hash 落報告
