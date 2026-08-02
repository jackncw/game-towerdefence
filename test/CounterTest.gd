extends Node
## 第十輪 B + C:巫教族反制 + 聖光塔全圖光環。
##
## 呢個測試問嘅唔係「個數啱唔啱」,而係「嗰件事真係發生咗冇」。分別喺:
## 一個 -70% 治療減免寫落 GameData 度係一個常數;寫落一隻怪身上,再叫佢
## 回血,再量返佢實際回咗幾多 —— 嗰個先係一個功能。
##
##   godot --headless --path . res://test/CounterTest.tscn

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	_tree.paused = true
	await _case_heal_cut()
	await _case_poison_heal_cut()
	await _case_miasma_heal_cut()
	await _case_emp_silences_aura()
	await _case_beam_shred()
	await _case_support_targeting()
	await _case_smite_support()
	await _case_holy_global()
	await _case_holy_stacking()
	await _case_holy_axis_replaced()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	print("COUNTER %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------------------
# B — 削治療
# ---------------------------------------------------------------------------
## 通用狀態,唔係逐個機制各寫一套:任何治療來源都應該受制。
func _case_heal_cut() -> void:
	var b = await _start()
	var m = _spawn(b, "cultist", 3)
	m.hp = m.max_hp * 0.5
	var before: float = m.hp
	m.request_heal(100.0, true)
	var full: float = m.hp - before
	_ok("B1 未中重傷:治療全額到帳", full > 99.0, "healed %.1f" % full)
	m.hp = m.max_hp * 0.5
	m.apply_heal_cut(0.7, 5.0)
	before = m.hp
	m.request_heal(100.0, true)
	var cut: float = m.hp - before
	_near("B1 重傷 70%:治療只剩三成", cut, 30.0, 1.0)
	# 兩個來源取最大值,唔係相加 —— 疊到超過 100% 就唔再係狀態,係免疫
	m.apply_heal_cut(0.5, 5.0)
	_near("B1 兩個來源取最大值", m.heal_cut, 0.7, 0.001)
	await _end(b)

## 毒液塔嘅重傷跟住「每層毒傷」一齊深化。
func _case_poison_heal_cut() -> void:
	var b = await _start()
	Meta.tower_up["6"] = [0, 0, 0, 0, 0, 0]
	var t0 = _place(b, 6, Vector2(300, 700))
	var base_cut: float = t0._poison_heal_cut()
	_near("B2 毒液塔基礎重傷", base_cut, GameData.POISON_HEALCUT_BASE, 0.001)
	# 課滿「每層毒傷」(dir 3)之後重傷要更深
	Meta.tower_up["6"] = [0, 0, 0, GameData.MAX_UP_LV, 0, 0]
	var t1 = _place(b, 6, Vector2(500, 700))
	_ok("B2 每層毒傷連帶加深重傷", t1._poison_heal_cut() > base_cut + 0.05,
		"base=%.3f maxed=%.3f" % [base_cut, t1._poison_heal_cut()])
	_ok("B2 重傷有封頂", t1._poison_heal_cut() <= GameData.POISON_HEALCUT_MAX + 0.001,
		"cut=%.3f" % t1._poison_heal_cut())
	# 真係打一發落去:中毒之後個狀態要上到身
	var m = _spawn(b, "cultist", 3)
	_step(b, 0.05)
	t1.position = m.global_position + Vector2(0, -30)
	t1._fire(m)
	for i in 30:
		_step(b, 0.05)
		if m.heal_cut > 0.0:
			break
	_ok("B2 中毒之後真係帶住重傷", m.heal_cut > 0.0, "heal_cut=%.2f" % m.heal_cut)
	Meta.tower_up.erase("6")
	await _end(b)

## 劇毒瘴氣:範圍內減療。
func _case_miasma_heal_cut() -> void:
	var b = await _start()
	var m = _spawn(b, "cultist", 3)
	# 落霧之前行一幀:怪物每幀都會由 route.pos_at(dist) 重設自己個位置,
	# 所以「我擺佢喺呢度」呢句嘢喺下一幀就唔成立 —— 要問返佢實際企喺邊。
	_step(b, 0.05)
	Spells.cast(b, 4, m.global_position)
	_step(b, 0.1)
	_ok("C0 瘴氣範圍內帶住重傷", m.heal_cut > 0.6, "heal_cut=%.2f" % m.heal_cut)
	var want: float = float(GameData.spell_by_id(4).stats.healcut)
	_near("C0 減免幅度同資料一致", m.heal_cut, want, 0.001)
	await _end(b)

# ---------------------------------------------------------------------------
# B — 熄光環
# ---------------------------------------------------------------------------
## 一個被電暈嘅巫師唔應該繼續幫全隊回血。
func _case_emp_silences_aura() -> void:
	var b = await _start()
	var caster = _spawn(b, "cultist", 3)
	caster.position = Vector2(540, 800)
	var ally = _spawn(b, "goblin", 3)
	ally.position = Vector2(560, 800)
	ally.hp = ally.max_hp * 0.4
	# 冇暈眩:光環照跑,同伴回到血
	caster.boss_timer = 0.0
	var before: float = ally.hp
	for i in 12:
		_step(b, 0.1)
	_ok("B3 冇暈眩:光環真係喺度回血", ally.hp > before,
		"%.1f -> %.1f" % [before, ally.hp])
	# 暈眩:光環停
	ally.hp = ally.max_hp * 0.4
	caster.apply_stun(3.0)
	caster.boss_timer = 0.0
	before = ally.hp
	for i in 12:
		_step(b, 0.1)
	_near("B3 暈眩期間光環失效", ally.hp, before, 0.01)
	await _end(b)

## 融甲蝕魔:護甲同魔抗一齊削,唔係轉成易傷。
func _case_beam_shred() -> void:
	var b = await _start()
	Meta.tower_up["10"] = [0, 0, 0, 0, GameData.MAX_UP_LV, 0]   # 融甲軸
	var t = _place(b, 10, Vector2(400, 700))
	var m = _spawn(b, "ghost", 3)     # 魔抗 25,係融甲軸嘅整個重點
	m.position = Vector2(420, 700)
	t.last_target = null
	for i in 10:
		t._proc_beam(0.05)
	_ok("B4 護甲被削", m.shred_armor > 0.0, "shred_armor=%.2f" % m.shred_armor)
	_ok("B4 魔抗一齊被削", m.shred_mres > 0.0, "shred_mres=%.2f" % m.shred_mres)
	# 削魔抗要真係令魔法傷害打得入
	var hp0: float = m.hp
	m.take_hit(100.0, "magic")
	var with_shred: float = hp0 - m.hp
	m.shred_mres = 0.0
	m.shred_armor = 0.0
	hp0 = m.hp
	m.take_hit(100.0, "magic")
	var without: float = hp0 - m.hp
	_ok("B4 削魔抗真係令魔法打得入", with_shred > without + 0.5,
		"with=%.2f without=%.2f" % [with_shred, without])
	Meta.tower_up.erase("10")
	await _end(b)

## 狙擊塔 / 導彈塔優先點名支援型單位。
func _case_support_targeting() -> void:
	var b = await _start()
	var tank = _spawn(b, "golem", 5)       # 最肥,原本嘅「最高血」規則會揀佢
	tank.position = Vector2(420, 700)
	tank.dist = 400.0
	var caster = _spawn(b, "cultist", 1)   # 最瘦,但係支援型
	caster.position = Vector2(440, 700)
	caster.dist = 100.0
	_ok("B5 巫師算支援型", caster.is_support(), "mech=%s" % caster.mech)
	_ok("B5 岩石巨像唔算支援型", not tank.is_support(), "mech=%s" % tank.mech)
	var sniper = _place(b, 7, Vector2(400, 700))
	_ok("B5 狙擊塔優先揀巫師", sniper._acquire_target() == caster,
		"picked %s" % str(sniper._acquire_target()))
	var missile = _place(b, 16, Vector2(400, 720))
	_ok("B5 導彈塔優先揀巫師", missile._acquire_target() == caster,
		"picked %s" % str(missile._acquire_target()))
	# 冇支援型嘅時候要跌返落原本規則,唔係唔開火
	caster.alive = false
	_ok("B5 冇巫師就跌返落原本規則", sniper._acquire_target() == tank,
		"picked %s" % str(sniper._acquire_target()))
	await _end(b)

## 天雷誅殺對支援型增傷。
func _case_smite_support() -> void:
	var b = await _start()
	var caster = _spawn(b, "cultist", 3)
	caster.position = Vector2(540, 900)
	caster.max_hp = 1.0e9
	caster.hp = 1.0e9
	var hp0: float = caster.hp
	Spells.cast(b, 13, Vector2(540, 900))
	var on_support: float = hp0 - caster.hp
	caster.alive = false
	var grunt = _spawn(b, "goblin", 3)
	grunt.position = Vector2(540, 900)
	grunt.max_hp = 1.0e9
	grunt.hp = 1.0e9
	grunt.mres = caster.mres          # 隔走魔抗差異,只量增傷本身
	hp0 = grunt.hp
	Spells.cast(b, 13, Vector2(540, 900))
	var on_grunt: float = hp0 - grunt.hp
	_ok("B6 天雷誅殺對支援型增傷", on_support > on_grunt * 1.5,
		"support=%.0f grunt=%.0f" % [on_support, on_grunt])
	await _end(b)

# ---------------------------------------------------------------------------
# C — 聖光塔全圖光環
# ---------------------------------------------------------------------------
func _case_holy_global() -> void:
	var b = await _start()
	var holy = _place(b, 18, Vector2(150, 300))
	var far = _place(b, 1, Vector2(950, 1400))    # 對角,舊版一定唔喺光環入面
	b._refresh_holy_aura()
	_ok("C1 光環冇範圍限制", b.holy_haste_at(far.global_position) > 0.0,
		"haste=%.3f" % b.holy_haste_at(far.global_position))
	_near("C1 同聖光塔自己身上一樣", b.holy_haste_at(far.global_position),
		b.holy_haste_at(holy.global_position), 0.0001)
	# 攻速真係加咗落塔身上
	var rate_with: float = far.get_rate()
	b.holy_towers.clear()
	b._refresh_holy_aura()
	var rate_without: float = far.get_rate()
	_ok("C1 對角嗰座塔真係快咗", rate_with > rate_without,
		"%.3f vs %.3f" % [rate_with, rate_without])
	await _end(b)

func _case_holy_stacking() -> void:
	var b = await _start()
	var one := 0.0
	for n in [1, 2, 3, 5]:
		b.holy_towers.clear()
		for t in b.towers.duplicate():
			b.towers.erase(t)
			t.queue_free()
		for i in n:
			_place(b, 18, Vector2(200 + i * 100, 400))
		b._refresh_holy_aura()
		if n == 1:
			one = b.holy_haste_total
		else:
			var want_ratio := 0.0
			for k in n:
				want_ratio += GameData.holy_stack_factor(k)
			_near("C2 %d 座嘅疊加係遞減嘅" % n, b.holy_haste_total, one * want_ratio, 0.0005)
	# 第二座要有用,第五座要冇乜用 —— 呢個先係「擺幾多座」呢個決策嘅內容
	_ok("C2 第二座仍然有意義", GameData.holy_stack_factor(1) >= 0.4,
		"f(1)=%.2f" % GameData.holy_stack_factor(1))
	_ok("C2 第五座幾乎冇意義", GameData.holy_stack_factor(4) <= 0.12,
		"f(4)=%.2f" % GameData.holy_stack_factor(4))
	await _end(b)

## 舊「光環範圍」軸要真係唔喺度,而唔係留返一條冇作用嘅軸。
func _case_holy_axis_replaced() -> void:
	var def := GameData.tower_by_id(18)
	var stats: Array = []
	for up in def.ups:
		stats.append(String(up.stat))
	_ok("C3 光環範圍軸已經除名", not ("aurarange" in stats), str(stats))
	_ok("C3 聖光強度軸已經上線", "aurapower" in stats, str(stats))
	_ok("C3 六軸總數不變", def.ups.size() == 6, "%d axes" % def.ups.size())
	_ok("C3 aurarange 唔再係一個 stat", not def.stats.has("aurarange"),
		str(def.stats.keys()))
	# 遷移:舊存檔喺呢條軸課過嘅魔晶要全退,新軸由 0 起
	var before_crystals: int = Meta.crystals
	Meta.tower_up["18"] = [3, 0, 0, 0, 5, 0]
	Meta.save_version = 1
	var refund: int = Meta._refund_holy_aurarange()
	var want := 0
	for k in 5:
		want += GameData.upgrade_cost(Meta.HOLY_OLD_AURARANGE_BASE_COST, k)
	_ok("C3 退款金額等於實際課咗嘅", refund == want, "refund=%d want=%d" % [refund, want])
	_ok("C3 魔晶真係入返帳", Meta.crystals == before_crystals + want,
		"%d -> %d" % [before_crystals, Meta.crystals])
	_ok("C3 新軸由 0 起", int(Meta.tower_up["18"][4]) == 0, str(Meta.tower_up["18"]))
	_ok("C3 其餘五軸原封不動", int(Meta.tower_up["18"][0]) == 3, str(Meta.tower_up["18"]))
	Meta.tower_up.erase("18")
	Meta.save_version = Meta.SAVE_VERSION

# ===========================================================================
func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("COUNTER ok   %s" % label)
	else:
		fails += 1
		print("COUNTER FAIL %s — %s" % [label, detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol, "got %.4f want %.4f (tol %.4f)" % [got, want, tol])

func _start():
	seed(0x0C0FFEE)
	Flow.selected_level = 9      # 巫教族出場嘅關
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	b.gold = 9999999
	b.base_shield = 999999       # 呢度冇一條 case 係關於輸贏嘅
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

func _spawn(b, fam: String, lvl: int):
	return b._spawn_monster(fam, lvl, false, 200.0)

func _place(b, id: int, pos: Vector2):
	var t = load("res://scripts/battle/Tower.gd").new()
	b.towers_root.add_child(t)
	t.setup(b, id, pos)
	b.towers.append(t)
	match t.mech:
		"alchemy": b.alchemy_towers.append(t)
		"holy": b.holy_towers.append(t)
		"curse": b.curse_towers.append(t)
	return t

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
