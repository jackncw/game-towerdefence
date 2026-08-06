extends Control
## Debug self-audit gallery: every monster (10 families x lv1-5 + boss), all 20
## towers and 15 spell icons, at 1x and 2x nearest-neighbour, for readability QA.

func _ready() -> void:
	UI.fullscreen_bg(self, Color(0.11, 0.085, 0.065))
	var title := UI.title(tr("GALLERY_TITLE"), 40)
	title.position = Vector2(0, 30); title.size = Vector2(1080, 56)
	add_child(title)
	var back := UI.button(tr("NAV_BACK"), Vector2(200, 80), UI.PANEL, 28)
	back.position = Vector2(20, 34)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 120)
	scroll.size = Vector2(1040, 1760)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	TouchScroll.attach(scroll)   # see TouchScroll
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	scroll.add_child(vb)

	vb.add_child(_section(tr("GALLERY_MONSTERS")))
	for fam in GameData.family_ids():
		var famdef: Dictionary = GameData.FAMILIES[fam]
		vb.add_child(UI.label(tr(famdef.name), 28, UI.ACCENT))
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		for lvl in range(1, 6):
			grid.add_child(_cell(Assets.monster(fam, lvl), "Lv%d" % lvl))
		grid.add_child(_cell(Assets.monster_boss(fam), "Boss"))
		vb.add_child(grid)

	vb.add_child(_section(tr("GALLERY_TOWERS")))
	var tg := GridContainer.new()
	tg.columns = 6
	tg.add_theme_constant_override("h_separation", 8)
	tg.add_theme_constant_override("v_separation", 8)
	for t in GameData.TOWERS:
		tg.add_child(_cell(Assets.tower(t.id), tr(t.name)))
	vb.add_child(tg)

	vb.add_child(_section(tr("GALLERY_SPELLS")))
	var sg := GridContainer.new()
	sg.columns = 6
	sg.add_theme_constant_override("h_separation", 8)
	sg.add_theme_constant_override("v_separation", 8)
	for s in GameData.SPELLS:
		sg.add_child(_cell(Assets.spell(s.id), tr(s.name)))
	vb.add_child(sg)

func _section(txt: String) -> Control:
	var p := UI.panel_rect()
	p.custom_minimum_size = Vector2(1000, 60)
	var l := UI.label(txt, 32, UI.TEXT)
	l.position = Vector2(20, 10)
	p.add_child(l)
	return p

func _cell(tex: Texture2D, label: String) -> Control:
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(160, 150)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 8)
	# 「原檔 1x + 2x」呢個擺法喺舊嘅 32-96px 程序圖啱用。新怪物圖 66-189px,
	# 2x 就係 378px,一格 160px 直接爆晒。改為「戰鬥入面嘅真實顯示尺寸」——
	# 本來 debug gallery 想睇嘅就係呢個 —— 再加一張半尺寸做細位辨識度參考。
	var sz := tex.get_size()
	var k: float = minf(1.0, 120.0 / maxf(sz.x, sz.y))
	hb.add_child(UI.tex_rect(tex, sz * k * 0.5))
	hb.add_child(UI.tex_rect(tex, sz * k))
	vb.add_child(hb)
	# English tower/spell names are ~2x the width of the 繁中 ones and overran the
	# 160px cell, so the caption wraps inside the cell instead of bleeding into
	# its neighbour
	var l := UI.label(label, 20, Color(0.8, 0.85, 0.9))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(156, 46)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	return vb
