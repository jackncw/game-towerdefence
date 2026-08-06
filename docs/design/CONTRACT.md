# Asset & Data Contract (shared by art generator and game code)

All generated art goes to `res://assets/generated/`. Original pixel art only — no pixels copied
from `art_reference/`. Nearest-neighbour filtering (crisp pixels).

**呢兩條規則有一個例外(2026-08-06 起):`art_reference/monster/` 嗰 10 張
sprite sheet 係 Jack 自己生成、自己擁有嘅正式遊戲素材,授權直接處理入遊戲。**
60 張怪物 sprite 就係由嗰度摳出嚟(`tools/monster_cutout.py`),唔係程序生成;
佢哋亦都係全套資產入面唯一用 LINEAR filter 嘅(手繪圖 + 非整數縮放)。
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

## Tower sprites
- `towers/tower_{id}.png` — id 1..20, 64x64 canvas, tower art ~56px, base pad at bottom.

## Spell icons
- `spells/spell_{id}.png` — id 1..15, 64x64 canvas (rounded square frame, element-coded).

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
