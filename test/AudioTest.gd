extends Node
## Audio system checks.
##
##   B  bus layout — Master / BGM / SFX / UI exist and the sub-buses feed Master
##   R  routing — a sound's NAME decides its bus, so nothing can land on the
##      wrong slider by being called from the wrong place
##   S  settings — three sliders drive three buses, mute is Master, and a save
##      written before round 8 (no volume_bgm / volume_sfx) still loads
##   D  dedup — twenty towers firing on one frame produce ONE sound, not twenty
##      stacked copies
##   T  time scale — THE question this file exists to answer: 0.5x and 3x must
##      not slow down, speed up or detune the audio
##
## T needs a real audio driver to observe playback advancing. Under --headless
## the driver is a dummy and the case reports SKIP rather than passing quietly —
## run this windowed to actually answer it:
##   Godot --path . res://test/AudioTest.tscn

var fails := 0
var skips := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	await _case_buses()
	await _case_routing()
	await _case_registry()
	await _case_bar_align()
	await _case_bar_align_process()
	await _case_settings()
	await _case_dedup()
	await _case_time_scale()
	_restore_save()
	Meta.load_game()
	Meta.apply_audio_settings()
	# This test is the only thing that loads every stream at once; drop them so
	# the engine's exit-time leak report stays a real signal.
	Audio.stop_bgm()
	for c in Audio.get_children():
		if c is AudioStreamPlayer:
			c.stop()
			c.stream = null
	Audio._cache.clear()
	await _idle(3)     # let the audio server release the playbacks it still holds
	print("AUDIO %s fails=%d skips=%d"
		% ["PASS" if fails == 0 else "FAIL", fails, skips])
	_tree.quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------------------
func _case_buses() -> void:
	for name in ["Master", "BGM", "SFX", "UI"]:
		_ok("B bus %s 存在" % name, AudioServer.get_bus_index(name) >= 0,
			"bus %s missing from default_bus_layout.tres" % name)
	for name in ["BGM", "SFX", "UI"]:
		var i := AudioServer.get_bus_index(name)
		if i < 0:
			continue
		_ok("B %s -> Master" % name, AudioServer.get_bus_send(i) == "Master",
			"%s sends to %s" % [name, AudioServer.get_bus_send(i)])

func _case_routing() -> void:
	var want := {
		"ui_click": "UI", "ui_error": "UI", "ui_panel_open": "UI",
		"bgm_battle": "BGM",
		"sfx_atk_arrow": "SFX", "sfx_atk_beam": "SFX",
	}
	for s in want:
		_ok("R %s -> %s" % [s, want[s]], Audio.bus_for(s) == want[s],
			"got %s" % Audio.bus_for(s))
	# every generated file must resolve, or a call site is silently doing nothing
	var missing: Array = []
	for s in want:
		if Audio.stream(s) == null:
			missing.append(s)
	for e in Audio.TOWER_SOUND.values():
		if Audio.stream(String(e[0])) == null and not (String(e[0]) in missing):
			missing.append(String(e[0]))
	_ok("R 全部音效檔載到", missing.is_empty(), "missing: %s" % str(missing))

## 每張「事件 → 音名」表入面嘅每個名都要有實檔。呢個 case 存在嘅原因好具體:
## 改一個音名而唔改表,遊戲入面唯一嘅症狀係嗰個事件靜咗,而靜咗係冇人會即刻
## 發現嘅 bug。
func _case_registry() -> void:
	var names: Array = Audio.registered_sounds()
	_ok("G 註冊表非空", names.size() > 0, "registered_sounds() returned nothing")
	var missing: Array = []
	for n in names:
		if Audio.stream(String(n)) == null:
			missing.append(String(n))
	_ok("G 註冊咗嘅 %d 個音全部載到" % names.size(), missing.is_empty(),
		"missing: %s" % str(missing))

## 小節對齊嘅數學。呢個 case 存在嘅原因:真正嘅交接要有一個會推進嘅音訊驅動先
## 觀察到(headless 個 dummy 唔會),所以決定「幾時切」嗰條數獨立成純函數,
## 喺任何環境都答得到。切換本身嘅正確性 = 呢條數 + 一句 if,冇第三樣嘢。
func _case_bar_align() -> void:
	var meta := {"bpm": 132.0, "beats": 4, "bars": 8}
	var bar: float = Audio.bar_seconds(meta)
	_near("A 一個小節 = 60/132*4", bar, 1.8181818, 0.0005)
	_near("A 啱啱踩正線 -> 唔使等", Audio.time_to_bar(0.0, meta), 0.0, 0.0005)
	_near("A 小節中間 -> 等返差嗰段", Audio.time_to_bar(1.0, meta), bar - 1.0, 0.0005)
	_near("A 跨過一個小節之後照計", Audio.time_to_bar(bar + 0.5, meta), bar - 0.5, 0.0005)
	# 呢個係最重要嗰個:啱啱過線嘅位置絕對唔可以返一個完整小節,否則 boss 曲會
	# 白等成個小節先入,而個 bug 喺遊戲入面只會顯示為「有時慢咗」
	_ok("A 啱啱過線唔會白等成個小節",
		Audio.time_to_bar(bar * 2.0, meta) < 0.01,
		"got %.4f, want ~0" % Audio.time_to_bar(bar * 2.0, meta))
	# battle 同 boss 必須同 BPM,唔係「無縫」就係空話
	var b1: Dictionary = Audio.BGM_META.get("bgm_battle", {})
	var b2: Dictionary = Audio.BGM_META.get("bgm_boss", {})
	_ok("A battle / boss 同 BPM",
		not b1.is_empty() and not b2.is_empty()
		and is_equal_approx(float(b1.get("bpm", 0.0)), float(b2.get("bpm", -1.0))),
		"battle=%s boss=%s" % [str(b1), str(b2)])
	# 排隊之後未到線之前唔可以即刻換走
	Audio.play_bgm("bgm_battle")
	Audio.queue_bgm("bgm_boss")
	_ok("A 排咗隊但未切", Audio._bgm_pending == "bgm_boss" and Audio._bgm_name == "bgm_battle",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])
	Audio.stop_bgm()
	Audio._bgm_pending = ""

## `_process()` 有三個分支。呢度覆蓋到得兩個:
##   * 排咗隊但冇嘢喺度播 -> 即刻切(冇小節線可以等)
##   * 排咗隊,但而家播緊嘅嘢喺 BGM_META 度冇 entry -> 即刻切
## 第三個分支(排咗隊 + 有嘢播緊 + 有 meta -> 要等到 time_to_bar 落返
## BAR_SNAP 之內先切)需要一個真係郁得嘅播放位置,dummy 音訊驅動喺 headless
## 底下唔會推進 get_playback_position(),同 _case_time_scale() 嗰個限制一樣 ——
## 呢個分支冇喺呢度覆蓋到,要開窗聽先驗到。
func _case_bar_align_process() -> void:
	# 呢個 case 之前嘅 case(B/R/G/A 頭半嗰段)全部冇 await,即係呢度先係成個
	# 測試第一個真正嘅 yield 點 —— 引擎啟動時 Audio._process() 可能已經行過
	# 一次(喺 AudioTest._ready() 嗰段同步code 行到之前),所以要先 settle 一
	# 幀,先至保證跟住嗰句 await _idle(1) 對應嘅係「我哋啱啱改完 state 之後
	# 嘅第一個 _process」,唔係啱啱行完、仲未睇到新 state 嗰個。
	await _idle(1)
	# 分支一:冇嘢播緊 -> 即刻切
	Audio.stop_bgm()
	Audio.queue_bgm("bgm_battle")
	_ok("A 冇嘢播緊嘅前置條件", Audio._bgm_pending == "bgm_battle" and not Audio._bgm.playing,
		"pending=%s playing=%s" % [Audio._bgm_pending, Audio._bgm.playing])
	await _idle(1)
	_ok("A 冇嘢播緊 -> 即刻切",
		Audio._bgm_pending == "" and Audio._bgm_name == "bgm_battle",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])
	Audio.stop_bgm()

	# 分支二:有嘢播緊,但嗰個名喺 BGM_META 度冇 entry -> 即刻切
	Audio.play_bgm("sfx_atk_arrow")     # 借一個實際存在但唔喺 BGM_META 嘅音源
	Audio.queue_bgm("bgm_battle")
	_ok("A 播緊冇 meta 嘅嘢嘅前置條件",
		Audio._bgm_pending == "bgm_battle" and Audio.BGM_META.get(Audio._bgm_name, {}).is_empty(),
		"pending=%s now=%s meta=%s" % [Audio._bgm_pending, Audio._bgm_name,
			str(Audio.BGM_META.get(Audio._bgm_name, {}))])
	await _idle(1)
	_ok("A 播緊嘅嘢冇節奏 meta -> 即刻切",
		Audio._bgm_pending == "" and Audio._bgm_name == "bgm_battle",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])
	Audio.stop_bgm()
	Audio._bgm_pending = ""

func _case_settings() -> void:
	Meta.reset_save()
	Meta.set_audio_volume("volume", 0.5)
	Meta.set_audio_volume("volume_bgm", 0.25)
	Meta.set_audio_volume("volume_sfx", 1.0)
	_near("S 總音量 -> Master", db_to_linear(AudioServer.get_bus_volume_db(0)), 0.5, 0.02)
	_near("S 音樂 -> BGM",
		db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("BGM"))),
		0.25, 0.02)
	_near("S 音效 -> SFX",
		db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))),
		1.0, 0.02)
	_near("S 音效 -> UI (同一條 slider)",
		db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("UI"))),
		1.0, 0.02)
	# mute is Master, so it silences music and effects together
	Meta.settings["muted"] = true
	Meta.apply_audio_settings()
	_ok("S 靜音 = Master mute", AudioServer.is_bus_mute(0), "master not muted")
	Meta.settings["muted"] = false
	Meta.apply_audio_settings()

	# a pre-round-8 save has neither sub-bus key; it must load and sound the same
	Meta.settings = {"volume": 0.7, "muted": false, "locale": ""}
	Meta.save_game()
	Meta.load_game()
	_near("S 舊存檔補回 音樂", Meta.audio_volume("volume_bgm"), 1.0, 0.001)
	_near("S 舊存檔補回 音效", Meta.audio_volume("volume_sfx"), 1.0, 0.001)
	_near("S 舊存檔保留 總音量", Meta.audio_volume("volume"), 0.7, 0.001)

func _case_dedup() -> void:
	Meta.reset_save()
	var before := _playing_count("SFX")
	for i in 20:                       # one frame's worth of a saturated field
		Audio.play("sfx_atk_arrow")
	await _idle(1)
	var started := _playing_count("SFX") - before
	_ok("D 同幀 20 次只響一次", started <= 1, "%d players started" % started)

func _case_time_scale() -> void:
	# Long clip so there is something to measure against.
	var s := Audio.stream("bgm_battle")
	if s == null:
		_ok("T 有長音檔可以量", false, "bgm_battle missing")
		return
	var probe := AudioStreamPlayer.new()
	probe.bus = "BGM"
	probe.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(probe)
	probe.stream = s

	# Does this driver advance playback at all? Headless uses a dummy that does
	# not, and a silent pass there would be worse than no test.
	Engine.time_scale = 1.0
	probe.play()
	await _wait_real(0.25)
	var moved: float = probe.get_playback_position()
	probe.stop()
	if moved < 0.05:
		skips += 1
		print("AUDIO SKIP T 時間縮放 — 呢個音訊驅動唔會推進播放位置(headless dummy)。"
			+ "要答呢條要開窗跑:Godot --path . res://test/AudioTest.tscn")
		await _drop(probe)
		Engine.time_scale = 1.0
		return

	for scale in [0.5, 1.0, 3.0]:
		Engine.time_scale = scale
		probe.play()
		await _wait_real(0.40)
		var pos: float = probe.get_playback_position()
		probe.stop()
		# 0.40s of WALL CLOCK must be 0.40s of audio at every game speed
		_near("T time_scale=%.1f 播放位置跟真實時間" % scale, pos, 0.40, 0.09)
		_ok("T time_scale=%.1f 冇變調" % scale, is_equal_approx(probe.pitch_scale, 1.0),
			"pitch_scale=%f" % probe.pitch_scale)
	Engine.time_scale = 1.0
	await _drop(probe)

## Tearing the probe down cleanly, in order. stop() alone is not enough: the
## audio server still holds the AudioStreamPlayback until its next mix, so
## freeing the node in the same frame left a playback and its stream alive and
## Godot reported both as leaks at exit. Clear the stream, let a frame pass, then
## free.
func _drop(n: AudioStreamPlayer) -> void:
	n.stop()
	n.stream = null
	await _idle(2)
	remove_child(n)
	n.free()

# ---------------------------------------------------------------------------
func _playing_count(bus: String) -> int:
	var n := 0
	for c in Audio.get_children():
		if c is AudioStreamPlayer and c.bus == bus and c.playing:
			n += 1
	return n

## Wait `secs` of REAL time. get_tree().create_timer() is scaled by
## Engine.time_scale, which is exactly the variable under test here.
func _wait_real(secs: float) -> void:
	var until := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("AUDIO ok   %s" % label)
	else:
		fails += 1
		print("AUDIO FAIL %s — %s" % [label, detail])

func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol, "got %.4f want %.4f (tol %.3f)" % [got, want, tol])

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
