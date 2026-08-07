extends Node
## 塔 / 魔法美術收官輪(round 20)嘅專用截圖 harness。
##
## 影嘅嘢:
##   10_towers_t1/t2/t3  20 座塔喺**真實戰鬥尺寸**排開,逐階一張(接地 / 大細 /
##                       進化遞進一次過睇晒)
##   20_peak             高峰戰鬥全景:新怪 + 新塔 + 新魔法列同框 —— 成個美術
##                       升級嘅定案圖
##   25_evolve_*         戰鬥中進化換圖前後(同一場、同一格、同一幀距)
##   30/31_quickbar      建塔列 + 魔法列,中文 / English
##   32/33_upgrade_tower 升級介面(塔),中 / 英 —— 264px 大圖 + 進化預覽
##   34/35_upgrade_spell 升級介面(魔法),中 / 英
##   36/37_bestiary_*    圖鑑塔頁 / 魔法頁,中 / 英
##   40/41_shop          商店,中 / 英
##   50_icon44           44px 辨識度:20 塔 x 3 階 + 15 魔法 x 3 階
##
## 跑法(**一定要開窗**,headless 冇 GPU):
##   Godot --path . tools/tower_r20_shots.tscn --log-file qa/r20.log
## 完成訊號 = log 入面出現 "R20_SHOTS: DONE"。

const VW := 1080
const VH := 1920
const OUT := "res://qa/screenshots/round-20-tower-magic-art/"

var sub: SubViewport

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(420, 760))
	# 一贏 / 一輸 Flow.goto 就會換走 root scene,連 harness 都 free 埋
	Flow.nav_enabled = false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_unlock_all()
	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	await _run()
	print("R20_SHOTS: DONE")
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
	img.save_png(ProjectSettings.globalize_path(OUT) + name + ".png")
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
	# 語言由存檔嘅 settings 決定,而上一次跑呢個 harness 影英文嗰批之後
	# 就會留低 locale=en —— 唔明寫返實嘅話,「定案圖」下次跑出嚟係英文。
	TranslationServer.set_locale("zh_TW")
	await _shoot_tower_rows()
	await _shoot_peak()
	await _shoot_evolve()
	for loc in ["zh_TW", "en"]:
		await _shoot_ui(loc)
	await _shoot_icon44()
	TranslationServer.set_locale("zh_TW")

## 20 座塔逐階一張。全部擺喺同一組坐標,所以三張疊住睇就係「進化跳唔跳位」。
func _shoot_tower_rows() -> void:
	for tier in range(1, 4):
		for id in range(1, 21):
			Meta.tower_tiers[str(id)] = tier
		var b: Node = _battle(6)
		await _mount(b)
		_idle(b)
		for i in 20:
			_place(b, i + 1, Vector2(150 + (i % 4) * 260, 330 + (i / 4) * 250))
		for i in 30:
			await get_tree().process_frame
		await _grab("10_towers_t%d" % tier)
	Meta.tower_tiers.clear()

## 定案圖:新怪 + 新塔 + 新魔法列同框。
func _shoot_peak() -> void:
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 3
	for id in range(1, 16):
		Meta.spell_tiers[str(id)] = 3
	var b: Node = _battle(12)
	await _mount(b)
	_idle(b)
	var ids: Array = [18, 1, 2, 3, 5, 6, 7, 9, 10, 12, 13, 16, 17, 20, 4, 8, 11, 14, 15, 19]
	for i in ids.size():
		_place(b, int(ids[i]), Vector2(150 + (i % 4) * 250, 330 + (i / 4) * 235))
	# 塔要行足一陣先有光環 / 光柱 / 符文,但怪一放出嚟就會即刻俾廿座第三階塔
	# 秒晒(第一次跑出嚟成張圖冇怪)。所以分兩段:塔先行 90 幀,之後先放怪,
	# 再只等 8 幀 —— 夠 sprite 擺位,唔夠佢哋死。
	for i in 90:
		await get_tree().process_frame
	var total: float = b.route.total
	for i in 34:
		b._spawn_monster(GameData.FAMILY_ORDER[i % 10], 1 + i % 5, false,
			total * 0.06 + float(i) * 34.0)
	b._spawn_monster("golem", 5, true, total * 0.55)
	for i in 8:
		await get_tree().process_frame
	await _grab("20_peak")
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()

## 戰鬥中進化換圖:同一場、同一格、前後各一張。跳位 / 跳大細一比就見到。
func _shoot_evolve() -> void:
	var b: Node = _battle(8)
	await _mount(b)
	_idle(b)
	# 揀四座差異最大嘅:箭塔(細)、兵營塔(闊)、聖光塔(光柱)、荊棘塔(t3 爆框)
	var ids: Array = [1, 13, 18, 15]
	var ts: Array = []
	for i in ids.size():
		ts.append(_place(b, int(ids[i]), Vector2(230 + (i % 2) * 460, 560 + (i / 2) * 420)))
	for i in 20:
		await get_tree().process_frame
	await _grab("25_evolve_before")
	# 直接推 tier 再叫塔重新讀圖 —— 呢個就係遊戲入面進化行嘅同一條路
	for i in ids.size():
		Meta.tower_tiers[str(int(ids[i]))] = 3
		var t = ts[i]
		t.tier = 3
		t.sprite.texture = Assets.tower(int(ids[i]), 3)
	for i in 20:
		await get_tree().process_frame
	await _grab("25_evolve_after")
	Meta.tower_tiers.clear()

func _shoot_ui(loc: String) -> void:
	TranslationServer.set_locale(loc)
	# 圖鑑同進化預覽對住未擁有嘅階級係畫黑色剪影 —— 睇美術就乜都睇唔到。
	# 推到第二階:第三階仍然係「下一階預覽」,所以進化預覽嗰格照樣試到。
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 2
	for id in range(1, 16):
		Meta.spell_tiers[str(id)] = 2
	var p: String = "30" if loc == "zh_TW" else "31"
	# --- 建塔列 / 魔法列(戰鬥 HUD)---
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

	# --- 升級介面:塔 + 魔法 ---
	for kind in [["tower", 18, "32" if loc == "zh_TW" else "33"],
			["spell", 11, "34" if loc == "zh_TW" else "35"]]:
		var u: Node = load("res://scenes/Upgrade.tscn").instantiate()
		await _mount(u)
		u.sel_type = String(kind[0])
		u.sel_id = int(kind[1])
		u._rebuild()
		for i in 8:
			await get_tree().process_frame
		await _grab("%s_upgrade_%s_%s" % [String(kind[2]), String(kind[0]), loc])

	# --- 圖鑑:塔頁 + 魔法頁 ---
	for tab in ["tower", "spell"]:
		var g: Node = load("res://scenes/Bestiary.tscn").instantiate()
		await _mount(g)
		g._switch_tab(tab)
		for i in 8:
			await get_tree().process_frame
		await _grab("%s_bestiary_%s_%s" % ["36" if loc == "zh_TW" else "37", tab, loc])

	# --- 商店 ---
	var sh: Node = load("res://scenes/Shop.tscn").instantiate()
	await _mount(sh)
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_shop_%s" % ["40" if loc == "zh_TW" else "41", loc])
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()

## 44px 辨識度 —— 縮到卡片圖示嗰個尺寸,一次過睇 60 塔 + 45 魔法認唔認得出。
func _shoot_icon44() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.16, 0.14, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	for tier in range(1, 4):
		for id in range(1, 21):
			var ic := UI.tex_rect(Assets.tower(id, tier), Vector2(44, 44), true)
			ic.position = Vector2(30 + ((id - 1) % 10) * 100 + (tier - 1) * 0,
				60 + (tier - 1) * 220 + ((id - 1) / 10) * 92)
			root.add_child(ic)
	for tier in range(1, 4):
		for id in range(1, 16):
			var ic := UI.tex_rect(Assets.spell(id, tier), Vector2(44, 44), true)
			ic.position = Vector2(30 + ((id - 1) % 10) * 100,
				760 + (tier - 1) * 190 + ((id - 1) / 10) * 92)
			root.add_child(ic)
	for i in 3:
		var l := UI.label(["塔 t1", "塔 t2", "塔 t3"][i], 26, Color(1, 0.9, 0.5))
		l.position = Vector2(30, 30 + i * 220)
		root.add_child(l)
	for i in 3:
		var l := UI.label(["魔法 t1", "魔法 t2", "魔法 t3"][i], 26, Color(1, 0.9, 0.5))
		l.position = Vector2(30, 730 + i * 190)
		root.add_child(l)
	await _mount(root)
	for i in 8:
		await get_tree().process_frame
	await _grab("50_icon44")
