extends Node2D
class_name Soldier
## Melee blocker (barracks tower + summon militia spell). Stands on the route,
## roots and fights the nearest ground monster.
##
## The two sources look DIFFERENT on purpose. They used to share one sprite and
## were indistinguishable mid-fight, which hides the thing the player most needs
## to know: a barracks soldier is permanent and respawns, a summoned militia is
## on a 20-second clock. `is_magic` switches both the sprite (a hooded, legless
## robe instead of an armoured trooper) and the effects below.

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
## 要塞營地 (兵營 T2)「陣型」:兩個以上士兵企埋一齊,各自加甲加傷。
var formation: bool = false
## 聖殿騎士團 (兵營 T3)「不屈」:陣亡時原地爆一下,範圍傷害兼擊退。0 = 冇。
var death_blast: float = 0.0
## 召喚聖騎 (召喚 T2):首次致命傷免疫一次。
var shielded: bool = false
## 英靈殿軍 (召喚 T3):陣亡時把剩餘時間分畀其餘同袍。
var share_life: bool = false

## Magic body: half-transparent, runes, a summoning circle, and a warning
## flicker before it expires.
var is_magic: bool = false
var _age: float = 0.0
const SUMMON_TIME := 0.4      # magic circle grows + body fades in
const FADE_WARN := 2.0        # flicker starts this long before expiry
const FADE_HZ := 6.0
const BODY_ALPHA := 0.82
const MAGIC_COL := Color(0.62, 0.86, 1.0)

func setup(b, r: PathRoute, dist_pos: float, hpv: float, dmgv: float, arm: float,
		pool_ref: Pool, tower = null, magic := false) -> void:
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
	is_magic = magic
	_age = 0.0
	formation = false
	death_blast = 0.0
	shielded = false
	share_life = false
	z_index = 18
	queue_redraw()

## 陣型加成:附近有幾多個同袍。逐幀問一次 owner_tower 嘅名單而唔係全場掃 ——
## 一個兵營最多幾個兵,而「陣型」講嘅本來就係同一個兵營嘅隊形。
func _formation_allies() -> int:
	if not formation or owner_tower == null or not is_instance_valid(owner_tower):
		return 0
	var n := 0
	for sd in owner_tower.soldiers:
		if sd != self and is_instance_valid(sd) and sd.alive \
				and sd.global_position.distance_to(global_position) <= GameData.FORMATION_RADIUS:
			n += 1
	return n

func _process(delta: float) -> void:
	if not alive:
		return
	_age += delta
	if life_time > 0.0:
		life_time -= delta
		if life_time <= 0.0:
			_die()
			return
	var m = battle.nearest_ground_monster_near(global_position, block_radius)
	if m != null and m.is_alive():
		m.rooted_time = maxf(m.rooted_time, 0.2)
		var allies := _formation_allies()
		var eff_armor: float = armor * (1.0 + GameData.FORMATION_ARMOR * allies)
		var eff_dmg: float = dmg * (1.0 + GameData.FORMATION_DMG * allies)
		# monster fights back
		var mdps: float = (40.0 if m.is_boss else (5.0 + m.lvl * 3.0))
		hp -= maxf(1.0, mdps - eff_armor * 2.0) * delta
		_cd -= delta
		if _cd <= 0.0:
			_cd = 1.0 / rate
			m.take_hit(eff_dmg, "phys")
		if hp <= 0.0:
			# 召喚聖騎 (召喚 T2):第一次致命傷擋得住,而且要睇得出佢擋咗
			if shielded:
				shielded = false
				hp = max_hp * 0.35
				battle.spawn_fx_ring(global_position, 52, Color(0.9, 0.95, 1.0))
			else:
				_die()
				return
	# 一個普通士兵畫出嚟嘅嘢係「一張圖 + 一條血條」,兩樣都唔會逐幀變 ——
	# 郁位係 node transform 帶,唔使重畫。所以淨係血量真係郁咗先重畫。
	# 魔法民兵唔同:佢有一個逐幀轉嘅符文圈同閃緊嘅身,嗰個真正需要逐幀。
	if is_magic or absf(hp - _drawn_hp) > 0.01:
		_drawn_hp = hp
		queue_redraw()

var _drawn_hp: float = -1.0

func _die() -> void:
	alive = false
	# 聖殿騎士團 (兵營 T3)「不屈」:倒下嗰下唔係白死
	if death_blast > 0.0 and battle != null:
		for m in battle.monsters_in_radius(global_position, GameData.TEMPLAR_BLAST_RADIUS, false):
			m.take_hit(death_blast, "phys")
			m.displace(60.0, false)
		battle.spawn_fx_burst(global_position, GameData.TEMPLAR_BLAST_RADIUS,
			Color(1, 0.9, 0.6), 0.35)
	# 英靈殿軍 (召喚 T3):剩返嘅時間分畀其他仲喺度嘅同袍。要有時間先分得 ——
	# 一個因為打死咗而唔係到鐘先死嘅民兵,佢嗰份時間係真係剩返嘅。
	if share_life and life_time > 0.0 and battle != null:
		var mates: Array = []
		for n in get_parent().get_children():
			if n != self and n is Soldier and n.alive and n.share_life:
				mates.append(n)
		if not mates.is_empty():
			var each: float = life_time / float(mates.size())
			for n in mates:
				n.life_time += each
	if is_magic and battle != null:
		# a summon leaves as it arrived, so an expiry is never a silent vanish
		battle.spawn_fx_ring(global_position, 46, MAGIC_COL)
	if owner_tower and owner_tower.has_method("on_soldier_died"):
		owner_tower.on_soldier_died(self)
	if pool:
		pool.release(self)

func _draw() -> void:
	if is_magic:
		_draw_magic()
	else:
		_draw_body(Assets.soldier(), 1.0)
	_draw_hp_bar()

func _draw_body(tex: Texture2D, alpha: float) -> void:
	var sz: Vector2 = tex.get_size() * GameData.SOLDIER_RENDER
	draw_texture_rect(tex, Rect2(-sz * 0.5, sz), false,
		Color(1, 1, 1, alpha) if alpha < 1.0 else Color.WHITE)

func _draw_hp_bar() -> void:
	var tex := Assets.militia() if is_magic else Assets.soldier()
	var sz: Vector2 = tex.get_size() * GameData.SOLDIER_RENDER
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	var w: float = 24.0 * GameData.SOLDIER_RENDER
	var y: float = -sz.y * 0.5 - 6.0
	draw_rect(Rect2(-w * 0.5, y, w, 4), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(-w * 0.5, y, w * frac, 4),
		MAGIC_COL if is_magic else Color(0.4, 0.8, 1.0))

func _draw_magic() -> void:
	var tex := Assets.militia()
	var sz: Vector2 = tex.get_size() * GameData.SOLDIER_RENDER
	var foot: float = sz.y * 0.5
	# --- summoning circle: snaps up in SUMMON_TIME, then idles as a faint disc
	var grow: float = clampf(_age / SUMMON_TIME, 0.0, 1.0)
	var spin: float = _age * (6.0 if grow < 1.0 else 0.8)
	var ring_r: float = sz.x * 0.44 * (0.15 + 0.85 * grow)
	var ring_a: float = 0.9 if grow < 1.0 else 0.34
	_draw_rune_circle(Vector2(0, foot - 2.0), ring_r, spin, ring_a)

	# --- body alpha: fade in on arrival, flicker as the clock runs out
	var a: float = BODY_ALPHA * grow
	if life_time > 0.0 and life_time < FADE_WARN:
		# a square wave, not a sine: a smooth pulse reads as ambient shimmer,
		# and the point here is to say "this one is about to leave"
		var on: bool = fmod(_age * FADE_HZ, 1.0) < 0.5
		a *= 1.0 if on else 0.30
	_draw_body(tex, a)

	# --- rune motes orbiting the torso, pulsing out of phase
	for i in 3:
		var ph: float = _age * 2.2 + float(i) * TAU / 3.0
		var p := Vector2(cos(ph) * sz.x * 0.34, -sz.y * 0.10 + sin(ph * 1.7) * sz.y * 0.16)
		var s: float = 1.6 + 1.1 * (0.5 + 0.5 * sin(ph * 2.0))
		draw_circle(p, s, Color(MAGIC_COL.r, MAGIC_COL.g, MAGIC_COL.b, a * 0.9))

## Two rings plus six spokes — enough to read as a rune circle at this size
## without paying for a texture.
func _draw_rune_circle(c: Vector2, r: float, spin: float, alpha: float) -> void:
	if r <= 1.0:
		return
	var col := Color(MAGIC_COL.r, MAGIC_COL.g, MAGIC_COL.b, alpha)
	var dim := Color(MAGIC_COL.r, MAGIC_COL.g, MAGIC_COL.b, alpha * 0.55)
	# Squashed on Y so the circle reads as lying ON the ground in this top-down-ish
	# view. draw_arc would give a true circle standing upright, which floats.
	_ellipse(c, r, r * 0.42, col, 2.0)
	_ellipse(c, r * 0.62, r * 0.26, dim, 1.5)
	for i in 6:
		var a := spin + float(i) * TAU / 6.0
		var d := Vector2(cos(a), sin(a) * 0.42)
		draw_line(c + d * r * 0.62, c + d * r, dim, 2.0)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color, w: float) -> void:
	var pts := PackedVector2Array()
	for i in 21:
		var a := TAU * float(i) / 20.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, col, w)
