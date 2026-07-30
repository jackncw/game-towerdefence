extends Node
## Regression suite for the 總檢輪 stage-1 bug fixes. Every case here reproduces
## a defect that was live in the shipped build; each one FAILS on the old code.
## Runs headless with the tree paused so nothing is frame-rate dependent —
## systems are stepped by calling their real _process / handlers directly.
##
## Run: godot --headless --path . res://test/RegressionTest.tscn
##
## Restores the real save.json afterwards (several cases write to it).

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(60.0).timeout.connect(func():
		print("REG: TIMEOUT"); get_tree().quit(1))
	_backup_save()
	get_tree().paused = true
	await _run_all()
	get_tree().paused = false
	_restore_save()
	print("REG %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _run_all() -> void:
	await _case_dot_kill_at_gate()
	await _case_invuln_blocks_dot()
	await _case_sell_barracks_kills_all_soldiers()
	await _case_clear_field_disarms_ordnance()
	await _case_barrier_reflect()
	await _case_curse_aura()
	await _case_curse_no_amp_stack()
	await _case_curse_gold_payout()
	await _case_gatling_spread()
	await _case_slime_split_backoff()
	_case_purchase_is_atomic()
	_case_legacy_save_pads_levels()
	_case_corrupt_save_falls_back()
	_case_audio_settings_applied()
	_case_upgrade_stat_formatting()
	_case_curse_rework_migration()

# ---------------------------------------------------------------------------
# 1. A poison/burn tick that kills a monster on the LAST step of the path used to
#    let the rest of Monster._process run on the corpse: it walked past
#    route.total, called on_reach_base() and lost the level.
func _case_dot_kill_at_gate() -> void:
	var b = await _start(1)
	b.base_shield = 0
	var m: Monster = b._spawn_monster("goblin", 1, false, b.route.total - 1.0)
	m.hp = 5.0
	m.poison_dmg = 500.0
	m.poison_stacks = 5
	m.poison_time = 5.0
	m.poison_tick = 0.5          # next _tick_status crosses the 0.5s tick line
	m._process(0.4)
	_check(not m.alive, "gate DoT actually killed the monster")
	_check(not b.ended, "DoT kill on the last step does NOT lose the level")
	_check(not b.monsters.has(m), "dead monster removed from the live list")
	await _end(b)

# 2. 無敵 (golem boss 石化) has to stop damage-over-time too; take_hit already
#    returned early on invuln while _deal_dot went straight through.
func _case_invuln_blocks_dot() -> void:
	var b = await _start(4)
	var m: Monster = b._spawn_monster("golem", 3, false, 100.0)
	var hp0: float = m.hp
	m.invuln_time = 2.0
	m.burn_dps = 400.0
	m.burn_time = 4.0
	m.burn_tick = 0.25
	m._process(0.3)
	_check(is_equal_approx(m.hp, hp0), "invulnerable monster takes no burn damage (hp %.0f)" % m.hp)
	m.invuln_time = 0.0
	m.burn_tick = 0.25
	m._process(0.3)
	_check(m.hp < hp0, "burn resumes once invuln expires (hp %.0f)" % m.hp)
	await _end(b)

# 3. sell_tower() iterated t.soldiers while Soldier._die() erased from it, so
#    every second soldier survived the sale and kept blocking the road for free.
func _case_sell_barracks_kills_all_soldiers() -> void:
	var b = await _start(1)
	b.gold = 5000
	var spot: Vector2 = _free_spot(b)
	_check(b.place_tower(13, spot), "barracks placed for the sell test")
	var t = b.towers[-1]
	for i in 4:
		t._spawn_soldier()
	var made: Array = t.soldiers.duplicate()
	_check(made.size() == 4, "4 soldiers deployed (got %d)" % made.size())
	b.sell_tower(t)
	var still_alive := 0
	for sd in made:
		if is_instance_valid(sd) and sd.alive:
			still_alive += 1
	_check(still_alive == 0, "selling the barracks kills EVERY soldier (%d left)" % still_alive)
	await _end(b)

# 4. On victory the field was released to the pool without clearing `alive`, so a
#    shot still in the air landed afterwards, paid gold, bumped the kill counter
#    and pushed the same monster into the free list a second time.
func _case_clear_field_disarms_ordnance() -> void:
	var b = await _start(1)
	var m: Monster = b._spawn_monster("goblin", 1, false, 200.0)
	b.spawn_projectile(Vector2(200, 200), m, m.global_position, 900, true,
		Color.WHITE, 5, {"type": "phys", "dmg": 9999.0}, false)
	var proj: Projectile = b.proj_root.get_child(0)
	b.ended = true
	b._clear_field()
	_check(not m.alive, "cleared monsters are flagged dead, not just pooled")
	_check(proj.live_target() == null, "in-flight shot loses its (recycled) target")
	var gold0: int = b.gold
	var kills0: int = b.kills
	proj.alive = true            # force the landing the old code allowed
	proj._hit()
	_check(b.gold == gold0 and b.kills == kills0,
		"a post-result impact pays nothing (gold %d->%d kills %d->%d)"
		% [gold0, b.gold, kills0, b.kills])
	await _end(b)

# 5. 守護結界「結界反傷」wrote Battle.barrier_reflect and nothing ever read it —
#    the whole upgrade direction was a paid no-op.
func _case_barrier_reflect() -> void:
	var b = await _start(1)
	b.base_shield = 2
	b.barrier_reflect = 40.0
	var blocked: Monster = b._spawn_monster("treant", 5, false, b.route.total - 30.0)
	var near: Monster = b._spawn_monster("treant", 5, false, b.route.total - 60.0)
	near.position = b.base_pos + Vector2(30, 0)
	var hp_near0: float = near.hp
	b.on_reach_base(blocked)
	_check(b.base_shield == 1, "shield consumed one charge (%d)" % b.base_shield)
	_check(near.hp < hp_near0, "結界反傷 damages what is standing at the gate (%.0f -> %.0f)"
		% [hp_near0, near.hp])
	# and with the upgrade unbought nothing happens
	b.barrier_reflect = 0.0
	var hp1: float = near.hp
	b.on_reach_base(b._spawn_monster("treant", 5, false, b.route.total - 30.0))
	_check(is_equal_approx(near.hp, hp1), "no reflect damage without the upgrade")
	await _end(b)

# 6. 詛咒塔 REWORK: the tower is now a standing aura, not a per-target shot.
#    Amplification takes the MAX across overlapping towers (stacking it would let
#    a wall of them multiply the whole board), the gold bonus stacks with
#    diminishing returns, and the curse LINGERS after leaving the circle.
func _case_curse_aura() -> void:
	var b = await _start(1)
	b.gold = 9000
	var spot: Vector2 = _free_spot(b)
	_check(b.place_tower(17, spot), "詛咒塔 placed")
	var t = b.towers[-1]
	_check(b.curse_towers.size() == 1, "tower registered as a curse aura source")
	var inside: Monster = b._spawn_monster("goblin", 1, false, 100.0)
	inside.position = spot + Vector2(t.range_val * 0.5, 0)
	var outside: Monster = b._spawn_monster("goblin", 1, false, 120.0)
	outside.position = spot + Vector2(t.range_val * 2.0, 0)
	b._tick_curse_auras()
	_check(is_equal_approx(inside.curse_amp, float(t.s.curse)),
		"圈內敵人食到詛咒 (amp %.2f)" % inside.curse_amp)
	_check(outside.curse_amp == 0.0, "圈外敵人冇食到")
	_check(inside.curse_gold > 0.0, "掉金加成掛咗上去 (%.2f)" % inside.curse_gold)
	# the amplification really lands on damage taken
	var plain: Monster = b._spawn_monster("goblin", 1, false, 140.0)
	plain.position = spot + Vector2(t.range_val * 2.0, 40)
	var hp_a: float = inside.hp
	var hp_b: float = plain.hp
	inside.take_hit(20.0, "true")
	plain.take_hit(20.0, "true")
	var dmg_cursed: float = hp_a - inside.hp
	var dmg_plain: float = hp_b - plain.hp
	_check(dmg_cursed > dmg_plain * 1.4,
		"受詛咒者食多咗傷害 (%.1f vs %.1f)" % [dmg_cursed, dmg_plain])
	# linger: the curse survives walking out of the circle
	outside.position = spot + Vector2(t.range_val * 0.5, 0)
	b._tick_curse_auras()
	outside.position = spot + Vector2(t.range_val * 3.0, 0)
	b._tick_curse_auras()
	_check(outside.curse_amp > 0.0, "行出光環之後詛咒仍然殘留")
	# boss takes a reduced share (bosseff)
	var boss: Monster = b._spawn_monster("goblin", 5, true, 160.0)
	boss.position = spot
	b._tick_curse_auras()
	_check(boss.curse_amp < inside.curse_amp and boss.curse_amp > 0.0,
		"boss 食到但打折 (%.2f vs %.2f)" % [boss.curse_amp, inside.curse_amp])
	await _end(b)

# 6b. Two overlapping 詛咒塔: amplification must NOT double up, gold must stack
#     but with diminishing returns (second source contributes half).
func _case_curse_no_amp_stack() -> void:
	var b = await _start(1)
	b.gold = 9000
	var spots := _free_spots(b, 2)
	_check(spots.size() == 2, "two placement spots found")
	b.place_tower(17, spots[0])
	b.place_tower(17, spots[1])
	_check(b.curse_towers.size() == 2, "兩座詛咒塔")
	var t0 = b.curse_towers[0]
	var t1 = b.curse_towers[1]
	var mid: Vector2 = (t0.global_position + t1.global_position) * 0.5
	var m: Monster = b._spawn_monster("goblin", 1, false, 100.0)
	m.position = mid
	var in_both: bool = mid.distance_to(t0.global_position) <= t0.range_val 		and mid.distance_to(t1.global_position) <= t1.range_val
	_check(in_both, "測試點真係喺兩個光環重疊區")
	b._tick_curse_auras()
	var one: float = float(t0.s.curse)
	_check(is_equal_approx(m.curse_amp, one),
		"重疊唔會疊加放大 (%.2f, 單座 = %.2f)" % [m.curse_amp, one])
	var g1: float = float(t0.s.goldbonus)
	_check(m.curse_gold > g1 and m.curse_gold < g1 * 2.0,
		"掉金遞減疊加 (%.3f, 單座 %.3f, 兩座唔會 %.3f)" % [m.curse_gold, g1, g1 * 2.0])
	_check(is_equal_approx(m.curse_gold, g1 * 1.5),
		"第二座只計一半 (%.3f = %.3f)" % [m.curse_gold, g1 * 1.5])
	await _end(b)

# 6c. 掉金加成 actually reaches the wallet.
func _case_curse_gold_payout() -> void:
	var b = await _start(1)
	var m: Monster = b._spawn_monster("goblin", 3, false, 100.0)
	var base_gold: int = m.gold
	var g0: int = b.gold
	m.take_hit(999999.0, "true")
	var plain_pay: int = b.gold - g0
	var m2: Monster = b._spawn_monster("goblin", 3, false, 100.0)
	m2.apply_curse_aura(0.5, 0.5, 5.0)
	var g1: int = b.gold
	m2.take_hit(999999.0, "true")
	var cursed_pay: int = b.gold - g1
	_check(cursed_pay > plain_pay,
		"受詛咒死亡多掉金 (%d vs %d, 基礎 %d)" % [cursed_pay, plain_pay, base_gold])
	await _end(b)

# 7. 機槍塔「散射」picked others[0], which was usually the primary target itself,
#    so the upgrade often just double-tapped the same monster.
func _case_gatling_spread() -> void:
	var b = await _start(1)
	b.gold = 5000
	var spot: Vector2 = _free_spot(b)
	b.place_tower(8, spot)
	var t = b.towers[-1]
	t.s.spread = 1.0             # force the roll
	var main: Monster = b._spawn_monster("treant", 5, false, 300.0)
	main.position = spot + Vector2(60, 0)
	var side: Monster = b._spawn_monster("treant", 5, false, 320.0)
	side.position = main.global_position + Vector2(35, 0)
	var side_hp0: float = side.hp
	t._fire_gatling(main)
	_check(side.hp < side_hp0, "散射 hits a DIFFERENT monster (%.0f -> %.0f)"
		% [side_hp0, side.hp])
	await _end(b)

# 8. A slime killed on the last step spawned its children at route.total - 10,
#    i.e. inside the gate where nothing could shoot them: a guaranteed leak.
func _case_slime_split_backoff() -> void:
	var b = await _start(10)
	b.spawn_split("slime", 2, 4, b.route.total)
	var worst := 0.0
	for m in b.monsters:
		worst = maxf(worst, m.dist)
	var margin: float = b.route.total - worst
	_check(margin >= Battle.SPLIT_BACK - 26.0,
		"split children keep road left to be killed on (margin %.0f px)" % margin)
	await _end(b)

# ---------------------------------------------------------------------------
# 9. Purchases were TWO save writes (deduct, then deliver). Quitting between them
#    billed the player and delivered nothing. One write now covers both.
func _case_purchase_is_atomic() -> void:
	Meta.reset_save()
	Meta.crystals = 10_000
	var before: int = Meta.tower_levels(1)[0]
	_check(Meta.buy_tower_upgrade(1, 0), "upgrade purchased")
	var d: Dictionary = _read_save()
	_check(int(d.get("crystals", -1)) == Meta.crystals,
		"saved crystals match memory (%s vs %d)" % [d.get("crystals"), Meta.crystals])
	var lv: int = int((d.get("tower_up", {}).get("1", [0]))[0])
	_check(lv == before + 1, "the SAME save write carries the new level (%d)" % lv)
	# an unaffordable purchase must not touch the wallet
	Meta.crystals = 1
	var c0: int = Meta.crystals
	_check(not Meta.buy_tower_upgrade(1, 1), "unaffordable upgrade refused")
	_check(Meta.crystals == c0, "refused purchase costs nothing (%d)" % Meta.crystals)
	_check(not Meta.unlock_tower(7), "unaffordable unlock refused")
	_check(Meta.crystals == c0 and not Meta.is_tower_unlocked(7), "refused unlock costs nothing")

# 10. A save written before a tower gained upgrade directions held a SHORT level
#     array: Upgrade._up_row crashed on levels[dir] and the new directions could
#     never be bought.
func _case_legacy_save_pads_levels() -> void:
	_write_save({
		"crystals": 5000,
		"unlocked_towers": [1, 2, 5, 13],
		"unlocked_spells": [1],
		"tower_up": {"1": [4, 2]},          # only 2 of the 6 directions
		"spell_up": {"1": [1]},             # only 1 of the 3
		"highest_level": 3,
	})
	Meta.load_game()
	var lv: Array = Meta.tower_levels(1)
	_check(lv.size() == GameData.tower_by_id(1).ups.size(),
		"short tower array padded to %d (got %d)" % [GameData.tower_by_id(1).ups.size(), lv.size()])
	_check(lv[0] == 4 and lv[1] == 2, "existing levels preserved (%d,%d)" % [lv[0], lv[1]])
	_check(int(lv[5]) == 0, "new direction defaults to 0")
	_check(Meta.spell_levels(1).size() == GameData.spell_by_id(1).ups.size(),
		"short spell array padded")
	_check(Meta.buy_tower_upgrade(1, 5), "the newly padded direction is buyable")
	_check(Meta.tower_up_cost(1, 5) > 0, "and prices correctly")

# 11. load_game() trusted the file's types: a corrupt or hand-edited save could
#     leave the player with zero towers (and crash the upgrade screen on [0]).
func _case_corrupt_save_falls_back() -> void:
	_write_save({
		"crystals": "not-a-number",
		"unlocked_towers": "oops",
		"unlocked_spells": [],
		"tower_up": {"1": 7},
		"cleared": null,
		"settings": 5,
		"seen": [1, 2, 3],
		"highest_level": -9,
	})
	Meta.load_game()
	_check(Meta.unlocked_towers == [1, 2, 5, 13],
		"garbage unlock list falls back to the starting towers (%s)" % [Meta.unlocked_towers])
	_check(Meta.unlocked_spells == [1], "empty spell list falls back to the starting spell")
	_check(Meta.crystals == 0, "non-numeric crystals become 0 (%d)" % Meta.crystals)
	_check(Meta.highest_level == 0, "negative level clamped (%d)" % Meta.highest_level)
	_check(typeof(Meta.cleared) == TYPE_DICTIONARY, "null cleared becomes an empty dict")
	_check(typeof(Meta.seen) == TYPE_DICTIONARY, "array seen becomes an empty dict")
	_check(Meta.settings.has("volume") and Meta.settings.has("muted"),
		"settings always carry volume + muted")
	_check(Meta.tower_levels(1).size() == 6, "non-array level entry rebuilt")

# 12. The saved 靜音 / 音量 were only ever applied when re-toggled in 設定 — a
#     muted player heard sound again on every restart.
func _case_audio_settings_applied() -> void:
	Meta.settings = {"volume": 0.25, "muted": true}
	Meta.apply_audio_settings()
	_check(AudioServer.is_bus_mute(0), "saved mute is applied to the bus")
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.25)) < 0.01,
		"saved volume is applied to the bus")
	Meta.settings = {"volume": 0.8, "muted": false}
	Meta.apply_audio_settings()
	_check(not AudioServer.is_bus_mute(0), "unmute is applied too")

# 13. The upgrade screen formatted by stat NAME only, but the same name means
#     different things on different towers:
#       knock = 擊退機率 on 加農砲台 (a probability) vs 擊退距離 on 磁力塔 (pixels)
#       stun  = 麻痺機率 on 雷電塔 (a probability) vs 傳送後暈眩 on 傳送塔 (seconds)
#     磁力塔's 40px knockback used to render as "4000%".
func _case_upgrade_stat_formatting() -> void:
	var u = load("res://scripts/ui/Upgrade.gd").new()
	u.sel_type = "tower"
	u._refresh_kind_map(GameData.tower_by_id(19))          # 磁力塔
	_check(u._fmt(40.0, "knock") == "40", "磁力塔 擊退距離 renders as px (%s)" % u._fmt(40.0, "knock"))
	_check(u._stat_icon("knock") == "ic_scope", "…with a distance icon")
	u._refresh_kind_map(GameData.tower_by_id(2))           # 加農砲台
	_check(u._fmt(0.05, "knock") == "5%", "加農砲台 擊退機率 renders as %% (%s)" % u._fmt(0.05, "knock"))
	u._refresh_kind_map(GameData.tower_by_id(20))          # 傳送塔
	_check(not u._fmt(0.15, "stun").ends_with("%"),
		"傳送塔 暈眩 renders as seconds, not a percentage (%s)" % u._fmt(0.15, "stun"))
	u._refresh_kind_map(GameData.tower_by_id(3))           # 雷電塔
	_check(u._fmt(0.04, "stun") == "4%", "雷電塔 麻痺機率 renders as %% (%s)" % u._fmt(0.04, "stun"))
	u._refresh_kind_map(GameData.tower_by_id(16))          # 導彈塔
	_check(u._fmt(0.5, "bossmult") == "50%", "對boss增傷 renders as %% (%s)" % u._fmt(0.5, "bossmult"))
	# fractional stats whose per-level step is under _fmt's 0.05 rounding
	# threshold used to render as a bare "0", i.e. "0 → 0" on the upgrade row
	u._refresh_kind_map(GameData.tower_by_id(19))          # 磁力塔 擊退後減速
	_check(u._fmt(0.03, "knockslow") == "3%",
		"擊退後減速 lv1 is visible, not \"0\" (%s)" % u._fmt(0.03, "knockslow"))
	u._refresh_kind_map(GameData.tower_by_id(7))           # 狙擊塔 處決線
	_check(u._fmt(0.012, "execute") == "1%",
		"處決線 lv1 is visible, not \"0\" (%s)" % u._fmt(0.012, "execute"))
	u.free()

# 14. 詛咒塔 REWORK save migration. Four of the tower's six upgrade axes no
#     longer exist, so an existing save may have 魔晶 sunk into directions that
#     were deleted. The migration refunds every crystal spent on the tower, wipes
#     it back to level 0 on the new axes, and runs exactly once.
func _case_curse_rework_migration() -> void:
	# a save from the PREVIOUS build: no "version" key, 詛咒塔 levelled on the old
	# axes (詛咒幅度 4 / 施咒頻率 3 / 射程 2 / 詛咒持續 5 / 附帶減速 1 / 死亡詛咒擴散 2)
	var old_levels := [4, 3, 2, 5, 1, 2]
	_write_save({
		"crystals": 100,
		"unlocked_towers": [1, 2, 5, 13, 17],
		"unlocked_spells": [1],
		"tower_up": {"17": old_levels, "1": [3, 0, 0, 0, 0, 0]},
		"highest_level": 6,
	})
	# what the old build charged for those levels
	var expect := 0
	for i in old_levels.size():
		for k in int(old_levels[i]):
			expect += GameData.upgrade_cost(Meta.CURSE_OLD_BASE_COSTS[i], k)
	Meta.rework_refund = 0
	Meta.load_game()
	Meta._migrate()
	_check(Meta.rework_refund == expect,
		"退還金額 = 舊軸實際課金 (%d, 期望 %d)" % [Meta.rework_refund, expect])
	_check(Meta.crystals == 100 + expect,
		"魔晶餘額加返 (100 -> %d)" % Meta.crystals)
	var lv: Array = Meta.tower_levels(17)
	_check(lv.size() == GameData.tower_by_id(17).ups.size(), "新軸數量正確 (%d)" % lv.size())
	var all_zero := true
	for v in lv:
		if int(v) != 0:
			all_zero = false
	_check(all_zero, "新軸全部由 0 開始 (%s)" % [lv])
	_check(Meta.tower_levels(1)[0] == 3, "其他塔嘅升級唔受影響 (箭塔 lv%d)" % Meta.tower_levels(1)[0])
	_check(Meta.save_version == Meta.SAVE_VERSION, "存檔版本已推進")
	# and it must not run twice
	var c_after: int = Meta.crystals
	Meta.rework_refund = 0
	Meta._migrate()
	_check(Meta.crystals == c_after and Meta.rework_refund == 0, "遷移唔會重複執行")
	# a save written by the NEW build carries a version and is left alone
	_write_save({"crystals": 42, "tower_up": {"17": [2, 0, 0, 0, 0, 0]},
		"unlocked_towers": [1], "unlocked_spells": [1], "version": Meta.SAVE_VERSION})
	Meta.rework_refund = 0
	Meta.load_game()
	Meta._migrate()
	_check(Meta.crystals == 42 and Meta.rework_refund == 0, "新版存檔唔會被再遷移")
	_check(Meta.tower_levels(17)[0] == 2, "新版存檔嘅詛咒塔升級保留")

# ---------------------------------------------------------------------------
# helpers
func _start(level: int):
	Flow.selected_level = level
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE   # children inherit ALWAYS from us
	add_child(b)
	await get_tree().process_frame
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true   # Battle._exit_tree unpauses; re-pause for the next run

## Two spots close enough that their 詛咒塔 auras overlap (needed by the
## no-double-stacking case).
func _free_spots(b, n: int) -> Array:
	var out: Array = []
	for gx in range(3, 13):
		for gy in range(5, 18):
			var p: Vector2 = b.snap(Vector2(gx * 74, gy * 74))
			if not b.can_place(p):
				continue
			# far enough apart to actually place (TOWER_SPACING = 78) but close
			# enough that the two 200-radius auras overlap
			var d: float = 0.0 if out.is_empty() else p.distance_to(out[0])
			if out.is_empty() or (d > 90.0 and d < 190.0):
				out.append(p)
			if out.size() >= n:
				return out
	return out

func _free_spot(b) -> Vector2:
	for gx in range(3, 13):
		for gy in range(5, 18):
			var p: Vector2 = b.snap(Vector2(gx * 74, gy * 74))
			if b.can_place(p):
				return p
	return Vector2(234, 520)

func _read_save() -> Dictionary:
	var txt := FileAccess.get_file_as_string(Meta.SAVE_PATH)
	var d = JSON.parse_string(txt)
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _write_save(d: Dictionary) -> void:
	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print("REG %s: %s" % ["ok" if ok else "FAIL", label])

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
