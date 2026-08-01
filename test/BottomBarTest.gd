extends Node
## Regression test for the rebuilt battle bottom bar (round 8).
##
## The bar it replaces was two horizontally-scrolling strips. The whole point of
## the rebuild is that NOTHING down there scrolls any more, so the assertions are
## about reachability, not about pixels:
##
##   L 魔法列    every learned spell is on screen at once, ≥88px, no overlaps,
##               and 15 spells lay out as 8 + 7 rather than one long lane
##   D 抽屜      every unlocked tower has a card, all of them fit on screen with
##               the drawer open, and the panel itself never runs off the top
##   O 開關      handle opens, scrim tap closes, and the game keeps running —
##               opening the build menu must not pause the battle
##   P 放置      tap-to-arm still works (two-stage), drag-out places a tower, and
##               dropping back onto the panel cancels instead of building a tower
##               underneath the UI (the panel covers legal build coordinates)
##
## Gestures go through Viewport.push_input in canvas (1080x1920) coordinates so
## the real hit-test → gui_input → card_press/drag/release chain runs, the same
## way test/ScrollTest.gd does it.

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.nav_enabled = false
	_backup_save()
	await _case_spell_layout(3)
	await _case_spell_layout(8)
	await _case_spell_layout(15)
	await _case_drawer_layout()
	await _case_open_close()
	await _case_place()
	await _case_quick_persist()
	await _case_quick_layout()
	await _case_one_gesture()
	_restore_save()
	Meta.load_game()
	print("BOTTOMBAR %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------------------
# L — the spell grid
# ---------------------------------------------------------------------------
func _case_spell_layout(n: int) -> void:
	var b = await _start(n, 4)
	var hud = b.hud
	var tag := "L%d" % n
	_ok("%s 卡數" % tag, hud.spell_cards.size() == n,
		"%d cards for %d spells" % [hud.spell_cards.size(), n])
	var rects: Array = []
	var ys: Dictionary = {}
	for c in hud.spell_cards:
		var r: Rect2 = Rect2(c.btn.position, c.btn.size)
		rects.append(r)
		ys[int(round(r.position.y))] = int(ys.get(int(round(r.position.y)), 0)) + 1
		_ok("%s 觸控目標 %.0fx%.0f" % [tag, r.size.x, r.size.y],
			minf(r.size.x, r.size.y) >= 88.0, "min side %.1f < 88" % minf(r.size.x, r.size.y))
		_ok("%s 喺畫面內 @%.0f,%.0f" % [tag, r.position.x, r.position.y],
			r.position.x >= 0.0 and r.end.x <= 1080.0
			and r.position.y >= 1580.0 and r.end.y <= 1920.0,
			"rect %s escapes the bottom bar" % str(r))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	_ok("%s 冇重疊" % tag, overlaps == 0, "%d overlapping pairs" % overlaps)
	# row shape: <=8 stays on one line, more splits top-heavy (15 -> 8+7)
	var counts: Array = ys.values()
	counts.sort()
	counts.reverse()
	if n <= 8:
		_ok("%s 單行" % tag, counts == [n], "rows %s" % str(counts))
	else:
		_ok("%s 兩行 %d+%d" % [tag, int(ceil(n / 2.0)), n - int(ceil(n / 2.0))],
			counts == [int(ceil(n / 2.0)), n - int(ceil(n / 2.0))], "rows %s" % str(counts))
	await _end(b)

# ---------------------------------------------------------------------------
# D — the tower drawer holds every unlocked tower without scrolling
# ---------------------------------------------------------------------------
func _case_drawer_layout() -> void:
	var b = await _start(1, 20)
	var hud = b.hud
	_ok("D 卡數", hud.build_cards.size() == 20, "%d cards" % hud.build_cards.size())
	_ok("D 面板收埋開場", not hud.drawer.visible, "drawer starts visible")
	_ok("D 遮罩收埋開場", not hud.drawer_scrim.visible, "scrim starts visible")
	# open it instantly (skip the slide) and measure where the cards land
	hud._set_drawer(true)
	hud.drawer.position.y = hud._drawer_shown_y
	await _idle(2)
	var top: float = hud.drawer.position.y
	_ok("D 面板唔會頂穿畫面 (top=%.0f)" % top, top >= 0.0, "panel top %.1f < 0" % top)
	_ok("D 面板唔會冚住魔法列 (bottom=%.0f)" % (top + hud.drawer.size.y),
		top + hud.drawer.size.y <= hud.SPELL_AREA.position.y,
		"panel bottom %.1f overlaps spells at %.1f" % [top + hud.drawer.size.y,
		hud.SPELL_AREA.position.y])
	var off := 0
	for c in hud.build_cards:
		var g: Rect2 = Rect2(c.btn.global_position, c.btn.size)
		if g.position.x < 0.0 or g.end.x > 1080.0 or g.position.y < 0.0 or g.end.y > 1920.0:
			off += 1
	_ok("D 20 張卡全部喺畫面內", off == 0, "%d cards off-screen" % off)
	await _end(b)

# ---------------------------------------------------------------------------
# O — open / close, and the battle keeps running while open
# ---------------------------------------------------------------------------
func _case_open_close() -> void:
	var b = await _start(4, 12)
	var hud = b.hud
	await _tap(hud.more_btn.global_position + hud.more_btn.size * 0.5)
	_ok("O 撳更多掣開面板", hud._drawer_open and hud.drawer.visible, "drawer did not open")
	_ok("O 遮罩出現", hud.drawer_scrim.visible, "scrim hidden while open")
	_ok("O 開面板唔暫停", not _tree.paused, "tree paused while drawer open")
	_ok("O 魔法列唔畀遮罩擋",
		hud.drawer_scrim.size.y <= hud.SPELL_AREA.position.y,
		"scrim reaches %.1f, spells start at %.1f" % [hud.drawer_scrim.size.y,
		hud.SPELL_AREA.position.y])
	await _tap(Vector2(540, 300))          # anywhere outside the panel
	_ok("O 撳面板外收埋", not hud._drawer_open, "drawer stayed open")
	await _tap(hud.more_btn.global_position + hud.more_btn.size * 0.5)
	await _tap(hud.more_btn.global_position + hud.more_btn.size * 0.5)
	_ok("O 再撳更多掣收埋", not hud._drawer_open, "more_btn did not toggle shut")
	await _end(b)

# ---------------------------------------------------------------------------
# P — placement paths out of the drawer
# ---------------------------------------------------------------------------
func _case_place() -> void:
	var b = await _start(1, 20)
	var hud = b.hud
	b.gold = 9999
	var card: Button = hud.build_cards[0].btn
	var tid: int = hud.build_cards[0].id
	var spot := _free_spot(b, hud)
	if spot == Vector2.INF:
		_ok("P 有空地可放", false, "no legal build spot above the drawer")
		await _end(b)
		return

	# --- two-stage: tap the card, drawer gets out of the way, build stays armed
	hud._set_drawer(true)
	hud.drawer.position.y = hud._drawer_shown_y
	await _idle(2)
	await _tap(card.global_position + card.size * 0.5)
	_ok("P 撳卡 arm 建造", b.build_id == tid, "build_id=%d want %d" % [b.build_id, tid])
	_ok("P 撳卡後面板收埋", not hud._drawer_open, "drawer stayed open after a card tap")

	# --- drag out onto the map places the tower and closes the panel
	hud._set_drawer(true)
	hud.drawer.position.y = hud._drawer_shown_y
	await _idle(2)
	var before: int = b.towers.size()
	var gold0: int = b.gold
	await _drag(card.global_position + card.size * 0.5, spot)
	_ok("P 拖出去放到塔", b.towers.size() == before + 1,
		"towers %d -> %d" % [before, b.towers.size()])
	_ok("P 放塔扣金", b.gold < gold0, "gold %d -> %d" % [gold0, b.gold])
	_ok("P 放完面板收埋", not hud._drawer_open, "drawer stayed open after placing")
	_ok("P 面板透明度還原", is_equal_approx(hud.drawer.modulate.a, hud.DRAWER_A_IDLE),
		"alpha %.2f" % hud.drawer.modulate.a)

	# --- drop back onto the panel builds NOTHING (it covers legal coordinates)
	hud._set_drawer(true)
	hud.drawer.position.y = hud._drawer_shown_y
	await _idle(2)
	var n0: int = b.towers.size()
	var g0: int = b.gold
	var inside := _spot_under_drawer(b, hud)
	_ok("P 面板蓋住嘅位本來合法", inside != Vector2.INF,
		"no legal build spot sits under the panel, so this case proves nothing")
	if inside == Vector2.INF:
		await _end(b)
		return
	await _drag(card.global_position + card.size * 0.5, inside)
	_ok("P 放返落面板唔會起塔", b.towers.size() == n0,
		"towers %d -> %d" % [n0, b.towers.size()])
	_ok("P 放返落面板唔扣金", b.gold == g0, "gold %d -> %d" % [g0, b.gold])
	await _end(b)

# ---------------------------------------------------------------------------
# Q — 快捷槽嘅持久化同不變式
# ---------------------------------------------------------------------------
func _case_quick_persist() -> void:
	Meta.reset_save()
	_ok("Q 預設 = 四座初始塔 + 兩個空格",
		Meta.quick_slot_ids() == [1, 2, 5, 13, 0, 0],
		"got %s" % str(Meta.quick_slot_ids()))
	_ok("Q 長度一定係 6", Meta.quick_slot_ids().size() == Meta.QUICK_SLOTS,
		"got %d" % Meta.quick_slot_ids().size())

	# 解鎖新塔自動入第一個空格
	Meta.crystals = 99999
	Meta.unlock_tower(3)
	_ok("Q 新解鎖入第一個空格", int(Meta.quick_slot_ids()[4]) == 3,
		"slots=%s" % str(Meta.quick_slot_ids()))
	Meta.unlock_tower(4)
	_ok("Q 第二個新解鎖入第二個空格", int(Meta.quick_slot_ids()[5]) == 4,
		"slots=%s" % str(Meta.quick_slot_ids()))
	# 滿咗就唔再自動郁 —— 玩家排好嘅嘢唔可以俾一次解鎖打亂
	var before: Array = Meta.quick_slot_ids()
	Meta.unlock_tower(6)
	_ok("Q 六格滿咗之後解鎖唔會自動取代", Meta.quick_slot_ids() == before,
		"%s -> %s" % [str(before), str(Meta.quick_slot_ids())])

	# 指派一座已經喺另一格嘅塔 = 兩格對調,唔會出現兩次
	Meta.set_quick_slot(0, 4)     # 4 本來喺第 5 格
	var s: Array = Meta.quick_slot_ids()
	_ok("Q 指派已在列嘅塔 = 對調", int(s[0]) == 4 and int(s[5]) == 1,
		"slots=%s" % str(s))
	var seen: Dictionary = {}
	var dupes := 0
	for id in s:
		if int(id) > 0:
			if seen.has(int(id)): dupes += 1
			seen[int(id)] = true
	_ok("Q 冇一座塔佔兩格", dupes == 0, "slots=%s" % str(s))

	# 對調
	Meta.swap_quick_slots(0, 1)
	var s2: Array = Meta.quick_slot_ids()
	_ok("Q 對調", int(s2[0]) == int(s[1]) and int(s2[1]) == int(s[0]),
		"%s -> %s" % [str(s), str(s2)])

	# 存檔 round-trip
	Meta.save_game()
	var want: Array = Meta.quick_slot_ids()
	Meta.quick_slots = [0, 0, 0, 0, 0, 0]
	Meta.load_game()
	_ok("Q 重開遊戲保留", Meta.quick_slot_ids() == want,
		"want %s got %s" % [str(want), str(Meta.quick_slot_ids())])

	# 未解鎖 / 唔存在嘅 id 要當空格。呢個唔係防駭,係防「舊存檔」:
	# 一個 round 9 之前嘅存檔冇 quick_slots,而一個玩到一半又 reset 過嘅存檔
	# 可能有一個而家已經唔屬於佢嘅 id。
	Meta.quick_slots = [1, 999, 7, 0, 0, 0]     # 999 唔存在,7 未解鎖
	Meta.save_game()
	Meta.load_game()
	var s3: Array = Meta.quick_slot_ids()
	_ok("Q 唔存在嘅 id 當空格", int(s3[1]) == 0, "slots=%s" % str(s3))
	_ok("Q 未解鎖嘅 id 當空格", int(s3[2]) == 0, "slots=%s" % str(s3))
	_ok("Q 已解鎖嘅照留", int(s3[0]) == 1, "slots=%s" % str(s3))

	# 完全冇 quick_slots 嘅舊存檔要落返預設
	var raw: Dictionary = Meta.to_dict()
	raw.erase("quick_slots")
	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw, "\t"))
	f.close()
	Meta.load_game()
	_ok("Q 舊存檔(冇 quick_slots)落返預設",
		Meta.quick_slot_ids().size() == Meta.QUICK_SLOTS
		and int(Meta.quick_slot_ids()[0]) > 0,
		"got %s" % str(Meta.quick_slot_ids()))

# ---------------------------------------------------------------------------
# Q — 快捷列佈局
# ---------------------------------------------------------------------------
func _case_quick_layout() -> void:
	# 最迫嘅情況:15 個魔法 + 6 個塔槽 + 更多掣同場
	var b = await _start(15, 20)
	var hud = b.hud
	_ok("Q 六格都起咗", hud.quick_cards.size() + _empty_slots(hud) == Meta.QUICK_SLOTS,
		"%d 張卡 + %d 個空格" % [hud.quick_cards.size(), _empty_slots(hud)])
	_ok("Q 有更多掣", hud.more_btn != null, "more_btn is null")
	var rects: Array = []
	for c in hud.quick_cards:
		rects.append(Rect2(c.btn.position, c.btn.size))
	rects.append(Rect2(hud.more_btn.position, hud.more_btn.size))
	for r in rects:
		_ok("Q 觸控目標 %.0fx%.0f" % [r.size.x, r.size.y],
			minf(r.size.x, r.size.y) >= 88.0,
			"min side %.1f < 88" % minf(r.size.x, r.size.y))
		_ok("Q 喺畫面內 @%.0f,%.0f" % [r.position.x, r.position.y],
			r.position.x >= 0.0 and r.end.x <= 1080.0 and r.end.y <= 1920.0,
			"rect %s escapes the screen" % str(r))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	_ok("Q 七格冇重疊", overlaps == 0, "%d overlapping pairs" % overlaps)
	# 快捷列同魔法 grid 唔可以撞 —— 呢個係最迫佈局嘅真正風險
	for r in rects:
		_ok("Q 唔撞魔法列 @%.0f" % r.position.y,
			r.end.y <= hud.SPELL_AREA.position.y,
			"quick cell bottom %.0f overlaps spells at %.0f"
			% [r.end.y, hud.SPELL_AREA.position.y])
	for c in hud.spell_cards:
		_ok("Q 魔法卡唔撞快捷列",
			c.btn.position.y >= UI.QUICK_RECT.end.y,
			"spell top %.0f is above quick row bottom %.0f"
			% [c.btn.position.y, UI.QUICK_RECT.end.y])
	await _end(b)

func _empty_slots(hud) -> int:
	var n := 0
	for id in Meta.quick_slot_ids():
		if int(id) == 0:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Q — 一個手勢起塔
# ---------------------------------------------------------------------------
func _case_one_gesture() -> void:
	# 20 座全解鎖,但快捷列維持預設 [1,2,5,13,0,0] —— 即係「四張卡 + 兩個空格」
	# 呢個開局形狀,同時保證嗰四個 id 真係解鎖咗
	var b = await _start(4, 20)
	var hud = b.hud
	b.gold = 9999
	_ok("Q 預設四張快捷卡", hud.quick_cards.size() == 4,
		"%d cards, slots=%s" % [hud.quick_cards.size(), str(Meta.quick_slot_ids())])
	var spot := _free_spot(b, hud)
	if spot == Vector2.INF:
		_ok("Q 有空地可放", false, "no legal build spot")
		await _end(b)
		return
	var card: Button = hud.quick_cards[0].btn
	var tid: int = hud.quick_cards[0].id
	var before: int = b.towers.size()
	var gold0: int = b.gold
	# 呢個就係成個 task 嘅重點:由快捷槽按住 -> 拖 -> 放手,一個手勢,
	# 全程唔使開抽屜。_drawer_open 同 drawer.visible 呢兩個係手勢完咗之後先至
	# 睇嘅終態,而終態呢兩個字段係唔可靠嘅 —— release 路徑本身就會叫
	# _set_drawer(false),所以就算中途開咗抽屜,_drawer_open 都會喺手勢完結之前
	# 變返 false;drawer.visible 就要等 DRAWER_SLIDE(0.16s 真實時間)嘅 tween
	# callback 先至變返 false,而 _end() 淨係等 2 個 process frame,所以呢個
	# assertion 其實係同個 timer 賽跑,唔係真係測緊件事。真正可靠嘅檢查要喺
	# 拖緊嘅過程入面驗:_drag() 每一步之後都攞一次 _drawer_open。
	# GDScript lambdas capture outer locals BY VALUE, so a plain `var opened_mid_drag
	# := false` mutated inside the callback would silently never update the copy
	# read below — wrap it in a single-element Array so the lambda mutates the same
	# backing storage the outer scope reads afterwards.
	var opened_mid_drag := [false]
	await _drag(card.global_position + card.size * 0.5, spot,
		func(): opened_mid_drag[0] = opened_mid_drag[0] or hud._drawer_open)
	_ok("Q 拖緊途中都冇開抽屜", not opened_mid_drag[0], "drawer was open during at least one drag step")
	_ok("Q 一手勢起到塔", b.towers.size() == before + 1,
		"towers %d -> %d" % [before, b.towers.size()])
	_ok("Q 起到嘅係嗰座塔",
		b.towers.size() > before and int(b.towers[b.towers.size() - 1].id) == tid,
		"placed a different tower")
	_ok("Q 有扣金", b.gold < gold0, "gold %d -> %d" % [gold0, b.gold])
	_ok("Q 全程冇開過抽屜", not hud._drawer_open, "drawer opened during the gesture")
	_ok("Q 抽屜真係冇現身", not hud.drawer.visible, "drawer became visible")

	# 空槽撳一下 = 開抽屜
	var empty_btn: Button = _empty_slot_btn(hud)
	_ok("Q 揾到空槽", empty_btn != null, "no empty slot button found")
	if empty_btn != null:
		await _tap(empty_btn.global_position + empty_btn.size * 0.5)
		_ok("Q 撳空槽開抽屜", hud._drawer_open, "drawer did not open")
		await _tap(Vector2(540, 300))
	await _end(b)

## 空槽個掣冇入 quick_cards(佢冇 id),所以按位置揾。
func _empty_slot_btn(hud) -> Button:
	var taken: Dictionary = {}
	for c in hud.quick_cards:
		taken[int(c.slot)] = true
	for i in Meta.QUICK_SLOTS:
		if taken.has(i):
			continue
		var x: float = UI.QUICK_RECT.position.x + i * (UI.quick_cell_w() + UI.QUICK_GAP)
		for ch in hud.get_children():
			if ch is Button and absf(ch.position.x - x) < 1.0 \
					and absf(ch.position.y - UI.QUICK_RECT.position.y) < 1.0:
				return ch
	return null

## First snapped, legal build position that the OPEN drawer does not cover.
func _free_spot(b, hud) -> Vector2:
	return _scan(b, -INF, hud._drawer_shown_y - 60.0)

## The mirror: a legal build position the OPEN drawer DOES cover. Without one of
## these the drop-back case is vacuous — it would "pass" simply because the drop
## point was out of bounds anyway.
func _spot_under_drawer(b, hud) -> Vector2:
	var top: float = hud.drawer.position.y + 40.0
	return _scan(b, top, hud.drawer.position.y + hud.drawer.size.y - 40.0)

func _scan(b, lo: float, hi: float) -> Vector2:
	for gy in range(3, 21):
		for gx in range(1, 15):
			var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
			if p.y > lo and p.y < hi and b.can_place(p):
				return p
	return Vector2.INF

# ===========================================================================
# assertions + harness
# ===========================================================================
func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("BOTTOMBAR ok   %s" % label)
	else:
		fails += 1
		print("BOTTOMBAR FAIL %s — %s" % [label, detail])

## Boot a battle with exactly `spells` spells and `towers` towers unlocked, so
## the layout cases can drive the grid into each of its shapes.
func _start(spells: int, towers: int):
	Meta.reset_save()
	Meta.unlocked_spells = []
	for i in range(1, spells + 1):
		Meta.unlocked_spells.append(i)
	Meta.unlocked_towers = []
	for i in range(1, towers + 1):
		Meta.unlocked_towers.append(i)
	# 直接寫 unlocked_towers 繞過咗 unlock_tower() 嘅自動填充同載入時嘅清洗,
	# 所以要自己洗一次 —— 唔係就會出現「快捷列有張卡指住一座你未解鎖嘅塔」
	Meta._sanitize_quick_slots()
	Flow.selected_level = 1
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await _idle(3)
	return b

func _end(b) -> void:
	b.queue_free()
	await _idle(2)

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## Gestures are pushed as MOUSE events, not ScreenTouch, and that is deliberate.
## On a device `emulate_mouse_from_touch` (on by default) turns a finger into
## exactly this stream before it reaches gui_input, which is why the shipped card
## handlers read InputEventMouseButton/Motion. Viewport.push_input does NOT run
## that emulation, so pushing ScreenTouch here would deliver events no gui_input
## handler in this game has ever seen on a real phone — the test would be
## exercising a path that does not exist.
func _press(pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e, true)

func _tap(pos: Vector2) -> void:
	_press(pos, true)
	await _idle(1)
	_press(pos, false)
	await _idle(2)

## Press on `from`, move to `to` in steps big enough to pass Battle's tap/drag
## threshold, release on `to`.
## `on_step`, if given, is invoked after every motion step (mid-drag, before the
## release) — the only point in this helper where the caller can observe state
## while the gesture is still in flight, rather than at its final rest state.
func _drag(from: Vector2, to: Vector2, on_step: Callable = func(): pass) -> void:
	_press(from, true)
	await _idle(1)
	var steps := 6
	var p := from
	for i in range(1, steps + 1):
		var np: Vector2 = from.lerp(to, float(i) / steps)
		var d := InputEventMouseMotion.new()
		d.button_mask = MOUSE_BUTTON_MASK_LEFT
		d.position = np
		d.global_position = np
		d.relative = np - p
		get_viewport().push_input(d, true)
		p = np
		await _idle(1)
		on_step.call()
	_press(to, false)
	await _idle(2)

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
