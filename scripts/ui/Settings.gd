extends Control

var confirm_reset: bool = false
var reset_btn: Button

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title(tr("NAV_SETTINGS"), 30, 520, 52))
	var back := UI.button(tr("NAV_BACK"), Vector2(200, 84), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	# everything sits on one framed plate instead of floating on bare colour
	var plate := UI.panel_rect()
	plate.position = Vector2(80, 240)
	plate.size = Vector2(920, 720)
	add_child(plate)

	var vb := VBoxContainer.new()
	vb.position = Vector2(140, 296)
	vb.size = Vector2(800, 0)
	vb.add_theme_constant_override("separation", 30)
	add_child(vb)

	# language (first: it is the one control a player who cannot read the current
	# language still has to be able to find)
	vb.add_child(_language_row())

	# volume
	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 20)
	var vlabel := UI.label(tr("SET_VOLUME"), 34, UI.TEXT)
	vlabel.custom_minimum_size = Vector2(180, 60)
	vrow.add_child(vlabel)
	# the default HSlider was the last unstyled cool-grey control in the game
	var slider := UI.slider(590)
	slider.min_value = 0; slider.max_value = 1; slider.step = 0.05
	slider.value = Meta.settings.get("volume", 0.8)
	slider.value_changed.connect(func(v):
		Meta.settings["volume"] = v
		Meta.apply_audio_settings()
		Meta.save_game())
	vrow.add_child(slider)
	vb.add_child(vrow)

	# mute
	var mute := UI.button("", Vector2(800, 96))
	var refresh_mute := func():
		mute.text = tr("SET_MUTE_ON") if Meta.settings.get("muted", false) else tr("SET_MUTE_OFF")
	refresh_mute.call()
	mute.pressed.connect(func():
		Meta.settings["muted"] = not Meta.settings.get("muted", false)
		Meta.apply_audio_settings()
		Meta.save_game()
		refresh_mute.call())
	vb.add_child(mute)

	# reset save (double confirm)
	reset_btn = UI.button(tr("SET_RESET"), Vector2(800, 96), UI.DANGER)
	reset_btn.pressed.connect(_on_reset)
	vb.add_child(reset_btn)

	var stat := UI.panel_dark()
	stat.position = Vector2(140, 830)
	stat.size = Vector2(800, 90)
	add_child(stat)
	var info := UI.label(tr("SET_STATS").format({
		"n": Meta.highest_level, "c": Meta.crystals}), 30, UI.TEXT_DIM)
	info.size = Vector2(800, 90)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.add_child(info)

## Label + one button per shipping locale. The selected one is highlighted; a
## tap switches immediately (Flow.set_locale reloads this scene, so the whole
## screen — this row included — comes back in the new language).
func _language_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var lbl := UI.label(tr("SET_LANGUAGE"), 34, UI.TEXT)
	lbl.custom_minimum_size = Vector2(300, 96)
	row.add_child(lbl)
	# read the TranslationServer, not the setting: it is what the text on screen
	# is actually coming from, so the highlight can never disagree with the words
	# next to it
	var cur := TranslationServer.get_locale()
	for l in Meta.LOCALES:
		var code: String = l.code
		var selected: bool = code == cur
		var b := UI.button(l.label, Vector2(230, 96),
			UI.ACCENT if selected else UI.PANEL_HI, 32)
		if not selected:
			b.modulate = Color(0.72, 0.70, 0.68)
		b.pressed.connect(func(): Flow.set_locale(code))
		row.add_child(b)
	return row

func _on_reset() -> void:
	if not confirm_reset:
		confirm_reset = true
		reset_btn.text = tr("SET_RESET_CONFIRM")
		return
	Meta.reset_save()
	reset_btn.text = tr("SET_RESET_DONE")
	confirm_reset = false
	get_tree().create_timer(0.8).timeout.connect(func(): Flow.goto(Flow.MAIN_MENU))
