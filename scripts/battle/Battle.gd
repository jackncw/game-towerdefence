extends Node2D
class_name Battle
## Battle orchestrator: spawning, economy, boss timer, win/lose, targeting
## helpers, pools, tower placement, and spell casting. Rendering split into the
## world (this Node2D) and the HUD (CanvasLayer).

const BattleHUD := preload("res://scripts/ui/BattleHUD.gd")

# world containers
var monsters_root: Node2D
var towers_root: Node2D
var proj_root: Node2D
var fx_root: Node2D
var hud: Control

# pools
var proj_pool: Pool
var dmg_pool: Pool
var fx_pool: Pool
var monster_pool: Pool
var soldier_pool: Pool
var hazard_pool: Pool

# state
var route: PathRoute
var cfg: Dictionary
var level: int
var monsters: Array = []
var towers: Array = []
var alchemy_towers: Array = []
var holy_towers: Array = []
var curse_towers: Array = []
var skeleton_boss_alive = null

var gold: int = 0
var base_shield: int = 0
var _base_shield_max: int = 1
var _danger_played: bool = false
var barrier_reflect: float = 0.0
var base_pos: Vector2

var enemy_speed_mult: float = 1.0
var _enemy_slow_time: float = 0.0
var warcry_haste: float = 0.0
var _warcry_time: float = 0.0
var midas_bonus: float = 0.0
var midas_time: float = 0.0

## Cycle order for the speed button. 0.5x is a genuine slow-motion tier for the
## dense late levels, so this is a float list — game_speed used to be an int and
## every consumer that formatted it with "%d" silently printed x0 at half speed.
var game_speed: float = 1.0
const SPEEDS := [0.5, 1.0, 3.0, 5.0]

## Button caption for a speed. "%g" would render 1.0 as "1" and 0.5 as "0.5",
## but it also renders 3.0 as "3" only by luck of the locale, so spell it out.
static func speed_label(s: float) -> String:
	return "x0.5" if s < 0.75 else "x%d" % int(round(s))

# spawning
var elapsed: float = 0.0
var spawn_timer: float = 0.0
var spawned_count: int = 0       # every monster ever spawned this run (SpeedScaleTest B)
var boss_time: float = 60.0
var boss_spawned: bool = false
var boss_ref = null
# deepest fraction of boss HP removed this run (peaks are kept, so a boss that
# heals back up doesn't erase the progress already earned). Feeds the loss payout.
var boss_best_frac: float = 0.0
# ambient-spawn profile for the current boss (GameData.BOSS_SPAWN), set on boss
# entry. burst_def/_burst_timer drive burst-style profiles (e.g. wolf packs).
var boss_profile: Dictionary = {}
var burst_def: Dictionary = {}
var _burst_timer: float = 0.0
var ended: bool = false
var kills: int = 0
## Total HP actually removed from enemies this battle (after armour / 魔抗 /
## 硬殼 caps). Fed by Monster; the balance bench reads it, because "kills" and
## "leaks" both saturate — one wave is either fully cleared or fully leaked —
## while damage output stays monotone and comparable between builds.
var damage_dealt: float = 0.0

# input modes
var build_id: int = 0            # tower id being placed (0 = none)
var aiming_spell: int = 0        # spell id awaiting target (0 = none)
var selected_tower = null
var spell_cd: Dictionary = {}    # id -> remaining cd

# drag-from-card gesture (C1/C2 primary path). A press that STARTS on a HUD card
# is captured by that Button, so the drag/release arrive at the card's gui_input
# (never at _unhandled_input). BattleHUD forwards them to these methods. _card_*
# tracks whether the gesture has moved far enough to count as a drag vs a tap.
var _dragging_card: int = 0      # >0 build id, <0 -(spell id), 0 none
var _card_press_screen: Vector2
var _card_moved: bool = false

# debug overlay (A). Ring buffer of recent input events + where they were
# consumed; the overlay reads live placement/ghost/valid state each frame.
var _dbg_on: bool = false
var _dbg: Array = []             # of {t:String, p:Vector2, sink:String}
const _DBG_MAX := 10
var _dbg_overlay

const BUILD_MIN := Vector2(70, 250)
const BUILD_MAX := Vector2(1010, 1450)
const ROAD_CLEAR := 62.0
const TOWER_SPACING := 78.0

# camera + gesture input (B2). Screen->world always via camera transform so
# placement/aim stay correct under any zoom/pan.
var cam: Camera2D
var _placer: _Placer
var _flash_rect: ColorRect
var base_spr: Sprite2D
var _base_pulse: float = 0.0
const MAP_MIN := Vector2(0, 0)
const MAP_MAX := Vector2(1080, 1920)
const DEF_ZOOM := 1.0
const ZOOM_MIN := 0.5
const ZOOM_MAX := 2.0
const TAP_MOVE_THRESH := 12.0    # px on screen; beyond this a press is a pan/drag
const DOUBLE_TAP_MS := 300
var _touches: Dictionary = {}    # touch index -> current screen pos
var _press_screen: Vector2
var _press_moved: bool = false
var _panning: bool = false
var _pinch_ref: float = 0.0
var _pinch_zoom0: float = 1.0
var _last_tap_ms: int = 0
var _pointer_world: Vector2 = Vector2(540, 820)

func _ready() -> void:
	level = Flow.selected_level
	cfg = GameData.level_config(level)
	route = PathRoute.template(cfg.path_idx)
	boss_time = cfg.boss_time
	gold = cfg.start_gold
	base_pos = route.pos_at(route.total - 20.0)
	_base_shield_max = base_shield

	Assets.prewarm_battle(cfg.families, cfg.boss_family)
	_build_world()
	_build_pools()
	_build_hud()
	_build_debug()
	spawn_timer = 0.6
	Audio.play_bgm("bgm_battle")
	Engine.time_scale = 1.0
	set_process_unhandled_input(true)

func _exit_tree() -> void:
	Audio.stop_bgm()
	Engine.time_scale = 1.0
	get_tree().paused = false
	Meta.flush_pending_save()   # bestiary sightings collected during the run

# ---------------------------------------------------------------------------
func _build_world() -> void:
	# base dark backdrop (fills any area beyond the tiled ground)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.13, 0.16)
	bg.position = Vector2(-400, -400)
	bg.size = Vector2(1880, 2720)
	bg.z_index = -30
	add_child(bg)
	# tiled rocky ground
	var ground := TextureRect.new()
	ground.texture = Assets.tile("ground")
	ground.stretch_mode = TextureRect.STRETCH_TILE
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ground.position = Vector2(-300, -300)
	ground.size = Vector2(1680, 2520)
	ground.z_index = -20
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	# scatter decorations (cosmetic; never affect placement)
	var scatter := _Scatter.new()
	scatter.route = route
	scatter.z_index = -14
	add_child(scatter)

	# Road: just TWO layers now — a dark ground-line and the textured band.
	# The road tile is authored as a cross-section (dark shoulders -> lit crown),
	# and Line2D maps its V axis across the width, so the shading that used to
	# need a stack of three nested Line2Ds is baked into the texture. Three
	# stacked lines was what produced the "corrugated ribbon" rims at corners.
	var w := GameData.ROAD_WIDTH_SCALE
	_add_road_line(route.points, 104.0 * w, Color(0.07, 0.06, 0.08), -12, null)
	_add_road_line(route.points, 96.0 * w, Color(1, 1, 1), -10, Assets.tile("road"))

	monsters_root = Node2D.new(); add_child(monsters_root)
	towers_root = Node2D.new(); add_child(towers_root)
	proj_root = Node2D.new(); add_child(proj_root)
	fx_root = Node2D.new(); add_child(fx_root)

	# spawn portal where monsters emerge (path start)
	var portal := Sprite2D.new()
	portal.texture = Assets.tile("portal")
	portal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portal.scale = Vector2(2.0, 2.0)   # integer, matches every other sprite
	# nudged down the entry stub so the arch clears the top HUD bar and the
	# currency badges — at the raw path start it was hidden behind them
	portal.position = route.pos_at(4.0) + Vector2(0, 58)
	portal.z_index = -8   # monsters walk OUT of it, so it sits under them
	add_child(portal)

	# base marker
	base_spr = Sprite2D.new()
	base_spr.texture = Assets.base_tex()
	base_spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	base_spr.scale = Vector2(GameData.BASE_RENDER, GameData.BASE_RENDER)
	base_spr.position = base_pos
	base_spr.z_index = 8
	add_child(base_spr)

	# camera: default view = whole map (full path overview) at zoom 1
	cam = Camera2D.new()
	cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	cam.position = Vector2(540, 960)
	cam.zoom = Vector2(DEF_ZOOM, DEF_ZOOM)
	cam.position_smoothing_enabled = false
	add_child(cam)
	cam.make_current()

	# placement / spell-aim overlay (ghost + range). Always-process so it clears
	# its draw when a mode is cancelled even while the game is paused.
	_placer = _Placer.new()
	_placer.battle = self
	_placer.z_index = 30
	_placer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_placer)

	# full-screen flash overlay (freeze/holy/meteor). Own CanvasLayer above the
	# HUD so a screen-wide colour wash reads instantly; alpha driven by flash().
	var flayer := CanvasLayer.new()
	flayer.layer = 5
	add_child(flayer)
	_flash_rect = ColorRect.new()
	_flash_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.modulate.a = 0.0
	flayer.add_child(_flash_rect)

func _add_road_line(pts: PackedVector2Array, width: float, col: Color, z: int, tex: Texture2D) -> void:
	var ln := Line2D.new()
	ln.points = pts
	ln.width = width
	ln.default_color = col
	ln.joint_mode = Line2D.LINE_JOINT_ROUND
	ln.begin_cap_mode = Line2D.LINE_CAP_ROUND
	ln.end_cap_mode = Line2D.LINE_CAP_ROUND
	ln.z_index = z
	if tex != null:
		ln.texture = tex
		ln.texture_mode = Line2D.LINE_TEXTURE_TILE
		ln.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ln)

func _build_pools() -> void:
	proj_pool = Pool.new(func(): return Projectile.new(), proj_root)
	dmg_pool = Pool.new(func(): return DamageNumber.new(), fx_root)
	fx_pool = Pool.new(func(): return Fx.new(), fx_root)
	monster_pool = Pool.new(func(): return Monster.new(), monsters_root)
	soldier_pool = Pool.new(func(): return Soldier.new(), monsters_root)
	hazard_pool = Pool.new(func(): return Hazard.new(), fx_root)
	# Pay for the crowd at scene load instead of mid-wave. Sized from a saturated
	# 5x boss fight (~150 monsters, heavy fx / damage-number churn).
	monster_pool.prewarm(80)
	proj_pool.prewarm(64)
	fx_pool.prewarm(160)
	dmg_pool.prewarm(80)
	soldier_pool.prewarm(12)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	hud = BattleHUD.new()
	hud.battle = self
	layer.add_child(hud)

func _build_debug() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	_dbg_overlay = _DbgOverlay.new()
	_dbg_overlay.battle = self
	_dbg_overlay.visible = false
	layer.add_child(_dbg_overlay)

# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	if ended:
		return
	# camera shake (uses cam.offset so pan/zoom clamp logic is untouched)
	if _shake_t > 0.0:
		_shake_t -= delta
		var a := _shake_amp * clampf(_shake_t / 0.35, 0.0, 1.0)
		cam.offset = Vector2(randf_range(-a, a), randf_range(-a, a))
	elif cam.offset != Vector2.ZERO:
		cam.offset = Vector2.ZERO
	# base crystal: gentle idle glow; flashes red as enemies close on it
	if base_spr != null:
		_base_pulse += delta
		var threat := 0.0
		for m in monsters:
			if m.alive:
				var dd: float = m.global_position.distance_to(base_pos)
				if dd < 320.0:
					threat = maxf(threat, 1.0 - dd / 320.0)
		if threat > 0.05:
			var beat := 0.5 + 0.5 * sin(_base_pulse * (6.0 + threat * 6.0))
			base_spr.modulate = Color(1, 1, 1).lerp(Color(1.6, 0.5, 0.45), threat * beat)
		else:
			var g := 1.0 + 0.06 * sin(_base_pulse * 2.2)
			base_spr.modulate = Color(g, g, g)
	elapsed += delta
	# timed buffs
	if _enemy_slow_time > 0.0:
		_enemy_slow_time -= delta
		if _enemy_slow_time <= 0.0:
			enemy_speed_mult = 1.0
	if _warcry_time > 0.0:
		_warcry_time -= delta
		if _warcry_time <= 0.0:
			warcry_haste = 0.0
	if midas_time > 0.0:
		midas_time -= delta
		if midas_time <= 0.0:
			midas_bonus = 0.0
	for k in spell_cd.keys():
		if spell_cd[k] > 0.0:
			spell_cd[k] = maxf(0.0, spell_cd[k] - delta)

	_tick_curse_auras()
	_spawn_logic(delta)
	if boss_ref != null and is_instance_valid(boss_ref):
		var bm: float = boss_ref.max_hp
		if bm > 0.0:
			boss_best_frac = maxf(boss_best_frac, 1.0 - boss_ref.hp / bm)
	if hud:
		hud.refresh(delta)

func _spawn_logic(delta: float) -> void:
	if not boss_spawned and elapsed >= boss_time:
		_spawn_boss()
	if boss_spawned:
		_burst_logic(delta)
	# The timer is re-armed with `+= interval`, not `= interval`. Assigning threw
	# away the overshoot, so the true spawn period was always rounded UP to the
	# next frame boundary — harmless at 60fps, but the frame delta is 10x larger
	# at 5x than at 0.5x, so the same level spawned measurably fewer monsters the
	# faster you ran it. Draining the remainder makes the long-run rate identical
	# at every speed tier (test/SpeedScaleTest case B).
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		var frac: float = clampf(elapsed / boss_time, 0.0, 1.0)
		var interval: float = lerpf(cfg.spawn_interval_start, cfg.spawn_interval_min, frac)
		if boss_spawned:
			var rate: float = float(boss_profile.get("rate", GameData.BOSS_SPAWN_BASE_RATE))
			if rate <= 0.0:
				# burst-only profile: no ambient spawns, keep the timer ticking
				spawn_timer += interval
				return
			interval /= rate
		_spawn_wave_monster()
		spawn_timer += interval

func _spawn_wave_monster() -> void:
	var fams: Array = cfg.families
	var lv_bonus := 0
	if boss_spawned:
		fams = boss_profile.get("pool", fams)
		lv_bonus = int(boss_profile.get("lvl_bonus", 0))
	var fam: String = fams[randi() % fams.size()]
	var lv: int = clampi(randi_range(cfg.lvl_min, cfg.lvl_max) + lv_bonus, 1, 5)
	var m := _spawn_monster(fam, lv, false, 0.0)
	if boss_spawned:
		var mr: float = float(boss_profile.get("minion_regen", 0.0))
		if mr > 0.0:
			m.regen_rate = maxf(m.regen_rate, m.max_hp * mr)

## Burst-style boss profiles (wolf packs): every `interval` seconds a squad of
## count_min..count_max minions rushes out together from the path start.
func _burst_logic(delta: float) -> void:
	if burst_def.is_empty() or boss_ref == null:
		return
	_burst_timer -= delta
	if _burst_timer > 0.0:
		return
	_burst_timer = float(burst_def["interval"])
	var n := randi_range(int(burst_def["count_min"]), int(burst_def["count_max"]))
	var fam: String = burst_def.get("fam", cfg.boss_family)
	for i in n:
		_spawn_monster(fam, randi_range(cfg.lvl_min, cfg.lvl_max), false, float(i) * 22.0)

func _spawn_boss() -> void:
	boss_spawned = true
	boss_profile = GameData.boss_spawn_profile(cfg.boss_family)
	burst_def = boss_profile.get("burst", {})
	if not burst_def.is_empty():
		_burst_timer = float(burst_def.get("first", burst_def["interval"]))
	var m := _spawn_monster(cfg.boss_family, 5, true, 0.0)
	boss_ref = m
	if m.mech == "revive":
		skeleton_boss_alive = m
	if hud:
		hud.show_boss(m)
	Audio.play("sfx_boss_warning")
	Audio.queue_bgm("bgm_boss")

func _spawn_monster(fam: String, lv: int, boss: bool, start_dist: float) -> Monster:
	var m: Monster = monster_pool.acquire()
	m.setup(self, route, fam, lv, boss, cfg.wave_scale, monster_pool, start_dist)
	monsters.append(m)
	spawned_count += 1
	Meta.mark_seen(fam, lv, boss)   # bestiary sighting
	return m

func spawn_add(fam: String, count: int, at_dist: float) -> void:
	for i in count:
		_spawn_monster(fam, cfg.lvl_min, false, maxf(0.0, at_dist - randf_range(20, 60)))

## Slime split. Children are held back from the gate: at the old `total - 10`
## clamp a slime killed on the last step spawned its children essentially inside
## the base, where nothing could shoot them — a guaranteed uncounterable leak.
## SPLIT_BACK leaves them a short stretch of road to be killed on.
const SPLIT_BACK := 80.0

func spawn_split(fam: String, lv: int, count: int, at_dist: float) -> void:
	var cap: float = maxf(0.0, route.total - SPLIT_BACK)
	for i in count:
		var off := randf_range(-25, 25)
		_spawn_monster(fam, maxi(1, lv), false, clampf(at_dist + off, 0.0, cap))

# ---------------------------------------------------------------------------
# removal / economy
func on_monster_killed(m: Monster) -> void:
	kills += 1
	var g: int = m.gold
	# alchemy kill bonus
	for a in alchemy_towers:
		if is_instance_valid(a) and a.global_position.distance_to(m.global_position) <= a.range_val:
			g += int(m.gold * a.s.killbonus)
			break
	# 詛咒塔「掉金加成」: dying while cursed pays extra. This is the tower's second
	# reason to exist — it is an amplifier AND an economy piece, but only where
	# there are already output towers killing things.
	if m.curse_gold > 0.0:
		g += int(round(m.gold * m.curse_gold))
	if midas_bonus > 0.0:
		g += int(m.gold * midas_bonus)
	add_gold(g)
	# death juice: family-tinted dissolve burst + dust sparks + coins popping out
	var fc: Color = Assets._fam_col(m.fam)
	spawn_fx_burst(m.global_position, m.size * 0.8, fc.lightened(0.2), 0.28)
	spawn_sparks(m.global_position, 5, fc.lightened(0.3), 150.0, 3.5, 0.45)
	spawn_coin_pop(m.global_position, 2 if m.gold < 20 else 3)
	spawn_damage(m.global_position + Vector2(0, -m.size * 0.4), g, Color(1, 0.85, 0.2))
	_remove(m)

func on_boss_killed(m: Monster) -> void:
	kills += 1
	spawn_fx_burst(m.global_position, 140, Color(0.7, 0.5, 1.0), 0.7)
	spawn_sparks(m.global_position, 22, Color(1, 0.9, 0.5), 320.0, 6.0, 0.9)
	spawn_coin_pop(m.global_position, 10)
	shake(14.0, 0.5)
	flash(Color(1, 1, 1, 0.4), 0.3)
	if skeleton_boss_alive == m:
		skeleton_boss_alive = null
	_remove(m)
	_win()

func on_reach_base(m: Monster) -> void:
	if base_shield > 0:
		base_shield -= 1
		# 基地危險:只喺跌穿三成嗰一刻響一次,唔係每次漏怪都響 —— 後者喺守唔住嘅
		# 局入面會變成連續警報,而連續警報等於冇警報
		if base_shield > 0 and float(base_shield) / float(_base_shield_max) < GameData.BASE_DANGER_FRAC \
				and not _danger_played:
			_danger_played = true
			Audio.play("sfx_base_danger")
		spawn_fx_ring(base_pos, 90, Color(0.5, 0.8, 1.0))
		_barrier_reflect_burst(m)
		if not m.alive:
			return          # the reflect finished it off; _die already removed it
		if m.is_boss:
			# boss cannot be blocked away permanently; push it back instead
			m.dist = maxf(0.0, m.dist - 300.0)
			m.position = route.pos_at(m.dist)
			base_shield += 1
			return
		_remove(m)
		return
	_lose()

## 守護結界「結界反傷」: the shield discharges into whatever is standing at the
## gate. barrier_reflect was previously assigned by the spell and never read, so
## the whole upgrade direction was inert.
func _barrier_reflect_burst(blocked) -> void:
	if barrier_reflect <= 0.0:
		return
	if is_instance_valid(blocked) and blocked.alive:
		blocked.take_hit(barrier_reflect, "magic")
	for m in monsters_in_radius(base_pos, 150.0, true):
		if m == blocked:
			continue
		m.take_hit(barrier_reflect * 0.5, "magic")
	spawn_fx_burst(base_pos, 150.0, Color(0.55, 0.82, 1.0), 0.35)

func _remove(m: Monster) -> void:
	monsters.erase(m)
	if boss_ref == m:
		boss_ref = null
	monster_pool.release(m)

func add_gold(amount: int) -> void:
	Audio.play("sfx_gold_pop")
	gold += amount

func spend_gold(amount: int) -> bool:
	if gold < amount:
		return false
	gold -= amount
	return true

# ---------------------------------------------------------------------------
# targeting helpers
func target_closest_to_base(pos: Vector2, rng: float):
	var best = null
	var best_d := -1.0
	var r2 := rng * rng
	for m in monsters:
		if not m.targetable():
			continue
		if pos.distance_squared_to(m.global_position) > r2:
			continue
		if m.dist > best_d:
			best_d = m.dist
			best = m
	return best

func target_highest_hp(pos: Vector2, rng: float):
	var best = null
	var best_hp := -1.0
	var r2 := rng * rng
	for m in monsters:
		if not m.targetable():
			continue
		if pos.distance_squared_to(m.global_position) > r2:
			continue
		if m.hp > best_hp:
			best_hp = m.hp
			best = m
	return best

func monsters_in_radius(pos: Vector2, rng: float, flying_ok: bool) -> Array:
	var out := []
	var r2 := rng * rng
	for m in monsters:
		if not m.alive:
			continue
		if not flying_ok and m.flying:
			continue
		if pos.distance_squared_to(m.global_position) <= r2:
			out.append(m)
	return out

func nearest_other(pos: Vector2, rng: float, exclude: Array):
	var best = null
	var best_d := rng * rng
	for m in monsters:
		if not m.targetable() or exclude.has(m):
			continue
		var d := pos.distance_squared_to(m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best

func nearest_any(pos: Vector2, rng: float):
	var best = null
	var best_d := rng * rng
	for m in monsters:
		if not m.targetable():
			continue
		var d := pos.distance_squared_to(m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best

func nearest_ground_monster_near(pos: Vector2, radius: float):
	var best = null
	var best_d := radius * radius
	for m in monsters:
		if not m.alive or m.flying:
			continue
		var d := pos.distance_squared_to(m.global_position)
		if d <= best_d:
			best_d = d
			best = m
	return best

func all_monsters() -> Array:
	return monsters.duplicate()

func monsters_sorted_by_progress() -> Array:
	var arr := monsters.duplicate()
	arr.sort_custom(func(a, b): return a.dist > b.dist)
	return arr

## 詛咒光環 (詛咒塔). One pass over the field per frame instead of letting each
## tower apply its own curse, because the two halves stack differently:
##   * amplification takes the MAX across overlapping towers — stacking it would
##     make a wall of 詛咒塔 multiply the whole board's damage
##   * the gold bonus DOES stack, but each extra source contributes half of the
##     previous one, so a second tower is worth something and a sixth is not
func _tick_curse_auras() -> void:
	if curse_towers.is_empty():
		return
	for i in range(curse_towers.size() - 1, -1, -1):
		if not is_instance_valid(curse_towers[i]):
			curse_towers.remove_at(i)
	if curse_towers.is_empty():
		return
	for m in monsters:
		if not m.alive:
			continue
		var amp := 0.0
		var linger := 0.0
		var slow := 0.0
		var golds: Array = []
		for t in curse_towers:
			if m.global_position.distance_to(t.global_position) > t.range_val:
				continue
			var a: float = float(t.s.curse) * (float(t.s.bosseff) if m.is_boss else 1.0)
			amp = maxf(amp, a)
			linger = maxf(linger, float(t.s.linger))
			slow = maxf(slow, float(t.s.slow))
			golds.append(float(t.s.goldbonus))
		if amp <= 0.0:
			continue
		golds.sort()
		golds.reverse()
		var gold_total := 0.0
		for i in golds.size():
			gold_total += golds[i] * pow(0.5, i)
		m.apply_curse_aura(amp, gold_total, linger)
		if slow > 0.0:
			m.apply_slow(slow, maxf(0.3, linger))

## `except` is the caster: a boss heals ITSELF out of its capped heal budget
## (Monster.request_heal, metered by the ceiling), not out of the full group
## heal, so its own bar can never
## outrun the player's damage. Minions are unaffected.
func heal_all(frac: float, except = null) -> void:
	for m in monsters:
		if m == except:
			continue
		m.heal(frac)

func cultist_aura(src, radius: float, heal_amt: float, haste: float) -> void:
	for m in monsters_in_radius(src.global_position, radius, true):
		if m == src:
			continue
		m.request_heal(heal_amt)
		m.apply_haste(haste, 0.7)

func holy_haste_at(pos: Vector2) -> float:
	var total := 0.0
	for h in holy_towers:
		if not is_instance_valid(h):
			continue
		if pos.distance_to(h.global_position) <= h.s.aurarange:
			total += h.s.aurahaste
	return total

# ---------------------------------------------------------------------------
# spawn helpers (pooled)
func spawn_projectile(from: Vector2, tgt, tpos: Vector2, speed: float, homing: bool, col: Color, radius: float, payload: Dictionary, lob: bool) -> void:
	var p: Projectile = proj_pool.acquire()
	p.setup(from, tgt, tpos, speed, homing, col, radius, payload, lob, self, proj_pool)

var _bpool: Pool = null
func spawn_boomerang(from: Vector2, dir: Vector2, dist: float, dmg: float, slow: float, rmult: float) -> void:
	if _bpool == null:
		_bpool = Pool.new(func(): return Boomerang.new(), proj_root)
	var b: Boomerang = _bpool.acquire()
	b.setup(self, from, dir, dist, dmg, slow, rmult, _bpool)

func on_projectile_hit(proj: Projectile) -> void:
	var pl: Dictionary = proj.payload
	var targets: Array
	var splash: float = pl.get("splash", 0.0)
	if splash > 0.0:
		targets = monsters_in_radius(proj.position, splash, true)
		spawn_fx_burst(proj.position, splash, Color(1, 0.6, 0.2), 0.3)
	else:
		var lt = proj.live_target()
		targets = [lt] if lt != null else monsters_in_radius(proj.position, 24.0, true)
	var dmg: float = pl.get("dmg", 0.0)
	var dtype: String = pl.get("type", "phys")
	var armorpen: float = pl.get("armorpen", 0.0)
	var bossmult: float = pl.get("bossmult", 0.0)
	for m in targets:
		if not m.alive:
			continue
		var d := dmg
		if bossmult > 0.0 and m.is_boss:
			d *= (1.0 + bossmult)
		if d > 0.0:
			m.take_hit(d, dtype, armorpen)
		# the hit may have killed (and pooled) it — never push status onto a
		# monster that is already back in the free list
		if not m.alive:
			continue
		if pl.has("knock"):
			m.displace(pl.knock)
		if pl.has("effects"):
			for e in pl.effects:
				_apply_effect(m, e)
	# fragment splits
	if pl.get("frag", 0) > 0:
		for i in int(pl.frag):
			spawn_fx_burst(proj.position + Vector2(randf_range(-40, 40), randf_range(-40, 40)), 40, Color(1, 0.6, 0.2), 0.25)
			for m in monsters_in_radius(proj.position + Vector2(randf_range(-40, 40), randf_range(-40, 40)), 40, true):
				m.take_hit(dmg * 0.4, dtype)

func _apply_effect(m, e: Dictionary) -> void:
	match e.kind:
		"slow": m.apply_slow(e.factor, e.dur)
		"freeze": m.apply_freeze(e.dur)
		"burn": m.apply_burn(e.dps, e.dur)
		"poison": m.apply_poison(e.dmg, e.stacks, e.max, e.dur)
		"stun": m.apply_stun(e.dur)
		"vuln": m.apply_vuln(e.amp, e.dur)

## `magic` picks the 魔法民兵 body (hooded, timed, runed) over the barracks
## trooper. It is explicit rather than inferred from `tower == null`, because a
## future permanent summon would silently get the wrong look.
func spawn_soldier(dist_pos: float, hp: float, dmg: float, armor: float, tower = null, life := -1.0, magic := false):
	var sd: Soldier = soldier_pool.acquire()
	sd.setup(self, route, clampf(dist_pos, 0, route.total - 10), hp, dmg, armor, soldier_pool, tower, magic)
	sd.life_time = life
	return sd

func spawn_hazard(pos: Vector2, radius: float, dps: float, dur: float, kind: int, col: Color, ground_only: bool) -> void:
	# pooled like everything else — miasma / firewall / blackhole used to
	# instantiate and queue_free a node per cast
	var h: Hazard = hazard_pool.acquire()
	h.setup(self, pos, radius, dps, dur, kind, col, ground_only, hazard_pool)

# Damage numbers are Labels — the most expensive node in the battle, because
# every setup() re-shapes text. Unbounded, a saturated 5x fight pushed the pool
# past 400 live labels, which is both the biggest frame-time spike AND completely
# unreadable on screen. Big hits (crits / boss damage) always get through;
# ordinary chip damage thins out once the screen is already full.
const DMG_SOFT_CAP := 90
const DMG_HARD_CAP := 150

## `prefix` lets a heal read as "+140" in green next to the red damage numbers —
## the 視覺誠實 half of the boss-heal rework.
func spawn_damage(pos: Vector2, amount: int, col: Color, big := false, prefix := "") -> void:
	var live: int = dmg_pool.live_count()
	if live >= DMG_HARD_CAP:
		return
	if not big and live >= DMG_SOFT_CAP and (live % 3) != 0:
		return
	var d: DamageNumber = dmg_pool.acquire()
	d.setup(pos, prefix + str(amount), col, dmg_pool, big)

# --- cosmetic FX budget -----------------------------------------------------
# Under a saturated 5x fight the fx pool used to grow past NINE HUNDRED live
# nodes — 43 towers each throw 2 muzzle sparks per shot, every kill adds a burst
# + 5 dust sparks + coins — and every one of those redraws itself every frame.
# Pool growth plus that draw load was a major source of 90-150ms frame spikes.
# Sparks/coins are pure garnish, so they thin out as the field gets busy; the
# structural effects (rings, bursts, bolts) only stop at the hard ceiling.
const FX_SOFT_CAP := 220     # start halving garnish
const FX_HARD_CAP := 400     # absolute ceiling on live fx nodes

func _fx_room() -> int:
	return FX_HARD_CAP - fx_pool.live_count()

## How many garnish particles we are willing to spend right now.
func _spark_allowance(n: int) -> int:
	var live: int = fx_pool.live_count()
	if live >= FX_HARD_CAP:
		return 0
	if live >= FX_SOFT_CAP:
		n = n / 2
	return mini(n, FX_HARD_CAP - live)

func spawn_line(pts: PackedVector2Array, col: Color, w: float, dur: float) -> void:
	if _fx_room() <= 0:
		return
	var f: Fx = fx_pool.acquire()
	f.line(pts, col, w, dur, fx_pool)

func spawn_fx_ring(pos: Vector2, r: float, col: Color) -> void:
	if _fx_room() <= 0:
		return
	var f: Fx = fx_pool.acquire()
	f.ring(pos, r, col, 0.4, fx_pool)

## Ring with an explicit lifetime (spell shockwaves / domes / funnels). Spells.gd
## used to acquire from fx_pool directly, which side-stepped this budget.
func spawn_fx_ring_dur(pos: Vector2, r: float, col: Color, dur: float) -> void:
	if _fx_room() <= 0:
		return
	var f: Fx = fx_pool.acquire()
	f.ring(pos, r, col, dur, fx_pool)

func spawn_fx_burst(pos: Vector2, r: float, col: Color, dur: float) -> void:
	if _fx_room() <= 0:
		return
	var f: Fx = fx_pool.acquire()
	f.burst(pos, r, col, dur, fx_pool)

func spawn_fx_orb(pos: Vector2, col: Color) -> void:
	if _fx_room() <= 0:
		return
	var f: Fx = fx_pool.acquire()
	f.orb(pos, 8, col, 0.3, fx_pool)

## Burst of small physics sparks (death dust, muzzle, elemental hits).
func spawn_sparks(pos: Vector2, n: int, col: Color, speed: float, r := 4.0, dur := 0.5, grav := 340.0, dia := false) -> void:
	for i in _spark_allowance(n):
		var ang := randf() * TAU
		var sp := speed * randf_range(0.5, 1.1)
		var f: Fx = fx_pool.acquire()
		f.spark(pos, Vector2(cos(ang), sin(ang)) * sp - Vector2(0, speed * 0.3),
			r * randf_range(0.7, 1.2), col, dur * randf_range(0.75, 1.1), fx_pool, grav, dia)

## Gold coins bursting up on a kill (juice).
func spawn_coin_pop(pos: Vector2, n := 3) -> void:
	for i in _spark_allowance(n):
		var f: Fx = fx_pool.acquire()
		var vx := randf_range(-70, 70)
		f.spark(pos, Vector2(vx, randf_range(-230, -150)), 6.0, Color(1, 0.82, 0.2),
			0.6, fx_pool, 520.0, true)

## Short camera shake (big impacts / spells).
var _shake_t := 0.0
var _shake_amp := 0.0
func shake(amp: float, dur: float) -> void:
	_shake_amp = maxf(_shake_amp, amp)
	_shake_t = maxf(_shake_t, dur)

## Full-screen colour flash (freeze white, holy gold, meteor red).
func flash(col: Color, dur := 0.35) -> void:
	if _flash_rect == null:
		return
	_flash_rect.color = col
	_flash_rect.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_flash_rect, "modulate:a", 0.0, dur)

# ---------------------------------------------------------------------------
# timed global buffs
func set_enemy_slow(slow: float, dur: float) -> void:
	enemy_speed_mult = 1.0 - slow
	_enemy_slow_time = dur

func set_warcry(haste: float, dur: float) -> void:
	warcry_haste = haste
	_warcry_time = dur

# ---------------------------------------------------------------------------
# placement + input
# A spot is RED (invalid) for exactly three reasons, and GREEN otherwise:
#   1. outside the buildable rectangle (map edges / UI margins)
#   2. on the road or within ROAD_CLEAR of its centreline (road + edge buffer)
#   3. overlapping an existing tower (within TOWER_SPACING)
# can_place_reason() returns "" when placeable, else the failing reason (used by
# the debug overlay and tests); can_place() is just the boolean form.
func can_place_reason(pos: Vector2) -> String:
	if pos.x < BUILD_MIN.x or pos.x > BUILD_MAX.x or pos.y < BUILD_MIN.y or pos.y > BUILD_MAX.y:
		return "out_of_bounds"
	if route.dist_to_route(pos) < ROAD_CLEAR:
		return "on_road"
	for t in towers:
		if t.global_position.distance_to(pos) < TOWER_SPACING:
			return "tower_overlap"
	return ""

func can_place(pos: Vector2) -> bool:
	return can_place_reason(pos) == ""

func snap(pos: Vector2) -> Vector2:
	var g := 74.0
	return Vector2(round(pos.x / g) * g + 12, round(pos.y / g) * g + 6)

func place_tower(id: int, pos: Vector2) -> bool:
	var def := GameData.tower_by_id(id)
	if gold < def.place_cost or not can_place(pos):
		return false
	gold -= def.place_cost
	var t := Tower.new()
	towers_root.add_child(t)
	t.setup(self, id, pos)
	towers.append(t)
	if t.mech == "alchemy":
		alchemy_towers.append(t)
	elif t.mech == "holy":
		holy_towers.append(t)
	elif t.mech == "curse":
		curse_towers.append(t)
	Audio.play("sfx_place_tower")
	return true

func sell_tower(t) -> void:
	if t == null:
		return
	Audio.play("sfx_sell_tower")
	gold += t.sell_value()
	spawn_damage(t.global_position, t.sell_value(), Color(1, 0.85, 0.2))
	towers.erase(t)
	alchemy_towers.erase(t)
	holy_towers.erase(t)
	curse_towers.erase(t)
	# duplicate() is required: Soldier._die() calls back into on_soldier_died(),
	# which erases from this very array — iterating it live skipped every second
	# soldier and left orphans blocking the road for free after the sale.
	for sd in t.soldiers.duplicate():
		if is_instance_valid(sd) and sd.alive:
			sd._die()
	t.queue_free()
	if selected_tower == t:
		selected_tower = null

# --- gesture input --------------------------------------------------------
# emulate_touch_from_mouse is on, so a desktop click arrives as ScreenTouch and
# a drag as ScreenDrag; the mouse wheel stays a MouseButton. We take the tap
# location from the EVENT (event.position) — never get_global_mouse_position(),
# which is (0,0) under touch and was the cause of "can't place / cast".
func _unhandled_input(event: InputEvent) -> void:
	# F3 toggles the debug overlay (works even mid-build / paused)
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_toggle_debug()
		return
	if ended:
		return
	if event is InputEventScreenTouch:
		dbg_log("touch%s" % ("↓" if event.pressed else "↑"), event.position, "world/_unhandled")
		_on_touch(event)
	elif event is InputEventScreenDrag:
		dbg_log("drag", event.position, "world/_unhandled")
		_on_drag(event)
	elif event is InputEventMouseButton and event.pressed and \
			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var f: float = 1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12
		_zoom_at(cam.zoom.x * f, event.position)
	elif event is InputEventMouseMotion:
		# desktop hover: keep the ghost/aim following the cursor
		_pointer_world = screen_to_world(event.position)

# --- debug overlay plumbing (A) -------------------------------------------
func dbg_log(kind: String, pos: Vector2, sink: String) -> void:
	_dbg.append({"t": kind, "p": pos, "sink": sink})
	while _dbg.size() > _DBG_MAX:
		_dbg.pop_front()

func _toggle_debug() -> void:
	_dbg_on = not _dbg_on
	if _dbg_overlay:
		_dbg_overlay.visible = _dbg_on

func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		_pointer_world = screen_to_world(e.position)
		if _touches.size() == 1:
			_press_screen = e.position
			_press_moved = false
			_panning = false
		elif _touches.size() == 2:
			# second finger down -> pinch, never a tap
			_panning = false
			_press_moved = true
			_pinch_ref = _touch_span()
			_pinch_zoom0 = cam.zoom.x
	else:
		var was_single: bool = _touches.size() == 1
		_touches.erase(e.index)
		if _touches.is_empty():
			if was_single and not _press_moved:
				_tap(e.position)
			_panning = false

func _on_drag(e: InputEventScreenDrag) -> void:
	_touches[e.index] = e.position
	_pointer_world = screen_to_world(e.position)
	if _touches.size() >= 2:
		_press_moved = true
		var span := _touch_span()
		if _pinch_ref > 1.0:
			_zoom_at(_pinch_zoom0 * (span / _pinch_ref), _touch_mid())
	else:
		if not _press_moved and e.position.distance_to(_press_screen) > TAP_MOVE_THRESH:
			_press_moved = true
			_panning = true
		if _panning:
			cam.position -= e.relative / cam.zoom.x
			_clamp_cam()

func _tap(screen: Vector2) -> void:
	var now := Time.get_ticks_msec()
	# double-tap resets the view, but only when not mid build/aim so it never
	# swallows a placement/cast tap
	if now - _last_tap_ms <= DOUBLE_TAP_MS and build_id == 0 and aiming_spell == 0:
		_reset_view()
		_last_tap_ms = 0
		return
	_last_tap_ms = now
	_handle_tap(screen_to_world(screen))

func screen_to_world(sp: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * sp

func _touch_span() -> float:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)

func _touch_mid() -> Vector2:
	var pts: Array = _touches.values()
	if pts.size() < 2:
		return _press_screen
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5

func _zoom_at(z: float, focus_screen: Vector2) -> void:
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	var old: float = cam.zoom.x
	if is_equal_approx(z, old):
		return
	var focus_world := screen_to_world(focus_screen)
	cam.zoom = Vector2(z, z)
	# keep the focus point under the finger/cursor (derivation independent of stretch)
	cam.position += (focus_world - cam.position) * (1.0 - old / z)
	_clamp_cam()

func _clamp_cam() -> void:
	var vis: Vector2 = get_viewport().get_visible_rect().size
	var half: Vector2 = (vis * 0.5) / cam.zoom.x
	var lo: Vector2 = MAP_MIN + half
	var hi: Vector2 = MAP_MAX - half
	var p: Vector2 = cam.position
	p.x = (lo.x + hi.x) * 0.5 if lo.x > hi.x else clampf(p.x, lo.x, hi.x)
	p.y = (lo.y + hi.y) * 0.5 if lo.y > hi.y else clampf(p.y, lo.y, hi.y)
	cam.position = p

func _reset_view() -> void:
	cam.zoom = Vector2(DEF_ZOOM, DEF_ZOOM)
	cam.position = Vector2(540, 960)
	_clamp_cam()

func _handle_tap(pos: Vector2) -> void:
	# spell aiming: tap a spot to cast; keep aiming if the cast had no valid target
	if aiming_spell > 0:
		if _cast_spell_at(aiming_spell, pos):
			aiming_spell = 0
		return
	# build mode: valid spot places (may keep placing while affordable); tapping a
	# red/invalid spot cancels build mode (per spec)
	if build_id > 0:
		var sp := snap(pos)
		if place_tower(build_id, sp):
			if gold < GameData.tower_by_id(build_id).place_cost:
				cancel_modes()
		else:
			cancel_modes()
		return
	# select existing tower
	var picked = _tower_at(pos)
	_set_selected(picked)

func _tower_at(pos: Vector2):
	for t in towers:
		if t.global_position.distance_to(pos) < 40:
			return t
	return null

func _set_selected(t) -> void:
	if selected_tower:
		selected_tower.selected = false
		selected_tower.queue_redraw()
	selected_tower = t
	if t:
		t.selected = true
		t.queue_redraw()
	hud.show_tower_panel(t)

# ---------------------------------------------------------------------------
# Drag-from-card gesture (C1/C2 primary path). BattleHUD forwards a card's
# captured press/drag/release here. `screen` is a viewport-space point (from the
# event's global_position), converted with the same screen_to_world() the map
# taps use, so it stays correct under any zoom/pan.
func card_press(id: int, is_spell: bool, screen: Vector2) -> void:
	dbg_log("card↓ id=%d%s" % [id, "(spell)" if is_spell else ""], screen, "hud/gui_input")
	_set_selected(null)
	_card_press_screen = screen
	_card_moved = false
	_pointer_world = screen_to_world(screen)
	if is_spell:
		# spells on cooldown are inert (C2); a targeted press arms aiming, an
		# instant press fires immediately.
		if spell_cd.get(id, 0.0) > 0.0:
			_dragging_card = 0
			return
		build_id = 0
		var def := GameData.spell_by_id(id)
		if def.target:
			aiming_spell = id
			_dragging_card = -id
		else:
			aiming_spell = 0
			_dragging_card = 0
			_cast_spell_now(id)
	else:
		aiming_spell = 0
		build_id = id
		_dragging_card = id

## Abandon a card gesture without acting on it. The build drawer needs this:
## its panel sits over world coordinates that are perfectly legal build spots,
## so releasing a dragged tower back onto the open panel would otherwise build a
## tower underneath the UI the player was looking at.
func card_cancel() -> void:
	_dragging_card = 0
	_card_moved = false
	build_id = 0
	aiming_spell = 0

func card_drag(screen: Vector2) -> void:
	if _dragging_card == 0:
		return
	if screen.distance_to(_card_press_screen) > TAP_MOVE_THRESH:
		_card_moved = true
	_pointer_world = screen_to_world(screen)
	dbg_log("card↔", screen, "hud/gui_input")

func card_release(screen: Vector2) -> void:
	var dc := _dragging_card
	_dragging_card = 0
	if dc == 0:
		return
	_pointer_world = screen_to_world(screen)
	dbg_log("card↑ moved=%s" % _card_moved, screen, "hud/gui_input")
	if dc > 0:
		# tower card. A tap (no movement) just ARMS build mode for the two-stage
		# fallback; a real drag places on a green spot and cancels on red/UI.
		if not _card_moved:
			return
		var sp := snap(_pointer_world)
		if place_tower(dc, sp):
			if gold < GameData.tower_by_id(dc).place_cost:
				build_id = 0
		else:
			build_id = 0
	else:
		# targeted spell card. Tap = keep aiming (two-stage); drag = cast at the
		# release point.
		if not _card_moved:
			return
		if _cast_spell_at(-dc, _pointer_world):
			aiming_spell = 0

# ---------------------------------------------------------------------------
# HUD callbacks
func request_build(id: int) -> void:
	aiming_spell = 0
	_set_selected(null)
	# re-pressing the active card cancels build mode
	build_id = 0 if build_id == id else id

func request_spell(id: int) -> void:
	if spell_cd.get(id, 0.0) > 0.0:
		return
	build_id = 0
	_set_selected(null)
	var def := GameData.spell_by_id(id)
	if def.target:
		# re-pressing the active spell cancels aiming
		aiming_spell = 0 if aiming_spell == id else id
	else:
		aiming_spell = 0
		_cast_spell_now(id)

func _cast_spell_at(id: int, pos: Vector2) -> bool:
	if Spells.cast(self, id, pos):
		_start_cd(id)
		return true
	return false

func _cast_spell_now(id: int) -> void:
	if Spells.cast(self, id, Vector2(540, 900)):
		_start_cd(id)

func _start_cd(id: int) -> void:
	var s := Meta.spell_stats(id)
	spell_cd[id] = s.get("cd", 10.0)

func set_speed_index(i: int) -> void:
	game_speed = float(SPEEDS[i % SPEEDS.size()])
	Engine.time_scale = game_speed

func cancel_modes() -> void:
	build_id = 0
	aiming_spell = 0
	_set_selected(null)

# ---------------------------------------------------------------------------
func _win() -> void:
	if ended: return
	ended = true
	Engine.time_scale = 1.0
	Audio.stop_bgm()
	Audio.play("jingle_win")
	if not Meta.is_cleared(level):
		Audio.play("jingle_first_clear")
	var award := Meta.on_level_cleared(level)
	Flow.last_result = {"win": true, "level": level, "kills": kills,
		"crystals": award.total, "base": award.base, "first": award.first,
		"replay": award.replay}
	for m in monsters:
		spawn_fx_orb(m.global_position, Color(0.7, 0.7, 0.9))
	_clear_field()
	get_tree().create_timer(0.6).timeout.connect(func(): Flow.goto(Flow.RESULT))

func _lose() -> void:
	if ended: return
	ended = true
	Engine.time_scale = 1.0
	Audio.stop_bgm()
	Audio.play("jingle_lose")
	var award := Meta.on_level_failed(level, kills, elapsed, boss_time, boss_best_frac)
	Flow.last_result = {"win": false, "level": level, "kills": kills,
		"crystals": award.crystals, "progress": award.progress, "cap": award.cap,
		"too_short": award.too_short, "boss_frac": award.boss_frac,
		"time": elapsed, "boss_reached": boss_spawned}
	get_tree().create_timer(0.2).timeout.connect(func(): Flow.goto(Flow.FAIL))

## Wipe the field once the run is decided. Monsters MUST be flagged dead before
## going back to the pool: a projectile still in the air lands after the result
## is locked in, and `is_instance_valid(target) and target.alive` used to be true
## for a pooled monster — so a post-victory arrow paid gold, bumped the kill
## count and pushed the same node into the free list a second time.
func _clear_field() -> void:
	for m in monsters:
		m.alive = false
		monster_pool.release(m)
	monsters.clear()
	boss_ref = null
	skeleton_boss_alive = null
	# in-flight ordnance and lingering ground effects have nothing left to hit
	for n in proj_root.get_children():
		if n.get("alive") != null:
			n.alive = false
			n.visible = false
			n.process_mode = Node.PROCESS_MODE_DISABLED
	for n in fx_root.get_children():
		if n is Hazard and n.alive:
			n.alive = false
			hazard_pool.release(n)


# ---------------------------------------------------------------------------
class _Scatter extends Node2D:
	## Cosmetic ground clutter (rocks / bones / grass / cracks) placed on a fixed
	## seed, only where it is clear of the road. Purely visual — placement logic
	## never consults these, so they can never block a tower.
	var route: PathRoute
	# weighted: small ground cover is common, landmarks are rare. A flat pick
	# over 10 names put ~12 red banners on screen, and red reads as "danger".
	const NAMES := ["rock1", "rock1", "rock2", "rock2", "grass", "grass",
		"grass", "crack", "crack", "bush", "bush", "pebbles", "pebbles",
		"bones", "skull", "stump", "banner"]

	func _ready() -> void:
		queue_redraw()

	func _draw() -> void:
		if route == null: return
		var rng := RandomNumberGenerator.new()
		rng.seed = 0xB0B5 ^ int(route.total)
		var texs := {}
		for n in NAMES:
			texs[n] = Assets.tile("deco_" + n)
		var placed := 0
		var tries := 0
		# denser clutter (46 -> 120): the old count left whole screens of bare
		# ground. Still off-road, still cosmetic.
		while placed < 120 and tries < 2600:
			tries += 1
			# stop above the HUD bars: clutter placed under them only ever showed
			# as fragments peeking through the gaps between cards
			var p := Vector2(rng.randf_range(40, 1040), rng.randf_range(150, 1560))
			# keep clear of the road corridor and the base
			if route.dist_to_route(p) < 74.0:
				continue
			if p.distance_to(route.pos_at(route.total - 20.0)) < 130.0:
				continue
			var nm: String = NAMES[rng.randi() % NAMES.size()]
			var tex: Texture2D = texs[nm]
			# INTEGER scales only — a random 0.7..1.35 gave every rock its own
			# pixel size, which is the same density mismatch the sprite scales had
			var sc: float = [2.0, 2.0, 2.0, 3.0][rng.randi() % 4]
			var sz: Vector2 = tex.get_size() * sc
			var a := 0.9 if nm != "crack" else 0.6
			draw_texture_rect(tex, Rect2(p - sz * 0.5, sz), false, Color(1, 1, 1, a))
			placed += 1


# ---------------------------------------------------------------------------
# Placement / spell-aim overlay: a translucent ghost that follows the pointer,
# green when placeable, red when not; and the spell's effect radius while aiming.
class _Placer extends Node2D:
	var battle
	var _was_idle := true

	func _process(_d: float) -> void:
		# only invalidate while a build/aim mode is actually up (plus one final
		# redraw to clear the ghost) — this ran every frame of every battle
		var idle: bool = battle == null or (battle.build_id == 0 and battle.aiming_spell == 0)
		if idle and _was_idle:
			return
		_was_idle = idle
		queue_redraw()

	func _draw() -> void:
		if battle == null:
			return
		if battle.build_id > 0:
			_draw_build_ghost()
		elif battle.aiming_spell > 0:
			_draw_spell_aim()

	func _draw_build_ghost() -> void:
		var def: Dictionary = GameData.tower_by_id(battle.build_id)
		var pos: Vector2 = battle.snap(battle._pointer_world)
		var affordable: bool = battle.gold >= int(def.place_cost)
		var ok: bool = affordable and battle.can_place(pos)
		var tint: Color = Color(0.35, 0.9, 0.45) if ok else Color(0.95, 0.32, 0.28)
		var rng: float = float(Meta.tower_stats(battle.build_id).range)
		# range preview
		draw_circle(pos, rng, Color(tint.r, tint.g, tint.b, 0.10))
		draw_arc(pos, rng, 0.0, TAU, 56, Color(tint.r, tint.g, tint.b, 0.85), 2.5)
		# ghost tower sprite
		var tex: Texture2D = Assets.tower(battle.build_id)
		var sz: Vector2 = tex.get_size() * GameData.TOWER_RENDER
		draw_texture_rect(tex, Rect2(pos - sz * 0.5, sz), false, Color(1, 1, 1, 0.55))
		# footprint disc for clarity
		draw_circle(pos, 10.0, Color(tint.r, tint.g, tint.b, 0.9))

	func _draw_spell_aim() -> void:
		var s: Dictionary = Meta.spell_stats(battle.aiming_spell)
		var pos: Vector2 = battle._pointer_world
		var r: float = float(s.get("radius", 130.0))
		var c := Color(1.0, 0.55, 0.95)
		draw_circle(pos, r, Color(c.r, c.g, c.b, 0.12))
		draw_arc(pos, r, 0.0, TAU, 56, Color(c.r, c.g, c.b, 0.85), 2.5)
		# crosshair
		draw_line(pos - Vector2(20, 0), pos + Vector2(20, 0), Color(1, 0.85, 1, 0.9), 2.0)
		draw_line(pos - Vector2(0, 20), pos + Vector2(0, 20), Color(1, 0.85, 1, 0.9), 2.0)


# ---------------------------------------------------------------------------
# Debug overlay (A): press F3 to toggle. Shows the recent input log (type,
# position, which node consumed it), the live placement state, the ghost world
# coord, and the can_place result + failure reason — so the next round of
# debugging can watch exactly where events go and why a spot reads red.
class _DbgOverlay extends Control:
	var battle
	var _lbl: Label
	var _bg: ColorRect

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		_bg = ColorRect.new()
		_bg.color = Color(0, 0, 0, 0.72)
		_bg.position = Vector2(12, 300)
		_bg.size = Vector2(1056, 560)
		_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_bg)
		_lbl = Label.new()
		_lbl.position = Vector2(28, 312)
		_lbl.add_theme_font_size_override("font_size", 26)
		_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_lbl)

	func _process(_d: float) -> void:
		if not visible or battle == null:
			return
		var sp: Vector2 = battle.snap(battle._pointer_world)
		var reason: String = battle.can_place_reason(sp)
		var mode := "none"
		if battle.build_id > 0:
			mode = "BUILD id=%d" % battle.build_id
		elif battle.aiming_spell > 0:
			mode = "AIM spell=%d" % battle.aiming_spell
		var lines := PackedStringArray()
		lines.append("=== DEBUG (F3) ===")
		lines.append("mode=%s  dragging_card=%d  moved=%s" %
			[mode, battle._dragging_card, battle._card_moved])
		lines.append("pointer_world=%s  snap=%s" % [battle._pointer_world.round(), sp.round()])
		lines.append("can_place=%s%s" %
			["GREEN" if reason == "" else "RED", "" if reason == "" else " (%s)" % reason])
		lines.append("cam pos=%s zoom=%.2f  gold=%d  towers=%d" %
			[battle.cam.position.round(), battle.cam.zoom.x, battle.gold, battle.towers.size()])
		lines.append("--- input log (newest last) ---")
		for e in battle._dbg:
			lines.append("%s  @%s  -> %s" % [e.t, (e.p as Vector2).round(), e.sink])
		_lbl.text = "\n".join(lines)
