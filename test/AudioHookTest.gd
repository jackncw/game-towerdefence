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
##   C   **註冊咗嘅每一個音名,都真係有人派過** —— 見 _case_every_sound_dispatched
##
## 唔需要真嘅音訊驅動:呢度問嘅係「派唔派」,唔係「聽落點」。

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

## 成個 run 派過嘅所有音名。debug_log 會被逐個 case clear,所以每次 clear 之前
## 都要 _mark() 一次,將嗰段記錄併入呢度 —— C case 問嘅係「成場落嚟有冇派過」,
## 唔係「上一段有冇派過」。
var _seen: Dictionary = {}

const DT := 1.0 / 30.0

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	_tree.paused = true
	seed(0xA0D10)
	# 由第一行開始就開住觀察窗 —— Battle._ready() 嘅 bgm_battle 喺 _start() 嗰刻
	# 就派咗,遲一步開就永遠見唔到佢。
	Audio.debug_capture = true
	Audio.debug_log.clear()
	await _case_battle_sounds()
	await _case_end_jingles()
	await _case_base_danger()
	await _case_meta_hooks()
	await _case_every_sound_dispatched()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	Audio.debug_capture = false
	_mark()
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
	# 12 幀,唔係 3。C case 一路派聲派到最後一刻(ui_error 同最後一族嘅死亡聲),
	# 而音訊伺服器要等下一次 mix 先放得低 AudioStreamPlayback —— 3 幀之下佢仲
	# 揸住兩三個,引擎退出嗰陣就報做 leak,而嗰個報告係我哋用嚟捉真 leak 嘅信號,
	# 唔可以有恆常噪音。
	await _idle(12)
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
	_mark()

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

	# 每個魔法各施放一次。施法點揀喺一隻真怪身上 —— 神罰(smite)要 240px 之內
	# 有目標先施放得成,冇目標佢 return false。「揀一個有嘢打嘅位施法」正正就係
	# 玩家做嘅事;冇目標嗰個 case 下面單獨驗。
	var cast_dist: float = b.route.total * 0.5
	var cast_pos: Vector2 = b.route.pos_at(cast_dist)
	_mark()
	for sp in GameData.SPELLS:
		# 每次施法之前補返一隻。排喺前面嗰幾個範圍魔法(隕石 / 地震 / 黑洞)會
		# 將施法點附近清空,所以唔補嘅話「十五個魔法都出聲」實際上淨係驗到
		# 排頭嗰幾個 —— 而排最後嗰個 smite 正正就係要目標先施放得成嗰個。
		b._spawn_monster(String(b.cfg.families[0]), 1, false, cast_dist)
		Spells.cast(b, int(sp.id), cast_pos)
	for sp in GameData.SPELLS:
		_heard("H3 魔法 %s" % String(sp.mech), String(Audio.SPELL_SOUND[sp.mech]))

	# 反面:射程內冇嘢嘅神罰,乜都冇做過 —— 冇傷害、冇入冷卻、cast() return
	# false —— 所以佢絕對唔可以出聲。round 9 之前 Audio.play_spell() 派喺 match
	# 之前,呢條路照樣響一下完整嘅神罰聲,玩家聽到「施放咗」但其實乜都冇發生。
	# 一個「乜都冇做」嘅操作出一個「做咗嘢」嘅聲,係最難查嗰種騙人回饋。
	_kill_all(b)
	_mark()
	var smite_id := 0
	for sp in GameData.SPELLS:
		if String(sp.mech) == "smite":
			smite_id = int(sp.id)
	_ok("H3 冇目標嘅神罰施放唔成", not Spells.cast(b, smite_id, Vector2(540, 900)),
		"smite cast returned true with nothing in range")
	_ok("H3 冇目標嘅神罰唔出聲", not Audio.debug_log.has("sfx_spell_smite"),
		"一個冇發生過嘅施放響咗聲:%s" % str(Audio.debug_log))

	# 賣塔
	_mark()
	if b.towers.size() > 0:
		b.sell_tower(b.towers[0])
		_heard("H2 賣塔", "sfx_sell_tower")
	await _end(b)

func _case_end_jingles() -> void:
	# 敗:直接叫 _lose(),唔使真係捱到失守
	Meta.reset_save()
	var b = await _start(1)
	Audio.debug_capture = true
	_mark()
	b._lose()
	_heard("H5 敗 jingle", "jingle_lose")
	await _end(b)

	# 勝 + 首通:第 1 關未通過,所以一次過驗到兩個
	Meta.reset_save()
	var b2 = await _start(1)
	_mark()
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
	_mark()

	var fam: String = b.cfg.families[0]
	b._spawn_monster(fam, 1, false, b.route.total * 0.9)
	_step(b, DT)
	_heard("H4b 基地危險", "sfx_base_danger")

	_mark()
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
	_mark()

	Meta.add_crystals(10)
	_heard("H6 魔晶", "sfx_crystal_gain")

	var unlock_tower_id := 3
	var unlock_spell_id := 2
	_mark()
	_ok("H6 解鎖塔前置:未解鎖", not Meta.is_tower_unlocked(unlock_tower_id),
		"tower %d already unlocked" % unlock_tower_id)
	_ok("H6 解鎖塔成功", Meta.unlock_tower(unlock_tower_id), "unlock_tower returned false")
	_heard("H6 解鎖塔", "sfx_unlock")

	_mark()
	_ok("H6 解鎖魔法前置:未解鎖", not Meta.is_spell_unlocked(unlock_spell_id),
		"spell %d already unlocked" % unlock_spell_id)
	_ok("H6 解鎖魔法成功", Meta.unlock_spell(unlock_spell_id), "unlock_spell returned false")
	_heard("H6 解鎖魔法", "sfx_unlock")

	_mark()
	_ok("H6 升級塔成功", Meta.buy_tower_upgrade(1, 0), "buy_tower_upgrade returned false")
	_heard("H6 升級塔", "sfx_upgrade")

	_mark()
	_ok("H6 升級魔法成功", Meta.buy_spell_upgrade(1, 0), "buy_spell_upgrade returned false")
	_heard("H6 升級魔法", "sfx_upgrade")

	_mark()
	var menu: Node = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(menu)
	await get_tree().process_frame
	_ok("H6 選單 BGM",
		Audio.debug_log.has("bgm_menu") or Audio._bgm_name == "bgm_menu",
		"log=%s now=%s" % [str(Audio.debug_log), Audio._bgm_name])
	menu.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# C — 註冊咗嘅每一個音名,都真係有一個到得到嘅派聲點
# ---------------------------------------------------------------------------
## 呢個 case 補返 round 9 走漏咗嗰個窿。
##
## AudioTest._case_registry 一直只係問「呢個名有冇對應嘅檔」。冇嘢問過「呢個名
## 有冇人叫」—— 所以 Audio.TOWER_SOUND 入面 barracks / curse / slowfield 三個
## entry 連同註解寫住「由各自事件派」,而嗰啲事件由頭到尾冇寫過,測試全綠,三座
## 塔照樣一聲不響咁出咗街。名 → 檔 同 名 → 呼叫點 係兩條唔同嘅問題,要分開問。
##
## 做法:跑一場乜都齊嘅戰鬥(廿座塔全落地、十族怪都生過同死過、十五個魔法都
## 施放過、UI 都撳過),再攞成個 run 累積落嚟嘅 _seen 同 registered_sounds()
## 對數。有名冇派過就紅 —— 除非佢喺 UNHOOKED_OK 入面,而嗰度每一行都要寫低理由。
##
## 而家 UNHOOKED_OK 係空嘅。六十四個名全部派得到 —— 呢個先係「音效做完咗」
## 應該長成嘅樣。將來有名真係冇路可以行到,就加落去連埋理由,唔好靜靜雞刪個名。
const UNHOOKED_OK := {}

func _case_every_sound_dispatched() -> void:
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	var b = await _start(1)
	b.gold = 9999999
	b.base_shield = 9999          # 漏怪唔好變成輸,呢個 case 唔係測輸贏

	# --- 廿座塔全部落地。放喺路邊,唔係求其揾個空地:一座冇目標嘅塔同一座
	#     冇接駁聲嘅塔,喺呢個測試度睇落一模一樣。
	var placed: int = _place_all_towers(b)
	_ok("C 廿座塔全部起到", placed == 20, "只起到 %d 座" % placed)

	# --- 每座塔嘅路邊都生一隻。唔可以靠「生十隻散落成條路,行下就會有塔打到」
	#     —— 邊隻怪喺 90 幀之內行入邊座塔嘅射程係彩數,而彩數紅嘅測試等於冇測試。
	#     詛咒光環同傳送塔就係咁走甩咗嘅:唔係冇接駁,係射程入面冇嘢。
	for t in b.towers:
		if not is_instance_valid(t):
			continue
		b._spawn_monster("goblin", 1, false,
			clampf(b.route.nearest_dist_param(t.global_position), 0.0, b.route.total - 10.0))
	# 3 秒遊戲時間:夠所有攻擊塔行完一個冷卻、兵營出到兵、詛咒同緩速上到身
	for i in 90:
		_step(b, DT)

	# --- 傳送塔:tpchance 唔係 100%,所以直接夾硬校做必中再叫返個真呼叫點,
	#     否則呢個 case 會變成一個間中紅嘅測試,而間中紅等於冇測試。
	var tp = _tower_with_mech(b, "teleport")
	_ok("C 揾到傳送塔", tp != null, "no teleport tower placed")
	var victim = _any_monster(b)
	_ok("C 場上仲有怪可以做目標", victim != null, "no live monster left to displace")
	if tp != null and victim != null:
		tp.s.tpchance = 1.0
		tp._fire_teleport(victim)
		# 擊退:磁力塔同龍捲風平時派呢個,呢度直接叫返 Monster.displace() 個
		# 呼叫點,唔使等磁力塔啱啱好有嘢喺射程入面。
		victim.displace(60.0)

	# --- 十族嘅死亡聲同三款受擊聲。上面嗰 3 秒唔保證十族都死得晒(塔打邊隻
	#     係睇 targeting 嘅),所以呢度逐族生一隻、打一下(受擊)、再打死佢
	#     (死亡),行嘅係 Monster.take_hit / _die 兩個真呼叫點。
	for fam in GameData.FAMILY_ORDER:
		var m = b._spawn_monster(String(fam), 1, false, 20.0)
		m.take_hit(1.0, "true")
		# 一下唔一定打得死:甲蟲嘅 hardshell 將每一下封頂喺最大血 12%,所以要
		# 打到死為止。上限只係防死循環,唔係邏輯嘅一部分。
		var guard := 0
		while m.alive and guard < 64:
			m.take_hit(9999999.0, "true")
			guard += 1
		_ok("C %s 打得死" % fam, not m.alive, "%s 打咗 %d 下都仲未死" % [fam, guard])

	# --- UI 三條路:掣、抽屜、拒絕提示
	var btn := UI.button("x", Vector2(120, 60))
	add_child(btn)
	btn.pressed.emit()
	btn.queue_free()
	if b.hud != null:
		b.hud._set_drawer(true)
		b.hud._set_drawer(false)
		# toast 就係遊戲入面唯一嘅「拒絕」頻道(魔晶不足 / 冷卻中 / 唔可以起喺呢度)
		UI.toast(b.hud, "test", UI.DANGER)
	await _idle(1)
	_mark()
	await _end(b)

	# --- 對數
	var names: Array = Audio.registered_sounds()
	_ok("C 註冊表覆蓋成套音(64 個)", names.size() == 64,
		"registered_sounds() 返咗 %d 個" % names.size())
	var never: Array = []
	for n in names:
		if not _seen.has(String(n)) and not UNHOOKED_OK.has(String(n)):
			never.append(String(n))
	_ok("C 註冊咗嘅 %d 個音全部有人派過" % names.size(), never.is_empty(),
		"註冊咗但成個 run 冇一次派過:%s" % str(never))
	# 反方向:allowlist 唔可以生鏽。一個名接返咗聲之後仲留喺 allowlist 度,
	# 就等於下次佢再斷聲都冇人會知。
	var stale: Array = []
	for n in UNHOOKED_OK:
		if _seen.has(String(n)):
			stale.append(String(n))
	_ok("C allowlist 冇過期 entry", stale.is_empty(),
		"呢啲名而家派得到,應該喺 UNHOOKED_OK 度拆走:%s" % str(stale))

## 廿座塔逐座揾一個離路最近嘅合法空地。逐座重新掃,因為前一座落地之後會令
## 佢自己嗰格唔再合法。
func _place_all_towers(b) -> int:
	var placed := 0
	for id in range(1, 21):
		var want: Vector2 = b.route.pos_at(b.route.total * (float(id) / 21.0))
		var best := Vector2.INF
		var bestd := INF
		for gy in range(1, 26):
			for gx in range(0, 15):
				var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
				if not b.can_place(p):
					continue
				var d: float = p.distance_to(want)
				if d < bestd:
					bestd = d
					best = p
		if best != Vector2.INF and b.place_tower(id, best):
			placed += 1
	return placed

func _tower_with_mech(b, mech: String):
	for t in b.towers:
		if is_instance_valid(t) and String(t.mech) == mech:
			return t
	return null

func _any_monster(b):
	for m in b.monsters:
		if m.alive:
			return m
	return null

## 打死場上所有嘢。b.monsters 會喺死亡途中縮水,所以要行副本。
func _kill_all(b) -> void:
	for m in b.monsters.duplicate():
		var guard := 0
		while is_instance_valid(m) and m.alive and guard < 64:
			m.take_hit(9999999.0, "true")
			guard += 1

## debug_log 併入 _seen,然後清空。每個 case 之間都要叫。
func _mark() -> void:
	for n in Audio.debug_log:
		_seen[String(n)] = true
	Audio.debug_log.clear()

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
