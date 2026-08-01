extends Node
## 魔晶 economy regression test + 10-level income/spend simulation (headless).
## Covers the crystal-payout rules only — it never starts a Battle.
##   1. first clear pays 通關獎勵 + 首次通關獎勵; replay pays half base, no bonus
##   2. the first-clear record survives a save/reload round trip (save.json)
##   3. a loss pays by progress, never above 40% of the clear reward, and pays
##      nothing at all inside the 10s anti-farm window
##   4. loss progress is monotone in kills / time / boss damage
##   5. clearing always beats farming losses on the same level
## Also prints the first-10-level income table vs the unlock+upgrade cost curve.
## Restores the real save.json afterwards (every award writes to it).

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_backup_save()
	Meta.reset_save()
	_test_first_clear()
	_test_persistence()
	_test_loss_payout()
	_test_monotone()
	_test_clear_beats_farming()
	_simulate()
	_restore_save()
	Meta.load_game()
	print("ECON %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

# --- tests ------------------------------------------------------------------
func _test_first_clear() -> void:
	Meta.reset_save()
	var lv := 4
	var base := GameData.level_crystal_reward(lv)
	var bonus := GameData.level_first_clear_bonus(lv)
	var a := Meta.on_level_cleared(lv)
	_check(not a.replay, "first clear is not flagged as replay")
	_check(a.base == base, "first clear base = %d (got %d)" % [base, a.base])
	_check(a.first == bonus, "first clear bonus = %d (got %d)" % [bonus, a.first])
	_check(a.total == base + bonus, "first clear total = %d (got %d)" % [base + bonus, a.total])
	_check(Meta.crystals == base + bonus, "crystals credited (%d)" % Meta.crystals)
	_check(bonus > base, "bonus %d is clearly bigger than base %d" % [bonus, base])

	var before := Meta.crystals
	var b := Meta.on_level_cleared(lv)
	_check(b.replay, "second clear flagged as replay")
	_check(b.first == 0, "replay pays no first-clear bonus (got %d)" % b.first)
	_check(b.base == int(base / 2), "replay base halved = %d (got %d)" % [int(base / 2), b.base])
	_check(Meta.crystals == before + b.total, "replay credited %d" % b.total)

	# bonus must grow with level, so pushing forward beats re-farming
	var grows := true
	for n in range(1, 30):
		if GameData.level_first_clear_bonus(n + 1) <= GameData.level_first_clear_bonus(n):
			grows = false
	_check(grows, "first-clear bonus is strictly increasing with level")

func _test_persistence() -> void:
	Meta.reset_save()
	Meta.on_level_cleared(7)
	var crystals_after := Meta.crystals
	Meta.load_game()   # re-read save.json from disk, as a fresh launch would
	_check(Meta.is_cleared(7), "first-clear record survives reload")
	_check(Meta.crystals == crystals_after, "crystal balance survives reload")
	var again := Meta.on_level_cleared(7)
	_check(again.first == 0, "replay after reload pays no first-clear bonus")

func _test_loss_payout() -> void:
	Meta.reset_save()
	var lv := 5
	var cap := GameData.level_lose_cap(lv)
	var clear := GameData.level_crystal_reward(lv)
	_check(cap == int(floor(clear * GameData.LOSE_REWARD_CAP_FRAC)),
		"loss cap = %d%% of clear (%d of %d)"
		% [int(GameData.LOSE_REWARD_CAP_FRAC * 100.0), cap, clear])
	# Round 8: the payout is pinned to the measured upgrade-cost curve, so the
	# thing worth asserting is the DESIGN PROMISE, not the arithmetic — a loss
	# with typical progress has to buy at least one upgrade level.
	for n in range(1, 21):
		var typ := GameData.level_lose_reward(n, 27, 60.0, 100.0, 0.25)
		var cn := GameData.typical_upgrade_cost(n)
		_check(typ >= cn, "lv%d: 有進度嘅敗仗 %d >= 下一級升級 %d" % [n, typ, cn])

	# 10s anti-farm window: instant surrender / instant loss pays nothing
	var quick := Meta.on_level_failed(lv, 0, 3.0, 60.0, 0.0)
	_check(quick.crystals == 0, "loss at 3s pays 0 (got %d)" % quick.crystals)
	_check(quick.too_short, "loss at 3s flagged too_short")
	var quick2 := Meta.on_level_failed(lv, 20, 9.9, 60.0, 0.5)
	_check(quick2.crystals == 0, "loss at 9.9s pays 0 even with kills (got %d)" % quick2.crystals)
	_check(Meta.crystals == 0, "no crystals credited inside the window")

	var just_out := Meta.on_level_failed(lv, 2, 10.0, 60.0, 0.0)
	_check(just_out.crystals >= 1, "loss at 10.0s pays at least 1 (got %d)" % just_out.crystals)

	# perfect-progress loss still lands on the cap, never above it
	# the reachable ceiling, which is not the same as LOSE_REWARD_CAP_FRAC * clear
	var reach := GameData.level_lose_max(lv)
	var best := Meta.on_level_failed(lv, 999, 600.0, 60.0, 1.0)
	_check(best.crystals == reach, "max-progress loss = %d (got %d)" % [reach, best.crystals])
	_check(best.cap == reach, "fail screen quotes the reachable ceiling (%d vs %d)"
		% [best.cap, reach])
	var over := false
	for n in range(1, 31):
		var c := GameData.level_lose_cap(n)
		for k in [0, 10, 45, 200]:
			for t in [10.0, 40.0, 60.0, 300.0]:
				for bf in [0.0, 0.5, 1.0, 2.0]:
					if GameData.level_lose_reward(n, k, t, 60.0, bf) > c:
						over = true
	_check(not over, "no (level, kills, time, boss%) combination exceeds the cap")

func _test_monotone() -> void:
	var lv := 8
	var a := GameData.lose_progress(5, 30.0, 60.0, 0.0)
	var b := GameData.lose_progress(25, 30.0, 60.0, 0.0)
	_check(b > a, "more kills => more progress (%.2f > %.2f)" % [b, a])
	var c := GameData.lose_progress(25, 55.0, 60.0, 0.0)
	_check(c > b, "longer survival => more progress (%.2f > %.2f)" % [c, b])
	var d := GameData.lose_progress(25, 55.0, 60.0, 0.6)
	_check(d > c, "boss damage => more progress (%.2f > %.2f)" % [d, c])
	# a boss-reaching run must out-earn an early wipe by a clear margin
	var early := GameData.level_lose_reward(lv, 8, 20.0, 60.0, 0.0)
	var deep := GameData.level_lose_reward(lv, 40, 60.0, 60.0, 0.7)
	_check(deep >= early * 2, "deep boss run out-earns early wipe (%d vs %d)" % [deep, early])

func _test_clear_beats_farming() -> void:
	# The whole point of the cap: a clear must always be worth more than a loss
	# on the same level, first clear or replay.
	# Two separate comparisons, because round 8 gave losses their own replay rule.
	# Farming is only possible on a level you have ALREADY cleared, so that is the
	# case the cap has to win: there, a max-progress loss pays LOSE_REPLAY_FRAC of
	# the cap and must still lose to simply re-clearing (which pays half).
	var bad_replay := 0
	var bad_fresh := 0
	for n in range(1, 31):
		var best_replay_loss := GameData.level_lose_reward(n, 9999, 9999.0, 60.0, 1.0, true)
		if best_replay_loss >= int(GameData.level_crystal_reward(n) / 2):
			bad_replay += 1
		# and on a NEW level, losing must lose to clearing it outright
		var best_fresh_loss := GameData.level_lose_reward(n, 9999, 9999.0, 60.0, 1.0, false)
		if best_fresh_loss >= (GameData.level_crystal_reward(n)
				+ GameData.level_first_clear_bonus(n)):
			bad_fresh += 1
	_check(bad_replay == 0, "重玩關: 最好嘅敗仗 < 減半通關獎勵")
	_check(bad_fresh == 0, "新關: 最好嘅敗仗 < 通關 + 首通")

# --- 10-level economy simulation -------------------------------------------
func _simulate() -> void:
	print("\nECON --- 頭 10 關魔晶收入模擬 ---")
	print("ECON lv | 通關 | 首通 | 首通合計 | 輸1局(50%%進度) | 輸1局(打到boss 70%%) | 失敗上限")
	var total_first := 0
	for n in range(1, 11):
		var base := GameData.level_crystal_reward(n)
		var first := GameData.level_first_clear_bonus(n)
		total_first += base + first
		var mid := GameData.level_lose_reward(n, 22, 30.0, 60.0, 0.0)
		var deep := GameData.level_lose_reward(n, 40, 60.0, 60.0, 0.7)
		print("ECON %2d | %4d | %4d | %8d | %14d | %20d | %8d"
			% [n, base, first, base + first, mid, deep, GameData.level_lose_cap(n)])
	print("ECON 全首通 1-10 關總收入 = %d 魔晶" % total_first)

	# cumulative income curves at each level checkpoint
	print("\nECON --- 累積收入 (到第 N 關為止) ---")
	print("ECON N | 全首通 | 每關輸2次再過 | 每關輸3次再過")
	var pure := 0
	var mix2 := 0
	var mix3 := 0
	for n in range(1, 11):
		var win := GameData.level_crystal_reward(n) + GameData.level_first_clear_bonus(n)
		var l1 := GameData.level_lose_reward(n, 18, 26.0, 60.0, 0.0)   # 1st try: early wipe
		var l2 := GameData.level_lose_reward(n, 34, 52.0, 60.0, 0.25)  # 2nd try: nearly at boss
		var l3 := GameData.level_lose_reward(n, 42, 60.0, 60.0, 0.55)  # 3rd try: deep into boss
		pure += win
		mix2 += win + l1 + l2
		mix3 += win + l1 + l2 + l3
		print("ECON %2d | %6d | %13d | %13d" % [n, pure, mix2, mix3])

	# the 輸 -> 升級 -> 過到 loop: what a stuck player banks per retry cycle,
	# against the cheapest key-upgrade levels on the starter arrow tower.
	print("\nECON --- 卡關循環: 連輸 N 次攞到幾多 ---")
	print("ECON lv | 輸2次(普通) | 輸3次(普通) | 輸2次(打到boss) | 輸3次(打到boss) | 最平升級1級")
	for n in range(1, 11):
		var l1 := GameData.level_lose_reward(n, 18, 26.0, 60.0, 0.0)
		var l2 := GameData.level_lose_reward(n, 34, 52.0, 60.0, 0.25)
		var l3 := GameData.level_lose_reward(n, 42, 60.0, 60.0, 0.55)
		# "serious" attempts: player reaches the boss and chips it every time
		var s1 := GameData.level_lose_reward(n, 40, 60.0, 60.0, 0.35)
		var s2 := GameData.level_lose_reward(n, 44, 75.0, 60.0, 0.6)
		var s3 := GameData.level_lose_reward(n, 48, 90.0, 60.0, 0.8)
		var cheapest := 99999
		for t2 in GameData.TOWERS:
			for d in t2.ups:
				cheapest = mini(cheapest, int(d.base_cost))
		print("ECON %2d | %11d | %11d | %15d | %15d | %11d"
			% [n, l1 + l2, l1 + l2 + l3, s1 + s2, s1 + s2 + s3, cheapest])

	# spend curve: what that has to cover
	print("\nECON --- 開支對照 ---")
	var unlocks: Array = []
	for t in GameData.TOWERS:
		if t.unlock > 0:
			unlocks.append(t.unlock)
	unlocks.sort()
	var cheapest2: int = unlocks[0] + unlocks[1]
	print("ECON 最平 2 座塔解鎖 = %d (%d + %d) -> 共 6 座塔" % [cheapest2, unlocks[0], unlocks[1]])
	print("ECON 最平 4 座塔解鎖 = %d" % (cheapest2 + unlocks[2] + unlocks[3]))
	var arrow: Dictionary = GameData.tower_by_id(1)
	for dirs in [1, 2, 3]:
		var cost := 0
		var lines: Array = []
		for i in range(dirs):
			var d: Dictionary = arrow.ups[i]
			var sub := 0
			for lv in range(3):
				sub += GameData.upgrade_cost(d.base_cost, lv)
			cost += sub
			lines.append("%s x3=%d" % [d.name, sub])
		print("ECON 箭塔 %d 條線各升到 3 級 = %d (%s)" % [dirs, cost, ", ".join(lines)])
	var five := 0
	var d0: Dictionary = arrow.ups[0]
	for lv in range(5):
		five += GameData.upgrade_cost(d0.base_cost, lv)
	print("ECON 箭塔攻擊線升到 5 級 = %d" % five)

# --- helpers ----------------------------------------------------------------
func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print("ECON %s: %s" % ["ok" if ok else "FAIL", label])

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
