extends RefCounted
class_name Spells
## Stateless spell resolver. cast() reads effective stats from Meta and applies
## the effect to the battle. Returns true if cast succeeded (target valid).
##
## Round-5 presentation pass (visual only — no stat, cost or timing changed):
##   * seven spells (summon / midas / timewarp / warcry / barrier / tornado /
##     firewall) previously had NO on-screen performance at all; every spell now
##     shows where it happened and to whom.
##   * the big ones leaned on a full-screen colour wash (meteor 0.28, freeze
##     0.42, emp 0.22) which washed the board out and hid the very thing it was
##     announcing. Washes are now a thin accent (<=0.16) and the impact is
##     carried by world-space rings/bursts/debris instead.

## A layered impact: shockwave ring + fireball + debris. `power` scales it.
static func _impact(battle, pos: Vector2, r: float, c: Color, power := 1.0) -> void:
	battle.spawn_fx_ring(pos, r * 1.25, c.lightened(0.25))
	battle.spawn_fx_burst(pos, r, c, 0.45)
	battle.spawn_fx_burst(pos, r * 0.55, c.lightened(0.5), 0.3)
	battle.spawn_sparks(pos, int(10 * power), c, 260.0 * power, 6.0, 0.65)

## Concentric rings travelling out from a point — used for the全場 spells so
## they read as one event sweeping the map rather than a flat coloured disc.
static func _shockwaves(battle, pos: Vector2, r: float, c: Color, n := 3) -> void:
	for i in n:
		battle.spawn_fx_ring_dur(pos, r * (0.45 + 0.28 * i), c, 0.45 + 0.13 * i)

static func cast(battle, id: int, pos: Vector2) -> bool:
	var s: Dictionary = Meta.spell_stats(id)
	var def: Dictionary = GameData.spell_by_id(id)
	var centre := Vector2(540, 960)
	match def.mech:
		"meteor":
			# the rock itself: a long burning streak in from off-screen
			battle.spawn_line(PackedVector2Array([pos + Vector2(-620, -1180),
				pos + Vector2(-150, -300), pos]), Color(1, 0.72, 0.32), 16, 0.22)
			battle.spawn_line(PackedVector2Array([pos + Vector2(-560, -1120),
				pos]), Color(1, 0.94, 0.7), 6, 0.18)
			_impact(battle, pos, s.radius, Color(1, 0.5, 0.2), 1.8)
			_shockwaves(battle, pos, s.radius * 1.5, Color(1, 0.66, 0.3), 3)
			battle.spawn_sparks(pos, 22, Color(0.5, 0.36, 0.28), 340.0, 7.0, 0.9, 620.0)
			battle.shake(16.0, 0.45)
			battle.flash(Color(1, 0.55, 0.25, 0.14), 0.3)
			for m in battle.monsters_in_radius(pos, s.radius, true):
				m.take_hit(s.dmg, "magic")
		"stormbolt":
			var n := int(s.bolts)
			var list: Array = battle.all_monsters()
			list.shuffle()
			for i in mini(n, list.size()):
				var m = list[i]
				m.take_hit(s.dmg, "magic")
				var mp: Vector2 = m.global_position
				battle.spawn_line(PackedVector2Array([mp + Vector2(randf_range(-60, 60), -900),
					mp + Vector2(randf_range(-40, 40), -400), mp]),
					Color(0.72, 0.9, 1.0), 7, 0.2)
				battle.spawn_fx_burst(mp, 46, Color(0.8, 0.94, 1.0), 0.28)
				battle.spawn_sparks(mp, 5, Color(0.8, 0.94, 1.0), 200.0, 4.0, 0.4)
			battle.flash(Color(0.7, 0.85, 1.0, 0.10), 0.2)
			battle.shake(5.0, 0.2)
		"freezenova":
			# a wave crossing the whole board + one frost bloom per victim, so
			# you can see exactly who got caught (the old flat disc showed none)
			var ice := Color(0.62, 0.9, 1.0)
			_shockwaves(battle, centre, 1500, ice, 3)
			for m in battle.all_monsters():
				m.apply_freeze(s.dur)
				m.apply_slow(s.slowafter, 2.0)
				battle.spawn_fx_burst(m.global_position, 40, ice, 0.4)
				battle.spawn_sparks(m.global_position, 4, Color(0.85, 0.97, 1.0),
					120.0, 5.0, 0.5, 80.0, true)
			battle.flash(Color(0.75, 0.92, 1.0, 0.16), 0.3)
			battle.shake(6.0, 0.25)
		"miasma":
			battle.spawn_hazard(pos, s.radius, s.dps, s.dur, Hazard.Kind.DOT, Color(0.5, 0.9, 0.2), false)
			battle.spawn_fx_burst(pos, s.radius * 0.8, Color(0.5, 0.9, 0.2), 0.5)
			battle.spawn_sparks(pos, 10, Color(0.62, 0.95, 0.3), 130.0, 6.0, 0.9, -40.0)
		"summon":
			# a rally beacon so the call-to-arms is visible, not just 3 tokens
			var rd: float = battle.route.nearest_dist_param(pos)
			for i in int(s.count):
				var off := randf_range(-45, 45)
				var sp: Vector2 = battle.route.pos_at(clampf(rd + off, 0.0, battle.route.total - 10))
				battle.spawn_line(PackedVector2Array([sp + Vector2(0, -320), sp]),
					Color(0.68, 0.86, 1.0), 8, 0.3)
				battle.spawn_fx_ring(sp, 60, Color(0.6, 0.82, 1.0))
				battle.spawn_sparks(sp, 6, Color(0.75, 0.9, 1.0), 150.0, 5.0, 0.5)
				battle.spawn_soldier(rd + off, s.hp, s.dmg, 2.0, null, 20.0)
		"midas":
			battle.add_gold(int(s.gold))
			battle.spawn_damage(pos, int(s.gold), Color(1, 0.85, 0.2), true)
			# a coin fountain at the cast point and over the base
			battle.spawn_coin_pop(pos, 10)
			battle.spawn_coin_pop(battle.base_pos + Vector2(0, -40), 8)
			battle.spawn_fx_ring(pos, 90, Color(1, 0.85, 0.25))
			if s.killbonus > 0.0:
				battle.midas_bonus = s.killbonus
				battle.midas_time = 10.0
		"timewarp":
			battle.set_enemy_slow(s.slow, s.dur)
			_shockwaves(battle, centre, 1400, Color(0.6, 0.78, 1.0), 2)
			for m in battle.all_monsters():
				battle.spawn_fx_ring(m.global_position, 44, Color(0.62, 0.8, 1.0))
			battle.flash(Color(0.6, 0.75, 1.0, 0.10), 0.35)
		"warcry":
			battle.set_warcry(s.haste, s.dur)
			# every tower flares — the buff is on THEM, so show it on them
			for t in battle.towers:
				if not is_instance_valid(t):
					continue
				battle.spawn_fx_ring(t.global_position, 66, Color(1, 0.78, 0.35))
				battle.spawn_sparks(t.global_position, 5, Color(1, 0.86, 0.45),
					170.0, 5.0, 0.5, 240.0, true)
			_shockwaves(battle, battle.base_pos, 900, Color(1, 0.8, 0.35), 2)
			battle.flash(Color(1, 0.8, 0.4, 0.10), 0.25)
		"barrier":
			battle.base_shield += int(s.block)
			battle.barrier_reflect = s.reflect
			# a shield dome snapping shut over the keep
			for i in 3:
				battle.spawn_fx_ring_dur(battle.base_pos, 230 - i * 60,
					Color(0.55, 0.82, 1.0), 0.5 + i * 0.1)
			battle.spawn_fx_burst(battle.base_pos, 120, Color(0.6, 0.85, 1.0), 0.45)
			battle.spawn_sparks(battle.base_pos, 12, Color(0.7, 0.9, 1.0), 220.0, 6.0, 0.7, -60.0)
		"tornado":
			var list2: Array = battle.monsters_sorted_by_progress()
			var cnt := 0
			for m in list2:
				var p0: Vector2 = m.global_position
				m.displace(s.push)
				# a visible funnel: stacked rings + dust dragged backwards
				for k in 3:
					battle.spawn_fx_ring_dur(p0 + Vector2(0, -k * 26), 34 + k * 16,
						Color(0.78, 0.82, 0.74), 0.4 + k * 0.08)
				battle.spawn_sparks(p0, 6, Color(0.72, 0.68, 0.58), 210.0, 5.0, 0.55, 90.0)
				cnt += 1
				if cnt >= int(s.count):
					break
		"quake":
			for m in battle.all_monsters():
				if m.flying:
					continue
				if m.is_boss:
					m.take_true(s.bossdmg)
				else:
					m.take_true(m.max_hp * s.pct)
				battle.spawn_sparks(m.global_position, 5, Color(0.55, 0.42, 0.3),
					180.0, 5.0, 0.6, 700.0)
			# ground waves rolling out + dust kicked up across the field
			_shockwaves(battle, centre, 1600, Color(0.66, 0.5, 0.34), 3)
			for i in 7:
				var dp := Vector2(randf_range(80, 1000), randf_range(220, 1780))
				battle.spawn_sparks(dp, 6, Color(0.55, 0.42, 0.3), 240.0, 6.0, 0.7, 700.0)
			battle.flash(Color(0.7, 0.5, 0.32, 0.12), 0.3)
			battle.shake(20.0, 0.6)
		"firewall":
			battle.spawn_hazard(pos, s.length * 0.6, s.dps, s.dur, Hazard.Kind.DOT, Color(1, 0.5, 0.2), true)
			# flames erupting along the covered stretch of road
			var rd2: float = battle.route.nearest_dist_param(pos)
			for i in 5:
				var fp: Vector2 = battle.route.pos_at(clampf(
					rd2 + (i - 2) * s.length * 0.22, 0.0, battle.route.total - 10))
				battle.spawn_fx_burst(fp, 54, Color(1, 0.52, 0.18), 0.45)
				battle.spawn_sparks(fp, 6, Color(1, 0.7, 0.25), 200.0, 5.0, 0.7, -120.0)
			battle.shake(5.0, 0.2)
		"smite":
			var m2 = battle.nearest_any(pos, 240.0)
			if m2 == null:
				return false
			var d: float = s.dmg * (1.0 + (s.bossmult if m2.is_boss else 0.0))
			m2.take_hit(d, "magic")
			var tp: Vector2 = m2.global_position
			battle.spawn_line(PackedVector2Array([tp + Vector2(0, -1100),
				tp + Vector2(0, -420), tp]), Color(1, 1, 0.66), 12, 0.28)
			_impact(battle, tp, 84, Color(1, 1, 0.72), 1.2)
			battle.flash(Color(1, 1, 0.75, 0.12), 0.2)
			battle.shake(9.0, 0.3)
		"emp":
			var hit: Array = battle.monsters_in_radius(pos, s.radius, true)
			for m3 in hit:
				m3.apply_stun(s.dur)
				# an arc reaching from the epicentre to each stunned target
				battle.spawn_line(PackedVector2Array([pos, m3.global_position]),
					Color(0.72, 0.48, 1.0), 5, 0.25)
				battle.spawn_fx_ring(m3.global_position, 38, Color(0.7, 0.45, 1.0))
			_impact(battle, pos, s.radius, Color(0.62, 0.32, 0.92), 1.3)
			battle.flash(Color(0.6, 0.35, 0.95, 0.12), 0.22)
		"blackhole":
			battle.spawn_hazard(pos, s.radius, s.dps, s.dur, Hazard.Kind.BLACKHOLE, Color(0.4, 0.2, 0.6), false)
			for i in 3:
				battle.spawn_fx_ring_dur(pos, s.radius * (1.4 - i * 0.3),
					Color(0.55, 0.3, 0.85), 0.5)
			battle.spawn_fx_burst(pos, s.radius * 0.5, Color(0.35, 0.16, 0.55), 0.5)
			battle.shake(6.0, 0.3)
	return true
