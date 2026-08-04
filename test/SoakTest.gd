extends Node
## 閃退 soak test —— 唔係問「呢個功能啱唔啱」,係問「連續咁玩落去佢死唔死」。
##
## 同其餘十九個測試嘅分別:嗰啲每一個都答一條**具體**問題,而且大部分靠手動
## 餵 delta 去避開真實幀率。呢個係倒轉嚟做 —— **真幀、真 _process、真
## Engine.time_scale、真場景切換**,因為一單閃退嘅成因通常就正正喺嗰啲被手動
## 步進繞開咗嘅位:節點生命週期、pool 回收、autoload 跨場景狀態、音效池。
##
## 兩個階段,缺一不可:
##
##   A. **孤立戰鬥**(add_child / queue_free)—— 壓力行先。一場鋪 40 座塔、
##      3x、魔法連放、中途賣塔轉速加塔,打到 boss 死或者夠鐘。快,所以做得多。
##   B. **真流程**(Flow.goto -> change_scene_to_file)—— 主選單 → 選關 →
##      戰鬥 → 結算 → 返主選單 → 商店 / 升級 / 快捷列 / 圖鑑 …
##      呢個階段唔可以由 A 代替:change_scene_to_file 係**延遲**釋放成個現行
##      場景,而戰鬥收場嗰陣仲有計時器、tween、pool 節點喺度。A 嗰種
##      queue_free 唔行同一條路。
##
## 判斷標準:process 要行到最尾自己 quit(0)。一單真閃退 process 死喺半路,
## exit code 唔會係 0,而 Crash.gd 嘅 marker 會留低最後嗰幾十個麵包屑 ——
## 即係話「跑完 = 冇閃退」呢句係由 exit code 講,唔係由呢個腳本自己講。
##
## 用法:
##   godot --headless res://test/SoakTest.tscn -- --rounds=30
##   godot res://test/SoakTest.tscn -- --rounds=6        # 有窗有真音效驅動
##   ... --flow=0   # 淨係跑 A 階段

const DEFAULT_ROUNDS := 30
## 一場最多行幾多秒**遊戲時間**。boss 喺第 60 秒出,所以呢個數一定要過 60,
## 唔係就永遠測唔到 boss 場 —— 而 boss 場先係塔/怪/音效同時最密嗰陣。
const BATTLE_MAX_GAME_S := 110.0
const TOWERS_PER_BATTLE := 40

func _ready() -> void:
	# 真流程階段會 change_scene_to_file,而嗰下會釋放**現行場景**(即係呢個
	# 節點)。所以真正跑嘢嗰個 driver 要掛喺 root 底下做現行場景嘅兄弟,
	# 唔係掛喺呢度。
	var drv := _Driver.new()
	drv.rounds = _arg_int("--rounds=", DEFAULT_ROUNDS)
	drv.do_flow = _arg_int("--flow=", 1) > 0
	get_tree().root.call_deferred("add_child", drv)

func _arg_int(prefix: String, dflt: int) -> int:
	for a in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if a.begins_with(prefix):
			return maxi(0, int(a.substr(prefix.length())))
	return dflt


class _Driver extends Node:
	var rounds := DEFAULT_ROUNDS
	var do_flow := true
	var battles_done := 0
	var flow_rounds_done := 0
	var _save_bytes := PackedByteArray()
	var _had_save := false
	var _last := ""

	const MENUS := [
		"res://scenes/Shop.tscn",
		"res://scenes/Upgrade.tscn",
		"res://scenes/Bestiary.tscn",
		"res://scenes/QuickBar.tscn",
		"res://scenes/Gallery.tscn",
		"res://scenes/Settings.tscn",
		"res://scenes/LevelSelect.tscn",
	]

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_backup_save()
		Meta.unlocked_towers = range(1, 21)
		Meta.unlocked_spells = range(1, 16)
		Meta.crystals = 9999999
		Crash.crumb("soak", "開始 rounds=%d flow=%s" % [rounds, str(do_flow)])
		print("SOAK: start rounds=%d headless=%s" % [rounds, str(DisplayServer.get_name() == "headless")])
		await _phase_isolated()
		if do_flow:
			await _phase_flow()
		_restore_save()
		Meta.load_game()
		print("SOAK PASS rounds=%d battles=%d flow=%d" % [rounds, battles_done, flow_rounds_done])
		get_tree().quit(0)

	# -----------------------------------------------------------------------
	# A. 孤立戰鬥 + 選單
	# -----------------------------------------------------------------------
	func _phase_isolated() -> void:
		Flow.nav_enabled = false
		for i in rounds:
			# 關數用 7 做步長行勻 1..20,唔係順住行 —— 順住行嘅話短跑淨係試到
			# 頭幾關,而怪物家族/路線/boss 全部係跟關數輪嘅。
			var lv: int = 1 + (i * 7) % 20
			Crash.crumb("soak", "A 第 %d 輪 lv=%d" % [i + 1, lv])
			await _one_battle(lv)
			await _one_menu(MENUS[i % MENUS.size()])
			if i % 5 == 4:
				await _flip_locale()
			print("SOAK: A round %d/%d lv=%d %s" % [i + 1, rounds, lv, _last])
		Flow.nav_enabled = true

	func _one_battle(lv: int) -> void:
		Flow.selected_level = lv
		Flow.last_result = {}
		var b = load("res://scenes/Battle.tscn").instantiate()
		add_child(b)
		await get_tree().process_frame
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
			# 逢 7 嘅倍數關(第十五輪起)開波即刻攤三張合約卡並且凍結成個場。
			# 一個唔識答佢嘅 soak 會喺嗰一輪坐足全個預算、零擊殺 —— 而零擊殺
			# 唔會令任何斷言變紅,所以呢一輪會靜靜咁由「壓力測試」變成「乜都
			# 冇做」。逐段答一張(輪住揀,唔係永遠揀第一張),順便令合約嘅
			# 疊加路徑同卡片 UI 都行入三十分鐘嘅 soak 入面。
			if b.contract_pending and not b.contract_offer.is_empty():
				b.choose_contract(int(b.contract_offer[guard % b.contract_offer.size()]))
				continue
			# get_process_delta_time() 已經計埋 Engine.time_scale —— 再乘一次
			# 就係按倍速食完個預算,結果每場淨係跑到二十幾秒遊戲時間,連 boss
			# (第 60 秒)都未出過。呢個 soak 嘅重點正正就係 boss 場。
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
			# 抽屜 / 暫停 / 圖鑑 overlay —— 全部係戰鬥入面真係開得到嘅嘢,
			# 而且全部會喺一場打緊嘅仗上面加減節點。
			if guard % 331 == 0 and b.hud != null:
				b.hud._set_drawer(not b.hud._drawer_open)
			if guard % 907 == 0 and b.hud != null:
				b.hud._toggle_pause()
				await get_tree().process_frame
				b.hud._toggle_pause()
			if guard % 1511 == 0 and b.hud != null:
				b.hud._open_bestiary_overlay()
				await get_tree().process_frame
		battles_done += 1
		_last = "t=%.0fs boss=%s ended=%s 殺=%d 塔=%d 峰=%d" % [
			t, str(b.boss_spawned), str(b.ended), b.kills, b.towers.size(), b.sim_peak_alive]
		Crash.crumb("soak", "A 戰鬥完 lv=%d %s" % [lv, _last])
		get_tree().paused = false
		b.queue_free()
		await get_tree().process_frame
		Engine.time_scale = 1.0

	## 直接 instantiate 而唔行 place_tower():後者會被路面/間距/金錢擋住,而
	## soak 想要嘅係「二十款塔嘅 _process 全部同時行緊」呢個負載。
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
		Crash.crumb("soak", "A 選單 " + path.get_file())
		var s = load(path).instantiate()
		add_child(s)
		for i in 4:
			await get_tree().process_frame
		s.queue_free()
		await get_tree().process_frame

	func _flip_locale() -> void:
		var next := "en" if Meta.current_locale() == "zh_TW" else "zh_TW"
		Crash.crumb("soak", "A 語言 -> " + next)
		Meta.set_locale(next)
		await get_tree().process_frame

	# -----------------------------------------------------------------------
	# B. 真流程 —— change_scene_to_file 全程
	# -----------------------------------------------------------------------
	## 一圈 = 主選單 → 選關 → 戰鬥 → (結算/失敗) → 主選單 → 一個選單畫面 → 主選單。
	## 圈數特登少過 A:呢個階段慢好多(每次切場景要重建成棵 Control 樹),
	## 而佢要答嘅問題唔係「頂唔頂得住負載」,係「切場景嗰下有冇嘢跌落地」。
	func _phase_flow() -> void:
		var n: int = maxi(3, rounds / 5)
		for i in n:
			var lv: int = 1 + (i * 3) % 20
			Crash.crumb("soak", "B 第 %d 圈 lv=%d" % [i + 1, lv])
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
				# 打到收場為止,或者夠鐘就自己撳「返主選單」——兩條路都要行得通
				while is_instance_valid(b) and get_tree().current_scene == b \
						and t < BATTLE_MAX_GAME_S:
					await get_tree().process_frame
					t += get_process_delta_time()
				battles_done += 1
			# 戰鬥自己會 goto Result/Fail(0.2-0.6 秒之後),等佢切完先郁
			for k in 90:
				await get_tree().process_frame
				var cs := get_tree().current_scene
				if cs != b and cs != null:
					break
			Engine.time_scale = 1.0
			await _goto_wait(Flow.MAIN_MENU)
			await _goto_wait(MENUS[i % MENUS.size()])
			flow_rounds_done += 1
			print("SOAK: B round %d/%d lv=%d t=%.0fs -> %s" %
				[i + 1, n, lv, t, str(get_tree().current_scene)])
		await _goto_wait(Flow.MAIN_MENU)

	func _goto_wait(path: String) -> void:
		Flow.goto(path)
		# change_scene_to_file 係延遲嘅:今幀唔會換,下一幀先換。
		for k in 60:
			await get_tree().process_frame
			var cs := get_tree().current_scene
			if cs != null and cs.scene_file_path == path:
				break
		await get_tree().process_frame

	# -----------------------------------------------------------------------
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
