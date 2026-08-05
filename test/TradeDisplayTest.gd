extends Node
## 「畫面上寫嘅銀碼 == 實際過數嘅銀碼」+ 數值顯示格式規則 —— 顯示修正輪嘅回歸。
##   godot --headless --path . test/TradeDisplayTest.tscn
##
## 點解要有呢條測試:第十五輪建塔成本曾按場上塔數遞增,而 BattleHUD 將個價
## cache 咗落 dict + label,「卡上寫嘅」同「實際扣嘅」每座差開 3% 冇人發現。
## 第十七輪建塔改返固定價,呢啲斷言變成恆等式 —— 但佢哋照留低:佢哋守嘅係
## 「顯示側同扣賬側問同一個入口」,唔係守價錢點計。呢度逐項對:
##
##   A. 建塔 x10:逐座「卡面 label == 實價 == 扣賬額」,而且起完即刻刷新
##   B. 賣塔:面板寫嘅退款 == 實際入賬
##   C. 升級 / 進化(塔同魔法):介面出數嗰條路 == 扣魔晶額
##   D. 格式規則:百分比類一定係「35%」/「2.5%」(唔准 bare 小數)、
##      攻速類固定兩位小數、通用數值唔准出「2560.0」呢類尾數
##
## 同 StatDisplayTest 一樣係「顯示側 vs 引擎側」對數,唔係重新計一次公式。

const UPG := preload("res://scripts/ui/Upgrade.gd")

var fails := 0
var checks := 0
var battle
var _save_bytes := PackedByteArray()
var _had_save := false

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails += 1
		print("TRADE FAIL: ", what)

func _ready() -> void:
	Flow.nav_enabled = false
	_backup_save()
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	# 第 1 關:唔係 7 嘅倍數,唔會開場凍結等合約(嗰個會令 HUD 停喺揀卡層)。
	Flow.selected_level = 1
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	await _test_build_x10()
	_test_sell()
	_test_upgrade_costs()
	_test_evolve_costs()
	_test_format_rules()
	battle.queue_free()
	await get_tree().process_frame
	_restore_save()
	Meta.load_game()
	print("TRADEDISPLAY: %d checks, %d fails" % [checks, fails])
	get_tree().quit(0 if fails == 0 else 1)

# --- A. 建塔 x10 ------------------------------------------------------------
## 卡面 dict(id -> {cost, cost_label})。建塔抽屜卡同快捷卡兩邊都搵。
func _card_for(id: int) -> Dictionary:
	for c in battle.hud.build_cards:
		if int(c.id) == id:
			return c
	for c in battle.hud.quick_cards:
		if int(c.id) == id:
			return c
	return {}

func _test_build_x10() -> void:
	battle.gold = 999999
	var id := 1                      # 箭塔:唔會似鍊金塔咁有 startgold 污染金額
	var card := _card_for(id)
	_check(not card.is_empty(), "HUD 有箭塔嘅建塔卡")
	if card.is_empty():
		return
	var placed := 0
	for gx in range(2, 13):
		for gy in range(3, 9):
			if placed >= 10:
				break
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if not battle.can_place(pos):
				continue
			# 撳之前:卡面寫嘅 == 而家去問嘅實價
			var shown := int(String(card.cost_label.text))
			var quoted: int = battle.place_cost(id)
			_check(shown == quoted,
				"第 %d 座:卡面 %d == 實價 %d" % [placed + 1, shown, quoted])
			# 撳落去:扣嘅 == 卡面寫嘅(place_tower 係同步嘅,中間冇擊殺收入)
			var g0: int = battle.gold
			var ok: bool = battle.place_tower(id, pos)
			_check(ok, "第 %d 座起得成" % (placed + 1))
			if not ok:
				continue
			_check(g0 - battle.gold == shown,
				"第 %d 座:扣咗 %d == 卡面 %d" % [placed + 1, g0 - battle.gold, shown])
			placed += 1
			# 起完之後下一幀,卡面仍然要同 live 價一致(固定價之下即係冇變)
			await get_tree().process_frame
			_check(int(String(card.cost_label.text)) == battle.place_cost(id),
				"第 %d 座之後卡面刷新做 %d(而家寫 %s)"
				% [placed, battle.place_cost(id), card.cost_label.text])
		if placed >= 10:
			break
	_check(placed == 10, "起足 10 座(得 %d)" % placed)
	# affordability 用嘅 cost 都要係新價,唔係起卡嗰陣嘅舊價
	_check(int(card.cost) == battle.place_cost(id),
		"affordability cache 跟住新價 (%s vs %d)" % [card.cost, battle.place_cost(id)])

# --- B. 賣塔 ----------------------------------------------------------------
func _test_sell() -> void:
	if battle.towers.is_empty():
		_check(false, "有塔可以賣")
		return
	var t = battle.towers[0]
	battle.hud.show_tower_panel(t)
	# 面板個掣寫嘅數字(HUD_SELL_VALUE 嘅 {n})要係 sell_value()
	var txt := String(battle.hud.sell_btn.text)
	var rx := RegEx.new()
	rx.compile("\\d+")
	var m := rx.search(txt)
	_check(m != null, "賣塔掣有寫銀碼 (%s)" % txt)
	var shown := int(m.get_string()) if m != null else -1
	_check(shown == t.sell_value(),
		"賣塔掣寫 %d == sell_value %d" % [shown, t.sell_value()])
	var g0: int = battle.gold
	battle.sell_tower(t)
	_check(battle.gold - g0 == shown,
		"賣塔實收 %d == 面板寫嘅 %d" % [battle.gold - g0, shown])

# --- C. 升級 / 進化 ---------------------------------------------------------
## 升級介面出數嗰條路(Meta.*_up_cost / GameData.evolve_cost)vs 實扣魔晶。
func _test_upgrade_costs() -> void:
	Meta.crystals = 100000
	# 塔升級
	Meta.tower_up["1"] = [0, 0, 0, 0, 0, 0]
	Meta.tower_tiers["1"] = 1
	var shown: int = Meta.tower_up_cost(1, 0)
	var c0: int = Meta.crystals
	_check(Meta.buy_tower_upgrade(1, 0), "塔升級買得成")
	_check(c0 - Meta.crystals == shown,
		"塔升級:扣 %d == 介面寫 %d" % [c0 - Meta.crystals, shown])
	# 魔法升級
	Meta.spell_up["1"] = [0, 0, 0]
	Meta.spell_tiers["1"] = 1
	shown = Meta.spell_up_cost(1, 0)
	c0 = Meta.crystals
	_check(Meta.buy_spell_upgrade(1, 0), "魔法升級買得成")
	_check(c0 - Meta.crystals == shown,
		"魔法升級:扣 %d == 介面寫 %d" % [c0 - Meta.crystals, shown])

func _test_evolve_costs() -> void:
	# 進化(塔):_zone_evolve 顯示 GameData.evolve_cost(true, tier+1)
	Meta.tower_tiers["2"] = 1
	Meta.tower_up["2"] = []
	for _i in GameData.tower_by_id(2).ups.size():
		Meta.tower_up["2"].append(GameData.MAX_UP_LV)
	var shown := GameData.evolve_cost(true, 2)
	var c0: int = Meta.crystals
	_check(Meta.evolve(2, true), "塔進化得成")
	_check(c0 - Meta.crystals == shown,
		"塔進化:扣 %d == 介面寫 %d" % [c0 - Meta.crystals, shown])
	# 進化(魔法)
	Meta.spell_tiers["2"] = 1
	Meta.spell_up["2"] = []
	for _i in GameData.spell_by_id(2).ups.size():
		Meta.spell_up["2"].append(GameData.MAX_UP_LV)
	shown = GameData.evolve_cost(false, 2)
	c0 = Meta.crystals
	_check(Meta.evolve(2, false), "魔法進化得成")
	_check(c0 - Meta.crystals == shown,
		"魔法進化:扣 %d == 介面寫 %d" % [c0 - Meta.crystals, shown])

# --- D. 格式規則 -------------------------------------------------------------
## 全 project 嘅數字都由 Upgrade.fmt_value 出,所以規則喺呢一個函數上面掃勻
## 就係掃勻成個遊戲:
##   百分比  ^-?\d+%$ 或 ^-?\d+\.\d%$   (35% / 2.5%,唔准 0.35)
##   攻速類  ^\d+\.\d\d$                (1.25,固定兩位)
##   其他    唔准以 .0 結尾             (「2560.0」係噪音)
func _test_format_rules() -> void:
	var rx_pct := RegEx.new()
	rx_pct.compile("^-?\\d+(\\.\\d)?%$")
	var rx_rate := RegEx.new()
	rx_rate.compile("^\\d+\\.\\d\\d$")
	var defs: Array = GameData.TOWERS + GameData.SPELLS
	for def in defs:
		var kinds: Dictionary = UPG.kind_map(def)
		for tier in range(1, GameData.MAX_TIER + 1):
			for lv in [0, 1, 7, GameData.MAX_UP_LV]:
				var levels: Array = UPG.level_vector(def, lv)
				var stats: Dictionary = GameData.effective_stats(def, levels, tier)
				for up in def.ups:
					var st: String = up.stat
					var kind := String(kinds.get(st, ""))
					var txt := UPG.fmt_value(float(stats.get(st, 0.0)), st, kind)
					var label := "%s#%d t%d lv%d %s -> %s" % [def.kind, def.id, tier, lv, st, txt]
					if UPG.is_pct_stat(st, kind):
						_check(rx_pct.search(txt) != null, "百分比格式 " + label)
					elif st in UPG._RATE_STATS:
						_check(rx_rate.search(txt) != null, "攻速兩位小數 " + label)
					else:
						_check(not txt.ends_with(".0"), "通用數值冇 .0 尾 " + label)

# --- save 保護 ---------------------------------------------------------------
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
