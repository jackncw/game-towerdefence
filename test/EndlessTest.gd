extends Node
## 無盡模式(第 24 輪)嘅規則層測試。
##   godot --headless --path . res://test/EndlessTest.tscn
##
## 分五組:
##   A  解鎖條件同進度(Meta)
##   B  難度封頂(GameData.difficulty)
##   C  獎勵封頂(GameData.reward_scale / 派彩)
##   D  關卡種類(全 boss 關 / 合約關 / 普通無盡關)+ 真開得到場
##   E  **重玩全額獎勵嘅邊界** —— 呢組先係本輪最重要嗰組
##
## E 組要守嘅係一句好窄嘅說話:「取消重玩減免」**只**喺通關第 100 關之後
## 生效。1-100 進程中(即係 Gate 1-8 全部量度所處嘅狀態)一分錢都唔可以變。
## 一個只驗「解鎖後派全額」嘅測試會漏咗嗰半邊,而漏咗嘅後果係成套平衡讀數
## 靜靜咁位移 —— 冇 error、冇 crash,淨係每一條 gate 都量緊另一隻遊戲。

var fails: Array[String] = []
var checked := 0
var _save_bytes := PackedByteArray()
var _had_save := false

func _ok(what: String, cond: bool, detail := "") -> void:
	checked += 1
	if not cond:
		fails.append(what if detail == "" else "%s — %s" % [what, detail])

func _eq(what: String, got, want) -> void:
	_ok("%s(得到 %s,應該係 %s)" % [what, str(got), str(want)], got == want)

func _ready() -> void:
	Crash.enabled = false
	Flow.nav_enabled = false
	_backup_save()

	_case_unlock()
	_case_difficulty_freeze()
	_case_reward_freeze()
	_case_level_kinds()
	_case_replay_boundary()
	await _case_unlock_moment()
	await _case_play_three()

	_restore_save()
	if fails.is_empty():
		print("ENDLESS PASS fails=0 (%d 項)" % checked)
		get_tree().quit(0)
		return
	for f in fails:
		print("  FAIL " + f)
	print("ENDLESS FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

# ---------------------------------------------------------------------------
# 存檔備份 —— 呢個 test 會寫 Meta.cleared 同 add_crystals(佢自己 save_game),
# 唔還原就會污糟 Jack 個真存檔(同 GateSim 一樣嘅理由)。`--nosave` 之下
# disk_enabled = false,兩條路都要行得通。
# ---------------------------------------------------------------------------
func _backup_save() -> void:
	if not Meta.disk_enabled:
		return
	_had_save = FileAccess.file_exists(Meta.SAVE_PATH)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if not Meta.disk_enabled:
		return
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_save_bytes)
			f.close()
	elif FileAccess.file_exists(Meta.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.SAVE_PATH))

## 一個乾淨嘅記憶體狀態。
func _fresh(highest: int, cleared_levels) -> void:
	Meta.crystals = 0
	Meta.highest_level = highest
	Meta.cleared = {}
	for n in cleared_levels:
		Meta.cleared[str(n)] = true

# ---------------------------------------------------------------------------
# A 解鎖
# ---------------------------------------------------------------------------
func _case_unlock() -> void:
	_fresh(99, range(1, 100))
	_ok("A 打到第 99 關唔算解鎖", not Meta.endless_unlocked())
	_ok("A 未解鎖 = 重玩減免仲喺度", Meta.replay_penalty_active())
	_fresh(100, range(1, 101))
	_ok("A 通關第 100 關 = 解鎖", Meta.endless_unlocked())
	_eq("A 啱啱解鎖嘅無盡進度", Meta.endless_progress(), 0)
	_fresh(137, range(1, 138))
	_eq("A 打到第 137 關嘅無盡進度", Meta.endless_progress(), 37)
	_eq("A next_level()", Meta.next_level(), 138)
	## **解鎖係推導出嚟,唔係一個新欄位。** 一個只有 `cleared["100"]` 而
	## `highest_level` 唔啱嘅存檔照樣解鎖得到 —— 呢個係為咗 1.0.1 舊存檔:
	## 佢哋冇任何新欄位,但 `cleared` 由第一日起就寫住。
	_fresh(0, [100])
	_ok("A 只靠 cleared[100] 都解鎖到(舊存檔遷移)", Meta.endless_unlocked())

# ---------------------------------------------------------------------------
# B 難度封頂
# ---------------------------------------------------------------------------
func _case_difficulty_freeze() -> void:
	# 普通無盡關 = 第 99 關等值;全 boss 關 = 第 100 關等值。
	var d99 := GameData.difficulty(99)
	var d100 := GameData.difficulty(100)
	for n in [101, 102, 150, 199, 201, 999, 100001]:
		if GameData.is_boss_finale_level(n):
			continue
		_ok("B difficulty(%d) 要 = difficulty(99)" % n,
			is_equal_approx(GameData.difficulty(n), d99))
	for n in [200, 300, 1000, 100000]:
		_ok("B difficulty(%d) 要 = difficulty(100)" % n,
			is_equal_approx(GameData.difficulty(n), d100))
	_ok("B 無盡段唔可以再爬(difficulty(500) 唔大過 difficulty(101))",
		GameData.difficulty(500) <= GameData.difficulty(101) + 0.001)
	## `wave_scale` 仲有 path_factor / level_wave_norm 兩個「風味」修正器,
	## 佢哋得幾個離散值 —— 所以無盡段嘅實際怪血量係一個**有界**嘅擺動,
	## 唔係一條爬升線。呢度守住「冇指數成分漏返出嚟」。
	var lo := INF
	var hi := 0.0
	for n in range(101, 500):
		if GameData.is_boss_finale_level(n):
			continue
		var w := GameData.wave_scale(n)
		lo = minf(lo, w)
		hi = maxf(hi, w)
	_ok("B 無盡段 wave_scale 嘅擺動有界(%.2f 倍)" % (hi / maxf(1.0, lo)), hi / maxf(1.0, lo) < 4.0)
	_ok("B 第 400 關嘅 wave_scale 唔會大過第 101-140 段嘅最高",
		GameData.wave_scale(400) <= hi + 1.0)

# ---------------------------------------------------------------------------
# C 獎勵封頂
# ---------------------------------------------------------------------------
func _case_reward_freeze() -> void:
	var r99 := GameData.level_crystal_reward(99)
	var r100 := GameData.level_crystal_reward(100)
	for n in [101, 150, 199, 201, 5000]:
		if GameData.is_boss_finale_level(n):
			continue
		_eq("C 第%d關通關獎勵 = 第99關" % n, GameData.level_crystal_reward(n), r99)
	for n in [200, 300, 1000]:
		_eq("C 第%d關通關獎勵 = 第100關" % n, GameData.level_crystal_reward(n), r100)
	_eq("C 首通獎勵一樣封頂", GameData.level_first_clear_bonus(400),
		GameData.level_first_clear_bonus(100))
	## 難度平咗而派彩繼續爬 = 印鈔機。呢句就係嗰個唔准出現嘅狀態嘅可執行版本。
	## 逐**種**關比較 —— 全 boss 關派 FINAL_REWARD_MULT 倍係設計,唔係爬升
	## (第一版寫咗 `reward(3000) <= reward(101)`,而 3000 啱啱好係全 boss 關,
	## 即係嗰條斷言問緊一條錯嘅問題)。
	_ok("C 無盡段普通關派彩唔可以爬",
		GameData.level_crystal_reward(3001) <= GameData.level_crystal_reward(101))
	_ok("C 無盡段全 boss 關派彩唔可以爬",
		GameData.level_crystal_reward(3000) <= GameData.level_crystal_reward(200))
	_eq("C 全 boss 關派彩 = 第100關", GameData.level_crystal_reward(3000),
		GameData.level_crystal_reward(100))
	## cumulative_reward 喺無盡段唔可以行一條逐關 loop(一個打到第 5000 關嘅
	## 存檔每次問 typical_upgrade_cost 都要行五千次)—— 順手驗佢仲係單調。
	_ok("C cumulative_reward 喺無盡段仲係單調遞增",
		GameData.cumulative_reward(400) > GameData.cumulative_reward(200))
	_ok("C typical_upgrade_cost 喺無盡段有得計", GameData.typical_upgrade_cost(5000) > 0)

# ---------------------------------------------------------------------------
# D 關卡種類
# ---------------------------------------------------------------------------
func _case_level_kinds() -> void:
	_ok("D 100 唔算無盡關", not GameData.is_endless_level(100))
	_ok("D 101 係無盡關", GameData.is_endless_level(101))
	for n in [100, 200, 300, 700, 1000]:
		_ok("D 第%d關係全 boss 關" % n, GameData.is_boss_finale_level(n))
	for n in [101, 150, 199, 201]:
		_ok("D 第%d關唔係全 boss 關" % n, not GameData.is_boss_finale_level(n))
	## 合約關喺無盡段照舊逢 7,除咗撞正全 boss 關
	_ok("D 第105關係合約關", GameData.is_contract_level(105))
	_ok("D 第700關唔係合約關(全 boss 關優先)", not GameData.is_contract_level(700))
	_ok("D 第100關唔係合約關", not GameData.is_contract_level(100))
	var cfg: Dictionary = GameData.level_config(101)
	_ok("D 第101關唔係 finale", not bool(cfg.get("is_final", false)))
	_ok("D 第101關有 2-3 個家族", (cfg.get("families", []) as Array).size() >= 2)
	_ok("D 第101關 wave_scale > 0", float(cfg.get("wave_scale", 0.0)) > 0.0)
	_ok("D 第101關 start_gold > 0", int(cfg.get("start_gold", 0)) > 0)

# ---------------------------------------------------------------------------
# E 重玩全額獎勵嘅邊界(本輪最重要嗰組)
# ---------------------------------------------------------------------------
func _case_replay_boundary() -> void:
	var lv := 50
	var full := GameData.level_crystal_reward(lv)

	# --- 未通關第 100 關:一切照舊 -------------------------------------------
	_fresh(80, range(1, 81))
	var r1: Dictionary = Meta.on_level_cleared(lv)
	_eq("E1 進程中重玩通關獎勵要減半", int(r1["base"]), int(full / 2))
	_eq("E1 進程中重玩冇首通獎勵", int(r1["first"]), 0)
	_ok("E1 進程中要標住「重玩」", bool(r1["replay"]))
	var lose_replay := GameData.level_lose_max(lv, true)
	var lose_first := GameData.level_lose_max(lv, false)
	_ok("E1 進程中敗仗重玩上限細過首次", lose_replay < lose_first)
	_fresh(80, range(1, 81))
	var f1: Dictionary = Meta.on_level_failed(lv, 40, 60.0, 60.0, 0.5)
	_ok("E1 進程中敗仗要標住「重玩」", bool(f1["replay"]))
	_eq("E1 進程中敗仗上限 = 減免後嘅上限", int(f1["cap"]), lose_replay)

	# --- 未通關 100:未打過嘅關照樣派首通 ------------------------------------
	_fresh(80, range(1, 81))
	var r2: Dictionary = Meta.on_level_cleared(90)
	_eq("E1 未打過嘅關派全額", int(r2["base"]), GameData.level_crystal_reward(90))
	_ok("E1 未打過嘅關有首通獎勵", int(r2["first"]) > 0)

	# --- 通關咗第 100 關:減免全部取消 ---------------------------------------
	_fresh(100, range(1, 101))
	var r3: Dictionary = Meta.on_level_cleared(lv)
	_eq("E2 解鎖後重玩派全額", int(r3["base"]), full)
	_eq("E2 解鎖後重玩**仍然冇**首通獎勵", int(r3["first"]), 0)
	_ok("E2 解鎖後唔再標「重玩(減半)」", not bool(r3["replay"]))
	_fresh(100, range(1, 101))
	var f3: Dictionary = Meta.on_level_failed(lv, 40, 60.0, 60.0, 0.5)
	_ok("E2 解鎖後敗仗唔再減免", not bool(f3["replay"]))
	_eq("E2 解鎖後敗仗上限 = 全額上限", int(f3["cap"]), lose_first)

	# --- 邊界本身:99 vs 100 -------------------------------------------------
	_fresh(99, range(1, 100))
	_ok("E3 通關到第 99 關為止,減免仲喺度", Meta.replay_penalty_active())
	var r4: Dictionary = Meta.on_level_cleared(lv)
	_eq("E3 第 99 關嗰刻重玩仲係減半", int(r4["base"]), int(full / 2))
	Meta.cleared["100"] = true
	_ok("E3 一通關第 100 關,減免即刻取消", not Meta.replay_penalty_active())
	var r5: Dictionary = Meta.on_level_cleared(lv)
	_eq("E3 之後同一關重玩派全額", int(r5["base"]), full)

	# --- 首通獎勵永遠一關一次(唔係嘅話重玩就係印鈔機)----------------------
	_fresh(150, range(1, 151))
	var tot := 0
	for i in 5:
		tot += int((Meta.on_level_cleared(lv) as Dictionary)["first"])
	_eq("E4 解鎖後重玩五次都冇首通獎勵", tot, 0)

# ---------------------------------------------------------------------------
# F 解鎖嗰一刻:通關第 100 關 -> 結算畫面即刻要有「下一關 (101)」
#
# 呢個 case 守嘅係一個**次序**:`Battle._win()` 先叫 `Meta.on_level_cleared()`
# 再 `Flow.goto(RESULT)`,所以結算畫面讀 `endless_unlocked()` 嗰陣個 flag
# 一定已經 true。如果將來有人將派彩搬去結算畫面度先計,呢粒掣就會喺**通關
# 第 100 關嗰一次**唔見咗(而下一次入返去就會有)—— 一個只喺遊戲入面最重要
# 嗰一刻出現嘅 bug。
# ---------------------------------------------------------------------------
func _case_unlock_moment() -> void:
	_fresh(99, range(1, 100))
	_ok("F 通關第 100 關之前未解鎖", not Meta.endless_unlocked())
	Meta.on_level_cleared(GameData.FINAL_LEVEL)
	_ok("F 派完彩即刻解鎖", Meta.endless_unlocked())
	_eq("F highest_level 去到 100", Meta.highest_level, GameData.FINAL_LEVEL)
	Flow.last_result = {"win": true, "level": GameData.FINAL_LEVEL, "kills": 300,
		"base": 100, "first": 100, "crystals": 200, "mult": 1.0, "replay": false}
	# `var r :=` 推唔到型(instantiate() 返 Object)—— 呢個係本專案踩過好多次
	# 嘅 GDScript 陷阱,一定要寫明型。
	var r: Node = load("res://scenes/Result.tscn").instantiate()
	add_child(r)
	await get_tree().process_frame
	var texts: Array = []
	_collect_text(r, texts)
	var joined := " | ".join(texts)
	_ok("F 結算畫面要有「下一關 (101)」",
		joined.contains(tr("RESULT_NEXT").format({"n": 101})), joined)
	r.queue_free()
	await get_tree().process_frame

func _collect_text(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_text(c, out)

# ---------------------------------------------------------------------------
# D2 真開得到場:第 101/102/103 三關連續
# ---------------------------------------------------------------------------
func _case_play_three() -> void:
	_fresh(100, range(1, 101))
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	for lv in [101, 102, 103]:
		Flow.selected_level = lv
		Flow.last_result = {}
		var b = load("res://scenes/Battle.tscn").instantiate()
		add_child(b)
		await get_tree().process_frame
		get_tree().paused = true
		b.base_shield = 99999999
		b.gold = 99999999
		_eq("D2 第%d關開得到場" % lv, int(b.level), lv)
		_ok("D2 第%d關唔係 finale" % lv, not b.final_level)
		# 行三十秒,要有怪出、唔可以死喺半路
		var t := 0.0
		while t < 30.0 and not b.ended:
			b._process(1.0 / 30.0)
			for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
				for c in root.get_children():
					if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
						c._process(1.0 / 30.0)
			t += 1.0 / 30.0
		_ok("D2 第%d關三十秒內要出過怪(而家 %d)" % [lv, b.spawned_count],
			b.spawned_count > 0)
		_ok("D2 第%d關唔應該打得完(冇人打)" % lv, not b.ended)
		get_tree().paused = false
		b.queue_free()
		await get_tree().process_frame
		get_tree().paused = true
	get_tree().paused = false
