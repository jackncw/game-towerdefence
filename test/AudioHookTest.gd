extends Node
## 「呢個事件到底有冇出聲」嘅回歸測試。
##
## 音效最典型嘅壞法唔係響錯,係靜咗 —— 一個 typo 嘅音名、一個冇接駁嘅事件,
## 喺遊戲入面完全冇症狀,冇人會發現。所以呢度跑一場真戰鬥,開住 Audio 嘅
## 觀察窗,然後問:呢啲名有冇出現過。
##
##   H1  怪物死 / 受擊
##   H2  起塔 / 賣塔 / 金幣
##   H3  魔法
##   H4  boss 出場 -> 警號 + boss 曲排隊
##   H5  勝 / 敗 jingle
##   H4b 基地危險(路程跨過門檻,冇 Barrier 罩住)——淨係響一次
##   H6  魔晶 / 解鎖 / 升級 (Meta) + 選單 BGM
##
## 唔需要真嘅音訊驅動:呢度問嘅係「派唔派」,唔係「聽落點」。

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

const DT := 1.0 / 30.0

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	_tree.paused = true
	seed(0xA0D10)
	await _case_battle_sounds()
	await _case_end_jingles()
	await _case_base_danger()
	await _case_meta_hooks()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	Audio.debug_capture = false
	Audio.debug_log.clear()
	# Unlike AudioTest (which only load()s streams), every case above actually
	# play()s dozens of them — deaths, hits, spells, jingles, two whole BGM
	# tracks. Stop every player and drop its stream, then let a few frames pass
	# so the audio server releases the playbacks before the engine tears down,
	# same pattern as AudioTest._drop().
	Audio.stop_bgm()
	for c in Audio.get_children():
		if c is AudioStreamPlayer:
			c.stop()
			c.stream = null
	Audio._cache.clear()
	await _idle(3)
	print("AUDIOHOOK %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _case_battle_sounds() -> void:
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	var b = await _start(1)
	b.gold = 99999
	b.boss_time = 6.0            # 唔使等成 60 秒先見到 boss
	Audio.debug_capture = true
	Audio.debug_log.clear()

	# 起塔 -> 起塔聲
	var spot: Vector2 = _free_spot(b)
	_ok("H2 揾到空地", spot != Vector2.INF, "no legal build spot on level 1")
	if spot != Vector2.INF:
		b.place_tower(1, spot)
		_heard("H2 起塔", "sfx_place_tower")

	# 跑到 boss 出場之後,一路殺緊怪
	var t := 0.0
	while t < 20.0 and not b.ended:
		_step(b, DT)
		t += DT

	_ok("H1 有怪死過", b.kills > 0, "kills=%d — 呢個 case 冇嘢可以觀察" % b.kills)
	_heard_any("H1 死亡聲", Audio.DEATH_SOUND.values())
	_heard_any("H1 受擊聲", Audio.HIT_SOUND.values())
	_heard("H2 金幣", "sfx_gold_pop")
	_ok("H4 boss 出咗場", b.boss_spawned, "boss never spawned in 20s")
	_heard("H4 boss 警號", "sfx_boss_warning")
	_ok("H4 boss 曲排咗隊或者已經切咗",
		Audio._bgm_pending == "bgm_boss" or Audio._bgm_name == "bgm_boss",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])

	# 每個魔法各施放一次
	Audio.debug_log.clear()
	for sp in GameData.SPELLS:
		Spells.cast(b, int(sp.id), Vector2(540, 900))
	for sp in GameData.SPELLS:
		_heard("H3 魔法 %s" % String(sp.mech), String(Audio.SPELL_SOUND[sp.mech]))

	# 賣塔
	Audio.debug_log.clear()
	if b.towers.size() > 0:
		b.sell_tower(b.towers[0])
		_heard("H2 賣塔", "sfx_sell_tower")
	await _end(b)

func _case_end_jingles() -> void:
	# 敗:直接叫 _lose(),唔使真係捱到失守
	Meta.reset_save()
	var b = await _start(1)
	Audio.debug_capture = true
	Audio.debug_log.clear()
	b._lose()
	_heard("H5 敗 jingle", "jingle_lose")
	await _end(b)

	# 勝 + 首通:第 1 關未通過,所以一次過驗到兩個
	Meta.reset_save()
	var b2 = await _start(1)
	Audio.debug_log.clear()
	b2._win()
	_heard("H5 勝 jingle", "jingle_win")
	_heard("H5 首通 jingle", "jingle_first_clear")
	await _end(b2)

## 冇「基地生命值」呢樣嘢——一隻怪冇 Barrier 罩住走到底就係直接輸。呢個 case
## 唔等佢真係捱到失守,直接喺路程 90% 處生一隻怪(> BASE_DANGER_ROUTE_FRAC =
## 85%),踩一幀,睇吓「危險」有冇響;再踩多一幀,確認佢唔會響第二次。
func _case_base_danger() -> void:
	Meta.reset_save()
	var b = await _start(1)
	b.base_shield = 0        # 冇 Barrier 罩住 -> 呢個先算「危險」
	Audio.debug_capture = true
	Audio.debug_log.clear()

	var fam: String = b.cfg.families[0]
	b._spawn_monster(fam, 1, false, b.route.total * 0.9)
	_step(b, DT)
	_heard("H4b 基地危險", "sfx_base_danger")

	Audio.debug_log.clear()
	_step(b, DT)
	_ok("H4b 基地危險淨係響一次",
		not Audio.debug_log.has("sfx_base_danger"),
		"second frame past threshold dispatched again: %s" % str(Audio.debug_log))
	await _end(b)

## Meta 嗰五個掛鈎(魔晶 / 塔解鎖 / 魔法解鎖 / 塔升級 / 魔法升級)同主選單 BGM ——
## 呢五個係最容易「靜靜雞」嘅位,因為佢哋唔喺戰鬥入面,冇人會邊打邊聽。
## 塔 3 / 魔法 2 特登揀唔喺 Meta 預設解鎖表(unlocked_towers = [1,2,5,13],
## unlocked_spells = [1])入面嘅 id,否則 unlock_* 一開始就因為「已解鎖」return
## false,連 Audio.play 都唔會行到。塔 1 / 魔法 1 就特登揀喺表入面,因為升級唔
## 需要(亦唔驗)解鎖狀態,揀返同 RegressionTest 一樣嘅已知組合最穩陣。
func _case_meta_hooks() -> void:
	Meta.reset_save()
	Meta.crystals = 99999
	Audio.debug_capture = true
	Audio.debug_log.clear()

	Meta.add_crystals(10)
	_heard("H6 魔晶", "sfx_crystal_gain")

	var unlock_tower_id := 3
	var unlock_spell_id := 2
	Audio.debug_log.clear()
	_ok("H6 解鎖塔前置:未解鎖", not Meta.is_tower_unlocked(unlock_tower_id),
		"tower %d already unlocked" % unlock_tower_id)
	_ok("H6 解鎖塔成功", Meta.unlock_tower(unlock_tower_id), "unlock_tower returned false")
	_heard("H6 解鎖塔", "sfx_unlock")

	Audio.debug_log.clear()
	_ok("H6 解鎖魔法前置:未解鎖", not Meta.is_spell_unlocked(unlock_spell_id),
		"spell %d already unlocked" % unlock_spell_id)
	_ok("H6 解鎖魔法成功", Meta.unlock_spell(unlock_spell_id), "unlock_spell returned false")
	_heard("H6 解鎖魔法", "sfx_unlock")

	Audio.debug_log.clear()
	_ok("H6 升級塔成功", Meta.buy_tower_upgrade(1, 0), "buy_tower_upgrade returned false")
	_heard("H6 升級塔", "sfx_upgrade")

	Audio.debug_log.clear()
	_ok("H6 升級魔法成功", Meta.buy_spell_upgrade(1, 0), "buy_spell_upgrade returned false")
	_heard("H6 升級魔法", "sfx_upgrade")

	Audio.debug_log.clear()
	var menu: Node = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_ok("H6 選單 BGM",
		Audio.debug_log.has("bgm_menu") or Audio._bgm_name == "bgm_menu",
		"log=%s now=%s" % [str(Audio.debug_log), Audio._bgm_name])
	menu.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
func _heard(label: String, name: String) -> void:
	_ok(label, Audio.debug_log.has(name),
		"'%s' 冇派過。派過嘅:%s" % [name, str(Audio.debug_log)])

func _heard_any(label: String, names) -> void:
	for n in names:
		if Audio.debug_log.has(String(n)):
			_ok(label, true, "")
			return
	_ok(label, false, "冇一個派過:%s" % str(names))

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("AUDIOHOOK ok   %s" % label)
	else:
		fails += 1
		print("AUDIOHOOK FAIL %s — %s" % [label, detail])

func _free_spot(b) -> Vector2:
	for gy in range(3, 21):
		for gx in range(1, 15):
			var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
			if b.can_place(p):
				return p
	return Vector2.INF

func _start(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
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
