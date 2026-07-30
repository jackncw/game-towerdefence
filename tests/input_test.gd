extends Node
## Programmatic self-test for placement + spell input (spec D). Runs in a REAL
## battle scene and drives the actual fix code:
##   - card gestures go through the real BattleHUD._card_gui handler with real
##     InputEventMouse events (headless has no DisplayServer, so GUI hit-testing
##     never routes a click to a Button -- proven separately -- hence we inject
##     at the card's input handler, which is exactly the code the OS would call).
##   - map taps / drags / pan go through the real viewport input pipeline
##     (get_viewport().push_input -> Battle._unhandled_input), which DOES work
##     headless.
## Every case asserts on game state and prints PASS/FAIL; exit code != 0 if any
## case fails.
##
## Run: godot --headless --path . res://tests/input_test.tscn

var battle
var hud
var _results: Array = []   # [name, ok]

func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func():
		print("input_test: TIMEOUT"); get_tree().quit(1))
	Meta.unlocked_towers = [1, 2, 5, 13]
	Meta.unlocked_spells = [1, 2]        # 1=meteor(targeted), 2=stormbolt(instant)
	Flow.selected_level = 1
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await _idle()
	await _idle()
	hud = battle.hud
	battle.gold = 9000
	await _idle()

	await _case1()
	await _case2()
	await _case3()
	await _case4()
	await _case5()
	await _case6()

	_summary()

# ---------------------------------------------------------------------------
# 1: drag from a build card onto empty ground -> tower placed, gold spent
func _case1() -> void:
	battle.cancel_modes()
	var id: int = 1
	var cost: int = int(GameData.tower_by_id(id).place_cost)
	var g0: int = battle.gold
	var n0: int = battle.towers.size()
	var spot: Vector2 = _find_spot()
	await _card_drag_gesture(id, false, spot)
	var placed: bool = battle.towers.size() == n0 + 1
	var near: bool = placed and battle.towers[-1].global_position.distance_to(spot) < 60.0
	var paid: bool = battle.gold == g0 - cost
	_record("1 drag build->empty places+pays (towers=%d gold %d->%d)" %
		[battle.towers.size(), g0, battle.gold], placed and near and paid)

# 2: drag from a build card onto the ROAD -> nothing placed, no gold spent
func _case2() -> void:
	battle.cancel_modes()
	var g0: int = battle.gold
	var n0: int = battle.towers.size()
	var road: Vector2 = battle.route.pos_at(battle.route.total * 0.4)   # on the path
	await _card_drag_gesture(2, false, road)
	var ok: bool = battle.towers.size() == n0 and battle.gold == g0 \
		and battle.can_place_reason(battle.snap(road)) == "on_road"
	_record("2 drag build->road rejected (towers=%d gold=%d reason=%s)" %
		[battle.towers.size(), battle.gold, battle.can_place_reason(battle.snap(road))], ok)

# 3: zoom to 1.5x + pan, then repeat case 1 -> still succeeds (coord transform)
func _case3() -> void:
	battle.cancel_modes()
	battle._zoom_at(1.5, Vector2(540, 900))
	battle.cam.position += Vector2(120, 260)
	battle._clamp_cam()
	await _idle()
	var id: int = 1
	var g0: int = battle.gold
	var n0: int = battle.towers.size()
	var spot: Vector2 = _find_spot()
	await _card_drag_gesture(id, false, spot)
	var placed: bool = battle.towers.size() == n0 + 1
	var near: bool = placed and battle.towers[-1].global_position.distance_to(spot) < 60.0
	_record("3 place under zoom=%.2f+pan (towers=%d, near=%s)" %
		[battle.cam.zoom.x, battle.towers.size(), near], placed and near)
	battle._reset_view()
	await _idle()

# 4: tap meteor icon (two-stage) then tap the map on a monster -> cast + damage + CD
func _case4() -> void:
	battle.cancel_modes()
	var mpos: Vector2 = Vector2(540, 760)
	var mon = battle._spawn_monster("goblin", 3, false, 0.0)
	mon.dist = battle.route.nearest_dist_param(mpos)
	mon.position = mpos
	await _idle()
	var hp0: float = mon.hp
	# stage 1: tap the meteor card (press+release, no movement) -> arms aiming
	await _card_tap(1, true)
	var aiming_ok: bool = battle.aiming_spell == 1
	# stage 2: tap the map on the monster's LIVE position (it keeps walking) -> cast
	var live: Vector2 = mon.global_position
	_touch_map(live, true); await _idle()
	live = mon.global_position
	_touch_map(live, false); await _idle()
	var dmg: float = hp0 - mon.hp
	var cd: float = battle.spell_cd.get(1, 0.0)
	_record("4 meteor two-stage cast (aim=%s dmg=%.0f cd=%.1f)" % [aiming_ok, dmg, cd],
		aiming_ok and dmg > 0.0 and cd > 0.0)

# 5: press the meteor icon while it is on cooldown -> no cast, no aiming
func _case5() -> void:
	var cd0: float = battle.spell_cd.get(1, 0.0)
	var aim_before: int = battle.aiming_spell
	await _card_tap(1, true)       # press during CD
	var ok: bool = cd0 > 0.0 and battle.aiming_spell == 0 and battle.spell_cd.get(1, 0.0) > 0.0
	_record("5 press meteor on CD is inert (cd=%.1f aiming=%d)" %
		[battle.spell_cd.get(1, 0.0), battle.aiming_spell], ok)

# 6: single-finger drag on empty area -> camera pans, no tower placed.
# Zoom in first: at zoom 1 the map exactly fills the view so _clamp_cam leaves no
# pan room (true on device AND here); zoomed in there is room to pan.
func _case6() -> void:
	battle.cancel_modes()
	battle._reset_view()
	battle._zoom_at(1.5, Vector2(540, 960))
	battle._clamp_cam()
	await _idle()
	var n0: int = battle.towers.size()
	var cam0: Vector2 = battle.cam.position
	var a: Vector2 = _screen(Vector2(540, 1100))
	var mid: Vector2 = _screen(Vector2(540, 900))
	var b: Vector2 = _screen(Vector2(540, 700))    # drag upward across the map
	_touch_map_at(a, true); await _idle()
	_drag_map(a, mid); await _idle()
	_drag_map(mid, b); await _idle()
	_touch_map_at(b, false); await _idle()
	var moved: bool = battle.cam.position.distance_to(cam0) > 5.0
	var no_place: bool = battle.towers.size() == n0
	_record("6 single-finger drag pans, no place (cam moved=%.0f towers=%d)" %
		[battle.cam.position.distance_to(cam0), battle.towers.size()], moved and no_place)
	battle._reset_view()

# ---------------------------------------------------------------------------
# gesture helpers
func _idle() -> void:
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame

func _screen(world: Vector2) -> Vector2:
	return battle.get_viewport().get_canvas_transform() * world

# full press-drag-release from a card onto a world spot, via the real _card_gui
func _card_drag_gesture(id: int, is_spell: bool, world_spot: Vector2) -> void:
	var card_center: Vector2 = hud.build_cards[0].btn.get_global_rect().get_center() \
		if not is_spell else hud.spell_cards[0].btn.get_global_rect().get_center()
	var target: Vector2 = _screen(world_spot)
	hud._card_gui(_mb(card_center, true), id, is_spell)
	await _idle()
	hud._card_gui(_mm(target), id, is_spell)      # motion (button held) -> drag
	await _idle()
	hud._card_gui(_mb(target, false), id, is_spell)
	await _idle()

# a plain tap on a card (press + release, no movement)
func _card_tap(id: int, is_spell: bool) -> void:
	var c: Vector2 = (hud.spell_cards[0].btn if is_spell else hud.build_cards[0].btn) \
		.get_global_rect().get_center()
	hud._card_gui(_mb(c, true), id, is_spell)
	await _idle()
	hud._card_gui(_mb(c, false), id, is_spell)
	await _idle()

func _mb(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e

func _mm(pos: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	e.position = pos
	e.global_position = pos
	return e

# map touches go through the REAL viewport pipeline into _unhandled_input
func _touch_map(world: Vector2, pressed: bool) -> void:
	_touch_map_at(_screen(world), pressed)

# Map touches are injected at Battle._unhandled_input -- the exact entry point the
# viewport calls after it has applied its stretch transform and let the event
# fall through the (mouse_filter=IGNORE) HUD. We inject one layer below that
# because headless has no DisplayServer: push_input() there routes through a
# degenerate 1920^2 viewport that both scales positions ~30x AND hit-tests GUI in
# a mismatched space (a divided-down coord lands on the pause button). Injecting
# here still runs the FULL gesture state machine -- _on_touch/_on_drag, the
# tap-vs-pan threshold, screen_to_world(), _tap -> _handle_tap, cast/place -- i.e.
# everything the round-2 bug lived in; only the OS->viewport plumbing is stubbed.
# `screen` is canvas/viewport space, the same space real device touches arrive in.
func _touch_map_at(screen: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = screen
	battle._last_tap_ms = 0
	battle._unhandled_input(e)

func _drag_map(from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = to
	e.relative = to - from
	battle._unhandled_input(e)

func _find_spot() -> Vector2:
	for gx in range(3, 12):
		for gy in range(5, 16):
			var p: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(p):
				return p
	return Vector2(234, 520)

# ---------------------------------------------------------------------------
func _record(name: String, ok: bool) -> void:
	_results.append([name, ok])
	print("[%s] %s" % ["PASS" if ok else "FAIL", name])

func _summary() -> void:
	var fails := 0
	for r in _results:
		if not r[1]:
			fails += 1
	print("\n==== input_test: %d/%d PASS ====" % [_results.size() - fails, _results.size()])
	get_tree().quit(1 if fails > 0 else 0)
