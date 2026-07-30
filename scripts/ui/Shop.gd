extends Control

var crystal_label: Label
var refreshers: Array = []

func _ready() -> void:
	UI.fullscreen_bg(self, UI.BG)
	var title := UI.title(tr("SHOP_TITLE"), 56)
	title.position = Vector2(0, 40); title.size = Vector2(1080, 70)
	add_child(title)
	var back := UI.button(tr("NAV_BACK"), Vector2(200, 88), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)
	var crow := UI.currency_row(Assets.crystal(), Meta.crystals, UI.CRYSTAL, 38)
	crow.position = Vector2(840, 44)
	add_child(crow)
	crystal_label = crow.get_child(1)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 150)
	scroll.size = Vector2(1020, 1700)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	scroll.add_child(vb)

	vb.add_child(_header(tr("COMMON_TOWERS")))
	var tg := _grid()
	vb.add_child(tg)
	for t in GameData.TOWERS:
		tg.add_child(_unlock_card(t, true))

	vb.add_child(_header(tr("COMMON_SPELLS")))
	var sg := _grid()
	vb.add_child(sg)
	for s in GameData.SPELLS:
		sg.add_child(_unlock_card(s, false))

func _header(txt: String) -> Label:
	var l := UI.label(txt, 40, UI.ACCENT)
	l.custom_minimum_size = Vector2(960, 60)
	return l

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 16)
	g.add_theme_constant_override("v_separation", 16)
	return g

## One card builder for both shelves — the tower and spell versions were the same
## 40 lines twice, differing only in the texture, the price source, the verb and
## the unlock call.
func _unlock_card(def: Dictionary, is_tower: bool) -> Control:
	var cost: int = int(def.unlock) if is_tower else Meta.spell_unlock_cost(def.id)
	var card := UI.panel_rect()
	# taller than the round-4 card, and the text column starts further left: an
	# English name/description is roughly twice as wide as the 繁中 one, so both
	# now get a wrapping two/three-line box instead of a single fixed line.
	card.custom_minimum_size = Vector2(320, 226)
	var icon := UI.tex_rect(Assets.tower(def.id) if is_tower else Assets.spell(def.id),
		Vector2(88, 88))   # 2x of 44
	icon.position = Vector2(10, 12)
	card.add_child(icon)
	var nm := _wrap_box(card, Vector2(104, 8), Vector2(202, 62), tr(def.name), 24, UI.TEXT)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A free Label wraps unreliably, so the text lives FULL_RECT inside a fixed
	# clip box (this is why the longer tower descriptions used to spill over the
	# card frame and the unlock button)
	_wrap_box(card, Vector2(104, 74), Vector2(202, 76), tr(def.desc), 17, UI.TEXT_DIM)

	var action := UI.button("", Vector2(288, 58), UI.ACCENT if is_tower else Color(0.35, 0.4, 0.7), 28)
	action.position = Vector2(16, 154)
	card.add_child(action)
	# the price used a 💎 emoji — the only place in the game where 魔晶 was not the
	# purple crystal sprite (and a glyph the CJK system font can render as tofu)
	var price := HBoxContainer.new()
	price.add_theme_constant_override("separation", 6)
	price.position = Vector2(150, 11)
	price.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_child(UI.tex_rect(Assets.crystal(), Vector2(36, 36)))
	var price_lbl := UI.label(str(cost), 28, UI.CRYSTAL.lightened(0.35))
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price.add_child(price_lbl)
	action.add_child(price)

	var refresh := func():
		var owned: bool = Meta.is_tower_unlocked(def.id) if is_tower else Meta.is_spell_unlocked(def.id)
		var buyable: bool = not owned and cost > 0
		price.visible = buyable
		# the label sits left of the price badge while there is a price to show,
		# and re-centres once the card reads 已擁有 / 初始解鎖
		action.alignment = HORIZONTAL_ALIGNMENT_LEFT if buyable else HORIZONTAL_ALIGNMENT_CENTER
		if owned:
			action.text = tr("SHOP_OWNED")
			action.disabled = true
		elif cost <= 0:
			action.text = tr("SHOP_STARTER")
			action.disabled = true
		else:
			action.text = tr("SHOP_UNLOCK") if is_tower else tr("SHOP_LEARN")
			action.disabled = not Meta.can_afford(cost)
	action.pressed.connect(func():
		var ok: bool = Meta.unlock_tower(def.id) if is_tower else Meta.unlock_spell(def.id)
		if ok:
			_refresh_all())
	refreshers.append(refresh)
	refresh.call()
	return card

## A fixed-size clipped box holding a wrapping Label. Free Labels wrap
## unreliably, so every variable-length string on a card goes through here.
## WORD_SMART (not ARBITRARY) matters now that the same box has to hold both
## languages: ARBITRARY chops English mid-word ("physi / cal shots"), while
## WORD_SMART still falls back to grapheme breaks for a space-less CJK run.
func _wrap_box(parent: Control, pos: Vector2, sz: Vector2, text: String,
		fs: int, col: Color) -> Label:
	var box := Control.new()
	box.position = pos
	box.size = sz
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	var l := UI.label(text, fs, col)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(l)
	return l

func _refresh_all() -> void:
	crystal_label.text = str(Meta.crystals)
	for r in refreshers:
		r.call()
