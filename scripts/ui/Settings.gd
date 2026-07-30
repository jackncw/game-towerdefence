extends Control

var confirm_reset: bool = false
var reset_btn: Button

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title("設定", 30, 520, 52))
	var back := UI.button("← 返回", Vector2(200, 84), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	# everything sits on one framed plate instead of floating on bare colour
	var plate := UI.panel_rect()
	plate.position = Vector2(80, 240)
	plate.size = Vector2(920, 580)
	add_child(plate)

	var vb := VBoxContainer.new()
	vb.position = Vector2(140, 300)
	vb.size = Vector2(800, 0)
	vb.add_theme_constant_override("separation", 40)
	add_child(vb)

	# volume
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 20)
	vrow.add_child(UI.label("音量", 36, UI.TEXT))
	# the default HSlider was the last unstyled cool-grey control in the game
	var slider := UI.slider(560)
	slider.min_value = 0; slider.max_value = 1; slider.step = 0.05
	slider.value = Meta.settings.get("volume", 0.8)
	slider.value_changed.connect(func(v):
		Meta.settings["volume"] = v
		Meta.apply_audio_settings()
		Meta.save_game())
	vrow.add_child(slider)
	vb.add_child(vrow)

	# mute
	var mute := UI.button("", Vector2(800, 100))
	var refresh_mute := func():
		mute.text = "靜音: 開" if Meta.settings.get("muted", false) else "靜音: 關"
	refresh_mute.call()
	mute.pressed.connect(func():
		Meta.settings["muted"] = not Meta.settings.get("muted", false)
		Meta.apply_audio_settings()
		Meta.save_game()
		refresh_mute.call())
	vb.add_child(mute)

	# reset save (double confirm)
	reset_btn = UI.button("重置存檔", Vector2(800, 100), UI.DANGER)
	reset_btn.pressed.connect(_on_reset)
	vb.add_child(reset_btn)

	var stat := UI.panel_dark()
	stat.position = Vector2(140, 690)
	stat.size = Vector2(800, 90)
	add_child(stat)
	var info := UI.label("最高通關: 第 %d 關     魔晶: %d" % [Meta.highest_level, Meta.crystals], 30, UI.TEXT_DIM)
	info.size = Vector2(800, 90)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.add_child(info)

func _on_reset() -> void:
	if not confirm_reset:
		confirm_reset = true
		reset_btn.text = "確定要重置? 再按一次"
		return
	Meta.reset_save()
	reset_btn.text = "已重置"
	confirm_reset = false
	get_tree().create_timer(0.8).timeout.connect(func(): Flow.goto(Flow.MAIN_MENU))
