extends Control
## 圖鑑。三個分頁:**怪物 / 塔 / 魔法**。
##
## 怪物頁(原本嘅圖鑑):一族一頁,lv1-5 + boss,只有真係喺戰場見過嘅
## (Meta.seen)先揭盅,其餘剪影 + 「???」。左右翻頁 + 掃動。
##
## 塔頁同魔法頁(第十一輪加):一件一張卡,由上到下捲。每張卡答四條問題 ——
## 「佢做乜」、「佢而家幾強」、「我課到邊」、「佢仲會變成乜」。
##
## 兩個「未擁有」嘅狀態要分得清楚,佢哋唔係同一件事:
##   * **未喺商店解鎖** —— 剪影 + 名 + 解鎖價。你買唔買係你嘅決定。
##   * **未進化到嗰階** —— 剪影 + 「進化後解鎖」。你買唔到,要課上去。
## 舊圖鑑一律用「???」,而嗰個答唔到「我要做啲乜」。
##
## 每張卡撳落去跳去嗰件嘢嘅升級介面 —— 圖鑑係一個「望」嘅地方,而望完通常
## 想做嘢,而由圖鑑行返去主選單再入升級再翻到嗰座塔係四下操作。

var fam_idx: int = 0
var sel_slot: int = 0          # 0..4 = lv1..5, 5 = boss
var page_root: Control
var _swipe_accum: float = 0.0
# overlay mode: shown on top of a paused battle (from the pause menu) and simply
# frees itself on close; scene mode returns to the main menu.
var overlay: bool = false
var return_path: String = "res://scenes/MainMenu.tscn"

## "monster" / "tower" / "spell"
var tab: String = "monster"
var _tab_btns: Dictionary = {}
var _pager: Array = []

const SLOT_LABELS := ["Lv1", "Lv2", "Lv3", "Lv4", "Lv5", "BOSS"]
const TABS := ["monster", "tower", "spell"]
const TAB_KEYS := {"monster": "BESTIARY_TAB_MONSTER", "tower": "BESTIARY_TAB_TOWER",
	"spell": "BESTIARY_TAB_SPELL"}
## 剪影:見到形狀,見唔到細節。同升級介面嘅進化預覽用同一隻色。
const SILHOUETTE := Color(0.06, 0.05, 0.07, 1.0)

func _ready() -> void:
	UI.fullscreen_bg(self, Color(0.11, 0.085, 0.065))
	var title := UI.title(tr("BESTIARY_TITLE"), 52)
	title.position = Vector2(0, 24); title.size = Vector2(1080, 70)
	add_child(title)
	var back := UI.button(tr("NAV_BACK"), Vector2(200, 80), UI.PANEL, 30)
	back.position = Vector2(24, 34)
	back.pressed.connect(_go_back)
	add_child(back)

	# 分頁掣。三個並排,闊度夠英文最長嗰個("Monsters"/"Towers"/"Spells")。
	var tw := 300.0
	for i in TABS.size():
		var t: String = TABS[i]
		var b := UI.button(tr(TAB_KEYS[t]), Vector2(tw, 84), UI.PANEL_HI, 30)
		b.position = Vector2(40 + i * (tw + 20), 116)
		b.pressed.connect(func(): _switch_tab(t))
		add_child(b)
		_tab_btns[t] = b

	# family pager controls (怪物頁專用)
	var prev := UI.button("‹", Vector2(96, 96), UI.PANEL_HI, 52)
	prev.position = Vector2(24, 216)
	prev.pressed.connect(func(): _turn(-1))
	add_child(prev)
	var nxt := UI.button("›", Vector2(96, 96), UI.PANEL_HI, 52)
	nxt.position = Vector2(960, 216)
	nxt.pressed.connect(func(): _turn(1))
	add_child(nxt)
	_pager = [prev, nxt]

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

func _switch_tab(t: String) -> void:
	if tab == t:
		return
	tab = t
	_rebuild()

func _turn(dir: int) -> void:
	if tab != "monster":
		return
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
	for t in TABS:
		(_tab_btns[t] as Control).modulate = (Color.WHITE if t == tab
			else Color(0.66, 0.62, 0.58))
	for p in _pager:
		(p as Control).visible = tab == "monster"
	match tab:
		"tower":
			_build_catalogue(true)
			return
		"spell":
			_build_catalogue(false)
			return
	_build_monster_page()

# ===========================================================================
# 塔頁 / 魔法頁
# ===========================================================================
## 一件一張卡,由上到下捲。塔卡高過魔法卡(六條軸 vs 三條)。
const CARD_W := 1000.0
const TOWER_CARD_H := 506.0
const SPELL_CARD_H := 474.0

func _build_catalogue(is_tower: bool) -> void:
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 216)
	scroll.size = Vector2(CARD_W, 1560)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	page_root.add_child(scroll)
	# 每張卡係一個 Button(MOUSE_FILTER_STOP),會喺 container 見到之前食咗個
	# drag —— 同升級介面一樣嘅問題,同一個答案。
	TouchScroll.attach(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	box.custom_minimum_size = Vector2(CARD_W, 0)
	scroll.add_child(box)
	var defs: Array = GameData.TOWERS if is_tower else GameData.SPELLS
	for def in defs:
		box.add_child(_entry_card(def, is_tower))

func _entry_card(def: Dictionary, is_tower: bool) -> Control:
	var id: int = def.id
	var owned: bool = Meta.is_tower_unlocked(id) if is_tower else Meta.is_spell_unlocked(id)
	var tier: int = Meta.item_tier(id, is_tower)
	var card := Button.new()
	card.custom_minimum_size = Vector2(CARD_W, TOWER_CARD_H if is_tower else SPELL_CARD_H)
	card.add_theme_stylebox_override("normal", UI.frame_box("panel9", 22, 8, 8))
	card.add_theme_stylebox_override("hover", UI.frame_box("panel9", 22, 8, 8,
		Color(1.12, 1.12, 1.12)))
	card.add_theme_stylebox_override("pressed", UI.frame_box("panel9", 22, 8, 8,
		Color(0.8, 0.8, 0.84)))
	# 戰鬥入面開嘅圖鑑係一個 overlay,而跳去升級介面會炸咗場仗。
	if not overlay:
		card.pressed.connect(func(): _goto_upgrade(id, is_tower))
	else:
		card.disabled = true
		card.focus_mode = Control.FOCUS_NONE

	var tex: Texture2D = Assets.tower(id, tier) if is_tower else Assets.spell(id, tier)
	var icon := UI.tex_rect(tex, Vector2(128, 128), true)
	icon.position = Vector2(28, 26)
	if not owned:
		icon.modulate = SILHOUETTE
	card.add_child(icon)

	var nm := UI.label(tr(GameData.tier_name(def, is_tower, tier)), 36,
		UI.GOLD if owned else Color(0.58, 0.55, 0.52))
	nm.position = Vector2(176, 26); nm.size = Vector2(620, 46)
	nm.clip_text = true
	card.add_child(nm)
	if owned:
		var badge := UI.tier_badge(tier)
		badge.position = Vector2(880, 24)
		card.add_child(badge)
	else:
		# 未解鎖:名 + 解鎖價。呢張卡唯一嘅內容就係「你買唔買」。
		var price := UI.currency_row(Assets.crystal(), _unlock_cost(id, is_tower),
			UI.CRYSTAL, 30)
		price.position = Vector2(820, 30)
		card.add_child(price)

	var dbox := Control.new()
	dbox.position = Vector2(176, 78); dbox.size = Vector2(790, 68)
	dbox.clip_contents = true
	dbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(dbox)
	var desc := UI.label(tr(def.desc), 24, UI.TEXT if owned else UI.TEXT_DIM)
	desc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	dbox.add_child(desc)

	card.add_child(_tier_chain(def, is_tower, tier, owned))
	if owned:
		card.add_child(_mech_line(def, is_tower, tier))
		card.add_child(_stat_summary(def, is_tower, tier))
		card.add_child(_axis_grid(def, is_tower))
	else:
		var lock := UI.label(tr("BESTIARY_NOT_OWNED"), 26, UI.TEXT_DIM)
		lock.position = Vector2(28, TOWER_CARD_H - 120 if is_tower else SPELL_CARD_H - 110)
		lock.size = Vector2(940, 40)
		lock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(lock)
	return card

func _unlock_cost(id: int, is_tower: bool) -> int:
	return int(GameData.tower_by_id(id).unlock) if is_tower else Meta.spell_unlock_cost(id)

## 三階演進鏈,橫排:sprite + 名 + 羅馬數字。已到嘅階全彩,未到嘅剪影。
##
## 未到嘅階**照樣畫個形**:一條「你唔知佢會變成乜」嘅升級路冇人會行,而呢個鏈
## 就係嗰條路嘅樣。升級介面嘅進化區只睇得到下一階,呢度睇得到成條。
## 該階嘅機制描述唔喺格入面(三格得 198px 闊,英文一定斷喺半句)——
## 見 _mech_line()。
func _tier_chain(def: Dictionary, is_tower: bool, tier: int, owned: bool) -> Control:
	var wrap := Control.new()
	wrap.position = Vector2(28, 162)
	wrap.size = Vector2(944, 124)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cw := 314.0
	for t in range(1, GameData.MAX_TIER + 1):
		var cell := Control.new()
		cell.position = Vector2((t - 1) * cw, 0)
		cell.size = Vector2(cw - 12, 124)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var have: bool = owned and t <= tier
		var tex: Texture2D = Assets.tower(def.id, t) if is_tower else Assets.spell(def.id, t)
		var ic := UI.tex_rect(tex, Vector2(84, 84), true)
		ic.position = Vector2(6, 6)
		if not have:
			ic.modulate = SILHOUETTE
		cell.add_child(ic)
		# 個名要**入一個 clip 過嘅框**,唔可以淨係擺個 size 落 Label:
		# Label 嘅 size 會被佢自己嘅 minimum size(由文字長度決定)頂返大,
		# 所以一個長 tier 名會直接畫過隔籬格。呢個係 _zone_mech 用開嗰個做法。
		var nbox := Control.new()
		nbox.position = Vector2(98, 8); nbox.size = Vector2(cw - 116, 62)
		nbox.clip_contents = true
		nbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(nbox)
		# 兩個「睇唔到」嘅原因唔可以講成同一句:第一階唔係「進化後解鎖」,
		# 佢係「你未買」——而嗰兩件事要做嘅嘢完全唔同(去商店 vs 課六條軸)。
		var caption: String = tr(GameData.tier_name(def, is_tower, t)) if have \
			else tr("BESTIARY_SHOP_LOCKED" if t == 1 else "BESTIARY_EVO_LOCKED")
		var nm := UI.label(caption, 22, UI.TEXT if have else Color(0.55, 0.52, 0.5))
		nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		nbox.add_child(nm)
		var rn := UI.label(["", "I", "II", "III"][t], 20,
			UI.GOLD if have else UI.TEXT_DIM)
		rn.position = Vector2(6, 94); rn.size = Vector2(84, 28)
		rn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(rn)
		wrap.add_child(cell)
	return wrap

## 當前階嘅機制描述,整行闊。
##
## 呢句本來塞喺演進鏈嗰三格入面,而三格得 198px 闊 —— 英文機制描述長過繁中
## 大約三倍,結果每一格都喺半句度斷("becomes a triple, and")。一句斷喺
## 連接詞度嘅描述比冇描述更差,因為佢睇落好似完整咁。
##
## 第一階冇「新機制」—— 嗰陣講嘅係佢本身點運作,而嗰句就係卡頂嗰句 desc,
## 所以第一階呢一行唔畫。
func _mech_line(def: Dictionary, is_tower: bool, tier: int) -> Control:
	var box := Control.new()
	box.position = Vector2(28, 286)
	box.size = Vector2(944, 34)
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mk: String = GameData.tier_mech_key(def, is_tower, tier)
	if mk == "":
		return box
	var l := UI.label("%s — %s" % [tr("EVO_NEW_MECH"), tr(mk)], 20, UI.TEXT_DIM)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.clip_text = true
	box.add_child(l)
	return box

## 當前階嘅實際數值摘要。用 Meta.*_stats() —— 即係引擎真正讀嗰個 dictionary,
## 同升級介面同一個來源,所以「圖鑑寫嘅」同「打出嚟嘅」係同一個數。
func _stat_summary(def: Dictionary, is_tower: bool, _tier: int) -> Control:
	var wrap := Control.new()
	wrap.position = Vector2(28, 324)
	wrap.size = Vector2(944, 56)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var s: Dictionary = Meta.tower_stats(def.id) if is_tower else Meta.spell_stats(def.id)
	var kinds := Upgrade.kind_map(def)
	var cells: Array = []
	if is_tower:
		cells.append([tr("UP_ATK"), Upgrade.fmt_value(float(s.get("dmg", 0.0)), "dmg",
			String(kinds.get("dmg", "")))])
		cells.append([tr("UPG_DPS_LABEL"), Upgrade.fmt_value(
			float(s.get("dmg", 0.0)) * float(s.get("rate", 0.0)), "dmg", "")])
		cells.append([tr("UP_RANGE"), Upgrade.fmt_value(float(s.get("range", 0.0)),
			"range", "")])
		cells.append([tr("UPG_COST"), str(GameData.place_cost(int(def.id)))])
	else:
		var has_cd := false
		for up in def.ups:
			var st: String = up.stat
			if st == "cd":
				has_cd = true
			cells.append([tr(up.name), Upgrade.fmt_value(float(s.get(st, 0.0)), st,
				String(up.kind))])
		# 冷卻只有喺佢**唔係**一條升級軸嗰陣先另外列。十個魔法入面「冷卻」
		# 本身就係第三條軸,而嗰十張卡本來會印住兩格一模一樣嘅「冷卻」。
		if not has_cd:
			cells.append([tr("UP_CD"),
				Upgrade.fmt_value(float(s.get("cd", def.cd)), "cd", "")])
	var w: float = 944.0 / float(cells.size())
	for i in cells.size():
		var k := UI.label(String(cells[i][0]), 20, UI.TEXT_DIM)
		k.position = Vector2(i * w, 0); k.size = Vector2(w - 8, 26)
		k.clip_text = true
		wrap.add_child(k)
		var v := UI.label(String(cells[i][1]), 28, UI.GOLD)
		v.position = Vector2(i * w, 26); v.size = Vector2(w - 8, 32)
		wrap.add_child(v)
	return wrap

## 全部升級軸嘅當前等級。冇條 bar 都睇得出邊條落後 —— 「15/15」同「3/15」
## 喺同一行入面對比得到,而呢個就係玩家喺進化路上面要答嘅問題。
func _axis_grid(def: Dictionary, is_tower: bool) -> Control:
	var cols := 3
	var rows: int = int(ceilf(float(def.ups.size()) / float(cols)))
	var wrap := Control.new()
	wrap.position = Vector2(28, 388)
	wrap.size = Vector2(944, rows * 30 + 36)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var levels: Array = Meta.tower_levels(def.id) if is_tower else Meta.spell_levels(def.id)
	var cw := 944.0 / float(cols)
	for i in def.ups.size():
		var lv: int = int(levels[i]) if i < levels.size() else 0
		var full: bool = lv >= GameData.MAX_UP_LV
		var cell := UI.label("%s  %d/%d" % [tr(def.ups[i].name), lv, GameData.MAX_UP_LV],
			20, UI.ACCENT.lightened(0.2) if full else UI.TEXT_DIM)
		cell.position = Vector2((i % cols) * cw, (i / cols) * 30)
		cell.size = Vector2(cw - 8, 28)
		cell.clip_text = true
		wrap.add_child(cell)
	var done: Array = Meta.axes_maxed_count(def.id, is_tower)
	var hint := UI.label(tr("BESTIARY_GOTO_UPGRADE") if not overlay
		else tr("BESTIARY_AXES_DONE").format({"done": done[0], "total": done[1]}),
		20, UI.TEXT_DIM)
	hint.position = Vector2(0, rows * 30 + 6); hint.size = Vector2(944, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wrap.add_child(hint)
	return wrap

## 跳去升級介面,而且落到嗰件嘢上面。Flow 帶住個選擇 —— 唔係嘅話玩家
## 落到升級介面仲要自己撳左右翻二十次。
func _goto_upgrade(id: int, is_tower: bool) -> void:
	Flow.upgrade_focus = {"type": "tower" if is_tower else "spell", "id": id}
	Flow.goto(Flow.UPGRADE)

# ===========================================================================
# 怪物頁(原本嘅圖鑑)
# ===========================================================================
func _build_monster_page() -> void:
	var fam: String = GameData.FAMILY_ORDER[fam_idx]
	var famdef: Dictionary = GameData.FAMILIES[fam]
	var any_seen: bool = Meta.family_any_seen(fam)

	# family header
	var nm := UI.title("%s   (%d / %d)" % [
		tr(famdef.name) if any_seen else tr("BESTIARY_UNKNOWN_FAM"),
		fam_idx + 1, GameData.FAMILY_ORDER.size()], 40)
	nm.position = Vector2(140, 216); nm.size = Vector2(800, 56)
	page_root.add_child(nm)

	# portrait strip: 6 slots (lv1-5 + boss)
	var strip := Control.new()
	strip.position = Vector2(30, 300)
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
	hint.position = Vector2(60, 1866); hint.size = Vector2(960, 40)
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
	# 舊圖係 32-96px 嘅程序像素圖,所以呢度硬性整數放大(分數縮放會令同一格
	# 入面每個頭像嘅像素大細唔同)。2026-08-06 之後係 66-189px 嘅手繪圖 ——
	# 整數規則喺度會全部變成 ×1,boss 一張 189px 直接爆出個 140px 高嘅掣。
	# 手繪圖唔怕分數縮放,所以改為「塞入 110px 框」。
	var scale: float = 110.0 / maxf(base.x, base.y)
	# smooth=true:呢兩個位同上面 :168 / :236 一樣係手繪怪物圖,而 110px /
	# 270px 對 66-189px 源圖嚟講唔係整數倍。NEAREST 之下非整數縮放會逐格
	# 食走一行像素,手繪線條起格。UI.tex_rect 自己會按源圖大細揀 filter
	# (>48px 先至 LINEAR),所以剩返嘅程序像素圖唔會受影響。
	var tr := UI.tex_rect(tex, base * scale, true)
	tr.position = Vector2(20 + (110.0 - base.x * scale) * 0.5,
		15 + (110.0 - base.y * scale) * 0.5)
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
	# 620 而唔係 580:第十一輪喺頂加咗三個分頁掣,成頁內容落咗 40px。
	panel.position = Vector2(40, 620)
	# only boss entries carry the extra 首領技能 block, so a fixed height left
	# ~450px of blank plate under every ordinary creature
	panel.size = Vector2(1000, 1030 if boss else 800)

	# big portrait (integer 4x render, detail visible)
	var tex: Texture2D = Assets.monster_boss(fam) if boss else Assets.monster(fam, lvl)
	# 舊圖細,所以硬乘 4x / 2x 就啱。新圖大好多,同一條式會由 176px 變到 750px,
	# 撞穿右邊 x=360 嗰段文字。改為對返舊嗰個渲染尺寸(等級遞進照舊睇得出)。
	var _tsz: Vector2 = tex.get_size()
	# 上限 280:文字由 x=360 開始,頭像由 x=70 起,所以 290 之前都撞唔到。
	# 新圖細節多咗,舊嗰個 176px 睇唔到裝備差異。
	var _target: float = 270.0 if boss else float(GameData.LVL_SIZE[lvl]) * 5.5
	var big := UI.tex_rect(tex, _tsz * (_target / maxf(_tsz.x, _tsz.y)), true)
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

	# 剋制提示。淨係喺有寫過剋制法嘅族出現 —— 一句「用你有嘅嘢打佢」對每一族
	# 都成立,而一條對每一族都成立嘅提示等於冇提示。
	var counter_key := "FAM_%s_COUNTER" % fam.to_upper()
	if tr(counter_key) != counter_key:
		var ct := UI.label(tr("BESTIARY_COUNTER"), 32, UI.ACCENT.lightened(0.15))
		ct.position = Vector2(66, 790 if boss else 600 + 190)
		ct.size = Vector2(880, 44)
		panel.add_child(ct)
		var cbox := Control.new()
		cbox.position = Vector2(66, (842 if boss else 600 + 242))
		cbox.size = Vector2(872, 150)
		cbox.clip_contents = true
		panel.add_child(cbox)
		var cd2 := UI.label(tr(counter_key), 26, Color(0.86, 0.96, 0.86))
		cd2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cd2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cd2.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		cbox.add_child(cd2)
		# 加咗一段就要加返高度,唔係就會有一段字被剪走喺板外面
		panel.size.y += 210
		if boss:
			# boss 頁嘅「首領技能」原本就佔住 790 起嗰段,剋制推落佢下面
			ct.position.y = 1010
			cbox.position.y = 1062

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
