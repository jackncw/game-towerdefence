extends Node
## 合批輪嘅量度尺:一幀入面有幾多個 draw call。
##
## 點解要一個新 harness 而唔係加喺 perf3x 度:perf3x 量嘅係 fps,而 fps 喺一部
## 開發機上面會被 CPU 側嘅模擬掩蓋住 —— 一個由 1200 個 draw call 跌到 250 個嘅
## 改造喺 fps 度可能只係郁咗幾個字,但喺一部靠 tile-based GPU 嘅電話度嗰個先係
## 發熱嘅主因。所以呢一輪嘅成敗指標係 draw call,唔係 fps。
##
## 三個場景,同一把尺:
##   --scene=menu    主選單(靜態 UI,量 UI 側嘅底線)
##   --scene=battle  普通戰鬥(12 座塔 / 約 30 隻怪 / 1x)
##   --scene=peak    高峰戰鬥(40 座塔 / 130 隻怪 / 3x / 連環魔法)
##
## 用法(**一定要開窗**:headless 冇 GPU,所有 RENDER_* monitor 都係 0):
##   Godot --path . tools/drawcalls.tscn --log-file <log> -- --scene=peak --tag=before

const ArtExport := preload("res://tools/art_export.gd")

var mode := "peak"
var seconds := 8.0
var warm := 2.5
var tag := ""
## 拆解用:收起一組 node 再量一次,兩次之差就係嗰組嘅 draw call。
## 例:--hide=hud  /  --hide=monsters,towers
var hide_list: PackedStringArray = PackedStringArray()
## peak 場景擺幾多座塔。0 = 鋪滿(第十八輪 TOWER_SPACING 72 之下大約 90 座)。
## 第十四輪嘅 peak 基線係「鋪滿 = 40 座」(嗰陣間距 78 > 格距 74,棋盤格),
## 所以要同嗰條基線對數就要 --towers=40。
var tower_cap := 0
var battle = null

var _draw: Array[float] = []
var _obj: Array[float] = []
var _prim: Array[float] = []
var _ms: Array[float] = []
var _peak_monsters := 0
var _peak_fx := 0
var _spell_t := 0.0
var _done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			mode = a.substr(8)
		elif a.begins_with("--seconds="):
			seconds = maxf(2.0, float(a.substr(10)))
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a.begins_with("--hide="):
			hide_list = a.substr(7).split(",")
		elif a.begins_with("--towers="):
			tower_cap = int(a.substr(9))
	# 量度要睇真正嘅 render 成本,所以解封頂 —— 60fps cap 之下每一幀都會等,
	# frame time 就淨係反映個 cap。draw call 唔受影響,但 ms 會。
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.crystals = 999999
	seed(20260803)
	get_tree().create_timer(90.0, true, false, true).timeout.connect(_report)
	match mode:
		"menu": await _setup_menu()
		"battle": await _setup_battle(12 if tower_cap <= 0 else tower_cap, 30, 1.0)
		_: await _setup_peak()

func _setup_menu() -> void:
	add_child(load(Flow.MAIN_MENU).instantiate())
	for i in 10:
		await get_tree().process_frame

## 普通戰鬥:一個真人喺第 5 關中段會見到嘅密度。
func _setup_battle(n_towers: int, n_mon: int, ts: float) -> void:
	await _make_battle(n_towers, n_mon)
	Engine.time_scale = ts

## 高峰戰鬥:同 perf3x 一模一樣嘅合成負載,所以兩把尺量緊同一個場景。
func _setup_peak() -> void:
	await _make_battle(999 if tower_cap <= 0 else tower_cap, 46)
	Engine.time_scale = 3.0

func _make_battle(cap: int, n_mon: int) -> void:
	var tower_cap := cap
	Flow.selected_level = 5
	battle = load(Flow.BATTLE).instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.gold = 999999
	battle.boss_time = 1.0e9
	battle.base_shield = 1000000
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 16, 12, 18]
	var k := 0
	for gx in range(2, 13):
		for gy in range(4, 22):
			if k >= tower_cap:
				break
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos):
				battle.place_tower(ids[k % ids.size()], pos)
				k += 1
	for i in n_mon:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()],
			1 + i % 5, false, 200.0 + i * 22.0)
	for i in 6:
		await get_tree().process_frame
	_apply_hides()

func _apply_hides() -> void:
	for h in hide_list:
		match h:
			"hud": battle.hud.visible = false
			"monsters": battle.monsters_root.visible = false
			"towers": battle.towers_root.visible = false
			"fx": battle.fx_root.visible = false
			"proj": battle.proj_root.visible = false
			"env":
				for c in battle.get_children():
					if c is TextureRect or c is Line2D or c is Sprite2D:
						c.visible = false
			"deco":
				for c in battle.get_children():
					if c is CanvasItem and (c as CanvasItem).z_index == -14:
						c.visible = false

func _process(delta: float) -> void:
	var real: float = delta / maxf(0.001, Engine.time_scale)
	if battle != null and mode == "peak":
		if battle.monsters.size() < 130:
			for i in 8:
				battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 3, false, 120.0)
		# 魔法係 fx 體積嘅最壞情況,所以高峰場景要有魔法喺度放
		_spell_t -= real
		if _spell_t <= 0.0:
			_spell_t = 0.6
			_cast_something()
	elif battle != null and mode == "battle":
		if battle.monsters.size() < 30:
			battle._spawn_monster(GameData.FAMILY_ORDER[battle.monsters.size() % GameData.FAMILY_ORDER.size()], 2, false, 120.0)
	if battle != null:
		_peak_monsters = maxi(_peak_monsters, battle.monsters.size())
		_peak_fx = maxi(_peak_fx, battle.fx_pool.live_count())
	if warm > 0.0:
		warm -= real
		return
	_draw.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_obj.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	_prim.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	_ms.append(real * 1000.0)
	seconds -= real
	if seconds <= 0.0:
		_report()

var _spell_i := 0
func _cast_something() -> void:
	var picks := [1, 2, 3, 4, 5, 6, 7]
	var sid: int = picks[_spell_i % picks.size()]
	_spell_i += 1
	var p := Vector2(540.0 + sin(_spell_i) * 220.0, 700.0 + cos(_spell_i * 1.7) * 380.0)
	Spells.cast(battle, sid, p)

func _report() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	if _draw.is_empty():
		print("DRAWCALLS: no samples")
		get_tree().quit(1)
		return
	var texmb: float = Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0
	print("DRAWCALLS mode=%s tag=%s  draw_avg=%.0f draw_p95=%.0f draw_max=%.0f | obj_avg=%.0f prim_avg=%.0f | ms_avg=%.2f ms_p95=%.2f | texmem=%.2fMB | monsters=%d towers=%d fx_live=%d samples=%d" % [
		mode, tag, _avg(_draw), _p95(_draw), _mx(_draw), _avg(_obj), _avg(_prim),
		_avg(_ms), _p95(_ms), texmb, _peak_monsters,
		battle.towers.size() if battle != null else 0, _peak_fx, _draw.size()])
	get_tree().quit(0)

func _avg(a: Array[float]) -> float:
	var s := 0.0
	for v in a:
		s += v
	return s / maxf(1.0, float(a.size()))

func _p95(a: Array[float]) -> float:
	var b := a.duplicate()
	b.sort()
	return b[mini(b.size() - 1, int(b.size() * 0.95))]

func _mx(a: Array[float]) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, v)
	return m
