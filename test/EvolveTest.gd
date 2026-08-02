extends Node
## 第十輪 D:進化系統。
##
## 呢個測試守住四件事,而四件都係「一唔覺意就會靜靜雞爛咗」嗰種:
##   1. 105 項 tier 表真係齊 —— 名同新機制兩種語言都解得到,冇一格係 key 本身
##   2. 進化嘅**交易**係原子嘅:唔夠條件唔准、唔夠錢唔准、成功就三樣一齊落地
##   3. 費用曲線接續(tier 2 第一級貴過 tier 1 第十五級),唔係重頭計
##   4. 存檔:tier 存得住,而且一份冇呢個欄位嘅舊存檔一定係全部 tier 1
##
## 加一個 smoke:全部塔同魔法喺 tier 3 之下打一場,唔准有腳本錯誤 —— 四十個
## 新機制入面,「喺 tier 1 行得,喺 tier 3 爆」係最容易漏嘅一種。
##
##   godot --headless --path . res://test/EvolveTest.tscn

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
	_case_table_complete()
	_case_sprites_exist()
	_case_cost_curve()
	_case_stat_scaling()
	_case_evolve_transaction()
	_case_save_roundtrip()
	await _case_tier3_battle()
	await _case_ui_flow()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	print("EVOLVE %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------------------
# 1. tier 表齊唔齊
# ---------------------------------------------------------------------------
func _case_table_complete() -> void:
	var items := 0
	var missing: Array = []
	for pair in [[GameData.TOWERS, true], [GameData.SPELLS, false]]:
		for d in pair[0]:
			for tier in range(1, GameData.MAX_TIER + 1):
				items += 1
				var nk: String = GameData.tier_name(d, pair[1], tier)
				if nk == "" or tr(nk) == nk:
					missing.append("name %d T%d (%s)" % [int(d.id), tier, nk])
				if tier == 1:
					continue
				var mk: String = GameData.tier_mech_key(d, pair[1], tier)
				if mk == "" or tr(mk) == mk:
					missing.append("mech %d T%d (%s)" % [int(d.id), tier, mk])
	_ok("D1 105 項", items == 105, "%d items" % items)
	_ok("D1 每一格都解得到", missing.is_empty(), str(missing.slice(0, 6)))
	# 兩種語言都要 —— 一個只有中文嘅 tier 表就係一個英文玩家見到 key 嘅畫面
	for loc in ["zh_TW", "en"]:
		TranslationServer.set_locale(loc)
		var bad: Array = []
		for pair2 in [[GameData.TOWERS, true], [GameData.SPELLS, false]]:
			for d in pair2[0]:
				for tier in [2, 3]:
					if tr(GameData.tier_name(d, pair2[1], tier)) == GameData.tier_name(d, pair2[1], tier):
						bad.append("%d T%d" % [int(d.id), tier])
		_ok("D1 [%s] 全部進化名有譯文" % loc, bad.is_empty(), str(bad.slice(0, 6)))
	TranslationServer.set_locale("zh_TW")
	# 名唔可以同 tier 1 一樣 —— 「演進感」最起碼嘅要求係佢真係改咗個名
	var same: Array = []
	for d in GameData.TOWERS:
		for tier in [2, 3]:
			if GameData.tier_name(d, true, tier) == String(d.name):
				same.append("%d T%d" % [int(d.id), tier])
	_ok("D1 每一階都係一個新名", same.is_empty(), str(same))

func _case_sprites_exist() -> void:
	var missing: Array = []
	for id in range(1, 21):
		for tier in [2, 3]:
			if not ResourceLoader.exists("res://assets/generated/towers/tower_%d_t%d.png" % [id, tier]):
				missing.append("tower_%d_t%d" % [id, tier])
	for id in range(1, 16):
		for tier in [2, 3]:
			if not ResourceLoader.exists("res://assets/generated/spells/spell_%d_t%d.png" % [id, tier]):
				missing.append("spell_%d_t%d" % [id, tier])
	_ok("D1 40 塔 + 30 魔法進化圖齊全", missing.is_empty(), str(missing.slice(0, 8)))
	# Assets 要真係揀到嗰張,唔係靜靜地跌返 tier 1
	var t1: Texture2D = Assets.tower(1, 1)
	var t3: Texture2D = Assets.tower(1, 3)
	_ok("D1 Assets 按階攞到唔同嘅圖", t1 != t3, "same texture returned")
	_ok("D1 進化音效存在",
		ResourceLoader.exists("res://assets/generated_audio/sfx_evolve.wav"), "missing")

# ---------------------------------------------------------------------------
# 2. 費用曲線接續
# ---------------------------------------------------------------------------
func _case_cost_curve() -> void:
	var base := 55
	var last_t1 := GameData.upgrade_cost_at(base, GameData.MAX_UP_LV - 1, 1)
	var first_t2 := GameData.upgrade_cost_at(base, 0, 2)
	_ok("D2 tier 2 第一級貴過 tier 1 最後一級", first_t2 > last_t1,
		"t1[14]=%d t2[0]=%d" % [last_t1, first_t2])
	var last_t2 := GameData.upgrade_cost_at(base, GameData.MAX_UP_LV - 1, 2)
	var first_t3 := GameData.upgrade_cost_at(base, 0, 3)
	_ok("D2 tier 3 第一級貴過 tier 2 最後一級", first_t3 > last_t2,
		"t2[14]=%d t3[0]=%d" % [last_t2, first_t3])
	_ok("D2 tier 1 嘅價錢冇變過",
		GameData.upgrade_cost_at(base, 4, 1) == GameData.upgrade_cost(base, 4),
		"tier 1 curve moved")
	# 進化費本身要隨階遞增,而且塔貴過魔法
	_ok("D2 進化費隨階遞增",
		GameData.evolve_cost(true, 3) > GameData.evolve_cost(true, 2), "")
	_ok("D2 塔嘅進化費貴過魔法",
		GameData.evolve_cost(true, 2) > GameData.evolve_cost(false, 2), "")

# ---------------------------------------------------------------------------
# 3. 數值放大
# ---------------------------------------------------------------------------
func _case_stat_scaling() -> void:
	var def := GameData.tower_by_id(1)
	var zero: Array = [0, 0, 0, 0, 0, 0]
	var maxed: Array = []
	for i in 6:
		maxed.append(GameData.MAX_UP_LV)
	var t1_base := GameData.effective_stats(def, zero, 1)
	var t1_max := GameData.effective_stats(def, maxed, 1)
	var t2_base := GameData.effective_stats(def, zero, 2)
	var t2_max := GameData.effective_stats(def, maxed, 2)
	var t3_base := GameData.effective_stats(def, zero, 3)
	# 「基礎能力大幅躍升(明顯強過 tier 1 滿課)」—— 呢句係一個可以量嘅要求
	# 第十一輪:呢兩條由「大過就得」改成一條**帶**。
	# 「大過」只擋到斷崖嘅一邊 —— 一個 3.3 倍嘅跳幅一樣過得到,而嗰個正正就係
	# 第十輪魔法嗰邊發生嘅事(見 GameData 逐階倍率嗰段)。設計目標係 1.15,
	# 所以測試要問「係咪 1.15 左右」,唔係「有冇大過 1.1」。
	var dps1_max: float = float(t1_max.dmg) * float(t1_max.rate)
	var dps2_base: float = float(t2_base.dmg) * float(t2_base.rate)
	_in_band("D3 tier 2 基礎 / tier 1 滿課", dps2_base / dps1_max, 1.05, 1.35)
	var dps2_max: float = float(t2_max.dmg) * float(t2_max.rate)
	var dps3_base: float = float(t3_base.dmg) * float(t3_base.rate)
	_in_band("D3 tier 3 基礎 / tier 2 滿課", dps3_base / dps2_max, 1.05, 1.35)
	# 魔法只得三條軸,所以佢要一個細啲嘅逐階倍率先落到同一條帶入面。
	# 呢條 assertion 就係「一個倍率服侍唔到兩邊」呢個發現嘅守門員。
	var sp := GameData.spell_by_id(4)          # 劇毒瘴氣
	var sp_zero: Array = [0, 0, 0]
	var sp_max: Array = [GameData.MAX_UP_LV, GameData.MAX_UP_LV, GameData.MAX_UP_LV]
	_in_band("D3 魔法 tier 2 基礎 / tier 1 滿課",
		float(GameData.effective_stats(sp, sp_zero, 2).dps)
			/ float(GameData.effective_stats(sp, sp_max, 1).dps), 1.05, 1.35)
	# 射程唔跟 tier 放大 —— 一座 tier 3 塔唔應該打得晒成張地圖
	_near("D3 射程唔跟階放大", float(t3_base.range), float(t1_base.range), 0.001)
	# 步長要一齊放大,唔係六條軸就變裝飾
	var gain1: float = float(t1_max.dmg) - float(t1_base.dmg)
	var gain2: float = float(t2_max.dmg) - float(t2_base.dmg)
	_ok("D3 升級步長跟階放大", gain2 > gain1 * 5.0,
		"t1 gain=%.0f t2 gain=%.0f" % [gain1, gain2])
	# 機率封頂 1.0,唔會因為進化就變成必定觸發
	_ok("D3 機率唔跟階放大", float(t3_base.get("crit", 0.0)) <= 1.0,
		"crit=%.3f" % float(t3_base.get("crit", 0.0)))

# ---------------------------------------------------------------------------
# 4. 交易
# ---------------------------------------------------------------------------
func _case_evolve_transaction() -> void:
	Meta.tower_up.clear()
	Meta.tower_tiers.clear()
	Meta.crystals = 0
	_ok("D4 新存檔全部第一階", Meta.tower_tier(1) == 1, "tier=%d" % Meta.tower_tier(1))
	_ok("D4 軸未滿唔可以進化", not Meta.can_evolve(1, true), "can_evolve true")
	_ok("D4 軸未滿嘅進化被拒", not Meta.evolve(1, true), "evolve succeeded")
	# 課滿六軸
	var lv: Array = []
	for i in 6:
		lv.append(GameData.MAX_UP_LV)
	Meta.tower_up["1"] = lv.duplicate()
	_ok("D4 六軸全滿", Meta.all_axes_maxed(1, true), "not maxed")
	_ok("D4 全滿就符合進化條件", Meta.can_evolve(1, true), "cannot evolve")
	# 錢唔夠一樣要拒,而且一蚊都唔准扣
	Meta.crystals = GameData.evolve_cost(true, 2) - 1
	var before: int = Meta.crystals
	_ok("D4 錢唔夠嘅進化被拒", not Meta.evolve(1, true), "evolve succeeded")
	_ok("D4 被拒嘅進化冇扣過錢", Meta.crystals == before,
		"%d -> %d" % [before, Meta.crystals])
	_ok("D4 被拒之後階級冇郁", Meta.tower_tier(1) == 1, "tier moved")
	# 成功
	var cost: int = GameData.evolve_cost(true, 2)
	Meta.crystals = cost + 500
	_ok("D4 條件同錢都夠就進化得到", Meta.evolve(1, true), "evolve failed")
	_ok("D4 階級升咗", Meta.tower_tier(1) == 2, "tier=%d" % Meta.tower_tier(1))
	_ok("D4 扣咗啱嘅錢", Meta.crystals == 500, "crystals=%d" % Meta.crystals)
	# 升級軸歸零但唔退錢 —— 退錢會令進化變成一個免費 respec
	var levels: Array = Meta.tower_levels(1)
	var all_zero := true
	for v in levels:
		if int(v) != 0:
			all_zero = false
	_ok("D4 升級軸重開由 0 起", all_zero, str(levels))
	_ok("D4 進化之後又要重新課滿先再進化", not Meta.can_evolve(1, true), "can evolve again")
	# 第三階
	Meta.tower_up["1"] = lv.duplicate()
	Meta.crystals = GameData.evolve_cost(true, 3)
	_ok("D4 進到第三階", Meta.evolve(1, true) and Meta.tower_tier(1) == 3,
		"tier=%d" % Meta.tower_tier(1))
	Meta.tower_up["1"] = lv.duplicate()
	Meta.crystals = 9999999
	_ok("D4 第三階係最高", not Meta.can_evolve(1, true), "can evolve past max")
	_ok("D4 超階嘅進化被拒", not Meta.evolve(1, true), "evolved past max")

func _case_save_roundtrip() -> void:
	Meta.save_game()
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()
	Meta.load_game()
	_ok("D5 階級存得住", Meta.tower_tier(1) == 3, "tier=%d" % Meta.tower_tier(1))
	# 一份完全冇呢個欄位嘅舊存檔 —— 無痛,全部第一階
	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.READ)
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	d.erase("tower_tiers")
	d.erase("spell_tiers")
	f = FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	Meta.load_game()
	_ok("D5 舊存檔冇欄位就係全部第一階", Meta.tower_tier(1) == 1 and Meta.spell_tier(1) == 1,
		"tower=%d spell=%d" % [Meta.tower_tier(1), Meta.spell_tier(1)])
	# 手改到離譜嘅值要 clamp,唔可以攞到一張根本冇畫過嘅 sprite
	d["tower_tiers"] = {"1": 9, "2": -3}
	f = FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	Meta.load_game()
	_ok("D5 離譜嘅階級被夾返合法範圍",
		Meta.tower_tier(1) == GameData.MAX_TIER and Meta.tower_tier(2) == 1,
		"1=%d 2=%d" % [Meta.tower_tier(1), Meta.tower_tier(2)])

# ---------------------------------------------------------------------------
# 5. 全部第三階打一場
# ---------------------------------------------------------------------------
func _case_tier3_battle() -> void:
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 3
	for id in range(1, 16):
		Meta.spell_tiers[str(id)] = 3
	Flow.selected_level = 12
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	Engine.time_scale = 1.0
	b.gold = 9999999
	b.base_shield = 999999
	var TowerScript := load("res://scripts/battle/Tower.gd")
	for i in 20:
		var t = TowerScript.new()
		b.towers_root.add_child(t)
		t.setup(b, i + 1, Vector2(140 + (i % 5) * 190, 320 + (i / 5) * 200))
		b.towers.append(t)
		match t.mech:
			"alchemy": b.alchemy_towers.append(t)
			"holy": b.holy_towers.append(t)
			"curse": b.curse_towers.append(t)
	_ok("D6 二十座第三階塔擺得晒", b.towers.size() == 20, "%d towers" % b.towers.size())
	var placed_tier3 := true
	for t in b.towers:
		if t.tier != 3:
			placed_tier3 = false
	_ok("D6 場上嘅塔真係按階出貨", placed_tier3, "a tower came out at the wrong tier")
	for fam in GameData.FAMILY_ORDER:
		b._spawn_monster(fam, 4, false, 100.0)
		b._spawn_monster(fam, 2, false, 300.0)
	var boss = b._spawn_monster("cultist", 5, true, 200.0)
	boss.max_hp = 1.0e12
	boss.hp = 1.0e12
	# 每個第三階魔法都要放得出,而且唔准爆
	for sid in range(1, 16):
		Spells.cast(b, sid, Vector2(randf_range(200, 900), randf_range(400, 1400)))
		_step(b, 0.05)
	for i in 240:
		_step(b, 1.0 / 60.0)
	_ok("D6 第三階打完一輪冇死", is_instance_valid(b) and not b.ended,
		"ended=%s" % str(b.ended))
	_ok("D6 第三階真係打得死嘢", b.kills > 0, "kills=%d" % b.kills)
	b.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# 6. 由介面真係撳落去 —— 課滿 → 進化 → 再課 → 再進化
# ---------------------------------------------------------------------------
## 前面五個 case 全部係直接叫 Meta 嘅 API。呢個唔係:佢起返成個升級畫面,
## 喺入面搵嗰粒進化掣,emit 佢個 pressed signal,再問返 Meta 有冇變。
##
## 點解值得多寫一個:一個「Meta.evolve() 啱但個掣冇接到」嘅世界,喺前面
## 五個 case 底下係全綠嘅,而喺玩家手上係一個撳極都冇反應嘅掣。
func _case_ui_flow() -> void:
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.crystals = 9999999
	var up: Node = load("res://scenes/Upgrade.tscn").instantiate()
	add_child(up)
	await get_tree().process_frame
	up.sel_type = "tower"
	up.sel_id = 1
	# 由零課到滿,行返玩家真正嗰條路(逐級買,唔係直接寫個 Array)
	var bought := 0
	for dir in GameData.tower_by_id(1).ups.size():
		for lv in GameData.MAX_UP_LV:
			if Meta.buy_tower_upgrade(1, dir):
				bought += 1
	_ok("D7 由介面路徑逐級課滿六軸", bought == 6 * GameData.MAX_UP_LV,
		"bought %d levels" % bought)
	up._rebuild()
	await get_tree().process_frame
	for tier in [2, 3]:
		var btn := _find_evolve_button(up)
		_ok("D7 進化掣搵得到 (T%d)" % tier, btn != null, "no evolve button in the tree")
		if btn == null:
			break
		btn.emit_signal("pressed")
		await get_tree().process_frame
		_ok("D7 撳完真係升到第 %d 階" % tier, Meta.tower_tier(1) == tier,
			"tier=%d" % Meta.tower_tier(1))
		# 再課滿,行下一階
		for dir in GameData.tower_by_id(1).ups.size():
			for lv in GameData.MAX_UP_LV:
				Meta.buy_tower_upgrade(1, dir)
		_ok("D7 第 %d 階嘅軸再課得滿" % tier, Meta.all_axes_maxed(1, true), "not maxed")
		up._rebuild()
		await get_tree().process_frame
	# 滿階之後個掣要唔見咗,唔係仲喺度俾人撳
	_ok("D7 滿階之後冇進化掣", _find_evolve_button(up) == null,
		"evolve button still present at max tier")
	up.queue_free()
	await get_tree().process_frame

## 進化掣冇 name 亦冇 group —— 佢係 UI.button() 出嚟嘅裸 Button。用「掛住一個
## 寫住 EVO_BUTTON 文字嘅 Label」嚟認佢:呢個正正就係玩家用嚟認佢嗰樣嘢。
func _find_evolve_button(root: Node) -> Button:
	var want := tr("EVO_BUTTON")
	for n in _walk(root):
		if n is Button and not n.disabled:
			for c in n.get_children():
				if c is Label and c.text == want:
					return n
	return null

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out += _walk(c)
	return out

# ===========================================================================
func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("EVOLVE ok   %s" % label)
	else:
		fails += 1
		print("EVOLVE FAIL %s — %s" % [label, detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol, "got %.4f want %.4f (tol %.4f)" % [got, want, tol])

## 兩邊都有牆嘅斷言。一個「大過 X」嘅斷言只擋到一邊,而平衡出事嘅方向
## 通常係另一邊 —— 太強。
func _in_band(label: String, got: float, lo: float, hi: float) -> void:
	_ok(label, got >= lo and got <= hi, "got %.3f，要喺 %.2f..%.2f 之間" % [got, lo, hi])

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
