extends Node
## 怪物美術輪(round 19)嘅專用截圖 harness。
##
## 影嘅嘢:
##   10_<族>       每一族 lv1..5 + boss 喺**真實戰鬥尺寸**行緊路(縮細辨識度)
##   20_peak       高峰戰鬥全景:新怪 + 現有塔 + HUD 同場(整體風格協調感)
##   21_elite      精英 affix 嘅 tint / 放大喺新圖上面睇唔睇得清
##   30/31_bestiary 圖鑑怪物頁,中文 + English
##   32/33_bestiary_detail 圖鑑詳情頁(大頭像),中文 + English
##
## 跑法(**一定要開窗**,headless 冇 GPU):
##   Godot --path . tools/mon_r19_shots.tscn --log-file qa/r19.log
## 完成訊號 = log 入面出現 "R19_SHOTS: DONE"(GUI Godot 唔會 print 返落 console)。

const VW := 1080
const VH := 1920
const OUT := "res://qa/screenshots/round-19-monster-art/"

var sub: SubViewport
var done := false

func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(420, 760))
	# 一贏 / 一輸 Flow.goto 就會換走 root scene,連 harness 都 free 埋,
	# 跟住成串 await 喺一個已經 free 咗嘅 node 上面炒(踩過:第二次跑
	# _shoot_elite 中途爆 "data.tree is null" 之後剩返嗰幾張影唔到)。
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
	done = true
	print("R19_SHOTS: DONE")
	get_tree().quit()

func _unlock_all() -> void:
	Meta.highest_level = 20
	Meta.crystals = 9000
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
	var b: Node = load("res://scenes/Battle.tscn").instantiate()
	return b

func _run() -> void:
	await _shoot_families()
	await _shoot_peak()
	await _shoot_elite()
	await _shoot_bestiary("zh_TW", "30")
	await _shoot_bestiary("en", "31")

## 每族一張:同一條路上面擺 lv1→lv5→boss,大細級數同接地感一次過睇晒。
func _shoot_families() -> void:
	for fam in GameData.FAMILY_ORDER:
		var b: Node = _battle(6)
		await _mount(b)
		b.gold = 999999
		b.base_shield = 999999
		b.boss_time = 1.0e9
		var total: float = b.route.total
		for lv in range(1, 6):
			b._spawn_monster(fam, lv, false, total * (0.10 + 0.115 * float(lv - 1)))
		b._spawn_monster(fam, 5, true, total * 0.68)
		for i in 40:
			await get_tree().process_frame
		await _grab("10_%s" % fam)

## 高峰戰鬥:塔 + 怪 + HUD 同場,睇整體風格夾唔夾。
func _shoot_peak() -> void:
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 2
	var b: Node = _battle(12)
	await _mount(b)
	b.gold = 9999999
	b.base_shield = 999999
	b.boss_time = 1.0e9
	var TowerScript := load("res://scripts/battle/Tower.gd")
	var ids: Array = [18, 1, 2, 3, 5, 6, 7, 9, 10, 12, 13, 16, 17, 20, 4, 8]
	for i in ids.size():
		var t = TowerScript.new()
		b.towers_root.add_child(t)
		t.setup(b, int(ids[i]), Vector2(150 + (i % 4) * 250, 340 + (i / 4) * 250))
		b.towers.append(t)
		match t.mech:
			"alchemy": b.alchemy_towers.append(t)
			"holy": b.holy_towers.append(t)
			"curse": b.curse_towers.append(t)
	var total: float = b.route.total
	for i in 34:
		var fam: String = GameData.FAMILY_ORDER[i % 10]
		b._spawn_monster(fam, 1 + i % 5, false, total * 0.06 + float(i) * 34.0)
	b._spawn_monster("golem", 5, true, total * 0.55)
	for i in 100:
		await get_tree().process_frame
	await _grab("20_peak")
	Meta.tower_tiers.clear()

## 精英 affix:tint + 放大喺新圖上面仲睇唔睇得出。
func _shoot_elite() -> void:
	var b: Node = _battle(8)
	await _mount(b)
	b.gold = 999999
	b.base_shield = 999999
	b.boss_time = 1.0e9
	var total: float = b.route.total
	# 每一個 affix 影一隻,再夾一隻冇 affix 嘅同族做對照 —— 「睇唔睇得清」
	# 呢個問題冇對照組係答唔到嘅。
	var fams: Array = ["goblin", "skeleton", "beetle", "slime"]
	for i in GameData.ELITE_AFFIXES.size():
		var af: Dictionary = GameData.ELITE_AFFIXES[i]
		var m = b._spawn_monster(String(fams[i % fams.size()]), 4, false,
			total * (0.10 + 0.13 * i))
		if m != null:
			m.apply_mods({"elite_id": String(af["id"]), "tint": af["tint"],
				"hp": af["hp"] - 1.0})
	for i in fams.size():
		b._spawn_monster(String(fams[i]), 4, false, total * (0.10 + 0.13 * i) + 62.0)
	for i in 40:
		await get_tree().process_frame
	await _grab("21_elite")

func _shoot_bestiary(loc: String, prefix: String) -> void:
	TranslationServer.set_locale(loc)
	var b: Node = load("res://scenes/Bestiary.tscn").instantiate()
	await _mount(b)
	if b.has_method("_switch_tab"):
		b._switch_tab("monster")
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_bestiary_%s" % [prefix, loc])
	# 詳情頁大頭像:揀一隻 boss(最大張圖,最容易爆版)
	b.fam_idx = GameData.FAMILY_ORDER.find("treant")
	b.sel_slot = 5
	if b.has_method("_rebuild"):
		b._rebuild()
	for i in 8:
		await get_tree().process_frame
	await _grab("%s_bestiary_detail_%s" % [str(int(prefix) + 2), loc])
	TranslationServer.set_locale("zh_TW")
