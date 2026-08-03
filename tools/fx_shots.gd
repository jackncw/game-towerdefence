extends Node
## 合批輪嘅**外觀對照**harness。
##
## 呢一輪改嘅全部係「點樣畫」,所以驗收唔可以只係 draw call 跌咗幾多 ——
## 要證明畫出嚟一模一樣。呢個 harness 喺一個 1080x1920 嘅 SubViewport 入面
## 砌一堆**確定性**嘅畫面(固定 seed、固定機位、手動逐幀推進),逐張影低。
## 改造前後各跑一次,再逐像素比。
##
## 手動推進係關鍵:`get_tree().paused = true` 之後自己叫每個 node 嘅
## `_process(1/60)`,咁樣「第 12 幀」喺兩個 build 入面係同一個 12 幀,同
## 實際幀率無關。動畫類(符文旋轉、光點繞行、fx 生命周期)就係靠連續幾幀
## 嘅截圖去比,唔係淨係比一張靜態圖。
##
## 用法(要開窗,要 GPU):
##   Godot --path . tools/fx_shots.tscn -- --out=qa/screenshots/round-14-batching/after

const VW := 1080
const VH := 1920
const DT := 1.0 / 60.0

var sub: SubViewport
var outdir := "res://qa/screenshots/round-14-batching/shots/"
var battle = null

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = "res://" + a.substr(6).rstrip("/") + "/"
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.tower_tiers = {}
	Meta.spell_tiers = {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		push_warning("fx_shots timed out"); get_tree().quit(2))

	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	get_tree().paused = true

	await _shot_curse()
	await _shot_holy()
	await _shot_fx("ring")
	await _shot_fx("burst")
	await _shot_fx("orb")
	await _shot_fx("spark")
	await _shot_fx("line")
	await _shot_monsters()
	await _shot_damage()
	await _shot_sprites()
	await _shot_battle()
	print("FXSHOTS DONE")
	get_tree().quit(0)

# ---------------------------------------------------------------------------
func _fresh(zoom := 1.0, centre := Vector2(540, 960)) -> void:
	if battle != null:
		battle.queue_free()
		battle = null
		await get_tree().process_frame
	seed(4242)
	Flow.selected_level = 5
	battle = load(Flow.BATTLE).instantiate()
	battle.process_mode = Node.PROCESS_MODE_PAUSABLE
	sub.add_child(battle)
	await get_tree().process_frame
	battle.gold = 999999
	battle.boss_time = 1.0e9
	battle.base_shield = 1000000
	battle.spawn_timer = 1.0e9
	battle.cam.position = centre
	battle.cam.zoom = Vector2(zoom, zoom)
	if battle.hud != null:
		battle.hud.visible = false

## 一幀。個 tree 係 paused 嘅,所以要自己叫 —— 咁「第 N 幀」喺改造前後嘅
## build 入面係同一件事。
func _tick(n: int) -> void:
	for i in n:
		battle._process(DT)
		for root in [battle.towers_root, battle.monsters_root, battle.proj_root, battle.fx_root]:
			for c in root.get_children():
				if c.has_method("_process"):
					c._process(DT)
		# 合批輪新加嘅渲染 node。改造之前呢三個唔存在,所以要問過先叫 ——
		# 同一個 harness 檔要喺兩個 build 度都跑得。
		for key in ["fx_render", "mon_overlay", "dmg_field"]:
			if key in battle and battle.get(key) != null:
				battle.get(key)._process(DT)
		await get_tree().process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	img.save_png(outdir + name + ".png")
	print("FXSHOT %s" % name)

# ---------------------------------------------------------------------------
## 詛咒塔符文陣:一座塔近鏡,影連續三幀相隔半秒 —— 符文陣兩圈係反方向轉、
## 外環同符文係脈動嘅、金點係向上飄,靜態一張圖驗唔到嗰啲。
func _shot_curse() -> void:
	await _fresh(2.0, Vector2(400, 700))
	battle.place_tower(17, battle.snap(Vector2(400, 700)))
	for i in 3:
		await _tick(30 if i > 0 else 2)
		await _snap("curse_%d" % i)

## 聖光塔本體(光柱)+ 三座受惠嘅鄰居(繞行光點)。
func _shot_holy() -> void:
	await _fresh(1.6, Vector2(480, 760))
	battle.place_tower(18, battle.snap(Vector2(400, 700)))
	battle.place_tower(1, battle.snap(Vector2(560, 700)))
	battle.place_tower(2, battle.snap(Vector2(400, 850)))
	battle.place_tower(5, battle.snap(Vector2(560, 850)))
	for i in 3:
		await _tick(24 if i > 0 else 2)
		await _snap("holy_%d" % i)

## 逐種 fx。每種喺三個固定位置放三個唔同顏色 / 半徑,再喺生命周期嘅
## 三個時點影 —— 因為每種 fx 嘅樣係跟住壽命變嘅。
func _shot_fx(kind: String) -> void:
	await _fresh(1.0, Vector2(540, 960))
	var cols := [Color(1, 0.55, 0.2), Color(0.5, 0.9, 1.0), Color(0.7, 0.4, 0.95)]
	var pos := [Vector2(300, 600), Vector2(760, 900), Vector2(400, 1300)]
	for i in 3:
		match kind:
			"ring": battle.spawn_fx_ring_dur(pos[i], 90.0 + i * 60.0, cols[i], 1.6)
			"burst": battle.spawn_fx_burst(pos[i], 80.0 + i * 55.0, cols[i], 1.6)
			"orb": battle.spawn_fx_orb(pos[i], cols[i])
			"spark": battle.spawn_sparks(pos[i], 14, cols[i], 220.0, 7.0, 1.6)
			"line": battle.spawn_line(PackedVector2Array([pos[i] - Vector2(200, 160),
				pos[i], pos[i] + Vector2(190, 120)]), cols[i], 3.0 + i * 3.0, 1.6)
	for f in 3:
		await _tick(16 if f > 0 else 4)
		await _snap("fx_%s_%d" % [kind, f])

## 怪物身上嘅資訊層:血條(三個唔同血量)、詛咒印、詠唱環。
func _shot_monsters() -> void:
	await _fresh(1.4, Vector2(540, 900))
	var fams := ["goblin", "skeleton", "golem", "cultist", "bat", "slime"]
	for i in 6:
		battle._spawn_monster(fams[i], 1 + i % 5, false, 260.0 + i * 130.0)
	await _tick(2)
	var k := 0
	for m in battle.monsters:
		m.hp = m.max_hp * [1.0, 0.75, 0.45, 0.2, 0.9, 0.55][k % 6]
		if k % 2 == 0:
			m.curse_amp = 0.4
			m.curse_time = 99.0
		k += 1
	for f in 2:
		await _tick(10 if f > 0 else 1)
		await _snap("monsters_%d" % f)

## 傷害數字(普通 / 大字 / 治療綠字),影彈出中同埋落定兩個時點。
func _shot_damage() -> void:
	await _fresh(1.0, Vector2(540, 960))
	for i in 12:
		battle.spawn_damage(Vector2(260 + (i % 4) * 190, 620 + (i / 4) * 240),
			120 + i * 37, Color(1, 0.9, 0.5), i % 3 == 0)
	for i in 4:
		battle.spawn_damage(Vector2(300 + i * 160, 1400), 90 + i * 11,
			Color(0.55, 1.0, 0.5), false, "+")
	for f in 3:
		await _tick(4 if f > 0 else 1)
		await _snap("damage_%d" % f)

## Atlas 抽樣:每一類 sprite 各幾件排成格,用嚟逐像素驗證入 atlas 之後
## 冇滲色、冇偏移、冇縮放差。
func _shot_sprites() -> void:
	await _fresh(1.0, Vector2(540, 960))
	var layer := Node2D.new()
	layer.z_index = 90
	battle.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.09, 0.12)
	bg.size = Vector2(VW, VH)
	bg.position = Vector2(0, 0)
	bg.z_index = -1
	layer.add_child(bg)
	var items: Array = []
	for fam in ["goblin", "wolf", "skeleton", "golem", "ghost", "bat", "treant", "beetle", "cultist", "slime"]:
		items.append(Assets.monster(fam, 3))
	for fam in ["goblin", "golem", "cultist"]:
		items.append(Assets.monster_boss(fam))
	for id in [1, 5, 9, 13, 17, 20]:
		items.append(Assets.tower(id))
	for id in [1, 4, 8, 12, 15]:
		items.append(Assets.spell(id))
	for t in ["deco_rock1", "deco_bones", "deco_grass", "portal"]:
		items.append(Assets.tile(t))
	for u in ["coin", "crystal", "soldier", "militia", "ic_pause", "ic_skull"]:
		items.append(Assets.ui(u))
	var i := 0
	for tex in items:
		var s := Sprite2D.new()
		s.texture = tex
		s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s.scale = Vector2(2, 2)      # 整數倍,同遊戲入面嘅像素密度規則一致
		s.position = Vector2(120 + (i % 5) * 210, 260 + (i / 5) * 210)
		layer.add_child(s)
		i += 1
	await _tick(2)
	await _snap("sprites")

## 高峰戰鬥全景 —— 肉眼一致嘅那一張。
func _shot_battle() -> void:
	await _fresh(1.0, Vector2(540, 960))
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 17, 18, 11, 19]
	var k := 0
	for gx in range(2, 13):
		for gy in range(5, 20):
			var p: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(p):
				battle.place_tower(ids[k % ids.size()], p)
				k += 1
	for i in 60:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()],
			1 + i % 5, false, 120.0 + i * 26.0)
	if battle.hud != null:
		battle.hud.visible = true
	await _tick(90)
	await _snap("battle_full")
	await _tick(20)
	await _snap("battle_full_b")
