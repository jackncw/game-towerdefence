extends Node2D
class_name Soldier
## Melee blocker (barracks tower + summon militia spell). Stands on the route,
## roots and fights the nearest ground monster.

var battle
var pool: Pool
var owner_tower = null
var max_hp: float
var hp: float
var dmg: float
var rate: float = 1.2
var armor: float = 0.0
var block_radius: float = 48.0
var _cd: float = 0.0
var alive: bool = false
var life_time: float = -1.0   # summon soldiers can be permanent (-1) or timed

func setup(b, r: PathRoute, dist_pos: float, hpv: float, dmgv: float, arm: float, pool_ref: Pool, tower = null) -> void:
	battle = b
	pool = pool_ref
	owner_tower = tower
	max_hp = hpv
	hp = hpv
	dmg = dmgv
	armor = arm
	position = r.pos_at(dist_pos)
	_cd = 0.0
	alive = true
	z_index = 18
	queue_redraw()

func _process(delta: float) -> void:
	if not alive:
		return
	if life_time > 0.0:
		life_time -= delta
		if life_time <= 0.0:
			_die()
			return
	var m = battle.nearest_ground_monster_near(global_position, block_radius)
	if m != null and m.is_alive():
		m.rooted_time = maxf(m.rooted_time, 0.2)
		# monster fights back
		var mdps: float = (40.0 if m.is_boss else (5.0 + m.lvl * 3.0))
		hp -= maxf(1.0, mdps - armor * 2.0) * delta
		_cd -= delta
		if _cd <= 0.0:
			_cd = 1.0 / rate
			m.take_hit(dmg, "phys")
		if hp <= 0.0:
			_die()
			return
	queue_redraw()

func _die() -> void:
	alive = false
	if owner_tower and owner_tower.has_method("on_soldier_died"):
		owner_tower.on_soldier_died(self)
	if pool:
		pool.release(self)

func _draw() -> void:
	var tex := Assets.soldier()
	var sz: Vector2 = tex.get_size() * GameData.SOLDIER_RENDER
	draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false)
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var w: float = 24.0 * GameData.SOLDIER_RENDER
	var y: float = -sz.y * 0.5 - 6.0
	draw_rect(Rect2(-w * 0.5, y, w, 4), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-w * 0.5, y, w * frac, 4), Color(0.4, 0.8, 1.0))
