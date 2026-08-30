extends Control

func _ready() -> void:
	Audio.play_bgm("bgm_menu")
	UI.menu_backdrop(self)

	# ornate title plate + title
	var plate := TextureRect.new()
	plate.texture = Assets.ui("title_plate")
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	plate.stretch_mode = TextureRect.STRETCH_SCALE
	plate.position = Vector2(120, 200)
	plate.size = Vector2(840, 190)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(plate)
	var title := UI.title(tr("MENU_TITLE"), 84)
	title.position = Vector2(120, 230)
	title.size = Vector2(840, 110)
	add_child(title)
	var sub := UI.title(tr("MENU_SUBTITLE"), 32)
	sub.position = Vector2(120, 336)
	sub.size = Vector2(840, 46)
	sub.add_theme_color_override("font_color", Color(0.82, 0.74, 0.55))
	add_child(sub)

	# crystal display (framed badge)
	var cbadge := UI.panel_dark()
	cbadge.position = Vector2(792, 40)
	cbadge.size = Vector2(240, 72)
	add_child(cbadge)
	var crys := UI.currency_row(Assets.crystal(), Meta.crystals, UI.CRYSTAL, 40)
	crys.position = Vector2(816, 56)
	add_child(crys)

	# buttons
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 26)
	vb.position = Vector2(240, 620)
	vb.size = Vector2(600, 0)
	add_child(vb)

	var next_n: int = Meta.next_level()
	var play := UI.button(tr("MENU_PLAY").format({"n": next_n}), Vector2(600, 120), UI.ACCENT, 40)
	play.pressed.connect(func(): Flow.play_level(next_n))
	vb.add_child(play)

	var sel := UI.button(tr("NAV_LEVEL_SELECT"), Vector2(600, 110))
	sel.pressed.connect(func(): Flow.goto(Flow.LEVEL_SELECT))
	vb.add_child(sel)

	var shop := UI.button(tr("MENU_SHOP"), Vector2(600, 110))
	shop.pressed.connect(func(): Flow.goto(Flow.SHOP))
	vb.add_child(shop)

	var up := UI.button(tr("MENU_UPGRADE"), Vector2(600, 110))
	up.pressed.connect(func(): Flow.goto(Flow.UPGRADE))
	vb.add_child(up)

	var quick := UI.button(tr("MENU_QUICKBAR"), Vector2(600, 110))
	quick.pressed.connect(func(): Flow.goto(Flow.QUICKBAR))
	vb.add_child(quick)

	var bestiary := UI.button(tr("NAV_BESTIARY"), Vector2(600, 110))
	bestiary.pressed.connect(func(): Flow.goto(Flow.BESTIARY))
	vb.add_child(bestiary)

	var settings := UI.button(tr("NAV_SETTINGS"), Vector2(600, 110))
	settings.pressed.connect(func(): Flow.goto(Flow.SETTINGS))
	vb.add_child(settings)

	# 美術畫廊(除錯)嘅入口喺呢度除名咗 —— 佢係一個開發工具,唔係一個玩家
	# 功能,而佢一路都喺出街版嘅主選單度一撳就入。
	#
	# 唔係「整潔」問題,係量出嚟嘅:嗰一頁一次過砌 95 個 sprite 格,峰值比
	# 主選單多 5.03 MB / 496 個節點(tools/menu_leak.gd)。喺一部已經貼住
	# Safari tab 上限嘅 iPhone 上面,呢個數唔細 —— 而佢喺 2026-08-02 嗰單
	# 閃退嘅麵包屑入面,正正就係死之前最後去嗰個畫面。
	#
	# 畫廊本身冇刪:tools/art_export.gd 同 SoakTest 仲會由原始碼開佢。佢淨係
	# 唔再出貨 —— 見 export_presets.cfg 嘅 exclude_filter。

	# 「上次係閃退」報告畫面 **喺呢度拆走咗**(第 24 輪,上架前)。
	#
	# 點解:嗰個畫面係為咗查一單具體嘅 iOS 網頁版閃退而加嘅診斷工具,而佢
	# 出現嘅時機係「開機第一眼」。對一個查緊 bug 嘅人嚟講咁啱;對一個買咗
	# 隻遊戲嘅玩家嚟講,佢係一版紅字 + 一堆佢睇唔明嘅麵包屑,而且佢會喺
	# **任何**非正常結束之後彈 —— 包括「用家自己 force-quit 咗個 app」呢種
	# 完全正常嘅事。一個嚇親玩家嘅假警報,唔值。
	#
	# **底層一個字都冇拆。** Crash autoload 照樣寫 marker、麵包屑同
	# user://logs/crash.log —— 嗰啲係查問題嘅真證物,而且成本係事件級唔係
	# 逐幀。變嘅只係「邊個睇得到」:而家要喺設定頁長撳版本號五秒先開到
	# (見 Settings.gd)。理由喺報告 Part B。

	# one-time notice after a save migration (詛咒塔 rework refund). Shown here
	# because the main menu is the first screen an existing save ever reaches.
	if Meta.rework_refund > 0:
		var amount: int = Meta.rework_refund
		Meta.rework_refund = 0
		await get_tree().process_frame
		UI.toast(self, tr("TOAST_CURSE_REFUND").format({"n": amount}), UI.GOLD)
