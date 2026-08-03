extends Node
## 稜鏡塔假說探針。
##
## 上一輪嘅症狀:3x 之下稜鏡塔(光束塔 T2)嘅折射光束望落好似冇出現,玩家讀
## 成「呢座塔冇傷害」。Harness 已經證實傷害正常,所以假說係**渲染層**嘅:
##
##   3x 之下每秒生成嘅特效數量係 1x 嘅三倍 → fx pool 打正 400 個上限 →
##   `Battle.spawn_line()` 喺 pool 滿嗰陣靜靜 `return` → 光束冇畫出嚟。
##
## 呢個探針就係去攞嗰個「靜靜 return」嘅次數。有數 = 假說成立。
##
## 用法(要開窗,要 GPU;headless 都跑得,但 draw call 側嘅數會係 0):
##   Godot --path . tools/prism_probe.tscn --log-file qa/bench/drawcalls/prism-before.log \
##         -- --tag=before

## 折射光束嘅顏色(Tower._proc_beam 入面 T2 嗰條)。
const PRISM_COL := Color(0.9, 1.0, 0.9)
## 主光束嘅顏色。
const BEAM_COL := Color(1.0, 1.0, 0.7)

var battle
var tag := ""
var _run := 10.0
var _warm := 2.0
var _frames := 0
var _prism_frames := 0
var _prism_max := 0
var _beam_frames := 0
var _recycle := true
var _spell_t := 0.0
var _spell_i := 0
var _fx_peak := 0
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--norecycle":
			_recycle = false
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	# 光束塔進化到第二階 = 稜鏡塔,先至有折射嗰條線
	Meta.tower_tiers = {"10": 2}
	seed(20260803)
	Flow.selected_level = 5
	get_tree().create_timer(60.0, true, false, true).timeout.connect(_report)
	battle = load(Flow.BATTLE).instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.gold = 999999
	battle.boss_time = 1.0e9
	battle.base_shield = 1000000
	battle.fx_recycle = _recycle
	# 一半光束塔(要佢哋不斷放折射線),一半係火星大戶(機槍 / 磁力 / 加農 /
	# 閃電)—— 假說講嘅正正就係後者食晒名額令前者冇位。
	var ids := [10, 10, 8, 2, 3, 18, 10, 8]
	var k := 0
	for gx in range(2, 13):
		for gy in range(4, 22):
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos):
				battle.place_tower(ids[k % ids.size()], pos)
				k += 1
	for i in 46:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()],
			1 + i % 5, false, 200.0 + i * 22.0)
	Engine.time_scale = 3.0
	print("PRISM: towers=%d beam_towers=%d" % [battle.towers.size(), _count_beam()])

func _count_beam() -> int:
	var n := 0
	for t in battle.towers:
		if t.mech == "beam":
			n += 1
	return n

func _process(delta: float) -> void:
	var real: float = delta / maxf(0.001, Engine.time_scale)
	if battle.monsters.size() < 130:
		for i in 8:
			battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 3, false, 120.0)
	# 魔法係 fx 體積嘅最壞情況,而玩家喺 boss 戰正正就係連環放 —— 唔放魔法
	# 嘅話 pool 根本去唔到 400,即係量緊一個玩家唔會遇到嘅輕鬆情境。
	_spell_t -= real
	if _spell_t <= 0.0:
		_spell_t = 0.6
		_spell_i += 1
		Spells.cast(battle, [1, 2, 3, 4, 5, 6, 7][_spell_i % 7],
			Vector2(540.0 + sin(_spell_i) * 220.0, 700.0 + cos(_spell_i * 1.7) * 380.0))
	_fx_peak = maxi(_fx_peak, battle.fx_pool.live_count())
	if _warm > 0.0:
		_warm -= real
		return
	_frames += 1
	var prism := 0
	var beam := 0
	for n in battle.fx_pool.live_nodes():
		var f: Fx = n
		if f.kind != Fx.Kind.LINE:
			continue
		if _same(f.col, PRISM_COL):
			prism += 1
		elif _same(f.col, BEAM_COL):
			beam += 1
	if prism > 0:
		_prism_frames += 1
	if beam > 0:
		_beam_frames += 1
	_prism_max = maxi(_prism_max, prism)
	_run -= real
	if _run <= 0.0:
		_report()

func _same(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.02 and absf(a.g - b.g) < 0.02 and absf(a.b - b.b) < 0.02

func _report() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	var rj: Dictionary = battle.fx_rejected
	print("PRISM RESULT tag=%s frames=%d | rejected line=%d ring=%d burst=%d orb=%d spark=%d | recycled=%d | prism_visible_frames=%d (%.1f%%) prism_max=%d | beam_visible_frames=%d (%.1f%%) | fx_peak=%d" % [
		tag, _frames, int(rj["line"]), int(rj["ring"]), int(rj["burst"]),
		int(rj["orb"]), int(rj["spark"]), battle.fx_recycled,
		_prism_frames, 100.0 * float(_prism_frames) / maxf(1.0, float(_frames)),
		_prism_max,
		_beam_frames, 100.0 * float(_beam_frames) / maxf(1.0, float(_frames)),
		_fx_peak])
	get_tree().quit(0)
