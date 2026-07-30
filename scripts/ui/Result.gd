extends Control

func _ready() -> void:
	# was a flat dark-green fill — a colour that appears nowhere else in the game
	UI.menu_backdrop(self, Color(0.42, 0.86, 0.46, 0.55))
	var r: Dictionary = Flow.last_result
	var lv: int = r.get("level", 1)

	add_child(UI.banner_title("關卡完成!", 168, 760, 62))
	var sub := UI.title("第 %d 關" % lv, 40)
	sub.position = Vector2(0, 300); sub.size = Vector2(1080, 60)
	add_child(sub)

	var panel := UI.panel_rect()
	panel.position = Vector2(190, 382)
	panel.size = Vector2(700, 366)
	add_child(panel)

	var vb := VBoxContainer.new()
	vb.position = Vector2(60, 34)
	vb.size = Vector2(580, 300)
	vb.add_theme_constant_override("separation", 20)
	panel.add_child(vb)

	vb.add_child(_stat_row("擊殺數", str(r.get("kills", 0)), UI.TEXT, null))
	# 魔晶 payout is itemised: the clear reward and the one-off first-clear bonus
	# are separate lines so the bonus reads as an event, not as a bigger number.
	var base: int = r.get("base", r.get("crystals", 0))
	var first: int = r.get("first", 0)
	vb.add_child(_stat_row("通關獎勵", str(base), UI.CRYSTAL, Assets.crystal()))
	if first > 0:
		vb.add_child(_stat_row("首次通關獎勵", "+%d" % first, UI.GOLD,
			Assets.crystal(), Assets.ui("ic_star")))
		vb.add_child(_stat_row("合計", str(base + first), UI.CRYSTAL, Assets.crystal()))
	if r.get("replay", false):
		var note := UI.label("(重玩關卡,魔晶獎勵減半)", 24, Color(0.7, 0.6, 0.85))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(note)

	# buttons
	var hb := HBoxContainer.new()
	hb.position = Vector2(140, 770)
	hb.add_theme_constant_override("separation", 24)
	add_child(hb)
	var nextn := lv + 1
	var nxt := UI.button("下一關 (%d)" % nextn, Vector2(360, 130), UI.ACCENT, 36)
	nxt.pressed.connect(func(): Flow.play_level(nextn))
	hb.add_child(nxt)
	var replay := UI.button("重玩本關", Vector2(360, 130), UI.PANEL_HI, 36)
	replay.pressed.connect(func(): Flow.play_level(lv))
	hb.add_child(replay)

	var home := UI.button("返回主選單", Vector2(500, 110), UI.PANEL, 34)
	home.position = Vector2(290, 930)
	home.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(home)

func _stat_row(name: String, value: String, col: Color, tex: Texture2D,
		lead: Texture2D = null) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	# `lead` marks the row as special (star on the first-clear bonus) and eats
	# into the label width so every row's value column still lines up.
	var lw := 280.0
	if lead:
		h.add_child(UI.tex_rect(lead, Vector2(40, 40)))
		lw -= 54.0
	var l := UI.label(name + ":", 36, UI.GOLD if lead else UI.TEXT)
	l.custom_minimum_size = Vector2(lw, 50)
	h.add_child(l)
	if tex:
		h.add_child(UI.tex_rect(tex, Vector2(44, 44)))
	h.add_child(UI.label(value, 42, col))
	return h
