extends Node
## Art-export / self-review pipeline (round 5 — full-game audit).
## Renders every game screen + every asset gallery to an output dir at full
## 1080x1920 via a SubViewport, then quits. Run windowed (needs a GPU):
##   Godot --path . tools/art_export.tscn -- --out=r5_before
## 輸出永遠喺 res://qa/ 之下(見 QA_ROOT),`--out=` 淨係揀個仔目錄名。
## The SubViewport gives exact resolution regardless of the OS window size.

const VW := 1080
const VH := 1920
const UPG_PATH := "res://scripts/ui/Upgrade.gd"

## 每一輪嘅 QA 截圖統一落喺呢個 parent 之下,`--out=` 傳咩名都好。
##
## 理由唔係整齊。Web export preset 用 export_filter="all_resources",排除表係
## 一份人手維護嘅目錄名單 —— 而人手名單漏咗兩次:round 9 export 出嚟嘅
## docs/index.pck 有 58.5MB,入面 50MB 係 art_r8_*/art_r9*/heal_shots 嘅 QA
## 截圖,每個 GitHub Pages 訪客開場前都要落載一次。一個固定 parent 換到一條
## `qa/*` 排除規則,之後開幾多個新目錄都自動喺遊戲外面,唔使有人記得去改個表。
const QA_ROOT := "res://qa/"

## 無論 `--out=` 傳咩入嚟,都拉返入 QA_ROOT 之下。已經喺 qa/ 入面就唔郁。
static func qa_dir(out: String) -> String:
	var p: String = out.replace("\\", "/").trim_prefix("res://").trim_prefix("/")
	if not p.ends_with("/"):
		p += "/"
	if p.begins_with("qa/"):
		return "res://" + p
	return QA_ROOT + p

var OUTDIR := QA_ROOT + "art_export/"
var sub: SubViewport
var done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			OUTDIR = qa_dir(a.substr(6))
		elif a.begins_with("--locale="):
			# shoot the whole game in one language: --locale=en / --locale=zh_TW
			TranslationServer.set_locale(a.substr(9))
	if not OUTDIR.ends_with("/"):
		OUTDIR += "/"
	# safety: never hang a CI/local run
	get_tree().create_timer(900.0).timeout.connect(func():
		if not done:
			push_warning("art_export timed out")
			get_tree().quit())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	print("ART_EXPORT: out=", OUTDIR)

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
	print("ART_EXPORT: DONE")
	get_tree().quit()

func _unlock_all() -> void:
	Meta.highest_level = 5
	Meta.cleared = {"1": true, "2": true, "3": true, "4": true, "5": true}
	Meta.crystals = 4200
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	# seen keys are "<fam>_<lvl>" / "<fam>_boss" (Meta.seen_key) — the old exporter
	# wrote "fam_1_<f>", which matched nothing, so the bestiary always shot locked.
	Meta.seen = {}
	for f in GameData.FAMILY_ORDER:
		for lv in range(1, 6):
			Meta.seen["%s_%d" % [f, lv]] = true
		Meta.seen["%s_boss" % f] = true
	Flow.last_result = {"win": true, "level": 3, "kills": 48, "crystals": 130,
		"base": 60, "first": 70, "replay": false}
	# 快捷列六格全滿 —— 最迫嘅底欄佈局(15 魔法 + 6 塔槽 + 更多掣)先係要驗嘅
	# 嗰個狀態,四座初始塔加兩個空格證明唔到乜
	Meta.quick_slots = [1, 2, 5, 13, 7, 9]

# --- capture helpers --------------------------------------------------------
func _save(img: Image, name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUTDIR) + name + ".png")
	print("EXPORT ", name, " ", img.get_size())

func _grab_img() -> Image:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return sub.get_texture().get_image()

func _grab(name: String) -> void:
	var img: Image = await _grab_img()
	_save(img, name)

func _mount(node: Node) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 4:
		await get_tree().process_frame

func _shoot_scene(path: String, name: String) -> void:
	var inst: Node = load(path).instantiate()
	await _mount(inst)
	await _grab(name)

## Scale an image by a float factor (lanczos for downscale readability).
func _scaled(img: Image, f: float) -> Image:
	var c := img.duplicate()
	c.resize(int(img.get_width() * f), int(img.get_height() * f), Image.INTERPOLATE_LANCZOS)
	return c

# ---------------------------------------------------------------------------
func _run() -> void:
	await _shoot_scene("res://scenes/MainMenu.tscn", "01_menu")
	await _shoot_scene("res://scenes/LevelSelect.tscn", "11_levelselect")
	await _shoot_battle_states()
	await _shoot_bottom_bar()
	await _shoot_militia()
	await _shoot_spell_casts()
	await _shoot_curse_aura()
	await _shoot_scene("res://scenes/Shop.tscn", "05_shop")
	# the all-unlocked shop shows nothing but 已擁有 buttons — shoot a locked one
	# too, which is the only state where the PRICE row is on screen
	var keep_t: Array = Meta.unlocked_towers.duplicate()
	var keep_s: Array = Meta.unlocked_spells.duplicate()
	Meta.unlocked_towers = [1, 2, 5, 13]
	Meta.unlocked_spells = [1]
	await _shoot_scene("res://scenes/Shop.tscn", "05b_shop_locked")
	Meta.unlocked_towers = keep_t
	Meta.unlocked_spells = keep_s
	await _shoot_upgrades()
	await _shoot_mech_sheet()
	await _shoot_scene("res://scenes/Gallery.tscn", "07_gallery")
	# bestiary: unlocked (all seen) then fully locked
	await _shoot_scene("res://scenes/Bestiary.tscn", "08_bestiary_unlocked")
	var keep_seen: Dictionary = Meta.seen.duplicate()
	Meta.seen = {}
	await _shoot_scene("res://scenes/Bestiary.tscn", "08b_bestiary_locked")
	Meta.seen = keep_seen
	await _shoot_catalogue()
	Flow.last_result = {"win": true, "level": 3, "kills": 48, "crystals": 130,
		"base": 60, "first": 70, "replay": false}
	await _shoot_scene("res://scenes/Result.tscn", "09_result")
	Flow.last_result = {"win": false, "level": 3, "kills": 22, "crystals": 17,
		"progress": 0.72, "cap": 24, "too_short": false, "boss_frac": 0.34,
		"time": 78.0, "boss_reached": true}
	await _shoot_scene("res://scenes/Fail.tscn", "10_fail")
	await _shoot_scene("res://scenes/Settings.tscn", "14_settings")
	# 快捷列釘選畫面:全部 20 座塔解鎖情況下,4 欄 grid 排唔排得晒 —— 呢個先係
	# 英文塔名(比中文闊 1.7 倍)真正會爆嘅地方
	await _shoot_scene("res://scenes/QuickBar.tscn", "23_quickbar")
	await _shoot_tier3_battle()
	await _gen_galleries()

## 全部第三階嘅戰場。要影呢張嘅理由:進化嘅視覺承諾(外觀進化 + 更多特效 +
## 全圖聖光光環嘅金光粒子同光柱)全部只有喺**場上一齊出現**嗰陣先睇得出夠唔夠
## 分得開 —— 一張塔卡 gallery 影唔到「二十座塔同時發光會唔會變成一嚿光」。
func _shoot_tier3_battle() -> void:
	for id in range(1, 21):
		Meta.tower_tiers[str(id)] = 3
	for id in range(1, 16):
		Meta.spell_tiers[str(id)] = 3
	var b: Node = _make_battle(12)
	await _mount(b)
	b.gold = 9999999
	b.base_shield = 99999
	var TowerScript := load("res://scripts/battle/Tower.gd")
	# 聖光塔(18)一定要喺呢張圖入面 —— 佢係全圖光環嘅光源,而「受惠塔身上
	# 有金光粒子」呢個表現冇佢就一粒都唔會出,即係影完都驗唔到。
	var ids: Array = [18, 1, 2, 3, 5, 6, 7, 9, 10, 12, 13, 16, 17, 20]
	for i in ids.size():
		var t = TowerScript.new()
		b.towers_root.add_child(t)
		t.setup(b, int(ids[i]), Vector2(150 + (i % 4) * 250, 380 + (i / 4) * 250))
		b.towers.append(t)
		match t.mech:
			"alchemy": b.alchemy_towers.append(t)
			"holy": b.holy_towers.append(t)
			"curse": b.curse_towers.append(t)
	for fam in ["goblin", "cultist", "golem", "bat"]:
		for k in 3:
			b._spawn_monster(fam, 4, false, 120.0 + k * 90.0)
	for i in 90:
		await get_tree().process_frame
	await _grab("25_battle_tier3")
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()

## 詛咒塔 in the field: the standing sigil on the ground plus the little hex/flame
## mark on every monster caught inside it. Both are new this round and neither
## shows up on any other screen.
func _shoot_curse_aura() -> void:
	Flow.selected_level = 4
	var b: Node = load("res://scenes/Battle.tscn").instantiate()
	await _mount(b)
	b.gold = 99999
	b.boss_time = 1.0e9
	# a ring of curse towers along the middle of the road, then a crowd walking in
	var placed := 0
	for gy in range(6, 18):
		for gx in range(2, 13):
			if placed >= 3:
				break
			var p: Vector2 = b.snap(Vector2(gx * 74, gy * 74))
			if b.route.dist_to_route(p) < 110.0 and b.can_place(p):
				if b.place_tower(17, p):
					placed += 1
	# a couple of arrow towers so the "amplifier next to output" read is visible
	for gy in range(6, 18):
		for gx in range(2, 13):
			var p2: Vector2 = b.snap(Vector2(gx * 74, gy * 74))
			if b.can_place(p2) and b.towers.size() < 8:
				b.place_tower(1, p2)
	for i in 26:
		b._spawn_monster(GameData.FAMILY_ORDER[i % 10], 1 + i % 5, false, 300.0 + i * 46.0)
	for i in 90:
		await get_tree().process_frame
	await _grab("02c_curse_aura")

# --- upgrade screen: a few towers/spell, top + scrolled (mechanic diagrams) --
## 圖鑑嘅塔頁 / 魔法頁 (round 11)。
##
## 影三個擁有狀態,因為佢哋喺卡上面係三個唔同嘅版式,而版式先係要驗嘅嘢:
## 全解鎖(數值 + 六條軸全彩)、有進化過(演進鏈前面幾格全彩、後面剪影)、
## 未解鎖(剪影 + 解鎖價,冇任何數值)。英文嗰版另外影一次 —— tier 名喺英文
## 長成兩倍,而演進鏈得三格 314px 闊。
func _shoot_catalogue() -> void:
	var keep_t: Array = Meta.unlocked_towers.duplicate()
	var keep_s: Array = Meta.unlocked_spells.duplicate()
	var b: Node = load("res://scenes/Bestiary.tscn").instantiate()
	await _mount(b)
	b._switch_tab("tower")
	for i in 6:
		await get_tree().process_frame
	await _grab("27_bestiary_towers")
	# 一件進化過嘅嘢:演進鏈上面「行到邊」先係呢一頁最想講嘅嘢
	Meta.tower_tiers["1"] = 2
	Meta.tower_up["1"] = [15, 15, 9, 3, 0, 0]
	b._rebuild()
	for i in 6:
		await get_tree().process_frame
	await _grab("27b_bestiary_towers_evolved")
	b._switch_tab("spell")
	for i in 6:
		await get_tree().process_frame
	await _grab("27c_bestiary_spells")
	# 未解鎖嘅版式:剪影 + 解鎖價,冇數值
	Meta.unlocked_towers = [1, 2]
	Meta.unlocked_spells = [1]
	b._switch_tab("tower")
	for i in 6:
		await get_tree().process_frame
	await _grab("27d_bestiary_towers_locked")
	Meta.unlocked_towers = keep_t
	Meta.unlocked_spells = keep_s
	Meta.tower_tiers.clear()
	Meta.tower_up.erase("1")

func _shoot_upgrades() -> void:
	var up: Node = load("res://scenes/Upgrade.tscn").instantiate()
	await _mount(up)
	await _grab("06_upgrade")
	await _select_upgrade(up, "tower", 1, 980)
	await _grab("06a_upgrade_arrow_rows")
	await _select_upgrade(up, "tower", 6, 0)
	await _grab("06b_upgrade_poison")
	await _select_upgrade(up, "tower", 13, 0)
	await _grab("06c_upgrade_barracks")
	await _select_upgrade(up, "spell", 1, 0)
	await _grab("06d_upgrade_spell")
	# 召喚民兵: the one spell whose diagram had to change with the new militia
	# body, so the upgrade screen teaches the same silhouette the field shows
	await _select_upgrade(up, "spell", 5, 420)
	await _grab("06m_upgrade_summon_mech")
	# 磁力塔 + 傳送塔: the two towers whose upgrade stats collide by NAME with a
	# probability stat on another tower (knock / stun). Shot so the px-vs-% and
	# seconds-vs-% formatting can actually be eyeballed.
	await _select_upgrade(up, "tower", 19, 980)
	await _grab("06g_upgrade_magnet_rows")
	await _select_upgrade(up, "tower", 20, 980)
	await _grab("06h_upgrade_teleport_rows")
	# the two reworked towers: mechanic panel (new diagram + lore) and the new
	# upgrade axes
	await _select_upgrade(up, "tower", 17, 420)
	await _grab("06i_upgrade_curse_mech")
	await _select_upgrade(up, "tower", 17, 1050)
	await _grab("06j_upgrade_curse_rows")
	await _select_upgrade(up, "tower", 16, 420)
	await _grab("06k_upgrade_missile_mech")
	await _select_upgrade(up, "tower", 16, 1050)
	await _grab("06l_upgrade_missile_rows")
	# --- 進化區 (round 10) ----------------------------------------------------
	# 三個狀態全部要影,因為佢哋係三張唔同嘅畫面,而唔係一張畫面嘅三個數值:
	#   未夠條件 = 剪影 + 「差幾多」;夠條件 = 亮起 + 新機制;滿階 = 封印。
	# 「未夠條件」嗰張最重要 —— 佢係大部分玩家大部分時間見到嗰張。
	Meta.tower_up["17"] = [15, 15, 15, 4, 0, 0]
	await _select_upgrade(up, "tower", 17, 1700)
	await _grab("24_evolve_locked")
	var maxed6: Array = [15, 15, 15, 15, 15, 15]
	Meta.tower_up["7"] = maxed6.duplicate()
	Meta.crystals = 99999
	await _select_upgrade(up, "tower", 7, 1700)
	await _grab("24b_evolve_ready")
	# 已經進化咗嘅塔:展示區個名 / 個圖要跟階,唔係仲叫舊名
	Meta.tower_tiers["7"] = 2
	Meta.tower_up["7"] = maxed6.duplicate()
	await _select_upgrade(up, "tower", 7, 0)
	await _grab("24c_evolved_showcase")
	await _select_upgrade(up, "tower", 7, 1700)
	await _grab("24d_evolve_to_t3")
	Meta.tower_tiers["7"] = 3
	await _select_upgrade(up, "tower", 7, 1700)
	await _grab("24e_evolve_maxed")
	Meta.spell_tiers["13"] = 2
	Meta.spell_up["13"] = [15, 15, 15]
	await _select_upgrade(up, "spell", 13, 1400)
	await _grab("24f_evolve_spell")
	Meta.tower_tiers.clear()
	Meta.spell_tiers.clear()
	Meta.tower_up.erase("17")
	Meta.tower_up.erase("7")
	Meta.spell_up.erase("13")

	# --- 效能面板嘅跨三階刻度 (round 11) --------------------------------------
	# 三張,而佢哋要影嘅唔係「數字啱唔啱」係「條 bar 講唔講到嘢」:
	#   tier 1 初期   —— 三段分區入面第一段都未行完,後面兩段係空嘅路
	#   tier 1 滿課   —— 頂住第一條界線,而唔係頂爆成條 bar(舊刻度嘅樣)
	#   tier 2 中段   —— 過咗第一條界線,仲有第二第三段喺前面
	# 第二張最重要:佢就係第十輪出事嗰張。
	Meta.tower_tiers.clear()
	Meta.tower_up["1"] = [0, 0, 0, 0, 0, 0]
	await _select_upgrade(up, "tower", 1, 560)
	await _grab("26_perf_t1_early")
	Meta.tower_up["1"] = [15, 15, 15, 15, 15, 15]
	await _select_upgrade(up, "tower", 1, 560)
	await _grab("26b_perf_t1_maxed")
	Meta.tower_tiers["1"] = 2
	Meta.tower_up["1"] = [8, 8, 8, 8, 8, 8]
	await _select_upgrade(up, "tower", 1, 560)
	await _grab("26c_perf_t2_mid")
	Meta.tower_tiers.clear()

	Meta.tower_up["1"] = [15, 7, 0, 0, 0, 0]
	await _select_upgrade(up, "tower", 1, 980)
	await _grab("06e_upgrade_maxed")
	Meta.crystals = 12
	up.crystal_label.text = "12"
	UI.toast(up, tr("TOAST_NEED_CRYSTALS").format({"n": 88}))
	for i in 8:
		await get_tree().process_frame
	await _grab("06f_upgrade_toast")
	Meta.crystals = 4200
	# let the toast finish fading before the showcase sheet, or it photobombs
	# every cell of it
	for i in 120:
		await get_tree().process_frame
	# showcase zone for every element (backdrop / platform / render coherence)
	var sheet := Image.create(1080, 820, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.07, 0.06))
	var i := 0
	for tid in [4, 5, 6, 3, 2, 12]:
		await _select_upgrade(up, "tower", tid, 0)
		var img: Image = await _grab_img()
		var crop := img.get_region(Rect2i(20, 126, 1040, 520))
		crop = _scaled(crop, 0.5)
		crop.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(crop, Rect2i(0, 0, crop.get_width(), crop.get_height()),
			Vector2i(4 + (i % 2) * 528, 4 + (i / 2) * 268))
		i += 1
	_save(sheet, "sheet_upgrade_showcase")

func _select_upgrade(up: Node, type: String, id: int, scroll_y: int) -> void:
	up.sel_type = type
	up.sel_id = id
	up._rebuild()
	for i in 4:
		await get_tree().process_frame
	up.scroll.scroll_vertical = scroll_y
	for i in 3:
		await get_tree().process_frame

## All 20 tower mechanic diagrams on one sheet (does the picture match the mech?)
func _shoot_mech_sheet() -> void:
	# must go through a runtime GDScript instance — calling get_script_constant_map()
	# on a preloaded class directly is a parse error ("non-static function").
	var upg_script: GDScript = load(UPG_PATH)
	var consts: Dictionary = upg_script.get_script_constant_map()
	var DiagCls: GDScript = consts["_MechDiagram"]
	var MECH: Dictionary = consts["TOWER_MECH"]
	var ELEM: Dictionary = consts["ELEM_COL"]
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.085, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var holder := Control.new()
	holder.scale = Vector2(0.62, 0.62)
	holder.position = Vector2(20, 40)
	root.add_child(holder)
	for i in 20:
		var tid := i + 1
		var def := GameData.tower_by_id(tid)
		var kind: String = MECH.get(def.mech, ["range", ""])[0]
		var e := "stone"
		if tid == 4: e = "fire"
		elif tid == 5: e = "ice"
		elif tid in [6, 15]: e = "poison"
		elif tid in [3, 10, 11, 17, 18, 19, 20]: e = "arcane"
		var d = DiagCls.new()
		d.kind = kind
		d.col = ELEM[e]
		d.size = Vector2(400, 272)
		d.position = Vector2((i % 4) * 425, (i / 4) * 316)
		holder.add_child(d)
		var l := UI.label("%d %s (%s)" % [tid, tr(def.name), kind], 30, UI.TEXT)
		l.position = Vector2((i % 4) * 425 + 6, (i / 4) * 316 + 272)
		l.size = Vector2(400, 40)
		holder.add_child(l)
	await _mount(root)
	await _grab("sheet_mech_diagrams")

# --- battle: several representative states ----------------------------------
func _make_battle(level: int) -> Node:
	Flow.selected_level = level
	return load("res://scenes/Battle.tscn").instantiate()

func _populate(battle: Node, n_towers: int, n_monsters: int) -> void:
	battle.gold = 12000
	var ids := [1, 2, 3, 5, 13, 12, 16, 10, 4, 6, 7, 18]
	var placed := 0
	for gx in range(2, 13):
		for gy in range(4, 22):
			if placed >= n_towers or placed >= ids.size(): break
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos) and battle.place_tower(ids[placed], pos):
				placed += 1
		if placed >= n_towers: break
	for i in n_monsters:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 1 + i % 5, false, i * 22.0)

## Round 8: the rebuilt bottom bar. The spell grid has three distinct shapes and
## the tower drawer has two states, and none of them are reachable from the
## default all-unlocked save the other shots use — so each one gets set up
## explicitly. These are the shots the layout was checked against.
func _shoot_bottom_bar() -> void:
	var keep_s: Array = Meta.unlocked_spells.duplicate()
	for n in [3, 8, 15]:
		Meta.unlocked_spells = range(1, n + 1)
		var b := _make_battle(4)
		await _mount(b)
		_populate(b, 6, 8)
		for i in 30:
			await get_tree().process_frame
		await _grab("20_bar_spells%02d" % n)
	Meta.unlocked_spells = keep_s
	# drawer open, all 20 towers, over a live field
	var bd := _make_battle(4)
	await _mount(bd)
	_populate(bd, 6, 8)
	for i in 20:
		await get_tree().process_frame
	if bd.hud:
		bd.hud._set_drawer(true)
		bd.hud.drawer.position.y = bd.hud._drawer_shown_y   # skip the slide
	for i in 10:
		await get_tree().process_frame
	await _grab("21_bar_drawer")

## Round 8: barracks trooper vs summoned militia, side by side and zoomed, which
## is the only way to check the thing that matters — that they are told apart at
## the size they actually appear on the field.
func _shoot_militia() -> void:
	var b := _make_battle(4)
	await _mount(b)
	var d0: float = b.route.total * 0.45
	# left group: barracks troopers (permanent, no magic)
	for i in 2:
		b.spawn_soldier(d0 - 70.0 + i * 40.0, 120.0, 12.0, 2.0, null, -1.0, false)
	# right group: summoned militia — one mid-summon, one steady, one expiring
	var fresh = b.spawn_soldier(d0 + 60.0, 120.0, 12.0, 2.0, null, 20.0, true)
	var steady = b.spawn_soldier(d0 + 110.0, 120.0, 12.0, 2.0, null, 20.0, true)
	var dying = b.spawn_soldier(d0 + 160.0, 120.0, 12.0, 2.0, null, 20.0, true)
	for i in 20:
		await get_tree().process_frame
	# force the three phases rather than waiting 18 seconds for the last one
	fresh._age = 0.18
	steady._age = 3.0
	dying._age = 3.0
	dying.life_time = 1.2
	if b.cam:
		b.cam.zoom = Vector2(2.4, 2.4)
		b.cam.position = b.route.pos_at(d0 + 40.0)
	for i in 3:
		await get_tree().process_frame
	await _grab("22_militia_vs_soldier")

func _shoot_battle_states() -> void:
	# 02: full combat (towers + monsters mid-fight, boss bar up)
	var b := _make_battle(4)
	await _mount(b)
	_populate(b, 8, 12)
	b.elapsed = b.boss_time - 4.0
	b.boss_spawned = true
	var boss_m = b._spawn_monster(GameData.FAMILY_ORDER[0], 5, true, 300.0)
	b.boss_ref = boss_m
	if b.hud:
		b.hud.show_boss(boss_m)
	b.spell_cd[1] = 8.5
	b.spell_cd[3] = 4.0
	b.spell_cd[6] = 6.5
	for i in 120:
		await get_tree().process_frame
	await _grab("02_battle")

	# 03: placement mode (ghost + range preview)
	b.build_id = 3
	b._pointer_world = b.snap(Vector2(6 * 74, 9 * 74))
	for i in 20:
		await get_tree().process_frame
	await _grab("03_battle_place")

	# 13: pause menu over the live battle
	b.build_id = 0
	if b.hud:
		b.hud.pause_menu.visible = true
	for i in 6:
		await get_tree().process_frame
	await _grab("13_pause")
	if b.hud:
		b.hud.pause_menu.visible = false

	# 15/16: camera zooms onto base + spawn portal (presence check)
	if b.cam:
		b.cam.zoom = Vector2(2.0, 2.0)
		b.cam.position = b.base_pos
		for i in 8:
			await get_tree().process_frame
		await _grab("15_zoom_base")
		b.cam.position = b.route.pos_at(4.0)
		for i in 8:
			await get_tree().process_frame
		await _grab("16_zoom_spawn")
		b.cam.zoom = Vector2.ONE
		b.cam.position = Vector2(540, 960)

	# 02b: FX showcase — projectiles in flight + a meteor impact
	var bf := _make_battle(4)
	await _mount(bf)
	_populate(bf, 8, 10)
	for i in 14:
		bf._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 3, false, 700.0 + i * 26.0)
	for i in 14:
		await get_tree().process_frame
	Spells.cast(bf, 1, bf.route.pos_at(760.0))
	await get_tree().process_frame
	await get_tree().process_frame
	_save(sub.get_texture().get_image(), "02b_fx")
	bf.queue_free()
	await get_tree().process_frame

	# 04: overview at start (few enemies emerging from spawn) — deco density
	var b2 := _make_battle(2)
	await _mount(b2)
	for i in 6:
		b2._spawn_monster(GameData.FAMILY_ORDER[i % 3], 1, false, i * 30.0)
	for i in 40:
		await get_tree().process_frame
	await _grab("04_battle_early")

## Every spell cast, captured mid-performance, tiled 3x5 (does each read big?).
func _shoot_spell_casts() -> void:
	var cell := Vector2i(360, 640)
	var sheet := Image.create(cell.x * 3 + 16, cell.y * 5 + 24, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.06, 0.05, 0.05))
	for id in range(1, 16):
		var b := _make_battle(4)
		await _mount(b)
		_populate(b, 6, 0)
		for i in 18:
			b._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 3, false, 620.0 + i * 24.0)
		b.gold = 12000
		for i in 10:
			await get_tree().process_frame
		var at: Vector2 = b.route.pos_at(760.0)
		Spells.cast(b, id, at)
		# 3 frames in gives the burst/line/sparks their most readable moment
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := sub.get_texture().get_image()
		var full := _scaled(img, float(cell.x) / VW)
		full.convert(Image.FORMAT_RGBA8)
		var idx := id - 1
		sheet.blend_rect(full, Rect2i(0, 0, full.get_width(), full.get_height()),
			Vector2i(4 + (idx % 3) * (cell.x + 4), 4 + (idx / 3) * (cell.y + 4)))
		# also keep a full-res shot of the five "big" spells
		if id in [1, 3, 11, 2, 15]:
			_save(img, "17_cast_%02d_%s" % [id, GameData.spell_by_id(id).mech])
	_save(sheet, "sheet_spell_casts")

# ---------------------------------------------------------------------------
# Sprite galleries
func _gen_galleries() -> void:
	_gallery_monsters()
	_gallery_towers()
	_gallery_spells()
	_gallery_env()
	await _gallery_ui_kit()
	await _gallery_projectiles()
	await _gallery_fx()
	await _gallery_cards()

func _grid(paths: Array, cols: int, cell: int, scale: int, name: String) -> void:
	var pad := 8
	var cw := cell + pad
	var ch := cell + pad
	var rows := int(ceil(float(paths.size()) / cols))
	var W := cols * cw + pad
	var H := rows * ch + pad
	var sheet := Image.create(W, H, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.14, 0.15, 0.19))
	for idx in paths.size():
		var r := idx / cols
		var cc := idx % cols
		var cx := pad + cc * cw
		var cy := pad + r * ch
		sheet.fill_rect(Rect2i(cx, cy, cell, cell), Color(0.10, 0.11, 0.15))
		var p: String = paths[idx]
		if not ResourceLoader.exists(p):
			continue
		var tex: Texture2D = load(p)
		var im := tex.get_image()
		if scale != 1:
			im.resize(im.get_width() * scale, im.get_height() * scale, Image.INTERPOLATE_NEAREST)
		if im.get_width() > cell or im.get_height() > cell:
			var s2 := minf(float(cell) / im.get_width(), float(cell) / im.get_height())
			im.resize(int(im.get_width() * s2), int(im.get_height() * s2), Image.INTERPOLATE_NEAREST)
		var ox := cx + (cell - im.get_width()) / 2
		var oy := cy + (cell - im.get_height()) / 2
		im.convert(Image.FORMAT_RGBA8)
		sheet.blend_rect(im, Rect2i(0, 0, im.get_width(), im.get_height()), Vector2i(ox, oy))
	_save(sheet, name)

func _gallery_monsters() -> void:
	var paths := []
	for fam in GameData.FAMILY_ORDER:
		for lvl in range(1, 6):
			paths.append("res://assets/generated/monsters/%s_%d.png" % [fam, lvl])
		paths.append("res://assets/generated/monsters/%s_boss.png" % fam)
	_grid(paths, 12, 100, 2, "gallery_monsters")

func _gallery_towers() -> void:
	var paths := []
	for i in range(1, 21):
		paths.append("res://assets/generated/towers/tower_%d.png" % i)
	_grid(paths, 5, 200, 3, "gallery_towers")

func _gallery_spells() -> void:
	var paths := []
	for i in range(1, 16):
		paths.append("res://assets/generated/spells/spell_%d.png" % i)
	_grid(paths, 5, 180, 2, "gallery_spells")

func _gallery_env() -> void:
	var paths := ["res://assets/generated/ui/base.png",
		"res://assets/generated/tiles/portal.png",
		"res://assets/generated/ui/soldier.png",
		"res://assets/generated/tiles/ground.png",
		"res://assets/generated/tiles/road.png",
		"res://assets/generated/tiles/deco_rock1.png",
		"res://assets/generated/tiles/deco_rock2.png",
		"res://assets/generated/tiles/deco_bones.png",
		"res://assets/generated/tiles/deco_skull.png",
		"res://assets/generated/tiles/deco_grass.png",
		"res://assets/generated/tiles/deco_crack.png"]
	_grid(paths, 4, 240, 3, "gallery_env")

## UI kit: every button state, every frame, every icon at 2x.
func _gallery_ui_kit() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.085, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var y := 20
	root.add_child(_kit_label("按鈕狀態 normal / hover / pressed / disabled", 12, y))
	y += 46
	var cols := [["普通", UI.PANEL_HI], ["確定", UI.ACCENT], ["危險", UI.DANGER], ["金", UI.GOLD]]
	for ci in cols.size():
		var nm: String = cols[ci][0]
		var col: Color = cols[ci][1]
		for si in 4:
			var b := UI.button(nm, Vector2(240, 96), col, 32)
			b.position = Vector2(16 + ci * 262, y + si * 106)
			if si == 1:
				b.add_theme_stylebox_override("normal", b.get_theme_stylebox("hover"))
			elif si == 2:
				b.add_theme_stylebox_override("normal", b.get_theme_stylebox("pressed"))
			elif si == 3:
				b.disabled = true
			root.add_child(b)
	y += 4 * 106 + 20
	root.add_child(_kit_label("框料 panel9 / panel_dark9 / panel_parch9 / card9 / slot9 / banner_gold9", 12, y))
	y += 46
	var frames := ["panel9", "panel_dark9", "panel_parch9", "card9", "slot9", "banner_gold9"]
	for i in frames.size():
		var p := Panel.new()
		p.add_theme_stylebox_override("panel", UI.frame_box(frames[i]))
		p.position = Vector2(16 + (i % 3) * 350, y + (i / 3) * 190)
		p.size = Vector2(330, 175)
		root.add_child(p)
		var l := UI.label(frames[i], 24, UI.TEXT_DIM)
		l.position = Vector2(28, 8)
		p.add_child(l)
	y += 2 * 190 + 16
	root.add_child(_kit_label("進度條 track + gold/green/crystal/red 填色", 12, y))
	y += 46
	var fills := ["bar_gold9", "bar_green9", "bar_crystal9", "bar_red9"]
	for i in fills.size():
		var t := Panel.new()
		t.add_theme_stylebox_override("panel", UI.frame_box("bar_track9", 10, 4, 2))
		t.position = Vector2(16, y + i * 46)
		t.size = Vector2(700, 32)
		root.add_child(t)
		var f := TextureRect.new()
		f.texture = Assets.ui(fills[i])
		f.position = Vector2(5, 5)
		f.size = Vector2(660 * (0.4 + i * 0.18), 22)
		f.stretch_mode = TextureRect.STRETCH_SCALE
		t.add_child(f)
		var l2 := UI.label(fills[i], 24, UI.TEXT_DIM)
		l2.position = Vector2(740, y + i * 46)
		root.add_child(l2)
	y += 4 * 46 + 20
	root.add_child(_kit_label("圖示 (2x) + 資源幣", 12, y))
	y += 46
	var icons := ["ic_pause", "ic_play", "ic_ff", "ic_sound", "ic_mute", "ic_back", "ic_shop",
		"ic_skull", "ic_stats", "ic_up", "ic_sword", "ic_speed", "ic_scope", "ic_star",
		"ic_spark", "ic_shield", "ic_coin", "ic_prev", "ic_next", "coin", "crystal", "badge_max"]
	for i in icons.size():
		var slot := Panel.new()
		slot.add_theme_stylebox_override("panel", UI.frame_box("slot9", 14, 4, 4))
		slot.position = Vector2(16 + (i % 8) * 130, y + (i / 8) * 140)
		slot.size = Vector2(118, 118)
		root.add_child(slot)
		var tr := UI.tex_rect(Assets.ui(icons[i]), Vector2(88, 88))
		tr.position = Vector2(15, 8)
		slot.add_child(tr)
		var l3 := UI.label(icons[i], 17, UI.TEXT_DIM)
		l3.position = Vector2(4, 96)
		l3.size = Vector2(110, 20)
		l3.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.add_child(l3)
	await _mount(root)
	await _grab("gallery_ui_kit")

func _kit_label(text: String, x: int, y: int) -> Label:
	var l := UI.label(text, 30, UI.GOLD)
	l.position = Vector2(x, y)
	return l

## Live projectile lab: every fx kind flying right, on a neutral field.
func _gallery_projectiles() -> void:
	var root := Node2D.new()
	var bgc := ColorRect.new()
	bgc.color = Color(0.16, 0.14, 0.12)
	bgc.size = Vector2(VW, VH)
	root.add_child(bgc)
	var kinds := ["arrow", "cannon", "fire", "rocket", "ice", "poison", "magic", "holy"]
	var cols := {"arrow": Color(0.95, 0.9, 0.7), "cannon": Color(0.3, 0.3, 0.34),
		"fire": Color(1, 0.6, 0.2), "rocket": Color(1, 0.8, 0.3), "ice": Color(0.6, 0.85, 1.0),
		"poison": Color(0.55, 0.9, 0.3), "magic": Color(0.8, 0.5, 1.0), "holy": Color(1, 0.95, 0.6)}
	var projs: Array = []
	for i in kinds.size():
		var k: String = kinds[i]
		for lob in [false, true]:
			var p := Projectile.new()
			root.add_child(p)
			var yy := 150 + i * 210 + (100 if lob else 0)
			p.setup(Vector2(200, yy), null, Vector2(6000, yy), 260.0, false,
				cols[k], 14.0, {"fx": k}, lob, null, null)
			if lob:
				p._total_dist = 900.0
			projs.append(p)
		var l := Label.new()
		l.text = k
		l.add_theme_font_size_override("font_size", 34)
		l.position = Vector2(30, 150 + i * 210 - 40)
		root.add_child(l)
	await _mount(root)
	# let them fly a bit so trails/lob arcs develop
	for i in 40:
		await get_tree().process_frame
	await _grab("gallery_projectiles")

## Live FX lab: each Fx kind at three points in its life.
func _gallery_fx() -> void:
	var root := Node2D.new()
	var bgc := ColorRect.new()
	bgc.color = Color(0.16, 0.14, 0.12)
	bgc.size = Vector2(VW, VH)
	root.add_child(bgc)
	await _mount(root)
	var specs := [
		["RING 爆炸環", Color(1, 0.6, 0.2)],
		["BURST 隕石/地震", Color(1, 0.5, 0.2)],
		["BURST 冰凍", Color(0.6, 0.9, 1.0)],
		["ORB 中毒雲", Color(0.5, 0.9, 0.2)],
		["LINE 閃電", Color(0.7, 0.9, 1.0)],
		["LINE 天雷", Color(1, 1, 0.6)],
		["SPARK 火花", Color(1, 0.6, 0.2)],
		["SPARK 金幣", Color(1, 0.85, 0.2)],
	]
	for i in specs.size():
		var l := Label.new()
		l.text = specs[i][0]
		l.add_theme_font_size_override("font_size", 30)
		l.position = Vector2(40, 90 + i * 225 - 76)
		root.add_child(l)
	var made: Array = []
	for i in specs.size():
		var c: Color = specs[i][1]
		var pos := Vector2(540, 90 + i * 225)
		var fx := Fx.new()
		root.add_child(fx)
		match i:
			0: fx.ring(pos, 90, c, 3.0, null)
			1: fx.burst(pos, 110, c, 3.0, null)
			2: fx.burst(pos, 110, c, 3.0, null)
			3: fx.orb(pos, 70, c, 3.0, null)
			4: fx.line(PackedVector2Array([pos + Vector2(-260, -90), pos + Vector2(-90, 20),
					pos + Vector2(80, -60), pos + Vector2(260, 40)]), c, 6.0, 3.0, null)
			5: fx.line(PackedVector2Array([pos + Vector2(0, -90), pos + Vector2(0, 80)]), c, 10.0, 3.0, null)
			6:
				for s in 10:
					var sp := Fx.new()
					root.add_child(sp)
					sp.spark(pos, Vector2(cos(s * 0.63), sin(s * 0.63)) * 180.0, 8.0, c, 3.0, null, 60.0, false)
					made.append(sp)
			7:
				for s in 8:
					var sp2 := Fx.new()
					root.add_child(sp2)
					sp2.spark(pos, Vector2(cos(s * 0.8), sin(s * 0.8)) * 150.0, 9.0, c, 3.0, null, 60.0, true)
					made.append(sp2)
		made.append(fx)
	for i in 6:
		await get_tree().process_frame
	await _grab("gallery_fx")

## The real HUD cards (20 tower cards + 15 spell cards), reparented onto a grid.
func _gallery_cards() -> void:
	var b := _make_battle(4)
	await _mount(b)
	b.gold = 118      # under most place costs -> disabled card state renders
	# put a few spells on cooldown before the HUD's last refresh so the radial
	# CD masks survive into the gallery (hud.refresh would zero them otherwise)
	for sid in [2, 5, 8, 11, 14]:
		b.spell_cd[sid] = 6.0 + sid * 0.4
	for i in 10:
		await get_tree().process_frame
	var hud = b.hud
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.11, 0.085, 0.065)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	var t1 := UI.label("塔卡片 x20 (灰=金幣不足)", 32, UI.GOLD)
	t1.position = Vector2(16, 10)
	host.add_child(t1)
	for i in hud.build_cards.size():
		var btn: Button = hud.build_cards[i].btn
		btn.get_parent().remove_child(btn)
		btn.position = Vector2(24 + (i % 5) * 200, 60 + (i / 5) * 245)
		btn.scale = Vector2(1.3, 1.3)
		host.add_child(btn)
	var t2 := UI.label("魔法卡片 x15 (含 CD 遮罩)", 32, UI.GOLD)
	t2.position = Vector2(16, 1060)
	host.add_child(t2)
	for i in hud.spell_cards.size():
		var sb: Button = hud.spell_cards[i].btn
		sb.get_parent().remove_child(sb)
		sb.position = Vector2(24 + (i % 5) * 200, 1120 + (i / 5) * 190)
		sb.scale = Vector2(1.5, 1.5)
		host.add_child(sb)
	await _mount(host)
	await _grab("gallery_cards")
