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

## 20 座塔嘅攻擊聲。原本 17 座共用六個 archetype 靠 pitch 分,而 barracks /
## curse / slowfield 三座完全無聲 —— 因為佢哋冇「一發」可以對齊。
##
## 而家:仲有 archetype 嘅係聲音上真係同一件事嘅塔(箭/機槍/狙擊 = 同一個
## thwip 嘅輕重),而毒/迴旋鏢/荊棘/磁力/傳送呢五座各自有一個聽落唔似射擊嘅
## 機制,借 pitch 只會令佢哋聽落似「走音嘅箭塔」,所以改咗做專屬。
## 最後三座唔係攻擊,由各自嘅事件派聲,唔係逐幀。
const TOWER_SOUND := {
	"arrow":     ["sfx_atk_arrow", 1.00],
	"gatling":   ["sfx_atk_arrow", 1.35],
	"sniper":    ["sfx_atk_arrow", 0.72],
	"cannon":    ["sfx_atk_cannon", 1.00],
	"mortar":    ["sfx_atk_cannon", 0.82],
	"missile":   ["sfx_atk_cannon", 1.18],
	"lightning": ["sfx_atk_electric", 1.00],
	"fireball":  ["sfx_atk_fire", 1.00],
	"frost":     ["sfx_atk_frost", 1.00],
	"alchemy":   ["sfx_atk_frost", 1.45],
	"beam":      ["sfx_atk_beam", 1.00],
	"holy":      ["sfx_atk_beam", 1.30],
	# 專屬
	"poison":    ["sfx_atk_poison", 1.00],
	"boomerang": ["sfx_atk_boomerang", 1.00],
	"thorn":     ["sfx_atk_thorn", 1.00],
	"magnet":    ["sfx_atk_magnet", 1.00],
	"teleport":  ["sfx_atk_teleport", 1.00],
	# 唔係攻擊:出兵 / 光環刷新 / 力場脈衝,由各自事件派
	"barracks":  ["sfx_tower_barracks", 1.00],
	"curse":     ["sfx_aura_curse", 1.00],
	"slowfield": ["sfx_field_slow", 1.00],
}

## 每族一個死亡聲。共用一個「死亡」聲會令十族聽落一樣 —— 而玩家分辨怪物族群
## 嘅速度,喺 5x 之下係靠聽多過靠睇。
const DEATH_SOUND := {
	"goblin": "sfx_die_goblin", "wolf": "sfx_die_wolf",
	"skeleton": "sfx_die_skeleton", "golem": "sfx_die_golem",
	"ghost": "sfx_die_ghost", "bat": "sfx_die_bat",
	"treant": "sfx_die_treant", "beetle": "sfx_die_beetle",
	"cultist": "sfx_die_cultist", "slime": "sfx_die_slime",
}

## 受擊聲。三款按目標嘅防禦形態揀,唔係按傷害類型 —— 玩家要聽到嘅係「我打緊嘅
## 嘢硬唔硬」,唔係「我用緊乜屬性」(後者睇塔就知)。
const HIT_SOUND := {"soft": "sfx_hit_soft", "hard": "sfx_hit_hard", "magic": "sfx_hit_magic"}

## 15 個魔法各有自己嘅聲。呢度冇用 archetype + pitch(塔嗰邊用嘅做法):
## 塔係一路重複咁響,pitch 已經夠分;魔法一場得幾次,每次都係一個決定,
## 所以每個都值一個自己嘅聲。
const SPELL_SOUND := {
	"meteor": "sfx_spell_meteor", "stormbolt": "sfx_spell_stormbolt",
	"freezenova": "sfx_spell_freezenova", "miasma": "sfx_spell_miasma",
	"summon": "sfx_spell_summon", "midas": "sfx_spell_midas",
	"timewarp": "sfx_spell_timewarp", "warcry": "sfx_spell_warcry",
	"barrier": "sfx_spell_barrier", "tornado": "sfx_spell_tornado",
	"quake": "sfx_spell_quake", "firewall": "sfx_spell_firewall",
	"smite": "sfx_spell_smite", "emp": "sfx_spell_emp",
	"blackhole": "sfx_spell_blackhole",
}

## 每個註冊表引用過嘅音名。AudioTest 用佢做「改名唔會靜靜雞收聲」嘅防線:
## 任何一個表指去一個唔存在嘅檔,測試就紅,而唔係遊戲入面靜咗。
func registered_sounds() -> Array:
	var out: Dictionary = {}
	for e in TOWER_SOUND.values():
		out[String(e[0])] = true
	for n in DEATH_SOUND.values():
		out[String(n)] = true
	for n in HIT_SOUND.values():
		out[String(n)] = true
	for n in SPELL_SOUND.values():
		out[String(n)] = true
	var arr: Array = out.keys()
	arr.sort()
	return arr

## 按怪物嘅防禦形態揀受擊聲,唔係按傷害類型 —— 呢兩個數係傳入嗰刻嘅實際
## 甲/魔抗(已經計埋 lvl 同 boss 加成,GameData.creature_stats/boss_stats),
## 唔係 FAMILIES 表原始值,所以邊隻算邊款會隨 lvl/boss 改變。核過
## GameData.FAMILIES(scripts/autoload/GameData.gd:31-40)同埋嗰兩個 stats
## function 之後:淨係 ghost(魔抗 25)原始值就過 15,穩企企算「魔」;
## golem(甲 12)原始值就過 8,穩企企算「硬」。其餘族(包括 bat,魔抗淨係
## 10)喺普通等級都跌落「軟」——bat 淨係做 boss(魔抗 +5 = 15)先會轉「魔」,
## beetle/treant 呢啲甲薄嘅族要夠高 lvl(甲 +最多 4)或者做 boss(甲 +6)
## 先跳得過 8 變「硬」。門檻本身(甲 8 / 魔抗 15)係設計選定值,唔改。
func play_hit(armor: float, mres: float) -> void:
	var key := "soft"
	if mres >= 15.0:
		key = "magic"
	elif armor >= 8.0:
		key = "hard"
	play_varied(String(HIT_SOUND[key]))

func play_death(fam: String) -> void:
	var n: String = String(DEATH_SOUND.get(fam, ""))
	if n != "":
		play_varied(n)

func play_spell(mech: String) -> void:
	var n: String = String(SPELL_SOUND.get(mech, ""))
	if n != "":
		play(n)

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
