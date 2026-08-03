extends Node2D
class_name Hazard
## Lingering ground area effect: DoT zone (miasma / firewall / scorch), or a
## black-hole that holds + damages. Ground effects skip flying monsters.

## SLOW = 一片淨係拖慢唔傷人嘅地(永凍紀元嘅冰原)。
enum Kind { DOT, BLACKHOLE, SLOW }

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
## 額外掛喺呢片地上面嘅嘢:治療減免(劇毒瘴氣)、削甲(腐蝕之霧)、
## 減速(冰原)、死亡播種(瘟疫爆發)、傷害遞增(奇點)。
## 一個 Dictionary 而唔係五個欄位:呢啲全部都係「某一階先有」嘅東西,
## 而 Hazard 係 pooled —— 五個欄位就係五個每次 setup 都要記得 reset 嘅位。
var extra: Dictionary = {}
var _ramp: float = 0.0

func setup(b, pos: Vector2, r: float, dmg: float, duration: float, k: int, c: Color, gonly: bool, p: Pool = null, ex := {}) -> void:
	battle = b
	pool = p
	global_position = pos
	radius = r
	dps = dmg
	dur = duration
	kind = k
	col = c
	ground_only = gonly
	extra = ex
	_ramp = 0.0
	_seeds = 3
	_absorbed = 0.0
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
		# 事件視界 (黑洞 T3):收場嗰下內爆,把吸咗嘅嘢還一次
		if extra.has("implode"):
			var boom: float = _absorbed * float(extra.implode)
			if boom > 0.0:
				for m in battle.monsters_in_radius(global_position, radius * 1.3, true):
					m.take_hit(boom, "magic")
				battle.spawn_fx_burst(global_position, radius * 1.3, Color(0.6, 0.3, 0.95), 0.5)
				battle.shake(9.0, 0.3)
		alive = false
		if pool:
			pool.release(self)
		else:
			queue_free()
		return
	# 煉獄之牆 (烈焰之牆 T2):火牆沿住路面向前推
	if extra.has("advance"):
		var d2: float = battle.route.nearest_dist_param(global_position) \
			+ float(extra.advance) * delta
		global_position = battle.route.pos_at(clampf(d2, 0.0, battle.route.total - 10.0))
	_tick += delta
	var do_dmg := _tick >= 0.3
	if do_dmg:
		_tick = 0.0
	# 奇點 (黑洞 T2):被困住嘅嘢受到嘅傷害逐秒遞增
	var ramp_step: float = float(extra.get("ramp", 0.0))
	if ramp_step > 0.0:
		_ramp += ramp_step * delta
	for m in battle.monsters_in_radius(global_position, radius, not ground_only):
		if ground_only and m.flying:
			continue
		if kind == Kind.BLACKHOLE:
			m.rooted_time = maxf(m.rooted_time, 0.2)
		# 劇毒瘴氣:治療減免。逐幀續期而唔係一次過落一個長 buff ——
		# 行出個霧就應該即刻回得返,而唔係拖住一個佢已經離開咗嘅狀態。
		if extra.has("healcut"):
			m.apply_heal_cut(float(extra.healcut), 0.4)
		# 腐蝕之霧 (劇毒瘴氣 T2):範圍內護甲被蝕
		if extra.has("shred_armor"):
			m.apply_shred(float(extra.shred_armor), 0.0, 0.4)
		if kind == Kind.SLOW or extra.has("slow"):
			m.apply_slow(float(extra.get("slow", 0.25)), 0.4)
		# `dpspct` = 每秒按目標**生命上限**嘅一份。點解要有:怪物血量係指數
		# 成長(第 40 關 1426 倍),而一個固定 dps 喺嗰度等於零。兩份加埋:
		# 固定值令早關嘅細怪即死,百分比令後關嘅大怪一樣痛。
		var pct_dps: float = float(extra.get("dpspct", 0.0)) * m.max_hp
		if do_dmg and (dps > 0.0 or pct_dps > 0.0):
			var was_alive: bool = m.alive
			var tick: float = (dps + pct_dps) * 0.3 * (1.0 + _ramp)
			_absorbed += tick
			m.take_hit(tick, "magic")
			if was_alive and not m.alive:
				# 瘟疫爆發 (劇毒瘴氣 T3):死喺霧入面嘅嘢再生一團細嘅
				if extra.has("seed") and _seeds > 0:
					_seeds -= 1
					battle.spawn_hazard(m.global_position, radius * 0.55, dps * 0.6,
						dur * 0.5, Kind.DOT, col, ground_only)
				# 不熄業火 (烈焰之牆 T3):死喺火裡面就燒得更耐
				if extra.has("feed"):
					dur += float(extra.feed)
	queue_redraw()

## 播種次數上限。冇上限嘅話一場瘟疫可以自己長成滿場 —— 同史萊姆分裂
## 一模一樣嘅炸彈,而嗰單嘢喺 round 6 已經教過一次。
var _seeds: int = 3
## 呢片地一路食落去嘅總傷害 —— 事件視界收場內爆嗰下要還返一部分。
var _absorbed: float = 0.0

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
