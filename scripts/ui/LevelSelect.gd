extends Control

## 無盡段最多列幾多格。**唔係一個美學數字,係一個節點數上限** —— 見下面
## _ready() 入面嗰段註解。30 = 十行,捲多兩下就見到,而且遠遠唔會令呢一頁
## 嘅節點數爆走。
const ENDLESS_SHOWN := 30

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
	# 一個 VBox 包住「1-100 格仔陣」同「無盡段」兩截。點解唔全部塞入同一個
	# GridContainer:無盡段個標題要食滿成行,而一個 GridContainer 入面冇「跨欄」
	# 呢回事 —— 標題會被當成一格,夾喺兩張卡中間。
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	scroll.add_child(col)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	col.add_child(grid)

	# 全部已通關嘅 + 下一關,封頂喺最終關(第 100 關)
	var maxn: int = clampi(Meta.highest_level + 1, 1, GameData.FINAL_LEVEL)
	for n in range(1, maxn + 1):
		grid.add_child(_level_card(n))

	# ── 無盡段(第 24 輪)────────────────────────────────────────────────
	# 通關第 100 關之後解鎖。**唔係**照樣一關一格排落去:一個打到第 300 關嘅
	# 存檔會砌出三百個 Button(每個入面仲有一個 VBox 三個 Label)—— 一頁千幾
	# 個節點,而呢一頁喺一部電話上面係常客,而且佢就係 2026-08-02 嗰單閃退
	# 麵包屑入面嘅高峰記憶體嫌疑之一(見 MainMenu 拆走畫廊入口嗰段)。
	# 所以無盡段只列**最近 ENDLESS_SHOWN 關 + 下一關**,而「行到第幾關」
	# 交畀上面嗰塊標題講。
	if Meta.endless_unlocked():
		var enext: int = maxi(GameData.FINAL_LEVEL + 1, Meta.highest_level + 1)
		var elo: int = maxi(GameData.FINAL_LEVEL + 1, enext - ENDLESS_SHOWN + 1)
		var head := UI.panel_dark()
		head.custom_minimum_size = Vector2(980, 132)
		col.add_child(head)
		var htitle := UI.label(tr("ENDLESS_SECTION"), 34, UI.CRYSTAL)
		htitle.position = Vector2(0, 16); htitle.size = Vector2(980, 44)
		htitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(htitle)
		var hsub := UI.label(tr("ENDLESS_PROGRESS").format(
			{"n": Meta.endless_progress(), "lv": Meta.highest_level}), 26, UI.TEXT_DIM)
		hsub.position = Vector2(0, 66); hsub.size = Vector2(980, 36)
		hsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		head.add_child(hsub)
		if elo > GameData.FINAL_LEVEL + 1:
			var more := UI.label(tr("ENDLESS_SHOWING").format({"n": ENDLESS_SHOWN}), 22,
				UI.TEXT_DIM.darkened(0.1))
			more.position = Vector2(0, 100); more.size = Vector2(980, 30)
			more.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			head.add_child(more)
		var egrid := GridContainer.new()
		egrid.columns = 3
		egrid.add_theme_constant_override("h_separation", 20)
		egrid.add_theme_constant_override("v_separation", 20)
		col.add_child(egrid)
		for n in range(elo, enext + 1):
			egrid.add_child(_level_card(n))

	# 進度條 —— 一百關嘅格仔陣列本身睇唔出「行到邊」,尤其係捲到中段嗰陣。
	# 無盡段解鎖之後個分母冇咗意思(冇上限),所以換一句只講「行到第幾關」。
	var prog := UI.label(
		tr("LEVELSEL_PROGRESS_ENDLESS").format({"n": Meta.highest_level})
		if Meta.endless_unlocked()
		else tr("LEVELSEL_PROGRESS").format({
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
	# 全 boss 關 = 第 100、200、300… 關。無盡段每一百關重演一次 finale 編排,
	# 所以佢哋要同第 100 關同一個樣。
	var final_lv := GameData.is_boss_finale_level(n)
	# 3-up, taller cards: at 4-up/150px tall the three lines of text ran over
	# the frame's bevel and the screen was three-quarters empty
	var base_col: Color = UI.PANEL_HI if unlocked else UI.PANEL
	if unlocked and contract:
		base_col = Color(0.42, 0.26, 0.34)     # 合約關:紫調
	if unlocked and GameData.is_endless_level(n) and not contract and not final_lv:
		base_col = Color(0.26, 0.24, 0.42)     # 無盡段普通關:藍紫
	if unlocked and final_lv:
		base_col = Color(0.48, 0.22, 0.16)     # 全 boss 關:赤紅
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
	var tag_key := ""
	var tag_col := Color(0.86, 0.66, 1.0)
	if final_lv:
		tag_key = "LEVELSEL_FINAL" if n == GameData.FINAL_LEVEL else "ENDLESS_FINALE_TAG"
		tag_col = Color(1.0, 0.72, 0.35)
	elif contract:
		tag_key = "LEVELSEL_CONTRACT"
	elif GameData.is_endless_level(n):
		tag_key = "ENDLESS_TAG"
		tag_col = UI.CRYSTAL
	if tag_key != "":
		var tag := UI.label(tr(tag_key), 24, tag_col)
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(tag)
	var status := tr("LEVELSEL_CLEARED") if cleared else (
		tr("LEVELSEL_AVAILABLE") if unlocked else tr("LEVELSEL_LOCKED"))
	var s := UI.label(status, 26, UI.ACCENT if cleared else UI.TEXT_DIM)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(s)
	# 通關第 100 關之後重玩派全額,嗰句「減半」就變成一句錯嘅嘢。
	if cleared and Meta.replay_penalty_active():
		var half := UI.label(tr("LEVELSEL_REPLAY_HALF"), 20, UI.CRYSTAL.darkened(0.15))
		half.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		half.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(half)
	elif cleared:
		var full := UI.label(tr("LEVELSEL_REPLAY_FULL"), 20, UI.ACCENT.darkened(0.1))
		full.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		full.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(full)
	btn.add_child(vb)
	if unlocked:
		btn.pressed.connect(func(): Flow.play_level(n))
	return btn
