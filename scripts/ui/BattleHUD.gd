extends Control
## In-battle HUD. Portrait layout after gameUI.jpg: top bar (pause/mute | level +
## boss timer | speed), currency row (gold left, crystal right), boss HP bar,
## bottom spell quickbar + tower build bar, and a tower-select panel.

var battle
var gold_label: Label
var crystal_label: Label
var level_label: Label
var boss_timer_label: Label
var speed_btn: Button
var mute_btn: Button
var boss_box: Control
var boss_bar: ProgressBar
var boss_heal_rect: ColorRect     # green rebound band over the boss HP bar
var boss_name: Label
var _boss_frac: float = -1.0      # HP fraction shown last frame
## Lowest fraction the bar has reached since the boss last took damage. The green
## band spans low-water -> now, so healing shows up even when it arrives as a
## trickle. Comparing frame to frame instead was tried and is WRONG: the heal
## ceiling meters regen down to ~0.02% of the bar per frame, far under any
## sensible threshold, so the band never appeared and slow regen stayed exactly
## as silent as before the rework.
var _boss_low: float = -1.0
var _boss_heal_t: float = 0.0     # pulse timer, re-armed each time the band grows
const BOSS_HEAL_FLASH := 0.55
## Band must be at least this wide to be worth drawing (0.4% of the bar).
const BOSS_HEAL_MIN := 0.004
var spell_cards: Array = []      # {id, btn, cover, cd_label}
var build_cards: Array = []      # {id, btn, cost}
var tower_panel: Panel
var tower_panel_name: Label
var sell_btn: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_resources()
	_build_boss_bar()
	# drawer first so the spell grid is drawn (and hit-tested) above it
	_build_buildbar()
	_build_spellbar()
	_build_tower_panel()
	_build_pause_menu()

func _build_top() -> void:
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 20, 8, 8))
	bar.position = Vector2(-8, -14)
	bar.size = Vector2(1096, 138)
	add_child(bar)

	var pause := UI.icon_button("ic_pause", Vector2(100, 100))
	pause.position = Vector2(16, 12)
	pause.pressed.connect(_toggle_pause)
	add_child(pause)

	mute_btn = UI.icon_button("ic_sound", Vector2(100, 100))
	mute_btn.position = Vector2(128, 12)
	mute_btn.pressed.connect(_toggle_mute)
	add_child(mute_btn)
	_refresh_mute()

	# decorative title banner
	var banner := Panel.new()
	banner.add_theme_stylebox_override("panel", UI.frame_box("banner_gold9", 18, 12, 6))
	banner.position = Vector2(348, 8)
	banner.size = Vector2(384, 104)
	add_child(banner)

	level_label = UI.title(tr("COMMON_LEVEL_N").format({"n": battle.level}), 40)
	level_label.position = Vector2(348, 12)
	level_label.size = Vector2(384, 48)
	add_child(level_label)

	boss_timer_label = UI.label("", 27, Color(1, 0.86, 0.5))
	boss_timer_label.position = Vector2(348, 64)
	boss_timer_label.size = Vector2(384, 40)
	boss_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	boss_timer_label.add_theme_constant_override("outline_size", 5)
	add_child(boss_timer_label)

	# caption sized for the widest tier ("x0.5"), not for "x1"
	speed_btn = UI.button(Battle.speed_label(battle.game_speed), Vector2(150, 100), UI.ACCENT, 36)
	speed_btn.position = Vector2(916, 12)
	speed_btn.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var sp_ic := UI.tex_rect(Assets.ui("ic_ff"), Vector2(42, 42))
	sp_ic.position = Vector2(14, 29)
	speed_btn.add_child(sp_ic)
	speed_btn.pressed.connect(_cycle_speed)
	add_child(speed_btn)

func _build_resources() -> void:
	# gold badge (left)
	var gbadge := Panel.new()
	gbadge.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 16, 6, 4))
	gbadge.position = Vector2(18, 128)
	gbadge.size = Vector2(268, 60)
	add_child(gbadge)
	var coin := UI.tex_rect(Assets.coin(), Vector2(48, 48))
	coin.position = Vector2(28, 134)
	add_child(coin)
	gold_label = UI.label(str(battle.gold), 40, UI.GOLD)
	gold_label.position = Vector2(84, 132)
	gold_label.size = Vector2(180, 48)   # five-digit gold used to overflow
	gold_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	gold_label.add_theme_constant_override("outline_size", 5)
	add_child(gold_label)

	# crystal badge (right)
	var cbadge := Panel.new()
	cbadge.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 16, 6, 4))
	cbadge.position = Vector2(852, 128)
	cbadge.size = Vector2(210, 60)
	add_child(cbadge)
	crystal_label = UI.label(str(Meta.crystals), 40, UI.CRYSTAL)
	crystal_label.position = Vector2(870, 132)
	crystal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crystal_label.size = Vector2(120, 48)
	crystal_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	crystal_label.add_theme_constant_override("outline_size", 5)
	add_child(crystal_label)
	var crys := UI.tex_rect(Assets.crystal(), Vector2(48, 48))
	crys.position = Vector2(1006, 134)
	add_child(crys)

func _build_boss_bar() -> void:
	boss_box = Control.new()
	boss_box.position = Vector2(60, 200)
	boss_box.size = Vector2(960, 74)
	boss_box.visible = false
	add_child(boss_box)
	# framed skull plate + name
	var plate := Panel.new()
	plate.add_theme_stylebox_override("panel", UI.frame_box("banner_gold9", 24, 10, 4))
	plate.position = Vector2(0, -6)
	plate.size = Vector2(300, 44)
	boss_box.add_child(plate)
	var skull := UI.tex_rect(Assets.ui("ic_skull"), Vector2(34, 34))
	skull.position = Vector2(14, 0)
	boss_box.add_child(skull)
	boss_name = UI.label("BOSS", 26, Color(0.3, 0.1, 0.05))
	boss_name.position = Vector2(56, -2)
	boss_name.size = Vector2(236, 40)
	boss_box.add_child(boss_name)
	# warm framed HP track + red gradient fill
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 20, 8, 6))
	track.position = Vector2(0, 40)
	track.size = Vector2(960, 34)
	boss_box.add_child(track)
	boss_bar = ProgressBar.new()
	boss_bar.position = Vector2(10, 7)
	boss_bar.size = Vector2(940, 20)
	boss_bar.show_percentage = false
	boss_bar.min_value = 0
	boss_bar.max_value = 1
	boss_bar.value = 1
	var fg := StyleBoxTexture.new()
	fg.texture = Assets.ui("bar_red9")
	fg.texture_margin_left = 8; fg.texture_margin_right = 8
	fg.texture_margin_top = 6; fg.texture_margin_bottom = 6
	var bgb := UI._style(Color(0.14, 0.08, 0.05), 6)
	boss_bar.add_theme_stylebox_override("fill", fg)
	boss_bar.add_theme_stylebox_override("background", bgb)
	track.add_child(boss_bar)
	# gloss strip + segment ticks so the bar reads as a framed gauge instead of
	# a flat red rectangle drawn across the top of the map
	var gloss := ColorRect.new()
	gloss.color = Color(1, 1, 1, 0.14)
	gloss.position = Vector2(10, 8)
	gloss.size = Vector2(940, 6)
	gloss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(gloss)
	for i in range(1, 4):
		var tick := ColorRect.new()
		tick.color = Color(0, 0, 0, 0.45)
		tick.position = Vector2(10 + 235 * i, 7)
		tick.size = Vector2(3, 20)
		tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(tick)
	# 視覺誠實: the stretch of bar a boss just healed BACK, painted bright green
	# over the red and faded out. Before this, a boss regenerating simply made
	# the red creep right with no announcement, which reads as "my damage is not
	# landing" rather than "it healed".
	boss_heal_rect = ColorRect.new()
	boss_heal_rect.color = Color(0.5, 1.0, 0.45)
	boss_heal_rect.position = Vector2(10, 7)
	boss_heal_rect.size = Vector2(0, 20)
	boss_heal_rect.visible = false
	boss_heal_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(boss_heal_rect)

# ---------------------------------------------------------------------------
# Bottom bar.
#
#   1586..1688  常駐快捷列 — 6 個塔槽 + 「更多」,一行過
#   1690..1912  魔法 grid — 每個學過嘅魔法,永遠喺畫面上
#   抽屜由「更多」掣拉上嚟,停喺 1584,所以佢永遠唔會冚住快捷列或者魔法列。
#
# 呢一行取代咗舊嘅「建造」把手。把手嘅問題唔係佢佔位,係佢令起塔變成兩個動作:
# 開抽屜,再拖。一個常駐嘅槽令個手勢變返一個 —— 按住、拖出去、放手。
# 抽屜留返做全塔倉庫(20 座塔擺唔落 6 格),入面照樣一手勢拖得。
# ---------------------------------------------------------------------------
const SPELL_AREA := Rect2(40, 1690, 1000, 222)
const DRAWER_BOTTOM := 1584.0
const DRAWER_COLS := 4
const DRAWER_CARD_H := 148.0
const DRAWER_PAD := 24.0
const DRAWER_SEP := 12.0
const DRAWER_TITLE_H := 56.0
const DRAWER_SLIDE := 0.16

func _build_spellbar() -> void:
	var ids: Array = Meta.unlocked_spells
	var n := ids.size()
	if n == 0:
		return
	# <=8 fits one comfortable row; past that it splits into two, top row first,
	# so 15 spells read as 8 + 7 instead of scrolling.
	var cell: float
	var rows: Array          # each entry is an Array of spell ids
	if n <= 8:
		# 120 is the comfortable size, but 8 x 120 + gaps is 1044 — wider than the
		# safe area — and the row ended up 18px from each screen edge. Shrink to
		# fit rather than bleed.
		cell = minf(120.0, (SPELL_AREA.size.x - (n - 1) * 12.0) / float(n))
		rows = [ids.duplicate()]
	else:
		var top := int(ceil(n / 2.0))
		cell = clampf((SPELL_AREA.size.x - (top - 1) * 8.0) / float(top), 88.0, 104.0)
		rows = [ids.slice(0, top), ids.slice(top, n)]
	var sep := 12.0 if n <= 8 else 8.0
	var grid_h := rows.size() * cell + (rows.size() - 1) * sep
	var y := SPELL_AREA.position.y + (SPELL_AREA.size.y - grid_h) * 0.5
	for r in rows.size():
		var row: Array = rows[r]
		var row_w := row.size() * cell + (row.size() - 1) * sep
		var x := SPELL_AREA.position.x + (SPELL_AREA.size.x - row_w) * 0.5
		for i in row.size():
			var card := _make_spell_card(int(row[i]), cell)
			card.position = Vector2(x + i * (cell + sep), y + r * (cell + sep))
			add_child(card)

func _make_spell_card(id: int, cell: float) -> Control:
	var def := GameData.spell_by_id(id)
	var btn := Button.new()
	btn.size = Vector2(cell, cell)
	btn.custom_minimum_size = Vector2(cell, cell)
	btn.add_theme_stylebox_override("normal", UI.frame_box("slot9", 14, 6, 6))
	btn.add_theme_stylebox_override("hover", UI.frame_box("slot9", 14, 6, 6, Color(1.2, 1.2, 1.2)))
	btn.add_theme_stylebox_override("pressed", UI.frame_box("slot9", 14, 6, 6, Color(0.8, 0.8, 0.8)))
	var tier: int = Meta.spell_tier(id)
	btn.tooltip_text = "%s\n%s" % [tr(GameData.tier_name(def, false, tier)), tr(def.desc)]
	# same drag-from-card path as tower cards; card_press handles instant vs
	# targeted spells and ignores presses while on cooldown.
	btn.gui_input.connect(func(e: InputEvent): _card_gui(e, id, true))
	var pad := cell * 0.06
	var icon := UI.tex_rect(Assets.spell(id), Vector2(cell - pad * 2.0, cell - pad * 2.0))
	icon.position = Vector2(pad, pad)
	btn.add_child(icon)
	var cover := _RadialCover.new()
	cover.position = Vector2(0, 0)
	cover.size = Vector2(cell, cell)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cover)
	# 魔法卡冇位擺一行字,所以階級全靠 icon 本身(底色 / 邊框已經跟階演進)
	# 加呢排星。放喺左上角:右下角係冷卻秒數嘅位。
	var pips := UI.tier_pips(tier, 12.0)
	pips.position = Vector2(5, 4)
	btn.add_child(pips)
	var cd_label := UI.label("", int(cell * 0.34), Color.WHITE)
	cd_label.position = Vector2(0, cell * 0.3)
	cd_label.size = Vector2(cell, cell * 0.4)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cd_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cd_label)
	# cd_max is cached at build time: upgrade levels cannot change mid-battle, and
	# calling Meta.spell_stats() per spell PER FRAME meant a deep dictionary
	# duplicate ~900 times a second just to draw a cooldown wedge.
	spell_cards.append({"id": id, "btn": btn, "cover": cover, "cd_label": cd_label,
		"on_cd": false, "cd_max": maxf(0.1, float(Meta.spell_stats(id).get("cd", 10.0)))})
	return btn

# --- tower drawer -----------------------------------------------------------
var drawer: Panel
var drawer_scrim: Control
var _drawer_open: bool = false
var _drawer_tw: Tween
var _drawer_shown_y: float = 0.0

func _build_buildbar() -> void:
	var ids: Array = Meta.unlocked_towers
	var rows: int = maxi(1, int(ceil(ids.size() / float(DRAWER_COLS))))
	var card_w := (1080.0 - DRAWER_PAD * 2.0 - (DRAWER_COLS - 1) * DRAWER_SEP) / float(DRAWER_COLS)
	var grid_h := rows * DRAWER_CARD_H + (rows - 1) * DRAWER_SEP
	var panel_h := DRAWER_PAD + DRAWER_TITLE_H + DRAWER_SEP + grid_h + DRAWER_PAD
	_drawer_shown_y = DRAWER_BOTTOM - panel_h

	# Tap-outside-to-close catcher. It stops short of the handle and the spell
	# grid, so both stay live while the drawer is open — closing the drawer is
	# never a prerequisite for casting.
	drawer_scrim = Control.new()
	drawer_scrim.position = Vector2.ZERO
	drawer_scrim.size = Vector2(1080, DRAWER_BOTTOM)
	drawer_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer_scrim.visible = false
	drawer_scrim.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_set_drawer(false))
	add_child(drawer_scrim)

	drawer = Panel.new()
	drawer.add_theme_stylebox_override("panel", UI.frame_box("panel9", 22, 16, 10))
	drawer.position = Vector2(0, 1920)     # parked off the bottom edge
	drawer.size = Vector2(1080, panel_h)
	drawer.modulate = Color(1, 1, 1, 0.94)
	drawer.visible = false
	add_child(drawer)

	var title := UI.label(tr("HUD_BUILD"), 36, UI.TEXT)
	title.position = Vector2(DRAWER_PAD + 6, DRAWER_PAD - 6)
	title.size = Vector2(500, DRAWER_TITLE_H)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(title)
	var hint := UI.label(tr("HUD_HINT_DRAWER"), 22, Color(0.7, 0.75, 0.8))
	hint.position = Vector2(520, DRAWER_PAD + 4)
	hint.size = Vector2(1080 - 520 - DRAWER_PAD, DRAWER_TITLE_H)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.add_child(hint)

	var gy := DRAWER_PAD + DRAWER_TITLE_H + DRAWER_SEP
	for i in ids.size():
		var card := _make_build_card(int(ids[i]), card_w)
		card.position = Vector2(
			DRAWER_PAD + (i % DRAWER_COLS) * (card_w + DRAWER_SEP),
			gy + (i / DRAWER_COLS) * (DRAWER_CARD_H + DRAWER_SEP))
		drawer.add_child(card)

	_build_quickbar()

# --- 常駐快捷列 -------------------------------------------------------------
var quick_cards: Array = []      # {id, btn, cost, slot}
var more_btn: Button
## 每幀要檢查買唔買得起嘅卡。抽屜卡同快捷卡合埋一個 Array 起一次,
## 好過喺 refresh() 入面逐幀 `build_cards + quick_cards` 開一個新 Array。
var _afford_cards: Array = []

func _build_quickbar() -> void:
	var cw: float = UI.quick_cell_w()
	var ids: Array = Meta.quick_slot_ids()
	for i in Meta.QUICK_SLOTS:
		# 未解鎖嘅 id 一律當空格。Meta 載入時會洗一次,但呢度唔可以假設佢啱 ——
		# 測試同 art_export 都會直接寫 Meta.unlocked_towers 而唔經 unlock_tower(),
		# 而喺戰鬥入面畫一張買唔到嘅塔卡係比空格差好多嘅結果。
		var id: int = int(ids[i])
		if id > 0 and not Meta.is_tower_unlocked(id):
			id = 0
		var cell := _make_quick_cell(id, i, cw)
		cell.position = Vector2(UI.QUICK_RECT.position.x + i * (cw + UI.QUICK_GAP),
			UI.QUICK_RECT.position.y)
		add_child(cell)
	more_btn = UI.button(tr("HUD_MORE"), Vector2(cw, UI.QUICK_RECT.size.y), UI.PANEL_HI, 26)
	more_btn.position = Vector2(
		UI.QUICK_RECT.position.x + Meta.QUICK_SLOTS * (cw + UI.QUICK_GAP),
		UI.QUICK_RECT.position.y)
	more_btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
	more_btn.pressed.connect(func(): _set_drawer(not _drawer_open))
	add_child(more_btn)
	_afford_cards = build_cards + quick_cards

## 一個快捷槽。空格畫成暗色「+」,撳落去開抽屜 —— 六格闊度永遠一樣,所以
## 解鎖一座新塔唔會令成條底欄跳位。
func _make_quick_cell(id: int, slot: int, cw: float) -> Control:
	var btn := Button.new()
	btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
	btn.custom_minimum_size = btn.size
	btn.add_theme_stylebox_override("normal", UI.frame_box("slot9", 14, 6, 6))
	btn.add_theme_stylebox_override("hover", UI.frame_box("slot9", 14, 6, 6, Color(1.18, 1.18, 1.18)))
	btn.add_theme_stylebox_override("pressed", UI.frame_box("slot9", 14, 6, 6, Color(0.7, 1.1, 0.8)))
	btn.add_theme_stylebox_override("disabled", UI.frame_box("slot9", 14, 6, 6, Color(0.42, 0.42, 0.46)))
	if id <= 0:
		var plus := UI.label("+", 44, Color(0.55, 0.50, 0.44))
		plus.size = btn.size
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(plus)
		btn.pressed.connect(func(): _set_drawer(true))
		return btn
	var def := GameData.tower_by_id(id)
	var tier: int = Meta.tower_tier(id)
	btn.tooltip_text = "%s\n%s" % [tr(GameData.tier_name(def, true, tier)), tr(def.desc)]
	# 同抽屜卡行同一條手勢鏈。快捷列唔係抽屜,所以 _over_drawer 唔會否決,
	# _set_drawer(false) 係 no-op —— 個手勢由頭到尾就係一下。
	btn.gui_input.connect(func(e: InputEvent): _card_gui(e, id, false))
	var icon := UI.tex_rect(Assets.tower(id), Vector2(60, 60))
	icon.position = Vector2((cw - 60.0) * 0.5, 4)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	var pips := UI.tier_pips(tier, 13.0)
	pips.position = Vector2(cw - pips.size.x - 5.0, 4)
	btn.add_child(pips)
	var coin := UI.tex_rect(Assets.coin(), Vector2(22, 22))
	coin.position = Vector2(cw * 0.5 - 36.0, 70)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(coin)
	var cost := UI.label(str(def.place_cost), 24, UI.GOLD)
	cost.position = Vector2(cw * 0.5 - 10.0, 68)
	cost.size = Vector2(64, 30)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cost)
	quick_cards.append({"id": id, "btn": btn, "cost": int(def.place_cost), "slot": slot})
	return btn

func _set_drawer(open: bool) -> void:
	if open == _drawer_open:
		return
	_drawer_open = open
	Audio.play("ui_panel_open" if open else "ui_panel_close")
	drawer_scrim.visible = open
	if open:
		drawer.visible = true
		# The sell panel lives at y1470 and would end up buried under the drawer,
		# so the two never coexist. Hide it directly rather than going through
		# show_tower_panel(), which calls back into _set_drawer().
		if tower_panel != null:
			tower_panel.visible = false
		battle.cancel_modes()
	if _drawer_tw != null and _drawer_tw.is_valid():
		_drawer_tw.kill()
	_drawer_tw = create_tween()
	# The drawer is chrome, not gameplay: at 3x an Engine.time_scale-driven tween
	# would snap open in a third of the time and at 0.5x it would crawl.
	_drawer_tw.set_ignore_time_scale(true)
	_drawer_tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_drawer_tw.tween_property(drawer, "position:y",
		_drawer_shown_y if open else 1920.0, DRAWER_SLIDE)
	if not open:
		_drawer_tw.tween_callback(func(): drawer.visible = false)

## True when `screen` lands on the open drawer. Used to veto a drop: the panel
## covers world coordinates that are legal build spots, so without this check
## dragging a tower back onto the panel would build it underneath the panel.
func _over_drawer(screen: Vector2) -> bool:
	return _drawer_open and Rect2(drawer.position, drawer.size).has_point(screen)

func _make_build_card(id: int, card_w: float) -> Control:
	var def := GameData.tower_by_id(id)
	var tier: int = Meta.tower_tier(id)
	var btn := Button.new()
	btn.size = Vector2(card_w, DRAWER_CARD_H)
	btn.custom_minimum_size = btn.size
	btn.add_theme_stylebox_override("normal", UI.frame_box("card9", 16, 6, 6))
	btn.add_theme_stylebox_override("hover", UI.frame_box("card9", 16, 6, 6, Color(1.18, 1.18, 1.18)))
	btn.add_theme_stylebox_override("pressed", UI.frame_box("card9", 16, 6, 6, Color(0.7, 1.1, 0.8)))
	btn.add_theme_stylebox_override("disabled", UI.frame_box("card9", 16, 6, 6, Color(0.42, 0.42, 0.46)))
	btn.tooltip_text = "%s\n%s" % [tr(def.name), tr(def.desc)]
	# Drag-from-card is the primary path: the press is captured by this Button so
	# the whole gesture (drag onto the map + release) arrives here at gui_input,
	# never at Battle._unhandled_input. We forward it to card_press/drag/release.
	# A plain tap (no movement) falls through to arming build mode for the
	# two-stage tap fallback. emulate_mouse_from_touch (on) means a finger drag
	# reaches us as mouse events with a correct global_position.
	btn.gui_input.connect(func(e: InputEvent): _card_gui(e, id, false))
	var icon := UI.tex_rect(Assets.tower(id), Vector2(84, 84))
	icon.position = Vector2(10, (DRAWER_CARD_H - 84) * 0.5)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	# Name and cost stack to the RIGHT of the icon. An English tower name is
	# roughly twice the width of the 繁中 one, so the Label sits FULL_RECT inside
	# a fixed clip box — a free Label with a manual size wraps unreliably here and
	# the second line silently vanished.
	var text_x := 100.0
	var text_w := card_w - text_x - 12.0
	var nbox := Control.new()
	nbox.position = Vector2(text_x, 16)
	nbox.size = Vector2(text_w, 66)
	nbox.clip_contents = true
	nbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(nbox)
	var pips := UI.tier_pips(tier, 14.0)
	pips.position = Vector2(card_w - pips.size.x - 8.0, 6)
	btn.add_child(pips)
	var nm := UI.label(tr(GameData.tier_name(def, true, tier)), 24, UI.TEXT)
	nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nbox.add_child(nm)
	var costrow := HBoxContainer.new()
	costrow.position = Vector2(text_x, 92)
	costrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	costrow.add_child(UI.tex_rect(Assets.coin(), Vector2(34, 34)))
	var cost := UI.label(str(def.place_cost), 30, UI.GOLD)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	costrow.add_child(cost)
	btn.add_child(costrow)
	build_cards.append({"id": id, "btn": btn, "cost": def.place_cost})
	return btn

func _build_tower_panel() -> void:
	tower_panel = Panel.new()
	tower_panel.add_theme_stylebox_override("panel", UI.frame_box("panel9", 22, 16, 10))
	tower_panel.position = Vector2(240, 1470)
	tower_panel.size = Vector2(600, 110)
	tower_panel.visible = false
	add_child(tower_panel)
	tower_panel_name = UI.label("", 30, UI.TEXT)
	tower_panel_name.position = Vector2(20, 14)
	tower_panel_name.size = Vector2(360, 40)
	tower_panel.add_child(tower_panel_name)
	var info := UI.label(tr("HUD_HINT_BUILD"), 22, Color(0.7, 0.75, 0.8))
	info.position = Vector2(20, 58)
	tower_panel.add_child(info)
	sell_btn = UI.button(tr("HUD_SELL"), Vector2(200, 90), UI.DANGER, 30)
	sell_btn.position = Vector2(388, 10)
	sell_btn.pressed.connect(func():
		if battle.selected_tower:
			battle.sell_tower(battle.selected_tower)
			tower_panel.visible = false)
	tower_panel.add_child(sell_btn)

# Forward a card's captured pointer gesture to the battle. We use mouse events
# (emulate_mouse_from_touch turns finger touches into these) so global_position
# is always the real viewport point; ScreenTouch/Drag would arrive control-local.
const DRAWER_A_IDLE := 0.94
const DRAWER_A_DRAG := 0.25    # dragging a tower out ghosts the panel away

var _card_press_pos: Vector2 = Vector2.ZERO

func _card_gui(e: InputEvent, id: int, is_spell: bool) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_card_press_pos = e.global_position
			battle.card_press(id, is_spell, e.global_position)
		elif is_spell:
			battle.card_release(e.global_position)
		else:
			_drawer_alpha(DRAWER_A_IDLE)
			# The "put it back" rule only applies to a real DRAG that ends over
			# the panel. A plain tap also releases inside the panel — it is a tap
			# ON A CARD — and treating that as a cancel silently killed the
			# two-stage 撳卡 -> 撳地圖 path.
			var moved: bool = e.global_position.distance_to(_card_press_pos) > Battle.TAP_MOVE_THRESH
			if moved and _over_drawer(e.global_position):
				# dropped straight back onto the panel: that reads as "never
				# mind", so cancel the placement and keep browsing
				battle.card_cancel()
			else:
				# a drag places (or fails on red ground); a plain tap leaves build
				# mode armed for the two-stage tap fallback. Either way the panel
				# has done its job and gets out of the way of the map.
				battle.card_release(e.global_position)
				_set_drawer(false)
	elif e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT):
		battle.card_drag(e.global_position)
		if not is_spell:
			_drawer_alpha(DRAWER_A_IDLE if _over_drawer(e.global_position) else DRAWER_A_DRAG)

func _drawer_alpha(a: float) -> void:
	if drawer != null and drawer.modulate.a != a:
		drawer.modulate.a = a

# ---------------------------------------------------------------------------
var _last_gold := -1
var _last_crys := -1

# Currency pop. Gold changes on EVERY kill, so a Tween per change was hundreds
# of allocations a second at 3x. Two floats ticked in refresh() instead.
var _pop_t := {}

func _pop(l: Label) -> void:
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2(1.35, 1.35)
	_pop_t[l] = 0.18

func _tick_pops(delta: float) -> void:
	for l in _pop_t.keys():
		var t: float = _pop_t[l] - delta
		if t <= 0.0:
			l.scale = Vector2.ONE
			_pop_t.erase(l)
		else:
			_pop_t[l] = t
			var sc: float = lerpf(1.0, 1.35, t / 0.18)
			l.scale = Vector2(sc, sc)

## 上一次寫入 boss 倒數 label 嘅秒數。-2 = 未寫過,-1 = 已經寫咗「boss 到咗」。
var _last_remain: int = -2

func refresh(delta: float) -> void:
	_tick_pops(delta)
	if battle.gold != _last_gold:
		if _last_gold >= 0: _pop(gold_label)
		_last_gold = battle.gold
		gold_label.text = str(battle.gold)
	if Meta.crystals != _last_crys:
		if _last_crys >= 0: _pop(crystal_label)
		_last_crys = Meta.crystals
		crystal_label.text = str(Meta.crystals)
	# boss timer —— 個數一秒先變一次,所以一秒砌一次字就夠。
	#
	# Label.set_text 見到同一段字會自己收手,所以之前浪費咗嘅唔係重新排版,係
	# 每一幀都行一次 tr() 查表 + 開一個 Dictionary 俾 format() + 砌一個新
	# String。一秒六十次(120Hz 機一百二十次),而當中五十九次嘅答案同上一幀
	# 一模一樣。`_last_remain` 記住上次個秒數,-2 = 「未寫過」,-1 = 「boss 出咗」。
	if not battle.boss_spawned:
		var remain: int = int(ceil(maxf(0.0, battle.boss_time - battle.elapsed)))
		if remain != _last_remain:
			_last_remain = remain
			boss_timer_label.text = tr("HUD_BOSS_COUNTDOWN").format({"n": remain})
	elif _last_remain != -1:
		_last_remain = -1
		boss_timer_label.text = tr("HUD_BOSS_HERE")
	# boss bar
	if battle.boss_ref != null and is_instance_valid(battle.boss_ref) and battle.boss_ref.alive:
		boss_box.visible = true
		var frac: float = clampf(battle.boss_ref.hp / battle.boss_ref.max_hp, 0, 1)
		if _boss_low < 0.0 or frac < _boss_low:
			_boss_low = frac                       # damage: the band resets here
		var band: float = frac - _boss_low
		if band >= BOSS_HEAL_MIN:
			boss_heal_rect.visible = true
			boss_heal_rect.position.x = 10.0 + 940.0 * _boss_low
			boss_heal_rect.size.x = 940.0 * band
			if frac > _boss_frac:
				_boss_heal_t = BOSS_HEAL_FLASH     # still climbing: keep pulsing
		elif boss_heal_rect.visible:
			boss_heal_rect.visible = false
		_boss_frac = frac
		boss_bar.value = frac
	else:
		boss_box.visible = false
		boss_heal_rect.visible = false
		_boss_frac = -1.0
		_boss_low = -1.0
		_boss_heal_t = 0.0
	# the band is solid while it exists; the pulse on top makes a fresh gain
	# unmissable even when the slice is thin
	if _boss_heal_t > 0.0:
		_boss_heal_t -= delta
		var k: float = clampf(_boss_heal_t / BOSS_HEAL_FLASH, 0.0, 1.0)
		boss_heal_rect.color.a = 0.55 + 0.45 * k
		boss_bar.modulate = Color.WHITE.lerp(Color(0.55, 1.35, 0.55), k * 0.8)
	elif boss_bar.modulate != Color.WHITE:
		boss_heal_rect.color.a = 0.55
		boss_bar.modulate = Color.WHITE
	# spell cooldowns (+ ready flash when a CD finishes)
	for c in spell_cards:
		var cd: float = battle.spell_cd.get(c.id, 0.0)
		if cd > 0.0:
			var frac: float = clampf(cd / float(c.cd_max), 0.0, 1.0)
			if absf(frac - c.cover.frac) > 0.004:
				c.cover.frac = frac
				c.cover.queue_redraw()
			var secs := str(int(ceil(cd)))
			if c.cd_label.text != secs:
				c.cd_label.text = secs
			c.on_cd = true
		else:
			if c.cover.frac != 0.0:
				c.cover.frac = 0.0
				c.cover.queue_redraw()
			if c.cd_label.text != "":
				c.cd_label.text = ""
			if c.on_cd:
				c.on_cd = false
				_flash_card(c.btn)
		# highlight the spell currently being aimed
		var sm := Color(1.35, 1.35, 0.9) if battle.aiming_spell == c.id else Color.WHITE
		if c.btn.modulate != sm:
			c.btn.modulate = sm
	# build affordability + active-card highlight
	for c in _afford_cards:
		var dis: bool = battle.gold < c.cost
		if c.btn.disabled != dis:
			c.btn.disabled = dis
		var bm := Color(0.8, 1.35, 0.9) if battle.build_id == c.id else Color.WHITE
		if c.btn.modulate != bm:
			c.btn.modulate = bm

func show_boss(m) -> void:
	boss_box.visible = true
	boss_name.text = tr("HUD_BOSS_NAME").format({"fam": tr(GameData.FAMILIES[m.fam].name)})

func show_tower_panel(t) -> void:
	if t == null:
		tower_panel.visible = false
		return
	# selecting a placed tower means the player is done browsing
	_set_drawer(false)
	tower_panel.visible = true
	tower_panel_name.text = tr(GameData.tier_name(t.def, true, t.tier))
	sell_btn.text = tr("HUD_SELL_VALUE").format({"n": t.sell_value()})

func _flash_card(btn: Button) -> void:
	var fl := ColorRect.new()
	fl.color = Color(1, 1, 1, 0.75)
	fl.size = btn.size     # cards are no longer a fixed 100x100
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(fl)
	var tw := create_tween()
	tw.tween_property(fl, "color:a", 0.0, 0.4)
	tw.tween_callback(fl.queue_free)

# --- pause menu -------------------------------------------------------------
var pause_menu: Control

func _build_pause_menu() -> void:
	pause_menu = Control.new()
	pause_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.visible = false
	pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_menu)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_menu.add_child(dim)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 30)
	box.position = Vector2(240, 620)
	box.size = Vector2(600, 0)
	pause_menu.add_child(box)
	var t := UI.title(tr("HUD_PAUSED"), 60)
	t.size = Vector2(600, 90)
	box.add_child(t)
	var resume := UI.button(tr("HUD_RESUME"), Vector2(600, 120), UI.ACCENT, 40)
	resume.pressed.connect(_toggle_pause)
	box.add_child(resume)
	var bes := UI.button(tr("NAV_BESTIARY"), Vector2(600, 110))
	bes.pressed.connect(_open_bestiary_overlay)
	box.add_child(bes)
	var quit := UI.button(tr("NAV_MAIN_MENU"), Vector2(600, 110), UI.DANGER, 36)
	quit.pressed.connect(func():
		get_tree().paused = false
		Flow.goto(Flow.MAIN_MENU))
	box.add_child(quit)

func _open_bestiary_overlay() -> void:
	var bs = load("res://scripts/ui/Bestiary.gd").new()
	bs.overlay = true
	bs.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.visible = false
	# when the bestiary closes, return to the (still-paused) pause menu.
	#
	# `is_instance_valid(self)` is NOT enough. Leaving the battle tears the whole
	# scene down, which fires tree_exited on the overlay while this HUD is still a
	# LIVE object that is already OUT of the tree — and get_tree() on a node with no
	# tree returns null, so the next line indexed `paused` on null. Every exit from a
	# battle that had the 圖鑑 overlay open logged two engine errors for it.
	# is_inside_tree() is the question actually being asked: "am I still a HUD that
	# has a pause menu to show".
	bs.tree_exited.connect(func():
		if is_instance_valid(self) and is_inside_tree() and get_tree().paused:
			pause_menu.visible = true)
	add_child(bs)

func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_menu.visible = p

func _toggle_mute() -> void:
	Meta.settings["muted"] = not Meta.settings.get("muted", false)
	Meta.save_game()
	Meta.apply_audio_settings()
	_refresh_mute()

func _refresh_mute() -> void:
	var muted: bool = Meta.settings.get("muted", false)
	if mute_btn.has_meta("icon"):
		var ic: TextureRect = mute_btn.get_meta("icon")
		ic.texture = Assets.ui("ic_mute" if muted else "ic_sound")

func _cycle_speed() -> void:
	var i: int = Battle.SPEEDS.find(battle.game_speed)
	i = (i + 1) % Battle.SPEEDS.size()
	battle.set_speed_index(i)
	speed_btn.text = Battle.speed_label(battle.game_speed)


# Sector cooldown mask: a dark pie wedge sweeping clockwise from 12 o'clock that
# shrinks as the spell recharges (after skill_icon.jpg radial-CD language).
class _RadialCover extends Control:
	var frac: float = 0.0     # 1 = just cast (full dark), 0 = ready

	func _draw() -> void:
		if frac <= 0.001:
			return
		var c := size * 0.5
		var r := size.x * 0.72
		var steps := 40
		var start := -PI / 2.0
		var pts := PackedVector2Array([c])
		var covered := frac * TAU
		for i in steps + 1:
			var a := start + covered * (float(i) / steps)
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color(0, 0, 0, 0.62))
