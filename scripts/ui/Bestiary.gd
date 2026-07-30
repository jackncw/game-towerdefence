extends Control
## Player-facing monster bestiary (怪物圖鑑). One page per family; each shows lv1-5
## + boss. Only creatures actually seen in battle (Meta.seen) are revealed — the
## rest show a dark silhouette + "???". Left/right paging + swipe; Esc / Android
## back returns to the previous screen.

var fam_idx: int = 0
var sel_slot: int = 0          # 0..4 = lv1..5, 5 = boss
var page_root: Control
var _swipe_accum: float = 0.0
# overlay mode: shown on top of a paused battle (from the pause menu) and simply
# frees itself on close; scene mode returns to the main menu.
var overlay: bool = false
var return_path: String = "res://scenes/MainMenu.tscn"

const SLOT_LABELS := ["Lv1", "Lv2", "Lv3", "Lv4", "Lv5", "BOSS"]

func _ready() -> void:
	UI.fullscreen_bg(self, Color(0.11, 0.085, 0.065))
	var title := UI.title(tr("BESTIARY_TITLE"), 52)
	title.position = Vector2(0, 30); title.size = Vector2(1080, 70)
	add_child(title)
	var back := UI.button(tr("NAV_BACK"), Vector2(200, 80), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(_go_back)
	add_child(back)

	# family pager controls
	var prev := UI.button("‹", Vector2(96, 96), UI.PANEL_HI, 52)
	prev.position = Vector2(24, 150)
	prev.pressed.connect(func(): _turn(-1))
	add_child(prev)
	var nxt := UI.button("›", Vector2(96, 96), UI.PANEL_HI, 52)
	nxt.position = Vector2(960, 150)
	nxt.pressed.connect(func(): _turn(1))
	add_child(nxt)

	page_root = Control.new()
	page_root.position = Vector2(0, 0)
	page_root.size = Vector2(1080, 1920)
	page_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_root)

	# start on first family that has any sighting, else family 0
	for i in GameData.FAMILY_ORDER.size():
		if Meta.family_any_seen(GameData.FAMILY_ORDER[i]):
			fam_idx = i
			break
	_rebuild()

func _turn(dir: int) -> void:
	fam_idx = (fam_idx + dir + GameData.FAMILY_ORDER.size()) % GameData.FAMILY_ORDER.size()
	sel_slot = _first_unlocked_slot()
	_rebuild()

func _first_unlocked_slot() -> int:
	var fam: String = GameData.FAMILY_ORDER[fam_idx]
	for i in 5:
		if Meta.has_seen(fam, i + 1, false):
			return i
	if Meta.has_seen(fam, 0, true):
		return 5
	return 0

# ---------------------------------------------------------------------------
func _rebuild() -> void:
	for c in page_root.get_children():
		c.queue_free()
	var fam: String = GameData.FAMILY_ORDER[fam_idx]
	var famdef: Dictionary = GameData.FAMILIES[fam]
	var any_seen: bool = Meta.family_any_seen(fam)

	# family header
	var nm := UI.title("%s   (%d / %d)" % [
		tr(famdef.name) if any_seen else tr("BESTIARY_UNKNOWN_FAM"),
		fam_idx + 1, GameData.FAMILY_ORDER.size()], 40)
	nm.position = Vector2(140, 160); nm.size = Vector2(800, 56)
	page_root.add_child(nm)

	# portrait strip: 6 slots (lv1-5 + boss)
	var strip := Control.new()
	strip.position = Vector2(30, 250)
	strip.size = Vector2(1020, 300)
	page_root.add_child(strip)
	var cols := 3
	var cw := 340.0
	var ch := 150.0
	for slot in 6:
		var boss: bool = slot == 5
		var lvl: int = slot + 1
		var seen: bool = Meta.has_seen(fam, lvl, boss) if not boss else Meta.has_seen(fam, 0, true)
		var col := slot % cols
		var row := slot / cols
		var cell := _portrait_cell(fam, slot, seen)
		cell.position = Vector2(col * cw + 20, row * ch)
		strip.add_child(cell)

	# detail panel for the selected slot
	page_root.add_child(_detail_panel(fam, sel_slot))

	# hint
	var hint := UI.label(tr("BESTIARY_HINT"), 22, Color(0.6, 0.65, 0.72))
	hint.position = Vector2(60, 1700); hint.size = Vector2(960, 40)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_root.add_child(hint)

func _portrait_cell(fam: String, slot: int, seen: bool) -> Control:
	var boss: bool = slot == 5
	var lvl: int = slot + 1
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(300, 140)
	btn.size = Vector2(300, 140)
	var hi: bool = slot == sel_slot
	var border := Color(1, 0.82, 0.32) if hi else Color(0.42, 0.30, 0.18)
	btn.add_theme_stylebox_override("normal", UI._style(Color(0.24, 0.18, 0.13), 12, 3, border))
	btn.add_theme_stylebox_override("hover", UI._style(Color(0.30, 0.23, 0.16), 12, 3, border))
	btn.add_theme_stylebox_override("pressed", UI._style(Color(0.34, 0.26, 0.18), 12, 3, border))
	btn.pressed.connect(func(): sel_slot = slot; _rebuild())

	var tex: Texture2D = Assets.monster_boss(fam) if boss else Assets.monster(fam, lvl)
	var base: Vector2 = tex.get_size()
	# integer scale only — a fractional fit made every portrait a different
	# pixel size inside the same grid
	var scale: float = maxf(1.0, floorf(110.0 / maxf(base.x, base.y)))
	var tr := UI.tex_rect(tex, base * scale)
	tr.position = Vector2(20, 15)
	if not seen:
		tr.modulate = Color(0, 0, 0, 1)   # silhouette
	btn.add_child(tr)

	var lab := UI.label(SLOT_LABELS[slot] if seen else "???", 26, Color(0.9, 0.9, 0.95) if seen else Color(0.55, 0.58, 0.65))
	lab.position = Vector2(150, 40); lab.size = Vector2(140, 60)
	btn.add_child(lab)
	return btn

func _detail_panel(fam: String, slot: int) -> Control:
	var boss: bool = slot == 5
	var lvl: int = slot + 1
	var seen: bool = Meta.has_seen(fam, 0, true) if boss else Meta.has_seen(fam, lvl, false)
	var famdef: Dictionary = GameData.FAMILIES[fam]
	var lore: Dictionary = GameData.FAMILY_LORE[fam]

	# The panel used to be 1210px tall with all of its content crammed into the
	# top third, leaving ~600px of blank parchment under every entry. Same
	# information, laid out down the whole plate, and the plate is shorter.
	var panel := UI.panel_rect()
	panel.position = Vector2(40, 580)
	# only boss entries carry the extra 首領技能 block, so a fixed height left
	# ~450px of blank plate under every ordinary creature
	panel.size = Vector2(1000, 1030 if boss else 800)

	# big portrait (integer 4x render, detail visible)
	var tex: Texture2D = Assets.monster_boss(fam) if boss else Assets.monster(fam, lvl)
	var big := UI.tex_rect(tex, tex.get_size() * (2.0 if boss else 4.0))
	big.position = Vector2(70, 70)
	if not seen:
		big.modulate = Color(0, 0, 0, 1)
	panel.add_child(big)

	var title := UI.label("%s %s" % [tr(famdef.name), SLOT_LABELS[slot]] if seen else tr("BESTIARY_UNKNOWN"),
		40, UI.ACCENT if seen else Color(0.6, 0.62, 0.7))
	title.position = Vector2(360, 66); title.size = Vector2(600, 60)
	panel.add_child(title)

	if not seen:
		var q := UI.label("%s\n%s" % [tr("BESTIARY_LOCKED_1"), tr("BESTIARY_LOCKED_2")],
			28, Color(0.6, 0.63, 0.7))
		q.position = Vector2(360, 150); q.size = Vector2(600, 130)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		panel.add_child(q)
		return panel

	# stats
	var st: Dictionary = GameData.boss_stats(fam, 1.0) if boss else GameData.creature_stats(fam, lvl, 1.0)
	var gold_line: String = tr("BESTIARY_BOSS_DROP") if boss else "%d" % int(st.gold)
	var rows := [
		[tr("STAT_HP"), "%d" % int(round(st.hp))],
		[tr("STAT_SPEED"), "%d" % int(round(st.speed))],
		[tr("STAT_ARMOR"), "%d" % int(round(st.armor))],
		[tr("STAT_MRES"), "%d" % int(round(st.mres))],
		[tr("STAT_GOLD_DROP"), gold_line],
		[tr("STAT_TYPE"), tr("TYPE_FLYING") if famdef.flying else tr("TYPE_GROUND")],
	]
	var y := 160
	for r in rows:
		# alternating row plate so the stat block reads as a table
		if int((y - 160) / 62.0) % 2 == 0:
			var bg := ColorRect.new()
			bg.color = Color(1, 0.92, 0.78, 0.05)
			bg.position = Vector2(348, y - 6)
			bg.size = Vector2(600, 56)
			panel.add_child(bg)
		var k := UI.label(r[0], 30, UI.TEXT_DIM)
		k.position = Vector2(360, y); k.size = Vector2(300, 44)
		panel.add_child(k)
		var v := UI.label(r[1], 30, UI.TEXT)
		v.position = Vector2(680, y); v.size = Vector2(280, 44)
		panel.add_child(v)
		y += 62

	# mechanic / boss skill
	var mech_title := UI.label(tr("BESTIARY_TRAIT"), 32, UI.GOLD)
	mech_title.position = Vector2(66, 600); mech_title.size = Vector2(880, 44)
	panel.add_child(mech_title)
	var mbox := Control.new()
	mbox.position = Vector2(66, 652); mbox.size = Vector2(872, 120)
	mbox.clip_contents = true
	panel.add_child(mbox)
	var mech := UI.label(tr(lore.mech), 28, UI.TEXT)
	mech.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mech.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mbox.add_child(mech)

	if boss:
		var bt := UI.label(tr("BESTIARY_BOSS_SKILL"), 32, UI.DANGER.lightened(0.25))
		bt.position = Vector2(66, 790); bt.size = Vector2(880, 44)
		panel.add_child(bt)
		var bbox := Control.new()
		bbox.position = Vector2(66, 842); bbox.size = Vector2(872, 120)
		bbox.clip_contents = true
		panel.add_child(bbox)
		var bd := UI.label(tr(lore.boss), 28, Color(0.96, 0.84, 0.82))
		bd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bd.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		bbox.add_child(bd)
	return panel

# ---------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_swipe_accum += event.relative.x
		if absf(_swipe_accum) > 120.0:
			_turn(-1 if _swipe_accum > 0.0 else 1)
			_swipe_accum = 0.0
	elif event is InputEventScreenTouch and not event.pressed:
		_swipe_accum = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_go_back()

func _go_back() -> void:
	if overlay:
		queue_free()
	else:
		Flow.goto(return_path)
