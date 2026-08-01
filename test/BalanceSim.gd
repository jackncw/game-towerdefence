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
##   --walls    難度牆驗收 — plays levels 1..20 from a fresh save on each of
##              WALL_SEEDS seeds, retrying up to three times with the real
##              spend-crystals-between-attempts loop in between, and reports
##              first-try / three-try clear rates per level. Runs the sweep TWICE:
##              once with a composition-changing adaptive player and once with the
##              fixed greedy player, because the gap between them is the evidence
##              that a wall demands a different build rather than more upgrade
##              levels. See 自適應玩家 below.
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
	elif "--curve" in args:
		await _curve_table()
	elif "--walls" in args:
		await _walls_table()
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
##
## `adaptive` swaps ONLY the buy rule, from the fixed greedy player to the
## composition-changing one used by --walls (see 自適應玩家 below). It defaults to
## false, so --playthrough / --curve / --econ10 call this exactly as before.
func _play_attempt(level: int, adaptive := false, field_cap := 0) -> Dictionary:
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
			# `field_cap` > 0 stops the player at N towers. Off (0) everywhere except
			# the --walls sweep; see _wall_field_cap() for why it exists and how it scales.
			if field_cap > 0 and b.towers.size() >= field_cap:
				break
			var id: int = _ad_next_buy(b) if adaptive else _next_buy(b)
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
		# What the attempt FELT like, from Battle's sim_* measurement counters. Only
		# the adaptive player reads this; every other mode ignores the key.
		"sig": {
			"deep_flying": int(b.sim_deep_flying),
			"deep_ground": int(b.sim_deep_ground),
			"leak_flying": bool(b.sim_leak_flying),
			"revives": int(b.sim_revives),
			"splits": int(b.sim_splits),
			"peak_alive": int(b.sim_peak_alive),
			"heal": float(b.sim_heal_enemy),
			"dmg": float(b.damage_dealt),
			"raw_phys": float(b.sim_raw_phys),
			"out_phys": float(b.sim_out_phys),
			"raw_magic": float(b.sim_raw_magic),
			"out_magic": float(b.sim_out_magic),
			"max_frac": float(b.sim_max_frac),
		},
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
const ECON_LEVELS := 20   # round 8: the brief asks for the whole curve, not the first ten

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

# ===========================================================================
# MODE 6 — 獎勵曲線 vs 升級成本曲線 (--curve)
# ===========================================================================
## The payouts have to be pinned to something the player actually feels, and the
## only such thing is "what does my next upgrade cost right now". C(N) is that
## number, measured rather than assumed: the MEDIAN price of the next level on
## every axis this player is currently investing in, sampled at the moment they
## start level N. Because upgrade cost is base * 1.35^lv, C(N) grows
## geometrically — which is exactly why linear payouts (36+8n) fell further and
## further behind as the run went on.
##
## Prints one row per level: C(N), what the CURRENT formulas pay, and whether a
## loss covers one upgrade level. The new formulas are fitted to this table.
func _curve_table() -> void:
	Meta.reset_save()
	print("SIM 獎勵曲線 (CRYSTAL_REWARD_MULT=%.2f)" % GameData.CRYSTAL_REWARD_MULT)
	print("SIM  lv | C(N) 下級價 | 通關 | 首通 | 敗(p=典型) | 敗/C | 通關/C | 輸一場升到級? | 實測敗場 p")
	var rows: Array = []
	for lv in range(1, LEVELS + 1):
		var cn := _typical_next_cost()
		# what the formulas pay AT THIS POINT in the run
		var clear: int = GameData.level_crystal_reward(_payout_level(lv))
		var first: int = GameData.level_first_clear_bonus(_payout_level(lv))
		var lose_typ: int = GameData.level_lose_reward(_payout_level(lv), 27,
			60.0, 100.0, 0.25)     # a "reasonable" loss: ~60% progress
		var attempt := 0
		var won := false
		var ps: Array = []
		while attempt < MAX_ATTEMPTS and not won:
			attempt += 1
			var r: Dictionary = await _play_attempt(lv)
			won = r.win
			if not won:
				# `boss_left` is HP REMAINING; lose_progress wants HP REMOVED
				ps.append(GameData.lose_progress(int(r.kills), float(r.time),
					float(GameData.level_config(lv).boss_time), 1.0 - float(r.boss_left)))
			_spend_crystals()
		if not won:
			Meta.on_level_cleared(lv)
			_spend_crystals()
		var pmean := 0.0
		for p in ps:
			pmean += float(p)
		pmean = (pmean / ps.size()) if not ps.is_empty() else -1.0
		rows.append({"lv": lv, "c": cn, "clear": clear, "first": first, "lose": lose_typ,
			"p": pmean})
		print("SIM  %2d | %10d | %4d | %4d | %10d | %4.2f | %6.2f | %-12s | %s"
			% [lv, cn, clear, first, lose_typ,
			float(lose_typ) / maxf(1.0, float(cn)), float(clear) / maxf(1.0, float(cn)),
			("係" if lose_typ >= cn else "唔係"), ("-" if pmean < 0.0 else "%.2f" % pmean)])
	# summary: how badly the payout curve lags the cost curve
	var ok := 0
	for r in rows:
		if int(r.lose) >= int(r.c):
			ok += 1
	print("SIM ---- %d/%d 關「輸一場 >= 1 級升級」成立 ----" % [ok, rows.size()])
	var c1: float = float(rows[0].c)
	var cN: float = float(rows[rows.size() - 1].c)
	print("SIM C(1)=%d C(%d)=%d,幾何增長率 = %.3f/關"
		% [int(c1), rows.size(), int(cN), pow(cN / maxf(1.0, c1), 1.0 / float(rows.size() - 1))])
	var l1: float = float(rows[0].lose)
	var lN: float = float(rows[rows.size() - 1].lose)
	print("SIM 敗方獎勵 %d -> %d,增長率 = %.3f/關 (追唔追到成本曲線?)"
		% [int(l1), int(lN), pow(lN / maxf(1.0, l1), 1.0 / float(rows.size() - 1))])

## The level number the payouts are computed from — the level being PLAYED.
##
## Basing it on the highest cleared level instead was considered and rejected on
## the numbers: a player stuck on a new level is already playing their highest
## level, so it changes nothing for them, while a player who has cleared 15 and
## drops back to level 1 would start collecting level-15-sized payouts for a
## trivial fight. It makes old-level farming BETTER, not worse. The anti-farm job
## is done by GameData.LOSE_REPLAY_FRAC instead.
func _payout_level(playing: int) -> int:
	return playing

## Median next-level price across every axis this player is actually investing
## in — the core towers' CORE_DIRS, plus the cheapest remaining unlock while the
## player is still buying breadth. Median, not mean: one maxed-out 15th level at
## 1.35^14 would drag a mean far above anything the player is really looking at.
func _typical_next_cost() -> int:
	var costs: Array = []
	for id in _core_towers():
		var def := GameData.tower_by_id(id)
		var levels: Array = Meta.tower_levels(int(id))
		for d in def.ups.size():
			if not (String(def.ups[d].stat) in CORE_DIRS):
				continue
			if int(levels[d]) >= GameData.MAX_UP_LV:
				continue
			costs.append(Meta.tower_up_cost(int(id), d))
	if Meta.unlocked_towers.size() < UNLOCK_TARGET:
		var cl := _cheapest_locked()
		if cl > 0:
			costs.append(cl)
	if costs.is_empty():
		return 0
	costs.sort()
	return int(costs[costs.size() / 2])

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
# MODE 7 — 難度牆驗收 (--walls)
# ===========================================================================
## 「牆」係一個關於機率嘅講法 —— 「第一次到呢關預期會輸」 —— 所以量佢一定要跑多個
## seed。單次 playthrough 答唔到:一次通過只係一個樣本,而 crit / proc / spawn 家族
## 嘅骰喺一場入面嘅方差好大(round 6 量過同一個陣容連續兩次 boss 傷害係 47% 同 24%)。
##
## 每個 seed 都由 Meta.reset_save() 開始由第一關打上去,唔係直接跳去嗰關 —— 玩家到
## 第 13 關嗰陣有幾多升級,係佢前面十二關賺返嚟嘅,直接跳過去就等於問一個唔存在
## 嘅玩家。
##
## 跑兩次:一次自適應玩家,一次貪心玩家。點解要兩個,見下面「自適應玩家」嘅註解。
const WALL_SEEDS := 12
const WALL_MAX_TRIES := 3
## --- 場面上限,只喺 --walls 生效 -------------------------------------------
##
## 點解會有呢個掣。呢個 harness 嘅玩家係「有錢就即刻喺下一個空位起塔」,而地圖有
## 88-128 個可起塔位,佢由出怪口沿住路一路起上去。結果佢喺第 20 關會有 54 座塔,
## 剩 3891 金,boss 剩 1% 血 —— 換句話講,佢由頭到尾冇一關輸得到。
##
## 更嚴重嘅係個回路方向:牆加怪 -> 多擊殺 -> 多金 -> 多塔。第 7 關加咗成份之後佢由
## 12.5 座塔變 32 座。每幅加怪嘅牆都自己出錢買起自己嘅解藥。封住塔數就係斬斷呢條
## 回路 —— 封咗之後,多出嚟嘅怪冇得再換成防守。
##
## **只喺 --walls 用,而且兩個玩家都受同一個上限**,因為佢哋要互相比較。
## `--playthrough` / `--curve` / `--econ10` 嘅玩家一個字都冇變(呢三個 mode 唔會傳
## 呢個參數,`_play_attempt` 嘅預設係 0 = 唔封頂),所以 BALANCE_CHANGELOG 入面舊嘅
## 數字全部仍然成立。
##
## --- 點解係跟關數行,唔係一個常數 -------------------------------------------
## 試過常數,量到常數做唔到:
##   上限 18 -> 第 20 關首通 0%(非牆關要 >=85%,爆咗)
##   上限 24 -> 第 20 關首通 100%,但第 7 關嘅贏面只由 15% 郁到 20%
##   上限 30 -> 同 24 差唔多
## 原因係算術:同樣 24 座塔,喺第 7 關(wave_scale 2.08)同第 20 關(9.85)面對嘅
## 總血量差 11 倍。一個喺第 20 關啱啱好嘅常數,喺第 7 關等於送。而血量差係
## WAVE_GROWTH 決定嘅,唔喺 WALLS 手上。
##
## 所以上限跟返「玩家嘅場面本來就會隨住戰役長大」呢件事:唔封頂嘅 playthrough 量到
## 佢由第 1 關嘅 ~10 座長到第 20 關嘅 ~54 座。呢度用一條直線去追嗰條線嘅一個固定
## 比例(第 1 關 6/10 = 60%,第 7 關 12/19 = 63%,第 13 關 17/43 = 40%,第 20 關
## 24/54 = 44%),即係「一個唔會填晒 128 個位嘅人」。
##
## 斜率同截距唔係為咗令三幅牆輸而揀嘅 —— 唯一綁死嘅係尾端:WALL_CAP_AT_20 = 24 係
## 上面量到「第 20 關仲過到嘅最緊上限」(18 過唔到)。呢個同揀常數嗰陣用嘅係同一條
## 規則,只係而家沿住成條曲線應用。
const WALL_CAP_AT_1 := 8
const WALL_CAP_AT_20 := 24
## <= 0 就唔封頂。
func _wall_field_cap(level: int) -> int:
	if WALL_CAP_AT_20 <= 0:
		return 0
	var t: float = float(level - 1) / 19.0
	return maxi(1, int(round(lerpf(float(WALL_CAP_AT_1), float(WALL_CAP_AT_20), t))))

func _walls_table() -> void:
	print("SIM 難度牆驗收 (%d 個 seed, 每關最多 %d 次, 兩個玩家, 塔數上限 %s)"
		% [WALL_SEEDS, WALL_MAX_TRIES,
		"無" if WALL_CAP_AT_20 <= 0 else "第1關%d -> 第20關%d"
		% [_wall_field_cap(1), _wall_field_cap(LEVELS)]])
	var ad: Dictionary = await _walls_run(true)
	var gr: Dictionary = await _walls_run(false)
	print("SIM")
	print("SIM  lv | 牆 | 自適應首通 | 自適應%d次內 | 貪心首通 | 貪心%d次內 | 組成差距 | 平均嘗試 | 達標"
		% [WALL_MAX_TRIES, WALL_MAX_TRIES])
	var bad := 0
	var dead_walls: Array = []
	var soft_levels: Array = []
	for lv in range(1, LEVELS + 1):
		var f: float = float(ad.first[lv]) / float(WALL_SEEDS)
		var a: float = float(ad.any[lv]) / float(WALL_SEEDS)
		var gf: float = float(gr.first[lv]) / float(WALL_SEEDS)
		var ga: float = float(gr.any[lv]) / float(WALL_SEEDS)
		var avg: float = float(ad.tries[lv]) / float(WALL_SEEDS)
		var wall: bool = GameData.is_wall(lv)
		# 牆:第一次去到預期會輸(首通 <= 30%),但投資之後過到(3 次內 >= 90%)
		# 非牆:合理操作一次過(首通 >= 85%)
		var ok: bool = (f <= 0.30 and a >= 0.90) if wall else (f >= 0.85)
		if not ok:
			bad += 1
			if not wall:
				soft_levels.append(lv)
		# 一幅貪心玩家一樣輕鬆三次內過到嘅牆,唔係喺度考陣容,係喺度考升級級數 ——
		# 通過率幾靚都好,佢冇做緊佢存在嘅嗰件事。
		if wall and gf <= 0.30 and ga >= 0.90 and (a - ga) < 0.15:
			dead_walls.append(lv)
		print("SIM  %2d | %s | %9.0f%% | %11.0f%% | %7.0f%% | %9.0f%% | %+7.0f%% | %8.2f | %s"
			% [lv, "牆" if wall else "  ", f * 100.0, a * 100.0, gf * 100.0, ga * 100.0,
			(a - ga) * 100.0, avg, "OK" if ok else "唔達標"])
	print("SIM ---- %d/%d 關達標(自適應玩家)----" % [LEVELS - bad, LEVELS])
	if not soft_levels.is_empty():
		print("SIM 非牆關跌穿 85%%: %s —— 唔關 WALLS 事,係基礎曲線,只記錄唔喺呢度改"
			% [soft_levels])
	if not dead_walls.is_empty():
		print("SIM 無效嘅牆(貪心玩家一樣三次內過到,即係淨係考緊升級級數): %s" % [dead_walls])
	elif bad == 0:
		print("SIM 三幅牆都對貪心玩家造成咗真嘅阻力(組成差距 >= 15% 或者貪心過唔到)")
	# 自適應玩家喺每一關「感覺到」啲乜。呢個係牆有冇教到嘢嘅直接證據:一幅飛行牆
	# 應該讀到 air,一幅分裂牆應該讀到 crowd。
	print("SIM")
	print("SIM ---- 敗仗診斷(自適應玩家喺每關讀到嘅壓力,計數 = 診斷到嘅局數)----")
	for lv in range(1, LEVELS + 1):
		var d: Dictionary = ad.diag[lv]
		if d.is_empty():
			continue
		var parts: Array = []
		for t in AD_TAGS:
			if d.has(t):
				parts.append("%s x%d" % [t, int(d[t])])
		print("SIM  %2d %s | %s" % [lv, "牆" if GameData.is_wall(lv) else "  ", ", ".join(parts)])
	# --- 贏得幾驚險 ----------------------------------------------------------
	# 一個 100% 通過率答唔到「差幾多就輸」。呢張表答:最遠嗰隻怪行到成條路嘅幾多
	# (100% = 有嘢入到基地 = 輸)、同場最多幾多隻、行到門口嘅隻數、boss 剩幾多血、
	# 收工仲剩幾多金。如果通過率係 100% 而 max_frac 得五六成、剩金仲有幾千,咁「調
	# 成份」根本唔會改變任何嘢 —— 個瓶頸唔喺關卡,喺呢個模擬玩家身上。
	print("SIM")
	print("SIM ---- 贏面(自適應玩家,每關所有嘗試嘅平均)----")
	print("SIM  lv | 牆 | 最遠推進 | 到門口 | 同場最多 | 擊殺 | 塔數 | boss殘血 | 剩金")
	for lv in range(1, LEVELS + 1):
		var m: Dictionary = ad.marg[lv]
		var n: float = maxf(1.0, float(m.n))
		print("SIM  %2d | %s | %7.0f%% | %6.1f | %8.1f | %4.0f | %4.1f | %7.0f%% | %5.0f"
			% [lv, "牆" if GameData.is_wall(lv) else "  ",
			100.0 * float(m.frac) / n, float(m.deep) / n, float(m.peak) / n,
			float(m.kills) / n, float(m.towers) / n,
			100.0 * float(m.boss) / n, float(m.gold) / n])
	if bad > 0:
		print("SIM 未達標,要調 GameData.WALLS(牆太易 -> 加成份;牆太難 -> 減成份;"
			+ "非牆關跌穿 85% -> 睇下係咪牆嘅成份漏咗落隔離關)")

## One full 12-seed sweep with one of the two players. Both players face the SAME
## seed sequence, so the difference between the two tables is the player and not
## the dice.
func _walls_run(adaptive: bool) -> Dictionary:
	var who: String = "自適應" if adaptive else "貪心"
	var first: Dictionary = {}
	var any: Dictionary = {}
	var tries: Dictionary = {}
	var diag: Dictionary = {}
	var marg: Dictionary = {}
	for lv in range(1, LEVELS + 1):
		first[lv] = 0
		any[lv] = 0
		tries[lv] = 0
		diag[lv] = {}
		marg[lv] = {"n": 0, "frac": 0.0, "peak": 0, "deep": 0, "boss": 0.0,
			"gold": 0, "towers": 0, "kills": 0}
	for s in WALL_SEEDS:
		Meta.reset_save()
		_ad_reset()
		seed(0xBA1A + s * 7919)
		for lv in range(1, LEVELS + 1):
			var attempt := 0
			var won := false
			while attempt < WALL_MAX_TRIES and not won:
				attempt += 1
				var r: Dictionary = await _play_attempt(lv, adaptive, _wall_field_cap(lv))
				won = r.win
				if won and attempt == 1:
					first[lv] = int(first[lv]) + 1
				var sg: Dictionary = r.sig
				var mg: Dictionary = marg[lv]
				mg.n = int(mg.n) + 1
				mg.frac = float(mg.frac) + float(sg.max_frac)
				mg.peak = int(mg.peak) + int(sg.peak_alive)
				mg.deep = int(mg.deep) + int(sg.deep_flying) + int(sg.deep_ground)
				mg.boss = float(mg.boss) + float(r.boss_left)
				mg.gold = int(mg.gold) + int(r.gold_left)
				mg.towers = int(mg.towers) + int(r.towers)
				mg.kills = int(mg.kills) + int(r.kills)
				if adaptive:
					for t in _ad_observe(r, won):
						diag[lv][t] = int(diag[lv].get(t, 0)) + 1
					_ad_spend_crystals()
				else:
					_spend_crystals()
			tries[lv] = int(tries[lv]) + attempt
			if won:
				any[lv] = int(any[lv]) + 1
			else:
				# 同 playthrough 一樣強制放行,先至量到成條曲線而唔係淨係量到第一幅牆
				Meta.on_level_cleared(lv)
				if adaptive:
					_ad_spend_crystals()
				else:
					_spend_crystals()
		print("SIM   %s玩家 seed %d/%d 完成" % [who, s + 1, WALL_SEEDS])
	return {"first": first, "any": any, "tries": tries, "diag": diag, "marg": marg}

# ---------------------------------------------------------------------------
# 自適應玩家 —— 只俾 --walls 用
# ---------------------------------------------------------------------------
## 點解要多一個玩家。
##
## 上面嗰個玩家(_next_buy / _pick / _damage_value / _spend_crystals)輸咗只會做
## 一件事:袋起魔晶,喺佢本來就鍾意嗰兩三座塔身上再買多幾級。佢揀塔淨係睇每金傷
## 害,由頭到尾都唔會換陣容。
##
## 但「逼玩家換陣容」正正就係難度牆嘅全部論點 —— 一幅「你需要對空手段」嘅牆教到嘅
## 嘢,一幅「所有嘢多 40% 血」嘅牆教唔到。用一個永遠唔換陣容嘅玩家去調牆,調到佢
## 三次內過到,唯一調得出嘅結論就係「淨係買升級級數就夠」,而嗰樣正正係牆要防止嘅
## 失敗模式:個量度會過,但個設計會衰。所以呢度加咗一個會換陣容嘅玩家,而貪心玩家
## 一個字都冇改 —— --playthrough / --curve / --econ10 全部靠佢固定唔郁,郁咗就等於
## 靜靜雞廢咗 BALANCE_CHANGELOG.md 入面每一次舊量度。
##
## 呢個玩家係一個「講得通嘅人類」,唔係一個神:
##   * 佢淨係讀真人打完一場會察覺到嘅嘢 —— 有嘢衝到我門口而且係飛嘅、我殺咗佢佢
##     又企返起身、成場太多屍體、佢哋血一路上返、我啲彈打落去似冇入面。全部由
##     Battle 嘅 sim_* 計數器嚟(見 Battle.gd),冇一個係關卡資料。
##   * 佢絕對唔會讀 GameData.WALLS、唔會叫 is_wall()、唔知邊關係牆、亦都唔知牆加咗
##     乜家族入去。可以查答案嘅量度冇價值。
##   * 佢會輸。如果佢想要嘅剋制塔未解鎖又買唔起,佢就係買唔到 —— 嗰個先係我哋想
##     要嘅信號。
const AD_TAGS := ["air", "crowd", "heal", "armor", "mres"]

## 一場之後,舊嘅壓力衰減幾多。唔係記憶好唔好嘅問題:玩家換完陣容過咗關之後,再
## 過幾關嗰個壓力就唔再係佢決策嘅主軸。
const AD_DECAY := 0.55
## 診斷門檻。全部係「打完一場會察覺到」嘅量級,唔係精準值。
const AD_DEEP_AIR := 3          # 幾多隻飛行怪行到門口 = 對空唔夠
const AD_CROWD_ALIVE := 26      # 同場最多幾多隻
const AD_SPLIT := 8             # 分裂出嚟嘅屍體數
const AD_REVIVE := 5            # 殺完企返起身嘅次數
const AD_HEAL_FRAC := 0.10      # 敵人回復量 / 我造成嘅傷害
const AD_ABSORB := 0.32         # 被吸收咗嘅傷害比例

## 邊種機制答邊種壓力。key 係塔嘅 `mech`,值係乘落每金傷害估值嘅倍率。
## 呢張表係設計判斷,唔係量度出嚟嘅 —— 佢代表「一個諗過嘅玩家會點反應」。
const AD_COUNTER := {
	# 飛行:荊棘塔淨係打地面(monsters_in_radius(..., false)),兵營嘅士兵亦都只
	# 攔得住地面(Soldier 用 nearest_ground_monster_near)。所以「對空」喺呢隻遊戲
	# 唔係解鎖一座防空塔,而係唔好將塔位同魔晶倒落兩座打唔到天上嘅嘢度。
	"air": {"thorn": 0.15, "barracks": 0.25, "arrow": 1.30, "gatling": 1.30,
		"sniper": 1.25, "frost": 1.30, "lightning": 1.20, "boomerang": 1.20,
		"beam": 1.20, "slowfield": 1.20},
	# 屍體太多 / 殺唔死實:要範圍。單體大傷嘅塔(狙擊 / 導彈)喺呢個情境最差。
	"crowd": {"cannon": 1.60, "mortar": 1.55, "fireball": 1.50, "lightning": 1.50,
		"poison": 1.30, "slowfield": 1.30, "thorn": 1.20, "sniper": 0.70,
		"missile": 0.70, "beam": 0.80},
	# 佢哋一路回血:要燒 / 毒呢啲持續傷害,同埋快到可以喺回血之前殺死治療者。
	"heal": {"fireball": 1.40, "poison": 1.40, "lightning": 1.30, "beam": 1.30,
		"gatling": 1.20, "curse": 1.30, "barracks": 0.60, "alchemy": 0.70},
	# 打落去似冇入面,而且係物理被食:轉魔法 / 真傷,或者買穿甲。
	"armor": {"lightning": 1.50, "fireball": 1.50, "beam": 1.50, "holy": 1.40,
		"poison": 1.50, "thorn": 1.40, "arrow": 0.70, "sniper": 0.70,
		"gatling": 0.70, "boomerang": 0.80, "cannon": 1.10},
	# 魔法被食:轉返物理 / 真傷。
	"mres": {"arrow": 1.40, "cannon": 1.40, "sniper": 1.40, "gatling": 1.40,
		"mortar": 1.30, "missile": 1.30, "boomerang": 1.30, "poison": 1.40,
		"thorn": 1.40, "lightning": 0.60, "fireball": 0.60, "beam": 0.60,
		"holy": 0.60},
}

## 除咗 CORE_DIRS 之外,呢個壓力之下仲值得升邊啲方向。
const AD_DIRS := {
	"air": [],
	"crowd": ["splash", "chain", "frag", "pburst", "pmax"],
	"heal": ["burn", "burndur", "pstack", "execute"],
	"armor": ["armorpen", "meltarmor", "pstack", "bleed"],
	"mres": ["pstack", "pmax", "bleed"],
}

## 要幾強嘅剋制,先值得專登為佢解鎖一座新塔。
const AD_UNLOCK_BIAS := 1.15
## 壓力細過呢個就當佢已經淡咗,唔再影響升級方向。
const AD_LIVE := 0.25

## tag -> 強度 0..1
var _ad_p: Dictionary = {}

func _ad_reset() -> void:
	_ad_p = {}

## 打完一場:舊壓力衰減,贏咗就算數,輸咗就診斷返點解。回傳今次讀到嘅 tag。
func _ad_observe(r: Dictionary, won: bool) -> Array:
	for k in _ad_p.keys():
		_ad_p[k] = float(_ad_p[k]) * AD_DECAY
	if won:
		return []
	var tags: Array = _ad_diagnose(r.sig)
	for t in tags:
		_ad_p[t] = 1.0
	return tags

## 點解會輸。全部由 Battle 嘅 sim_* 嚟,全部係打完一場察覺得到嘅嘢。
func _ad_diagnose(sig: Dictionary) -> Array:
	var tags: Array = []
	# 「有嘢衝到我門口,而且係飛嘅」
	if int(sig.deep_flying) >= AD_DEEP_AIR or bool(sig.leak_flying):
		tags.append("air")
	# 「我殺咗佢佢又企返起身」/「一隻變幾隻」/「成場太多屍體」
	if int(sig.peak_alive) >= AD_CROWD_ALIVE or int(sig.splits) >= AD_SPLIT \
			or int(sig.revives) >= AD_REVIVE:
		tags.append("crowd")
	# 「佢哋條血一路上返」
	if float(sig.heal) >= AD_HEAL_FRAC * maxf(1.0, float(sig.dmg)):
		tags.append("heal")
	# 「我啲彈打落去似冇入面」—— 再分係甲food定係魔抗食。冇用過某一種傷害類型嘅
	# 玩家自然讀唔到嗰邊被食幾多,而佢嘅結論(「試下另一種」)一樣啱。
	var rp: float = float(sig.raw_phys)
	var rm: float = float(sig.raw_magic)
	var fp: float = (1.0 - float(sig.out_phys) / rp) if rp > 0.0 else -1.0
	var fm: float = (1.0 - float(sig.out_magic) / rm) if rm > 0.0 else -1.0
	if fp >= AD_ABSORB and fp >= fm:
		tags.append("armor")
	if fm >= AD_ABSORB and fm > fp:
		tags.append("mres")
	return tags

## 依家嘅壓力之下,呢個機制值幾多倍。
func _ad_bias(mech: String) -> float:
	var mult := 1.0
	for tag in _ad_p:
		var w: float = clampf(float(_ad_p[tag]), 0.0, 1.0)
		if w <= 0.02:
			continue
		var tbl: Dictionary = AD_COUNTER[tag]
		mult *= lerpf(1.0, float(tbl.get(mech, 1.0)), w)
	return mult

## 同貪心玩家一樣嘅結構(支援塔佔三分一場),但每金傷害估值乘咗剋制倍率。
## 呢個就係「換陣容」實際發生嘅位:同一筆金,依家會流去另一種塔。
func _ad_next_buy(b) -> int:
	var want_support: bool = float(_support_count(b)) < float(maxi(1, b.towers.size())) * SUPPORT_SHARE
	var best := _ad_pick(b, want_support)
	if best == 0:
		best = _ad_pick(b, not want_support)
	return best

func _ad_pick(b, support: bool) -> int:
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
		v *= _ad_bias(String(def.mech))
		if v > best_v:
			best_v = v
			best = int(id)
	return best

## 場與場之間嘅購物。同貪心玩家嘅分別得兩處:先買剋制塔嘅解鎖(買唔起就係買唔起,
## 唔會退而求其次亂咁解鎖),同埋升級方向會跟壓力走。
func _ad_spend_crystals() -> Dictionary:
	var out := {"unlock": 0, "upgrade": 0}
	var guard := 0
	while guard < 400:
		guard += 1
		var before: int = Meta.crystals
		if _ad_buy_counter_unlock():
			out.unlock += before - Meta.crystals
			continue
		if Meta.unlocked_towers.size() < UNLOCK_TARGET and _buy_best_unlock():
			out.unlock += before - Meta.crystals
			continue
		if _ad_buy_upgrade():
			out.upgrade += before - Meta.crystals
			continue
		return out
	return out

## 解鎖一座真係答到依家嗰個壓力嘅塔。買唔起就回 false —— 呢個係設計上要保留嘅失敗
## 途徑,唔係一個要補嘅窿:一個未儲夠錢買答案嘅玩家,就係應該過唔到。
##
## 兩道閘,兩個都係為咗令佢似返一個人:
##   * 壓力要係啱啱先診斷到(未衰減過)。翻兩關前嘅舊帳去買新塔,係一個人唔會做
##     嘅嘢,而且會令佢永遠喺度買散貨。
##   * 手上已經有一座答到嘅塔就唔買。人係喺已有嘅答案上面加碼,唔係每次撞板都
##     再開一條新線。
## 呢兩道閘係量度之後加嘅:冇佢哋嗰陣,自適應玩家喺第 7/13 關**衰過**貪心玩家
## (0% vs 33%),因為佢將魔晶洗晒喺解鎖同埋每次都換一批塔嚟升,結果一座都唔夠深。
func _ad_buy_counter_unlock() -> bool:
	var fresh := 0.0
	for tag in _ad_p:
		fresh = maxf(fresh, float(_ad_p[tag]))
	if fresh < 0.9:
		return false
	for t in GameData.TOWERS:
		if not Meta.is_tower_unlocked(t.id):
			continue
		if _ad_bias(String(t.mech)) >= AD_UNLOCK_BIAS:
			return false          # 已經有答案,應該加碼唔係再買
	var best := 0
	var best_v := AD_UNLOCK_BIAS
	for t in GameData.TOWERS:
		if Meta.is_tower_unlocked(t.id) or int(t.unlock) <= 0:
			continue
		var v: float = _ad_bias(String(t.mech))
		if v > best_v:
			best_v = v
			best = int(t.id)
	if best == 0:
		return false
	if not Meta.can_afford(int(GameData.tower_by_id(best).unlock)):
		return false
	return Meta.unlock_tower(best)

## 依家值得深耕嘅塔 = 本來嘅主力 + 一座答到依家壓力嘅塔。
##
## 第一版係將成個核心名單按「每金輸出 x 剋制倍率」重排,結果係災難:壓力每場都
## 變,個名單跟住變,而 _ad_buy_upgrade 永遠買最平嗰級,所以佢不停由零開始升一批
## 新塔,一座都唔夠深 —— 量到自適應玩家喺第 7/13 關輸到 0%,而貪心玩家有 33%。
##
## 一個人唔會咁做。佢會**保住**自己嘅主力,喺隔籬**加**一個答案。所以核心 =
## 頭 (CORE_COUNT-1) 座純粹睇每金輸出嘅主力(同貪心玩家一模一樣嘅排法),
## 加最多一座剋制塔。
func _ad_core_towers() -> Array:
	var ranked: Array = Meta.unlocked_towers.duplicate()
	ranked.sort_custom(func(a, c):
		return _out_per_gold(int(a)) > _out_per_gold(int(c)))
	var core: Array = ranked.slice(0, mini(CORE_COUNT - 1, ranked.size()))
	# 加一座剋制塔(如果佢仲未喺名單入面)
	var best := 0
	var best_v := AD_UNLOCK_BIAS
	for id in Meta.unlocked_towers:
		if int(id) in core:
			continue
		var v: float = _ad_bias(String(GameData.tower_by_id(int(id)).mech))
		if v > best_v:
			best_v = v
			best = int(id)
	if best != 0:
		core.append(best)
	elif ranked.size() > core.size():
		core.append(int(ranked[core.size()]))   # 冇剋制塔就照補返第三座主力
	return core

func _ad_dirs() -> Array:
	var dirs: Array = CORE_DIRS.duplicate()
	for tag in _ad_p:
		if float(_ad_p[tag]) < AD_LIVE:
			continue
		for d in AD_DIRS[tag]:
			if not (String(d) in dirs):
				dirs.append(String(d))
	return dirs

func _ad_buy_upgrade() -> bool:
	var dirs: Array = _ad_dirs()
	var best_id := 0
	var best_dir := -1
	var best_cost := 1 << 30
	for id in _ad_core_towers():
		var def := GameData.tower_by_id(id)
		var levels: Array = Meta.tower_levels(int(id))
		for d in def.ups.size():
			if not (String(def.ups[d].stat) in dirs):
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
