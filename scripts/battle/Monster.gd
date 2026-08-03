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
## 重傷 —— 所受治療嘅減免 (0..1)。巫教族反制嘅共同貨幣。
##
## 做成一個**通用狀態**而唔係逐個機制各寫一套,理由同 boss 回復上限一樣:
## 全部治療都經 request_heal(),所以將來加嘅任何治療來源自動受制,唔使人記得
## 返嚟補。毒液塔嘅「重傷」同劇毒瘴氣兩邊寫入嘅係同一個欄位,取最大值 ——
## 兩個減療疊到 130% 就變成「打中就永遠回唔到」,而嗰個唔係一個狀態,係一個
## 免疫。
var heal_cut: float = 0.0
var heal_cut_time: float = 0.0
## 削甲蝕魔(光束塔)。護甲同魔抗各自扣,唔係轉成易傷 —— 易傷對一個
## 魔抗 25 嘅幽靈完全冇講到「你嘅魔法而家打得穿佢」呢件事。
var shred_armor: float = 0.0
var shred_mres: float = 0.0
var shred_time: float = 0.0
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
## MEASUREMENT ONLY: latched once this monster crosses the "doorstep" distance, so
## Battle.sim_deep_* counts monsters rather than frames. See _process().
var _sim_deep: bool = false

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
	heal_cut = 0.0; heal_cut_time = 0.0
	shred_armor = 0.0; shred_mres = 0.0; shred_time = 0.0
	buff_lock_time = 0.0; ground_time = 0.0; frostbite = 0.0; rot_total = 0.0
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
	_sim_deep = false                 # pooled node: measurement latch resets too
	poison_tick = 0.0; burn_tick = 0.0; _flash_t = 0.0
	_walk = randf() * TAU
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	position = route.pos_at(dist)

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
		# MEASUREMENT ONLY (Battle.sim_*): "how many of them got to my doorstep, and
		# were they the flying ones". Piggybacks on the distance the danger warning
		# already needs, and the latch keeps it to one bool test per monster per
		# frame in the hot loop instead of a per-frame scan of the field.
		if not _sim_deep and dist >= route.total * GameData.BASE_DANGER_ROUTE_FRAC:
			_sim_deep = true
			if flying:
				battle.sim_deep_flying += 1
			else:
				battle.sim_deep_ground += 1
		if dist >= route.total:
			battle.on_reach_base(self)
			return
	position = route.pos_at(dist)
	_animate(delta, spd)

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
	if heal_cut_time > 0.0:
		heal_cut_time -= delta
		if heal_cut_time <= 0.0:
			heal_cut = 0.0
	if shred_time > 0.0:
		shred_time -= delta
		if shred_time <= 0.0:
			shred_armor = 0.0
			shred_mres = 0.0
	if buff_lock_time > 0.0:
		buff_lock_time -= delta
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
	# Resetting made the tick rate frame-dependent: at 3x a frame delta of 0.05s
	# leaves a remainder against the 0.25s burn period, and zeroing it stretched the
	# real period out — a silent DoT loss at high speed, and the mirror
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
		return
	rooted_time = maxf(rooted_time, channel_time)   # held in place for the cast
	channel_time -= delta
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

## The single door every heal in the game goes through, so the ceiling and the
## on-screen feedback can never be bypassed by accident. For a boss the request
## is QUEUED and metered by _drain_heal; for anything else it lands at once.
## `immediate` is for telegraphed casts and resurrections, which are events the
## player was given a way to answer rather than silent sustain.
func request_heal(amount: float, immediate := false) -> float:
	if not alive or amount <= 0.0 or hp >= max_hp:
		return 0.0
	# 重傷喺呢度收數,唔係喺每個治療來源度 —— 一個 enforcement point,
	# 同 boss 回復上限一樣。詠唱嗰種「玩家有窗口去否決」嘅治療同樣受制:
	# 佢係一個可以被打斷嘅治療,唔係一條免疫規則。
	if heal_cut_time > 0.0 and heal_cut > 0.0:
		amount *= maxf(0.0, 1.0 - heal_cut)
		if amount <= 0.0:
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
	battle.sim_heal_enemy += amount     # measurement only; see Battle.sim_*
	_heal_bank += amount
	_heal_flash = HEAL_FLASH_DUR
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

## 世界崩塌 (地震術 T3) 把飛行單位震落地面一段時間。用一個計時器而唔係改
## `flying`:`flying` 係身分(圖鑑、刷怪、族群邏輯全部讀佢),而「而家跌咗
## 落地」係一個狀態。is_airborne() 先係戰鬥判定應該問嘅嘢。
var ground_time: float = 0.0

func is_airborne() -> bool:
	return flying and ground_time <= 0.0

## 技能節拍嘅拖慢比例(時之枷鎖)。boss_timer / phase_cd 全部經呢度,
## 所以「拖慢」對一個 boss 嚟講唔係淨係腳步慢咗。
func _ability_dt(delta: float) -> float:
	if battle.ability_slow <= 0.0:
		return delta
	return delta * maxf(0.05, 1.0 - battle.ability_slow)

func _tick_family(delta: float) -> void:
	if ground_time > 0.0:
		ground_time -= delta
	delta = _ability_dt(delta)
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
			# 暈眩期間光環失效 —— 磁暴脈衝嘅答案。一個被電暈嘅巫師唔應該
			# 繼續一秒兩次咁幫全隊回血;而喺呢度攔截,即係「暈眩」呢個狀態
			# 對所有將來嘅光環都自動有效,唔使逐個機制寫一次。
			if stun_time > 0.0 or freeze_time > 0.0:
				return
			boss_timer -= delta
			if boss_timer <= 0.0:
				boss_timer = 0.6
				battle.cultist_aura(self, 150.0, max_hp * 0.03, 0.25)

func _tick_boss(delta: float) -> void:
	delta = _ability_dt(delta)
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
			# 同 "aura" 一樣:大祭司被電暈嗰陣,群療停。
			if stun_time > 0.0 or freeze_time > 0.0:
				return
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
		var a: float = maxf(0.0, (armor - shred_armor) * (1.0 - armorpen))
		d *= (1.0 - a / (a + 50.0))
		# MEASUREMENT ONLY (Battle.sim_*): two float adds, so the balance harness can
		# tell "armour is eating my shots" apart from "magic resistance is".
		battle.sim_raw_phys += dmg
		battle.sim_out_phys += d
	elif dtype == "magic":
		d *= (1.0 - maxf(0.0, mres - shred_mres) / (maxf(0.0, mres - shred_mres) + 60.0))
		battle.sim_raw_magic += dmg
		battle.sim_out_magic += d
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
	# 戰神降臨 (戰吼 T3):所有塔嘅攻擊附帶真傷濺射。喺呢度做而唔係喺每個
	# _fire_* 度做 —— 「所有攻擊」呢句嘢只有傷害落地嗰一刻先真係知道。
	if battle.warcry_splash > 0.0 and dtype != "true":
		for o in battle.monsters_in_radius(global_position, 70.0, true):
			if o != self and o.alive:
				o._deal_dot(d * battle.warcry_splash, Color(1, 0.85, 0.4))
	# 邁達斯權柄 (點金 T3):敵人每被打中一次就掉一點金
	if battle.midas_hit_gold > 0:
		battle.gold += battle.midas_hit_gold
	_flash()
	Audio.play_hit(armor, mres)
	var big := d >= max_hp * 0.18 and d >= 40.0
	var ncol := Color(1, 0.85, 0.35) if big else Color(1, 1, 0.7)
	battle.spawn_damage(global_position + Vector2(randf_range(-8, 8), -size * 0.5), int(round(d)), ncol, big)
	if hp <= 0.0:
		_die(false)

func take_true(dmg: float) -> void:
	take_hit(dmg, "true")

## Damage landed while a heal is being cast is subtracted from the pending heal
## 1:1 — out-damage the cast and it pays nothing.
func _spend_channel(d: float) -> void:
	if channel_time <= 0.0 or channel_heal <= 0.0:
		return
	channel_heal = maxf(0.0, channel_heal - d)

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
			battle.sim_revives += 1     # measurement only; see Battle.sim_*
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

## 凍傷(極寒塔 T2)。減速期間一層一層咁儲,凍結成立嗰刻一次過爆成真傷。
## 儲喺目標身上而唔係塔身上:一隻俾三座極寒塔輪住打嘅怪應該食晒三座嘅凍傷,
## 而唔係只計最後嗰座。
var frostbite: float = 0.0

func add_frostbite(amount: float) -> void:
	if slow_time > 0.0 or freeze_time > 0.0:
		frostbite += amount

func apply_freeze(dur: float) -> void:
	if frostbite > 0.0:
		var burst: float = frostbite
		frostbite = 0.0
		battle.spawn_fx_burst(global_position, size * 0.9, Color(0.7, 0.95, 1.0), 0.3)
		take_hit(burst, "true")
		if not alive:
			return
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

## `rot` = 腐化聖殿 (毒 T3):毒層每滿一批,生命上限永久跌一截。max_hp 真係
## 跌落去,唔係扮嘢加傷害 —— 血條要真係短咗,玩家先睇得出「呢隻嘢俾我蝕緊」。
var rot_total: float = 0.0

func apply_poison(dmg: float, stacks_add: int, maxstacks: int, dur: float, rot := 0.0) -> void:
	poison_dmg = maxf(poison_dmg, dmg)
	var before := poison_stacks
	poison_stacks = mini(maxstacks, poison_stacks + stacks_add)
	poison_time = maxf(poison_time, dur)
	if rot > 0.0 and poison_stacks >= maxstacks and before < maxstacks \
			and rot_total < GameData.ROT_MAX_TOTAL:
		var step: float = minf(rot, GameData.ROT_MAX_TOTAL - rot_total)
		rot_total += step
		max_hp = maxf(1.0, max_hp * (1.0 - step))
		hp = minf(hp, max_hp)
		if hp <= 0.0:
			_die(false)

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

## 重傷。兩個來源(毒液塔 / 劇毒瘴氣)取**最大值**唔係相加:兩個減療疊到
## 130% 就唔再係一個狀態,係一條「打中就永遠回唔到」嘅免疫規則,而嗰個會令
## 巫教族由「難打」變成「冇存在意義」。
func apply_heal_cut(cut: float, dur: float) -> void:
	heal_cut = clampf(maxf(heal_cut, cut), 0.0, 0.95)
	heal_cut_time = maxf(heal_cut_time, dur)

func apply_shred(armor_amt: float, mres_amt: float, dur: float) -> void:
	shred_armor = maxf(shred_armor, armor_amt)
	shred_mres = maxf(shred_mres, mres_amt)
	shred_time = maxf(shred_time, dur)

## 增益封鎖(磁暴脈衝 tier 3)。封鎖期間 apply_haste 直接被丟掉。
var buff_lock_time: float = 0.0

func apply_buff_lock(dur: float) -> void:
	buff_lock_time = maxf(buff_lock_time, dur)
	haste_amp = 0.0
	haste_time = 0.0
	enrage_time = 0.0

func apply_haste(amp: float, dur: float) -> void:
	if buff_lock_time > 0.0:
		return
	haste_amp = maxf(haste_amp, amp)
	haste_time = maxf(haste_time, dur)

## 「支援型單位」——靠光環撐住同伴嗰啲。狙擊 / 導彈嘅優先目標、天雷誅殺同
## 黎明聖壇嘅增傷全部問呢一條,所以「邊個算支援」只有一個定義。
func is_support() -> bool:
	return GameData.is_support_mech(mech, boss_mech)

func heal(frac: float) -> void:
	request_heal(max_hp * frac)

## `snd` = false 俾嗰啲已經有一個更專屬嘅聲講緊同一件事嘅呼叫點用(傳送塔嘅
## sfx_teleport_hit)。其餘呼叫點照響:磁力塔嘅脈衝同龍捲風一 push 就係一堆怪,
## 但 Audio.play() 嘅 60ms 同名去重窗會將成個迴圈收埋成一下 —— 而「一下」正正
## 就係啱嘅粒度,一次推撞係一件事,唔係二十件,所以呢度唔使再加限流。
func displace(amount: float, snd := true) -> void:
	## push back along route; bosses 80% resist
	var eff := amount * (0.2 if is_boss else 1.0)
	dist = maxf(0.0, dist - eff)
	position = route.pos_at(dist)
	if snd and eff > 0.0:
		Audio.play("sfx_knockback")

## Hit flash. This used to allocate a Tween per hit — with ~130 monsters being
## shot by 43 towers at 3x that is thousands of Tween objects a second, which is
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

# 血條 / 詛咒印 / 詠唱環全部搬咗去 `MonsterOverlay` —— 一個 node 畫晒成場,
# 而唔係 143 隻怪各自 `queue_redraw()` 再喺自己 `_draw()` 度畫。搬走之後
# `Monster` 完全冇 `_draw()`,所以佢哋嘅 sprite 喺 render list 度變成連續
# 一段,合批先至有得批。原因同對照數字寫喺 MonsterOverlay.gd 開頭。
