extends Node
## 收官輪(round 21)嘅截圖 harness。同 round-20 嗰個分別係:
##   * 影得到**圖鑑怪物頁**(round-20 只影塔頁 / 魔法頁)—— Part B 嘅前後對比
##   * 魔法列 / 商店 / 升級 / 進化預覽全部指定落新補嘅四格(龍捲風 / 地震術 /
##     烈焰之牆),唔係隨機一件
##   * 輸出資料夾由 `--out=<name>` 決定,所以同一支 harness 可以行「改之前」
##     同「改之後」兩次,出兩個可以逐張疊嘅資料夾
##
## 跑法(**一定要開窗**,headless 冇 GPU):
##   Godot --path . tools/r21_shots.tscn --log-file qa/r21_before.log -- --out=before
## 完成訊號 = log 入面出現 "R21_SHOTS: DONE"。

const VW := 1080
const VH := 1920
const BASE := "res://qa/screenshots/round-21-cleanup/"

var sub: SubViewport
var out_dir: String = BASE + "after/"

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(420, 760))
	Flow.nav_enabled = false
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = BASE + String(a).substr(6) + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	_unlock_all()
	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	await _run()
	print("R21_SHOTS: DONE")
	get_tree().quit()

func _unlock_all() -> void:
	Meta.highest_level = 40
	Meta.crystals = 999999
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.seen = {}
	for f in GameData.FAMILY_ORDER:
		for lv in range(1, 6):
			Meta.seen["%s_%d" % [f, lv]] = true
		Meta.seen["%s_boss" % f] = true

func _save(img: Image, name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(out_dir) + name + ".png")
	print("EXPORT ", name, " ", img.get_size())

func _grab(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_save(sub.get_texture().get_image(), name)

func _mount(node: Node) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 4:
		await get_tree().process_frame

func _battle(level: int) -> Node:
	Flow.selected_level = level
	return load("res://scenes/Battle.tscn").instantiate()

func _idle(b: Node) -> void:
	b.gold = 9999999
	b.base_shield = 999999
	b.boss_time = 1.0e9

func _place(b: Node, id: int, pos: Vector2) -> Object:
	var t = load("res://scripts/battle/Tower.gd").new()
	b.towers_root.add_child(t)
	t.setup(b, id, pos)
	b.towers.append(t)
	match t.mech:
		"alchemy": b.alchemy_towers.append(t)
		"holy": b.holy_towers.append(t)
		"curse": b.curse_towers.append(t)
	return t

func _run() -> void:
	TranslationServer.set_locale("zh_TW")
	await _shoot_bestiary_monsters()
	for loc in ["zh_TW", "en"]:
		await _shoot_ui(loc)
	await _shoot_icon44()
	TranslationServer.set_locale("zh_TW")

## Part B 嘅前後對比:圖鑑怪物頁。格仔頭像(:428)同大圖(:465)同一張入面。
## 三族各一張 —— 挑非整數縮放最明顯嗰幾隻(boss 大圖 270px、lv5 細圖)。
func _shoot_bestiary_monsters() -> void:
	var fams: Array = GameData.FAMILY_ORDER
	for pick in [[0, 5], [3, 4], [7, 0]]:
		var g: Node = load("res://scenes/Bestiary.tscn").instantiate()
		await _mount(g)
		g.tab = "monster"
		g.fam_idx = int(pick[0])
		g.sel_slot = int(pick[1])
		g._rebuild()
		for i in 8:
			await get_tree().process_frame
		await _grab("05_bestiary_mon_%s_slot%d" % [String(fams[int(pick[0])]), int(pick[1])])

func _shoot_ui(loc: String) -> void:
	TranslationServer.set_locale(loc)
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 2
	for id in range(1, 16):
		Meta.spell_tiers[str(id)] = 2
	var p: String = "30" if loc == "zh_TW" else "31"

	# --- 戰鬥魔法列(全 15 個魔法都喺列入面)---
	var b: Node = _battle(12)
	await _mount(b)
	_idle(b)
	for i in 8:
		_place(b, i + 1, Vector2(180 + (i % 4) * 250, 380 + (i / 4) * 250))
	var total: float = b.route.total
	for i in 12:
		b._spawn_monster(GameData.FAMILY_ORDER[i % 10], 3, false,
			total * 0.10 + float(i) * 60.0)
	for i in 40:
		await get_tree().process_frame
	await _grab("%s_quickbar_%s" % [p, loc])

	# --- 升級介面:新補嗰三件魔法。第二階 -> 第三階預覽,所以新圖前後都見到 ---
	for kind in [[10, "龍捲風"], [11, "地震術"], [12, "烈焰之牆"]]:
		var u: Node = load("res://scenes/Upgrade.tscn").instantiate()
		await _mount(u)
		u.sel_type = "spell"
		u.sel_id = int(kind[0])
		u._rebuild()
		for i in 8:
			await get_tree().process_frame
		await _grab("%s_upgrade_spell%d_%s" % [
			"32" if loc == "zh_TW" else "33", int(kind[0]), loc])

	# --- 升級介面第一階(睇 t1 -> t2 預覽,地震術 t1/t2 兩張新圖同框)---
	Meta.spell_tiers["11"] = 1
	var u1: Node = load("res://scenes/Upgrade.tscn").instantiate()
	await _mount(u1)
	u1.sel_type = "spell"
	u1.sel_id = 11
	u1._rebuild()
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_upgrade_spell11_t1_%s" % ["32" if loc == "zh_TW" else "33", loc])
	Meta.spell_tiers["11"] = 2

	# --- 圖鑑魔法頁 ---
	var g: Node = load("res://scenes/Bestiary.tscn").instantiate()
	await _mount(g)
	g._switch_tab("spell")
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_bestiary_spell_%s" % ["36" if loc == "zh_TW" else "37", loc])

	# --- 商店 ---
	var sh: Node = load("res://scenes/Shop.tscn").instantiate()
	await _mount(sh)
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_shop_%s" % ["40" if loc == "zh_TW" else "41", loc])
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()

## 44px 辨識度 —— 45 個魔法 icon 一次過睇認唔認得出。
func _shoot_icon44() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.14, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for tier in range(1, 4):
		for id in range(1, 16):
			var ic := UI.tex_rect(Assets.spell(id, tier), Vector2(44, 44), true)
			ic.position = Vector2(30 + ((id - 1) % 8) * 100,
				120 + (tier - 1) * 260 + ((id - 1) / 8) * 110)
			root.add_child(ic)
	for i in 3:
		var l := UI.label(["魔法 t1", "魔法 t2", "魔法 t3"][i], 30, Color(1, 0.9, 0.5))
		l.position = Vector2(30, 80 + i * 260)
		root.add_child(l)
	# 新補嗰四格放大到 88px 再睇一次(卡片實際尺寸)
	var picks: Array = [[10, 3], [11, 1], [11, 2], [12, 3]]
	for i in picks.size():
		var pk: Array = picks[i]
		var ic := UI.tex_rect(Assets.spell(int(pk[0]), int(pk[1])), Vector2(88, 88), true)
		ic.position = Vector2(60 + i * 240, 960)
		root.add_child(ic)
	var l2 := UI.label("新補四格 @88px", 30, Color(1, 0.9, 0.5))
	l2.position = Vector2(30, 910)
	root.add_child(l2)
	await _mount(root)
	for i in 8:
		await get_tree().process_frame
	await _grab("50_icon44")
