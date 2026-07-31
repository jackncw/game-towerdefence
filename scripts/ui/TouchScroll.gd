extends Node
class_name TouchScroll
## Finger-drag scrolling for a vertical ScrollContainer that keeps working when
## the finger starts ON a child button or card.
##
## WHY THIS EXISTS — measured, not assumed. Godot routes a pointer event to the
## deepest Control under it and MOUSE_FILTER_STOP (the default for Button and
## Panel) ENDS the propagation there, whether or not that control did anything
## with the event. On the real 商店 screen, a touch drag starting on an unlock
## button delivered `ScreenTouch x2 + ScreenDrag x10` to the Button and ZERO
## events to the ScrollContainer above it, so the container's built-in touch
## scroller never armed. Every card in 升級/商店/選關/畫廊 is a Panel full of
## Buttons, which is why those screens felt frozen on a phone.
##
## Loosening every child to MOUSE_FILTER_PASS restores the routing, but then the
## button still counts the release as a click in the middle of a drag. So the
## gesture is handled here in `_input()` instead, which Viewport calls BEFORE any
## GUI routing:
##   * the initial press is SWALLOWED — no child ever enters a pressed state
##   * once travel passes DRAG_THRESHOLD the gesture is a scroll and stays
##     swallowed all the way to the release, so nothing can be mis-tapped
##   * below the threshold the release replays a real click, so a tap still
##     presses the button under the finger
## Because every pointer event of a scrolling gesture is consumed, Godot's own
## touch scroller cannot double-apply it, and no `mouse_filter` had to change.
##
## Vertical only — every scroller in this game has horizontal scrolling disabled.

## Travel (in 1080x1920 canvas px) that turns a press into a scroll. Matches the
## 12px tap/pan split used by the battle camera, with a little more slack because
## a finger on a card wobbles more than a mouse.
const DRAG_THRESHOLD := 20.0
## Fling deceleration, in scroll-px per second squared.
const FRICTION := 2600.0
## Below this the fling is not worth continuing.
const MIN_FLING := 60.0
## One wheel notch, in scroll px (desktop parity: the wheel is blocked by the
## same MOUSE_FILTER_STOP children, so it is forwarded here too).
const WHEEL_STEP := 140.0

var sc: ScrollContainer

var _down: bool = false          # a gesture is in progress inside our rect
var _scrolling: bool = false     # ...and it has passed DRAG_THRESHOLD
var _src: String = ""            # "touch" | "mouse": the family owning the motion
var _start: Vector2 = Vector2.ZERO
var _travel: float = 0.0         # signed finger travel since press
var _scroll0: float = 0.0        # scroll offset when the press landed
var _pos: float = 0.0            # float scroll offset (scroll_vertical is int)
var _vel: float = 0.0            # px/s, for the fling
var _replaying: bool = false     # guard: our own synthetic click must not re-enter

## Attach a scroller to `scroll`. Safe to add to a ScrollContainer: containers
## only lay out their Control children, and this is a plain Node.
static func attach(scroll: ScrollContainer) -> TouchScroll:
	var t := TouchScroll.new()
	t.name = "TouchScroll"
	t.sc = scroll
	scroll.add_child(t)
	return t

func _ready() -> void:
	set_process_input(true)
	set_process(true)

func _usable() -> bool:
	return sc != null and is_instance_valid(sc) and sc.is_visible_in_tree()

func _max_scroll() -> float:
	var bar := sc.get_v_scroll_bar()
	return maxf(0.0, bar.max_value - bar.page)

func _apply(v: float) -> void:
	_pos = clampf(v, 0.0, _max_scroll())
	sc.scroll_vertical = int(round(_pos))

# ---------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if _replaying or not _usable():
		return
	var rect: Rect2 = sc.get_global_rect()

	# --- desktop wheel: same STOP children swallow it, so forward it ---------
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed and rect.has_point(mb.position) and _max_scroll() > 0.0:
				var dir := -1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
				_vel = 0.0
				_apply(_pos + dir * WHEEL_STEP * maxf(1.0, mb.factor))
				get_viewport().set_input_as_handled()
			return

	# --- press --------------------------------------------------------------
	var down_at: Variant = _press_pos(event, true)
	if down_at != null:
		if _down:
			# the other event family echoing the same physical press
			get_viewport().set_input_as_handled()
			return
		var p: Vector2 = down_at
		if not rect.has_point(p) or _max_scroll() <= 0.0:
			return
		_down = true
		_scrolling = false
		_src = ""
		_start = p
		_travel = 0.0
		_pos = float(sc.scroll_vertical)
		_scroll0 = _pos
		_vel = 0.0
		# Swallow it: nothing under the finger may start a press until we know
		# whether this gesture is a tap or a drag.
		get_viewport().set_input_as_handled()
		return

	if not _down:
		return

	# --- motion -------------------------------------------------------------
	var mv := _motion(event)
	if not mv.is_empty():
		# both families report the same physical motion; obey the first one only
		if _src == "":
			_src = mv.src
		if mv.src != _src:
			get_viewport().set_input_as_handled()
			return
		_travel += float(mv.dy)
		if not _scrolling and absf(_travel) >= DRAG_THRESHOLD:
			_scrolling = true
			# re-base at the crossing point so the content does not jump by the
			# whole threshold distance the moment the drag is recognised
			_travel = 0.0
			_scroll0 = _pos
		if _scrolling:
			_apply(_scroll0 - _travel)
			_vel = -float(mv.vy)
		get_viewport().set_input_as_handled()
		return

	# --- release ------------------------------------------------------------
	var up_at: Variant = _press_pos(event, false)
	if up_at != null:
		var was_scrolling := _scrolling
		_down = false
		_scrolling = false
		_src = ""
		get_viewport().set_input_as_handled()
		if was_scrolling:
			if absf(_vel) < MIN_FLING:
				_vel = 0.0
		else:
			# a tap: the press was swallowed, so hand the control under the
			# finger a real click now
			_vel = 0.0
			_replay_click.call_deferred(up_at)

func _process(delta: float) -> void:
	if not _usable() or _down or absf(_vel) < 1.0:
		return
	_apply(_pos + _vel * delta)
	if _pos <= 0.0 or _pos >= _max_scroll():
		_vel = 0.0
		return
	_vel = move_toward(_vel, 0.0, FRICTION * delta)

# ---------------------------------------------------------------------------
## Position of a pointer press (`want_pressed`) / release, or null if `event` is
## not one. Both the touch and the mouse family count, because
## emulate_mouse_from_touch and emulate_touch_from_mouse are BOTH on, so one
## physical gesture arrives twice.
func _press_pos(event: InputEvent, want_pressed: bool):
	if event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		return st.position if st.pressed == want_pressed else null
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return null
		return mb.position if mb.pressed == want_pressed else null
	return null

## {src, dy, vy} for a pointer motion event, or {} if `event` is not one.
func _motion(event: InputEvent) -> Dictionary:
	if event is InputEventScreenDrag:
		var sd: InputEventScreenDrag = event
		return {"src": "touch", "dy": sd.relative.y, "vy": sd.velocity.y}
	if event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		if not (mm.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return {}
		return {"src": "mouse", "dy": mm.relative.y, "vy": mm.velocity.y}
	return {}

## Replay the click we swallowed, so a tap on a card/button still registers.
## Deferred, so it never re-enters the input handler we are standing in.
func _replay_click(at: Vector2) -> void:
	if not _usable():
		return
	var vp := get_viewport()
	if vp == null:
		return
	_replaying = true
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		e.pressed = pressed
		e.position = at
		e.global_position = at
		vp.push_input(e, true)
	_replaying = false
