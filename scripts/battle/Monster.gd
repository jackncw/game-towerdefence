extends Node2D
class_name Monster
## Enemy unit. Moves along a PathRoute by scalar distance. Holds status effects
## and family / boss mechanics. Pooled + reset via setup().

var battle
var route: PathRoute
var pool: Pool
var sprite: Sprite2D

# identity
var fam: String
var lvl: int
var is_boss: bool
var mech: String
var boss_mech: String
var heavy: bool

# stats
var max_hp: float
var hp: float
var base_speed: float
var armor: float
var mres: float
var gold: int
var flying: bool
var size: float

# progress
var dist: float
var alive: bool = false
var revived: bool = false
## 史萊姆分裂出嚟嘅數量(見 FAMILY_LORE:分裂成兩隻)
const SPLIT_COUNT := 2

# status timers (seconds)
var slow_factor: float = 0.0
var slow_time: float = 0.0
var freeze_time: float = 0.0
var stun_time: float = 0.0
var rooted_time: float = 0.0
var burn_dps: float = 0.0
var burn_time: float = 0.0
var poison_stacks: int = 0
var poison_dmg: float = 0.0
var poison_time: float = 0.0
var poison_tick: float = 0.0
var curse_amp: float = 0.0
var curse_time: float = 0.0
var curse_gold: float = 0.0       # 詛咒塔「掉金加成」carried by the curse (fraction)
# Bumped on every pool acquire. Projectiles/boomerangs capture it so a recycled
# node can't be mistaken for the monster they were originally aimed at.
var serial: int = 0
static var _next_serial: int = 1
var vuln_amp: float = 0.0
var vuln_time: float = 0.0
var invuln_time: float = 0.0
var enrage_time: float = 0.0
var dive_time: float = 0.0
var haste_time: float = 0.0
var haste_amp: float = 0.0
var regen_rate: float = 0.0
var phase_time: float = 0.0      # currently phased (untargetable) while > 0
var phase_cd: float = 5.0
var did_rootheal: bool = false
## How many times the 復活光環 has already brought this minion back.
var revive_count: int = 0
## Healing a BOSS has asked for but not yet been paid, in HP. It drains at
## GameData.boss_heal_cap_per_sec, so no boss — whatever its mechanic, now or
## later — can out-heal 20% of the level's expected player DPS, and no single
## frame can push the blood bar upward.
var heal_pending: float = 0.0
# --- telegraphed heal cast (遠古樹妖) ---------------------------------------
var channel_time: float = 0.0    # seconds of cast left
var channel_total: float = 0.0   # cast length, for the progress ring
var channel_heal: float = 0.0    # HP still pending; damage taken eats into it
var channel_heal0: float = 0.0   # what it started at, for the ring colour
# --- heal feedback ----------------------------------------------------------
var _heal_flash: float = 0.0     # green rebound on the HP bar
var _heal_bank: float = 0.0      # healed but not yet shown as a number
var _heal_bank_t: float = 0.0
var boss_timer: float = 0.0
var burn_tick: float = 0.0
var _walk: float = 0.0            # walk-cycle phase (procedural bob/step)
var _drawn_frac: float = -1.0     # HP fraction currently painted (redraw gate)
var _drawn_cursed: bool = false   # curse mark currently painted (redraw gate)

func _ready() -> void:
	sprite = Sprite2D.new()
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	z_index = 20

func setup(b, r: PathRoute, fam_id: String, level: int, boss: bool, wave_scale: float, p: Pool, start_dist := 0.0) -> void:
	battle = b
	route = r
	pool = p
	fam = fam_id
	lvl = level
	is_boss = boss
	var st: Dictionary = GameData.boss_stats(fam_id, wave_scale) if boss else GameData.creature_stats(fam_id, level, wave_scale)
	max_hp = st.hp
	hp = max_hp
	base_speed = st.speed
	armor = st.armor
	mres = st.mres
	gold = st.gold
	flying = st.flying
	mech = st.mech
	size = st.size * GameData.RENDER_SCALE
	boss_mech = st.get("boss_mech", "")
	heavy = is_boss or fam_id in ["golem", "treant", "beetle"]
	sprite.texture = Assets.monster_boss(fam_id) if boss else Assets.monster(fam_id, level)
	sprite.scale = Vector2(GameData.RENDER_SCALE, GameData.RENDER_SCALE)
	sprite.modulate = Color.WHITE
	# reset state
	dist = start_dist
	alive = true
	revived = false
	slow_factor = 0.0; slow_time = 0.0; freeze_time = 0.0; stun_time = 0.0; rooted_time = 0.0
	burn_dps = 0.0; burn_time = 0.0; poison_stacks = 0; poison_dmg = 0.0; poison_time = 0.0
	curse_amp = 0.0; curse_time = 0.0; curse_gold = 0.0
	vuln_amp = 0.0; vuln_time = 0.0; invuln_time = 0.0
	serial = _next_serial
	_next_serial += 1
	enrage_time = 0.0; dive_time = 0.0; haste_time = 0.0; haste_amp = 0.0
	# authored rate; for a boss the ceiling meters it on the way out, so there is
	# one enforcement point instead of a clamp per mechanic
	regen_rate = (max_hp * 0.02) if mech == "regen" else 0.0
	heal_pending = 0.0
	revive_count = 0
	channel_time = 0.0; channel_total = 0.0; channel_heal = 0.0; channel_heal0 = 0.0
	_heal_flash = 0.0; _heal_bank = 0.0; _heal_bank_t = 0.0
	phase_time = 0.0; phase_cd = 5.0; did_rootheal = false; boss_timer = 3.0
	poison_tick = 0.0; burn_tick = 0.0; _flash_t = 0.0; _drawn_frac = -1.0
	_drawn_cursed = false
	_walk = randf() * TAU
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	position = route.pos_at(dist)
	queue_redraw()

func is_alive() -> bool:
	return alive

func targetable() -> bool:
	return alive and phase_time <= 0.0 and invuln_time <= 0.0

func _process(delta: float) -> void:
	if not alive:
		return
	_tick_status(delta)
	# A burn/poison tick inside _tick_status can kill us, and _die() releases this
	# node back to the pool. Without this guard the rest of the frame kept running
	# on a dead monster: it walked past route.total and called on_reach_base(),
	# which ate a base shield charge or LOST the level outright — a poison tick
	# landing on the last step of the path could fail the run.
	if not alive:
		return
	_tick_family(delta)
	if is_boss:
		_tick_boss(delta)
	if not alive:
		return
	# movement
	var spd := _current_speed()
	if spd > 0.0:
		dist += spd * delta
		battle._maybe_warn_base_danger(dist / route.total)
		if dist >= route.total:
			battle.on_reach_base(self)
			return
	position = route.pos_at(dist)
	_animate(delta, spd)
	# _draw() only ever paints the HP bar, and the node transform already carries
	# movement — so redrawing every monster every frame was pure waste. Only
	# invalidate when the bar would actually look different.
	var frac := clampf(hp / max_hp, 0.0, 1.0) if max_hp > 0.0 else 0.0
	var cursed: bool = curse_amp > 0.0
	if absf(frac - _drawn_frac) > 0.004 or cursed != _drawn_cursed:
		_drawn_frac = frac
		_drawn_cursed = cursed
		queue_redraw()

# Procedural walk cycle: grounded units bob up + lean each step; flyers hover.
func _animate(delta: float, spd: float) -> void:
	if flying:
		_walk += delta * 3.2
		sprite.position.y = sin(_walk) * 4.0
		sprite.rotation = sin(_walk * 0.7) * 0.05
	elif spd > 1.0:
		_walk += delta * (7.0 + spd * 0.02)
		sprite.position.y = -absf(sin(_walk)) * (size * 0.07)
		sprite.rotation = sin(_walk * 2.0) * 0.06
	else:
		sprite.position.y = lerpf(sprite.position.y, 0.0, clampf(delta * 8.0, 0, 1))
		sprite.rotation = lerpf(sprite.rotation, 0.0, clampf(delta * 8.0, 0, 1))

func _current_speed() -> float:
	if freeze_time > 0.0 or stun_time > 0.0 or rooted_time > 0.0:
		return 0.0
	var m := 1.0
	if slow_time > 0.0:
		m *= (1.0 - slow_factor)
	if haste_time > 0.0:
		m *= (1.0 + haste_amp)
	if enrage_time > 0.0:
		m *= 1.5
	if dive_time > 0.0:
		m *= 1.8
	if phase_time > 0.0 and boss_mech == "phase_fast":
		m *= 1.6
	m *= battle.enemy_speed_mult
	return base_speed * maxf(m, 0.0)

func _tick_status(delta: float) -> void:
	_tick_flash(delta)
	if slow_time > 0.0: slow_time -= delta
	if freeze_time > 0.0: freeze_time -= delta
	if stun_time > 0.0: stun_time -= delta
	if rooted_time > 0.0: rooted_time -= delta
	if curse_time > 0.0:
		curse_time -= delta
		if curse_time <= 0.0:
			curse_amp = 0.0
			curse_gold = 0.0
	if vuln_time > 0.0:
		vuln_time -= delta
		if vuln_time <= 0.0: vuln_amp = 0.0
	if invuln_time > 0.0: invuln_time -= delta
	if enrage_time > 0.0: enrage_time -= delta
	if dive_time > 0.0: dive_time -= delta
	if haste_time > 0.0:
		haste_time -= delta
		if haste_time <= 0.0: haste_amp = 0.0
	# DoT accumulators DRAIN by one period per tick instead of resetting to 0.
	# Resetting made the tick rate frame-dependent: at 5x a frame delta of 0.167s
	# overshoots the 0.25s burn period, and zeroing the remainder stretched the
	# real period to 0.333s — a silent 25% DoT loss at high speed, and the mirror
	# problem (no loss) at 0.5x, so the same burn did different total damage
	# depending on the speed button. The while-loop also pays out every period
	# that fits in one frame, so a huge delta cannot skip ticks either.
	if burn_time > 0.0:
		burn_time -= delta
		burn_tick += delta
		while burn_tick >= 0.25:
			burn_tick -= 0.25
			_deal_dot(burn_dps * 0.25, Color(1.0, 0.6, 0.15))
			if not alive:
				break
	if poison_time > 0.0 and poison_stacks > 0:
		poison_time -= delta
		poison_tick += delta
		while poison_tick >= 0.5:
			poison_tick -= 0.5
			_deal_dot(poison_dmg * poison_stacks * 0.5, Color(0.5, 0.9, 0.2))
			if not alive:
				break
		if poison_time <= 0.0:
			poison_stacks = 0
	if _heal_flash > 0.0:
		_heal_flash -= delta
	_tick_channel(delta)
	if regen_rate > 0.0 and hp < max_hp:
		request_heal(regen_rate * delta)
	_drain_heal(delta)
	_flush_heal_number(delta)

## Pay out queued healing at no more than the ceiling. Bosses only — everything
## else is healed the moment it is asked for.
func _drain_heal(delta: float) -> void:
	if heal_pending <= 0.0:
		return
	var step: float = minf(heal_pending, GameData.boss_heal_cap_per_sec(max_hp) * delta)
	heal_pending -= step
	_apply_heal(step)

## The telegraphed heal cast: the boss stands still, glows and fills a ring while
## `channel_heal` is on the table. Damage taken during the cast is subtracted
## from it 1:1 (see take_hit / _deal_dot) and a stun cancels it outright, so this
## is a moment the player can answer instead of HP appearing out of nowhere.
func _tick_channel(delta: float) -> void:
	if channel_time <= 0.0:
		return
	if stun_time > 0.0:
		# 打斷: the cast is broken, nothing is paid
		channel_time = 0.0
		channel_heal = 0.0
		rooted_time = 0.0
		battle.spawn_fx_ring(global_position, 70, Color(0.9, 0.9, 0.4))
		queue_redraw()
		return
	rooted_time = maxf(rooted_time, channel_time)   # held in place for the cast
	channel_time -= delta
	queue_redraw()                                  # the ring animates
	if channel_time > 0.0:
		return
	if channel_heal > 0.0:
		# a designed, telegraphed payout — deliberately outside the per-second
		# ceiling, because the player was given a window to deny it
		request_heal(channel_heal, true)
		battle.spawn_fx_ring(global_position, 90, Color(0.4, 0.9, 0.35))
	else:
		battle.spawn_fx_ring(global_position, 70, Color(0.9, 0.9, 0.4))
	channel_heal = 0.0

## Start a telegraphed heal cast for `frac` of max HP over `secs`.
func begin_heal_channel(frac: float, secs: float) -> void:
	channel_total = secs
	channel_time = secs
	channel_heal = max_hp * frac
	channel_heal0 = channel_heal
	# rooted from the very first frame: _tick_boss runs AFTER _tick_channel, so
	# without this the cast's first frame still moved
	rooted_time = maxf(rooted_time, secs)
	battle.spawn_fx_ring(global_position, 60, Color(0.5, 1.0, 0.45))
	queue_redraw()

## The single door every heal in the game goes through, so the ceiling and the
## on-screen feedback can never be bypassed by accident. For a boss the request
## is QUEUED and metered by _drain_heal; for anything else it lands at once.
## `immediate` is for telegraphed casts and resurrections, which are events the
## player was given a way to answer rather than silent sustain.
func request_heal(amount: float, immediate := false) -> float:
	if not alive or amount <= 0.0 or hp >= max_hp:
		return 0.0
	if is_boss and not immediate:
		var room: float = GameData.boss_heal_cap_per_sec(max_hp) * GameData.BOSS_HEAL_QUEUE_SECONDS
		heal_pending = minf(heal_pending + amount, room)
		return 0.0
	return _apply_heal(amount)

## Actually restore HP and announce it. Returns what was restored.
func _apply_heal(amount: float) -> float:
	if not alive or amount <= 0.0 or hp >= max_hp:
		return 0.0
	amount = minf(amount, max_hp - hp)
	hp += amount
	_heal_bank += amount
	_heal_flash = HEAL_FLASH_DUR
	_drawn_frac = -1.0          # force the bar to repaint on the way up too
	queue_redraw()
	return amount

const HEAL_FLASH_DUR := 0.45
## Heal is shown as a floating green number like damage is. Trickle regen is
## banked and emitted in readable lumps rather than one label per frame.
const HEAL_NUMBER_MIN_FRAC := 0.01
const HEAL_NUMBER_MAX_WAIT := 0.9

func _flush_heal_number(delta: float) -> void:
	if _heal_bank <= 0.0:
		return
	_heal_bank_t += delta
	if _heal_bank < max_hp * HEAL_NUMBER_MIN_FRAC and _heal_bank_t < HEAL_NUMBER_MAX_WAIT:
		return
	var n := int(round(_heal_bank))
	if n >= 1:
		battle.spawn_damage(global_position + Vector2(randf_range(-8, 8), -size * 0.75),
			n, Color(0.45, 1.0, 0.45), is_boss, "+")
	_heal_bank = 0.0
	_heal_bank_t = 0.0

func _tick_family(delta: float) -> void:
	match mech:
		"phase":
			if phase_time > 0.0:
				phase_time -= delta
				if phase_time <= 0.0:
					sprite.modulate.a = 1.0
			else:
				phase_cd -= delta
				if phase_cd <= 0.0:
					phase_time = 1.0
					phase_cd = 5.0
					sprite.modulate.a = 0.4
		"aura":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 0.6
				battle.cultist_aura(self, 150.0, max_hp * 0.03, 0.25)

func _tick_boss(delta: float) -> void:
	match boss_mech:
		"summon":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 4.0
				battle.spawn_add(fam, 1, dist)
		"stoneskin":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 6.0
				invuln_time = 1.5
				battle.spawn_fx_ring(global_position, 70, Color(0.7, 0.7, 0.8))
		"dive":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 5.0
				dive_time = 2.0
		"mass_heal":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 7.0
				# the minions still get the full 12%; the 大祭司's own share is
				# queued and metered, so its bar cannot outrun the player's
				# damage the way it used to (12% / 7s = 1.7%/s, over the ceiling)
				battle.heal_all(0.12, self)
				request_heal(max_hp * 0.12)
				battle.spawn_fx_ring(global_position, 120, Color(0.9, 0.5, 0.9))
		"split_birth":
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 3.0
				battle.spawn_add(fam, 1, dist)
		"root_heal":
			# was: instant +25% max HP, nothing the player could do about it.
			# now: a 2.5s cast with a visible ring that damage cancels 1:1.
			if not did_rootheal and hp < max_hp * 0.4:
				did_rootheal = true
				begin_heal_channel(GameData.TREANT_CHANNEL_HEAL, GameData.TREANT_CHANNEL_TIME)

# --- combat -----------------------------------------------------------------
func take_hit(dmg: float, dtype: String, armorpen: float = 0.0) -> void:
	if not alive:
		return
	if invuln_time > 0.0:
		return
	var d := dmg
	if dtype == "phys":
		var a: float = maxf(0.0, armor * (1.0 - armorpen))
		d *= (1.0 - a / (a + 50.0))
	elif dtype == "magic":
		d *= (1.0 - mres / (mres + 60.0))
	# amplifiers
	var amp := 1.0 + curse_amp + vuln_amp
	d *= amp
	# hard shell cap
	if mech == "hardshell":
		d = minf(d, max_hp * 0.12)
	if is_boss and boss_mech == "reflect":
		d *= 0.75
	# wolf enrage on hit
	if boss_mech == "enrage":
		enrage_time = 2.0
	_spend_channel(d)
	hp -= d
	battle.damage_dealt += minf(d, maxf(0.0, hp + d))
	_flash()
	Audio.play_hit(armor, mres)
	var big := d >= max_hp * 0.18 and d >= 40.0
	var ncol := Color(1, 0.85, 0.35) if big else Color(1, 1, 0.7)
	battle.spawn_damage(global_position + Vector2(randf_range(-8, 8), -size * 0.5), int(round(d)), ncol, big)
	if hp <= 0.0:
		_die(false)
	queue_redraw()

func take_true(dmg: float) -> void:
	take_hit(dmg, "true")

## Damage landed while a heal is being cast is subtracted from the pending heal
## 1:1 — out-damage the cast and it pays nothing.
func _spend_channel(d: float) -> void:
	if channel_time <= 0.0 or channel_heal <= 0.0:
		return
	channel_heal = maxf(0.0, channel_heal - d)
	queue_redraw()

func _deal_dot(amount: float, _col: Color) -> void:
	if not alive:
		return
	# 無敵 (golem boss 石化) must block DoT too — take_hit already returns early on
	# invuln, so letting burn/poison through made "短暫無敵" a lie.
	if invuln_time > 0.0:
		return
	_spend_channel(amount)
	battle.damage_dealt += minf(amount, maxf(0.0, hp))
	hp -= amount
	if hp <= 0.0:
		_die(false)

func try_execute(threshold_frac: float) -> bool:
	## returns true if executed (for sniper). bosses immune.
	if is_boss:
		return false
	if hp <= max_hp * threshold_frac:
		_die(false)
		return true
	return false

func _die(force: bool) -> void:
	if not alive:
		return
	# revive. The 復活光環 used to be UNBOUNDED — while the 骷髏君主 lived, every
	# skeleton came back at 30% every single time it died, so the level 3/13 boss
	# fight ran 38-45s against a 16s median and the player's damage read as if it
	# simply did not count. It is now capped at AURA_REVIVE_MAX with the second
	# revive returning half as much HP, which bounds one minion's effective HP at
	# 1 + 0.30 + 0.15 = 1.45x instead of infinity.
	if not force and mech == "revive":
		var limit := 0
		if is_boss:
			limit = 0
		elif battle.skeleton_boss_alive and battle.skeleton_boss_alive != self:
			limit = GameData.AURA_REVIVE_MAX
		else:
			limit = 1
		if revive_count < limit:
			var frac: float = GameData.REVIVE_HP[mini(revive_count, GameData.REVIVE_HP.size() - 1)]
			revive_count += 1
			revived = true
			hp = 0.0
			request_heal(max_hp * frac, true)   # shows the green number + rebound
			battle.spawn_fx_ring(global_position, size, Color(0.8, 0.8, 0.7))
			return
	alive = false
	Audio.play_death(fam)
	if is_boss:
		battle.on_boss_killed(self)
		return
	# split. FAMILY_LORE says 「陣亡時分裂成兩隻較小的史萊姆」 but the code split
	# into 2 + lvl/2, i.e. FOUR at lv5 — and every child splits again, so one lv5
	# slime cascaded into 4 + 16 + 48 + 144 = 212 bodies. The simulated 20th level
	# drowned in them (1500+ kills, boss untouched). Two, as documented, still
	# cascades to 30 but stays a mechanic instead of a bomb.
	if mech == "split" and lvl > 1:
		battle.spawn_split(fam, lvl - 1, SPLIT_COUNT, dist)
	battle.on_monster_killed(self)

# --- effect application -----------------------------------------------------
func apply_slow(factor: float, dur: float) -> void:
	if factor >= slow_factor or slow_time <= 0.0:
		slow_factor = factor
	slow_time = maxf(slow_time, dur)

func apply_freeze(dur: float) -> void:
	if is_boss:
		apply_slow(0.6, dur)
	else:
		freeze_time = maxf(freeze_time, dur)

func apply_stun(dur: float) -> void:
	stun_time = maxf(stun_time, dur)
	# a stun is the spell answer to a telegraphed heal cast; _tick_channel breaks
	# the cast on the next frame

func apply_burn(dps: float, dur: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	burn_time = maxf(burn_time, dur)

func apply_poison(dmg: float, stacks_add: int, maxstacks: int, dur: float) -> void:
	poison_dmg = maxf(poison_dmg, dmg)
	poison_stacks = mini(maxstacks, poison_stacks + stacks_add)
	poison_time = maxf(poison_time, dur)

## Applied every frame by Battle._tick_curse_auras while this monster stands in a
## 詛咒塔 aura. `dur` is the linger time, so walking out of the circle keeps the
## curse for a moment instead of dropping it the instant you cross the edge.
## Amplification does NOT stack across towers (Battle passes the max); the gold
## bonus does, with diminishing returns (Battle does that too).
func apply_curse_aura(amp: float, gold: float, dur: float) -> void:
	curse_amp = maxf(curse_amp, amp)
	curse_gold = maxf(curse_gold, gold)
	curse_time = maxf(curse_time, dur)

func apply_vuln(amp: float, dur: float) -> void:
	vuln_amp = maxf(vuln_amp, amp)
	vuln_time = maxf(vuln_time, dur)

func apply_haste(amp: float, dur: float) -> void:
	haste_amp = maxf(haste_amp, amp)
	haste_time = maxf(haste_time, dur)

func heal(frac: float) -> void:
	request_heal(max_hp * frac)

func displace(amount: float) -> void:
	## push back along route; bosses 80% resist
	var eff := amount * (0.2 if is_boss else 1.0)
	dist = maxf(0.0, dist - eff)
	position = route.pos_at(dist)

## Hit flash. This used to allocate a Tween per hit — with ~130 monsters being
## shot by 43 towers at 5x that is thousands of Tween objects a second, which is
## where a large slice of the frame-time spikes came from. One float ticked in
## _tick_status now: no allocation, and re-hitting simply re-arms it.
const FLASH_DUR := 0.12
var _flash_t: float = 0.0

func _flash() -> void:
	_flash_t = FLASH_DUR
	sprite.modulate = Color(1.6, 1.6, 1.6)

func _tick_flash(delta: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t -= delta
	var base := Color.WHITE if phase_time <= 0.0 else Color(1, 1, 1, 0.4)
	if _flash_t <= 0.0:
		sprite.modulate = base
		return
	sprite.modulate = base.lerp(Color(1.6, 1.6, 1.6), _flash_t / FLASH_DUR)

func _draw() -> void:
	if curse_amp > 0.0:
		_draw_curse_mark()
	if channel_time > 0.0:
		_draw_heal_cast()
	if is_boss:
		return
	var frac := clampf(hp / max_hp, 0.0, 1.0)
	if frac >= 0.999 and _heal_flash <= 0.0:
		return
	var w := size
	var y := -size * 0.62
	draw_rect(Rect2(-w * 0.5, y, w, 5), Color(0, 0, 0, 0.7))
	var col := Color(0.3, 0.9, 0.3)
	if frac < 0.3: col = Color(0.9, 0.25, 0.2)
	elif frac < 0.6: col = Color(0.95, 0.8, 0.2)
	# 視覺誠實: HP that came BACK is painted as a bright green cap on the bar that
	# fades out, so healing is never silent. Without it the bar just crept right
	# and the player read it as "my damage is doing nothing".
	if _heal_flash > 0.0:
		var k: float = _heal_flash / HEAL_FLASH_DUR
		var lift: float = 3.0 * k
		draw_rect(Rect2(-w * 0.5, y - lift, w * frac, 5 + lift * 2.0),
			Color(0.55, 1.0, 0.5, 0.35 + 0.45 * k))
	draw_rect(Rect2(-w * 0.5, y, w * frac, 5), col)

## The 詠唱 tell: a glowing ring that fills over the cast, drawn in green while
## the heal is still on the table and washing out to grey as damage eats it. A
## fully greyed ring means the cast will pay nothing.
func _draw_heal_cast() -> void:
	var r: float = size * 0.85
	var k: float = 1.0 - clampf(channel_time / maxf(0.01, channel_total), 0.0, 1.0)
	var left: float = clampf(channel_heal / maxf(1.0, channel_heal0), 0.0, 1.0)
	var live := Color(0.45, 1.0, 0.42)
	var dead := Color(0.65, 0.65, 0.6)
	var col: Color = dead.lerp(live, left)
	draw_circle(Vector2.ZERO, r + 6.0, Color(live.r, live.g, live.b, 0.10 * left))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 7.0)
	draw_arc(Vector2.ZERO, r, -PI * 0.5, -PI * 0.5 + TAU * k, 40, col, 5.0)

## A small violet wisp + hex sigil over anything standing in a 詛咒塔 aura, so it
## is obvious at a glance WHICH monsters are currently taking amplified damage
## (and will pay the bonus gold). Deliberately tiny — it has to read on a lv1
## goblin without covering the sprite.
func _draw_curse_mark() -> void:
	var y: float = -size * 0.86
	var vio := Color(0.72, 0.36, 0.95, 0.9)
	# hex sigil
	var pts := PackedVector2Array()
	for i in 6:
		var a: float = TAU * i / 6.0 - PI / 2.0
		pts.append(Vector2(cos(a), sin(a)) * 7.0 + Vector2(0, y))
	draw_polyline(pts + PackedVector2Array([pts[0]]), vio, 2.0, true)
	# little flame licking up out of it
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, y - 15.0), Vector2(-4.5, y - 4.0), Vector2(4.5, y - 4.0)]),
		Color(0.86, 0.52, 1.0, 0.85))
	draw_circle(Vector2(0, y - 6.0), 2.2, Color(1, 0.92, 1, 0.9))
