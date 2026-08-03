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
	#
	# 個高度由 720 加到 1000。原本嗰個唔夠高:六行控制項由 y=296 排落去要到
	# 914,而「最高通關」面板釘死喺 y=830 —— 即係話**「重置存檔」掣一直俾嗰
	# 塊面板蓋住**,出街版只露得返一條紅色頂邊。呢個唔係今輪整壞嘅,係影相
	# 對比嗰陣先見到(qa/screenshots/round-13-layout/settings-zh-BEFORE.png)。
	# 今輪要喺呢一版加一粒省電掣,就冇可能唔順手擺返好個高度。
	var plate := UI.panel_rect()
	plate.position = Vector2(80, 240)
	plate.size = Vector2(920, 1000)
	add_child(plate)

	var vb := VBoxContainer.new()
	vb.position = Vector2(140, 296)
	vb.size = Vector2(800, 0)
	vb.add_theme_constant_override("separation", 30)
	add_child(vb)

	# language (first: it is the one control a player who cannot read the current
	# language still has to be able to find)
	vb.add_child(_language_row())

	# 總音量 / 音樂 / 音效 — three sliders over the Master / BGM / SFX buses
	vb.add_child(_volume_row("SET_VOLUME", "volume"))
	vb.add_child(_volume_row("SET_VOLUME_BGM", "volume_bgm"))
	vb.add_child(_volume_row("SET_VOLUME_SFX", "volume_sfx"))

	# mute
	var mute := UI.button("", Vector2(800, 96))
	var refresh_mute := func():
		mute.text = tr("SET_MUTE_ON") if Meta.settings.get("muted", false) else tr("SET_MUTE_OFF")
	refresh_mute.call()
	mute.pressed.connect(func():
		Meta.settings["muted"] = not Meta.settings.get("muted", false)
		Meta.apply_audio_settings()
		Meta.save_game()
		refresh_mute.call()
		# the click has to survive its own un-mute, so it plays after the toggle
		if not Meta.settings.get("muted", false):
			Audio.play("ui_click"))
	vb.add_child(mute)

	# 省電模式 —— 幀率上限 60 -> 30。同靜音一樣用「一粒掣兩個字串」嘅寫法。
	var power := UI.button("", Vector2(800, 96))
	var refresh_power := func():
		power.text = tr("SET_POWER_ON") if Meta.settings.get("power_save", false) \
			else tr("SET_POWER_OFF")
	refresh_power.call()
	power.pressed.connect(func():
		Meta.settings["power_save"] = not Meta.settings.get("power_save", false)
		# 即刻生效先算數:一個要重開先生效嘅慳電掣,玩家撳完見唔到分別
		# 就只會當佢壞咗。
		Flow.apply_frame_cap()
		Meta.save_game()
		refresh_power.call()
		Audio.play("ui_click"))
	vb.add_child(power)

	var phint := UI.label(tr("SET_POWER_HINT"), 22, UI.TEXT_DIM)
	phint.custom_minimum_size = Vector2(800, 56)
	phint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(phint)

	# reset save (double confirm)
	reset_btn = UI.button(tr("SET_RESET"), Vector2(800, 96), UI.DANGER)
	reset_btn.pressed.connect(_on_reset)
	vb.add_child(reset_btn)

	var stat := UI.panel_dark()
	# 排喺最後一行控制項下面(見上面個 plate 嘅註解),唔再壓住佢
	stat.position = Vector2(140, 1120)
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

## One labelled slider bound to a settings key. Dragging previews the change
## immediately (that is the only way to judge a volume) and saves as it goes.
func _volume_row(label_key: String, setting_key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	var l := UI.label(tr(label_key), 34, UI.TEXT)
	l.custom_minimum_size = Vector2(180, 60)
	row.add_child(l)
	# the default HSlider was the last unstyled cool-grey control in the game
	var slider := UI.slider(590)
	slider.min_value = 0; slider.max_value = 1; slider.step = 0.05
	slider.value = Meta.audio_volume(setting_key)
	slider.value_changed.connect(func(v):
		Meta.set_audio_volume(setting_key, v)
		# audition the bus you just moved, so the slider means something
		if setting_key == "volume_bgm":
			Audio.play_bgm("bgm_battle")
		else:
			Audio.play("ui_click"))
	row.add_child(slider)
	return row
