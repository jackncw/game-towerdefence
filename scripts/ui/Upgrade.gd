extends Control
class_name Upgrade
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
## 跨三階統一刻度。`_HI` = 呢類數值喺「同類物件 tier 3 六軸滿課」嘅全遊戲上限,
## `_LO` = 同類物件喺 tier 1 一級時嘅最細正值。兩個一齊定義咗成條 bar 嘅量程。
##
## 點解要跨階:舊刻度嘅上限係「tier 1 基礎值入面最大嗰個」,所以一座塔淨係
## 課到 tier 1 十級就已經滿格,而一進化就成塊面板頂爆 —— 一條永遠滿嘅 bar
## 講唔到任何嘢,而玩家喺進化之後最需要知嘅正正就係「我行到邊」。
var STAT_HI: Dictionary = {}
var STAT_LO: Dictionary = {}
var SPELL_STAT_HI: Dictionary = {}
var SPELL_STAT_LO: Dictionary = {}
## 每秒傷害唔係一個 stat(佢係 dmg x rate),但佢係塔嘅第一指標,所以佢有
## 自己一對量程。
var DPS_HI: float = 1.0
var DPS_LO: float = 1.0

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
	# not "segment": the summon diagram now shows hooded militia on their circles,
	# matching what the spell actually puts on the field
	"summon": ["militia", "SPELL_SUMMON_LORE"],
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
	_apply_focus()
	_rebuild()

## 由圖鑑撳過嚟嘅話,落喺嗰件嘢上面。讀完清走 —— 下次由主選單入嚟就照舊
## 由第一件開始,唔係接住上次。
##
## 未解鎖嘅嘢照樣唔會被揀中:圖鑑俾你望未買嘅塔,但升級介面淨係處理你有嘅嘢,
## 而一個「揀咗一件你冇嘅嘢」嘅升級介面會喺 _levels() 度攞到一堆冇意義嘅數。
func _apply_focus() -> void:
	var f := Flow.upgrade_focus
	Flow.upgrade_focus = {}
	if f.is_empty():
		return
	var t := String(f.get("type", "tower"))
	var id := int(f.get("id", 0))
	var owned: Array = Meta.unlocked_towers if t == "tower" else Meta.unlocked_spells
	if not owned.has(id):
		return
	sel_type = t
	sel_id = id

# ---------------------------------------------------------------------------
## 全部軸都喺某一級嘅等級向量。
static func level_vector(def: Dictionary, lv: int) -> Array:
	var a: Array = []
	for _i in def.ups.size():
		a.append(lv)
	return a

func _build_stat_tables() -> void:
	for t in GameData.TOWERS:
		for up in t.ups:
			STAT_LABEL[up.stat] = up.name
	for sp in GameData.SPELLS:
		for up in sp.ups:
			STAT_LABEL[up.stat] = up.name
	_scan_range(GameData.TOWERS, STAT_HI, STAT_LO)
	_scan_range(GameData.SPELLS, SPELL_STAT_HI, SPELL_STAT_LO)
	DPS_LO = INF
	for t in GameData.TOWERS:
		for pt in _endpoints(t):
			var d: float = float(pt.get("dmg", 0.0)) * float(pt.get("rate", 0.0))
			DPS_HI = maxf(DPS_HI, d)
			if d > 0.0:
				DPS_LO = minf(DPS_LO, d)
	if not is_finite(DPS_LO):
		DPS_LO = 1.0

## 一件嘢喺量程兩端(同埋中間一個非零起點)嘅樣。
##
## 三個點而唔係兩個,而且上下限**兩個都由三個點一齊摺出嚟**:唔係每一個 stat
## 都係越課越大。冷卻、連鎖衰減、補兵間隔嗰幾條軸嘅步長係**負**嘅,所以佢哋
## 喺「tier 3 六軸滿課」嗰點係最**細**。淨係攞嗰一點做上限嘅話,一個未課過嘅
## 守護結界(冷卻 30 秒)就會除以 7.5,條 bar 永遠爆滿。
##
## 中間嗰點用 tier 1 一級:好多軸嘅零級值就係 0(爆毒、起手金、流血…),
## 而 0 做唔到對數刻度嘅原點。
func _endpoints(d: Dictionary) -> Array:
	return [
		GameData.effective_stats(d, level_vector(d, 0), 1),
		GameData.effective_stats(d, level_vector(d, 1), 1),
		GameData.effective_stats(d, level_vector(d, GameData.MAX_UP_LV), GameData.MAX_TIER),
	]

## 一類物件(塔 / 魔法)每個 stat 嘅量程。
func _scan_range(defs: Array, hi: Dictionary, lo: Dictionary) -> void:
	for d in defs:
		for pt in _endpoints(d):
			for stat in pt.keys():
				var v: float = absf(float(pt[stat]))
				hi[stat] = maxf(hi.get(stat, 0.0), v)
				if v <= 0.0:
					continue
				lo[stat] = minf(lo[stat], v) if lo.has(stat) else v

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
	nav_name.text = tr(GameData.tier_name(def, sel_type == "tower",
		Meta.item_tier(sel_id, sel_type == "tower")))
	var keep_scroll: int = scroll.scroll_vertical
	for c in content.get_children():
		c.queue_free()
	content.add_child(_zone_showcase(def))
	content.add_child(_zone_stats(def))
	content.add_child(_zone_mech(def))
	content.add_child(_zone_upgrades(def))
	content.add_child(_zone_evolve(def))
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
	# 名要跟階 —— 一座已經進化咗嘅塔喺展示區叫返個舊名,係一個直接嘅講大話。
	render.position = Vector2(342, 118)   # sit the pad ON the stone platform
	clip.add_child(render)
	# name + one-line description on a dark strip
	var strip := ColorRect.new()
	strip.color = Color(0.08, 0.06, 0.05, 0.72)
	strip.position = Vector2(0, 430)
	strip.size = Vector2(948, 86)
	clip.add_child(strip)
	var nm := UI.title(tr(GameData.tier_name(def, sel_type == "tower",
		Meta.item_tier(sel_id, sel_type == "tower"))), 46)
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
	var is_spell := sel_type == "spell"
	var tier: int = Meta.item_tier(sel_id, not is_spell)
	var head := _section_head(tr("UPG_PERF"), "ic_stats")
	head.add_child(UI.tier_badge(tier))
	box.add_child(head)
	var stats: Dictionary = Meta.tower_stats(sel_id) if not is_spell else Meta.spell_stats(sel_id)
	if not is_spell:
		box.add_child(_bar(def, tier, "ic_sword", tr("UP_ATK"), "dmg",
			_fmt(stats.get("dmg", 0.0), "dmg"), float(stats.get("dmg", 0.0)), "bar_gold9"))
		box.add_child(_bar(def, tier, "ic_speed", tr("UP_RATE"), "rate",
			tr("UPG_RATE_VALUE").format({"v": _fmt(stats.get("rate", 0.0), "rate")}),
			float(stats.get("rate", 0.0)), "bar_gold9"))
		box.add_child(_bar(def, tier, "ic_scope", tr("UP_RANGE"), "range",
			_fmt(stats.get("range", 0.0), "range"), float(stats.get("range", 0.0)), "bar_gold9"))
		var dps: float = float(stats.get("dmg", 0.0)) * float(stats.get("rate", 0.0))
		box.add_child(_dps_bar(def, tier, dps))
		# the tower's signature special (first non-core upgrade direction)
		var sp := _signature_stat(def)
		if sp != "":
			box.add_child(_bar(def, tier, "ic_spark", tr(STAT_LABEL.get(sp, sp)), sp,
				_fmt(stats.get(sp, 0.0), sp), float(stats.get(sp, 0.0)), "bar_crystal9"))
		box.add_child(_kv_row(tr("UPG_COST"), "ic_coin",
			tr("UPG_GOLD_VALUE").format({"n": int(def.place_cost)}), UI.GOLD))
	else:
		var has_cd := false
		for up in def.ups:
			var st: String = up.stat
			if st == "cd":
				has_cd = true
			box.add_child(_bar(def, tier, _stat_icon(st), tr(up.name), st,
				_fmt(stats.get(st, 0.0), st), float(stats.get(st, 0.0)), "bar_gold9"))
		if not has_cd:
			box.add_child(_kv_row(tr("UP_CD"), "ic_speed",
				tr("UPG_SEC_VALUE").format({"v": _fmt(stats.get("cd", def.cd), "cd")}),
				UI.CRYSTAL.lightened(0.2)))
	box.add_child(_scale_legend())
	return z

func box_height(def: Dictionary) -> float:
	var n: int = def.ups.size()
	if sel_type == "tower":
		n = 4 + (1 if _signature_stat(def) != "" else 0)
	# +84: 刻度圖例。英文係兩行(繁中一行),而高度要按最長嗰個語言訂 ——
	# 按最短嗰個訂就會喺英文版度俾板底切走半行。
	return 20 + 52 + n * UI.STAT_BAR_H + 56 + 84 + 30

## 一條跨三階刻度嘅 bar。
##
## `stat` 決定量程同分區:跟 tier 放大嘅 stat 用對數刻度 + 三段分區,
## 唔跟階嘅(射程、機率、持續)照舊線性而且**唔畫**分區 —— 畫咗就係喺一個
## 冇三段路可行嘅數字上面畫三段路。
func _bar(def: Dictionary, tier: int, icon: String, name: String, stat: String,
		value_txt: String, value: float, fill_tex: String) -> Control:
	var sc := _scale_for(def, stat, value)
	return UI.stat_bar(icon, name, value_txt, sc.frac, fill_tex, 940, sc.bands, tier)

func _dps_bar(def: Dictionary, tier: int, dps: float) -> Control:
	var bands: Array = []
	for t in range(1, GameData.MAX_TIER):
		var e: Dictionary = GameData.effective_stats(def,
			level_vector(def, GameData.MAX_UP_LV), t)
		bands.append(_log_frac(float(e.get("dmg", 0.0)) * float(e.get("rate", 0.0)),
			DPS_LO, DPS_HI))
	return UI.stat_bar("ic_star", tr("UPG_DPS_LABEL"),
		tr("UPG_DPS_VALUE").format({"v": _fmt(dps, "dmg")}),
		_log_frac(dps, DPS_LO, DPS_HI), "bar_green9", 940, bands, tier)

## 一個 stat 值喺統一刻度上面嘅位置,連埋呢件嘢自己 tier 1 / tier 2 滿課
## 落喺邊 —— 嗰兩點就係 bar 底下三段淺色分區嘅界線。
func _scale_for(def: Dictionary, stat: String, val: float) -> Dictionary:
	var is_tower := sel_type == "tower"
	var hi: float = float((STAT_HI if is_tower else SPELL_STAT_HI).get(stat, 0.0))
	var lo: float = float((STAT_LO if is_tower else SPELL_STAT_LO).get(stat, 0.0))
	if stat in GameData.TIER_SCALED_STATS and hi > 0.0 and lo > 0.0 and hi > lo * 1.01:
		var full := level_vector(def, GameData.MAX_UP_LV)
		var bands: Array = []
		for t in range(1, GameData.MAX_TIER):
			bands.append(_log_frac(
				float(GameData.effective_stats(def, full, t).get(stat, 0.0)), lo, hi))
		return {"frac": _log_frac(val, lo, hi), "bands": bands}
	if _is_pct(stat):
		return {"frac": clampf(absf(val), 0.03, 1.0), "bands": []}
	return {"frac": clampf(absf(val) / maxf(hi, 0.0001), 0.03, 1.0), "bands": []}

## 對數位置。三千幾倍嘅量程之下線性刻度會令頭兩階完全睇唔見,而每一階本身
## 就係一個固定倍率 —— 對數就係「將倍率變成等距」嗰個轉換,所以三段分區
## 喺對數之下自然係差唔多闊嘅三段。
static func _log_frac(v: float, lo: float, hi: float) -> float:
	if v <= 0.0 or lo <= 0.0 or hi <= lo:
		return 0.0
	return clampf(log(maxf(absf(v), lo) / lo) / log(hi / lo), 0.0, 1.0)

## bar 底三段分區代表乜。冇呢行嘅話啲淺色格就係裝飾。
func _scale_legend() -> Control:
	var l := UI.label(tr("UPG_SCALE_LEGEND"), 20, UI.TEXT_DIM)
	l.custom_minimum_size = Vector2(940, 76)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return l

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

# --- ZONE 5: 進化 -----------------------------------------------------------
# 呢一區永遠喺度,唔係「條件夠先出現」。
#
# 一個只有夠條件先見到嘅區塊等於一個秘密:玩家六條軸課到第十級都唔知道有
# 進化呢回事,亦都唔知道自己課緊嘅嘢通往邊。所以未夠條件嗰陣佢照樣畫一個
# 剪影 + 進度(3/6 條軸滿),夠條件先亮起 —— 「你差幾多」本身就係內容。
const EVO_SILHOUETTE := Color(0.06, 0.05, 0.07, 1.0)

func _is_tower() -> bool:
	return sel_type == "tower"

func _zone_evolve(def: Dictionary) -> Control:
	var is_tower := _is_tower()
	var tier: int = Meta.item_tier(sel_id, is_tower)
	var z := UI.panel_rect()
	# 540 唔係 470:條「全部軸已滿」提示喺英文係兩行(繁中一行),而 470 之下
	# 佢會被進化掣壓住最後半行 —— 一句被切走一半嘅提示比冇提示更差,因為佢
	# 睇落好似完整咁。高度按最長嗰個語言嚟訂,唔係按最短嗰個。
	z.custom_minimum_size = Vector2(1000, 540)
	var head := _section_head(tr("EVO_SECTION"), "ic_star")
	head.position = Vector2(30, 20)
	z.add_child(head)
	# 現階徽章
	var cur := UI.label(tr("EVO_TIER_LABEL").format({"n": tier}), 30, UI.PARCH)
	cur.position = Vector2(700, 24); cur.size = Vector2(260, 44)
	cur.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	z.add_child(cur)

	if tier >= GameData.MAX_TIER:
		var maxed := UI.label(tr("EVO_MAXED"), 34, UI.GOLD)
		maxed.position = Vector2(60, 200); maxed.size = Vector2(880, 60)
		maxed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		z.add_child(maxed)
		var seal := UI.badge_max(Vector2(120, 120))
		seal.position = Vector2(480, 290)
		z.add_child(seal)
		return z

	var next_tier: int = tier + 1
	var ready: bool = Meta.all_axes_maxed(sel_id, is_tower)
	# 下一階預覽:未夠條件就係剪影 —— 見得到形狀,見唔到細節。
	var tex: Texture2D = (Assets.tower(sel_id, next_tier) if is_tower
		else Assets.spell(sel_id, next_tier))
	var pv := UI.tex_rect(tex, Vector2(176, 176))
	pv.position = Vector2(56, 96)
	if not ready:
		pv.modulate = EVO_SILHOUETTE
	z.add_child(pv)

	var nm := UI.label(tr(GameData.tier_name(def, is_tower, next_tier)) if ready
		else tr("BESTIARY_UNKNOWN"), 38, UI.GOLD if ready else Color(0.55, 0.52, 0.5))
	nm.position = Vector2(256, 100); nm.size = Vector2(700, 50)
	z.add_child(nm)

	var mk: String = GameData.tier_mech_key(def, is_tower, next_tier)
	var mbox := Control.new()
	mbox.position = Vector2(256, 152); mbox.size = Vector2(690, 110)
	mbox.clip_contents = true
	z.add_child(mbox)
	# 破折號而唔係冒號:繁中「新機制:」後面唔加空格,英文 "New mechanic:" 後面
	# 一定要加,而同一句 format 出唔到兩種標點習慣 —— 破折號兩邊都成立。
	var mech := UI.label("%s — %s" % [tr("EVO_NEW_MECH"), tr(mk)] if ready else "???",
		24, UI.TEXT if ready else Color(0.55, 0.52, 0.5))
	mech.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mech.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mech.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	mbox.add_child(mech)

	# 條件 / 提示
	var done_total: Array = Meta.axes_maxed_count(sel_id, is_tower)
	var hintbox := Control.new()
	hintbox.position = Vector2(56, 286); hintbox.size = Vector2(890, 96)
	hintbox.clip_contents = true
	z.add_child(hintbox)
	var hint := UI.label(tr("EVO_READY_HINT") if ready
		else tr("EVO_REQ_HINT_SPELL" if not is_tower else "EVO_REQ_HINT").format(
			{"max": GameData.MAX_UP_LV, "done": done_total[0], "total": done_total[1]}),
		24, UI.ACCENT.lightened(0.2) if ready else UI.TEXT_DIM)
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	hintbox.add_child(hint)

	# 進化掣 + 費用
	var cost: int = GameData.evolve_cost(is_tower, next_tier)
	var btn := UI.button("", Vector2(300, 116), UI.GOLD if ready else UI.PANEL, 30)
	btn.position = Vector2(620, 398)
	var lbl := UI.label(tr("EVO_BUTTON"), 30, Color(0.28, 0.18, 0.05) if ready else UI.TEXT_DIM)
	lbl.position = Vector2(0, 16); lbl.size = Vector2(300, 38)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	var crow := HBoxContainer.new()
	crow.position = Vector2(88, 60)
	crow.add_theme_constant_override("separation", 6)
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crow.add_child(UI.tex_rect(Assets.crystal(), Vector2(38, 38)))
	crow.add_child(UI.label(str(cost), 30, Color(0.2, 0.12, 0.35) if ready else UI.TEXT_DIM))
	btn.add_child(crow)
	if not (ready and Meta.can_afford(cost)):
		btn.modulate = Color(0.55, 0.5, 0.5)
	btn.pressed.connect(func(): _try_evolve(cost, z))
	z.add_child(btn)
	var costlbl := UI.label(tr("EVO_COST"), 26, UI.TEXT_DIM)
	costlbl.position = Vector2(56, 434); costlbl.size = Vector2(400, 40)
	z.add_child(costlbl)
	return z

## 進化。三種失敗各有各嘅講法 —— 「未夠級」同「唔夠魔晶」係兩件唔同嘅事,
## 而一個統一嘅「唔得」會令玩家去補錯嘅嘢。
func _try_evolve(cost: int, row: Control) -> void:
	var is_tower := _is_tower()
	if not Meta.all_axes_maxed(sel_id, is_tower):
		UI.toast(self, tr("TOAST_EVO_LOCKED"))
		UI.shake(row)
		return
	if not Meta.can_afford(cost):
		UI.toast(self, tr("TOAST_EVO_NEED").format({"n": cost - Meta.crystals}))
		UI.shake(row)
		return
	if not Meta.evolve(sel_id, is_tower):
		return
	crystal_label.text = str(Meta.crystals)
	var new_name: String = tr(GameData.tier_name(_def(), is_tower,
		Meta.item_tier(sel_id, is_tower)))
	_evolve_ceremony()
	UI.toast(self, tr("TOAST_EVO_DONE").format({"name": new_name}), UI.GOLD)
	_rebuild()

## 儀式感演出:一道由下而上嘅光柱掃過成個畫面 + 一圈爆閃。
## 冇呢個嘅話一次進化同買一級升級喺畫面上係一模一樣嘅 —— 而佢哋喺價錢上
## 差成百倍。演出唔係裝飾,佢係「呢件事有幾大」嘅唯一表達。
func _evolve_ceremony() -> void:
	var beam := ColorRect.new()
	beam.color = Color(1.0, 0.92, 0.62, 0.0)
	beam.position = Vector2(0, 0)
	beam.size = Vector2(1080, 1920)
	beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	beam.z_index = 250
	add_child(beam)
	var tw := create_tween()
	tw.tween_property(beam, "color:a", 0.55, 0.12)
	tw.tween_property(beam, "color:a", 0.0, 0.45)
	tw.tween_callback(beam.queue_free)

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

## 升級欄嘅「而家 → 下一級」。
##
## 第十一輪之前呢兩個數係用 effective_stats(def, levels) 計 —— 冇傳 tier,
## 所以 tier 參數食咗預設值 1。即係話一座已經進化嘅塔,升級欄報返嘅係
## 「如果佢仲係第一階」嗰個數。劇毒瘴氣嘅例:15 級每秒毒傷實際 130,
## 進化上 tier 2、六條軸歸零之後,升級欄寫住 25 → 32,而引擎實際用緊
## 400 → 512。差咗 16 倍,而且個方向係**倒退**,睇落好似進化整衰咗件嘢。
##
## 而家所有數都經呢度出,而 test/StatDisplayTest.gd 逐項將呢個函數同
## Meta.tower_stats() / Meta.spell_stats()(引擎真正讀嗰個)對數。
static func now_next_values(def: Dictionary, levels: Array, tier: int, dir: int) -> Array:
	var cur: Dictionary = GameData.effective_stats(def, levels, tier)
	var nxt_levels := levels.duplicate()
	nxt_levels[dir] = mini(int(levels[dir]) + 1, GameData.MAX_UP_LV)
	var nxt: Dictionary = GameData.effective_stats(def, nxt_levels, tier)
	var stat: String = def.ups[dir].stat
	return [cur.get(stat, 0.0), nxt.get(stat, 0.0)]

func _now_next(def: Dictionary, levels: Array, dir: int) -> Array:
	return now_next_values(def, levels, Meta.item_tier(sel_id, sel_type == "tower"), dir)


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

## 同一個 map,但係 static —— 測試同圖鑑都要問「呢個 stat 喺呢件嘢上面係
## 咩 kind」,而三個地方各自砌一次就一定會有一日答案唔同。
static func kind_map(def: Dictionary) -> Dictionary:
	var m := {}
	for up in def.ups:
		m[up.stat] = up.kind
	return m

static func is_pct_stat(stat: String, kind: String) -> bool:
	return kind == "prob" or stat in _PCT_STATS

## 一個 stat 值嘅顯示文字。呢個係全遊戲**唯一**將數字變成字嘅地方(升級介面、
## 圖鑑、效能面板都經佢),所以「畫面上見到嘅」同「引擎用緊嘅」之間只有一層
## 轉換,而嗰層有得逐項對數。
static func fmt_value(v: float, stat: String, kind: String) -> String:
	if is_pct_stat(stat, kind):
		return "%d%%" % int(round(v * 100.0))
	if stat == "cd":
		return "%.1f" % v
	if absf(v) >= 1000.0:
		# tier 3 之後傷害去到四五位數,而 "2560.0" 呢類尾數係純粹噪音。
		return str(int(round(v)))
	if absf(v - round(v)) < 0.05:
		return str(int(round(v)))
	return "%.1f" % v

func _refresh_kind_map(def: Dictionary) -> void:
	_cur_kind = kind_map(def)

func _is_pct(stat: String) -> bool:
	return is_pct_stat(stat, String(_cur_kind.get(stat, "")))

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
	return fmt_value(v, stat, String(_cur_kind.get(stat, "")))

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

	## Barracks trooper: armoured, square-shouldered, feet on the ground.
	func _trooper(c: Vector2) -> void:
		draw_circle(c, 13, Color(0.2, 0.35, 0.6))
		draw_circle(c + Vector2(0, -4), 9, Color(0.4, 0.62, 0.95))

	## Summoned militia: hooded and legless over a rune circle. Deliberately not
	## _trooper — on the field the two are told apart by silhouette, and the
	## upgrade screen has to teach the same shape.
	func _militia(c: Vector2) -> void:
		var glow := Color(0.62, 0.86, 1.0)
		# ground circle (squashed, like the one Soldier._draw_rune_circle draws)
		var pts := PackedVector2Array()
		for i in 21:
			var a := TAU * float(i) / 20.0
			pts.append(c + Vector2(cos(a) * 20.0, sin(a) * 8.0 + 16.0))
		draw_polyline(pts, Color(glow.r, glow.g, glow.b, 0.7), 2.0)
		# hooded robe tapering to a point — no legs
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -20), c + Vector2(9, -6), c + Vector2(12, 10),
			c + Vector2(0, 18), c + Vector2(-12, 10), c + Vector2(-9, -6)]),
			Color(glow.r, glow.g, glow.b, 0.85))
		draw_rect(Rect2(c.x - 5, c.y - 14, 10, 6), Color(0.10, 0.16, 0.30))

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
					_trooper(Vector2(w * sx, ry))
			"militia":
				# Same road-blocking idea as "soldiers", drawn with the magic body
				# so the upgrade screen matches the field: hooded, on a rune
				# circle, no barracks behind them.
				var mry := h * 0.5
				draw_rect(Rect2(w * 0.06, mry - 34, w * 0.88, 68), Color(0.45, 0.34, 0.22, 0.6))
				draw_line(Vector2(w * 0.06, mry - 34), Vector2(w * 0.94, mry - 34), Color(0.6, 0.46, 0.3), 3.0)
				draw_line(Vector2(w * 0.06, mry + 34), Vector2(w * 0.94, mry + 34), Color(0.6, 0.46, 0.3), 3.0)
				for fx in [0.74, 0.88]:
					_enemy(Vector2(w * fx, mry))
				for sx in [0.20, 0.36, 0.52]:
					_militia(Vector2(w * sx, mry))
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
