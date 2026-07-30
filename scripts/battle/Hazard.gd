extends Node2D
class_name Hazard
## Lingering ground area effect: DoT zone (miasma / firewall / scorch), or a
## black-hole that holds + damages. Ground effects skip flying monsters.

enum Kind { DOT, BLACKHOLE }

var battle
var pool: Pool
var alive: bool = false
var kind: int = Kind.DOT
var radius: float
var dps: float
var dur: float
var col: Color
var ground_only: bool
var _tick: float = 0.0
var _t: float = 0.0

func setup(b, pos: Vector2, r: float, dmg: float, duration: float, k: int, c: Color, gonly: bool, p: Pool = null) -> void:
	battle = b
	pool = p
	global_position = pos
	radius = r
	dps = dmg
	dur = duration
	kind = k
	col = c
	ground_only = gonly
	z_index = 5
	_t = 0.0
	_tick = 0.0
	alive = true
	queue_redraw()

func _process(delta: float) -> void:
	if not alive:
		return
	_t += delta
	if _t >= dur:
		alive = false
		if pool:
			pool.release(self)
		else:
			queue_free()
		return
	_tick += delta
	var do_dmg := _tick >= 0.3
	if do_dmg:
		_tick = 0.0
	for m in battle.monsters_in_radius(global_position, radius, not ground_only):
		if ground_only and m.flying:
			continue
		if kind == Kind.BLACKHOLE:
			m.rooted_time = maxf(m.rooted_time, 0.2)
		if do_dmg:
			m.take_hit(dps * 0.3, "magic")
	queue_redraw()

func _draw() -> void:
	# Round 5: this used to be one flat translucent disc + a thin ring, which is
	# what made poison clouds and fire walls read as coloured stickers. Now the
	# area is built from drifting lumps with a bright rim so it reads as gas /
	# flame while still showing its exact radius.
	var a := 0.32 * (1.0 - _t / dur) + 0.1
	draw_circle(Vector2.ZERO, radius, Color(col.r, col.g, col.b, a * 0.28))
	for i in 6:
		var ang := TAU * i / 6.0 + _t * (0.9 if kind == Kind.BLACKHOLE else 0.35)
		var puff := radius * (0.55 + 0.12 * sin(_t * 2.0 + i))
		draw_circle(Vector2(cos(ang), sin(ang)) * puff, radius * 0.34,
			Color(col.r, col.g, col.b, a * 0.5))
	draw_circle(Vector2.ZERO, radius * 0.45, Color(col.r, col.g, col.b, a * 0.45))
	draw_arc(Vector2.ZERO, radius, 0, TAU, 44, Color(col.r, col.g, col.b, a + 0.28), 3.0)
	if kind == Kind.BLACKHOLE:
		# an in-spiralling maw instead of a plain dark dot
		for k in 3:
			var r0 := radius * (0.62 - k * 0.16)
			draw_arc(Vector2.ZERO, r0, _t * 3.0 + k * 2.1, _t * 3.0 + k * 2.1 + 4.4,
				20, Color(0.72, 0.5, 1.0, a + 0.3), 4.0, true)
		draw_circle(Vector2.ZERO, radius * 0.26, Color(0.06, 0.02, 0.1, 0.92))
	else:
		# little rising motes (embers / spores)
		for j in 3:
			var ph := fmod(_t * 0.9 + j * 0.33, 1.0)
			var mx := sin((j * 2.3) + _t) * radius * 0.5
			draw_circle(Vector2(mx, radius * 0.4 - ph * radius * 0.9),
				4.0 * (1.0 - ph), Color(col.r, col.g, col.b, (1.0 - ph) * 0.7))
