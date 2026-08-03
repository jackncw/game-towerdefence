extends Node2D
class_name Projectile
## Pooled projectile. Homing or point-targeted, optional lob arc. On arrival it
## calls battle.on_projectile_hit(self) which reads `payload`.
##
## Round-5 art pass: every ammo type used to be a ~6px coloured dot, so poison /
## magic / holy / ice were the same circle in a different hue, and the lob
## branch threw the per-kind art away entirely (a lobbed cannon ball and a
## lobbed ice shard drew the same plain disc). Now each kind has its own shape
## with a dark rim + a trail, and the lob path draws the SAME body raised on an
## arc with a ground shadow underneath.

var battle
var pool: Pool
var target: Node = null          # Monster
# Monsters are pooled, so `target` can be recycled into a completely different
# monster mid-flight. The serial is captured at launch and re-checked before we
# home on it or damage it.
var target_serial: int = 0
var target_pos: Vector2
var speed: float = 700.0
var homing: bool = true
var lob: bool = false
var col: Color = Color.WHITE
var radius: float = 6.0
var payload: Dictionary = {}
var kind: String = ""
var _t: float = 0.0
var _total_dist: float = 1.0
var _start: Vector2
var _spin: float = 0.0
var alive: bool = false

const RIM := Color(0.09, 0.07, 0.11, 0.85)

func setup(from: Vector2, tgt, tpos: Vector2, sp: float, home: bool, c: Color, r: float, pl: Dictionary, is_lob: bool, b, p: Pool) -> void:
	position = from
	_start = from
	target = tgt
	target_serial = int(tgt.serial) if tgt != null else 0
	target_pos = tpos
	speed = sp
	homing = home
	lob = is_lob
	col = c
	# ammo reads at a distance now: the old radii were ~6px on a 1080-wide map
	radius = r * 1.5
	payload = pl
	kind = pl.get("fx", "")
	battle = b
	pool = p
	_t = 0.0
	_spin = 0.0
	_total_dist = maxf(from.distance_to(tpos), 1.0)
	alive = true
	rotation = 0.0
	queue_redraw()

## The monster this shot was actually aimed at, or null once it died / was
## recycled out from under us.
func live_target():
	if target == null or not is_instance_valid(target):
		return null
	if int(target.serial) != target_serial or not target.alive:
		return null
	return target

func _process(delta: float) -> void:
	if not alive:
		return
	if homing and live_target() != null:
		target_pos = target.global_position
	var to := target_pos - position
	var d := to.length()
	var step := speed * delta
	_spin += delta * 14.0
	if d <= step or d < 6.0:
		# 落點要 snap 返落目標點先引爆。
		#
		# 之前係喺「差一步之內」就地引爆,而一步嘅長度係 speed*delta —— 3x 之下
		# 一步係 1x 嘅三倍,即係炮彈平均喺離目標更遠嘅地方爆。對單體傷害冇分別,
		# 但濺射就有:爆點郁咗幾十 px,邊個喺濺射範圍入面就唔同咗。實測加農砲台
		# T2 喺 3x 少咗 13.5% 傷害,迫擊砲多咗 11.1%(一個少一個多,正正因為
		# 唔係「傷害計錯」而係「爆邊度」跟住幀長浮動)。
		position = target_pos
		_hit()
		return
	position += to / d * step
	rotation = to.angle()
	if lob:
		_t = 1.0 - (position.distance_to(target_pos) / _total_dist)
	# 大部分彈藥喺自己嘅坐標系入面係**唔郁**嘅:飛行同轉向由 node 嘅
	# position / rotation 帶,而嗰兩樣唔需要重畫。真正逐幀變樣嘅得三種 ——
	# 冰(自轉嘅六角碎片)、魔法(反向轉嘅火花)、同拋物線(彈體騎住個弧)。
	if lob or kind == "ice" or kind == "magic":
		queue_redraw()

func _hit() -> void:
	if not alive:
		return
	alive = false
	if battle:
		battle.on_projectile_hit(self)
	if pool:
		pool.release(self)

func _draw() -> void:
	if lob:
		# ground shadow stays at the node origin, the body rides a parabola.
		# The offset is pre-rotated by -rotation so that after the node's own
		# rotation it ends up straight up in world space.
		var arc := sin(clampf(_t, 0.0, 1.0) * PI) * 52.0
		draw_circle(Vector2.ZERO, radius * maxf(0.35, 1.0 - arc / 90.0) * 0.9,
			Color(0, 0, 0, 0.32))
		draw_set_transform(Vector2(0, -arc).rotated(-rotation), 0.0, Vector2.ONE)
		_draw_body(true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	_draw_body(false)

func _draw_body(lobbed: bool) -> void:
	# local space: +X is the travel direction (rotation = velocity angle)
	var r := radius
	match kind:
		"fire":
			for i in 3:
				var tr := 1.0 - i * 0.28
				draw_circle(Vector2(-r * (0.9 + i * 1.25), 0), r * tr * 0.9,
					Color(1, 0.5 - i * 0.12, 0.1, 0.5 - i * 0.14))
			draw_circle(Vector2.ZERO, r * 1.25, RIM)
			draw_circle(Vector2.ZERO, r * 1.05, Color(1, 0.42, 0.12))
			draw_circle(Vector2.ZERO, r * 0.7, Color(1, 0.78, 0.28))
			draw_circle(Vector2(-r * 0.15, -r * 0.2), r * 0.3, Color(1, 1, 0.8))
		"rocket":
			for i in 3:
				draw_circle(Vector2(-r * (1.1 + i * 1.1), 0), r * (0.85 - i * 0.22),
					Color(1, 0.7 - i * 0.2, 0.2, 0.6 - i * 0.16))
			# fuselage with a nose cone and fins
			draw_line(Vector2(-r * 1.3, 0), Vector2(r * 1.1, 0), RIM, r * 1.5, true)
			draw_line(Vector2(-r * 1.2, 0), Vector2(r * 1.0, 0), Color(0.86, 0.87, 0.92), r * 1.0, true)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 1.8, 0),
				Vector2(r * 0.9, -r * 0.55), Vector2(r * 0.9, r * 0.55)]), Color(0.92, 0.28, 0.24))
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 1.3, 0),
				Vector2(-r * 0.5, -r * 0.9), Vector2(-r * 0.3, 0)]), Color(0.72, 0.74, 0.8))
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 1.3, 0),
				Vector2(-r * 0.5, r * 0.9), Vector2(-r * 0.3, 0)]), Color(0.55, 0.57, 0.63))
		"ice":
			# a six-point shard, spinning
			var a0 := _spin if not lobbed else _spin * 0.6
			var pts := PackedVector2Array()
			for i in 6:
				var ang := a0 + TAU * i / 6.0
				var rr: float = r * (1.5 if i % 2 == 0 else 0.62)
				pts.append(Vector2(cos(ang), sin(ang)) * rr)
			draw_colored_polygon(pts, RIM)
			var inner := PackedVector2Array()
			for p in pts:
				inner.append(p * 0.78)
			draw_colored_polygon(inner, col)
			draw_circle(Vector2.ZERO, r * 0.42, Color(0.94, 0.99, 1.0))
		"poison":
			# lumpy blob + drips, never a clean circle
			draw_circle(Vector2.ZERO, r * 1.3, RIM)
			draw_circle(Vector2.ZERO, r * 1.1, col)
			draw_circle(Vector2(-r * 0.75, r * 0.5), r * 0.6, col)
			draw_circle(Vector2(r * 0.5, -r * 0.6), r * 0.5, col)
			draw_circle(Vector2(-r * 0.4, -r * 0.35), r * 0.42, col.lightened(0.45))
			draw_circle(Vector2(-r * 1.7, r * 0.2), r * 0.35, Color(col.r, col.g, col.b, 0.5))
		"magic":
			# runic diamond with a counter-rotating spark
			draw_circle(Vector2.ZERO, r * 1.5, Color(col.r, col.g, col.b, 0.22))
			var d := PackedVector2Array([Vector2(r * 1.5, 0), Vector2(0, r * 1.0),
				Vector2(-r * 1.5, 0), Vector2(0, -r * 1.0)])
			draw_colored_polygon(d, RIM)
			var d2 := PackedVector2Array()
			for p in d:
				d2.append(p * 0.74)
			draw_colored_polygon(d2, col)
			draw_circle(Vector2.ZERO, r * 0.35, Color(1, 1, 1, 0.9))
			for i in 2:
				var ang2 := _spin * 2.0 + PI * i
				draw_circle(Vector2(cos(ang2), sin(ang2)) * r * 1.7, r * 0.28,
					Color(col.r, col.g, col.b, 0.8))
		"holy":
			# a four-point star / cross flare
			draw_circle(Vector2.ZERO, r * 1.6, Color(col.r, col.g, col.b, 0.25))
			for w in [Vector2(r * 2.0, 0), Vector2(0, r * 1.2)]:
				draw_line(-w, w, RIM, r * 0.85, true)
			for w2 in [Vector2(r * 1.9, 0), Vector2(0, r * 1.1)]:
				draw_line(-w2, w2, col, r * 0.5, true)
			draw_circle(Vector2.ZERO, r * 0.65, Color(1, 1, 0.92))
		"cannon":
			draw_line(Vector2(-r * 2.0, 0), Vector2.ZERO, Color(0.35, 0.33, 0.38, 0.45), r * 1.3, true)
			draw_circle(Vector2.ZERO, r * 1.15, RIM)
			draw_circle(Vector2.ZERO, r * 0.95, Color(0.24, 0.24, 0.28))
			draw_circle(Vector2(-r * 0.28, -r * 0.3), r * 0.36, Color(0.62, 0.62, 0.68))
		_:
			# arrow / bolt: a real shaft with a head and fletching
			draw_line(Vector2(-r * 3.6, 0), Vector2(-r * 1.4, 0),
				Color(col.r, col.g, col.b, 0.35), r * 0.7, true)
			draw_line(Vector2(-r * 1.8, 0), Vector2(r * 0.9, 0), RIM, r * 0.95, true)
			draw_line(Vector2(-r * 1.7, 0), Vector2(r * 0.8, 0), col, r * 0.55, true)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 1.9, 0),
				Vector2(r * 0.5, -r * 0.75), Vector2(r * 0.5, r * 0.75)]), RIM)
			draw_colored_polygon(PackedVector2Array([Vector2(r * 1.65, 0),
				Vector2(r * 0.65, -r * 0.55), Vector2(r * 0.65, r * 0.55)]),
				col.lightened(0.45))
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 1.8, 0),
				Vector2(-r * 1.0, -r * 0.7), Vector2(-r * 0.8, 0)]), Color(0.9, 0.9, 0.94, 0.9))
			draw_colored_polygon(PackedVector2Array([Vector2(-r * 1.8, 0),
				Vector2(-r * 1.0, r * 0.7), Vector2(-r * 0.8, 0)]), Color(0.72, 0.72, 0.78, 0.9))
