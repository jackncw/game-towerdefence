extends Control

func _ready() -> void:
	# was a flat dark-green fill — a colour that appears nowhere else in the game
	UI.menu_backdrop(self, Color(0.42, 0.86, 0.46, 0.55))
	var r: Dictionary = Flow.last_result
	var lv: int = r.get("level", 1)

	add_child(UI.banner_title(tr("RESULT_TITLE"), 168, 760, 62))
	# 無盡段嘅關卡編號本身睇唔出「呢關係無盡段」,而全 boss 關更加要認得出。
	# 用同一行副標題加一個尾綴,唔另開一行 —— 下面塊面板釘死喺 y=382,
	# 加一行就會頂到佢。
	var subtxt := tr("COMMON_LEVEL_N").format({"n": lv})
	if GameData.is_endless_level(lv):
		subtxt += "  ·  " + tr("ENDLESS_FINALE_TAG" if GameData.is_boss_finale_level(lv)
			else "ENDLESS_TAG")
	var sub := UI.title(subtxt, 40)
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

	vb.add_child(_stat_row(tr("RESULT_KILLS"), str(r.get("kills", 0)), UI.TEXT, null))
	# 魔晶 payout is itemised: the clear reward and the one-off first-clear bonus
	# are separate lines so the bonus reads as an event, not as a bigger number.
	var base: int = r.get("base", r.get("crystals", 0))
	var first: int = r.get("first", 0)
	vb.add_child(_stat_row(tr("RESULT_CLEAR_REWARD"), str(base), UI.CRYSTAL, Assets.crystal()))
	if first > 0:
		vb.add_child(_stat_row(tr("RESULT_FIRST_CLEAR"), "+%d" % first, UI.GOLD,
			Assets.crystal(), Assets.ui("ic_star")))
		vb.add_child(_stat_row(tr("RESULT_TOTAL"), str(base + first), UI.CRYSTAL, Assets.crystal()))
	# 合約關:倍率已經計入上面嘅數,所以呢一行係一個**解釋**,唔係一個加項。
	if float(r.get("mult", 1.0)) > 1.001:
		var cm := UI.label(tr("RESULT_CONTRACT_MULT").format(
			{"n": "%.2f" % float(r.get("mult", 1.0))}), 28, Color(0.86, 0.66, 1.0))
		cm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(cm)
	if r.get("replay", false):
		var note := UI.label(tr("RESULT_REPLAY_NOTE"), 24, Color(0.7, 0.6, 0.85))
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vb.add_child(note)

	# buttons
	var hb := HBoxContainer.new()
	hb.position = Vector2(140, 770)
	hb.add_theme_constant_override("separation", 24)
	add_child(hb)
	var nextn := lv + 1
	## 「下一關」喺無盡段一樣要有 —— 之前個條件係 `nextn <= FINAL_LEVEL`,即係
	## 一過咗第 100 關,結算畫面就淨返「重玩」同「主選單」,而無盡段嘅正常
	## 玩法就係一關接一關。條件而家係「下一關存在」:1-100 一路有,而通關咗
	## 第 100 關之後永遠有(無盡段冇上限)。
	if nextn <= GameData.FINAL_LEVEL or Meta.endless_unlocked():
		var nxt := UI.button(tr("RESULT_NEXT").format({"n": nextn}), Vector2(360, 130), UI.ACCENT, 36)
		nxt.pressed.connect(func(): Flow.play_level(nextn))
		hb.add_child(nxt)
	var replay := UI.button(tr("RESULT_REPLAY"), Vector2(360, 130), UI.PANEL_HI, 36)
	replay.pressed.connect(func(): Flow.play_level(lv))
	hb.add_child(replay)

	var home := UI.button(tr("NAV_MAIN_MENU"), Vector2(500, 110), UI.PANEL, 34)
	home.position = Vector2(290, 930)
	home.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(home)

func _stat_row(name: String, value: String, col: Color, tex: Texture2D,
		lead: Texture2D = null) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	# `lead` marks the row as special (star on the first-clear bonus) and eats
	# into the label width so every row's value column still lines up. The column
	# is sized for the longest ENGLISH label (First Clear Bonus), which is roughly
	# twice the width of its 繁中 counterpart.
	var lw := 380.0
	if lead:
		h.add_child(UI.tex_rect(lead, Vector2(40, 40)))
		lw -= 54.0
	var l := UI.label(name + ":", 30, UI.GOLD if lead else UI.TEXT)
	l.custom_minimum_size = Vector2(lw, 50)
	h.add_child(l)
	if tex:
		h.add_child(UI.tex_rect(tex, Vector2(44, 44)))
	h.add_child(UI.label(value, 42, col))
	return h
