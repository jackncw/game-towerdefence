extends Control

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title("選擇關卡", 26, 520, 50))

	var back := UI.button("← 返回", Vector2(200, 88), UI.PANEL, 30)
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
	scroll.position = Vector2(40, 170)
	scroll.size = Vector2(1000, 1680)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(grid)

	# show cleared levels + the next unlocked one
	var maxn: int = maxi(1, Meta.highest_level + 1)
	for n in range(1, maxn + 1):
		grid.add_child(_level_card(n))

func _level_card(n: int) -> Control:
	var cleared := Meta.is_cleared(n)
	var unlocked := n <= Meta.highest_level + 1
	# 3-up, taller cards: at 4-up/150px tall the three lines of text ran over
	# the frame's bevel and the screen was three-quarters empty
	var btn := UI.button("", Vector2(310, 220), UI.PANEL_HI if unlocked else UI.PANEL, 30)
	btn.disabled = not unlocked
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.position = Vector2(28, 30)
	vb.size = Vector2(254, 160)
	vb.add_theme_constant_override("separation", 6)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var l := UI.label("第 %d 關" % n, 42, UI.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(l)
	var status := "★ 已通關" if cleared else ("可挑戰" if unlocked else "未解鎖")
	var s := UI.label(status, 26, UI.ACCENT if cleared else UI.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(s)
	if cleared:
		var half := UI.label("重玩魔晶減半", 20, UI.CRYSTAL.darkened(0.15))
		half.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(half)
	btn.add_child(vb)
	if unlocked:
		btn.pressed.connect(func(): Flow.play_level(n))
	return btn
