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
##   * 3x speed. A busy field fires dozens of shots per frame. Players are
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

## 測試用嘅觀察窗。冇呢個,「呢個事件有冇派聲」就只可以靠人手開音箱聽,
## 而咁樣嘅嘢冇人會喺每次改動之後重做一次。預設關,零成本。
var debug_capture: bool = false
var debug_log: Array = []

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
	# 唔係攻擊:出兵 / 光環刷新 / 力場脈衝。呢三個唔可以逐幀派,要接喺各自嗰個
	# 真事件度,再喺呼叫端限流 —— 見 Tower.play_event_sound()。
	"barracks":  ["sfx_tower_barracks", 1.00],
	"curse":     ["sfx_aura_curse", 1.00],
	"slowfield": ["sfx_field_slow", 1.00],
}

## 「持續事件」聲兩次之間最少隔幾多**真實**毫秒。
##
## Audio.play() 嗰個 60ms 去重窗係為咗擋「同一幀二十座箭塔一齊射」,唔係為咗擋
## 一個每隔零點幾秒就再嚟一次嘅事件 —— 而且 3x 之下遊戲時間壓縮咗三倍:兵營嘅
## 最短補兵間隔 0.5 秒遊戲時間喺真實時間只係 0.17 秒,60ms 窗完全放得過,結果就
## 係一秒六次號角。
##
## 用真實時間(Time.get_ticks_msec)唔用 delta:玩家聽到嘅密度係按真實時間計,
## 跟住 Engine.time_scale 縮放就等於冇限過。每個窗取返自己音檔長度嘅一倍幾,
## 兩次之間就唔會疊聲。數住呢個窗嘅字典喺 Battle 度(一場一份),見
## Battle.play_event_sound()。
const EVENT_SND_GAP_MS := {
	"sfx_tower_barracks": 450,   # 音長 0.30s
	"sfx_aura_curse": 800,       # 音長 0.50s —— 環境聲,派得最疏
	"sfx_field_slow": 650,       # 音長 0.44s
}
const EVENT_SND_GAP_DEFAULT := 400

## 每族一個死亡聲。共用一個「死亡」聲會令十族聽落一樣 —— 而玩家分辨怪物族群
## 嘅速度,喺 3x 之下係靠聽多過靠睇。
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

## 系統音。金幣同魔晶嘅音色一定要分得開 —— 佢哋喺畫面上係兩種顏色兩個 icon,
## 聽落一樣就等於將呢個區分喺聽覺上撤銷咗。金幣 = 金屬、短、亮;
## 魔晶 = 玻璃、長尾、有 shimmer。
const SYSTEM_SOUNDS := [
	"sfx_gold_pop", "sfx_gold_bank", "sfx_crystal_gain",
	"sfx_upgrade", "sfx_unlock",
	"sfx_boss_warning", "sfx_base_danger",
	"jingle_win", "jingle_lose", "jingle_first_clear",
	"sfx_teleport_hit", "sfx_knockback", "sfx_summon_circle",
	"sfx_place_tower", "sfx_sell_tower",
	# 進化係成個 meta 進程入面最大嗰下,所以佢唔可以借 sfx_upgrade —— 一個
	# 買咗一級同一次進化聽落一樣,等於話兩件事一樣重要。
	"sfx_evolve",
]

## UI 音。呢四個唔經任何一張「事件 → 音名」表 —— UI.gd 直接叫名。列喺度嘅
## 原因同下面 registered_sounds() 一樣:唔列就冇任何測試知道佢哋存在,而
## ui_panel_close 之前就正正係咁,連「有冇隻檔」都冇人問過。
const UI_SOUNDS := ["ui_click", "ui_panel_open", "ui_panel_close", "ui_error"]

## 遊戲引用過嘅每一個音名,一個都唔少。AudioTest 用佢做「改名唔會靜靜雞收聲」
## 嘅防線(每個名都要有實檔),AudioHookTest 用佢做「註冊咗就一定有人派」嘅
## 防線(每個名都要喺一場代表性嘅跑動入面真係派過)。
##
## BGM_META 同 UI_SOUNDS 一定要計埋:之前呢個表淨係行五張事件表,所以 64 個音
## 入面有 7 個(四個 ui_*、bgm_menu、bgm_boss、bgm_battle)喺任何地方都冇被
## 斷言過存在 —— 而 ui_panel_close / bgm_menu / bgm_boss 更加係一個測試都冇掂過。
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
	for n in SYSTEM_SOUNDS:
		out[String(n)] = true
	for n in UI_SOUNDS:
		out[String(n)] = true
	for n in BGM_META:
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
	if debug_capture:
		debug_log.append(sound)
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
	# Round-robin rather than "find a free one": at 3x every player is busy most
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

## 每首 BGM 嘅節奏,用嚟計小節線。battle 同 boss 一定要同 BPM 同 key,
## 唔係咁「無縫」就淨係得個講字。
const BGM_META := {
	"bgm_menu":   {"bpm": 90.0,  "beats": 4, "bars": 8},
	"bgm_battle": {"bpm": 132.0, "beats": 4, "bars": 8},
	"bgm_boss":   {"bpm": 132.0, "beats": 4, "bars": 8},
}
## 幾近就當踩正線。一幀喺 60fps 係 0.0167 秒,所以呢個窗要闊過一幀,
## 唔係就會有時啱啱跳過條線,要等多成個小節先切到。
const BAR_SNAP := 0.05

var _bgm_pending: String = ""

static func bar_seconds(meta: Dictionary) -> float:
	return 60.0 / maxf(1.0, float(meta.get("bpm", 120.0))) * float(meta.get("beats", 4))

## 由播放位置 `pos` 去到下一條小節線仲要幾耐。啱啱踩正線返 0。
static func time_to_bar(pos: float, meta: Dictionary) -> float:
	var bar: float = bar_seconds(meta)
	if bar <= 0.0:
		return 0.0
	var into: float = fposmod(pos, bar)
	return 0.0 if into < 0.0005 or bar - into < 0.0005 else bar - into

## 排隊換 BGM,等下一條小節線先真係切。
##
## 即刻切試過,唔得:切喺小節中間會斷拍,而斷拍係聽得出嘅 —— 玩家唔會諗到
## 「換咗歌」,只會覺得「卡咗一下」。等最多一個小節(132bpm 之下 1.82 秒)
## 換返一個真係接得上嘅過渡,係抵嘅。
func queue_bgm(sound: String) -> void:
	# 觀察窗喺呢度都要記一筆:排隊本身就係一個派聲決定。真正嘅 play_bgm() 要
	# 等到下一條小節線先行,而測試問嘅係「有冇人叫過呢個名」——如果淨係喺
	# play_bgm() 記,bgm_boss 就要靠一個郁得嘅播放位置先睇得到,而 headless
	# 底下嗰個 dummy driver 唔會郁。
	if debug_capture:
		debug_log.append(sound)
	if _bgm_name == sound and _bgm.playing:
		_bgm_pending = ""
		return
	_bgm_pending = sound

func _process(_delta: float) -> void:
	if _bgm_pending == "":
		return
	# 冇嘢喺度播 = 冇小節線可以等
	if not _bgm.playing:
		_commit_pending()
		return
	var meta: Dictionary = BGM_META.get(_bgm_name, {})
	if meta.is_empty():
		_commit_pending()
		return
	if time_to_bar(_bgm.get_playback_position(), meta) <= BAR_SNAP:
		_commit_pending()

func _commit_pending() -> void:
	var n: String = _bgm_pending
	_bgm_pending = ""
	play_bgm(n)

func play_bgm(sound: String) -> void:
	if _bgm_name == sound and _bgm.playing:
		return
	if debug_capture:
		debug_log.append(sound)
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
	_bgm_pending = ""

func is_bgm_playing() -> bool:
	return _bgm.playing
