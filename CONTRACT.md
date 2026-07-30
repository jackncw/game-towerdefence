# Asset & Data Contract (shared by art generator and game code)

All generated art goes to `res://assets/generated/`. Original pixel art only — no pixels copied
from `art reference/`. Nearest-neighbour filtering (crisp pixels).

## Family IDs (order 1..10)
1 goblin, 2 wolf, 3 skeleton, 4 golem, 5 ghost, 6 bat, 7 treant, 8 beetle, 9 cultist, 10 slime

## Monster sprites
- `monsters/{fam}_{lvl}.png` — fam in the 10 ids above, lvl 1..5
- `monsters/{fam}_boss.png` — boss per family
- Sizes (square PNG, creature centred, transparent bg):
  - lvl1=32, lvl2=35, lvl3=37, lvl4=40, lvl5=44, boss=96
- Level progression: size up, colour deeper/brighter, cumulative features (horns/armor/aura),
  lvl5 = elite (crown/glow) recognisable at a glance.

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
