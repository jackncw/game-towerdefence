extends Node
## 淨影**一個**畫面。
##
## 點解要有:`art_export.tscn` 影 61 張,跑足四分鐘。改一版設定頁想睇下有冇
## 爆版,唔應該要等四分鐘同埋落 61 張圖落 qa/。呢個係同一套 SubViewport 做法
## (1080x1920,同遊戲設計解像度一模一樣),但一次得一張。
##
## 用法(要開窗,要 GPU):
##   Godot --path . tools/shoot_screen.tscn -- --scene=res://scenes/Settings.tscn \
##         --name=settings --out=round-13-layout --locale=zh_TW

const VW := 1080
const VH := 1920

const ArtExport := preload("res://tools/art_export.gd")

var sub: SubViewport
var scene_path := "res://scenes/Settings.tscn"
var shot_name := "screen"
var outdir := ArtExport.QA_ROOT + "screen/"

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--name="):
			shot_name = a.substr(7)
		elif a.begins_with("--out="):
			outdir = ArtExport.qa_dir(a.substr(6))
		elif a.begins_with("--locale="):
			TranslationServer.set_locale(a.substr(9))
	get_tree().create_timer(120.0).timeout.connect(func():
		push_warning("shoot_screen timed out")
		get_tree().quit(2))

	# 影設定頁要有嘢可以顯示 —— 一個全鎖嘅存檔會影到一版灰
	Meta.highest_level = 5
	Meta.crystals = 4200
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

	var inst: Node = load(scene_path).instantiate()
	sub.add_child(inst)
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	var path: String = outdir + shot_name + ".png"
	img.save_png(path)
	print("SHOOT: wrote %s (%dx%d)" % [path, img.get_width(), img.get_height()])
	get_tree().quit(0)
