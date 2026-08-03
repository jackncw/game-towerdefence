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

## 命中判定嘅取樣半徑,同每步最長距離。
##
## 命中係「飛到邊,就喺嗰點度個半徑」——即係一串離散取樣,唔係掃掠碰撞。
## 一步嘅長度係 speed*delta:1x 之下 420*0.0167 = 7px,取樣點密到冇嘢漏得到;
## 3x 之下 420*0.05 = 21px,而一隻擦邊嘅怪(中心離飛行線 29px)喺線上只佔
## 大約 15px 嘅窗口 —— 21px 一步就跨得過佢。實測 3x 少咗 24.9% 傷害。
##
## 解法係將移動切成細步,令取樣密度同幀長脫鈎。8px 係「1x 嘅 7px 一步」嘅
## 同級數,所以 3x 之下嘅命中結果同 1x 對得返。
const HIT_R := 30.0
const MAX_STEP := 8.0

func _process(delta: float) -> void:
	if not alive:
		return
	rotation += delta * 18.0
	var remaining: float = speed * delta
	while alive and remaining > 0.0:
		var sub: float = minf(remaining, MAX_STEP)
		remaining -= sub
		var goal := far if _phase == 0 else origin
		var to := goal - position
		if to.length() <= sub:
			position = goal          # 折返點唔可以隨步長浮動
			if _phase == 0:
				_phase = 1
				_hit.clear()
			else:
				alive = false
				if pool: pool.release(self)
				return
		else:
			position += to.normalized() * sub
		_sample_hits()
	queue_redraw()

## hit monsters along the way. Keyed on the monster's pool serial, not the node
## — a node recycled mid-flight is a different monster and must be hittable.
func _sample_hits() -> void:
	for m in battle.monsters_in_radius(global_position, HIT_R, true):
		var key: int = int(m.serial)
		if not _hit.has(key):
			_hit[key] = true
			var d := dmg * (returnmult if _phase == 1 else 1.0)
			m.take_hit(d, "phys")
			if m.alive and slow > 0.0:
				m.apply_slow(slow, 1.2)

func _draw() -> void:
	draw_line(Vector2(-12, 0), Vector2(12, 0), col, 5, true)
	draw_line(Vector2(0, -12), Vector2(0, 12), col, 5, true)
