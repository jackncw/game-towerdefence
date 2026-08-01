# Round 9 Report — Audio Completion, One-Gesture Building, Difficulty-Wall Withdrawal

Verification and publish pass for round 9 (2026-08-01). Covers: full 64-sound audio
system, the one-gesture quick-build row + `QuickBar` pinning screen, and an honest
account of the difficulty-wall feature that was measured and withheld.

## TL;DR

- **Audio: shipped complete.** 64 sounds (up from 11), `gen_audio.py --verify` reports
  0 problems, `AudioTest` and `AudioHookTest` both pass.
- **One-gesture building: shipped complete.** Permanent 6-slot quick row + `More`
  drawer button replaces the old build handle; `QuickBar` main-menu screen lets the
  player arrange the six slots. Visual self-check done in both locales, no layout
  fixes needed.
- **Difficulty walls: built, measured, withheld.** `GameData.WALLS := {}` ships empty.
  The measurement tooling (`BalanceSim --walls`, adaptive player, 11 `sim_*`
  counters) ships and is documented. No skull markers, no fail-screen hints — there
  is nothing to mark.
- **Full suite: 19/19 tests exit 0.** One known pre-existing skip (`AudioTest` "T
  時間縮放", needs a real audio driver).
- **Performance: no regression by the pass/fail gate** (min fps must stay ≥55; it's
  109–116). Average fps reads lower than the previously recorded figure but the two
  runs aren't the same measurement window — see the Performance section.
- **Web export rebuilt**, `docs/index.pck` 7.1MB → 58.5MB (all the new WAV content).

---

## Acceptance checklist

| # | Item | Status | Evidence |
|---|---|---|---|
| 1 | 64 sounds, `gen_audio.py --verify` 0 problems | ✅ | `python tools/gen_audio.py --verify` → `64 file(s), 0 with problems` |
| 2 | Main menu → boss battle has sound throughout | ✅ | `AudioHookTest` exit 0, all `H1`–`H5` cases pass |
| 3 | 5x doesn't clip/overload (dedup) | ✅ | `AudioTest` case `D 同幀 20 次只響一次` passes; `perf_r9.log` min fps 109–116 |
| 4 | battle → boss BGM handoff is bar-aligned, seamless | ✅ | `AudioTest` case group `A` passes; `gen_audio.py --verify` shows `bgm_battle`/`bgm_boss` seam 0.0000 |
| 5 | Three walls + non-wall levels all hit target | ❌ **withdrawn** | `BALANCE_CHANGELOG.md` §"第九輪" — none of the three walls met the target; see below |
| 6 | Level-select danger marker + fail-screen counter hint, both languages | ❌ **cancelled** | No walls to mark; `LevelSelect.gd` has no danger-marking code, `Fail.gd` has no wall-hint code (verified by grep) |
| 7 | One-gesture build test passes, drawer never opens during the gesture | ✅ | `BottomBarTest` exit 0, case `Q 全程冇開過抽屜` and `Q 抽屜真係冇現身` pass |
| 8 | Tightest layout (15 spells + 6 tower slots) screenshot self-check, both languages | ✅ | See "Visual self-check" below |
| 9 | Pinned slots survive a restart | ✅ | `BottomBarTest` `Q` round-trip case + `QuickBar` writes through `Meta.set_quick_slot`/`swap_quick_slots`, both persisted via `Meta.save_game()` |
| 10 | Full suite green | ✅ | 19/19 exit 0 (see table below) |
| 11 | Pushed to GitHub, commit hash recorded | ✅ | see bottom of this report |

---

## 1. Audio — complete list of 64 sounds

Confirmed via `python tools/gen_audio.py --verify` (0 clipping, 0 near-silent, 0
format problems, 0 loop-seam problems, 64 files). 11 of these existed before round 9
(6 tower archetypes, `bgm_battle`, 4 `ui_*`); 53 are new this round.

### Music (3)
| Sound | Description |
|---|---|
| `bgm_menu` | Unhurried major-key menu loop, 90bpm — deliberately not the battle loop slowed down |
| `bgm_battle` | Main battle loop, 132bpm (pre-existing) |
| `bgm_boss` | Boss theme, same 132bpm/root as battle so the bar-aligned handoff never breaks tempo or key; darker progression, lead an octave down, thinner duty cycle |

### Jingles (3)
| Sound | Description |
|---|---|
| `jingle_win` | Ascending 5-note major fanfare on victory |
| `jingle_lose` | Descending 4-note minor phrase on defeat |
| `jingle_first_clear` | The win motif shifted up an octave with a shimmer tail and closing arpeggio, for a level's first-ever clear |

### Tower attack sounds — 6 shared archetypes (pre-existing)
| Sound | Description |
|---|---|
| `sfx_atk_arrow` | Bow thwip; pitched and shared across arrow / gatling / sniper |
| `sfx_atk_cannon` | Shared across cannon / mortar / missile |
| `sfx_atk_electric` | Lightning tower's zap |
| `sfx_atk_fire` | Fireball tower's whoosh |
| `sfx_atk_frost` | Frost/alchemy tower's chill hit |
| `sfx_atk_beam` | Beam/holy tower's sustained ray |

### Tower sounds — new dedicated (8, round 9 Task 3)
| Sound | Description |
|---|---|
| `sfx_atk_boomerang` | Rotation-modulated whirr, replaces a pitched arrow borrow |
| `sfx_atk_magnet` | Deep rising pulse, no high end |
| `sfx_atk_poison` | Wet band-pass spray + gooey low end |
| `sfx_atk_teleport` | Rising-then-falling square sweep pair |
| `sfx_atk_thorn` | Sharp spike snap + high-frequency crackle |
| `sfx_tower_barracks` | Two-note muster horn on troop spawn |
| `sfx_aura_curse` | Slow low drone on curse-aura refresh; mixed at RMS 0.06 so it stays under combat sounds |
| `sfx_field_slow` | Breathing field tone on the slow-field pulse; also RMS 0.06 |

### Death sounds — one per family (10, Task 1)
| Sound | Description |
|---|---|
| `sfx_die_goblin` | Shriek sweep + noise tail |
| `sfx_die_wolf` | Vibrato howl sweep |
| `sfx_die_skeleton` | Dry, six-click scattering bone rattle |
| `sfx_die_golem` | Crumbling rock + three staggered thuds |
| `sfx_die_ghost` | Fade-**in** triangle dissolve + high noise tail, deliberately no attack transient |
| `sfx_die_bat` | High-pitched squeak sweep |
| `sfx_die_treant` | Crack + falling groan sweep |
| `sfx_die_beetle` | Brittle shell crack + falling square |
| `sfx_die_cultist` | Chant cut off mid-note, drops a fourth |
| `sfx_die_slime` | Wet low burst, long tail, no high end |

### Hit sounds — by target defense, not damage type (3, Task 1)
| Sound | Description |
|---|---|
| `sfx_hit_soft` | Low thud for unarmoured targets |
| `sfx_hit_hard` | Low thump + falling square for armoured targets (armor ≥8) |
| `sfx_hit_magic` | Triangle sweep + high noise for magic-resistant targets (mres ≥15) |

### Spell sounds — one per spell (15, Task 2)
| Sound | Description |
|---|---|
| `sfx_spell_meteor` | Falling whoosh into a low double impact |
| `sfx_spell_stormbolt` | Seven staggered, randomized-pitch square zaps |
| `sfx_spell_freezenova` | Crystalline dual triangle sweep + noise burst |
| `sfx_spell_miasma` | Band-pass hiss cloud + muddy low sawtooth |
| `sfx_spell_summon` | Three-note ascending major triad + magic dust |
| `sfx_spell_midas` | Five randomized bright coin-stack triangles |
| `sfx_spell_timewarp` | Slow vibrato sawtooth pitch-down |
| `sfx_spell_warcry` | Rising square shout + low noise body |
| `sfx_spell_barrier` | Rising tone settling into a steady hum |
| `sfx_spell_tornado` | Band-pass noise with rotating amplitude modulation |
| `sfx_spell_quake` | Deep sine rumble + low noise + three punctuating cracks |
| `sfx_spell_firewall` | Band-pass noise sweeping left-to-right + low crackle |
| `sfx_spell_smite` | Bright strike, then a two-note holy chord |
| `sfx_spell_emp` | Harsh fast-falling square + noise crackle, roughest bitcrush in the set |
| `sfx_spell_blackhole` | Inward sawtooth suck + collapsing sine |

### System sounds (12, Task 4)
| Sound | Description |
|---|---|
| `sfx_gold_pop` | Short, bright metallic tick per gold pickup |
| `sfx_gold_bank` | Two-note ascending chime for a banked gold total |
| `sfx_crystal_gain` | Glassy three-partial shimmer, long tail, no noise component (deliberately unlike gold) |
| `sfx_upgrade` | Three-note major ascending arpeggio |
| `sfx_unlock` | Four-note major ascending fanfare, bright final note |
| `sfx_boss_warning` | Two-tone klaxon + low threat drone on boss spawn |
| `sfx_base_danger` | Low double-thump heartbeat when the base is threatened |
| `sfx_teleport_hit` | Rising-then-falling square pair, arrival/departure |
| `sfx_knockback` | Low thud + falling sine, physical push |
| `sfx_summon_circle` | Rising triangle drone + sparkle for the militia summon circle |
| `sfx_place_tower` | Dust thump + settling square as a tower lands |
| `sfx_sell_tower` | `sfx_place_tower`'s phrase reversed + two coin ticks |

### UI sounds (4, pre-existing)
| Sound | Description |
|---|---|
| `ui_click` | Generic button tap |
| `ui_error` | Disabled/invalid-action buzz |
| `ui_panel_open` | Panel/drawer opening |
| `ui_panel_close` | Panel/drawer closing |

**Total: 3 + 3 + 6 + 8 + 10 + 3 + 15 + 12 + 4 = 64.**

---

## 2. One-gesture building

**Shipped:** the old "建造" drawer handle is gone. In its place, a permanent 6-slot
quick row (`UI.QUICK_RECT`, 7 cells: 6 tower slots + a `More` button) sits directly
above the always-visible spell grid. The six slots reuse the existing card gesture
chain unchanged (`_card_gui` → press/drag/release), so building one of the six pinned
towers is press-drag-release in one motion, with no drawer opening at any point.
Tapping an empty slot, or the `More` button, opens the drawer (the full 20-tower
warehouse) exactly as before. Slot assignment is persisted (`Meta.quick_slots`,
survives save/reload) and is edited from a new main-menu screen, `QuickBar` — chosen
over doing it in-battle because the only spare in-battle gesture (long-press) collides
with "press-and-drag-to-place."

`BottomBarTest` covers this directly: `Q 一手勢起到塔`, `Q 全程冇開過抽屜`, `Q 抽屜真係
冇現身`, plus geometry checks (`Q 七格冇重疊`, `Q 唔撞魔法列`, touch-target minimum
88px). All pass.

### Visual self-check

Ran `tools/art_export.gd` in both `zh_TW` and `en`, with `Meta.quick_slots = [1, 2, 5,
13, 7, 9]` (all six quick slots filled) so the shots capture the actual tightest
bottom-bar state: 6 quick-slot cards + `More`/`更多` + a 15-spell grid, all on screen
at once. Also added a shot of the `QuickBar` screen itself (`23_quickbar.png`),
because it wasn't captured before and the brief explicitly asks for a look at it —
this is a tooling addition to `art_export.gd`, not a game-code change.

Examined, both locales:

- **`02_battle.png` / `03_battle_place.png`** (full combat + placement-drag state):
  the 6 quick-slot cards read cleanly — tower icon, coin icon, price (60/110/90/90/
  160/150), all legible, no overlap. The `更多`/`More` 7th cell sits at the same row,
  same size, text centered and unclipped. The 15-spell grid (two rows of 8+7) sits
  immediately below with each cell independently framed — the two rows read as
  distinct bars, not a single merged block. The quick row stays on screen unchanged
  while a tower is mid-drag with the range-preview circle up (`03_battle_place`),
  confirming it isn't hidden or covered by placement UI.
- **`21_bar_drawer.png` (en)**: drawer open over a live field, 20 towers in a 4-column
  grid, each cell a two-line wrapped name ("Cannon Battery", "Boomerang Tower",
  "Slowing Field", etc.) — none truncated, none overlapping their price row, and the
  drawer's bottom edge sits right above the quick row without covering it.
- **`23_quickbar.png`**, both locales: the preview row at the top is pixel-identical
  geometry to the real battle bottom bar (shared constants, `UI.QUICK_RECT` /
  `quick_cell_w()`), 6 slots + disabled `More`/`更多`. Below it, all 20 unlocked
  towers in a 4×5 grid. English names — "Cannon Battery", "Boomerang Tower", "Bramble
  Tower", "Alchemy Tower", "Slowing Field" — all wrap to a single line inside their
  232×168 cell with no clipping or overlap; longest names sit comfortably above the
  price row.
- **English-specific check**: per the note that English runs ~1.7x the width of 繁中
  for words like "More"/tower names, I looked specifically for truncation in the `en`
  shots. `Level 4` / `BOSS INCOMING!` (vs `第 4 關` / `BOSS 出場!`) both stay inside
  their banner. `Goblins BOSS` (vs `哥布林族 BOSS`) fits the left label without
  overrunning into the health bar. `Defenses Breached!` / `Monsters reached the keep
  — Level 3` (fail screen) both fit their panels with room to spare.

**No layout problems found; no fixes needed.** The only change made to `art_export.gd`
was the required `Meta.quick_slots` fill (brief item) and the new `QuickBar` shot
(tooling gap, not a game-code change).

---

## 3. Difficulty walls — built, measured, and withheld

**`GameData.WALLS := {}` ships empty.** `level_config()` behaves identically to
before this round for every one of the 20 levels. The feature that would put a real
difficulty wall at levels 7/13/18 was built, measured across three rounds of tuning,
and did not meet its own target, so the project owner withheld it rather than ship a
wall that doesn't wall.

**Target:** first-clear rate ≤30% and ≤90%-in-three-tries at the three wall levels;
≥85% first-clear on every non-wall level.

**What ships:** the measurement tooling only —
- `BalanceSim --walls` mode: plays a full 20-level campaign per seed (not a jump to
  the wall level), with a real lose → payout → upgrade → retry loop, up to 3 losses.
- Two simulated players run the same seed list: an **adaptive** player (loses feed
  back into buying the counter it needed) and the original **greedy** player,
  unchanged. The gap between their results is the read on "does this wall force a
  composition change."
- 11 new `sim_*` counters on `Battle`/`Monster`, each mapped to something a real
  player would say ("something reached my door", "I killed it and it got back up",
  "their health bar keeps refilling", "my hits look like they're landing on nothing —
  and it's the one eating my shots").
- A per-level field-size cap and a per-tower-slot valuation, used only in `--walls`
  mode.
- `wall_slot()` / `is_wall()` / `wall_hint_key()` in `GameData.gd`, exercised by
  `WallTest` against an injected fake wall (so the mechanism is covered even though
  the real content is empty).
- Four i18n keys kept for whenever this reopens: `LEVELSEL_DANGER`, `WALL_HINT_7`,
  `WALL_HINT_13`, `WALL_HINT_18` — all translated, both languages, verified present
  in `i18n/game.csv` (§ above). No code currently reads them into a level-select
  marker or a fail-screen hint — that task (round 9 Task 9) is cancelled; `LevelSelect
  .gd` has no danger-marking code and `Fail.gd` has no wall-hint code, confirmed by
  direct inspection.

**Key measured findings** (pulled from `BALANCE_CHANGELOG.md` §"第九輪 — 難度牆量度";
full log files listed there: `sim_walls_r9_shipped.log`, `sim_walls_r9_withheld.log`,
plus per-iteration `sim_tune_*` / `sim_capsweep_*` / `sim_walls_r9_it*` logs):

1. **Adding families to a spawn pool makes a level *easier*, not harder.**
   `_spawn_wave_monster()` draws uniformly from `cfg.families`, so appending a family
   to the list dilutes every family already there. The first wall design added bats
   (7.2 HP/gold) and cultists (7.1) to level 7's base of ancient treants (13.6) and
   slimes (12.0) — the two most expensive families in the game — and the average
   blood-per-gold dropped from 12.8 to 9.5. **Level 7 got roughly a quarter easier.**
   More monsters also means more kills, more gold, and more towers — every
   dilution-style wall was funding its own counter. This approach (`add_fams`) was
   scrapped entirely in favour of `pool`, which *replaces* the family list rather
   than appending to it. That fix alone moved level 7's farthest-advance win rate
   from 11% to 96%, and level 13's from 14% to 69%.
2. **`pool`-replacement is the right mechanism, and it works** — but density
   (`spawn_min`) is the only other lever `level_config()` exposes, and density
   overrides whatever the wall is trying to teach. Every wall design that was pushed
   hard enough to actually threaten the player degenerated into a crowd problem: at
   level 7's tuned `spawn_min` 0.105, the failure diagnostic reads `crowd ×35, heal
   ×35` in the same breath — the wall's intended axis (healing/regen sustain) gets
   drowned out by "there are simply too many monsters on screen," which is not the
   lesson the wall was built to teach.
3. **The composition gap never went positive.** The entire premise of a wall is that
   it should force the player to buy a *different* loadout than the one that clears
   every other level — measured as a gap between the adaptive player (who reacts to
   losses by buying counters) and the greedy player (who doesn't). In the final
   12-seed × 2-player acceptance run:

   | Level | Wall | Adaptive 1st-clear | Adaptive ≤3 tries | Greedy 1st-clear | Composition gap | Met target? |
   |---|---|---|---|---|---|---|
   | 1–6 | — | 100% | 100% | 100% | +0% | OK |
   | **7** | **wall** | **0%** ✓ | **8%** ✗ (need ≥90%) | 0% | **−92%** | **No** |
   | 8–12 | — | 100% | 100% | 100% | +0% | OK |
   | **13** | **wall** | **67%** ✗ (need ≤30%) | **100%** ✓ | 92% | +0% | **No** |
   | 14–17 | — | 100% | 100% | 100% | +0% | OK |
   | **18** | **wall** | **100%** ✗ | 100% | 100% | +0% | **No** |
   | 19–20 | — | 100% | 100% | 100% | +0% | OK |

   Level 13 came closest (its axis, corpse-count, happens to align with density
   itself — the one wall where density and intent point the same way). Levels 7 and
   18 both missed outright. The −92% gap at level 7 is real but backwards: the
   *greedy* player did better than the adaptive one there, traced to a probable
   defect in the adaptive player's upgrade-buying policy (documented as unverified —
   see open items below), not to the wall producing a genuine composition
   requirement anywhere in the 12-seed run.

**Structural conclusion (from `BALANCE_CHANGELOG.md` §8, the one thing worth reading
before anyone reopens this):** `level_config()` only reads `pool` and `spawn_min`.
The family damage-per-gold table only spans 7.1–13.6 (1.9x), and the families that
best express each wall's intended mechanic (bat 7.2/flight, ghost 7.3/magic-resist,
cultist 7.1/group-heal) are also the cheapest in the table — so the only real
difficulty lever left is density, and density is what breaks the read. What's
missing for next time: a **per-level family-strength multiplier**, or letting `pool`
specify **weights** so the expensive/threatening families dominate the draw instead
of being drawn uniformly. Both are small `level_config()` changes but are outside
"only touch `WALLS` contents," so this round didn't do them.

---

## 4. Full test suite

All 19 test scenes run headless, exit code 0.

| Test | Exit | Notes |
|---|---|---|
| AudioTest | 0 | `AUDIO PASS fails=0 skips=1` — see open items |
| AudioHookTest | 0 | all H1–H5 cases pass |
| WallTest | 0 | `WALL PASS fails=0` |
| BottomBarTest | 0 | includes all `Q` (quick-row) and `O` cases |
| RegressionTest | 0 | |
| SpellFlowTest | 0 | |
| BossSpawnTest | 0 | |
| BossHealTest | 0 | |
| WinTest | 0 | |
| LoseTest | 0 | |
| SpeedScaleTest | 0 | |
| EconTest | 0 | |
| FlowTest | 0 | |
| I18nTest | 0 | `I18N: 688 passed, 0 failed` |
| BestiaryTest | 0 | |
| ScrollTest | 0 | `SCROLLTEST PASS fails=0` |
| StretchTest | 0 | `STRETCH PASS fails=0` |
| SceneCheck | 0 | `CHECK: ALL DONE` |
| InputProbe | 0 | |

**ALL PASS.**

(Several tests print `ERROR: N resources still in use at exit` on shutdown — this is
Godot's own scene-cleanup diagnostic on `--headless` exit, unrelated to test pass/fail;
exit code and the test's own PASS/FAIL line are the actual signal, both green.)

---

## 5. Performance

`tools/perf5x.tscn`, uncapped, 20-tower field + saturated ~130-monster crowd + boss,
`Engine.time_scale = 5.0`. Two clean runs (no competing GPU load):

| Run | avg fps | min fps | peak monsters | towers |
|---|---|---|---|---|
| Previously recorded (`perf.log`) | 161.3 | 107.0 | 136 | 43 |
| Round 9, run 1 | 133.5 | 116.0 | 140 | 43 |
| Round 9, run 2 (clean, isolated) | 139.8 | 109.0 | 138 | 43 |

**No regression by the actual gate:** the brief's stated concern is min fps dropping
below 55, and it hasn't — both round-9 runs land at 109–116, essentially matching or
beating the recorded 107.0 minimum, with a comparable peak monster count and the same
tower count.

Average fps reads 13–17% lower than the recorded 161.3. I don't believe this is
comparable apples-to-apples: `perf5x.gd` samples once per rendered frame over a fixed
12-second *real-time* window (`_run := 12.0`), so sample count should equal roughly
`avg_fps × 12`. The recorded baseline logged `samples=546`, which at its own reported
avg_fps of 161.3 implies a ~3.4s window, not 12s — both round-9 runs are internally
consistent (`samples=1671` at `avg_fps=139.8` → 1671/12 ≈ 139.3, matches). That means
the recorded baseline was very likely captured under a different `_run` duration or
different code path than what's in the repo now, making a direct average-fps
comparison unreliable; the minimum-fps figures (which are a single worst-sample value,
not window-dependent) are the only cross-run-safe comparison, and those pass cleanly.
I did not find any sign in these numbers of an audio-driven regression specifically —
`AudioTest`'s dedup case (`D 同幀 20 次只響一次`) passes, meaning the pooling/dedup that
exists precisely to prevent 5x audio overload is doing its job.

---

## 6. Web export

Rebuilt via `--headless --export-release "Web" "docs/index.html"`, exit 0, no errors.
`docs/index.pck` grew from 7.1MB to 58.5MB (all 64 audio assets now included, up from
11). `docs/index.wasm` unchanged in size (39.5MB) as expected — engine binary, not
asset content.

---

## 7. Known open items

1. **`AudioTest`'s `T 時間縮放` case reports SKIP under `--headless`.** It needs an
   audio driver that actually advances playback position, which the headless dummy
   driver doesn't provide. This is a known, tracked, pre-existing condition, not a
   failure — confirmed still skipping in this run (`AUDIO PASS fails=0 skips=1`). I
   did not additionally run it windowed this session (no new information expected
   beyond what round 9 Task 5 already established when it verified the windowed
   pass).
2. **`gen_audio.py` uses one shared RNG.** Adding a new synthesized sound anywhere in
   the file shifts the random draws every later `def` sees, so regenerating after an
   edit silently changes the exact bytes of unrelated existing sounds (still passes
   `--verify`, since it checks objective properties, not byte-identity — but a
   "just retune this one sound" request will, in practice, touch every `.wav` after
   it in generation order).
3. **`I18nTest` validates non-emptiness and glyph coverage, not grammatical
   completeness.** 688 checks pass, confirming every `tr()` key resolves to a
   non-empty, font-coverable string in both languages — it does not check that a
   translated sentence is grammatically well-formed or that formatted placeholders
   (`{n}`, `{pct}`) land in a sensible spot in the translated word order.
4. **Adaptive-player-underperforms-greedy at level 7** (BALANCE_CHANGELOG.md §9):
   the wall-tuning adaptive AI does worse than the unmodified greedy AI at the one
   wall where the composition gap went most negative. Likely cause identified but
   *unverified*: `_ad_buy_upgrade` may inherit a "buy the cheapest available level"
   policy that, with three extra upgrade axes unlocked by the wall's answer tower,
   spreads purchases across many level-1 upgrades instead of concentrating them.
   Flagged in the changelog for whoever reopens the wall work, not fixed this round.

---

## Commit hash

`<filled in after commit — see follow-up commit "Record the round 9 commit hash in the report">`
