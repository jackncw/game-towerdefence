extends RefCounted
class_name PathRoute
## A polyline route with distance parameterisation. Monsters store a scalar
## `dist` along the route; position/tangent derived from it. Enables clean
## push-back / teleport / "closest to base" logic.

var points: PackedVector2Array
var _cum: PackedFloat32Array   # cumulative length at each point
var total: float = 0.0

func _init(pts: PackedVector2Array) -> void:
	points = pts
	_cum = PackedFloat32Array()
	_cum.resize(pts.size())
	_cum[0] = 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
		_cum[i] = total

func pos_at(d: float) -> Vector2:
	d = clampf(d, 0.0, total)
	# binary-ish linear search over segments
	for i in range(1, points.size()):
		if d <= _cum[i]:
			var seg := _cum[i] - _cum[i - 1]
			var t := 0.0 if seg <= 0.0001 else (d - _cum[i - 1]) / seg
			return points[i - 1].lerp(points[i], t)
	return points[points.size() - 1]

func dist_to_route(p: Vector2) -> float:
	## shortest distance from a world point to the polyline
	var best := INF
	for i in range(1, points.size()):
		var d := _seg_dist(p, points[i - 1], points[i])
		if d < best:
			best = d
	return best

func nearest_dist_param(p: Vector2) -> float:
	## returns route-distance of nearest point on route to p (for firewall/thorn placement)
	var best := INF
	var best_d := 0.0
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var ab := b - a
		var l2 := ab.length_squared()
		var t := 0.0 if l2 < 0.0001 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var proj := a + ab * t
		var d := proj.distance_to(p)
		if d < best:
			best = d
			best_d = _cum[i - 1] + ab.length() * t
	return best_d

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# --- templates -------------------------------------------------------------
const FIELD_TOP := 210.0
const FIELD_BOTTOM := 1470.0
const LEFT := 150.0
const RIGHT := 930.0

static func template(idx: int) -> PathRoute:
	var rows := 3 + (idx % 3)             # 3,4,5 sweeps
	var flip := (idx / 3) % 2 == 1        # start side
	var pts := PackedVector2Array()
	var band := (FIELD_BOTTOM - FIELD_TOP) / float(rows)
	for r in rows:
		var y := FIELD_TOP + band * (r + 0.35)
		var left_first := (r % 2 == 0) != flip
		if left_first:
			pts.append(Vector2(LEFT, y))
			pts.append(Vector2(RIGHT, y))
		else:
			pts.append(Vector2(RIGHT, y))
			pts.append(Vector2(LEFT, y))
	# entry from top above first point
	var first := pts[0]
	pts.insert(0, Vector2(first.x, FIELD_TOP - 80.0))
	# exit down to base at bottom centre
	pts.append(Vector2((LEFT + RIGHT) * 0.5, FIELD_BOTTOM + 40.0))
	return PathRoute.new(pts)
