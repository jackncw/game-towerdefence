extends Node
## Verify the full lose path: Battle._lose -> Meta.on_level_failed -> save,
## and that Battle tracks the deepest boss-damage fraction of the run.
## Restores the real save.json afterwards.

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false
# Battle._lose schedules a Flow.goto(FAIL) on a 0.2s timer, and that swaps the
# root scene — i.e. frees this harness — mid-run. So the tree is cached up front
# and the tree-dependent boss-tracking case runs BEFORE any _lose() call.
var _tree: SceneTree

func _ready() -> void:
	_tree = get_tree()
	_backup_save()
	Meta.reset_save()
	await _boss_frac_tracking()
	await _lose_run(6, 38, 72.0, 0.55, true)
	await _lose_run(6, 0, 4.0, 0.0, false)
	_restore_save()
	Meta.load_game()
	print("LOSETEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

func _lose_run(lv: int, kills: int, elapsed: float, boss_frac: float, expect_pay: bool) -> void:
	var before := Meta.crystals
	Flow.selected_level = lv
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await _tree.process_frame
	b.kills = kills
	b.elapsed = elapsed
	b.boss_best_frac = boss_frac
	b.boss_spawned = boss_frac > 0.0
	b._lose()
	await _tree.process_frame
	var r: Dictionary = Flow.last_result
	var paid: int = r.get("crystals", 0)
	var expected := GameData.level_lose_reward(lv, kills, elapsed, b.boss_time, boss_frac)
	_check(r.get("win") == false, "lose result flagged win=false")
	_check(paid == expected, "payout %d matches formula %d" % [paid, expected])
	_check(Meta.crystals == before + paid, "crystals credited (%d -> %d)" % [before, Meta.crystals])
	_check(paid <= GameData.level_lose_cap(lv), "payout %d within cap %d" % [paid, GameData.level_lose_cap(lv)])
	if expect_pay:
		_check(paid > 0, "real attempt pays out (%d)" % paid)
		_check(not r.get("too_short", true), "real attempt not flagged too_short")
	else:
		_check(paid == 0, "sub-10s attempt pays nothing (%d)" % paid)
		_check(r.get("too_short", false), "sub-10s attempt flagged too_short")
	_check(not Meta.is_cleared(lv), "a loss never marks the level cleared")
	b.queue_free()
	await _tree.process_frame

func _boss_frac_tracking() -> void:
	# a boss that heals back up must not erase the damage progress already earned
	Flow.selected_level = 3
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await _tree.process_frame
	b.elapsed = 61.0
	b._spawn_logic(0.001)          # boss enters
	_check(b.boss_ref != null, "boss spawned for tracking test")
	if b.boss_ref != null:
		var boss = b.boss_ref
		boss.hp = boss.max_hp * 0.3
		b._process(0.016)
		var deep: float = b.boss_best_frac
		_check(absf(deep - 0.7) < 0.02, "tracks 70%% boss damage (got %.2f)" % deep)
		boss.hp = boss.max_hp     # full heal
		b._process(0.016)
		_check(absf(b.boss_best_frac - deep) < 0.001,
			"peak damage kept after boss heals (got %.2f)" % b.boss_best_frac)
	b.queue_free()
	await _tree.process_frame

func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print("LOSETEST %s: %s" % ["ok" if ok else "FAIL", label])

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
