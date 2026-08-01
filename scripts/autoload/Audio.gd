extends Node
## Central sound playback. Every sound in the game goes through Audio.play().
##
## Bus routing comes from the NAME, not from the call site, so a sound can never
## end up on the wrong slider: `ui_*` -> UI, `bgm_*` -> BGM, everything else ->
## SFX. That contract is shared with tools/gen_audio.py, which produces the files.
##
## Two things this has to survive that a naive "instantiate a player and
## queue_free it" version does not:
##
##   * 5x speed. A busy field fires dozens of shots per frame. Players are
##     POOLED (no allocation per shot) and identical sounds are DE-DUPLICATED
##     inside DEDUP_MS, so twenty arrow towers firing on the same frame produce
##     one arrow sound at full volume instead of twenty stacked copies that
##     clip the master bus.
##   * Engine.time_scale. Audio is mixed on its own thread and is deliberately
##     NOT given a time-scaled pitch — 0.5x must not detune the game. The only
##     pitch variation applied is the small random spread below, which exists to
##     stop repeated shots sounding like a machine.

const DIR := "res://assets/generated_audio/"
const DEDUP_MS := 60          # real milliseconds, never scaled
const POOL_SIZE := {"SFX": 12, "UI": 4}
const PITCH_SPREAD := 0.06    # +-6% so repeats do not sound mechanical

var _cache: Dictionary = {}          # name -> AudioStream
var _pool: Dictionary = {}           # bus -> Array[AudioStreamPlayer]
var _next: Dictionary = {}           # bus -> round-robin index
var _last_ms: Dictionary = {}        # name -> Time.get_ticks_msec of last start
var _bgm: AudioStreamPlayer
var _bgm_name: String = ""
var _missing: Dictionary = {}        # names already warned about

## Tower attack sounds. Twenty towers share SIX synthesised archetypes, each
## re-pitched — a distinct sample per tower would be twenty near-identical blips
## and twenty things to keep in tune with each other, while pitch alone already
## separates 狙擊塔 (heavy, low) from 機槍塔 (fast, high) on the same thwip.
##
## 兵營塔 / 詛咒塔 / 緩速力場塔 are absent on purpose: none of them has a discrete
## attack to sync a sound to (a spawn, an aura, a field). They get their own
## sounds with the rest of the set.
const TOWER_SOUND := {
	"arrow":     ["sfx_atk_arrow", 1.00],
	"gatling":   ["sfx_atk_arrow", 1.35],
	"sniper":    ["sfx_atk_arrow", 0.72],
	"boomerang": ["sfx_atk_arrow", 0.88],
	"cannon":    ["sfx_atk_cannon", 1.00],
	"mortar":    ["sfx_atk_cannon", 0.82],
	"missile":   ["sfx_atk_cannon", 1.18],
	"lightning": ["sfx_atk_electric", 1.00],
	"magnet":    ["sfx_atk_electric", 0.72],
	"teleport":  ["sfx_atk_electric", 1.50],
	"fireball":  ["sfx_atk_fire", 1.00],
	"poison":    ["sfx_atk_fire", 0.78],
	"thorn":     ["sfx_atk_fire", 1.25],
	"frost":     ["sfx_atk_frost", 1.00],
	"alchemy":   ["sfx_atk_frost", 1.45],
	"beam":      ["sfx_atk_beam", 1.00],
	"holy":      ["sfx_atk_beam", 1.30],
}

func play_tower(mech: String) -> void:
	var e: Array = TOWER_SOUND.get(mech, [])
	if e.is_empty():
		return
	play_varied(String(e[0]), float(e[1]))

func _ready() -> void:
	# UI sound has to work while the game is paused (the pause menu is a menu)
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in POOL_SIZE:
		var arr: Array = []
		for i in int(POOL_SIZE[bus]):
			var p := AudioStreamPlayer.new()
			p.bus = bus
			p.process_mode = Node.PROCESS_MODE_ALWAYS
			add_child(p)
			arr.append(p)
		_pool[bus] = arr
		_next[bus] = 0
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "BGM"
	_bgm.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_bgm)

## Which mixer bus a sound belongs to, derived from its name prefix.
static func bus_for(sound: String) -> String:
	if sound.begins_with("ui_"):
		return "UI"
	if sound.begins_with("bgm_"):
		return "BGM"
	return "SFX"

func stream(sound: String) -> AudioStream:
	if _cache.has(sound):
		return _cache[sound]
	var path := DIR + sound + ".wav"
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	if s == null and not _missing.has(sound):
		# a missing sound must never be fatal, but it must not be silent either
		_missing[sound] = true
		push_warning("Audio: no such sound '%s' (%s)" % [sound, path])
	_cache[sound] = s
	return s

## Fire a one-shot. Safe to call every frame from anywhere; the dedup window and
## the pool absorb the volume.
func play(sound: String, pitch := 1.0) -> void:
	var s := stream(sound)
	if s == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(sound, -DEDUP_MS * 2)) < DEDUP_MS:
		return
	_last_ms[sound] = now
	var bus := bus_for(sound)
	var arr: Array = _pool.get(bus, _pool.get("SFX", []))
	if arr.is_empty():
		return
	# Round-robin rather than "find a free one": at 5x every player is busy most
	# of the time, and stealing the oldest is better than dropping the sound.
	var i: int = int(_next[bus if _pool.has(bus) else "SFX"])
	var p: AudioStreamPlayer = arr[i % arr.size()]
	_next[bus if _pool.has(bus) else "SFX"] = (i + 1) % arr.size()
	p.stream = s
	p.pitch_scale = clampf(pitch, 0.05, 4.0)
	p.play()

## Same, with a small random detune. Used for anything that repeats — tower fire,
## monster deaths — so a stream of them does not sound like one looping buzz.
func play_varied(sound: String, pitch := 1.0) -> void:
	play(sound, pitch * (1.0 + randf_range(-PITCH_SPREAD, PITCH_SPREAD)))

func play_bgm(sound: String) -> void:
	if _bgm_name == sound and _bgm.playing:
		return
	var s := stream(sound)
	if s == null:
		return
	if s is AudioStreamWAV:
		# the generated loops are one seamless bar-aligned phrase
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = 0
	_bgm_name = sound
	_bgm.stream = s
	_bgm.play()

func stop_bgm() -> void:
	_bgm_name = ""
	_bgm.stop()

func is_bgm_playing() -> bool:
	return _bgm.playing
