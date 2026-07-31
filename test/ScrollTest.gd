extends Node
## Regression test for the "手機版 升級/商店 拉唔郁" bug.
##
## The bug: every card/button inside those ScrollContainers is MOUSE_FILTER_STOP,
## which ends Godot's pointer propagation at the child, so the container never
## received the touch and its built-in drag scroller never armed. TouchScroll now
## handles the gesture in _input(), ahead of GUI routing.
##
## What is asserted, per screen (升級頁 + 商店頁):
##   1 a touch drag that STARTS ON A BUTTON scrolls the content
##   2 that drag does NOT press the button it started on (誤觸)
##   3 a tap on the same button still presses it
##   4 a drag on empty scroller background scrolls
##   5 a flick keeps scrolling after the finger lifts (慣性), then settles
##   6 a drag outside the scroller does not scroll it
##   7 scrolling is clamped to the content, never past either end
##
## Gestures go through Viewport.push_input in canvas (1080x1920) coordinates with
## in_local_coords=true, so the real hit-test → gui_input → TouchScroll chain runs.
## Headless has no renderer but GUI routing works, which this suite relies on.

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.nav_enabled = false     # a replayed tap must not swap the root scene
	_backup_save()
	# The "a tap still presses" case fires a REAL card handler. With zero 魔晶 the
	# purchase is refused, so `pressed` still proves the click landed while the
	# card list is never rebuilt under the node references this test holds.
	Meta.reset_save()
	Meta.crystals = 0
	await _screen("升級頁", "res://scenes/Upgrade.tscn")
	await _screen("商店頁", "res://scenes/Shop.tscn")
	_restore_save()
	Meta.load_game()
	print("SCROLLTEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

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

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("SCROLLTEST   %s %s" % ["ok  " if ok else "FAIL", what])

func _screen(label: String, path: String) -> void:
	print("SCROLLTEST -- %s (%s)" % [label, path])
	var scene: Control = load(path).instantiate()
	add_child(scene)
	await _idle(2)
	var sc: ScrollContainer = _find(scene, "ScrollContainer")
	if sc == null:
		_check(false, "%s 有 ScrollContainer" % label)
		scene.queue_free()
		return
	var ts := sc.get_node_or_null("TouchScroll")
	_check(ts != null, "%s scroller 掛咗 TouchScroll" % label)
	var max_scroll: float = sc.get_v_scroll_bar().max_value - sc.get_v_scroll_bar().page
	_check(max_scroll > 0.0, "%s 內容長過視窗 (可捲 %d px)" % [label, int(max_scroll)])

	# 升級頁 opens on the showcase/stat zone — its first Button is further down the
	# content, so scroll it into view before using it as the finger target.
	var btn: BaseButton = null
	for offset in range(0, int(max_scroll) + 200, 200):
		sc.scroll_vertical = offset
		await _idle(1)
		btn = _visible_button(sc)
		if btn != null:
			break
	if btn == null:
		_check(false, "%s scroller 內有可見 Button" % label)
		scene.queue_free()
		return
	_check(true, "%s scroller 內搵到可見 Button (%s)" % [label, btn.name])
	btn.disabled = false          # some cards ship disabled (已擁有 / 已滿級)
	var pressed := [0]
	btn.pressed.connect(func(): pressed[0] += 1)
	# every case starts from the offset where that button is on screen, so the
	# finger always lands on it
	var base_off: int = sc.scroll_vertical

	# 1 + 2 — drag from the button scrolls, and does not click it
	await _reset(sc, base_off)
	pressed[0] = 0
	await _drag(btn.get_global_rect().get_center(), Vector2(0, -40), 8)
	await _idle(2)
	_check(sc.scroll_vertical > base_off,
		"%s 由掣上面起手拖得郁 (%d -> %d)" % [label, base_off, sc.scroll_vertical])
	_check(pressed[0] == 0, "%s 拖動途中冇誤觸個掣 (pressed=%d)" % [label, pressed[0]])

	# 3 — a tap on the same button still presses
	await _reset(sc, base_off)
	pressed[0] = 0
	await _drag(btn.get_global_rect().get_center(), Vector2.ZERO, 0)
	await _idle(3)               # the replayed click is deferred
	_check(pressed[0] == 1, "%s 淨係撳唔拖仍然當撳掣 (pressed=%d)" % [label, pressed[0]])
	_check(sc.scroll_vertical == base_off, "%s 純點撳唔會捲動" % label)

	# 4 — drag on empty scroller background
	await _reset(sc, base_off)
	await _drag(sc.get_global_rect().get_center(), Vector2(0, -40), 8)
	await _idle(2)
	_check(sc.scroll_vertical > base_off,
		"%s 空白處拖得郁 (%d -> %d)" % [label, base_off, sc.scroll_vertical])

	if not is_instance_valid(btn):
		_check(false, "%s 個掣喺撳完之後仲喺度(冇被重建)" % label)
		scene.queue_free()
		await _idle(2)
		return

	# 5 — inertia: a flick keeps going after release, then settles
	await _reset(sc, base_off)
	await _drag(btn.get_global_rect().get_center(), Vector2(0, -70), 8, 900.0)
	var at_release: int = sc.scroll_vertical
	await _idle(6)
	var after_coast: int = sc.scroll_vertical
	_check(after_coast > at_release,
		"%s 放手之後仲有慣性 (%d -> %d)" % [label, at_release, after_coast])
	# settle is checked by polling, not by a fixed frame count: headless runs
	# uncapped, so "40 frames" is not a fixed amount of time
	var settled := await _settle(sc)
	_check(settled >= 0, "%s 慣性最終停得低 (停喺 %d)" % [label, settled])

	# 6 — a drag outside the scroller must not move it
	await _reset(sc, base_off)
	var outside := Vector2(sc.get_global_rect().position.x + 500.0,
		maxf(10.0, sc.get_global_rect().position.y - 60.0))
	await _drag(outside, Vector2(0, -40), 8)
	await _idle(2)
	_check(sc.scroll_vertical == base_off,
		"%s scroller 以外嘅拖動唔會捲佢 (scroll_vertical=%d)" % [label, sc.scroll_vertical])

	# 7 — clamped at both ends
	await _reset(sc, base_off)
	await _drag(btn.get_global_rect().get_center(), Vector2(0, 60), 40)  # wrong way, hard
	await _settle(sc)
	_check(sc.scroll_vertical == 0, "%s 頂位唔會捲過頭 (%d)" % [label, sc.scroll_vertical])
	await _drag(sc.get_global_rect().get_center(), Vector2(0, -60), 60)
	await _settle(sc)
	_check(float(sc.scroll_vertical) <= max_scroll + 1.0,
		"%s 底位唔會捲過頭 (%d <= %d)" % [label, sc.scroll_vertical, int(max_scroll)])

	scene.queue_free()
	await _idle(2)

# ---------------------------------------------------------------------------
## One press + n drags + release, pushed through the Viewport in canvas space so
## the real hit-test and propagation run. `speed` feeds InputEventScreenDrag's
## velocity, which is what TouchScroll turns into a fling.
func _drag(from: Vector2, step: Vector2, n: int, speed := 0.0) -> void:
	var vp := get_viewport()
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = from
	vp.push_input(t, true)
	await _idle(1)
	var p := from
	for i in n:
		var d := InputEventScreenDrag.new()
		d.position = p + step
		d.relative = step
		d.velocity = step.normalized() * speed if speed > 0.0 else Vector2.ZERO
		vp.push_input(d, true)
		p += step
		await _idle(1)
	var u := InputEventScreenTouch.new()
	u.pressed = false
	u.position = p
	vp.push_input(u, true)
	await _idle(1)

## Park the scroller at `off` and let any leftover fling die first, so one case
## cannot bleed into the next.
func _reset(sc: ScrollContainer, off: int) -> void:
	await _settle(sc)
	sc.scroll_vertical = off
	await _idle(2)

## Poll until scroll_vertical holds still. Returns the resting offset, or -1 if
## it never stopped (which is the assertion the fling test cares about).
func _settle(sc: ScrollContainer) -> int:
	var last: int = sc.scroll_vertical
	var still := 0
	for i in 2000:
		await _tree.process_frame
		if sc.scroll_vertical == last:
			still += 1
			if still >= 8:
				return last
		else:
			still = 0
			last = sc.scroll_vertical
	return -1

func _idle(frames: int) -> void:
	for i in frames:
		await _tree.process_frame

func _find(n: Node, cls: String) -> Node:
	if n.is_class(cls):
		return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r != null:
			return r
	return null

## A button whose centre sits inside the scroller's visible window — a clipped
## one is not something a finger can land on.
func _visible_button(sc: ScrollContainer) -> BaseButton:
	return _vb(sc, sc.get_global_rect())

func _vb(n: Node, view: Rect2) -> BaseButton:
	if n is BaseButton and n.visible and view.has_point(n.get_global_rect().get_center()):
		return n
	for c in n.get_children():
		var r := _vb(c, view)
		if r != null:
			return r
	return null
