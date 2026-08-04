extends Control
## 快捷列設定 —— 決定戰鬥底欄常駐嗰六格擺邊六座塔。
##
## 呢個畫面喺主選單而唔喺戰鬥入面,有兩個理由。一,戰鬥入面唯一夠位嘅手勢係
## 長按,而長按同「按住拖出去起塔」係同一個開頭,兩者一定會撞。二,揀邊六座塔
## 帶上戰場本來就係開打之前先決定嘅事,唔係打到一半先諗。
##
## 上半部 1:1 畫返戰鬥底欄嗰行(共用 UI.QUICK_RECT / UI.quick_cell_w(),
## 唔係另外抄一套數),落半部係已解鎖嘅塔。撳槽 -> 撳塔 = 指派。

const PREVIEW_Y := 260.0
const GRID_TOP := 470.0
const GRID_COLS := 4
const GRID_CELL := Vector2(232, 168)
const GRID_GAP := 16.0

## -1 = 未揀。入嚟嗰陣冇嘢揀住 —— 預設揀住第 0 格會令玩家撳第一座塔嗰時
## 唔知唔覺改咗一格佢冇打算改嘅嘢。
var selected_slot: int = -1
var _slot_btns: Array = []       # index = slot
var _tower_btns: Dictionary = {} # tower id -> Button
var _preview_root: Control

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title(tr("QUICKBAR_TITLE"), 26, 620, 50))

	var back := UI.button(tr("NAV_BACK"), Vector2(200, 88), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	var hint := UI.label(tr("QUICKBAR_HINT"), 26, UI.TEXT_DIM)
	hint.position = Vector2(60, 180)
	hint.size = Vector2(960, 60)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_build_preview()
	_build_grid()
	_refresh()

## 幾何直接由 UI 攞。呢度嘅重點就係「你見到嘅就係戰鬥入面嗰行」,
## 所以絕對唔可以喺呢度另外定義一套尺寸。
func preview_cell_w() -> float:
	return UI.quick_cell_w()

func _build_preview() -> void:
	var cw: float = preview_cell_w()
	_preview_root = Control.new()
	_preview_root.position = Vector2(UI.QUICK_RECT.position.x, PREVIEW_Y)
	_preview_root.size = Vector2(UI.QUICK_RECT.size.x, UI.QUICK_RECT.size.y)
	add_child(_preview_root)
	_slot_btns.resize(Meta.QUICK_SLOTS)
	for i in Meta.QUICK_SLOTS:
		# 呢六格特登用赤裸 Button.new()(唔用 UI.button):佢哋要保持戰鬥入面
		# 嗰行嘅外觀,由 _refresh() 逐格貼圖。但「唔行 UI.button」順手連
		# UI._click_sound 都冇咗 —— 結果係成個畫面得呢六個主要控制係啞嘅。
		var btn := Button.new()
		UI._click_sound(btn)
		btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
		btn.custom_minimum_size = btn.size
		btn.position = Vector2(i * (cw + UI.QUICK_GAP), 0)
		btn.pressed.connect(_slot_pressed.bind(i))
		_preview_root.add_child(btn)
		_slot_btns[i] = btn
	# 「更多」格畫出嚟係為咗令預覽真係等於實際嗰行 —— 但佢唔係一個可以指派嘅槽
	var more := UI.button(tr("HUD_MORE"), Vector2(cw, UI.QUICK_RECT.size.y), UI.PANEL, 26)
	more.position = Vector2(Meta.QUICK_SLOTS * (cw + UI.QUICK_GAP), 0)
	more.size = Vector2(cw, UI.QUICK_RECT.size.y)
	more.disabled = true
	_preview_root.add_child(more)

func _build_grid() -> void:
	var ids: Array = Meta.unlocked_towers.duplicate()
	ids.sort()
	for k in ids.size():
		var id: int = int(ids[k])
		var btn := UI.button("", GRID_CELL, UI.PANEL_HI, 24)
		btn.position = Vector2(
			60.0 + (k % GRID_COLS) * (GRID_CELL.x + GRID_GAP),
			GRID_TOP + (k / GRID_COLS) * (GRID_CELL.y + GRID_GAP))
		btn.size = GRID_CELL
		btn.pressed.connect(_tower_pressed.bind(id))
		add_child(btn)
		var def := GameData.tower_by_id(id)
		var icon := UI.tex_rect(Assets.tower(id), Vector2(88, 88))
		icon.position = Vector2((GRID_CELL.x - 88.0) * 0.5, 10)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		var nbox := Control.new()
		nbox.position = Vector2(8, 104)
		nbox.size = Vector2(GRID_CELL.x - 16.0, 56)
		nbox.clip_contents = true
		nbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(nbox)
		var nm := UI.label(tr(def.name), 22, UI.TEXT)
		nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nbox.add_child(nm)
		_tower_btns[id] = btn

## 撳一個槽。撳返已經揀住嗰個 = 取消揀;撳另一個槽 = 兩格對調。
##
## 對調做成「撳兩下」而唔係拖曳,係因為呢啲格得 141px 闊,喺電話上拖一個
## 141px 嘅目標去另一個 141px 嘅目標本身就係一個容易撳錯嘅動作,
## 而「撳 A 再撳 B」冇呢個問題,又同下面「撳槽再撳塔」係同一個句法。
func _slot_pressed(i: int) -> void:
	if selected_slot == i:
		selected_slot = -1
	elif selected_slot >= 0:
		Meta.swap_quick_slots(selected_slot, i)
		selected_slot = -1
	else:
		selected_slot = i
	_refresh()

## 撳一座塔。要有一個揀咗嘅槽先有意義 —— 冇揀槽就撳,唔知放邊格,所以乜都唔做。
## 撳返已經喺揀咗嗰格入面嘅塔 = 清空嗰格(即係「取消釘選」,唔使多一個掣)。
##
## 成功指派/清空之後要清返 selected_slot —— 唔係就個槽會繼續揀住,令玩家跟住
## 嗰一撳(佢以為係「揀第二格」)被讀成「同揀住嗰格對調」,一個佢冇叫過嘅動作。
## 冇做嘢嘅早退(冇揀槽 / 塔未解鎖)就唔郁 selected_slot —— 淨係一個真係
## 成功嘅變動先算完咗一個手勢。
func _tower_pressed(id: int) -> void:
	if selected_slot < 0 or selected_slot >= Meta.QUICK_SLOTS:
		return
	if not Meta.is_tower_unlocked(id):
		return
	var cur: int = int(Meta.quick_slot_ids()[selected_slot])
	Meta.set_quick_slot(selected_slot, 0 if cur == id else id)
	selected_slot = -1
	_refresh()

func _refresh() -> void:
	var ids: Array = Meta.quick_slot_ids()
	for i in Meta.QUICK_SLOTS:
		var btn: Button = _slot_btns[i]
		for c in btn.get_children():
			c.queue_free()
		var id: int = int(ids[i])
		var chosen: bool = (i == selected_slot)
		btn.add_theme_stylebox_override("normal",
			UI.frame_box("slot9", 14, 6, 6,
				Color(1.35, 1.25, 0.75) if chosen else Color.WHITE))
		if id > 0:
			var icon := UI.tex_rect(Assets.tower(id), Vector2(60, 60))
			icon.position = Vector2((btn.size.x - 60.0) * 0.5, 4)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(icon)
			var cost := UI.label(str(GameData.place_cost(id, Meta.next_level())), 24, UI.GOLD)
			cost.position = Vector2(0, 68)
			cost.size = Vector2(btn.size.x, 30)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(cost)
		else:
			var plus := UI.label("+", 44, Color(0.55, 0.50, 0.44))
			plus.size = btn.size
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(plus)
	# 已經喺快捷列嘅塔加個星,方便一眼睇晒仲有邊幾座未擺
	for id in _tower_btns:
		var b: Button = _tower_btns[id]
		b.modulate = Color(1.25, 1.2, 0.85) if ids.has(int(id)) else Color.WHITE
