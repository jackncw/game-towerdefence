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
## 進化階級 1..3。喺 setup() 由 Meta 讀一次 —— 一場戰鬥入面唔會變,所以
## 逐幀問 Meta 係白做。塔卡、快捷槽同場上呢座塔一定係同一階。
var tier: int = 1

func t2() -> bool:
	return tier >= 2

func t3() -> bool:
	return tier >= 3

## 全部塔嘅輸出都經呢度。
##
## 聖光光環嘅「攻擊力加成」係全場性嘅,所以佢一定要喺**一個**地方乘,唔係
## 喺二十個 _fire_* 各自記得乘一次 —— 後者嘅失敗模式係「有三座塔冇食到光環
## 加成」,而嗰件事喺畫面上完全睇唔出,只會令玩家覺得嗰三座塔數值講大話。
func atk(v: float) -> float:
	return v * (1.0 + battle.holy_power_total + battle.warcry_power)

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
	place_cost = b.place_cost(int(def.id))
	tier = Meta.tower_tier(id)
	s = Meta.tower_stats(id)
	_read_axis_levels()
	range_val = s.range
	position = world_pos
	sprite.texture = Assets.tower(id, tier)
	_cd = 0.0
	heat = 0.0
	beam_ramp = 0.0
	_streak_target = null
	_streak = 0
	_shot_count = 0
	_void_charge = 0.0
	_rangefind = 0.0
	_rangefind_at = Vector2.ZERO
	_salvo_count = 0
	_pulse_count = 0
	_holy_timer = 0.0
	if mech == "curse":
		_build_sigil()
	elif mech == "holy":
		_build_pillar()
	if mech == "barracks":
		rally_dist = battle.route.nearest_dist_param(world_pos)
	if mech == "alchemy" and s.get("startgold", 0.0) > 0.0:
		battle.add_gold(battle.scale_gold(s.startgold), true)   # 一次過入賬,唔係涓滴收入

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
	_tick_holy_glow(delta)
	if mech == "holy" and t3():
		_proc_oracle(delta)
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
	# 揀中嗰座塔畫嘅係一個**唔郁**嘅射程圈,而揀中 / 唔揀中兩個時刻
	# `Battle._set_selected()` 已經各叫咗一次 `queue_redraw()` —— 逐幀再叫
	# 一次係重畫一個同上一幀一模一樣嘅圓。

# generic: needs a target
# MAX_SHOTS_PER_FRAME lets a very fast tower catch up when one frame covers
# several of its intervals. At 3x speed a frame is ~50ms of game time while a
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
#
# 上彈用 `_cd += period` 而唔係 `_cd = period`。
#
# `= period` 會將「今幀已經超咗幾多」直接掉咗,於是真正嘅週期永遠被向上取整
# 到下一個幀邊界。1x 一幀 16.7ms,誤差細到冇人見到;3x 一幀 50ms,一個 80ms
# 嘅週期就變成 100ms —— 慢咗 25%,而玩家大部分時間開緊 3x。
#
# 呢個專案已經修過同一個 bug 兩次(`_spawn_logic` 刷怪、`_proc_attack` 普通
# 攻擊),呢度係第三個現場:荊棘塔喺 3x 實測少咗 11.7% 傷害,0.5x 多咗 3.7%。
# 見 test/TimeScaleTest.gd。
func _proc_interval(delta: float, cb: Callable, _need: bool) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	var period: float = 1.0 / maxf(0.05, s.rate)
	var fired := 0
	while _cd <= 0.0 and fired < MAX_SHOTS_PER_FRAME:
		cb.call()
		_cd += period
		fired += 1
	if _cd < 0.0:
		_cd = 0.0

# --- 進化機制用嘅逐塔狀態 ----------------------------------------------------
## 連續命中同一目標嘅次數(鷹眼塔 / 多管火箭 / 鷹巢哨站)。
var _streak_target = null
var _streak: int = 0
## 開過幾多發(神射殿嘅「每第五箭」、末日發射井嘅「每第四次齊射」)。
var _shot_count: int = 0
var _salvo_count: int = 0
var _pulse_count: int = 0
## 虛空祭壇累積嘅獻祭能量。
var _void_charge: float = 0.0
## 軌道砲台嘅校射:同一片區域轟得越耐越準。
var _rangefind: float = 0.0
var _rangefind_at: Vector2 = Vector2.ZERO
## 神諭光柱嘅復甦計時。
var _holy_timer: float = 0.0

## 狙擊塔同導彈塔:射程內有支援型單位(巫師 / 大祭司)就先打佢。
## 呢兩座係全場淨係得佢哋夠遠打得到後排嘅武器,而後排治療者正正就係
## 令其他嘢殺唔死嘅原因 —— 見 Battle.target_support_first()。
func _acquire_target():
	if mech == "sniper":
		return battle.target_support_first(global_position, range_val,
			Callable(battle, "target_highest_hp"))
	if mech == "missile":
		return battle.target_support_first(global_position, range_val,
			Callable(battle, "target_closest_to_base"))
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
# The recoil used to be a Tween allocated per shot; 43 towers firing at 3x speed
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

## 連續命中同一目標嘅層數。鷹眼塔 (T2) 嘅新機制,亦都畀鷹巢哨站同多管火箭
## 共用 —— 三座都係「盯實一個目標」呢個主題嘅深化,所以佢哋數同一條數。
func _bump_streak(tgt) -> int:
	if tgt != _streak_target:
		_streak_target = tgt
		_streak = 0
	_streak = mini(_streak + 1, GameData.STREAK_MAX)
	return _streak

func _fire_arrow(tgt) -> void:
	# T2 鷹眼塔:連續命中疊加傷害,換目標歸零 —— 原本嘅「雙重射擊」係一個
	# 純機率,呢個係同一件事(打得密)嘅另一面,而且係玩家控制得到嗰面。
	var mult := 1.0 + (GameData.STREAK_STEP * (_bump_streak(tgt) - 1) if t2() else 0.0)
	var res := _crit_dmg(atk(s.dmg) * mult, s.crit, s.critmult)
	_shot_count += 1
	# T3 神射殿:每第五箭必定暴擊兼貫穿。
	var judgement: bool = t3() and _shot_count % GameData.SAGITTARIAN_EVERY == 0
	var dmg: float = res[0] * (s.critmult if judgement and not res[1] else 1.0)
	var pl := {"type": "phys", "dmg": dmg, "fx": "arrow"}
	if judgement:
		pl["pierce_line"] = true
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 900, true,
		Color(1, 1, 0.6) if not judgement else Color(1, 0.92, 0.45), 5 if not judgement else 8, pl, false)
	# T2 起「雙重射擊」變三連:同一次觸發最多再射兩發。
	var extra := 2 if t2() else 1
	for i in extra:
		if _roll(s.double):
			battle.spawn_projectile(global_position, tgt, tgt.global_position, 900, true,
				Color(1, 1, 0.6), 5, {"type": "phys", "dmg": dmg, "fx": "arrow"}, false)

func _fire_cannon(tgt) -> void:
	var pl := {"type": "phys", "dmg": atk(s.dmg), "splash": s.splash, "armorpen": s.armorpen, "fx": "cannon"}
	if _roll(s.knock):
		pl["knock"] = 55.0
	# T2 雙管砲塔:同一個落點爆兩次,第二下範圍更闊傷害減半。
	if t2():
		pl["double_blast"] = true
	# T3 攻城巨砲:破城彈,爆炸範圍內永久削甲(場內有效,可疊)。
	if t3():
		pl["armor_break"] = GameData.SIEGE_ARMOR_BREAK
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 520, false, Color(0.3, 0.3, 0.3), 9, pl, true)

func _fire_lightning(tgt) -> void:
	var chain := int(s.chain)
	var dmg: float = atk(s.dmg)
	var hit: Array = [tgt]
	var pts := PackedVector2Array([global_position, tgt.global_position])
	var cur = tgt
	for i in chain:
		# T2 雷霆之柱「導電」:上一發標記咗嘅目標優先接返條鏈,而且額外增傷。
		var nxt = null
		if t2() and is_instance_valid(_conductor) and _conductor.alive \
				and not hit.has(_conductor) \
				and cur.global_position.distance_to(_conductor.global_position) <= 260.0:
			nxt = _conductor
		if nxt == null:
			nxt = battle.nearest_other(cur.global_position, 160.0, hit)
		if nxt == null:
			break
		hit.append(nxt)
		pts.append(nxt.global_position)
		cur = nxt
	var d := dmg
	var last = tgt
	for m in hit:
		if not m.alive:
			continue        # an earlier link in the chain already killed it
		var bonus: float = GameData.CONDUCTOR_BONUS if (t2() and m == _conductor) else 0.0
		m.take_hit(d * (1.0 + bonus), "magic")
		if m.alive and _roll(s.stun):
			m.apply_stun(0.6)
		if m.alive:
			last = m
		d *= (1.0 - s.falloff)
	if t2():
		_conductor = tgt
	# T3 天罰穹頂:鏈尾再落一道雷,範圍傷害兼必定麻痺。
	if t3() and is_instance_valid(last) and last.alive:
		for m in battle.monsters_in_radius(last.global_position, GameData.SKYFALL_RADIUS, true):
			m.take_hit(dmg * GameData.SKYFALL_FRAC, "magic")
			if m.alive:
				m.apply_stun(GameData.SKYFALL_STUN)
		battle.spawn_line(PackedVector2Array([last.global_position + Vector2(0, -900),
			last.global_position]), Color(0.85, 0.95, 1.0), 9, 0.2)
		battle.spawn_fx_burst(last.global_position, GameData.SKYFALL_RADIUS, Color(0.7, 0.9, 1.0), 0.3)
	battle.spawn_line(pts, Color(0.6, 0.85, 1.0), 4, 0.15)

## T2 導電標記:上一發打中嘅目標,下一次連鎖優先經過佢。
var _conductor = null

func _fire_fireball(tgt) -> void:
	var burning: bool = tgt.burn_time > 0.0
	var pl := {"type": "magic", "dmg": atk(s.dmg), "fx": "fire",
		"effects": [{"kind": "burn", "dps": atk(s.burn), "dur": s.burndur}]}
	if burning and _roll(s.detonate):
		pl["splash"] = 60.0
		# T3 炎魔祭壇「烈焰連鎖」:引爆成功會將燃燒傳染畀爆炸範圍內所有敵人。
		if t3():
			pl["spread_burn"] = {"dps": atk(s.burn), "dur": s.burndur}
	# T2 煉獄塔「餘燼」:燒緊嘅嘢死喺邊,邊度就留一灘火。
	if t2():
		pl["ember"] = {"dps": atk(s.burn) * GameData.EMBER_DPS_FRAC,
			"dur": GameData.EMBER_DUR, "radius": GameData.EMBER_RADIUS}
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 650, true, Color(1, 0.5, 0.2), 8, pl, false)

func _fire_frost(tgt) -> void:
	var eff := [{"kind": "slow", "factor": s.slow, "dur": s.slowdur}]
	# T2 極寒塔「凍傷」:減速期間累積凍傷層,凍結成立嗰刻一次過爆成真傷。
	if t2():
		eff.append({"kind": "frostbite", "amount": atk(s.dmg) * GameData.FROSTBITE_FRAC})
	if _roll(s.freeze):
		eff.append({"kind": "freeze", "dur": 1.0})
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 800, true, Color(0.6, 0.9, 1.0), 6,
		{"type": "phys", "dmg": atk(s.dmg), "effects": eff, "fx": "ice"}, false)

## 「重傷」—— 中毒目標所受治療嘅減免。跟住「每層毒傷」一齊深化:嗰條軸本來
## 就係「毒得幾狠」,而重傷幅度係同一件事嘅另一面,所以佢唔值一條新軸。
##
## 跟嗰條軸嘅**等級**,唔係跟 s.pstack 嘅數值。數值會跟 tier 放大十六倍,
## 而重傷係一個百分比 —— 用數值嘅話一進化就直接撞封頂,即係進化順手偷埋
## 一條軸嘅投資。等級先係玩家真係買落去嗰樣嘢。
func _poison_heal_cut() -> float:
	return minf(GameData.POISON_HEALCUT_BASE
		+ GameData.POISON_HEALCUT_PER_PSTACK * float(axis_level("pstack")),
		GameData.POISON_HEALCUT_MAX)

## 某一條升級軸而家幾多級。喺 setup() 讀一次入 _axis_lv —— 一場戰鬥入面
## 升級等級唔會變,而 Meta.tower_levels() 每次都會 pad / trim 一個 Array。
var _axis_lv: Dictionary = {}

func axis_level(stat_name: String) -> int:
	return int(_axis_lv.get(stat_name, 0))

func _read_axis_levels() -> void:
	_axis_lv.clear()
	var levels: Array = Meta.tower_levels(id)
	for i in def.ups.size():
		if i < levels.size():
			_axis_lv[String(def.ups[i].stat)] = int(levels[i])

func _fire_poison(tgt) -> void:
	var pe := {"kind": "poison", "dmg": atk(s.pstack), "stacks": 1, "max": int(s.pmax), "dur": 4.0}
	# T3 腐化聖殿:毒層每滿一批,目標生命上限永久跌一截。
	if t3():
		pe["rot"] = GameData.ROT_MAXHP_FRAC
	var eff := [pe,
		{"kind": "healcut", "cut": _poison_heal_cut(), "dur": GameData.POISON_HEALCUT_DUR}]
	var pl := {"type": "true", "dmg": atk(s.dmg), "effects": eff, "fx": "poison"}
	if s.pburst > 0.0:
		pl["splash"] = s.pburst
	# T2 瘟疫塔:滿層嘅屍體會將整疊毒傳畀最近三隻。
	if t2():
		pl["plague"] = {"max": int(s.pmax), "dmg": atk(s.pstack),
			"targets": GameData.PLAGUE_TARGETS}
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 700, true, Color(0.5, 0.9, 0.2), 6, pl, false)

func _fire_sniper(tgt) -> void:
	# T2 鷹巢哨站「致命標記」:每次命中疊一層,層數越多下一發越痛,擊殺清空。
	var marks: int = (_bump_streak(tgt) - 1) if t2() else 0
	var base: float = atk(s.dmg) * (1.0 + GameData.MARK_STEP * marks)
	# T3 天罰狙擊台:處決線大幅提高,而且處決成功後下一發必定暴擊。
	var exec_line: float = s.execute * (GameData.JUDGEMENT_EXEC_MULT if t3() else 1.0)
	var res := _crit_dmg(base, s.crit if not _guaranteed_crit else 1.0, 2.2)
	_guaranteed_crit = false
	if exec_line > 0.0 and tgt.try_execute(exec_line):
		_streak_target = null
		_streak = 0
		if t3():
			_guaranteed_crit = true
		battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 0.9, 0.5), 3, 0.12)
		return
	tgt.take_hit(res[0], "phys")
	if not tgt.alive:
		_streak_target = null
		_streak = 0
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

var _guaranteed_crit: bool = false

func _fire_gatling(tgt) -> void:
	if tgt == last_target:
		heat = minf(s.heatmax, heat + s.heatrate)
	else:
		# T3 風暴壁壘「彈鏈共鳴」:換目標唔再清零,只係跌一半 —— 一座機槍塔
		# 最痛嘅唔係傷害係「每次目標死咗就由零開始」,呢個就係嗰個痛點。
		heat = heat * 0.5 if t3() else 0.0
	last_target = tgt
	# T3 熱度同時推高散射機率
	var spread_p: float = s.spread + (heat * GameData.RESONANCE_SPREAD if t3() else 0.0)
	var dmg: float = atk(s.dmg) * (1.0 + heat * 0.5)
	tgt.take_hit(dmg, "phys")
	battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]), Color(1, 0.95, 0.6), 2, 0.05)
	# T2 旋風機炮「過熱噴發」:熱度撞頂嗰一刻放一圈彈幕,然後熱度減半繼續。
	if t2() and heat >= s.heatmax - 0.0001:
		for o in battle.monsters_in_radius(global_position, range_val, true):
			o.take_hit(dmg * GameData.CYCLONE_BURST_FRAC, "phys")
		battle.spawn_fx_ring(global_position, range_val, Color(1, 0.9, 0.5))
		heat *= 0.5
	if _roll(spread_p):
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
	# T3 軌道砲台「校射」:連續轟同一片區域層層加成,換區歸零。
	var aim: Vector2 = tgt.global_position
	if t3():
		if aim.distance_to(_rangefind_at) <= GameData.RANGEFIND_RADIUS:
			_rangefind = minf(_rangefind + 1.0, GameData.RANGEFIND_MAX)
		else:
			_rangefind = 0.0
		_rangefind_at = aim
	var rf: float = _rangefind
	var pl := {"type": "phys", "dmg": atk(s.dmg) * (1.0 + GameData.RANGEFIND_DMG * rf),
		"splash": s.splash * (1.0 + GameData.RANGEFIND_AREA * rf), "fx": "cannon"}
	if s.scorch > 0.0:
		pl["effects"] = [{"kind": "burn", "dps": atk(s.dmg) * 0.15, "dur": s.scorch}]
	if s.frag > 0.0:
		pl["frag"] = int(s.frag)
	battle.spawn_projectile(global_position, null, aim, 480, false, Color(0.4, 0.45, 0.2), 10, pl, true)
	# T2 重砲陣地「齊射」:第二發打喺前後錯開嘅位,蓋住一條線唔係一個點。
	if t2():
		var along: Vector2 = (aim - global_position).normalized() * GameData.HEAVY_BATTERY_OFFSET
		battle.spawn_projectile(global_position, null, aim + along, 480, false,
			Color(0.4, 0.45, 0.2), 10, pl.duplicate(true), true)

func _fire_missile(tgt) -> void:
	var salvo := int(s.salvo)
	# T2 多管火箭「追蹤鎖定」:連續命中同一目標,該目標受到嘅導彈傷害層層升。
	var lock: float = 1.0 + (GameData.LOCKON_STEP * (_bump_streak(tgt) - 1) if t2() else 0.0)
	# T3 末日發射井:每第四次齊射改為一枚核心彈頭。
	_salvo_count += 1
	var doomsday: bool = t3() and _salvo_count % GameData.DOOMSDAY_EVERY == 0
	if doomsday:
		battle.spawn_projectile(global_position, tgt, tgt.global_position, 900, true,
			Color(1, 0.75, 0.35), 12,
			{"type": "phys", "dmg": atk(s.dmg) * lock * GameData.DOOMSDAY_DMG,
			 "splash": s.splash * GameData.DOOMSDAY_AREA, "bossmult": s.bossmult,
			 "knock": 90.0, "fx": "rocket"}, false)
		return
	for i in salvo:
		var pl := {"type": "phys", "dmg": atk(s.dmg) * lock, "splash": s.splash, "bossmult": s.bossmult, "fx": "rocket"}
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
	_anim_sigil()
	# T2 夢魘之環「恐懼」:光環入面嘅嘢定期俾人嚇退一小段路。
	if t2():
		_dread_t -= delta
		if _dread_t <= 0.0:
			_dread_t = GameData.DREAD_PERIOD
			for m in battle.monsters_in_radius(global_position, range_val, true):
				m.displace(GameData.DREAD_PUSH * (0.4 if m.is_boss else 1.0), false)
	# T3 虛空祭壇「獻祭」:光環入面嘅死亡累積能量,滿咗對全場引爆真傷。
	# 充能由 Battle.on_monster_killed 經 add_void_charge() 入賬。
	if t3() and _void_charge >= GameData.VOID_CHARGE_FULL:
		_void_charge = 0.0
		var burst: float = atk(s.curse) * GameData.VOID_BURST
		for m in battle.all_monsters():
			if m.alive:
				m.take_hit(burst, "true")
		battle.spawn_fx_burst(global_position, 400, Color(0.55, 0.25, 0.85), 0.6)
		battle.shake(10.0, 0.35)
		Audio.play("sfx_spell_blackhole")

var _dread_t: float = 0.0

## 虛空祭壇充能。Battle 喺一隻怪死喺光環入面嗰陣叫。
func add_void_charge(amount: float) -> void:
	if t3():
		_void_charge += amount

func _fire_holy(tgt) -> void:
	# T2 黎明聖壇:本塔對支援型敵人(巫師 / 大祭司)造成額外傷害 —— 全場
	# 光環嗰半係俾隊友嘅,呢半係佢自己嘅點名能力。
	var mult := 1.0 + (GameData.DAWN_SUPPORT_MULT if t2() and tgt.is_support() else 0.0)
	tgt.take_hit(atk(s.dmg) * mult, "magic")
	if s.purify > 0.0 and _roll(s.purify):
		tgt.haste_time = 0.0
	battle.spawn_projectile(global_position, tgt, tgt.global_position, 800, true, Color(1, 0.95, 0.7), 6, {"type": "magic", "dmg": 0.0, "fx": "holy"}, false)

func _fire_teleport(tgt) -> void:
	if _roll(s.tpchance):
		# 傳送真係成功嗰下先響 —— tpchance 唔中就冇嘢傳送過。displace 嗰個
		# 推撞聲要熄咗:同一件事已經有 sfx_teleport_hit 講緊,兩個聲疊住就
		# 變成「傳送」聽落似「傳送 + 被打」。
		# T3 時空樞紐「放逐」:有機會直接送返起點,次數由 cap 封住。
		if t3() and not tgt.is_boss and _banished < int(s.cap) and _roll(GameData.BANISH_CHANCE):
			_banished += 1
			tgt.displace(tgt.dist, false)
			battle.spawn_fx_ring(tgt.global_position, 70, Color(0.75, 0.5, 1.0))
		else:
			tgt.displace(s.tpdist, false)
		Audio.play("sfx_teleport_hit")
		# T2 空間裂隙「回溯」:傳送成功順手清走目標身上嘅增益。
		if t2():
			tgt.haste_time = 0.0
			tgt.haste_amp = 0.0
			tgt.enrage_time = 0.0
		if s.stun > 0.0:
			tgt.apply_stun(s.stun)
		battle.spawn_fx_ring(tgt.global_position, 40, Color(0.6, 0.3, 0.9))

var _banished: int = 0

func _fire_boomerang(tgt) -> void:
	var dir: Vector2 = (tgt.global_position - global_position).normalized()
	battle.spawn_boomerang(global_position, dir, range_val, atk(s.dmg), s.slow, s.returnmult)
	# T2 雙刃塔:第二把成夾角擲出,交叉點嘅敵人食兩次。
	if t2():
		battle.spawn_boomerang(global_position, dir.rotated(GameData.TWINBLADE_ANGLE),
			range_val, atk(s.dmg), s.slow, s.returnmult)
	# T3 風暴之輪「無盡迴旋」:有機會即刻再擲一次,唔消耗攻速。
	if t3() and _roll(GameData.TEMPEST_RETHROW * s.returnmult):
		battle.spawn_boomerang(global_position, dir.rotated(-GameData.TWINBLADE_ANGLE),
			range_val, atk(s.dmg), s.slow, s.returnmult)

# --- interval / continuous mechs -------------------------------------------
func _fire_alchemy() -> void:
	var g: float = s.gold
	# T2 鑄金坊「金線」:場上每多一座鍊金塔就加成,遞減疊加 —— 呢座塔本來
	# 係「擺邊都一樣」,而金線令佢第一次有咗擺位以外嘅陣容決策。
	if t2():
		var others: int = maxi(0, battle.alchemy_towers.size() - 1)
		var bonus := 0.0
		for i in others:
			bonus += GameData.FOUNDRY_STEP * pow(GameData.FOUNDRY_FALLOFF, i)
		g *= (1.0 + bonus)
	var paid: int = battle.scale_gold(g)
	battle.add_gold(paid)
	battle.spawn_damage(global_position + Vector2(0, -20), paid, Color(1, 0.85, 0.2))

func _fire_thorn() -> void:
	# T3 世界樹根:覆蓋範圍由一個圓變成沿住路面嘅一段路。
	var victims: Array = (battle.monsters_on_road_near(global_position,
		range_val * GameData.WORLDROOT_LENGTH) if t3()
		else battle.monsters_in_radius(global_position, range_val, false))
	var front = null
	for m in victims:
		m.take_hit(atk(s.dmg) * (1.0 + (s.heavymult if m.heavy else 0.0)), "true")
		if s.slow > 0.0:
			m.apply_slow(s.slow, 1.0)
		if s.bleed > 0.0:
			m.apply_poison(atk(s.bleed), 1, 5, 4.0)
		if m.alive and (front == null or m.dist > front.dist):
			front = m
	# T2 食人花巢「纏繞」:每次觸發把最前嗰隻短暫定身。內部冷卻由觸發率本身
	# 決定 —— 荊棘塔嘅 rate 就係佢嘅節奏,再加一個計時器就等於兩個節奏。
	if t2() and front != null:
		front.rooted_time = maxf(front.rooted_time, GameData.ENSNARE_DUR)

func _fire_magnet() -> void:
	_pulse_count += 1
	# T3 極性風暴「極性反轉」:每隔幾次脈衝改為吸引,把敵人拉成一團。
	var attract: bool = t3() and _pulse_count % GameData.POLARITY_EVERY == 0
	var caught: Array = battle.monsters_in_radius(global_position, range_val, true)
	for m in caught:
		var eff: float = 1.0 if not m.is_boss else s.heavyeff
		if attract:
			# 吸引 = 負推撞。displace() 只識推後,所以直接郁 dist。
			m.dist = minf(battle.route.total - 20.0, m.dist + s.knock * eff * 0.6)
			m.position = battle.route.pos_at(m.dist)
		else:
			m.displace(s.knock * eff)
		if s.pulse > 0.0:
			var dmg: float = atk(s.pulse)
			# T2 斥力核心「磁軌」:被推嘅敵人互相撞,擠得越密越痛。
			if t2():
				dmg *= (1.0 + GameData.RAILSLAM_STEP * mini(caught.size() - 1, GameData.RAILSLAM_MAX))
			m.take_hit(dmg, "phys")
		if s.knockslow > 0.0:
			m.apply_slow(s.knockslow, 1.0)
	battle.spawn_fx_ring(global_position, range_val,
		Color(0.5, 0.7, 1.0) if attract else Color(0.8, 0.5, 0.4))

func _proc_slowfield(delta: float) -> void:
	var caught := false
	for m in battle.monsters_in_radius(global_position, range_val, true):
		caught = true
		var f: float = s.slow * (s.bosseff if m.is_boss else 1.0)
		m.apply_slow(f, 0.2)
		if s.vuln > 0.0:
			m.apply_vuln(s.vuln, 0.3)
		# T2 重力井「牽引」:場內嘅嘢俾人慢慢拉返轉頭,飛行單位一樣中招。
		if t2():
			m.displace(GameData.GRAVITY_PULL * delta, false)
	# T3 時滯領域:每隔一段時間全場定身一瞬。
	if t3():
		_holy_timer -= delta
		if _holy_timer <= 0.0:
			_holy_timer = GameData.CHRONAL_PERIOD
			for m in battle.monsters_in_radius(global_position, range_val, true):
				m.apply_stun(GameData.CHRONAL_FREEZE)
			battle.spawn_fx_ring(global_position, range_val, Color(0.7, 0.85, 1.0))
	# 力場嘅「脈衝」聲接喺場入面真係有嘢俾佢緩到嗰陣,唔係接喺 s.pulse 嗰條
	# 傷害線度:pulse 係一個升級,基礎值 0,咁樣接嘅話絕大部分玩家嘅緩速塔
	# 由頭到尾都係啞嘅。空場唔響 —— 一個乜都冇困住嘅力場冇嘢好報。
	if caught:
		play_event_sound(mech)
	if s.pulse > 0.0:
		# 同 _proc_interval 一樣要累加,唔可以賦值 —— 見嗰度嘅註解。
		# 實測:緩速力場塔 T3 喺 3x 少咗 11.1% 傷害,0.5x 多咗 4.4%。
		_cd -= delta
		var period: float = 1.0 / maxf(0.1, s.pulserate)
		var pulses := 0
		while _cd <= 0.0 and pulses < MAX_SHOTS_PER_FRAME:
			_cd += period
			pulses += 1
			for m in battle.monsters_in_radius(global_position, range_val, true):
				m.take_hit(s.pulse, "magic")
			battle.spawn_fx_ring(global_position, range_val, Color(0.3, 0.8, 0.8))
		if _cd < 0.0:
			_cd = 0.0

## The beam is continuous, so it cannot key its sound off a shot. It re-triggers
## on its own timer while it has a target — tied to the clip length, not to the
## frame rate, or 3x would fire it 60 times a second into the dedup filter.
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
		_overload = 0.0
	last_target = tgt
	var dps: float = atk(s.dmg) * (1.0 + beam_ramp)
	# T3 恆星核心「聚能爆發」:蓄能撞頂就轉爆發模式,幾秒內傷害倍增,
	# 然後重置蓄能重新黎過 —— 光束塔嘅主題本來就係「蓄」,呢個係佢嘅頂點。
	if t3():
		if _overload > 0.0:
			_overload -= delta
			dps *= GameData.STELLAR_BURST_MULT
			if _overload <= 0.0:
				beam_ramp = 0.0
		elif beam_ramp >= s.rampmax - 0.0001:
			_overload = GameData.STELLAR_BURST_DUR
			battle.spawn_fx_ring(global_position, 90, Color(1, 0.95, 0.6))
	tgt.take_hit(dps * delta, "magic")
	# 融甲蝕魔:護甲同魔抗一齊削,唔再係轉成易傷。
	# 舊寫法(apply_vuln)對住一隻魔抗 25 嘅幽靈完全冇講到「你嘅魔法而家打得穿
	# 佢」呢件事 —— 佢只係將所有傷害乘大少少,而個問題係減免本身。
	if s.meltarmor > 0.0:
		tgt.apply_shred(s.meltarmor * GameData.BEAM_SHRED_ARMOR,
			s.meltarmor * GameData.BEAM_SHRED_MRES, GameData.BEAM_SHRED_DUR)
	battle.spawn_line(PackedVector2Array([global_position, tgt.global_position]),
		Color(1, 1, 0.7) if _overload <= 0.0 else Color(1, 0.85, 0.4),
		4 + beam_ramp * 2.0, 0.05)
	# T2 稜鏡塔「折射」:光束撞落目標之後彈去最近另一個敵人。
	if t2():
		var refr = battle.nearest_other(tgt.global_position, GameData.PRISM_RANGE, [tgt])
		if refr:
			refr.take_hit(dps * delta * GameData.PRISM_FRAC, "magic")
			battle.spawn_line(PackedVector2Array([tgt.global_position, refr.global_position]),
				Color(0.9, 1, 0.9), 3, 0.05)
	if s.dual > 0.0 and _roll(s.dual * delta):
		var o = battle.nearest_other(global_position, range_val, [tgt])
		if o: o.take_hit(dps * delta, "magic")

var _overload: float = 0.0

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
	var sd = battle.spawn_soldier(rally_dist + off, s.soldierhp, atk(s.dmg), s.armor, self)
	if sd:
		sd.formation = t2()      # T2 要塞營地「陣型」
		sd.death_blast = (atk(s.dmg) * GameData.TEMPLAR_BLAST) if t3() else 0.0
		soldiers.append(sd)
		# 號角響喺真係出到兵嗰下,唔係響喺「想出兵」嗰下 —— spawn_soldier() 返
		# null 就係冇兵出到,冇兵而有號角就係一個講大話嘅提示。
		play_event_sound(mech)

## T3 神諭光柱「復甦之光」。每隔一段時間為全場一座兵營補返一個士兵,並且
## 清走全場敵人嘅加速 —— 聖光塔本來就係「幫隊友」嗰座,呢個係佢嘅頂點:
## 佢唔再係加數字,佢係將已經輸咗嘅嘢攞返。
func _proc_oracle(delta: float) -> void:
	_holy_timer -= delta
	if _holy_timer > 0.0:
		return
	_holy_timer = GameData.ORACLE_PERIOD
	for m in battle.all_monsters():
		if m.alive:
			m.haste_time = 0.0
			m.haste_amp = 0.0
	for t in battle.towers:
		if is_instance_valid(t) and t.mech == "barracks" and t.soldiers.size() < int(t.s.count):
			t.respawn_timer = 0.0
			t._spawn_soldier()
			break
	battle.spawn_fx_ring(global_position, 220, Color(1, 0.96, 0.75))

func on_soldier_died(sd) -> void:
	soldiers.erase(sd)

func sell_value() -> int:
	return int(place_cost * 0.7)

## 聖光光環嘅表現。一個「全場受惠」嘅光環最大嘅風險係佢完全睇唔出 ——
## 冇範圍圈可以畫,而數字喺畫面上係隱形嘅。所以分兩邊講同一件事:
##
##   * 受惠嘅塔:塔身上一圈細細嘅金色微光粒子,強度跟住光環實際幾強。
##     喺**每一座**塔上面出現,先至讀得出「全場」呢個意思。
##   * 聖光塔本體:一條向上嘅光柱 —— 光源喺邊,睇一眼就知。
##
## 舊版:每座塔逐幀 `queue_redraw()` 再喺 `_draw()` 度畫三粒繞行光點 ——
## 四十三座塔 = 258 個 primitive 一幀,而且三粒點嘅大細/顏色/透明度**全場
## 一致**(k 只由 battle 嘅兩個全場光環總和決定),唯一唔同係位置。
##
## 所以受惠標記搬咗去 `Battle._tick_holy_motes()`,全場一個 MultiMesh 畫晒,
## 一個 draw call。塔呢邊淨返光柱 —— 佢只喺聖光塔本體出現,而家係兩個
## sprite,郁 scale / modulate,唔重畫。
var _holy_glow: float = 0.0
var _glow_phase: float = 0.0
var _pillar: Sprite2D = null
var _pillar_core: Sprite2D = null

func _build_pillar() -> void:
	_pillar = Sprite2D.new()
	_pillar.texture = Assets.fx("holy_pillar")
	_pillar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_pillar.scale = Vector2.ONE * FX_PX
	# 貼圖代表 world y = -190 .. -18,所以中心喺 -104
	_pillar.position = Vector2(0, -104.0)
	_pillar.z_index = -1
	_pillar.visible = false
	add_child(_pillar)
	_pillar_core = Sprite2D.new()
	_pillar_core.texture = Assets.fx("holy_core")
	_pillar_core.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_pillar_core.position = Vector2(0, -20.0)
	_pillar_core.z_index = -1
	_pillar_core.visible = false
	add_child(_pillar_core)

func _tick_holy_glow(delta: float) -> void:
	if _pillar == null:
		return
	var want: float = battle.holy_haste_total + battle.holy_power_total
	if want > 0.0:
		_glow_phase += delta
	_holy_glow = want
	var on: bool = want > 0.0
	_pillar.visible = on
	_pillar_core.visible = on
	if not on:
		return
	var pulse: float = 0.75 + 0.25 * sin(_glow_phase * 2.4)
	_pillar.modulate = Color(1, 1, 1, pulse)
	_pillar_core.scale = Vector2.ONE * (FX_PX * pulse)

func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, range_val, 0, TAU, 48, Color(1, 1, 1, 0.5), 3.0)
		draw_circle(Vector2.ZERO, range_val, Color(1, 1, 1, 0.06))

# ---------------------------------------------------------------------------
# 詛咒塔地面符文陣(合批輪重寫)
# ---------------------------------------------------------------------------
## Always-visible ground sigil for the 詛咒塔 aura: a violet haze disc, two
## counter-rotating rune rings and a pulsing rim, so the player can see which
## stretch of road is buffed without having to select the tower.
##
## 舊版係喺 `_draw()` 逐幀畫返晒出嚟:兩隻碟 + 一個 52 段嘅弧 + 兩圈共 13 條
## 線 13 粒點 + 一粒金點 ≈ 每座塔每幀 90 個 primitive,而每一個 polygon 喺
## Godot 嘅 2D renderer 度都係自己一個 draw call(rect 先批得埋)。量到光係
## 塔身上嘅光環(詛咒 + 聖光)就佔咗高峰戰鬥 1053 個 draw call 入面嘅 259 個。
##
## 而家:形狀全部預繪成貼圖,一座塔 = 15 個 sprite + 1 個弧,而且**冇一個
## 需要逐幀重畫** —— 旋轉係 `Node2D.rotation`、脈動係 `modulate.a`,兩樣都
## 唔會令 CanvasItem 變 dirty。15 個 sprite 共用同一張圖,所以合埋一個 batch。
const CURSE_VIOLET := Color(0.62, 0.26, 0.86)
## 貼圖入面嗰條符文劃烘死咗嘅 alpha —— 遊戲側除返佢先乘返真正嘅脈動值。
const RUNE_BAKED_ALPHA := 0.80
## 光環外圈嗰個弧烘死咗嘅 alpha(0.42 + 0.22 嘅上限)。
const RIM_BAKED_ALPHA := 0.64
## curse_haze.png 代表嘅 world 半徑。
const HAZE_TEX_R := 128.0
## fx 貼圖統一 4 texture px = 1 world px。
const FX_PX := 0.25

var _sigil: Node2D = null
var _sigil_haze: Sprite2D = null
var _sigil_rings: Array[Node2D] = []
var _sigil_mote: Sprite2D = null
var _sigil_rim: CanvasItem = null

func _build_sigil() -> void:
	_sigil = Node2D.new()
	# 相對 z = -1 → 實際 z 14:喺塔身(15)同怪物(20)之下,同舊版一樣壓喺
	# 地面。而且全場所有符文陣一齊落喺 z 14 呢個桶,所以佢哋批得埋一齊。
	_sigil.z_index = -1
	add_child(_sigil)
	var r: float = range_val

	_sigil_haze = Sprite2D.new()
	_sigil_haze.texture = Assets.fx("curse_haze")
	_sigil_haze.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sigil_haze.scale = Vector2.ONE * (r / HAZE_TEX_R)
	_sigil.add_child(_sigil_haze)

	var rune := Assets.fx("curse_rune")
	for ring in 2:
		var holder := Node2D.new()
		_sigil.add_child(holder)
		_sigil_rings.append(holder)
		var rr: float = r * (0.78 if ring == 0 else 0.46)
		var n: int = 8 if ring == 0 else 5
		for i in n:
			var a: float = TAU * i / float(n)
			var s := Sprite2D.new()
			s.texture = rune
			s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			s.scale = Vector2.ONE * FX_PX
			s.position = Vector2(cos(a), sin(a)) * rr
			s.rotation = a
			holder.add_child(s)

	_sigil_mote = Sprite2D.new()
	_sigil_mote.texture = Assets.fx("curse_mote")
	_sigil_mote.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sigil_mote.scale = Vector2.ONE * FX_PX
	_sigil.add_child(_sigil_mote)

	# 外圈嗰個脈動光環仍然係一條真弧 —— 一條 3px 闊嘅線放大就會變粗,而
	# 詛咒塔嘅射程係課得上去嘅,即係一張烘死嘅光環貼圖會跟住射程變肥。
	# 一個弧 = 一個 draw call,而場上詛咒塔數得出,呢個代價買返一個完全
	# 一樣嘅外觀。佢畫一次就唔再重畫,脈動行 modulate。
	_sigil_rim = _CurseRim.new()
	(_sigil_rim as _CurseRim).radius = r
	_sigil.add_child(_sigil_rim)
	_anim_sigil()

## 符文陣嘅動畫。全部都係 node property —— 冇一句 queue_redraw。
func _anim_sigil() -> void:
	if _sigil == null:
		return
	var r: float = range_val
	var pulse: float = 0.5 + 0.5 * sin(_aura_phase * 1.6)
	var rune_a: float = (0.55 + 0.25 * pulse) / RUNE_BAKED_ALPHA
	for ring in _sigil_rings.size():
		_sigil_rings[ring].rotation = _aura_phase * (0.35 if ring == 0 else -0.55)
		_sigil_rings[ring].modulate = Color(1, 1, 1, rune_a)
	_sigil_rim.modulate = Color(1, 1, 1, (0.42 + 0.22 * pulse) / RIM_BAKED_ALPHA)
	var gy: float = fmod(_aura_phase * 26.0, r * 0.7)
	_sigil_mote.position = Vector2(sin(_aura_phase * 1.1) * r * 0.3, r * 0.35 - gy)
	_sigil_mote.modulate = Color(1, 1, 1, 0.55 * (1.0 - gy / maxf(1.0, r * 0.7)))

## 光環外圈。一個只畫一次嘅 CanvasItem。
class _CurseRim extends Node2D:
	var radius: float = 100.0
	func _draw() -> void:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 52,
			Color(Tower.CURSE_VIOLET.r, Tower.CURSE_VIOLET.g, Tower.CURSE_VIOLET.b,
				Tower.RIM_BAKED_ALPHA), 3.0, true)
