# Asset & Data Contract (shared by art generator and game code)

All generated art goes to `res://assets/generated/`. Original pixel art only — no pixels copied
from `art_reference/`. Nearest-neighbour filtering (crisp pixels).

**呢兩條規則有一個例外:`art_reference/` 底下呢三個資料夾係 Jack 自己生成、
自己擁有嘅正式遊戲素材,授權直接處理入遊戲 ——**

| 資料夾 | 由邊時起 | 出咩 | 工具 |
|---|---|---|---|
| `art_reference/monster/` | 2026-08-06 | 60 張怪物 sprite | `tools/monster_cutout.py` |
| `art_reference/tower/` | 2026-08-07 | 60 張塔 sprite | `tools/tower_cutout.py` |
| `art_reference/magic/` | 2026-08-07 | 41 張魔法 icon(45 格入面) | `tools/magic_cutout.py` |

呢三批都唔係程序生成,亦都係全套資產入面**唯一**用 LINEAR filter 嗰批
(手繪圖 + 非整數縮放)—— 其餘嘅圖照舊 NEAREST。
`art_reference/` 其餘嘅圖照舊「只准睇唔准抄像素」。

## Family IDs (order 1..10)
1 goblin, 2 wolf, 3 skeleton, 4 golem, 5 ghost, 6 bat, 7 treant, 8 beetle, 9 cultist, 10 slime

## Monster sprites(2026-08-06 換成 sprite-sheet 摳圖)
- `monsters/{fam}_{lvl}.png` — fam in the 10 ids above, lvl 1..5
- `monsters/{fam}_boss.png` — boss per family
- **PNG 唔再係正方形**,係就住主體剪到啱剪(66..189px)。錨點靠計:
  sprite 中心 = 怪物喺路上嘅位置,腳底離中心嘅距離同舊版一模一樣。
- 顯示尺寸(冇變):`lvl` 邊長 × `GameData.RENDER_SCALE`(2.0)
  = 64 / 70 / 76 / 82 / 88,boss 192 級數。
- 檔案解像度:lv1-5 = 顯示尺寸 × 1.25,boss = 顯示尺寸 × 0.75。所以
  `Monster.gd` 要用 `GameData.MON_ART_SCALE`(0.8)/ `MON_ART_SCALE_BOSS`(4/3),
  **唔係** `RENDER_SCALE`。`size`(血條 / 特效半徑)仍然行 `RENDER_SCALE`。
- 呢三個數(檔案解像度、`MON_ART_SCALE`、`monster_cutout.py` 嘅 `SS_*`)係
  一組綁死嘅 —— 改一個冇改另外兩個,全場怪物即刻大細錯。
- Level progression 由來源 sprite sheet 決定(每級加裝備、色深、boss 有王冠 /
  光環 / 衛星元素)。

## Tower sprites(2026-08-07 換成 sprite-sheet 摳圖)
- `towers/tower_{id}.png` / `_t2` / `_t3` — id 1..20,三個進化階。
- **高度一律 128px,闊度逐張剪到啱剪(50..174px)。** 高度冇得剪:接地線就住
  node 落 61 畫布 px,所以每張嘅畫布半高都至少 61+3。同高呢個副作用係想要嘅
  —— UI 用 `STRETCH_KEEP_ASPECT_CENTERED`,60 張同高先會縮到一樣大。
- **接地線 y=125 / 128**(= 舊 44px 圖嘅 43 / 44),底座水平中心 = 畫布中線。
  一座塔三個 tier 共用同一個縮放倍率,所以進化換圖唔會跳位。
- 顯示尺寸(冇變):128 × `GameData.TOWER_RENDER`(**0.6875**)= 88px。
  **呢三個數綁死** —— `tower_cutout.py` 嘅 `CANVAS` / `GROUND_Y` 同 `TOWER_RENDER`,
  改一個冇改另外兩個,全場塔即刻大細錯或者浮起 / 陷落地面。
- filter:LINEAR(手繪圖 + 非整數縮放)。

## Spell icons(2026-08-07 換成 sprite-sheet 切格)
- `spells/spell_{id}.png` / `_t2` / `_t3` — id 1..15,三個進化階。
- **新圖 64x64 正方形**,圓角 alpha(inset 3%、圓角半徑 15.6%),底色跟源圖
  (元素色),第二 / 三階疊 `gen_art.py` 嘅銀 / 金框 —— 戰鬥卡片冇位擺文字,
  階級一直都係靠嗰個框讀。
- **四格例外:龍捲風 t3、地震術 t1、地震術 t2、烈焰之牆 t3 喺源圖度冇**,
  仲行緊 `gen_art.py` 嘅 44x44 程序畫法(`PROCEDURAL_SPELLS`)。
  補到圖之後三個地方要一齊改:`magic_cutout.py` 嘅 `GRID` / `MISSING`、
  `gen_art.py` 嘅 `PROCEDURAL_SPELLS`、`test/TowerArtTest` 嘅 `STILL_PROCEDURAL`。
- filter:64px 嗰批 LINEAR,44px 嗰四張照 NEAREST(`UI.tex_rect` 按圖嘅尺寸判)。

## UI / world
- `ui/coin.png` 40x40 — gold coin, yellow, highlight glint.
- `ui/crystal.png` 40x40 — blue/purple faceted crystal, glow. MUST look clearly different from coin.
- `ui/base.png` 96x96 — player base crystal/banner (bottom of map).
- `ui/soldier.png` 20x20 — barracks/militia soldier token.
- `tiles/ground.png` 128x128, `tiles/road.png` 128x128 — tileable-ish terrain/path fill.

## Data IDs
- Towers 1..20, spells 1..15 exactly as numbered in the task spec.
- Starting unlocked towers: 1,2,5,13. Starting spell: 1.
- Upgrade cost curve: cost(lv) = round(base * 1.35^(lv-1)), max lv 15 per direction.
