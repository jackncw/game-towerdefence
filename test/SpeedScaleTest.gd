extends Node
## Regression test for the speed button, added when 0.5x joined [1,3].
##
## `Engine.time_scale` does exactly one thing: it multiplies the `delta` handed to
## `_process`. So "0.5x / 1x / 3x scale every time system correctly" is precisely
## the claim "the same amount of GAME time produces the same result no matter how
## big each frame's delta is". Anything that counts frames instead of seconds, or
## that quantises an accumulator to the frame size, breaks that equality — and
## that is the class of bug this test is here to catch.
##
## So every case runs the SAME scenario three times over the SAME total game
## time, stepping at the per-frame delta each speed tier actually produces at
## 60fps (0.5x -> 0.0083s, 1x -> 0.0167s, 3x -> 0.0500s), and compares:
##
##   A boss 倒數    — elapsed at the moment the boss spawns
##   B 刷怪間隔      — how many monsters spawned in a fixed window
##   C 魔法 CD      — remaining cooldown after a fixed wait
##   D DoT tick     — total burn damage over a fixed burn
##
## The tree is paused and every step is driven by hand, so none of this depends
## on the real frame rate of the machine running it. Backs up/restores save.json.

## Per-frame game delta at 60fps for each speed tier we ship.
const TIERS := [
	{"name": "0.5x", "dt": (1.0 / 60.0) * 0.5},
	{"name": "1x", "dt": (1.0 / 60.0) * 1.0},
	{"name": "3x", "dt": (1.0 / 60.0) * 3.0},
]
const LEVEL := 3

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	_tree.paused = true
	await _case_speed_table()
	_case_no_5x_in_code()
	await _case_boss_countdown()
	await _case_spawn_interval()
	await _case_spell_cd()
	await _case_dot()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	print("SPEEDSCALE %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------------------
# A0 — the tier list and its captions
# ---------------------------------------------------------------------------
func _case_speed_table() -> void:
	# 第十一輪拎走 5x —— 呢條 assertion 就係「拎走咗」嘅唯一證據,
	# 見 Battle.SPEEDS 上面嗰段。
	_eq_arr("A0 速度循環", Battle.SPEEDS, [0.5, 1.0, 3.0])
	_ok("A0 冇 5x", not Battle.SPEEDS.has(5.0), "SPEEDS=%s" % [Battle.SPEEDS])
	for pair in [[0.5, "x0.5"], [1.0, "x1"], [3.0, "x3"]]:
		var got: String = Battle.speed_label(float(pair[0]))
		_ok("A0 掣面 %s" % pair[1], got == pair[1], "%s != %s" % [got, pair[1]])
	# cycling from 1x must reach every tier and come back
	var b = await _start(LEVEL)
	var seen: Array = []
	var i: int = Battle.SPEEDS.find(b.game_speed)
	_ok("A0 開場 1x", is_equal_approx(b.game_speed, 1.0), "game_speed=%f" % b.game_speed)
	for _n in Battle.SPEEDS.size():
		i = (i + 1) % Battle.SPEEDS.size()
		b.set_speed_index(i)
		seen.append(b.game_speed)
		_ok("A0 time_scale 跟 %s" % Battle.speed_label(b.game_speed),
			is_equal_approx(Engine.time_scale, b.game_speed),
			"time_scale=%f game_speed=%f" % [Engine.time_scale, b.game_speed])
	seen.sort()
	_eq_arr("A0 循環行勻三檔", seen, [0.5, 1.0, 3.0])
	Engine.time_scale = 1.0
	await _end(b)

# ---------------------------------------------------------------------------
# A1 — 冇任何一句**程式碼**仲提住 5x
#
# Battle.SPEEDS 冇咗 5.0 唔代表 5x 走清:一個 `Engine.time_scale = 5.0` 嘅
# 效能工具、一個 `SPEEDS.find(5.0)`(而家返 -1,即係靜靜咁變成 index -1)、
# 一個測試入面嘅 `[0.5, 1.0, 5.0]` —— 三樣都唔會 crash,淨係會靜靜咁量錯嘢。
#
# 掃嘅只係**程式碼**,唔係註解。註解要講得返「點解冇咗 5x」,而嗰啲句子
# 一定會提到 5x —— 一條連解釋都禁埋嘅規則會逼人刪走理由,而理由先係
# 呢個 codebase 最值錢嘅嘢。
# ---------------------------------------------------------------------------
const CODE_DIRS := ["res://scripts", "res://test", "res://tests", "res://tools"]

func _case_no_5x_in_code() -> void:
	var re := RegEx.new()
	# 0.5x / 1.5x / 3x5 / 0x5EED 全部唔算 —— 前面係數字或者字母就唔係「五倍速」。
	re.compile("(?<![0-9A-Za-z_.])5(\\.0)?\\s*[xX](?![0-9])|(?<![0-9A-Za-z_.])[xX]\\s*5(?![0-9])|time_scale\\s*=\\s*5|SPEEDS\\s*\\.\\s*find\\s*\\(\\s*5")
	var hits: Array = []
	for d in CODE_DIRS:
		_scan_dir(d, re, hits)
	_ok("A1 程式碼冇 5x 殘留", hits.is_empty(), "%s" % [hits.slice(0, 8)])
	_ok("A1 真係掃過嘢", _scanned_files > 40, "只掃到 %d 個檔" % _scanned_files)

var _scanned_files := 0

func _scan_dir(path: String, re: RegEx, hits: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var full := path + "/" + name
		if d.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full, re, hits)
		elif name.ends_with(".gd") and name != "SpeedScaleTest.gd":
			# 呢個檔本身就係規則嘅定義,佢一定要講得出 "5x" 三個字。
			_scan_file(full, re, hits)
		name = d.get_next()
	d.list_dir_end()

func _scan_file(path: String, re: RegEx, hits: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	_scanned_files += 1
	var n := 0
	while not f.eof_reached():
		n += 1
		var code := _strip_comment(f.get_line())
		if code.strip_edges() == "":
			continue
		if re.search(code) != null:
			hits.append("%s:%d %s" % [path.get_file(), n, code.strip_edges()])
	f.close()

## 剝走 `#` 註解,但唔可以斬斷字串入面嘅 `#`(顏色碼 "#1c1611" 就係一個)。
func _strip_comment(line: String) -> String:
	var quote := ""
	for i in line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				continue
			if c == quote:
				quote = ""
		elif c == "\"" or c == "'":
			quote = c
		elif c == "#":
			return line.substr(0, i)
	return line

# ---------------------------------------------------------------------------
# A — boss countdown reaches zero after the same amount of game time
# ---------------------------------------------------------------------------
func _case_boss_countdown() -> void:
	var got := []
	for tier in TIERS:
		var b = await _start(LEVEL)
		var guard := 0
		while not b.boss_spawned and guard < 200000:
			guard += 1
			_step(b, tier.dt)
		got.append({"name": tier.name, "v": b.elapsed, "boss_time": b.boss_time})
		await _end(b)
	for g in got:
		# one frame of overshoot is inherent: the countdown is checked per frame
		_near("A boss 倒數 %s" % g.name, g.v, g.boss_time, 0.1)
	_spread("A boss 倒數三檔一致", got, 0.1)

# ---------------------------------------------------------------------------
# B — the spawner emits the same number of monsters per unit of game time
# ---------------------------------------------------------------------------
const SPAWN_WINDOW := 30.0

func _case_spawn_interval() -> void:
	var got := []
	for tier in TIERS:
		var b = await _start(LEVEL)
		_run_for(b, tier.dt, SPAWN_WINDOW)
		got.append({"name": tier.name, "v": float(b.spawned_count)})
		await _end(b)
	# +-1 monster: whether the last interval lands inside the window depends on
	# where the frame boundary falls, and that is a frame, not a scaling bug.
	_spread("B %ds 內刷怪數" % int(SPAWN_WINDOW), got, 1.0)

# ---------------------------------------------------------------------------
# C — a spell cooldown burns down in game seconds, not in frames
# ---------------------------------------------------------------------------
const CD_WAIT := 5.0

func _case_spell_cd() -> void:
	var got := []
	for tier in TIERS:
		var b = await _start(LEVEL)
		b._start_cd(1)
		var full: float = b.spell_cd.get(1, 0.0)
		_ok("C 魔法 CD 有值 %s" % tier.name, full > CD_WAIT, "cd=%f" % full)
		_run_for(b, tier.dt, CD_WAIT)
		got.append({"name": tier.name, "v": b.spell_cd.get(1, 0.0), "full": full})
		await _end(b)
	for g in got:
		_near("C CD 剩餘 %s" % g.name, g.v, g.full - CD_WAIT, 0.1)
	_spread("C 魔法 CD 三檔一致", got, 0.05)

# ---------------------------------------------------------------------------
# D — a burn deals the same total damage over the same burn duration
# ---------------------------------------------------------------------------
const DOT_DPS := 6.0
const DOT_TIME := 4.0

func _case_dot() -> void:
	var got := []
	for tier in TIERS:
		var b = await _start(LEVEL)
		# wait for a monster, then burn it in isolation (no towers are built, so
		# nothing else touches its HP)
		var guard := 0
		while b.monsters.is_empty() and guard < 200000:
			guard += 1
			_step(b, tier.dt)
		if b.monsters.is_empty():
			_ok("D 有怪可燒 %s" % tier.name, false, "no monster spawned")
			await _end(b)
			continue
		var m = b.monsters[0]
		m.max_hp = 100000.0      # keep it alive so the whole burn is observable
		m.hp = 100000.0
		m.burn_dps = DOT_DPS
		m.burn_time = DOT_TIME
		m.burn_tick = 0.0
		var hp0: float = m.hp
		_run_for(b, tier.dt, DOT_TIME + 0.5)
		got.append({"name": tier.name, "v": hp0 - m.hp})
		await _end(b)
	for g in got:
		# one 0.25s tick of slack: the burn's last partial period may or may not
		# have accumulated to a full tick when burn_time runs out
		_near("D 燒傷總傷 %s" % g.name, g.v, DOT_DPS * DOT_TIME, DOT_DPS * 0.25 + 0.01)
	_spread("D 燒傷三檔一致", got, DOT_DPS * 0.25 + 0.01)

# ===========================================================================
# assertions
# ===========================================================================
func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("SPEEDSCALE ok   %s" % label)
	else:
		fails += 1
		print("SPEEDSCALE FAIL %s — %s" % [label, detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol, "got %.4f want %.4f (tol %.4f)" % [got, want, tol])

func _eq_arr(label: String, got, want) -> void:
	_ok(label, str(got) == str(want), "got %s want %s" % [str(got), str(want)])

## The real assertion: the three tiers agree with each other.
func _spread(label: String, got: Array, tol: float) -> void:
	if got.size() < 2:
		_ok(label, false, "only %d tiers ran" % got.size())
		return
	var lo: float = got[0].v
	var hi: float = got[0].v
	var parts: Array = []
	for g in got:
		lo = minf(lo, g.v)
		hi = maxf(hi, g.v)
		parts.append("%s=%.4f" % [g.name, g.v])
	_ok(label, hi - lo <= tol, "spread %.4f > %.4f (%s)" % [hi - lo, tol, ", ".join(parts)])

# ===========================================================================
# harness (same manual-stepping model as BalanceSim/BossHealTest)
# ===========================================================================
func _start(level: int):
	seed(0x59EED)   # identical RNG stream for every tier
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	Engine.time_scale = 1.0   # we supply delta by hand; never let it double-scale
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

## Advance EXACTLY `seconds` of game time in `dt`-sized frames, closing with one
## short frame for the remainder. Overshooting by up to a frame instead makes the
## fast tier run further than the slow one, which shows up as a spread the game
## did not cause — the first version of this harness did that and "failed" the
## cooldown case by precisely one 3x frame.
func _run_for(b, dt: float, seconds: float) -> void:
	var t := 0.0
	while t + dt <= seconds:
		_step(b, dt)
		t += dt
	if seconds - t > 1e-6:
		_step(b, seconds - t)

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
