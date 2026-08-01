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
##   T  time scale — THE question this file exists to answer: 0.5x and 5x must
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

	for scale in [0.5, 1.0, 5.0]:
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
