extends Node
## Headless balance simulation. Three modes:
##
##   (default)  PLAYTHROUGH — plays levels 1..20 end to end as a *reasonable*
##              player: spends gold on towers as it comes in, spends 魔晶 between
##              attempts on unlocks and upgrades, and retries a level it loses.
##              Reports clear rate, attempts, boss-fight length and the economy.
##
##   --towers   TOWER BENCH — every tower gets the SAME gold budget on the SAME
##              wave, once solo and once mixed into an arrow-tower baseline, so
##              "冇廢塔冇獨大" can be judged from numbers instead of feel.
##
##   --spells   SPELL BENCH — casts each spell once into an identical standing
##              crowd and measures the damage and the control it produces.
##
##   --rework   REWORK CHECK — the two design targets from the 詛咒塔 / 導彈塔
##              rework, measured rather than asserted by feel:
##                * 詛咒塔: "詛咒塔 + 3 輸出" vs "4 輸出" at aura coverage 1 / 2 / 3
##                  must lose / tie / win
##                * 導彈塔: same investment must beat a generic output tower on a
##                  boss by +30-50% AND lose to it on a trash wave
##
## Everything is stepped MANUALLY at a fixed dt with the tree paused, so results
## are frame-rate independent and repeatable across machines.
##   godot --headless --path . res://test/BalanceSim.tscn -- --towers
##
## Backs up and restores the real save.json.

const DT := 1.0 / 30.0
const MAX_ATTEMPTS := 4          # how many times our player retries a level
const LEVELS := 20
const ATTEMPT_TIMEOUT := 320.0   # in-game seconds before we call an attempt stuck

var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false          # we own navigation; see Flow.goto
	get_tree().paused = true
	seed(0xBA1A)
	var args := OS.get_cmdline_user_args()
	if "--towers" in args:
		await _bench_towers()
	elif "--spells" in args:
		await _bench_spells()
	elif "--rework" in args:
		await _bench_rework()
	elif "--econ10" in args:
		await _econ_table()
	else:
		await _playthrough()
	get_tree().paused = false
	Flow.nav_enabled = true
	_restore_save()
	get_tree().quit(0)

# ===========================================================================
# MODE 1 — 20-level playthrough
# ===========================================================================
func _playthrough() -> void:
	Meta.reset_save()
	print("SIM PLAYTHROUGH  (levels 1..%d, up to %d attempts each)" % [LEVELS, MAX_ATTEMPTS])
	print("SIM  lv | boss族   | try | 結果 | 用時s | boss戰s | 擊殺 | 塔/位 | 金收入 | 剩金 | boss殘血 | 魔晶(前→後)")
	var total_attempts := 0
	var first_try := 0
	var cleared := 0
	var walls: Array = []
	var usage: Dictionary = {}          # tower id -> times placed across the run
	var usage_win: Dictionary = {}      # tower id -> times placed in a CLEARED run
	for lv in range(1, LEVELS + 1):
		var attempt := 0
		var won := false
		while attempt < MAX_ATTEMPTS and not won:
			attempt += 1
			total_attempts += 1
			var c0: int = Meta.crystals
			var r: Dictionary = await _play_attempt(lv)
			won = r.win
			for id in r.used:
				usage[id] = int(usage.get(id, 0)) + int(r.used[id])
				if won:
					usage_win[id] = int(usage_win.get(id, 0)) + int(r.used[id])
			# the real 輸→升級→再試 loop: bank the payout, then shop
			_spend_crystals()
			print("SIM  %2d | %-8s| %d   | %s | %5.1f | %6s | %5d | %2d/%2d | %6d | %5d | %7d%% | %5d→%-5d"
				% [lv, GameData.FAMILIES[GameData.level_config(lv).boss_family].name,
				attempt, "通關" if won else "失守", r.time,
				("%.1f" % r.boss_fight) if r.boss_fight > 0.0 else "-",
				r.kills, r.towers, r.spots, r.income, r.gold_left,
				int(round(r.boss_left * 100.0)), c0, Meta.crystals])
			if won and attempt == 1:
				first_try += 1
		if won:
			cleared += 1
		else:
			# Do not stop at the first wall: force the level cleared so the run can
			# profile the WHOLE curve in one pass and show every wall, not just the
			# first one. Walls are listed separately in the summary.
			walls.append(lv)
			Meta.on_level_cleared(lv)
			_spend_crystals()
			print("SIM  >>> 第 %d 關 %d 次都過唔到 = 卡關(強制放行,繼續量度後面)" % [lv, MAX_ATTEMPTS])
	print("SIM ---- 總結 ----")
	print("SIM 通關 %d/%d 關,總嘗試 %d 次,一次過 %d 關 (%.0f%%)"
		% [cleared, LEVELS, total_attempts, first_try,
		100.0 * float(first_try) / maxf(1.0, float(cleared))])
	if walls.is_empty():
		print("SIM 冇卡關")
	else:
		print("SIM 卡關關卡: %s" % [walls])
	# --- 塔使用率 -----------------------------------------------------------
	# Which towers the simulated player actually reached for, and how often the
	# runs that used them ended in a clear. A tower that never appears here is a
	# tower no reasonable build has a reason to buy.
	print("SIM")
	print("SIM ---- 塔使用率(20 關內自動玩家實際擺過幾多座)----")
	print("SIM  id | 塔名       | 擺過 | 其中通關局 | 通關率")
	var total_placed := 0
	for t in GameData.TOWERS:
		total_placed += int(usage.get(int(t.id), 0))
	for t in GameData.TOWERS:
		var n: int = int(usage.get(int(t.id), 0))
		var w: int = int(usage_win.get(int(t.id), 0))
		print("SIM  %2d | %-10s | %4d | %10d | %s"
			% [t.id, t.name, n, w,
			("%.0f%%" % (100.0 * float(w) / float(n))) if n > 0 else "—(冇被揀過)"])
	print("SIM  總共擺咗 %d 座" % total_placed)

## One attempt at `level` with the current Meta state.
func _play_attempt(level: int) -> Dictionary:
	var b = await _start(level)
	var start_gold: int = b.gold
	var spent := 0
	var spots := _spots(b)
	var spot_i := 0
	var t := 0.0
	var boss_at := -1.0
	while not b.ended and t < ATTEMPT_TIMEOUT:
		# spend gold as it arrives
		while spot_i < spots.size():
			var id: int = _next_buy(b)
			if id == 0:
				break
			var cost: int = int(GameData.tower_by_id(id).place_cost)
			while spot_i < spots.size() and not b.can_place(spots[spot_i]):
				spot_i += 1
			if spot_i >= spots.size():
				break
			if b.place_tower(id, spots[spot_i]):
				spent += cost
			spot_i += 1
		if b.boss_spawned and boss_at < 0.0:
			boss_at = t
		_step(b, DT)
		t += DT
	var used: Dictionary = {}
	for tw in b.towers:                      # `t` is the elapsed-time accumulator
		used[int(tw.id)] = int(used.get(int(tw.id), 0)) + 1
	var res := {
		"win": b.ended and Flow.last_result.get("win", false),
		"time": t,
		"kills": b.kills,
		"towers": b.towers.size(),
		"income": b.gold + spent - start_gold,
		"boss_fight": (t - boss_at) if (boss_at >= 0.0 and b.ended) else 0.0,
		"boss_left": (1.0 - b.boss_best_frac) if b.boss_spawned else 1.0,
		"spots": spots.size(),
		"gold_left": b.gold,
		"used": used,
	}
	await _end(b)
	return res

# Towers that mainly exist to buy time / money rather than to kill things. A
# reasonable player mixes a few in but does not build a wall of them.
const SUPPORT := ["slowfield", "alchemy", "barracks", "frost", "magnet", "teleport", "curse", "holy", "thorn"]
const SUPPORT_SHARE := 0.35

## What our player buys next, given what is already on the field: the best
## damage-per-gold tower it can afford right now, with roughly a third of the
## field kept for support/economy. Deliberately ordinary — an optimised build
## order would hide balance problems instead of exposing them. Upgrade levels
## are included, so a heavily upgraded tower correctly becomes the better buy.
func _next_buy(b) -> int:
	var want_support: bool = float(_support_count(b)) < float(maxi(1, b.towers.size())) * SUPPORT_SHARE
	var best := _pick(b, want_support)
	if best == 0:
		best = _pick(b, not want_support)     # nothing in the preferred category
	return best

## BOSS_SHARE: a level is roughly a third boss fight, and our player knows the
## boss is coming — so a tower's worth is its wave output plus its boss output,
## weighted. Without this the valuation is blind to `bossmult` and would never
## name 導彈塔 no matter how good it is at the job it exists for.
const BOSS_SHARE := 0.35

func _pick(b, support: bool) -> int:
	var best := 0
	var best_v := -1.0
	for id in Meta.unlocked_towers:
		var def := GameData.tower_by_id(id)
		var cost: int = int(def.place_cost)
		if cost > b.gold:
			continue
		if (def.mech in SUPPORT) != support:
			continue
		var v: float = _support_value(b, int(id), cost) if support else _damage_value(int(id), cost)
		if v > best_v:
			best_v = v
			best = int(id)
	return best

## A tower's worth per gold. Deliberately simple and UNCHANGED from the round-6
## run that validated the difficulty curve — the point of the playthrough is to
## measure the curve under a fixed player, so the player must not move when the
## game does. `bossmult` is folded in at BOSS_SHARE weight because a build that
## is blind to the boss phase would never even consider a boss specialist.
##
## LIMITATION, stated plainly: this greedy dps-per-gold rule cannot value
## positioning, target priority or synergy, so 箭塔 wins it almost always. The
## tower-usage table below therefore measures THIS HEURISTIC, not the game. Real
## evidence about a single tower comes from the controlled benches
## (--towers / --rework), where every build faces an identical wave.
func _damage_value(id: int, cost: int) -> float:
	var st: Dictionary = Meta.tower_stats(id)
	var dps: float = float(st.get("dmg", 0.0)) * float(st.get("rate", 0.0))
	var boss_dps: float = dps * (1.0 + float(st.get("bossmult", 0.0)))
	return (dps * (1.0 - BOSS_SHARE) + boss_dps * BOSS_SHARE) / float(cost)

func _support_value(b, id: int, cost: int) -> float:
	# 詛咒塔 is a pure amplifier — buying it before there is any output to amplify
	# is a trap, and its own design text says so. Everything else is cheapest-first,
	# exactly as in the round-6 run that validated the curve.
	if GameData.tower_by_id(id).mech == "curse" and _damage_tower_count(b) < 4:
		return -1.0
	return 1000.0 / float(cost)

func _damage_tower_count(b) -> int:
	var n := 0
	for t in b.towers:
		if not (t.mech in SUPPORT):
			n += 1
	return n

func _support_count(b) -> int:
	var n := 0
	for t in b.towers:
		if t.mech in SUPPORT:
			n += 1
	return n

## Between-attempt shopping. A reasonable player does NOT spread upgrade levels
## evenly over every direction of every tower they own — they pick a couple of
## workhorses and deepen those, unlocking only enough breadth to answer the
## enemies they keep meeting. Spending everything on the globally cheapest
## upgrade (the naive policy) buys ~1 level per level of progress and models
## nobody. `core` = the towers this build actually leans on.
const CORE_COUNT := 3            # workhorse towers we keep investing in
const UNLOCK_TARGET := 6         # breadth we want before going deep
const CORE_DIRS := ["dmg", "rate", "range"]

## Returns what it spent, split by kind, so the 收支表 can book it.
func _spend_crystals() -> Dictionary:
	var out := {"unlock": 0, "upgrade": 0}
	var guard := 0
	while guard < 400:
		guard += 1
		var before: int = Meta.crystals
		if Meta.unlocked_towers.size() < UNLOCK_TARGET and _buy_best_unlock():
			out.unlock += before - Meta.crystals
			continue
		if _buy_core_upgrade():
			out.upgrade += before - Meta.crystals
			continue
		return out
	return out

# ===========================================================================
# MODE 5 — 頭 10 關魔晶收支表
# ===========================================================================
## Answers the one question a payout multiplier has to answer: does the player
## still have something left to want? Plays levels 1..10 with the same
## reasonable player as the playthrough, and books every 魔晶 in and out.
const ECON_LEVELS := 10

func _econ_table() -> void:
	Meta.reset_save()
	print("SIM 魔晶收支表 (第 1-%d 關, CRYSTAL_REWARD_MULT=%.1f)"
		% [ECON_LEVELS, GameData.CRYSTAL_REWARD_MULT])
	print("SIM  lv | 嘗試 | 本關收入 | 其中通關 | 其中首通 | 其中敗方 | 解鎖支出 | 升級支出 | 期末餘額 | 已解鎖塔 | 升級總級數")
	var t_in := 0
	var t_unlock := 0
	var t_up := 0
	for lv in range(1, ECON_LEVELS + 1):
		var attempt := 0
		var won := false
		var inc_clear := 0
		var inc_first := 0
		var inc_lose := 0
		var sp_unlock := 0
		var sp_up := 0
		while attempt < MAX_ATTEMPTS and not won:
			attempt += 1
			var c0: int = Meta.crystals
			var r: Dictionary = await _play_attempt(lv)
			won = r.win
			# Battle already paid out through Meta; recover the split from the
			# result Flow recorded rather than re-deriving it here.
			var res: Dictionary = Flow.last_result
			if won:
				inc_clear += int(res.get("base", 0))
				inc_first += int(res.get("first", 0))
			else:
				inc_lose += Meta.crystals - c0
			var sp: Dictionary = _spend_crystals()
			sp_unlock += int(sp.unlock)
			sp_up += int(sp.upgrade)
		if not won:
			Meta.on_level_cleared(lv)     # force through, same as the playthrough
			var sp2: Dictionary = _spend_crystals()
			sp_unlock += int(sp2.unlock)
			sp_up += int(sp2.upgrade)
		var income := inc_clear + inc_first + inc_lose
		t_in += income
		t_unlock += sp_unlock
		t_up += sp_up
		print("SIM  %2d | %4d | %8d | %8d | %8d | %8d | %8d | %8d | %8d | %7d/%d | %10d"
			% [lv, attempt, income, inc_clear, inc_first, inc_lose, sp_unlock, sp_up,
			Meta.crystals, Meta.unlocked_towers.size(), GameData.TOWERS.size(),
			_total_up_levels()])
	print("SIM ---- 合計 ----")
	print("SIM 總收入 %d,解鎖用咗 %d,升級用咗 %d,剩低 %d" % [t_in, t_unlock, t_up, Meta.crystals])
	# The harness player only ever unlocks UNLOCK_TARGET towers and only ever
	# deepens CORE_DIRS on CORE_COUNT towers — that is a POLICY, not a budget
	# limit. So state the budget question directly: could 10 levels of income buy
	# out the shop, which is the "第3關買晒嘢就冇癮" failure mode.
	var shop_all := 0
	for t in GameData.TOWERS:
		shop_all += maxi(0, int(t.unlock))
	var spells_all := 0
	for s in GameData.SPELLS:
		spells_all += maxi(0, Meta.spell_unlock_cost(s.id))
	print("SIM 全解鎖成本:塔 %d + 魔法 %d = %d;頭 %d 關總收入 %d = 其中 %.0f%%"
		% [shop_all, spells_all, shop_all + spells_all, ECON_LEVELS, t_in,
		100.0 * float(t_in) / maxf(1.0, float(shop_all + spells_all))])
	var owned: int = Meta.unlocked_towers.size()
	print("SIM 第%d關完:解鎖 %d/%d 座塔,升級 %d 級,下一個最平解鎖仲要 %s"
		% [ECON_LEVELS, owned, GameData.TOWERS.size(), _total_up_levels(),
		("冇嘢可解鎖" if _cheapest_locked() < 0 else str(_cheapest_locked()))])
	# Inflation check: crystals sitting idle with nothing worth buying is the
	# failure mode a x3 payout can create.
	# Inflation reads as "money with nothing left to want": a big idle balance
	# next to cheap remaining purchases.
	print("SIM 通脹指標:期末餘額 %d,最平未解鎖 %s,最平核心升級 %d -> %s"
		% [Meta.crystals,
		("冇" if _cheapest_locked() < 0 else str(_cheapest_locked())),
		_cheapest_core_upgrade(),
		("有嘢想買,唔算通脹" if Meta.crystals < _cheapest_core_upgrade() else "餘額買得起下一級,注意")])

func _total_up_levels() -> int:
	var n := 0
	for t in GameData.TOWERS:
		for l in Meta.tower_levels(int(t.id)):
			n += int(l)
	return n

func _cheapest_locked() -> int:
	var best := -1
	for t in GameData.TOWERS:
		if Meta.is_tower_unlocked(t.id) or int(t.unlock) <= 0:
			continue
		if best < 0 or int(t.unlock) < best:
			best = int(t.unlock)
	return best

func _cheapest_core_upgrade() -> int:
	var best := 1 << 30
	for id in _core_towers():
		var def := GameData.tower_by_id(id)
		var levels: Array = Meta.tower_levels(int(id))
		for d in def.ups.size():
			if not (String(def.ups[d].stat) in CORE_DIRS):
				continue
			if int(levels[d]) >= GameData.MAX_UP_LV:
				continue
			best = mini(best, Meta.tower_up_cost(int(id), d))
	return 0 if best == (1 << 30) else best

func _buy_best_unlock() -> bool:
	var best := 0
	var best_cost := 1 << 30
	for t in GameData.TOWERS:
		if Meta.is_tower_unlocked(t.id) or int(t.unlock) <= 0:
			continue
		if int(t.unlock) < best_cost:
			best_cost = int(t.unlock)
			best = int(t.id)
	if best == 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.unlock_tower(best)

## The towers this build leans on: best raw output per gold among what we own.
func _core_towers() -> Array:
	var ranked: Array = Meta.unlocked_towers.duplicate()
	ranked.sort_custom(func(a, c):
		return _out_per_gold(int(a)) > _out_per_gold(int(c)))
	return ranked.slice(0, mini(CORE_COUNT, ranked.size()))

func _out_per_gold(id: int) -> float:
	var st: Dictionary = Meta.tower_stats(id)
	var cost: float = maxf(1.0, float(GameData.tower_by_id(id).place_cost))
	return float(st.get("dmg", 0.0)) * float(st.get("rate", 0.0)) / cost

func _buy_core_upgrade() -> bool:
	var best_id := 0
	var best_dir := -1
	var best_cost := 1 << 30
	for id in _core_towers():
		var def := GameData.tower_by_id(id)
		var levels: Array = Meta.tower_levels(id)
		for d in def.ups.size():
			if not (String(def.ups[d].stat) in CORE_DIRS):
				continue
			if int(levels[d]) >= GameData.MAX_UP_LV:
				continue
			var cost: int = Meta.tower_up_cost(int(id), d)
			if cost < best_cost:
				best_cost = cost
				best_id = int(id)
				best_dir = d
	if best_id == 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.buy_tower_upgrade(best_id, best_dir)

# ===========================================================================
# MODE 2 — per-tower bench
# ===========================================================================
const BENCH_LEVEL := 14          # mid-game wave: hard enough that leaks separate builds
const BENCH_BUDGET := 900        # deliberately tight — an unlimited budget makes
                                 # every tower look identical (everything leaks 0)
const BENCH_SECONDS := 60.0
const BENCH_SPAWN := 0.35

func _bench_towers() -> void:
	print("SIM TOWER BENCH  (第%d關波次, 預算%d金, %.0f秒, 每%.2f秒出一隻)"
		% [BENCH_LEVEL, BENCH_BUDGET, BENCH_SECONDS, BENCH_SPAWN])
	var base: Dictionary = await _bench_field([1], BENCH_BUDGET, false)
	var base_boss: Dictionary = await _bench_field([1], BENCH_BUDGET, true)
	print("SIM 基準(全箭塔): 波次傷害=%d 擊殺=%d | boss 情境: 打甩 %d%% boss 血"
		% [base.dmg, base.kills, int(round(base_boss.boss_dmg * 100.0))])
	print("SIM  id | 塔名       | 座 | 單塔波次傷害 | vs基準 | 混編波次傷害 | vs基準 | boss打甩% | vs基準")
	for t in GameData.TOWERS:
		var solo: Dictionary = await _bench_field([int(t.id)], BENCH_BUDGET, false)
		var mix: Dictionary = await _bench_field([1, int(t.id)], BENCH_BUDGET, false)
		var boss: Dictionary = await _bench_field([1, int(t.id)], BENCH_BUDGET, true)
		print("SIM  %2d | %-10s | %2d | %11d | %+5d%% | %11d | %+5d%% | %8d%% | %+d%%"
			% [t.id, t.name, solo.towers,
			solo.dmg, int(round(100.0 * (float(solo.dmg) / maxf(1.0, float(base.dmg)) - 1.0))),
			mix.dmg, int(round(100.0 * (float(mix.dmg) / maxf(1.0, float(base.dmg)) - 1.0))),
			int(round(boss.boss_dmg * 100.0)),
			int(round((boss.boss_dmg - base_boss.boss_dmg) * 100.0))])

## Build a field out of `ids` (round-robin) for `budget` gold and run a fixed
## wave. `boss_mode` swaps the trash wave for a single level boss so towers that
## exist to kill one big thing (狙擊/導彈/光束) get a situation where that counts.
func _bench_field(ids: Array, budget: int, boss_mode: bool) -> Dictionary:
	# every configuration must face the SAME dice: crit rolls / proc rolls swamp
	# the signal otherwise (an identical build measured 47% and 24% boss damage on
	# two consecutive runs before this was pinned).
	seed(0x5EED)
	var b = await _start(BENCH_LEVEL)
	b.gold = budget
	b.base_shield = 100000
	b.boss_time = 1.0e9          # we spawn the boss ourselves, if at all
	var spots := _spots(b)
	var spot_i := 0
	var k := 0
	while spot_i < spots.size():
		var id: int = ids[k % ids.size()]
		var cost: int = int(GameData.tower_by_id(id).place_cost)
		if b.gold < cost:
			break
		if b.place_tower(id, spots[spot_i]):
			k += 1
		spot_i += 1
	var placed: int = b.towers.size()
	var gold_at_build: int = b.gold
	var t := 0.0
	var spawn := 0.0
	var fams: Array = b.cfg.families
	var fi := 0
	var boss: Monster = null
	if boss_mode:
		boss = b._spawn_monster(b.cfg.boss_family, 5, true, 0.0)
		b.boss_ref = boss
		b.boss_spawned = true
		if boss.mech == "revive":
			b.skeleton_boss_alive = boss
	while t < BENCH_SECONDS:
		if not boss_mode:
			spawn -= DT
			if spawn <= 0.0:
				spawn = BENCH_SPAWN
				# start them 45% down the road: over a 60s window from the spawn
				# point almost nothing reaches the base, so every build measured
				# zero leaks and the metric said nothing
				b._spawn_monster(fams[fi % fams.size()], 1 + (fi % 4), false,
					b.route.total * 0.45)
				fi += 1
		_step(b, DT)
		t += DT
		if boss_mode and b.boss_best_frac >= 1.0:
			break
	var res := {
		"towers": placed,
		"kills": b.kills,
		"leaks": 100000 - b.base_shield,
		"gold": b.gold - gold_at_build,
		"boss_dmg": b.boss_best_frac if boss_mode else 0.0,
		"dmg": int(b.damage_dealt),
	}
	await _end(b)
	return res

# ===========================================================================
# MODE 4 — rework design-target check
# ===========================================================================
const RW_LEVEL := 10
const RW_SECONDS := 50.0
const RW_SPAWN := 0.5

func _bench_rework() -> void:
	print("SIM REWORK CHECK  (第%d關波次, %.0f秒, 每%.2f秒出一隻)" % [RW_LEVEL, RW_SECONDS, RW_SPAWN])
	print("SIM")
	print("SIM --- 1. 詛咒塔:「詛咒塔 + 3 輸出」vs「4 輸出」---")
	print("SIM  光環覆蓋 | 詛咒方傷害 | 對照(4輸出) | 比值 | 設計目標 | 結果")
	var targets := {1: "要輸", 2: "要打和", 3: "要贏"}
	for cover in [1, 2, 3]:
		var a: int = await _rw_field(cover, true)
		var bb: int = await _rw_field(cover, false)
		var ratio: float = float(a) / maxf(1.0, float(bb))
		var ok: bool
		if cover == 1:
			ok = ratio < 0.98
		elif cover == 2:
			ok = ratio > 0.94 and ratio < 1.06
		else:
			ok = ratio > 1.02
		print("SIM  %8d | %10d | %11d | %.3f | %-7s | %s"
			% [cover, a, bb, ratio, targets[cover], "OK" if ok else "唔達標"])

	print("SIM")
	print("SIM --- 2. 導彈塔:同等投資,打 boss vs 打雜兵海 ---")
	var base_boss: Dictionary = await _bench_field([1], BENCH_BUDGET, true)
	var base_wave: Dictionary = await _bench_field([1], BENCH_BUDGET, false)
	var mis_boss: Dictionary = await _bench_field([1, 16], BENCH_BUDGET, true)
	var mis_wave: Dictionary = await _bench_field([1, 16], BENCH_BUDGET, false)
	var boss_gain: float = mis_boss.boss_dmg / maxf(0.001, base_boss.boss_dmg) - 1.0
	var wave_gain: float = float(mis_wave.dmg) / maxf(1.0, float(base_wave.dmg)) - 1.0
	print("SIM  boss 情境:箭塔基準打甩 %d%%,加入導彈塔 %d%% -> %+.0f%%  (目標 +30~50%%) %s"
		% [int(round(base_boss.boss_dmg * 100.0)), int(round(mis_boss.boss_dmg * 100.0)),
		boss_gain * 100.0, "OK" if boss_gain >= 0.30 and boss_gain <= 0.55 else "唔達標"])
	print("SIM  雜兵海:箭塔基準傷害 %d,加入導彈塔 %d -> %+.0f%%  (目標:要輸) %s"
		% [base_wave.dmg, mis_wave.dmg, wave_gain * 100.0, "OK" if wave_gain < 0.0 else "唔達標"])

	# --- 3. 真.關卡 A/B ------------------------------------------------------
	# The 20-level playthrough cannot answer "揀咗呢座塔嘅局點樣" because its greedy
	# dps-per-gold player never picks either tower (see the usage table). So ask it
	# directly: play a REAL level three times with the same gold, changing only
	# which towers go in two of the slots.
	print("SIM")
	print("SIM --- 3. 真.關卡 A/B(第%d關,同一預算,只換兩個塔位)---" % AB_LEVEL)
	print("SIM  陣容            | 結果 | 用時s | 擊殺 | 總傷害 | 收入")
	for label in ["全箭塔(對照)", "換 2 座詛咒塔", "換 2 座導彈塔"]:
		var swap := 0
		if label == "換 2 座詛咒塔":
			swap = 17
		elif label == "換 2 座導彈塔":
			swap = 16
		var r: Dictionary = await _ab_level(swap)
		print("SIM  %-16s | %s | %5.1f | %4d | %6d | %5d"
			% [label, "通關" if r.win else "失守", r.time, r.kills, r.dmg, r.income])

const AB_LEVEL := 12
const AB_BUDGET := 1600

## Play a real level with a fixed budget field: arrows everywhere, except the two
## slots CLOSEST to the road midpoint which get `swap` (0 = keep arrows). Those
## two slots are the ones a 詛咒塔 aura would actually want.
func _ab_level(swap: int) -> Dictionary:
	seed(0x5EED)
	Flow.selected_level = AB_LEVEL
	Flow.last_result = {}
	var b = await _start(AB_LEVEL)
	b.gold = AB_BUDGET
	var spots := _spots(b)
	var mid: int = int(spots.size() * 0.45)
	var order: Array = spots.duplicate()
	# build outward from the middle of the path so the swapped pair sits inside
	# the same cluster as the arrows around them
	order.sort_custom(func(x, y):
		return absf(spots.find(x) - mid) < absf(spots.find(y) - mid))
	var placed := 0
	var swapped := 0
	var start_gold: int = b.gold
	var spent := 0
	for p in order:
		var id: int = 1
		if swap != 0 and swapped < 2 and placed >= 2:
			id = swap
		var cost: int = int(GameData.tower_by_id(id).place_cost)
		if b.gold < cost:
			break
		if b.place_tower(id, p):
			spent += cost
			placed += 1
			if id == swap:
				swapped += 1
	var t := 0.0
	while not b.ended and t < ATTEMPT_TIMEOUT:
		_step(b, DT)
		t += DT
	var res := {
		"win": b.ended and Flow.last_result.get("win", false),
		"time": t, "kills": b.kills, "dmg": int(b.damage_dealt),
		"income": b.gold + spent - start_gold,
	}
	await _end(b)
	return res

## One coverage scenario. `with_curse` picks between
##   詛咒塔(anchor) + `cover` 輸出塔喺光環覆蓋嘅路段 + (3-cover) 喺遠處另一段
##   4 輸出塔:同樣位置,但詛咒塔嗰格換成多一座輸出塔
## Both fields face the identical wave, so `damage_dealt` is directly comparable.
func _rw_field(cover: int, with_curse: bool) -> int:
	seed(0x5EED)
	var b = await _start(RW_LEVEL)
	b.gold = 100000
	b.base_shield = 100000
	b.boss_time = 1.0e9
	var route = b.route
	var spots := _spots(b)
	# anchor: a spot around the middle of the path; "near" = same stretch of road,
	# "far" = a stretch the aura cannot possibly touch
	var anchor: Vector2 = spots[int(spots.size() * 0.45)]
	var ad: float = route.nearest_dist_param(anchor)
	var near: Array = []
	var far: Array = []
	for p in spots:
		if p == anchor:
			continue
		var d: float = absf(route.nearest_dist_param(p) - ad)
		if d < 150.0:
			near.append(p)
		elif d > 700.0:
			far.append(p)
	if with_curse:
		b.place_tower(17, anchor)
	else:
		b.place_tower(1, anchor)
	var placed_near := 0
	for p in near:
		if placed_near >= (cover if with_curse else cover):
			break
		if b.place_tower(1, p):
			placed_near += 1
	var placed_far := 0
	for p in far:
		if placed_far >= 3 - cover:
			break
		if b.place_tower(1, p):
			placed_far += 1
	var t := 0.0
	var spawn := 0.0
	var fams: Array = b.cfg.families
	var fi := 0
	while t < RW_SECONDS:
		spawn -= DT
		if spawn <= 0.0:
			spawn = RW_SPAWN
			b._spawn_monster(fams[fi % fams.size()], 1 + (fi % 4), false, 0.0)
			fi += 1
		_step(b, DT)
		t += DT
	var dmg: int = int(b.damage_dealt)
	await _end(b)
	return dmg

# ===========================================================================
# MODE 3 — per-spell bench
# ===========================================================================
func _bench_spells() -> void:
	print("SIM SPELL BENCH  (第%d關怪, 30 隻站定, 觀察 6 秒)" % BENCH_LEVEL)
	print("SIM  id | 魔法名   | CD  | 總傷害 | 擊殺 | 減速/暈眩隻數 | 推返距離 | 每秒CD傷害")
	for sp in GameData.SPELLS:
		var r: Dictionary = await _bench_spell(int(sp.id))
		var cd: float = float(Meta.spell_stats(sp.id).get("cd", float(sp.cd)))
		print("SIM  %2d | %-8s | %4.1f | %6d | %4d | %13d | %8d | %10.1f"
			% [sp.id, sp.name, cd, r.dmg, r.kills, r.controlled, r.pushed,
			float(r.dmg) / maxf(1.0, cd)])

func _bench_spell(id: int) -> Dictionary:
	var b = await _start(BENCH_LEVEL)
	b.base_shield = 100000
	b.boss_time = 1.0e9
	# a standing crowd: freeze them in place so the measurement is about the
	# spell, not about how far anyone happened to walk
	var crowd: Array = []
	var hp0 := 0.0
	var dist0: Array = []
	for i in 30:
		var m: Monster = b._spawn_monster(b.cfg.families[i % b.cfg.families.size()],
			2 + (i % 3), false, 300.0 + i * 18.0)
		m.base_speed = 0.0
		crowd.append(m)
		hp0 += m.hp
		dist0.append(m.dist)
	var centre: Vector2 = crowd[15].global_position
	Spells.cast(b, id, centre)
	# Control is sampled 0.5s in, not at the end: freeze (2.5s), stun (2.5s) and
	# slow (2-4s) have all expired by t=6, so measuring at the end reported ZERO
	# controlled targets for 冰凍新星 / 時間扭曲 / 磁暴脈衝 — the three spells whose
	# entire job is control.
	var t := 0.0
	var controlled := 0
	while t < 6.0:
		_step(b, DT)
		t += DT
		if t >= 0.5 and controlled == 0:
			for m in crowd:
				if m.alive and (m.slow_time > 0.0 or m.stun_time > 0.0
						or m.freeze_time > 0.0 or m.rooted_time > 0.0):
					controlled += 1
	var hp1 := 0.0
	var kills := 0
	var pushed := 0.0
	for i in crowd.size():
		var m: Monster = crowd[i]
		if not m.alive:
			kills += 1
			continue
		hp1 += m.hp
		pushed += maxf(0.0, dist0[i] - m.dist)
	var res := {
		"dmg": int(hp0 - hp1),
		"kills": kills,
		"controlled": controlled,
		"pushed": int(pushed),
	}
	await _end(b)
	return res

# ===========================================================================
# harness
# ===========================================================================
func _start(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE   # children inherit ALWAYS from us
	add_child(b)
	await get_tree().process_frame
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true   # Battle._exit_tree unpauses; re-pause for the next run

## One simulation tick. The tree is paused, so nothing advances unless we say so:
## drive Battle plus every live child of its four containers at a fixed dt.
func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

## Buildable spots ordered along the path, so the field grows from the spawn end
## forward exactly as a player would build it.
func _spots(b) -> Array:
	var out: Array = []
	for gy in range(3, 21):
		for gx in range(1, 15):
			var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
			if b.can_place(p):
				out.append(p)
	var route = b.route
	out.sort_custom(func(x, y):
		return route.nearest_dist_param(x) < route.nearest_dist_param(y))
	return out

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
