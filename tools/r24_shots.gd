extends Node
## 第 24 輪嘅新畫面截圖(無盡選關 / 設定頁版本+私隱 / 首戰引導四頁 /
## 除錯記錄檢視器 / 無盡關結算)。中英各一份。
##
##   Godot --path . tools/r24_shots.tscn -- --out=round-24-endless
##
## **一定要開窗**(要 GPU)。同 art_export 一樣用一個 1080x1920 SubViewport,
## 所以影到嘅永遠係設計框。
##
## 點解要另寫一個而唔係加落 art_export:本輪嘅新畫面全部**要一個特定嘅存檔
## 狀態**先出得到(無盡段要 cleared["100"]、引導要 highest_level == 0),
## 而 art_export 係一個「解鎖晒然後逐個畫面影」嘅工具 —— 喺佢入面加狀態
## 切換會令佢之後嗰四十幾張圖全部影喺一個唔同嘅存檔上面。

const ArtExport := preload("res://tools/art_export.gd")
const VW := 1080
const VH := 1920

var out_dir: String = ArtExport.QA_ROOT + "round-24-endless/"
var sub: SubViewport
var done := false
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = ArtExport.qa_dir(String(a).substr(6))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	Flow.nav_enabled = false
	Crash.enabled = false
	_backup_save()
	get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
		if not done:
			push_warning("r24_shots timed out")
			get_tree().quit(1))

	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	add_child(sub)
	print("R24_SHOTS: out=", out_dir)

	for loc in ["zh_TW", "en"]:
		TranslationServer.set_locale(loc)
		await _shoot_all(loc)

	_restore_save()
	print("R24_SHOTS: DONE")
	done = true
	get_tree().quit(0)

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(Meta.SAVE_PATH)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_save_bytes)
			f.close()
	elif FileAccess.file_exists(Meta.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.SAVE_PATH))

## 一個「已通關第 N 關」嘅記憶體狀態。**唔寫檔** —— 呢個工具由頭到尾唔應該
## 掂到真存檔(收工嗰陣仲會還原一次做保險)。
func _state(highest: int) -> void:
	Meta.crystals = 250000
	Meta.highest_level = highest
	Meta.cleared = {}
	for n in range(1, highest + 1):
		Meta.cleared[str(n)] = true
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.settings["tutorial_done"] = true

func _shoot_all(loc: String) -> void:
	# ── 無盡模式:選關介面(頂 + 底)────────────────────────────────
	_state(137)
	var ls := await _mount("res://scenes/LevelSelect.tscn")
	await _snap("levelselect_top", loc)
	# 捲到最底 —— 無盡段排喺 1-100 格仔陣之後
	var sc := _find(ls, "ScrollContainer") as ScrollContainer
	if sc != null:
		# 無盡段個標題面板夾喺「1-100 格仔陣」同「無盡段格仔陣」中間,
		# 而佢先係本輪要睇嘅嘢 —— 一張捲到最底嘅圖影唔到佢。
		# **唔可以用 `sc.get_child(0)`** —— ScrollContainer 嘅兩條捲軸都係
		# 佢嘅子節點,而且排喺前面。第一版就係咁靜靜咁乜都影唔到。
		var col := _find(sc, "VBoxContainer")
		if col != null and col.get_child_count() >= 2:
			var head: Control = col.get_child(1)
			sc.scroll_vertical = maxi(0, int(head.position.y) - 260)
			await _wait(4)
			await _snap("levelselect_endless_head", loc)
		sc.scroll_vertical = 1 << 20
		await _wait(4)
	await _snap("levelselect_endless", loc)
	_drop(ls)

	# ── 主選單(「開始遊戲(第 138 關)」)────────────────────────────
	var mm := await _mount("res://scenes/MainMenu.tscn")
	await _snap("mainmenu_endless", loc)
	_drop(mm)

	# ── 設定頁(版本號 + 私隱政策)───────────────────────────────────
	var st := await _mount("res://scenes/Settings.tscn")
	await _snap("settings", loc)
	# 隱藏除錯檢視器(冇閃退記錄 -> 顯示今次 session)
	Crash.last_crash = {}
	st.open_debug_log()
	await _wait(3)
	await _snap("debug_log", loc)
	_drop(st)

	# ── 無盡關結算畫面 ───────────────────────────────────────────────
	for lv in [101, 200]:
		Flow.last_result = {"level": lv, "kills": 342, "base": 1180, "first": 1330,
			"crystals": 2510, "mult": 1.0, "replay": false, "win": true}
		var rs := await _mount("res://scenes/Result.tscn")
		await _snap("result_lv%d" % lv, loc)
		_drop(rs)

	# ── 首戰引導四頁 ────────────────────────────────────────────────
	_state(0)
	Meta.settings["tutorial_done"] = false
	Flow.selected_level = 1
	Flow.last_result = {}
	var b := await _mount("res://scenes/Battle.tscn")
	b.hud.show_tutorial()
	await _wait(3)
	for i in 4:
		await _snap("tutorial_%d" % (i + 1), loc)
		if i < 3:
			b.hud._tut_advance()
			await _wait(3)
	_drop(b)

func _mount(path: String) -> Node:
	var s = load(path).instantiate()
	sub.add_child(s)
	await _wait(4)
	return s

func _drop(s: Node) -> void:
	sub.remove_child(s)
	s.queue_free()
	await _wait(2)

func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _snap(name: String, loc: String) -> void:
	await RenderingServer.frame_post_draw
	var img := sub.get_texture().get_image()
	var p := "%s%s-%s.png" % [out_dir, name, loc]
	img.save_png(ProjectSettings.globalize_path(p))
	print("R24_SHOTS: ", p)

## 深度搵第一個指定 class 嘅子節點。
func _find(root: Node, cls: String) -> Node:
	for c in root.get_children():
		if c.is_class(cls):
			return c
		var r := _find(c, cls)
		if r != null:
			return r
	return null
