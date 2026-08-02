extends Node
## 3x-speed stress test: full tower field + continuous spawns + boss, running at
## Engine.time_scale=3 with vsync/fps-cap OFF so the sampled FPS reflects true
## render+sim headroom.
##
## 效能目標:**3x boss 戰 >= 55fps**。第十一輪之前呢個目標係喺 5x 度定嘅,而
## 5x 已經冇咗(見 Battle.SPEEDS)—— 一個量度一個唔再存在嘅場景嘅門檻,量到
## 幾多都唔關出街嗰個遊戲事。
##   Godot --path . tools/perf3x.tscn

## Two modes (pick with a command-line flag after `--`):
##   (default)   uncapped — measures raw headroom.
##   --budget30  caps the renderer at 30fps and counts DROPPED frames, i.e. the
##               low-end-device question: "given a 33.3ms budget, does anything
##               blow through it?" Uncapped average fps says nothing about that.
var battle
var _samples: Array = []
var _spikes := 0            # frames that overran the budget (budget mode)
var _frames := 0
var _worst_ms := 0.0
var _budget_mode := false
var _warm := 2.5            # longer warm-up: the first ~1s is shader/pipeline
                            # compilation for fx kinds that have not been drawn
                            # yet, which used to dominate the reported minimum
var _run := 12.0            # real seconds of measured window
var _peak_monsters := 0

func _ready() -> void:
	_budget_mode = "--budget30" in OS.get_cmdline_user_args() or "--budget30" in OS.get_cmdline_args()
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 30 if _budget_mode else 0
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Flow.selected_level = 5
	# hard safety: never hang past ~20s real time
	# ignore_time_scale=true: under a raised time_scale a plain SceneTreeTimer fires
	# proportionally early, which silently cut every measurement window short.
	get_tree().create_timer(40.0, true, false, true).timeout.connect(_report)
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.gold = 999999
	# keep the stress running: never let win/lose navigate away mid-measure
	battle.boss_time = 1.0e9
	battle.base_shield = 1000000
	# fill the field with a broad mix of towers
	var ids := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 16, 12, 18]
	var k := 0
	for gx in range(2, 13):
		for gy in range(4, 22):
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos):
				battle.place_tower(ids[k % ids.size()], pos)
				k += 1
	# a heavy standing crowd + a boss
	for i in 46:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 1 + i % 5, false, 200.0 + i * 22.0)
	Engine.time_scale = 3.0
	print("PERF: towers=", battle.towers.size(), " starting monsters=", battle.monsters.size())

func _process(delta: float) -> void:
	# keep the field saturated: constant spawns + periodic AoE spell casts (worst
	# case for FX/particle volume)
	# Hold a SATURATED field. The old target (top up to 40) only reached ~130
	# monsters because slime cascades inflated it; once the balance pass tamed the
	# split, the same harness measured a 50-monster field and the fps numbers
	# stopped being comparable across rounds. Target the population explicitly.
	if battle and battle.monsters.size() < 130:
		for i in 8:
			battle._spawn_monster(GameData.FAMILY_ORDER[i % GameData.FAMILY_ORDER.size()], 3, false, 120.0)
	_peak_monsters = maxi(_peak_monsters, battle.monsters.size() if battle else 0)
	if _warm > 0.0:
		_warm -= delta / Engine.time_scale
		return
	_samples.append(Engine.get_frames_per_second())
	# real wall-clock frame time (delta is scaled by time_scale)
	var ms: float = (delta / Engine.time_scale) * 1000.0
	_frames += 1
	_worst_ms = maxf(_worst_ms, ms)
	if _budget_mode and ms > 33.3 * 1.5:
		_spikes += 1
	_run -= delta / Engine.time_scale
	if _run <= 0.0:
		_report()

var _done := false
func _report() -> void:
	if _done:
		return
	_done = true
	Engine.time_scale = 1.0
	var n := _samples.size()
	if n == 0:
		print("PERF: no samples"); get_tree().quit(); return
	var sum := 0.0
	var mn := 100000.0
	_samples.sort()
	for f in _samples:
		sum += f
		mn = minf(mn, f)
	var avg := sum / n
	# percentiles (worst sustained) rather than a single outlier min
	var p1: float = _samples[int(n * 0.01)]
	var p5: float = _samples[int(n * 0.05)]
	var med: float = _samples[int(n * 0.5)]
	print("PERF RESULT @3x%s  avg_fps=%.1f  med=%.1f  p5=%.1f  p1=%.1f  min=%.1f  worst_frame=%.1fms  peak_monsters=%d  towers=%d  samples=%d" %
		["(30fps budget)" if _budget_mode else "", avg, med, p5, p1, mn,
		_worst_ms, _peak_monsters, battle.towers.size(), n])
	if _budget_mode:
		print("PERF BUDGET  dropped_frames=%d / %d  (%.2f%%)  budget=33.3ms" %
			[_spikes, _frames, 100.0 * float(_spikes) / maxf(1.0, float(_frames))])
	Engine.time_scale = 1.0
	get_tree().quit()
