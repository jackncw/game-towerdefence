extends Node
## Boss-fight ambient-spawn + economy regression test (headless).
## Drives Battle._spawn_logic manually with the tree paused so no monster moves
## and no frame-rate dependence. Verifies:
##   1. spawning continues during the boss fight at the profile rate (~40% std)
##   2. per-boss profiles differ: wolf = burst-only packs, slime = near-stop,
##      bat = flying-only pool, golem = +1 lvl minions, treant = minion regen
##   3. kills during the boss fight still pay gold; towers can still be placed
##   4. alchemy towers keep generating gold during the boss fight
## Restores the real save.json afterwards (mark_seen writes to it).

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	get_tree().paused = true
	await _run_all()
	get_tree().paused = false
	_restore_save()
	print("BOSSSPAWN %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _run_all() -> void:
	# --- skeleton (lv3): standard 0.4 rate vs forced 1.0 baseline -----------
	var b = await _start(3)
	var std: int = _sim(b, 30.0).spawned
	await _end(b)
	b = await _start(3)
	b._spawn_logic(0.001)            # boss enters (loads the real profile)...
	b.boss_profile = {"rate": 1.0}   # ...then force a full-rate baseline
	b.burst_def = {}
	var base: int = _sim(b, 30.0).spawned
	await _end(b)
	var ratio := float(std) / maxf(1.0, float(base))
	_check(std > 0, "skeleton ambient continues (std=%d)" % std)
	_check(ratio > 0.3 and ratio < 0.5,
		"skeleton rate ~40%% of baseline (std=%d base=%d ratio=%.2f)" % [std, base, ratio])

	# --- wolf (lv2): no ambient, packs of 3-5 at first=5s then every 12s ----
	b = await _start(2)
	var w: Dictionary = _sim(b, 30.0)
	_check(w.bursts == 3, "wolf 3 bursts in 30s (bursts=%d)" % w.bursts)
	_check(w.singles == 1, "wolf no ambient spawns, only boss entry (singles=%d)" % w.singles)
	_check(w.spawned >= 9 and w.spawned <= 15, "wolf pack sizes 3-5 (spawned=%d)" % w.spawned)
	await _end(b)

	# --- slime (lv10): near-stop 0.10 ambient --------------------------------
	b = await _start(10)
	var s: int = _sim(b, 30.0).spawned
	_check(s >= 4 and s <= 9, "slime ambient near-stop (spawned=%d)" % s)
	await _end(b)

	# --- bat (lv6): flying-only pool + economy checks ------------------------
	b = await _start(6)
	var n: int = _sim(b, 20.0).spawned
	var all_fly := n > 0
	for m in b.monsters:
		if not m.is_boss and not m.flying:
			all_fly = false
	_check(all_fly, "bat boss spawns flying-only (n=%d)" % n)
	# kill a minion mid-boss-fight -> gold drops
	var victim = null
	for m in b.monsters:
		if not m.is_boss:
			victim = m
			break
	var g0: int = b.gold
	victim.take_hit(9999999.0, "true")
	_check(b.gold > g0, "minion kill pays gold during boss (%d -> %d)" % [g0, b.gold])
	# place an alchemy tower mid-boss-fight -> it keeps producing
	b.gold = 500
	var spot := Vector2.ZERO
	for gx in range(2, 13):
		for gy in range(4, 20):
			var p: Vector2 = b.snap(Vector2(gx * 74, gy * 74))
			if b.can_place(p):
				spot = p
				break
		if spot != Vector2.ZERO:
			break
	_check(b.place_tower(12, spot), "alchemy tower placeable during boss")
	var alch = b.towers[b.towers.size() - 1]
	var g1: int = b.gold
	alch._process(0.5)
	_check(b.gold > g1, "alchemy produces gold during boss (%d -> %d)" % [g1, b.gold])
	await _end(b)

	# --- golem (lv4): fewer but +1 level (worth more gold each) --------------
	b = await _start(4)
	_sim(b, 15.0)
	var min_lv := 99
	var cnt := 0
	for m in b.monsters:
		if not m.is_boss:
			min_lv = mini(min_lv, m.lvl)
			cnt += 1
	_check(cnt > 0 and min_lv >= 2, "golem minions +1 lvl (n=%d min_lv=%d)" % [cnt, min_lv])
	await _end(b)

	# --- treant (lv17): ambient minions get light regen ----------------------
	# 第 17 關同第 7 關嘅 boss 家族一樣係遠古樹妖((n-1) % 10 == 6),但第 7 關
	# 由第十五輪起係合約關 —— 見 _start() 上面嗰段。
	b = await _start(17)
	_sim(b, 20.0)
	var regen_ok := false
	for m in b.monsters:
		if not m.is_boss and m.mech != "regen" and m.regen_rate > 0.0:
			regen_ok = true
	_check(regen_ok, "treant boss grants minion regen")
	await _end(b)

# --- harness ----------------------------------------------------------------
## **唔好用逢 7 嘅倍數關做 harness 場景。** 第十五輪起佢哋係合約關:開場即刻
## 攤三張卡並且凍結成個場(Battle._open_contract_offer),而一個唔識答佢嘅
## harness 會坐喺度乜都唔郁 —— 症狀係「所有同時間有關嘅斷言一齊靜靜咁失敗」,
## 而唔係一個講得出原因嘅錯誤。
func _start(level: int):
	Flow.selected_level = level
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE   # test node is ALWAYS; keep battle paused
	add_child(b)
	await get_tree().process_frame
	b.elapsed = b.boss_time + 0.01   # boss enters on the first _spawn_logic tick
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true   # Battle._exit_tree unpauses; re-pause for next run

## Steps _spawn_logic with fixed dt. Returns ambient spawn count plus per-tick
## growth classification: "bursts" = ticks gaining >=2 monsters (pack rushes),
## "singles" = ticks gaining exactly 1 (ambient spawns + the boss entry).
func _sim(b, seconds: float) -> Dictionary:
	var dt := 0.05
	var start: int = b.monsters.size()
	var last: int = start
	var bursts := 0
	var singles := 0
	var t := 0.0
	while t < seconds - 0.001:
		b._spawn_logic(dt)
		b.elapsed += dt
		t += dt
		var c: int = b.monsters.size()
		if c - last >= 2:
			bursts += 1
		elif c - last == 1:
			singles += 1
		last = c
	# the boss itself is not an ambient spawn
	var boss_n := 0
	for m in b.monsters:
		if m.is_boss:
			boss_n = 1
	return {"spawned": b.monsters.size() - start - (boss_n if start == 0 else 0),
		"bursts": bursts, "singles": singles}

func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print("BOSSSPAWN %s: %s" % ["ok" if ok else "FAIL", label])

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
