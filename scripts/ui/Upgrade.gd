extends Control
## Upgrade screen (round-4 redo) — vertical five-zone layout after upgradeUI.jpg:
##   1 showcase (element backdrop + platform + big tower render + name/desc)
##   2 performance panel (icon + relative stat bars, real upgraded values)
##   3 mechanics explanation (plain-Chinese lore + auto-picked schematic diagram)
##   4 upgrade tree (per-direction: icon + name + lv + now→next + crystal cost)
##   5 navigation (back + prev/next quick-switch), plus a tower/spell tab.
## Visual only: reads GameData/Meta, mutates nothing but upgrade purchases.

var sel_type: String = "tower"
var sel_id: int = 1

var crystal_label: Label
var scroll: ScrollContainer
var content: VBoxContainer
var nav_name: Label
var tab_tower: Button
var tab_spell: Button

var STAT_LABEL: Dictionary = {}
var STAT_MAX: Dictionary = {}
var SPELL_STAT_MAX: Dictionary = {}
var DPS_MAX: float = 1.0

const ELEM_COL := {
	"fire": Color(1.0, 0.55, 0.25), "ice": Color(0.55, 0.82, 1.0),
	"poison": Color(0.62, 0.9, 0.32), "arcane": Color(0.80, 0.58, 1.0),
	"stone": Color(1.0, 0.86, 0.46),
}

# --- mechanic lore + schematic-diagram kind (drives zone 3) -----------------
# [diagram_kind, lore TRANSLATION KEY] — the lore text lives in i18n/game.csv.
const TOWER_MECH := {
	"arrow": ["range", "TOWER_ARROW_LORE"],
	"cannon": ["splash", "TOWER_CANNON_LORE"],
	"lightning": ["chain", "TOWER_LIGHTNING_LORE"],
	"fireball": ["burn", "TOWER_FIREBALL_LORE"],
	"frost": ["slow", "TOWER_FROST_LORE"],
	"poison": ["dot", "TOWER_POISON_LORE"],
	"sniper": ["snipe", "TOWER_SNIPER_LORE"],
	"gatling": ["ramp", "TOWER_GATLING_LORE"],
	"mortar": ["mortar", "TOWER_MORTAR_LORE"],
	"beam": ["beam", "TOWER_BEAM_LORE"],
	"slowfield": ["aura", "TOWER_SLOWFIELD_LORE"],
	"alchemy": ["gold", "TOWER_ALCHEMY_LORE"],
	"barracks": ["soldiers", "TOWER_BARRACKS_LORE"],
	"boomerang": ["pierce", "TOWER_BOOMERANG_LORE"],
	"thorn": ["segment", "TOWER_THORN_LORE"],
	"missile": ["homing", "TOWER_MISSILE_LORE"],
	"curse": ["curseaura", "TOWER_CURSE_LORE"],
	"holy": ["buff", "TOWER_HOLY_LORE"],
	"magnet": ["knock", "TOWER_MAGNET_LORE"],
	"teleport": ["teleport", "TOWER_TELEPORT_LORE"],
}
const SPELL_MECH := {
	"meteor": ["splash", "SPELL_METEOR_LORE"],
	"stormbolt": ["fullscreen", "SPELL_STORMBOLT_LORE"],
	"freezenova": ["fullscreen", "SPELL_FREEZENOVA_LORE"],
	"miasma": ["splash", "SPELL_MIASMA_LORE"],
	"summon": ["segment", "SPELL_SUMMON_LORE"],
	"midas": ["fullscreen", "SPELL_MIDAS_LORE"],
	"timewarp": ["fullscreen", "SPELL_TIMEWARP_LORE"],
	"warcry": ["fullscreen", "SPELL_WARCRY_LORE"],
	"barrier": ["single", "SPELL_BARRIER_LORE"],
	"tornado": ["segment", "SPELL_TORNADO_LORE"],
	"quake": ["fullscreen", "SPELL_QUAKE_LORE"],
	"firewall": ["segment", "SPELL_FIREWALL_LORE"],
	"smite": ["single", "SPELL_SMITE_LORE"],
	"emp": ["splash", "SPELL_EMP_LORE"],
	"blackhole": ["splash", "SPELL_BLACKHOLE_LORE"],
}

func _ready() -> void:
	_build_stat_tables()
	UI.fullscreen_bg(self, UI.BG)
	_build_topbar()
	_build_scroll()
	_build_navbar()
	sel_type = "tower"
	# a corrupt/empty save must not crash the screen (load_game already falls back
	# to the starting set, this is the last line of defence)
	sel_id = Meta.unlocked_towers[0] if not Meta.unlocked_towers.is_empty() else 1
	_rebuild()

# ---------------------------------------------------------------------------
func _build_stat_tables() -> void:
	for t in GameData.TOWERS:
		for up in t.ups:
			STAT_LABEL[up.stat] = up.name
		for stat in t.stats.keys():
			var v: float = t.stats[stat]
			STAT_MAX[stat] = maxf(STAT_MAX.get(stat, 0.0), absf(v))
		var dps: float = float(t.stats.get("dmg", 0.0)) * float(t.stats.get("rate", 0.0))
		DPS_MAX = maxf(DPS_MAX, dps)
	for sp in GameData.SPELLS:
		for up in sp.ups:
			STAT_LABEL[up.stat] = up.name
		for stat in sp.stats.keys():
			var v: float = sp.stats[stat]
			SPELL_STAT_MAX[stat] = maxf(SPELL_STAT_MAX.get(stat, 0.0), absf(v))

func _build_topbar() -> void:
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 22, 10, 6))
	bar.position = Vector2(-8, -14)
	bar.size = Vector2(1096, 130)
	add_child(bar)

	var back := UI.icon_button("ic_back", Vector2(96, 96))
	back.position = Vector2(20, 14)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	# category tabs (塔 / 魔法)
	tab_tower = UI.button(tr("UPG_TAB_TOWER"), Vector2(190, 88), UI.GOLD, 34)
	tab_tower.position = Vector2(240, 18)
	tab_tower.pressed.connect(func(): _switch_type("tower"))
	add_child(tab_tower)
	tab_spell = UI.button(tr("COMMON_SPELLS"), Vector2(190, 88), UI.PANEL_HI, 34)
	tab_spell.position = Vector2(442, 18)
	tab_spell.pressed.connect(func(): _switch_type("spell"))
	add_child(tab_spell)

	# crystal count (right)
	var cbadge := Panel.new()
	cbadge.add_theme_stylebox_override("panel", UI.frame_box("panel_parch9", 18, 8, 4))
	cbadge.position = Vector2(806, 20)
	cbadge.size = Vector2(256, 84)
	add_child(cbadge)
	var crys := UI.tex_rect(Assets.crystal(), Vector2(52, 52))
	crys.position = Vector2(826, 36)
	add_child(crys)
	crystal_label = UI.label(str(Meta.crystals), 40, UI.CRYSTAL.lightened(0.15))
	crystal_label.position = Vector2(884, 30)
	crystal_label.size = Vector2(168, 60)
	crystal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	crystal_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	crystal_label.add_theme_constant_override("outline_size", 5)
	add_child(crystal_label)

func _build_scroll() -> void:
	scroll = ScrollContainer.new()
	scroll.position = Vector2(20, 126)
	scroll.size = Vector2(1040, 1666)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# upgrade rows are Buttons (MOUSE_FILTER_STOP), which swallow the drag before
	# the container can see it — see TouchScroll
	TouchScroll.attach(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	content.custom_minimum_size = Vector2(1000, 0)
	scroll.add_child(content)

func _build_navbar() -> void:
	var bar := Panel.new()
	bar.add_theme_stylebox_override("panel", UI.frame_box("panel_dark9", 22, 12, 8))
	bar.position = Vector2(-8, 1800)
	bar.size = Vector2(1096, 130)
	add_child(bar)
	var prev := UI.icon_button("ic_prev", Vector2(110, 100))
	prev.position = Vector2(24, 1814)
	prev.pressed.connect(func(): _cycle(-1))
	add_child(prev)
	var nxt := UI.icon_button("ic_next", Vector2(110, 100))
	nxt.position = Vector2(946, 1814)
	nxt.pressed.connect(func(): _cycle(1))
	add_child(nxt)
	nav_name = UI.title("", 40)
	nav_name.position = Vector2(160, 1826)
	nav_name.size = Vector2(760, 72)
	add_child(nav_name)

# ---------------------------------------------------------------------------
func _cur_list() -> Array:
	return Meta.unlocked_towers if sel_type == "tower" else Meta.unlocked_spells

func _switch_type(t: String) -> void:
	if sel_type == t:
		return
	var lst: Array = Meta.unlocked_towers if t == "tower" else Meta.unlocked_spells
	if lst.is_empty():
		return
	sel_type = t
	sel_id = lst[0]
	_rebuild()

func _cycle(dir: int) -> void:
	var lst := _cur_list()
	if lst.is_empty():
		return
	var i: int = lst.find(sel_id)
	if i < 0:
		i = 0
	sel_id = lst[(i + dir + lst.size()) % lst.size()]
	_rebuild()

func _def() -> Dictionary:
	return GameData.tower_by_id(sel_id) if sel_type == "tower" else GameData.spell_by_id(sel_id)

func _levels() -> Array:
	return Meta.tower_levels(sel_id) if sel_type == "tower" else Meta.spell_levels(sel_id)

func _elem() -> String:
	if sel_type == "tower":
		if sel_id == 4: return "fire"
		if sel_id == 5: return "ice"
		if sel_id in [6, 15]: return "poison"
		if sel_id in [3, 10, 11, 17, 18, 19, 20]: return "arcane"
		return "stone"
	else:
		var m: String = _def().mech
		if m in ["meteor", "firewall"]: return "fire"
		if m in ["freezenova", "timewarp"]: return "ice"
		if m == "miasma": return "poison"
		if m in ["stormbolt", "smite", "emp", "blackhole", "warcry", "barrier"]: return "arcane"
		return "stone"

func _rebuild() -> void:
	# refresh tab highlight
	tab_tower.modulate = Color.WHITE if sel_type == "tower" else Color(0.7, 0.7, 0.7)
	tab_spell.modulate = Color.WHITE if sel_type == "spell" else Color(0.7, 0.7, 0.7)
	var def := _def()
	_refresh_kind_map(def)
	nav_name.text = tr(def.name)
	var keep_scroll: int = scroll.scroll_vertical
	for c in content.get_children():
		c.queue_free()
	content.add_child(_zone_showcase(def))
	content.add_child(_zone_stats(def))
	content.add_child(_zone_mech(def))
	content.add_child(_zone_upgrades(def))
	# restore scroll position after layout settles
	await get_tree().process_frame
	scroll.scroll_vertical = keep_scroll

# --- ZONE 1: showcase -------------------------------------------------------
func _zone_showcase(def: Dictionary) -> Control:
	var z := UI.panel_rect()
	z.custom_minimum_size = Vector2(1000, 560)
	var clip := Control.new()
	clip.clip_contents = true
	clip.position = Vector2(26, 22)
	clip.size = Vector2(948, 516)
	z.add_child(clip)
	var bd := UI.tex_rect(Assets.ui("bd_%s" % _elem()), Vector2(948, 516))
	bd.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bd.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	bd.position = Vector2.ZERO
	clip.add_child(bd)
	# platform + big render
	var plat := UI.tex_rect(Assets.ui("platform"), Vector2(420, 176))
	plat.position = Vector2(264, 300)
	clip.add_child(plat)
	var tex: Texture2D = Assets.tower(sel_id) if sel_type == "tower" else Assets.spell(sel_id)
	var render := UI.tex_rect(tex, Vector2(264, 264))   # 44px source at exactly 6x
	render.position = Vector2(342, 118)   # sit the pad ON the stone platform
	clip.add_child(render)
	# name + one-line description on a dark strip
	var strip := ColorRect.new()
	strip.color = Color(0.08, 0.06, 0.05, 0.72)
	strip.position = Vector2(0, 430)
	strip.size = Vector2(948, 86)
	clip.add_child(strip)
	var nm := UI.title(tr(def.name), 46)
	nm.position = Vector2(24, 428)
	nm.size = Vector2(900, 52)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nm.add_theme_color_override("font_color", ELEM_COL[_elem()].lightened(0.35))
	clip.add_child(nm)
	var ds := UI.label(tr(def.desc), 24, UI.TEXT)
	ds.position = Vector2(26, 484)
	ds.size = Vector2(900, 32)
	clip.add_child(ds)
	return z

# --- ZONE 2: performance panel ---------------------------------------------
func _zone_stats(def: Dictionary) -> Control:
	var z := UI.panel_parch()
	z.custom_minimum_size = Vector2(1000, box_height(def))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.position = Vector2(30, 20)
	box.custom_minimum_size = Vector2(940, 0)
	z.add_child(box)
	box.add_child(_section_head(tr("UPG_PERF"), "ic_stats"))
	var is_spell := sel_type == "spell"
	var stats: Dictionary = Meta.tower_stats(sel_id) if not is_spell else Meta.spell_stats(sel_id)
	var mx: Dictionary = STAT_MAX if not is_spell else SPELL_STAT_MAX
	if not is_spell:
		box.add_child(UI.stat_bar("ic_sword", tr("UP_ATK"), _fmt(stats.get("dmg", 0.0), "dmg"),
			_frac("dmg", stats.get("dmg", 0.0), mx), "bar_gold9", 940))
		box.add_child(UI.stat_bar("ic_speed", tr("UP_RATE"),
			tr("UPG_RATE_VALUE").format({"v": _fmt(stats.get("rate", 0.0), "rate")}),
			_frac("rate", stats.get("rate", 0.0), mx), "bar_gold9", 940))
		box.add_child(UI.stat_bar("ic_scope", tr("UP_RANGE"), _fmt(stats.get("range", 0.0), "range"),
			_frac("range", stats.get("range", 0.0), mx), "bar_gold9", 940))
		var dps: float = float(stats.get("dmg", 0.0)) * float(stats.get("rate", 0.0))
		box.add_child(UI.stat_bar("ic_star", tr("UPG_DPS_LABEL"),
			tr("UPG_DPS_VALUE").format({"v": _fmt(dps, "dmg")}),
			clampf(dps / DPS_MAX, 0.03, 1.0), "bar_green9", 940))
		# the tower's signature special (first non-core upgrade direction)
		var sp := _signature_stat(def)
		if sp != "":
			box.add_child(UI.stat_bar("ic_spark", tr(STAT_LABEL.get(sp, sp)),
				_fmt(stats.get(sp, 0.0), sp), _frac(sp, stats.get(sp, 0.0), mx), "bar_crystal9", 940))
		box.add_child(_kv_row(tr("UPG_COST"), "ic_coin",
			tr("UPG_GOLD_VALUE").format({"n": int(def.place_cost)}), UI.GOLD))
	else:
		var has_cd := false
		for up in def.ups:
			var st: String = up.stat
			if st == "cd":
				has_cd = true
			box.add_child(UI.stat_bar(_stat_icon(st), tr(up.name), _fmt(stats.get(st, 0.0), st),
				_frac(st, stats.get(st, 0.0), mx), "bar_gold9", 940))
		if not has_cd:
			box.add_child(_kv_row(tr("UP_CD"), "ic_speed",
				tr("UPG_SEC_VALUE").format({"v": _fmt(stats.get("cd", def.cd), "cd")}),
				UI.CRYSTAL.lightened(0.2)))
	return z

func box_height(def: Dictionary) -> float:
	if sel_type == "tower":
		var n: int = 4 + (1 if _signature_stat(def) != "" else 0)
		return 20 + 52 + n * 68 + 56 + 30
	return 20 + 52 + def.ups.size() * 68 + 56 + 30

func _signature_stat(def: Dictionary) -> String:
	# first upgrade direction whose stat isn't one of the three core stats
	for up in def.ups:
		if not (up.stat in ["dmg", "rate", "range"]):
			return up.stat
	return ""

# --- ZONE 3: mechanics ------------------------------------------------------
func _zone_mech(def: Dictionary) -> Control:
	var z := UI.panel_rect()
	# taller than the round-4 zone: the English mechanic blurbs run roughly 3x the
	# character count of the 繁中 ones and the longest (詛咒塔 / 導彈塔) overflowed
	# the old 276px text column outright
	z.custom_minimum_size = Vector2(1000, 512)
	var head := _section_head(tr("UPG_MECH"), "ic_skull")
	head.position = Vector2(30, 20)
	z.add_child(head)
	var entry: Array = (TOWER_MECH.get(def.mech, ["range", def.desc]) if sel_type == "tower"
		else SPELL_MECH.get(def.mech, ["splash", def.desc]))
	var kind: String = entry[0]
	var lore: String = tr(entry[1])
	# diagram (left) + text (right)
	var diag := _MechDiagram.new()
	diag.kind = kind
	diag.col = ELEM_COL[_elem()]
	diag.position = Vector2(38, 100)
	diag.custom_minimum_size = Vector2(400, 272)
	diag.size = Vector2(400, 272)
	z.add_child(diag)
	# text in a fixed-size clip box so CJK wraps reliably to the column width
	var tbox := Control.new()
	tbox.position = Vector2(460, 100)
	tbox.size = Vector2(504, 392)
	tbox.custom_minimum_size = Vector2(504, 392)
	tbox.clip_contents = true
	z.add_child(tbox)
	# WORD_SMART, not ARBITRARY: ARBITRARY reads fine in 繁中 but chops English
	# mid-word ("everyt / hing"), and it still grapheme-breaks a space-less CJK run
	var txt := UI.label(lore, 22, UI.TEXT)
	txt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	tbox.add_child(txt)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(940, 504)
	z.add_child(pad)
	return z

# --- ZONE 4: upgrade tree ---------------------------------------------------
func _zone_upgrades(def: Dictionary) -> Control:
	var z := UI.panel_rect()
	var rows: int = def.ups.size()
	z.custom_minimum_size = Vector2(1000, 20 + 52 + rows * (138 + 14) + 30)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.position = Vector2(28, 22)
	box.custom_minimum_size = Vector2(944, 0)
	z.add_child(box)
	box.add_child(_section_head(tr("UPG_PATHS"), "ic_up"))
	var levels := _levels()
	for i in def.ups.size():
		box.add_child(_up_row(def, i, levels))
	return z

func _up_row(def: Dictionary, dir: int, levels: Array) -> Control:
	var up: Dictionary = def.ups[dir]
	var lv: int = levels[dir]
	var maxed: bool = lv >= GameData.MAX_UP_LV
	var row := UI.panel_dark()
	row.custom_minimum_size = Vector2(944, 138)

	var ic := UI.tex_rect(Assets.ui(_stat_icon(up.stat)), Vector2(56, 56))
	ic.position = Vector2(24, 22)
	row.add_child(ic)
	var nm := UI.label(tr(up.name), 28, UI.TEXT)
	nm.position = Vector2(92, 16)
	nm.size = Vector2(360, 38)
	nm.clip_text = true
	row.add_child(nm)
	var lvl := UI.label(tr("UPG_LEVEL").format({"lv": lv, "max": GameData.MAX_UP_LV}), 24, UI.PARCH)
	lvl.position = Vector2(92, 58)
	row.add_child(lvl)
	# level pip bar
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", UI.frame_box("bar_track9", 10, 4, 2))
	track.position = Vector2(94, 98)
	track.size = Vector2(360, 18)
	row.add_child(track)
	var fill := UI.tex_rect(Assets.ui("bar_gold9"), Vector2(352.0 * (float(lv) / GameData.MAX_UP_LV), 12))
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.position = Vector2(4, 3)
	track.add_child(fill)

	# now → next
	var nn := _now_next(def, levels, dir)
	var change := UI.label("%s → %s" % [_fmt(nn[0], up.stat), _fmt(nn[1], up.stat)],
		27, UI.GOLD if not maxed else UI.PARCH)
	change.position = Vector2(470, 40)
	change.size = Vector2(220, 40)
	change.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(change)

	if maxed:
		var badge := UI.badge_max(Vector2(120, 120))
		badge.position = Vector2(724, 10)
		row.add_child(badge)
	else:
		var cost: int = Meta.tower_up_cost(sel_id, dir) if sel_type == "tower" else Meta.spell_up_cost(sel_id, dir)
		var afford: bool = Meta.can_afford(cost)
		var btn := UI.button("", Vector2(240, 112), UI.GOLD, 30)
		btn.position = Vector2(700, 14)
		var lbl := UI.label(tr("UPG_BUY"), 28, Color(0.28, 0.18, 0.05))
		lbl.position = Vector2(0, 18)
		lbl.size = Vector2(240, 36)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_child(lbl)
		var crow := HBoxContainer.new()
		crow.position = Vector2(64, 58)
		crow.add_theme_constant_override("separation", 4)
		crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		crow.add_child(UI.tex_rect(Assets.crystal(), Vector2(38, 38)))
		var cl := UI.label(str(cost), 32, Color(0.2, 0.12, 0.35))
		crow.add_child(cl)
		btn.add_child(crow)
		if not afford:
			btn.modulate = Color(0.55, 0.5, 0.5)
		btn.pressed.connect(func(): _try_buy(dir, cost, row))
		row.add_child(btn)
	return row

func _try_buy(dir: int, cost: int, row: Control) -> void:
	if not Meta.can_afford(cost):
		UI.toast(self, tr("TOAST_NEED_CRYSTALS").format({"n": cost - Meta.crystals}))
		UI.shake(row)
		return
	var ok: bool = Meta.buy_tower_upgrade(sel_id, dir) if sel_type == "tower" else Meta.buy_spell_upgrade(sel_id, dir)
	if ok:
		crystal_label.text = str(Meta.crystals)
		_rebuild()

# --- shared helpers ---------------------------------------------------------
func _section_head(text: String, icon: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.custom_minimum_size = Vector2(900, 52)
	h.add_child(UI.tex_rect(Assets.ui(icon), Vector2(44, 44)))
	var l := UI.label(text, 34, UI.GOLD)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	h.add_child(l)
	return h

func _kv_row(name: String, icon: String, val: String, col: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.custom_minimum_size = Vector2(940, 56)
	h.add_child(UI.tex_rect(Assets.ui(icon), Vector2(40, 40)))
	var n := UI.label(name, 26, UI.TEXT)
	n.custom_minimum_size = Vector2(180, 40)
	h.add_child(n)
	var v := UI.label(val, 28, col)
	v.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	v.add_theme_constant_override("outline_size", 4)
	h.add_child(v)
	return h

func _now_next(def: Dictionary, levels: Array, dir: int) -> Array:
	var cur: Dictionary = GameData.effective_stats(def, levels)
	var nxt_levels := levels.duplicate()
	nxt_levels[dir] = mini(int(levels[dir]) + 1, GameData.MAX_UP_LV)
	var nxt: Dictionary = GameData.effective_stats(def, nxt_levels)
	var stat: String = def.ups[dir].stat
	return [cur.get(stat, 0.0), nxt.get(stat, 0.0)]

func _frac(stat: String, val: float, mx: Dictionary) -> float:
	if _is_pct(stat):
		return clampf(val, 0.03, 1.0)
	var m: float = mx.get(stat, 0.0)
	if m <= 0.0:
		return 0.5
	return clampf(absf(val) / m, 0.03, 1.0)

# Stats that are a FRACTION even though their upgrade kind is "add" (a 0..1
# multiplier, not a count). Probability stats are detected from the upgrade's own
# `kind == "prob"` instead of being listed here — that matters because the same
# stat name means different things on different towers:
#   knock  = 擊退機率 on 加農砲台 (prob, %)   vs 擊退距離 on 磁力塔 (add, px)
#   stun   = 麻痺機率 on 雷電塔 (prob, %)     vs 傳送後暈眩 on 傳送塔 (add, 秒)
# The old name-only list printed 磁力塔's 40px knockback as "4000%" and the
# 傳送塔's 0.15s stun as "15%".
const _PCT_STATS := ["curse", "vuln", "slow", "slowafter", "haste", "pct",
	"killbonus", "falloff", "bossmult", "aurahaste", "heavymult", "returnmult",
	# these read as a bare "0" otherwise: their per-level step is smaller than
	# _fmt's 0.05 rounding threshold, so 磁力塔's 擊退後減速 and 狙擊塔's 處決線
	# both showed "0 → 0" and looked like upgrades that did nothing
	"knockslow", "execute", "heatrate", "ramprate", "rampmax",
	# 詛咒塔 rework axes. bosseff is "prob" kind on 緩速力場塔 but "add" on 詛咒塔,
	# so the kind check alone missed it and it rendered as a raw "0.6".
	"goldbonus", "bosseff"]

# stat -> upgrade `kind` for the entry currently on screen, rebuilt per selection
var _cur_kind: Dictionary = {}

func _refresh_kind_map(def: Dictionary) -> void:
	_cur_kind.clear()
	for up in def.ups:
		_cur_kind[up.stat] = up.kind

func _is_pct(stat: String) -> bool:
	return _cur_kind.get(stat, "") == "prob" or stat in _PCT_STATS

func _stat_icon(stat: String) -> String:
	# money first: 掉金加成 is a percentage but it should read as gold, not as a
	# generic "chance" star
	if stat in ["gold", "startgold", "goldbonus"]:
		return "ic_coin"
	if _is_pct(stat):
		return "ic_star"
	if stat in ["dmg", "dps", "bleed", "pstack", "burn", "pulse"]:
		return "ic_sword"
	if stat in ["rate", "respawn", "pulserate", "ramprate", "heatrate", "dur",
			"burndur", "slowdur", "cd", "stun", "linger"]:
		return "ic_speed"
	if stat in ["range", "radius", "aurarange", "tpdist", "length", "push", "splash",
			"minrange", "pburst", "knock"]:
		return "ic_scope"
	if stat in ["soldierhp", "hp", "armor", "block", "reflect", "count", "salvo"]:
		return "ic_shield"
	return "ic_spark"

func _fmt(v: float, stat: String) -> String:
	if _is_pct(stat):
		return "%d%%" % int(round(v * 100.0))
	if stat == "cd":
		return "%.1f" % v
	if absf(v - round(v)) < 0.05:
		return str(int(round(v)))
	return "%.1f" % v

# ---------------------------------------------------------------------------
# Schematic mechanic diagram — drawn per `kind` so arrow/poison/barracks/etc.
# each read differently (range circle / splash rings / chain hops / aura /
# beam / pierce line / soldiers / knockback / teleport / full-screen / segment).
class _MechDiagram extends Control:
	var kind: String = "range"
	var col: Color = Color(1, 0.8, 0.4)

	func _tower(c: Vector2) -> void:
		draw_circle(c, 16, Color(0.20, 0.15, 0.10))
		draw_circle(c, 12, Color(0.55, 0.42, 0.28))
		draw_rect(Rect2(c.x - 5, c.y - 22, 10, 14), Color(0.7, 0.55, 0.35))

	func _enemy(c: Vector2, dim := false) -> void:
		var e := Color(0.75, 0.35, 0.32) if not dim else Color(0.5, 0.45, 0.5)
		draw_circle(c, 12, Color(0, 0, 0, 0.5))
		draw_circle(c, 10, e)

	func _arrow(a: Vector2, b: Vector2, w := 3.0) -> void:
		draw_line(a, b, col, w)
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([b, b - d * 14 + n * 7, b - d * 14 - n * 7]), col)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var mid := Vector2(w * 0.5, h * 0.5)
		match kind:
			"range", "single":
				var t := Vector2(w * 0.28, h * 0.62)
				var r: float = minf(w, h) * 0.42
				draw_arc(t, r, 0, TAU, 48, Color(col.r, col.g, col.b, 0.9), 3.0)
				draw_circle(t, r, Color(col.r, col.g, col.b, 0.10))
				var e := t + Vector2(r * 0.82, -r * 0.35)
				_enemy(e)
				_arrow(t + Vector2(14, -6), e - Vector2(10, -4))
				_tower(t)
			"splash", "area":
				var im := Vector2(w * 0.58, h * 0.5)
				for i in range(3, 0, -1):
					var rr: float = minf(w, h) * 0.16 * i
					draw_arc(im, rr, 0, TAU, 40, Color(col.r, col.g, col.b, 0.35 + 0.15 * (3 - i)), 3.0)
				draw_circle(im, minf(w, h) * 0.12, Color(col.r, col.g, col.b, 0.55))
				for ang in [30, 150, 210, 330]:
					_enemy(im + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * minf(w, h) * 0.34, true)
				var tt := Vector2(w * 0.14, h * 0.72)
				_arrow(tt, im - Vector2(minf(w, h) * 0.2, 0), 3.0)
				_tower(tt)
			"chain":
				var t2 := Vector2(w * 0.14, h * 0.5)
				_tower(t2)
				var pts := [t2 + Vector2(16, -8), Vector2(w * 0.42, h * 0.32),
					Vector2(w * 0.6, h * 0.62), Vector2(w * 0.82, h * 0.36)]
				for i in range(pts.size() - 1):
					_jag(pts[i], pts[i + 1])
				for i in range(1, pts.size()):
					_enemy(pts[i])
			"aura":
				var r2: float = minf(w, h) * 0.42
				draw_circle(mid, r2, Color(col.r, col.g, col.b, 0.16))
				draw_arc(mid, r2, 0, TAU, 48, Color(col.r, col.g, col.b, 0.85), 3.0)
				for ang in [20, 90, 160, 250, 320]:
					_enemy(mid + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * r2 * 0.6, true)
				_tower(mid)
			"beam":
				var tb := Vector2(w * 0.16, h * 0.66)
				var eb := Vector2(w * 0.84, h * 0.34)
				draw_line(tb, eb, Color(col.r, col.g, col.b, 0.35), 12.0)
				draw_line(tb, eb, Color(col.r, col.g, col.b, 0.95), 5.0)
				draw_line(tb, eb, Color(1, 1, 1, 0.8), 2.0)
				_enemy(eb)
				_tower(tb)
			"pierce":
				var y := h * 0.5
				draw_line(Vector2(w * 0.12, y), Vector2(w * 0.9, y), Color(col.r, col.g, col.b, 0.85), 4.0)
				_arrow(Vector2(w * 0.75, y), Vector2(w * 0.9, y))
				_arrow(Vector2(w * 0.3, y), Vector2(w * 0.14, y))
				for fx in [0.32, 0.5, 0.68, 0.86]:
					_enemy(Vector2(w * fx, y))
				_tower(Vector2(w * 0.14, y))
			"mortar":
				var im2 := Vector2(w * 0.68, h * 0.46)
				var tm := Vector2(w * 0.16, h * 0.76)
				# min-range deadzone (dashed)
				var dz: float = minf(w, h) * 0.28
				for a in range(0, 360, 22):
					var p0 := tm + Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a))) * dz
					var p1 := tm + Vector2(cos(deg_to_rad(a + 10)), sin(deg_to_rad(a + 10))) * dz
					draw_line(p0, p1, Color(0.9, 0.4, 0.3, 0.7), 2.0)
				# lob arc: a plain quadratic Bezier. The old one reused the same t in
				# two nested lerps and curled into a spiral artefact at the impact end.
				var apex := (tm + im2) * 0.5 + Vector2(0, -h * 0.42)
				var prev := tm
				for i in range(1, 17):
					var tt2 := i / 16.0
					var q := tm.lerp(apex, tt2).lerp(apex.lerp(im2, tt2), tt2)
					draw_line(prev, q, col, 3.0)
					prev = q
				# impact marked with a starburst, not concentric rings: fed by the
				# incoming arc the rings read as a spiral / snail shell
				for k in 8:
					var ad := Vector2(cos(TAU * k / 8.0), sin(TAU * k / 8.0))
					draw_line(im2 + ad * 14, im2 + ad * (32.0 if k % 2 == 0 else 23.0),
						Color(col.r, col.g, col.b, 0.85), 3.0)
				draw_circle(im2, 11, Color(col.r, col.g, col.b, 0.9))
				_enemy(im2 + Vector2(40, 22), true)
				_tower(tm)
			"slow":
				# a shot lands and drags one target down to a crawl
				var ts := Vector2(w * 0.16, h * 0.66)
				var es := Vector2(w * 0.66, h * 0.40)
				_arrow(ts + Vector2(16, -8), es - Vector2(20, -8))
				draw_arc(es, 30, 0, TAU, 24, Color(col.r, col.g, col.b, 0.9), 3.0)
				_enemy(es)
				for i in 3:
					var ln := 34.0 - i * 10.0
					draw_line(es + Vector2(30 + i * 14, -14 + i * 14),
						es + Vector2(30 + i * 14 + ln, -14 + i * 14),
						Color(col.r, col.g, col.b, 0.85 - i * 0.22), 4.0)
				_tower(ts)
			"dot":
				# stacking poison on ONE target (it was drawn as a splash blast)
				var td := Vector2(w * 0.16, h * 0.68)
				var ed := Vector2(w * 0.62, h * 0.46)
				_arrow(td + Vector2(16, -8), ed - Vector2(18, -8))
				_enemy(ed)
				for i in 3:
					draw_circle(ed + Vector2(-18 + i * 18, -36 - i * 5), 7.0 - i,
						Color(col.r, col.g, col.b, 0.9 - i * 0.2))
				for i in 3:
					draw_line(ed + Vector2(-22 + i * 22, 18),
						ed + Vector2(-22 + i * 22, 36 + i * 6),
						Color(col.r, col.g, col.b, 0.8), 4.0)
				_tower(td)
			"burn":
				# a direct hit that leaves the target burning (not a splash ring)
				var tb2 := Vector2(w * 0.16, h * 0.68)
				var eb2 := Vector2(w * 0.66, h * 0.46)
				_arrow(tb2 + Vector2(16, -8), eb2 - Vector2(20, -8))
				for i in 3:
					var fx2 := eb2.x - 18 + i * 18
					var top := eb2.y - (56 if i == 1 else 42)
					draw_colored_polygon(PackedVector2Array([
						Vector2(fx2, top), Vector2(fx2 - 9, eb2.y - 14),
						Vector2(fx2 + 9, eb2.y - 14)]),
						Color(col.r, col.g, col.b, 0.9 - i * 0.15))
				_enemy(eb2)
				_tower(tb2)
			"snipe":
				# one very long shot into a crosshair (arrow/gatling/missile all used
				# to share the identical plain range circle)
				var tsn := Vector2(w * 0.10, h * 0.80)
				var esn := Vector2(w * 0.86, h * 0.24)
				draw_dashed_line(tsn, esn, Color(col.r, col.g, col.b, 0.5), 2.0, 12.0)
				_arrow(tsn + Vector2(14, -10), esn - Vector2(22, -14), 4.0)
				_enemy(esn)
				draw_arc(esn, 26, 0, TAU, 28, Color(col.r, col.g, col.b, 0.95), 2.5)
				for d in [Vector2(34, 0), Vector2(-34, 0), Vector2(0, 34), Vector2(0, -34)]:
					draw_line(esn + d * 0.55, esn + d, Color(col.r, col.g, col.b, 0.95), 2.5)
				_tower(tsn)
			"ramp":
				# rate climbing while it stays locked on the same target
				var tr2 := Vector2(w * 0.14, h * 0.44)
				var er2 := Vector2(w * 0.84, h * 0.44)
				for i in 5:
					var yy := h * 0.44 - 30 + i * 15
					draw_line(Vector2(w * 0.24, yy), Vector2(w * 0.74, yy),
						Color(col.r, col.g, col.b, 0.32 + i * 0.14), 2.0 + i * 0.9)
				for i in 4:
					draw_rect(Rect2(w * 0.28 + i * 30, h * 0.88 - (12 + i * 14),
						18, 12 + i * 14), Color(col.r, col.g, col.b, 0.8))
				_enemy(er2)
				_tower(tr2)
			"homing":
				# a tracking missile curving onto its target, with a small splash
				var th2 := Vector2(w * 0.14, h * 0.78)
				var eh2 := Vector2(w * 0.76, h * 0.30)
				var ctrl := Vector2(w * 0.28, h * 0.16)
				var prev2 := th2
				for i in range(1, 19):
					var t3 := i / 18.0
					var q2 := th2.lerp(ctrl, t3).lerp(ctrl.lerp(eh2, t3), t3)
					draw_line(prev2, q2, col, 3.0)
					prev2 = q2
				for i in range(2, 0, -1):
					draw_arc(eh2, minf(w, h) * 0.11 * i, 0, TAU, 28,
						Color(col.r, col.g, col.b, 0.45), 3.0)
				_enemy(eh2)
				_tower(th2)
			"gold":
				# coins produced on a timer — it never attacks, so no enemies here
				var tg := Vector2(w * 0.28, h * 0.70)
				draw_arc(tg, minf(w, h) * 0.34, 0, TAU, 40,
					Color(col.r, col.g, col.b, 0.5), 2.0)
				_tower(tg)
				for i in 4:
					var cx2 := tg + Vector2(52 + i * 48, -30 - i * 24)
					draw_circle(cx2, 15, Color(0.55, 0.42, 0.10))
					draw_circle(cx2, 12, Color(0.98, 0.82, 0.28))
					draw_circle(cx2 + Vector2(-4, -4), 4, Color(1, 0.96, 0.8))
			"buff":
				# an aura that helps FRIENDLY towers (the shared "aura" picture put
				# enemies inside the circle, which said the opposite)
				var mb := Vector2(w * 0.5, h * 0.52)
				var rb: float = minf(w, h) * 0.40
				draw_circle(mb, rb, Color(col.r, col.g, col.b, 0.14))
				draw_arc(mb, rb, 0, TAU, 48, Color(col.r, col.g, col.b, 0.85), 3.0)
				for ang in [30, 150, 270]:
					var pf := mb + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * rb * 0.64
					_tower(pf)
					draw_colored_polygon(PackedVector2Array([
						pf + Vector2(0, -46), pf + Vector2(-10, -30), pf + Vector2(10, -30)]),
						Color(col.r, col.g, col.b, 0.95))
				_tower(mb)
			"curseaura":
				# a STANDING circle: the tower sits in it, the enemies caught inside
				# are marked, the friendly towers shooting into it hit harder, and
				# coins fall out of whatever dies in there. The old picture showed a
				# tower firing debuff bolts at three enemies, which is the mechanic
				# that no longer exists.
				var mc := Vector2(w * 0.44, h * 0.54)
				var rc: float = minf(w, h) * 0.42
				draw_circle(mc, rc, Color(col.r, col.g, col.b, 0.15))
				draw_arc(mc, rc, 0, TAU, 52, Color(col.r, col.g, col.b, 0.9), 3.0)
				draw_arc(mc, rc * 0.62, 0, TAU, 40, Color(col.r, col.g, col.b, 0.5), 2.0)
				# rune ticks around the rim
				for i in 8:
					var ra: float = TAU * i / 8.0
					var rp := mc + Vector2(cos(ra), sin(ra)) * rc * 0.82
					draw_line(rp, rp + (mc - rp).normalized() * 9.0,
						Color(col.r, col.g, col.b, 0.9), 2.5)
				# cursed enemies inside, each wearing the little hex mark
				for ang in [25, 150, 265]:
					var pe := mc + Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang))) * rc * 0.55
					_enemy(pe)
					draw_arc(pe + Vector2(0, -20), 5.0, 0, TAU, 10,
						Color(col.r, col.g, col.b, 0.95), 2.0)
					draw_colored_polygon(PackedVector2Array([
						pe + Vector2(0, -32), pe + Vector2(-4, -23), pe + Vector2(4, -23)]),
						Color(col.r, col.g, col.b, 0.95))
				# a friendly output tower shooting INTO the circle: the amplified damage
				var ally := Vector2(w * 0.90, h * 0.20)
				_tower(ally)
				_arrow(ally + Vector2(-10, 10), mc + Vector2(rc * 0.45, -rc * 0.45), 3.5)
				# coins dropping out — the 掉金加成 half of the identity
				for i in 3:
					var cp := mc + Vector2(-rc * 0.15 + i * 20.0, rc * 0.72 + (i % 2) * 12.0)
					draw_circle(cp, 9, Color(0.55, 0.42, 0.10))
					draw_circle(cp, 7, Color(0.98, 0.82, 0.28))
					draw_circle(cp + Vector2(-2, -2), 2.4, Color(1, 0.96, 0.8))
				_tower(mc)
			"knock":
				draw_arc(mid, minf(w, h) * 0.3, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8), 4.0)
				draw_arc(mid, minf(w, h) * 0.42, 0, TAU, 40, Color(col.r, col.g, col.b, 0.4), 3.0)
				for ang in [0, 72, 144, 216, 288]:
					var d := Vector2(cos(deg_to_rad(ang)), sin(deg_to_rad(ang)))
					_enemy(mid + d * minf(w, h) * 0.44, true)
					_arrow(mid + d * minf(w, h) * 0.3, mid + d * minf(w, h) * 0.42, 3.0)
				_tower(mid)
			"teleport":
				var e1 := Vector2(w * 0.74, h * 0.38)
				var e2 := Vector2(w * 0.34, h * 0.62)
				var tt3 := Vector2(w * 0.12, h * 0.80)
				_enemy(e1)
				_enemy(e2, true)
				var cprev := e1
				for i in range(1, 21):
					var a2 := i / 20.0
					var pt := e1.lerp(e2, a2) + Vector2(0, -sin(a2 * PI) * h * 0.32)
					draw_line(cprev, pt, Color(col.r, col.g, col.b, 0.85), 3.0)
					cprev = pt
				_arrow(e2 + Vector2(0, -34), e2 + Vector2(0, -14))
				# the tower doing it was missing entirely, so the arc read as noise
				_tower(tt3)
			"soldiers":
				var ry := h * 0.5
				_tower(Vector2(w * 0.10, h * 0.28))
				draw_rect(Rect2(w * 0.08, ry - 34, w * 0.84, 68), Color(0.45, 0.34, 0.22, 0.6))
				draw_line(Vector2(w * 0.08, ry - 34), Vector2(w * 0.92, ry - 34), Color(0.6, 0.46, 0.3), 3.0)
				draw_line(Vector2(w * 0.08, ry + 34), Vector2(w * 0.92, ry + 34), Color(0.6, 0.46, 0.3), 3.0)
				for fx in [0.7, 0.82]:
					_enemy(Vector2(w * fx, ry))
				for sx in [0.34, 0.46, 0.58]:
					draw_circle(Vector2(w * sx, ry), 13, Color(0.2, 0.35, 0.6))
					draw_circle(Vector2(w * sx, ry - 4), 9, Color(0.4, 0.62, 0.95))
			"fullscreen":
				draw_rect(Rect2(w * 0.06, h * 0.12, w * 0.88, h * 0.76), Color(col.r, col.g, col.b, 0.16))
				draw_rect(Rect2(w * 0.06, h * 0.12, w * 0.88, h * 0.76), Color(col.r, col.g, col.b, 0.6), false, 3.0)
				for gx in [0.22, 0.42, 0.62, 0.82]:
					for gy in [0.34, 0.68]:
						_enemy(Vector2(w * gx, h * gy), true)
			"segment":
				var ry2 := h * 0.5
				draw_rect(Rect2(w * 0.06, ry2 - 30, w * 0.88, 60), Color(0.4, 0.3, 0.2, 0.5))
				draw_rect(Rect2(w * 0.38, ry2 - 40, w * 0.28, 80), Color(col.r, col.g, col.b, 0.4))
				draw_rect(Rect2(w * 0.38, ry2 - 40, w * 0.28, 80), Color(col.r, col.g, col.b, 0.9), false, 3.0)
				for fx in [0.14, 0.24]:
					_enemy(Vector2(w * fx, ry2))
				for fx in [0.78, 0.88]:
					_enemy(Vector2(w * fx, ry2), true)

	func _jag(a: Vector2, b: Vector2) -> void:
		var segs := 5
		var prev := a
		for i in range(1, segs + 1):
			var t := float(i) / segs
			var base := a.lerp(b, t)
			var off := (10.0 if i % 2 == 0 else -10.0) if i < segs else 0.0
			var n := (b - a).normalized()
			var perp := Vector2(-n.y, n.x)
			var p := base + perp * off
			draw_line(prev, p, Color(col.r, col.g, col.b, 0.95), 3.0)
			prev = p
