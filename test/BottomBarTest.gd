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
	await _tap(hud.HANDLE_RECT.position + hud.HANDLE_RECT.size * 0.5)
	_ok("O 撳把手開面板", hud._drawer_open and hud.drawer.visible, "drawer did not open")
	_ok("O 遮罩出現", hud.drawer_scrim.visible, "scrim hidden while open")
	_ok("O 開面板唔暫停", not _tree.paused, "tree paused while drawer open")
	_ok("O 魔法列唔畀遮罩擋",
		hud.drawer_scrim.size.y <= hud.SPELL_AREA.position.y,
		"scrim reaches %.1f, spells start at %.1f" % [hud.drawer_scrim.size.y,
		hud.SPELL_AREA.position.y])
	await _tap(Vector2(540, 300))          # anywhere outside the panel
	_ok("O 撳面板外收埋", not hud._drawer_open, "drawer stayed open")
	await _tap(hud.HANDLE_RECT.position + hud.HANDLE_RECT.size * 0.5)
	await _tap(hud.HANDLE_RECT.position + hud.HANDLE_RECT.size * 0.5)
	_ok("O 再撳把手收埋", not hud._drawer_open, "handle did not toggle shut")
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
func _drag(from: Vector2, to: Vector2) -> void:
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
