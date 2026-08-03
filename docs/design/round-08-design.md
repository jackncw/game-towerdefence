# 第八輪設計 — 0.5x 速度 / 底欄重造 / 民兵外觀 / 獎勵曲線 / 聲音系統

還原點:tag `pre-round8` @ `bda4d96`。五項各自一個 commit,可獨立 revert。

---

## 1. 0.5x 速度

`Battle.SPEEDS` `[1,3,5]` → `[0.5, 1.0, 3.0, 5.0]`(float),`game_speed: int` → `float`。
掣面 `"x%d"` → `"x0.5" / "x1" / "x3" / "x5"`。每關 `_ready` 照舊重置 `Engine.time_scale = 1.0`,
唔存檔。

### 時間系統
全部經 `Engine.time_scale`,所以 boss 倒數(`battle.elapsed`)、魔法 CD、DoT tick、
Tween、刷怪間隔自動跟。三個唔跟 time_scale 嘅位,逐個確認過:

- `Meta.gd:255` 已經除返 `Engine.time_scale`(真實時間 flush)—— 正確,唔郁。
- `Battle.gd:977` `Time.get_ticks_msec()` —— 雙擊偵測,**應該**用真實時間,唔郁。
- 音效:Godot 4 `AudioStreamPlayer` 唔受 `Engine.time_scale` 影響,所以「唔變調」係
  預設行為。第 5 項寫完實測一次確認,唔靠估。

### 驗證
`test/SpeedScaleTest.tscn`:同一關喺 0.5x / 1x / 5x 各跑到 boss 出場,斷言
`elapsed`、spell CD 剩餘、DoT 總傷害三者喺三個速度下一致(容差內)。

---

## 2. 底欄重造

視窗 1080×1920。底部 y1596–1920 = 324px 可用。現有兩條 `ScrollContainer` 全部拆走。

### 魔法列 — 固定 grid,永遠可見(y1690–1910)
- ≥9 個:兩行 × 8 欄,格 104×104(觸控 ≥88 ✓)
- ≤8 個:單行置中,格 120×120
- 未學嘅唔佔位;CD 扇形遮罩(`_RadialCover`)照舊

### 塔選單 — 抽屜式面板
- 收起:y1596 一個 400×88「🔨 建造 · 💰<金幣>」把手掣,置中
- 撳開:面板由下滑上覆蓋 y900–1920,底色 alpha 0.92,**唔覆蓋魔法列**
  (魔法列 z 序高過面板)
- 面板內 4 欄 × 5 行 grid,20 座塔一頁見晒;每格 = 塔 icon + 名 + 價,錢唔夠 `disabled`
- 拖放:手指離開面板 rect → 面板 `modulate.a` 降到 0.25,ghost 跟手指
  (沿用現有 `card_press` / `card_drag` / `card_release`);放手後面板收埋
- 兩段式 tap 照支援(tap 揀 → 面板收埋 → tap 地圖)
- 撳面板外 / 再撳把手 = 收埋;**唔 pause**(`get_tree().paused` 唔郁)
- 賣塔面板照舊浮喺地圖上,抽屜一開自動收起

### 驗證
`art_export` 影中英兩語 × 魔法 3 / 8 / 15 個 = 6 張,自己 Read 返嚟睇。

---

## 3. 魔法民兵 vs 兵營士兵

`Soldier.gd` 加 `is_magic: bool`;`Spells.gd` summon 路徑傳 `true`,兵營塔傳 `false`。

- 新 sprite `assets/generated/ui/militia.png`(`tools/gen_art.py` 加 `gen_militia()`):
  **浮游披袍**剪影 —— 冇腳、袍腳散開、藍白為主。同兵營嗰個「站定、盔甲、旗幟色」
  嘅方頭方腳剪影,喺實際遊戲尺寸下一眼分到。
- 魔法體效果(全部喺 `Soldier._draw()` / `_process()`,唔加節點):
  半透明 a≈0.82、身上 2–3 點符文微光(正弦脈動)、腳下淡藍魔法陣
- 召喚:魔法陣由 0 放大 + 旋轉 0.4 秒,民兵同時淡入
- 消失前 2 秒:a 以 6Hz 方波閃爍(`life_time < 2.0`)
- `Upgrade.gd` 嘅 summon 示意圖由 `"segment"` 改成新嘅 `"militia"` 畫法,同場上一致
- 圖鑑唔收錄(佢哋唔係敵人)

---

## 4. 獎勵曲線

### 先量度,後定數
`test/BalanceSim.gd` 加 `--curve` 模式:跑 1–20 關,每關開始前記低
**C(N) = 玩家實際投資緊嗰幾條軸(`CORE_DIRS` × `CORE_COUNT` + 待解鎖)嘅下一級價中位數**。
有咗 C(1..20) 先反推公式。

### 目標
| 項 | 目標 |
|---|---|
| 失敗(典型進度 p≈0.6) | 1.0–1.2 × C(N) |
| 通關 | 2.5–3 × C(N) |
| 首通 | 疊加喺通關之上 |
| 下限 | 唔低過舊 ×3 水平 |

C(N) 跟 1.35^lv 幾何式升,而家嘅 `36+8n` / `40+10n` 係線性,追唔到 ——
派彩公式改成幾何式,增長率由量到嘅 C(N) 擬合。`LOSE_REWARD_CAP_FRAC` 由 0.40 重定,
令 p=0.6 落喺 1.0×C。

### 防刷
三條派彩改用 `N = 玩家已解鎖最高關`,唔係「而家打緊嗰關」;
打已通關嘅舊關,實派乘 0.30。返轉頭刷第 1 關無利可圖,卡關嗰關照足額。

### 驗證
- `--curve` 出 1–20 關逐關「輸一場 ≥ 1 級升級?」✓/✗ 表
- `--econ10` 擴到 20 關,出收支表 + 通脹指標(期末餘額 vs 最平未解鎖)
- 兩張表 + 曲線圖續寫入 `BALANCE_CHANGELOG.md`

---

## 5. 聲音系統(由零建立)

### 架構
- `default_bus_layout.tres`:Master → BGM / SFX / UI
- 新 autoload `Audio.gd`:`play(name, bus)`,每 bus 一個 `AudioStreamPlayer` pool(8 個),
  **同名音效 60ms 內去重**(5x 速度下幾十支箭同幀開火唔可以爆音)
- 設定頁:總 / 音樂 / 音效三條 slider,存 `save.json`
  (`volume` / `volume_bgm` / `volume_sfx`);現有靜音掣 = Master mute,兩處狀態同步
- 舊存檔冇新欄位 → fallback 預設,`RegressionTest` 加 case

### 生成
`tools/gen_audio.py`(numpy → wav → `assets/generated_audio/`),一個音效一個函數,
共用 8-bit 積木(方波 / 三角 / 噪音 / ADSR / 琶音 / 滑音)。

| 組 | 數 |
|---|---|
| UI 撳掣 / 開關面板 / 錯誤 | 3 |
| 放塔 / 賣塔 / 升級成功 | 3 |
| 20 種塔攻擊(6 個原型底 × 變奏) | 20 |
| 命中 / 爆炸 / 穿透 | 3 |
| 怪物死亡(按 10 族) | 10 |
| 怪到基地扣血、boss 出場吼叫、boss 回血 | 3 |
| 15 種魔法施放 | 15 |
| 召喚 / 民兵消失 | 2 |
| 勝利 / 失敗 jingle | 2 |
| 金幣 / 魔晶拾取 | 2 |
| BGM 循環:主選單 / 戰鬥 / boss | 3 |

### 風險
最大變數係「合成出嚟好唔好聽」—— 我聽唔到,只可以做到頻譜 / 包絡合理。
所以先做一小批(UI 3 個 + 塔攻擊 6 個原型 + 1 首 BGM)交你試聽,啱先生成餘下嗰批。
