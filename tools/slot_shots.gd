extends Node
## 塔位容量嘅**視覺**驗證(第十八輪)。
##
## slotcap.gd 講到擺得落幾多座,但一個數字答唔到「擺成點」:塔會唔會壓住條路、
## 會唔會蓋住上下兩條 HUD、密到黐埋一齊之後仲睇唔睇得出邊座係邊座。所以呢度
## 用同 art_export 一樣嘅 SubViewport(1080x1920,遊戲設計解像度)影真圖。
##
## 用法(要開窗、要 GPU):
##   Godot --path . tools/slot_shots.tscn -- --out=round-18-slots

const VW := 1080
const VH := 1920
const ArtExport := preload("res://tools/art_export.gd")

## (關卡, 塔數) —— 三款 path 模板 x 早/中/後期塔數
const SHOTS := [
	{"lv": 3, "n": 10, "name": "01_lv03_10towers"},     # 5 橫掃(最窄嘅模板)
	{"lv": 20, "n": 25, "name": "02_lv20_25towers"},
	{"lv": 45, "n": 45, "name": "03_lv45_45towers"},
	{"lv": 60, "n": 88, "name": "04_lv60_full"},        # 鋪到再擺唔落為止
]

var outdir := ArtExport.QA_ROOT + "slots/"
var sub: SubViewport

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = ArtExport.qa_dir(a.substr(6))
		elif a.begins_with("--locale="):
			TranslationServer.set_locale(a.substr(9))
	get_tree().create_timer(240.0).timeout.connect(func():
		push_warning("slot_shots timed out")
		get_tree().quit(2))
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.highest_level = 99
	Meta.crystals = 999999
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(outdir))
	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	for s in SHOTS:
		await _shot(int(s["lv"]), int(s["n"]), String(s["name"]))
	get_tree().quit(0)

func _shot(lv: int, n: int, name: String) -> void:
	Flow.selected_level = lv
	Flow.last_result = {}
	var b = load(Flow.BATTLE).instantiate()
	sub.add_child(b)
	await get_tree().process_frame
	b.gold = 9999999
	b.boss_time = 1.0e9              # 唔好喺影相中途出 boss
	b.base_shield = 1000000
	var placed: int = _fill(b, n)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	var path: String = outdir + name + ".png"
	img.save_png(path)
	print("SLOTSHOT %s lv=%d asked=%d placed=%d road_min=%.0f" % [
		path, lv, n, placed, _min_road_dist(b)])
	b.queue_free()
	await get_tree().process_frame

## 同 GateSim._spots(strong) 一樣嘅次序:覆蓋率高嘅位行先。
func _fill(b, want: int) -> int:
	var ids := [1, 2, 5, 13, 3, 4, 12, 18, 6, 15, 11, 17]
	var spots: Array = []
	var y: float = b.BUILD_MIN.y
	while y <= b.BUILD_MAX.y:
		var x: float = b.BUILD_MIN.x
		while x <= b.BUILD_MAX.x:
			var p: Vector2 = b.snap(Vector2(x, y))
			if b.can_place(p):
				spots.append(p)
			x += 74.0
		y += 74.0
	var cov := {}
	for p in spots:
		cov[p] = _coverage(b, p)
	spots.sort_custom(func(a, c):
		var ca: float = float(cov[a])
		var cc: float = float(cov[c])
		if absf(ca - cc) > 1.0:
			return ca > cc
		return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))
	var k := 0
	for p in spots:
		if k >= want:
			break
		if b.can_place(p) and b.place_tower(ids[k % ids.size()], p):
			k += 1
	return k

func _coverage(b, p: Vector2) -> float:
	var tot: float = b.route.total
	var d := 0.0
	var hit := 0.0
	while d < tot:
		if b.route.pos_at(d).distance_to(p) <= 260.0:
			hit += 8.0
		d += 8.0
	return hit

## 最近嘅一座塔離條路中線幾遠 —— 應該永遠 >= Battle.ROAD_CLEAR。
func _min_road_dist(b) -> float:
	var m := 1.0e9
	for t in b.towers:
		m = minf(m, b.route.dist_to_route(t.global_position))
	return m
