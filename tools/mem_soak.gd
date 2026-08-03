extends Node
## 長時間記憶體 / 效能取樣 soak。呢個唔係 pass/fail 測試,係一把尺。
##
## 點解要同 test/SoakTest.gd 分家:SoakTest 問「連續咁玩會唔會死」,答案係
## exit code。呢個問「連續咁玩,有咩數字**單調上升**」——答案係一條曲線,而
## 曲線要同另一條曲線比先有意思。所以佢:
##   * 按**真實時間**取樣(每 SAMPLE_S 秒一行),唔係按回合 —— 回合數同記憶體
##     增長冇固定關係,但玩家講「玩咗二十分鐘」係講真實時間。
##   * 出 CSV,一行一個時間點,方便 before/after 兩條線並排。
##   * 混合負載:孤立戰鬥 + 真 change_scene_to_file 流程 + overlay 開關,
##     因為 leak 可以匿喺其中任何一條路,而淨係跑戰鬥就永遠見唔到選單嗰邊。
##
## 用法:
##   godot --headless --path . tools/mem_soak.tscn -- --minutes=30 --out=qa/bench/mem/baseline.csv
##   godot --path . tools/mem_soak.tscn -- --minutes=5 --out=...   # 有窗:RENDER_* 先有真數
##
## ⚠ headless 用 dummy rendering driver,所以 RENDER_* 全部係 0。要 texture /
## draw call 嘅真數就一定要開窗跑。物件/節點/孤兒/static memory 兩邊都準。

const DEFAULT_MINUTES := 30.0
const SAMPLE_S := 60.0

func _ready() -> void:
	# 同 SoakTest / menu_leak 一樣:driver 要掛喺 root 底下做現行場景嘅兄弟,
	# 唔係嘅話第一次 change_scene_to_file 就連自己一齊 free 咗。
	var drv := _Driver.new()
	drv.minutes = _arg_f("--minutes=", DEFAULT_MINUTES)
	drv.out_path = _arg_s("--out=", "qa/bench/mem/soak.csv")
	drv.respect_cap = _arg_f("--cap=", 0.0) > 0.0
	get_tree().root.call_deferred("add_child", drv)

func _arg_f(prefix: String, dflt: float) -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return maxf(0.1, float(a.substr(prefix.length())))
	return dflt

func _arg_s(prefix: String, dflt: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return dflt


class _Driver extends Node:
	var minutes := DEFAULT_MINUTES
	var out_path := "qa/bench/mem/soak.csv"

	var _t0 := 0
	var _next_sample := 0.0
	var _rows: Array = []
	var _frame_ms: Array = []      # 今個取樣窗嘅逐幀時間,每次取樣後清空
	var _battles := 0
	var _flows := 0
	## 而家打緊嗰場(冇就 null)。攞嚟喺取樣嗰陣讀 pool 嘅實際佔用 —— 「pool
	## 上限定成點先叫有根據」呢條問題,唯一嘅答案就係量返峰值同時存在數。
	var _cur_battle = null
	var _peak: Dictionary = {"proj": 0, "fx": 0, "dmg": 0, "mon": 0, "sol": 0}
	var _level := 1
	var _phase := "boot"

	const MENUS := [
		"res://scenes/Shop.tscn",
		"res://scenes/Upgrade.tscn",
		"res://scenes/Bestiary.tscn",
		"res://scenes/QuickBar.tscn",
		"res://scenes/Gallery.tscn",
		"res://scenes/Settings.tscn",
		"res://scenes/LevelSelect.tscn",
	]

	## 一場最多行幾多秒遊戲時間。同 SoakTest 一樣要過 60,唔係就永遠測唔到 boss 場。
	const BATTLE_MAX_GAME_S := 110.0
	const TOWERS_PER_BATTLE := 40

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		# 呢個工具唔應該留低一個「上次閃退」嘅假陽性俾下次開遊戲。
		Crash.enabled = false
		Meta.unlocked_towers = range(1, 21)
		Meta.unlocked_spells = range(1, 16)
		Meta.crystals = 9999999
		_uncap()
		_t0 = Time.get_ticks_msec()
		print("MEMSOAK start minutes=%.1f headless=%s out=%s"
			% [minutes, str(DisplayServer.get_name() == "headless"), out_path])
		await get_tree().process_frame
		_sample()
		var i := 0
		while _elapsed() < minutes * 60.0:
			_level = 1 + (i * 7) % 20
			_phase = "battle"
			await _one_battle(_level)
			_phase = "menu"
			await _one_menu(MENUS[i % MENUS.size()])
			# 每五轉行一次真 change_scene_to_file 流程 —— add_child/queue_free
			# 同 change_scene_to_file 係兩條唔同嘅釋放路徑,leak 匿喺邊條都有可能。
			if i % 5 == 4:
				_phase = "flow"
				await _one_flow(_level)
			i += 1
		_phase = "end"
		_sample()
		_write()
		# Pool 上限嘅根據。左邊係量到嘅峰值同時存在數,右邊係 Battle.gd 設嘅
		# prewarm / cap(桌面值;網頁版乘 WEB_BUDGET=0.55)。
		print("MEMSOAK peak live: proj=%d(prewarm 64) fx=%d(cap %d) dmg=%d(cap %d) monster=%d(prewarm 80) soldier=%d(prewarm 12)"
			% [_peak.proj, _peak.fx, Battle.FX_HARD_CAP, _peak.dmg, Battle.DMG_HARD_CAP,
			_peak.mon, _peak.sol])
		print("MEMSOAK done battles=%d flows=%d rows=%d" % [_battles, _flows, _rows.size()])
		get_tree().quit(0)

	func _elapsed() -> float:
		return float(Time.get_ticks_msec() - _t0) / 1000.0

	## 呢個工具永遠跑喺**解封頂**之下。
	##
	## 點解:baseline 嗰陣個遊戲根本冇設過 Engine.max_fps,而效能輪之後
	## `Flow.apply_frame_cap()` 會鎖 60。如果 after 嗰次跑喺 60 而 baseline 跑喺
	## 140,兩條曲線嘅工作量就唔同,「記憶體平咗」就講唔清係修好咗定係淨係做少咗。
	## 一把尺要兩次量度都用同一個刻度。FPS cap 本身另外驗(見報告)。
	##
	## 要逐次拉返 0:`_one_flow()` 行 Flow.goto(),而佢會照設個 cap。
	## `--cap=1` 反轉呢個行為:唔解封頂,跟返遊戲自己嗰個上限跑。用嚟實測
	## 「60fps 真係鎖到」——嗰條問題同「有冇 leak」係兩件事,所以用兩次跑。
	var respect_cap := false

	func _uncap() -> void:
		if respect_cap:
			return
		Engine.max_fps = 0

	# ---------------------------------------------------------------- 取樣
	## 峰值要**逐幀**追,唔可以淨係喺取樣嗰刻讀 —— 一分鐘一次嘅快照撞正峰值
	## 嘅機會近乎零,而 pool 上限係為咗擋峰值而存在。
	func _track_peaks() -> void:
		var b = _cur_battle
		if b == null or not is_instance_valid(b) or b.proj_pool == null:
			return
		_peak.proj = maxi(_peak.proj, b.proj_pool.live_count())
		_peak.fx = maxi(_peak.fx, b.fx_pool.live_count())
		_peak.dmg = maxi(_peak.dmg, b.dmg_pool.live_count())
		_peak.mon = maxi(_peak.mon, b.monster_pool.live_count())
		_peak.sol = maxi(_peak.sol, b.soldier_pool.live_count())

	func _process(delta: float) -> void:
		_track_peaks()
		# 逐幀時間要用**真實**時間,唔可以受 Engine.time_scale 影響 —— 3x 之下
		# get_process_delta_time() 已經乘咗 3,直接記落去就會報一個假嘅 p95。
		_frame_ms.append(delta / maxf(0.01, Engine.time_scale) * 1000.0)
		# 呢個 array 自己都要有上限,唔係佢就變成呢個工具自己嘅 leak。
		if _frame_ms.size() > 200000:
			_frame_ms.resize(100000)
		if _elapsed() >= _next_sample:
			_sample()

	func _sample() -> void:
		_uncap()
		var el := _elapsed()
		_next_sample = el + SAMPLE_S
		var p95 := 0.0
		var avg := 0.0
		if not _frame_ms.is_empty():
			var s: Array = _frame_ms.duplicate()
			s.sort()
			p95 = float(s[mini(s.size() - 1, int(s.size() * 0.95))])
			var sum := 0.0
			for v in s:
				sum += float(v)
			avg = sum / float(s.size())
		_frame_ms.clear()
		var r := {
			"t_s": el,
			"phase": _phase,
			"level": _level,
			"battles": _battles,
			"fps": float(Performance.get_monitor(Performance.TIME_FPS)),
			"frame_avg_ms": avg,
			"frame_p95_ms": p95,
			"process_ms": float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0,
			"phys_ms": float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0,
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
			"static_mb": float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
			"static_max_mb": float(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)) / 1048576.0,
			"video_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
			"texture_mb": float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0,
			"buffer_mb": float(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED)) / 1048576.0,
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"render_objs": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			"audio_latency_ms": float(Performance.get_monitor(Performance.AUDIO_OUTPUT_LATENCY)) * 1000.0,
		}
		_rows.append(r)
		print("MEMSOAK %6.1fs %-7s lv=%-2d obj=%-7d node=%-6d orph=%-5d res=%-5d static=%7.2fMB tex=%6.2fMB draw=%-5d fps=%5.1f p95=%5.2fms"
			% [r.t_s, r.phase, r.level, r.objects, r.nodes, r.orphans, r.resources,
			r.static_mb, r.texture_mb, r.draw_calls, r.fps, r.frame_p95_ms])

	func _write() -> void:
		var dir := out_path.get_base_dir()
		if dir != "":
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://") + dir)
		var f := FileAccess.open("res://" + out_path, FileAccess.WRITE)
		if f == null:
			f = FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			push_error("MEMSOAK: cannot write " + out_path)
			return
		var cols: Array = _rows[0].keys() if not _rows.is_empty() else []
		f.store_line(",".join(cols))
		for r in _rows:
			var vals: Array = []
			for c in cols:
				var v = r[c]
				vals.append("%.3f" % v if v is float else str(v))
			f.store_line(",".join(vals))
		f.close()
		print("MEMSOAK wrote " + out_path)

	# ---------------------------------------------------------------- 負載
	func _one_battle(lv: int) -> void:
		Flow.nav_enabled = false
		Flow.selected_level = lv
		Flow.last_result = {}
		var b = load("res://scenes/Battle.tscn").instantiate()
		add_child(b)
		_cur_battle = b
		await get_tree().process_frame
		_uncap()
		b.gold = 9999999
		_place_towers(b)
		b.set_speed_index(Battle.SPEEDS.find(3.0))
		var t := 0.0
		var spell_t := 0.0
		var next_spell := 1
		var guard := 0
		while not b.ended and t < BATTLE_MAX_GAME_S and is_instance_valid(b) and guard < 400000:
			guard += 1
			await get_tree().process_frame
			t += get_process_delta_time()
			spell_t -= get_process_delta_time()
			if spell_t <= 0.0:
				spell_t = 0.3
				var sid := next_spell
				next_spell = 1 + (next_spell % 15)
				if b.spell_cd.get(sid, 0.0) <= 0.0:
					if GameData.spell_by_id(sid).target:
						b._cast_spell_at(sid, Vector2(randf_range(120, 960), randf_range(300, 1500)))
					else:
						b._cast_spell_now(sid)
			if guard % 137 == 0 and not b.towers.is_empty():
				b._set_selected(b.towers[randi() % b.towers.size()])
			if guard % 401 == 0 and b.towers.size() > 6:
				b.sell_tower(b.towers[randi() % b.towers.size()])
			if guard % 257 == 0:
				b.set_speed_index(randi() % Battle.SPEEDS.size())
			if guard % 613 == 0:
				b.gold = 9999999
				_place_towers(b, 6)
			if guard % 331 == 0 and b.hud != null:
				b.hud._set_drawer(not b.hud._drawer_open)
			if guard % 907 == 0 and b.hud != null:
				b.hud._toggle_pause()
				await get_tree().process_frame
				b.hud._toggle_pause()
			if guard % 1511 == 0 and b.hud != null:
				b.hud._open_bestiary_overlay()
				await get_tree().process_frame
		_battles += 1
		_cur_battle = null
		get_tree().paused = false
		b.queue_free()
		await get_tree().process_frame
		Engine.time_scale = 1.0
		Flow.nav_enabled = true

	func _place_towers(b, n := TOWERS_PER_BATTLE) -> void:
		var TowerScript := load("res://scripts/battle/Tower.gd")
		for i in n:
			var id: int = 1 + (b.towers.size() % 20)
			var col: int = b.towers.size() % 6
			var row: int = b.towers.size() / 6
			var tw = TowerScript.new()
			b.towers_root.add_child(tw)
			tw.setup(b, id, Vector2(120 + col * 160, 300 + row * 150))
			b.towers.append(tw)
			match tw.mech:
				"alchemy": b.alchemy_towers.append(tw)
				"holy": b.holy_towers.append(tw)
				"curse": b.curse_towers.append(tw)

	func _one_menu(path: String) -> void:
		var s = load(path).instantiate()
		add_child(s)
		for i in 4:
			await get_tree().process_frame
		s.queue_free()
		await get_tree().process_frame

	## 一圈真流程:主選單 → 選關 → 戰鬥 → 結算 → 主選單 → 一個選單。
	func _one_flow(lv: int) -> void:
		await _goto_wait(Flow.MAIN_MENU)
		await _goto_wait(Flow.LEVEL_SELECT)
		Flow.selected_level = lv
		await _goto_wait(Flow.BATTLE)
		var b = get_tree().current_scene
		var t := 0.0
		if b is Battle:
			b.gold = 9999999
			_place_towers(b, 24)
			b.set_speed_index(Battle.SPEEDS.find(3.0))
			while is_instance_valid(b) and get_tree().current_scene == b and t < 60.0:
				await get_tree().process_frame
				t += get_process_delta_time()
		for k in 90:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != b and cs != null:
				break
		Engine.time_scale = 1.0
		await _goto_wait(Flow.MAIN_MENU)
		_flows += 1

	func _goto_wait(path: String) -> void:
		Flow.goto(path)
		for k in 60:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.scene_file_path == path:
				break
		await get_tree().process_frame
