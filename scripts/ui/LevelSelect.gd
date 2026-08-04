extends Control

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title(tr("NAV_LEVEL_SELECT"), 26, 520, 50))

	var back := UI.button(tr("NAV_BACK"), Vector2(200, 88), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	# framed crystal badge, matching the main menu (it was bare text here)
	var cbadge := UI.panel_dark()
	cbadge.position = Vector2(806, 34)
	cbadge.size = Vector2(230, 72)
	add_child(cbadge)
	var crys := UI.currency_row(Assets.crystal(), Meta.crystals, UI.CRYSTAL, 34)
	crys.position = Vector2(830, 50)
	add_child(crys)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 186)
	scroll.size = Vector2(1000, 1664)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	TouchScroll.attach(scroll)   # level tiles are Buttons; see TouchScroll
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	# 全部已通關嘅 + 下一關,封頂喺最終關(第 100 關)
	var maxn: int = clampi(Meta.highest_level + 1, 1, GameData.FINAL_LEVEL)
	for n in range(1, maxn + 1):
		grid.add_child(_level_card(n))

	# 進度條 —— 一百關嘅格仔陣列本身睇唔出「行到邊」,尤其係捲到中段嗰陣
	var prog := UI.label(tr("LEVELSEL_PROGRESS").format({
		"n": mini(Meta.highest_level, GameData.FINAL_LEVEL), "t": GameData.FINAL_LEVEL}),
		28, UI.TEXT_DIM)
	# 132 而唔係 112:橫幅嘅下緣去到 ~125,擺喺 112 會俾框邊食一半。
	prog.position = Vector2(40, 132)
	prog.size = Vector2(1000, 44)
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prog)

## 合約關(逢 7)同最終關(第 100)喺格仔上面要一眼認得出。用**顏色 + 一行
## 標籤**,唔用一個新圖示:標籤講得出「呢關係乜」,而一個冇人解釋過嘅圖示
## 只係一個問號。
func _level_card(n: int) -> Control:
	var cleared := Meta.is_cleared(n)
	var unlocked := n <= Meta.highest_level + 1
	var contract := GameData.is_contract_level(n)
	var final_lv := GameData.is_final_level(n)
	# 3-up, taller cards: at 4-up/150px tall the three lines of text ran over
	# the frame's bevel and the screen was three-quarters empty
	var base_col: Color = UI.PANEL_HI if unlocked else UI.PANEL
	if unlocked and contract:
		base_col = Color(0.42, 0.26, 0.34)     # 合約關:紫調
	if unlocked and final_lv:
		base_col = Color(0.48, 0.22, 0.16)     # 最終關:赤紅
	var btn := UI.button("", Vector2(310, 240), base_col, 30)
	btn.disabled = not unlocked
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.position = Vector2(28, 26)
	vb.size = Vector2(254, 188)
	vb.add_theme_constant_override("separation", 4)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UI.label(tr("COMMON_LEVEL_N").format({"n": n}), 42, UI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	if contract or final_lv:
		var tag := UI.label(tr("LEVELSEL_FINAL" if final_lv else "LEVELSEL_CONTRACT"), 24,
			Color(1.0, 0.72, 0.35) if final_lv else Color(0.86, 0.66, 1.0))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tag)
	var status := tr("LEVELSEL_CLEARED") if cleared else (
		tr("LEVELSEL_AVAILABLE") if unlocked else tr("LEVELSEL_LOCKED"))
	var s := UI.label(status, 26, UI.ACCENT if cleared else UI.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(s)
	if cleared:
		var half := UI.label(tr("LEVELSEL_REPLAY_HALF"), 20, UI.CRYSTAL.darkened(0.15))
		half.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(half)
	btn.add_child(vb)
	if unlocked:
		btn.pressed.connect(func(): Flow.play_level(n))
	return btn
