extends Node2D
class_name Fx
## Pooled short-lived visual effect: expanding ring, filled burst, or polyline
## (lightning/beam/chain). Purely cosmetic.
##
## Round-5 art pass: every effect used to be ONE flat shape — a burst was a
## plain translucent disc, a poison cloud was a solid green sticker and
## "lightning" was a smooth 3-segment polyline that read like a chart. They all
## sat a tier below the cel-shaded sprites. Now each kind is layered (core +
## mid + rim), lightning is jagged with a bright inner filament, and clouds are
## built from overlapping lumps so nothing reads as a vector primitive.

enum Kind { RING, BURST, LINE, ORB, SPARK }

var pool: Pool
var kind: int = Kind.RING
var col: Color = Color.WHITE
var _life: float = 0.0
var _dur: float = 0.35
var radius: float = 40.0
var pts: PackedVector2Array
var _jag: PackedVector2Array   # pre-jittered LINE geometry (see _build_jag)
var width: float = 4.0
var _vel: Vector2 = Vector2.ZERO
var _grav: float = 0.0
var diamond: bool = false
var _seed: int = 0

func _reset(p: Pool) -> void:
	_life = 0.0
	pool = p
	_seed = randi()
	queue_redraw()

func ring(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.RING
	radius = r
	col = c
	_dur = dur
	_reset(p)

func burst(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.BURST
	radius = r
	col = c
	_dur = dur
	_reset(p)

func orb(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.ORB
	radius = r
	col = c
	_dur = dur
	_reset(p)

func spark(pos: Vector2, vel: Vector2, r: float, c: Color, dur: float, p: Pool, grav := 340.0, dia := false) -> void:
	global_position = pos
	kind = Kind.SPARK
	radius = r
	col = c
	_vel = vel
	_grav = grav
	diamond = dia
	_dur = dur
	_reset(p)

func line(world_pts: PackedVector2Array, c: Color, w: float, dur: float, p: Pool) -> void:
	global_position = Vector2.ZERO
	kind = Kind.LINE
	pts = world_pts
	col = c
	width = w
	_dur = dur
	_reset(p)
	_build_jag()

## The jagged bolt geometry is FIXED for the life of the effect (that is the
## whole point of the deterministic _j() jitter — it must not boil). It used to
## be rebuilt inside _draw: a fresh PackedVector2Array plus a full subdivision
## pass per bolt PER FRAME, and with every gatling/beam/sniper/lightning tower
## drawing a bolt at 3x that was the busiest allocator in the battle.
func _build_jag() -> void:
	_jag = PackedVector2Array()
	if pts.size() < 2:
		return
	var idx := 0
	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var n := (p1 - p0).orthogonal().normalized()
		var amp: float = minf(p0.distance_to(p1) * 0.16, 26.0)
		_jag.append(p0)
		for k in range(1, 4):
			idx += 1
			_jag.append(p0.lerp(p1, k / 4.0) + n * (_j(idx) - 0.5) * 2.0 * amp)
	_jag.append(pts[pts.size() - 1])

func _process(delta: float) -> void:
	_life += delta
	if _life >= _dur:
		if pool:
			pool.release(self)
		return
	if kind == Kind.SPARK:
		global_position += _vel * delta
		_vel.y += _grav * delta
		_vel *= (1.0 - 2.0 * delta)   # air drag
	queue_redraw()

## Deterministic per-instance jitter so a shape keeps its silhouette across
## frames instead of boiling (randf() every _draw would strobe).
func _j(i: int) -> float:
	var h := (_seed * 73856093) ^ (i * 19349663)
	return float(h & 1023) / 1023.0

func _draw() -> void:
	var f := clampf(_life / _dur, 0.0, 1.0)
	var a := 1.0 - f
	var c := Color(col.r, col.g, col.b, a)
	match kind:
		Kind.RING:
			# shockwave: bright thin leading edge + a soft wide trail behind it
			var rr := radius * (0.35 + f * 1.0)
			draw_arc(Vector2.ZERO, rr * 0.9, 0, TAU, 32,
				Color(col.r, col.g, col.b, a * 0.35), 11.0, true)
			draw_arc(Vector2.ZERO, rr, 0, TAU, 32, c, 5.0, true)
			draw_arc(Vector2.ZERO, rr, 0, TAU, 32,
				Color(1, 1, 1, a * 0.55), 2.0, true)
		Kind.BURST:
			# layered fireball: dark smoke ring, hot body, white core, debris
			var br := radius * (0.42 + f * 0.85)
			draw_circle(Vector2.ZERO, br * 1.06,
				Color(col.r * 0.35, col.g * 0.3, col.b * 0.3, a * 0.42))
			# lumpy body (never a clean disc)
			for i in 5:
				var ang := TAU * i / 5.0 + _j(i) * 0.7
				var d := br * (0.42 + _j(i + 20) * 0.34)
				draw_circle(Vector2(cos(ang), sin(ang)) * d, br * 0.58,
					Color(col.r, col.g, col.b, a * 0.68))
			draw_circle(Vector2.ZERO, br * 0.62, Color(col.r, col.g, col.b, a * 0.95))
			draw_circle(Vector2.ZERO, br * (0.34 - f * 0.24),
				Color(1, 1, 1, a * 0.9))
			draw_arc(Vector2.ZERO, br * 1.1, 0, TAU, 30, c, 3.0, true)
			# thrown debris streaks
			for i in 4:
				var a2 := TAU * i / 4.0 + _j(i + 40) * 1.2
				var v := Vector2(cos(a2), sin(a2))
				draw_line(v * br * 1.05, v * br * (1.15 + f * 0.55),
					Color(col.r, col.g, col.b, a * 0.7), 4.0, true)
		Kind.ORB:
			# gas cloud: overlapping lumps that drift apart, not a flat sticker
			var orr := radius * (0.8 + f * 0.35)
			for i in 5:
				var ang3 := TAU * i / 5.0 + _j(i) * 1.4
				var off := Vector2(cos(ang3), sin(ang3)) * orr * (0.30 + f * 0.22)
				draw_circle(off, orr * (0.46 + _j(i + 9) * 0.2),
					Color(col.r, col.g, col.b, a * 0.42))
			draw_circle(Vector2.ZERO, orr * 0.55,
				Color(col.r, col.g, col.b, a * 0.55))
			draw_circle(Vector2(-orr * 0.18, -orr * 0.2), orr * 0.24,
				Color(1, 1, 1, a * 0.28))
		Kind.SPARK:
			var rr2 := radius * (1.0 - f * 0.5)
			if diamond:
				var p := PackedVector2Array([Vector2(0, -rr2), Vector2(rr2, 0),
					Vector2(0, rr2), Vector2(-rr2, 0)])
				draw_colored_polygon(p, c)
				draw_circle(Vector2(-rr2 * 0.25, -rr2 * 0.25), rr2 * 0.3, Color(1, 1, 1, a * 0.9))
			else:
				draw_circle(Vector2.ZERO, rr2 * 1.25, Color(col.r * 0.4, col.g * 0.3, col.b * 0.3, a * 0.5))
				draw_circle(Vector2.ZERO, rr2, c)
				draw_circle(Vector2(-rr2 * 0.25, -rr2 * 0.25), rr2 * 0.35, Color(1, 1, 1, a * 0.7))
		Kind.LINE:
			# jagged bolt (geometry baked once in _build_jag): glow -> body -> filament
			if _jag.size() >= 2:
				draw_polyline(_jag, Color(col.r, col.g, col.b, a * 0.30),
					width * 2.6 * (1.0 - f * 0.4), true)
				draw_polyline(_jag, c, width * (1.0 - f * 0.4), true)
				draw_polyline(_jag, Color(1, 1, 1, a * 0.75),
					maxf(1.5, width * 0.35), true)
