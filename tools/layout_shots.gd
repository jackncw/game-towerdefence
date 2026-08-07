extends Node
## 喺真實電話解像度嘅**視窗**入面影圖,包埋黑邊。
##
## 同 `art_export.tscn` 嘅分別好重要:art_export 用一個 1080x1920 嘅
## SubViewport,即係佢**永遠**影到一個啱啱好嘅設計框 —— 佢答唔到「喺一部
## 20:9 嘅電話上面會唔會爆邊」呢條問題,因為佢由定義上面就冇邊。
##
## 呢度影嘅係**root viewport**,即係連 `stretch/aspect=keep` 留低嘅黑邊一齊影。
## 一張圖睇得出三件事:
##   1. 1080x1920 個設計框有冇被剪(keep 由定義上唔會剪,但呢張圖係證據)
##   2. 黑邊喺邊、幾闊
##   3. 個框有冇置中
##
## 視窗按比例縮細(`--scale=`)先至擺得落一部 1080p mon —— 影嘅係**比例**,
## 而爆唔爆邊係一個純比例問題。
##
## 跑法(**一定要開窗**):
##   Godot --path . tools/layout_shots.tscn -- --out=round-22-layout

const ArtExport := preload("res://tools/art_export.gd")

## 真機解像度。頭四個係 2024-2026 Android 最常見嗰批。
const SHAPES := [
	{"name": "1080x2400_20by9", "size": Vector2i(1080, 2400)},
	{"name": "1080x2340_19.5by9", "size": Vector2i(1080, 2340)},
	{"name": "1440x3200_qhd", "size": Vector2i(1440, 3200)},
	{"name": "720x1600_hd", "size": Vector2i(720, 1600)},
	{"name": "1080x1920_design", "size": Vector2i(1080, 1920)},
	{"name": "1200x2000_tablet", "size": Vector2i(1200, 2000)},
]

const SCENES := [
	{"key": "menu", "path": "res://scenes/MainMenu.tscn"},
	{"key": "battle", "path": "res://scenes/Battle.tscn"},
	{"key": "upgrade", "path": "res://scenes/Upgrade.tscn"},
]

var out_dir: String = ArtExport.QA_ROOT + "layout/"
var scale: float = 0.34          # 3200 * 0.34 = 1088,擺得落一部 1080p mon
var rows: Array = []

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = ArtExport.qa_dir(String(a).substr(6))
		elif String(a).begins_with("--scale="):
			scale = float(String(a).substr(8))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Flow.nav_enabled = false
	Crash.enabled = false
	Meta.reset_save()
	Meta.crystals = 90000
	Meta.highest_level = 40
	get_tree().create_timer(240.0).timeout.connect(func():
		push_warning("layout_shots timed out"); get_tree().quit(2))
	await _run()
	print("LAYOUT: DONE")
	get_tree().quit(0)

func _run() -> void:
	for shape in SHAPES:
		var dev: Vector2i = shape["size"]
		var win := Vector2i(int(dev.x * scale), int(dev.y * scale))
		DisplayServer.window_set_size(win)
		await _idle(4)
		for sc in SCENES:
			var node = load(sc["path"]).instantiate()
			if sc["key"] == "battle":
				Flow.selected_level = 3
			get_tree().root.add_child(node)
			await _idle(8)
			var img := get_tree().root.get_texture().get_image()
			var fn: String = "%s_%s.png" % [shape["name"], sc["key"]]
			img.save_png(out_dir + fn)
			rows.append(_measure(shape, win, img, sc["key"], fn))
			node.queue_free()
			await _idle(2)
	print("LAYOUT: %-22s %-8s %-11s %-11s %s" %
		["device", "screen", "window", "frame", "letterbox"])
	for r in rows:
		print("LAYOUT: " + r)

## 量返個 1080x1920 框喺呢個視窗入面實際佔咗幾多、黑邊幾闊。
## 用 stretch transform 問引擎,唔係自己再計一次 —— 呢度想知嘅係
## 「引擎實際做咗乜」,唔係「我以為佢會做乜」。
func _measure(shape: Dictionary, win: Vector2i, img: Image, key: String, fn: String) -> String:
	var t := get_tree().root.get_final_transform()
	var frame := Vector2(1080, 1920) * Vector2(t.x.x, t.y.y)
	var off := Vector2(t.origin)
	var bar_x := off.x
	var bar_y := off.y
	var ok := frame.x <= float(win.x) + 1.0 and frame.y <= float(win.y) + 1.0 \
		and bar_x >= -1.0 and bar_y >= -1.0
	return "%-22s %-8s %-11s %-11s %s  %s  %s" % [
		shape["name"], key, "%dx%d" % [win.x, win.y],
		"%dx%d" % [int(frame.x), int(frame.y)],
		"左右各 %d / 上下各 %d" % [int(bar_x), int(bar_y)],
		"OK" if ok else "**爆邊**", fn]

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
