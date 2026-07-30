extends Node2D
class_name Boomerang
## Out-and-back piercing projectile. Hits every monster along its path once per
## leg. Used by the boomerang tower.

var battle
var pool: Pool
var origin: Vector2
var far: Vector2
var speed: float = 420.0
var dmg: float
var slow: float
var returnmult: float
var col := Color(0.85, 0.7, 0.3)
var _phase: int = 0        # 0 = outward, 1 = return
var _hit: Dictionary = {}
var alive: bool = false

func setup(b, from: Vector2, dir: Vector2, dist: float, dmgv: float, slowv: float, rmult: float, p: Pool) -> void:
	battle = b
	pool = p
	origin = from
	far = from + dir.normalized() * dist
	dmg = dmgv
	slow = slowv
	returnmult = rmult
	position = from
	_phase = 0
	_hit.clear()
	alive = true
	z_index = 22
	queue_redraw()

func _process(delta: float) -> void:
	if not alive:
		return
	rotation += delta * 18.0
	var goal := far if _phase == 0 else origin
	var to := goal - position
	var step := speed * delta
	if to.length() <= step:
		if _phase == 0:
			_phase = 1
			_hit.clear()
		else:
			alive = false
			if pool: pool.release(self)
			return
	else:
		position += to.normalized() * step
	# hit monsters along the way. Keyed on the monster's pool serial, not the node
	# — a node recycled mid-flight is a different monster and must be hittable.
	for m in battle.monsters_in_radius(global_position, 30.0, true):
		var key: int = int(m.serial)
		if not _hit.has(key):
			_hit[key] = true
			var d := dmg * (returnmult if _phase == 1 else 1.0)
			m.take_hit(d, "phys")
			if m.alive and slow > 0.0:
				m.apply_slow(slow, 1.2)
	queue_redraw()

func _draw() -> void:
	draw_line(Vector2(-12, 0), Vector2(12, 0), col, 5, true)
	draw_line(Vector2(0, -12), Vector2(0, 12), col, 5, true)
