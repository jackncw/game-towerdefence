extends Node2D
class_name Tower
## A placed tower. Behaviour dispatched by `mech`. Effective stats are computed
## from Meta upgrade levels at placement time.

var battle
var id: int
var def: Dictionary
var s: Dictionary            # effective stats
var mech: String
var place_cost: int
var sprite: Sprite2D
var range_val: float
var _cd: float = 0.0
var selected: bool = false

# gatling / beam ramp
var last_target = null
var heat: float = 0.0
var beam_ramp: float = 0.0

# barracks
var soldiers: Array = []
var respawn_timer: float = 0.0
var rally_dist: float = 0.0

# damage type per mech
const PHYS := ["arrow", "cannon", "gatling", "sniper", "mortar", "missile", "boomerang", "magnet", "frost"]
const TRUEDMG := ["poison", "thorn"]

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.scale = Vector2(GameData.TOWER_RENDER, GameData.TOWER_RENDER)
	add_child(sprite)
	z_index = 15

func setup(b, tower_id: int, world_pos: Vector2) -> void:
	battle = b
	id = tower_id
	def = GameData.tower_by_id(id)
	mech = def.mech
	place_cost = def.place_cost
	s = Meta.tower_stats(id)
	range_val = s.range
	position = world_pos
	sprite.texture = Assets.tower(id)
	_cd = 0.0
	heat = 0.0
	beam_ramp = 0.0
	if mech == "barracks":
		rally_dist = battle.route.nearest_dist_param(world_pos)
	if mech == "alchemy" and s.get("startgold", 0.0) > 0.0:
		battle.add_gold(int(s.startgold), true)      # 一次過入賬,唔係涓滴收入

func dtype() -> String:
	if mech in TRUEDMG:
		return "true"
	if mech in PHYS:
		return "phys"
	return "magic"

func get_rate() -> float:
	var r: float = s.rate
	r *= (1.0 + battle.holy_haste_at(global_position))
	r *= (1.0 + battle.warcry_haste)
	if mech == "gatling":
		r *= (1.0 + heat)
	return maxf(0.1, r)

func _process(delta: float) -> void:
	_tick_recoil(delta)
	match mech:
		"slowfield": _proc_slowfield(delta)
		"beam": _proc_beam_audio(delta)
		# these three do not route through _fire(), so they play their own sound
		"alchemy": _proc_interval(delta, Callable(self, "_fire_alchemy_snd"), false)
		"thorn": _proc_interval(delta, Callable(self, "_fire_thorn_snd"), false)
		"magnet": _proc_interval(delta, Callable(self, "_fire_magnet_snd"), false)
		"barracks": _proc_barracks(delta)
		"curse": _proc_curse_aura(delta)
		_: _proc_attack(delta)
	if selected:
		queue_redraw()

# generic: needs a target
# MAX_SHOTS_PER_FRAME lets a very fast tower catch up when one frame covers
# several of its intervals. At 5x speed a frame is ~83ms of game time while a
# fully heated 機槍塔 fires every ~28ms, so "fire once, reset the timer to a full
# interval" silently capped it at a third of its advertised 攻速. Accumulating
# the leftover and draining it in a bounded loop delivers the real rate without
# ever letting a stall turn into an unbounded burst.
const MAX_SHOTS_PER_FRAME := 4

func _proc_attack(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	var tgt = _acquire_target()
	if tgt == null:
		if mech == "gatling":
			heat = maxf(0.0, heat - delta)
			last_target = null
		_cd = 0.0
		return
	var shots := 0
	while _cd <= 0.0 and shots < MAX_SHOTS_PER_FRAME:
		_fire(tgt)
		_cd += 1.0 / get_rate()
		shots += 1
		if not (is_instance_valid(tgt) and tgt.alive):
			break
	if _cd < 0.0:
		_cd = 0.0

# interval: fires regardless of target (alchemy/thorn/magnet)
func _proc_interval(delta: float, cb: Callable, _need: bool) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	cb.call()
	_cd = 1.0 / maxf(0.05, s.rate)

func _acquire_target():
	if mech == "sniper":
		return battle.target_highest_hp(global_position, range_val)
	return battle.target_closest_to_base(global_position, range_val)

const MUZZLE_COL := {
	"cannon": Color(1, 0.86, 0.45), "gatling": Color(1, 0.92, 0.55),
	"sniper": Color(1, 0.9, 0.6), "mortar": Color(1, 0.8, 0.4),
	"missile": Color(1, 0.6, 0.4), "fireball": Color(1, 0.55, 0.2),
	"frost": Color(0.7, 0.92, 1), "poison": Color(0.6, 0.95, 0.3),
	"lightning": Color(0.7, 0.9, 1), "curse": Color(0.7, 0.4, 0.9),
	"holy": Color(1, 0.95, 0.7), "arrow": Color(0.9, 1, 0.7),
}

# Recoil kick + muzzle flash toward the target — gives every shot a punch.
# The recoil used to be a Tween allocated per shot; 43 towers firing at 5x speed
# meant hundreds of Tween objects a second for a 0.11s ease. It is a plain
# exponential decay on _recoil now, ticked in _process.
var _recoil: Vector2 = Vector2.ZERO
var _aura_phase: float = 0.0   # 詛咒塔 circle animation

func _tick_recoil(delta: float) -> void:
	if _recoil == Vector2.ZERO:
		return
	_recoil = _recoil.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	if _recoil.length_squared() < 0.04:
		_recoil = Vector2.ZERO
	sprite.position = _recoil

func _muzzle(tgt) -> void:
	if not is_instance_valid(tgt):
		return
	var dir: Vector2 = (tgt.global_position - global_position).normalized()
	_recoil = -dir * 6.0
	sprite.position = _recoil
	var col: Color = MUZZLE_COL.get(mech, Color(1, 0.95, 0.7))
	battle.spawn_sparks(global_position + dir * 26.0, 2, col, 100.0, 3.0, 0.16, 40.0)

# ---------------------------------------------------------------------------
func _fire(tgt) -> void:
	_muzzle(tgt)
	Audio.play_tower(mech)
	match mech:
		"arrow": _fire_arrow(tgt)
		"cannon": _fire_cannon(tgt)
		"lightning": _fire_lightning(tgt)
		"fireball": _fire_fireball(tgt)
		"frost": _fire_frost(tgt)
		"poison": _fire_poison(tgt)
		"sniper": _fire_sniper(tgt)
		"gatling": _fire_gatling(tgt)
		"mortar": _fire_mortar(tgt)
		"missile": _fire_missile(tgt)
		"holy": _fire_holy(tgt)
		"teleport": _fire_teleport(tgt)
		"boomerang": _fire_boomerang(tgt)

func _roll(p: float) -> bool:
	return randf() < p

func _crit_dmg(base: float, chance: float, mult: float) -> Array:
	if _roll(chance):
		return [base * mult, true]
	return [base, false]

func _fire_arrow(tgt) -> void:
	var res := _crit_dmg(s.dmg, s.crit, s.critmult)
	var pl := {"type": "phys", "dmg": res[0], "fx": "arrow"}
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 900, true, Color(1, 1, 0.6), 5, pl, false)
	if _roll(s.double):
		battle.spawn_projectile(global_position, tgt, tgt.global_position, 900, true, Color(1, 1, 0.6), 5, {"type": "phys", "dmg": res[0], "fx": "arrow"}, false)

func _fire_cannon(tgt) -> void:
	var pl := {"type": "phys", "dmg": s.dmg, "splash": s.splash, "armorpen": s.armorpen, "fx": "cannon"}
	if _roll(s.knock):
		pl["knock"] = 55.0
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 520, false, Color(0.3, 0.3, 0.3), 9, pl, true)

func _fire_lightning(tgt) -> void:
	var chain := int(s.chain)
	var dmg: float = s.dmg
	var hit: Array = [tgt]
	var pts := PackedVector2Array([global_position, tgt.global_position])
	var cur = tgt
	for i in chain:
		var nxt = battle.nearest_other(cur.global_position, 160.0, hit)
		if nxt == null:
			break
		hit.append(nxt)
		pts.append(nxt.global_position)
		cur = nxt
	var d := dmg
	for m in hit:
		if not m.alive:
			continue        # an earlier link in the chain already killed it
		m.take_hit(d, "magic")
		if m.alive and _roll(s.stun):
			m.apply_stun(0.6)
		d *= (1.0 - s.falloff)
	battle.spawn_line(pts, Color(0.6, 0.85, 1.0), 4, 0.15)

func _fire_fireball(tgt) -> void:
	var burning: bool = tgt.burn_time > 0.0
	var pl := {"type": "magic", "dmg": s.dmg, "fx": "fire",
		"effects": [{"kind": "burn", "dps": s.burn, "dur": s.burndur}]}
	if burning and _roll(s.detonate):
		pl["splash"] = 60.0
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 650, true, Color(1, 0.5, 0.2), 8, pl, false)

func _fire_frost(tgt) -> void:
	var eff := [{"kind": "slow", "factor": s.slow, "dur": s.slowdur}]
	if _roll(s.freeze):
		eff.append({"kind": "freeze", "dur": 1.0})
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 800, true, Color(0.6, 0.9, 1.0), 6,
		{"type": "phys", "dmg": s.dmg, "effects": eff, "fx": "ice"}, false)

func _fire_poison(tgt) -> void:
	var eff := [{"kind": "poison", "dmg": s.pstack, "stacks": 1, "max": int(s.pmax), "dur": 4.0}]
	var pl := {"type": "true", "dmg": s.dmg, "effects": eff, "fx": "poison"}
	if s.pburst > 0.0:
		pl["splash"] = s.pburst
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 700, true, Color(0.5, 0.9, 0.2), 6, pl, false)

func _fire_sniper(tgt) -> void:
	var res := _crit_dmg(s.dmg, s.crit, 2.2)
	if s.execute > 0.0 and tgt.try_execute(s.execute):
		battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 0.9, 0.5), 3, 0.12)
		return
	tgt.take_hit(res[0], "phys")
	# pierce: also hit next highest-hp targets
	var pierce := int(s.pierce)
	if pierce > 0:
		var extra: Array = battle.monsters_in_radius(tgt.global_position, 90.0, true)
		var cnt := 0
		for m in extra:
			if m == tgt: continue
			m.take_hit(res[0] * 0.7, "phys")
			cnt += 1
			if cnt >= pierce: break
	battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 0.9, 0.5), 3, 0.12)

func _fire_gatling(tgt) -> void:
	if tgt == last_target:
		heat = minf(s.heatmax, heat + s.heatrate)
	else:
		heat = 0.0
	last_target = tgt
	var dmg: float = s.dmg * (1.0 + heat * 0.5)
	tgt.take_hit(dmg, "phys")
	battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 0.95, 0.6), 2, 0.05)
	if _roll(s.spread):
		# others[0] was frequently the primary target itself, so 散射 often just
		# double-tapped the same monster instead of splashing a neighbour.
		for o in battle.monsters_in_radius(tgt.global_position, 70.0, true):
			if o != tgt:
				o.take_hit(dmg * 0.6, "phys")
				break

func _fire_mortar(tgt) -> void:
	var dd := global_position.distance_to(tgt.global_position)
	if dd < s.minrange:
		return
	var pl := {"type": "phys", "dmg": s.dmg, "splash": s.splash, "fx": "cannon"}
	if s.scorch > 0.0:
		pl["effects"] = [{"kind": "burn", "dps": s.dmg * 0.15, "dur": s.scorch}]
	if s.frag > 0.0:
		pl["frag"] = int(s.frag)
	battle.spawn_projectile(global_position, null, tgt.global_position, 480, false, Color(0.4, 0.45, 0.2), 10, pl, true)

func _fire_missile(tgt) -> void:
	var salvo := int(s.salvo)
	for i in salvo:
		var pl := {"type": "phys", "dmg": s.dmg, "splash": s.splash, "bossmult": s.bossmult, "fx": "rocket"}
		# 900 (was 560): at the reworked 440 range a 560-speed missile spends 0.79s
		# in the air and the target has walked off the impact point. Homing itself
		# is exact — Projectile re-aims at the live target every frame, so there is
		# no turn-rate limit to outrun; the problem was purely time-of-flight.
		battle.spawn_projectile(global_position + Vector2(randf_range(-8, 8), -6), tgt,
			tgt.global_position, 900, true, Color(1, 0.4, 0.3), 6, pl, false)

## 詛咒光環. The tower itself does nothing per frame — Battle._tick_curse_auras
## walks the field once and resolves every overlapping aura together, because
## amplification takes the max across towers while the gold bonus stacks with
## diminishing returns. All this does is keep the circle animating.
func _proc_curse_aura(delta: float) -> void:
	_aura_phase += delta
	queue_redraw()

func _fire_holy(tgt) -> void:
	tgt.take_hit(s.dmg, "magic")
	if s.purify > 0.0 and _roll(s.purify):
		tgt.haste_time = 0.0
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 800, true, Color(1, 0.95, 0.7), 6, {"type": "magic", "dmg": 0.0, "fx": "holy"}, false)

func _fire_teleport(tgt) -> void:
	if _roll(s.tpchance):
		# 傳送真係成功嗰下先響 —— tpchance 唔中就冇嘢傳送過。displace 嗰個
		# 推撞聲要熄咗:同一件事已經有 sfx_teleport_hit 講緊,兩個聲疊住就
		# 變成「傳送」聽落似「傳送 + 被打」。
		tgt.displace(s.tpdist, false)
		Audio.play("sfx_teleport_hit")
		if s.stun > 0.0:
			tgt.apply_stun(s.stun)
		battle.spawn_fx_ring(tgt.global_position, 40, Color(0.6, 0.3, 0.9))

func _fire_boomerang(tgt) -> void:
	var dir: Vector2 = (tgt.global_position - global_position).normalized()
	battle.spawn_boomerang(global_position, dir, range_val, s.dmg, s.slow, s.returnmult)

# --- interval / continuous mechs -------------------------------------------
func _fire_alchemy() -> void:
	battle.add_gold(int(s.gold))
	battle.spawn_damage(global_position + Vector2(0, -20), int(s.gold), Color(1, 0.85, 0.2))

func _fire_thorn() -> void:
	for m in battle.monsters_in_radius(global_position, range_val, false):
		m.take_hit(s.dmg * (1.0 + (s.heavymult if m.heavy else 0.0)), "true")
		if s.slow > 0.0:
			m.apply_slow(s.slow, 1.0)
		if s.bleed > 0.0:
			m.apply_poison(s.bleed, 1, 5, 4.0)

func _fire_magnet() -> void:
	for m in battle.monsters_in_radius(global_position, range_val, true):
		var eff: float = 1.0 if not m.is_boss else s.heavyeff
		m.displace(s.knock * eff)
		if s.pulse > 0.0:
			m.take_hit(s.pulse, "phys")
		if s.knockslow > 0.0:
			m.apply_slow(s.knockslow, 1.0)
	battle.spawn_fx_ring(global_position, range_val, Color(0.8, 0.5, 0.4))

func _proc_slowfield(delta: float) -> void:
	var caught := false
	for m in battle.monsters_in_radius(global_position, range_val, true):
		caught = true
		var f: float = s.slow * (s.bosseff if m.is_boss else 1.0)
		m.apply_slow(f, 0.2)
		if s.vuln > 0.0:
			m.apply_vuln(s.vuln, 0.3)
	# 力場嘅「脈衝」聲接喺場入面真係有嘢俾佢緩到嗰陣,唔係接喺 s.pulse 嗰條
	# 傷害線度:pulse 係一個升級,基礎值 0,咁樣接嘅話絕大部分玩家嘅緩速塔
	# 由頭到尾都係啞嘅。空場唔響 —— 一個乜都冇困住嘅力場冇嘢好報。
	if caught:
		play_event_sound(mech)
	if s.pulse > 0.0:
		_cd -= delta
		if _cd <= 0.0:
			_cd = 1.0 / maxf(0.1, s.pulserate)
			for m in battle.monsters_in_radius(global_position, range_val, true):
				m.take_hit(s.pulse, "magic")
			battle.spawn_fx_ring(global_position, range_val, Color(0.3, 0.8, 0.8))

## The beam is continuous, so it cannot key its sound off a shot. It re-triggers
## on its own timer while it has a target — tied to the clip length, not to the
## frame rate, or 5x would fire it 60 times a second into the dedup filter.
var _beam_snd_t: float = 0.0
const BEAM_SND_PERIOD := 0.30

func _proc_beam_audio(delta: float) -> void:
	_proc_beam(delta)
	_beam_snd_t -= delta
	if last_target != null and _beam_snd_t <= 0.0:
		_beam_snd_t = BEAM_SND_PERIOD
		Audio.play_tower(mech)

# _proc_interval calls these with no argument (they pick their own targets), so
# the wrappers take none either.
func _fire_alchemy_snd() -> void:
	_fire_alchemy()
	Audio.play_tower(mech)

func _fire_thorn_snd() -> void:
	_fire_thorn()
	Audio.play_tower(mech)

func _fire_magnet_snd() -> void:
	_fire_magnet()
	Audio.play_tower(mech)

func _proc_beam(delta: float) -> void:
	var tgt = battle.target_closest_to_base(global_position, range_val)
	if tgt == null:
		beam_ramp = maxf(0.0, beam_ramp - delta)
		last_target = null
		return
	if tgt == last_target:
		beam_ramp = minf(s.rampmax, beam_ramp + s.ramprate * delta)
	else:
		beam_ramp = 0.0
	last_target = tgt
	var dps: float = s.dmg * (1.0 + beam_ramp)
	tgt.take_hit(dps * delta, "magic")
	if s.meltarmor > 0.0:
		tgt.apply_vuln(s.meltarmor * 0.05, 0.3)
	battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 1, 0.7), 4 + beam_ramp * 2.0, 0.05)
	if s.dual > 0.0 and _roll(s.dual * delta):
		var o = battle.nearest_other(global_position, range_val, [tgt])
		if o: o.take_hit(dps * delta, "magic")

## 出兵 / 詛咒光環 / 緩速力場 呢三個「持續事件」聲嘅限流住咗喺 Battle
## (battle.play_event_sound)。呢度剩返一個轉接,方便塔自己叫。
##
## 點解唔留喺呢度做 static:窗口本來係 `static var _event_snd_at`,即係跟住
## **腳本**而唔係跟住一場戰鬥活。離開再入返同一關,上一場最後嗰下號角嘅時間戳
## 仲喺度,所以新一場開頭嗰下會被靜靜咁丟 —— 一個由上一場決定嘅結果。
## 而且 static 令佢喺測試之間漏過去:兩個測試場景先後跑,第二個嘅斷言取決於
## 第一個播過乜。窗口屬於一場戰鬥,所以佢而家住喺 Battle 度。
func play_event_sound(mech_name: String) -> void:
	if battle != null:
		battle.play_event_sound(mech_name)

func _proc_barracks(delta: float) -> void:
	# prune dead
	for i in range(soldiers.size() - 1, -1, -1):
		if not is_instance_valid(soldiers[i]) or not soldiers[i].alive:
			soldiers.remove_at(i)
	var want := int(s.count)
	if soldiers.size() < want:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			respawn_timer = maxf(0.5, s.respawn)
			_spawn_soldier()

func _spawn_soldier() -> void:
	var off := randf_range(-40, 40)
	var sd = battle.spawn_soldier(rally_dist + off, s.soldierhp, s.dmg, s.armor, self)
	if sd:
		soldiers.append(sd)
		# 號角響喺真係出到兵嗰下,唔係響喺「想出兵」嗰下 —— spawn_soldier() 返
		# null 就係冇兵出到,冇兵而有號角就係一個講大話嘅提示。
		play_event_sound(mech)

func on_soldier_died(sd) -> void:
	soldiers.erase(sd)

func sell_value() -> int:
	return int(place_cost * 0.7)

func _draw() -> void:
	if mech == "curse":
		_draw_curse_aura()
	if selected:
		draw_arc(Vector2.ZERO, range_val, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(Vector2.ZERO, range_val, Color(1, 1, 1, 0.06))

## Always-visible ground sigil for the 詛咒塔 aura: a violet haze disc, two
## counter-rotating rune rings and a pulsing rim, so the player can see which
## stretch of road is buffed without having to select the tower.
const CURSE_VIOLET := Color(0.62, 0.26, 0.86)

func _draw_curse_aura() -> void:
	var r: float = range_val
	var pulse: float = 0.5 + 0.5 * sin(_aura_phase * 1.6)
	# kept deliberately faint: three overlapping auras stack their alpha, and at
	# 0.09 + 0.07 each that turned a whole corner of the map into a purple slab
	draw_circle(Vector2.ZERO, r, Color(CURSE_VIOLET.r, CURSE_VIOLET.g, CURSE_VIOLET.b, 0.055))
	draw_circle(Vector2.ZERO, r * 0.55, Color(CURSE_VIOLET.r, CURSE_VIOLET.g, CURSE_VIOLET.b, 0.04))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 52,
		Color(CURSE_VIOLET.r, CURSE_VIOLET.g, CURSE_VIOLET.b, 0.42 + 0.22 * pulse), 3.0, true)
	for ring in 2:
		var rr: float = r * (0.78 if ring == 0 else 0.46)
		var spin: float = _aura_phase * (0.35 if ring == 0 else -0.55)
		var n: int = 8 if ring == 0 else 5
		for i in n:
			var a: float = spin + TAU * i / float(n)
			var p := Vector2(cos(a), sin(a)) * rr
			draw_line(p, p - p.normalized() * 9.0,
				Color(CURSE_VIOLET.r, CURSE_VIOLET.g, CURSE_VIOLET.b, 0.55 + 0.25 * pulse), 3.0, true)
			draw_circle(p, 2.6, Color(0.86, 0.66, 1.0, 0.7))
	# a gold mote drifting up out of the sigil — the 掉金加成 half of the identity
	var gy: float = fmod(_aura_phase * 26.0, r * 0.7)
	draw_circle(Vector2(sin(_aura_phase * 1.1) * r * 0.3, r * 0.35 - gy), 3.4,
		Color(1.0, 0.84, 0.3, 0.55 * (1.0 - gy / maxf(1.0, r * 0.7))))
