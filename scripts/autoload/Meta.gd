extends Node
## Meta progression + persistence. Owns crystals, unlocks, upgrade levels,
## highest cleared level, settings. Saves to user://save.json.

const SAVE_PATH := "user://save.json"

var crystals: int = 0
var unlocked_towers: Array = [1, 2, 5, 13]
var unlocked_spells: Array = [1]
# tower_up["3"] = [lv0,lv1,...lv5] one per of 6 directions
var tower_up: Dictionary = {}
var spell_up: Dictionary = {}
var highest_level: int = 0            # highest cleared level (0 = none)
var cleared: Dictionary = {}          # "N": true for cleared levels
## volume = 總音量 (Master), volume_bgm / volume_sfx = the two sub-buses.
## UI shares the SFX slider: a separate "menu clicks" slider is a control nobody
## asks for, and the UI bus exists so the click can duck under the music, not so
## the player has to balance it.
var settings: Dictionary = {"volume": 0.8, "volume_bgm": 1.0, "volume_sfx": 1.0,
	"muted": false, "locale": ""}
var seen: Dictionary = {}             # bestiary: "fam_1".."fam_5","fam_boss" => true
var save_version: int = SAVE_VERSION   # migrations already applied to this save

# --- save migrations --------------------------------------------------------
## Bump when an existing save needs fixing up on load. Each step is one-way and
## runs exactly once; `save_version` is persisted so it never re-runs.
##   1 — 詛咒塔 rework: the tower changed from a per-target attack to a standing
##       aura and four of its six upgrade directions no longer exist. Anything
##       already spent on it is refunded in full and the new axes start at 0.
const SAVE_VERSION := 1
## The 詛咒塔's PRE-rework upgrade base costs, in the pre-rework axis order
## (詛咒幅度 / 施咒頻率 / 射程 / 詛咒持續 / 附帶減速 / 死亡詛咒擴散). Frozen here on
## purpose — GameData now holds the NEW costs, so the refund has to be computed
## from a copy of the old table.
const CURSE_OLD_BASE_COSTS := [60, 55, 45, 55, 60, 65]
const CURSE_TOWER_ID := 17
## Set by the migration for the UI to show once, then cleared by whoever shows it.
var rework_refund: int = 0

func _ready() -> void:
	load_game()
	_migrate()
	apply_audio_settings()
	apply_locale()

## Runs once per save, right after load_game().
func _migrate() -> void:
	if save_version >= SAVE_VERSION:
		return
	if save_version < 1:
		rework_refund += _refund_curse_tower()
	save_version = SAVE_VERSION
	save_game()

## 詛咒塔 rework (v1): give back every 魔晶 sunk into the old upgrade axes and
## reset the tower to level 0 on the new ones. Reads the RAW stored array rather
## than tower_levels(), because tower_levels() would already have padded/trimmed
## it to the new axis count and we need whatever the old build wrote.
func _refund_curse_tower() -> int:
	var key := str(CURSE_TOWER_ID)
	var old = tower_up.get(key, null)
	if not (old is Array):
		return 0
	var refund := 0
	for i in old.size():
		if i >= CURSE_OLD_BASE_COSTS.size():
			break
		var lv: int = maxi(0, int(old[i]))
		for k in lv:                       # cost of the 1st..lv-th level
			refund += GameData.upgrade_cost(CURSE_OLD_BASE_COSTS[i], k)
	if refund <= 0:
		tower_up.erase(key)
		return 0
	crystals += refund
	tower_up.erase(key)                    # new axes start from 0
	return refund

# --- upgrade level access ---------------------------------------------------
## Levels are stored one per upgrade DIRECTION. A save written before a tower
## gained a direction holds a shorter array; padding here (rather than trusting
## the file) is what keeps an old save from crashing the upgrade screen on
## `levels[dir]` and from refusing to sell the newer directions.
func _levels_for(store: Dictionary, key: String, n: int) -> Array:
	var arr: Array = store.get(key, [])
	if typeof(arr) != TYPE_ARRAY:
		arr = []
	while arr.size() < n:
		arr.append(0)
	if arr.size() > n:
		arr.resize(n)
	store[key] = arr
	return arr

func tower_levels(id: int) -> Array:
	return _levels_for(tower_up, str(id), GameData.tower_by_id(id).ups.size())

func spell_levels(id: int) -> Array:
	return _levels_for(spell_up, str(id), GameData.spell_by_id(id).ups.size())

func tower_stats(id: int) -> Dictionary:
	return GameData.effective_stats(GameData.tower_by_id(id), tower_levels(id))

func spell_stats(id: int) -> Dictionary:
	return GameData.effective_stats(GameData.spell_by_id(id), spell_levels(id))

# --- transactions -----------------------------------------------------------
func can_afford(cost: int) -> bool:
	return crystals >= cost

## NOTE ON ATOMICITY: every purchase used to be TWO writes — spend_crystals()
## saved the deduction, then the caller mutated the unlock/level and saved again.
## Quitting (or crashing) between the two writes billed the player and delivered
## nothing. Purchases now deduct in memory via _take_crystals() and write ONCE,
## after the goods are in the dictionary.
func _take_crystals(cost: int) -> bool:
	if crystals < cost:
		return false
	crystals -= cost
	return true

func spend_crystals(cost: int) -> bool:
	if not _take_crystals(cost):
		return false
	save_game()
	return true

func add_crystals(amount: int) -> void:
	crystals += amount
	save_game()

func is_tower_unlocked(id: int) -> bool:
	return unlocked_towers.has(id)

func is_spell_unlocked(id: int) -> bool:
	return unlocked_spells.has(id)

func unlock_tower(id: int) -> bool:
	if is_tower_unlocked(id) or not _take_crystals(GameData.tower_by_id(id).unlock):
		return false
	unlocked_towers.append(id)
	save_game()
	return true

func unlock_spell(id: int) -> bool:
	if is_spell_unlocked(id) or not _take_crystals(spell_unlock_cost(id)):
		return false
	unlocked_spells.append(id)
	save_game()
	return true

func spell_unlock_cost(id: int) -> int:
	return int(30 + id * 12)

func buy_tower_upgrade(id: int, dir: int) -> bool:
	var levels := tower_levels(id)
	if dir < 0 or dir >= levels.size():
		return false
	if levels[dir] >= GameData.MAX_UP_LV:
		return false
	var base: int = GameData.tower_by_id(id).ups[dir].base_cost
	var cost := GameData.upgrade_cost(base, levels[dir])
	if not _take_crystals(cost):
		return false
	levels[dir] += 1
	save_game()
	return true

func buy_spell_upgrade(id: int, dir: int) -> bool:
	var levels := spell_levels(id)
	if dir < 0 or dir >= levels.size():
		return false
	if levels[dir] >= GameData.MAX_UP_LV:
		return false
	var base: int = GameData.spell_by_id(id).ups[dir].base_cost
	var cost := GameData.upgrade_cost(base, levels[dir])
	if not _take_crystals(cost):
		return false
	levels[dir] += 1
	save_game()
	return true

func tower_up_cost(id: int, dir: int) -> int:
	var levels := tower_levels(id)
	var base: int = GameData.tower_by_id(id).ups[dir].base_cost
	return GameData.upgrade_cost(base, levels[dir])

func spell_up_cost(id: int, dir: int) -> int:
	var levels := spell_levels(id)
	var base: int = GameData.spell_by_id(id).ups[dir].base_cost
	return GameData.upgrade_cost(base, levels[dir])

# --- level completion -------------------------------------------------------
func is_cleared(n: int) -> bool:
	return cleared.has(str(n))

func on_level_cleared(n: int) -> Dictionary:
	## Awards crystals and returns the breakdown the result screen itemises:
	##   base   通關獎勵 (halved on a replay)
	##   first  首次通關獎勵 (0 unless this is the first ever clear of level n)
	## `cleared` IS the first-clear record and is persisted in save.json, so a
	## replay after a restart correctly pays no first-clear bonus.
	var replay := is_cleared(n)   # must be read BEFORE marking the level cleared
	var base := GameData.level_crystal_reward(n)
	if replay:
		base = int(base / 2)
	var first := 0 if replay else GameData.level_first_clear_bonus(n)
	cleared[str(n)] = true
	highest_level = maxi(highest_level, n)
	add_crystals(base + first)  # also saves
	return {"base": base, "first": first, "total": base + first, "replay": replay}

func on_level_failed(n: int, kills: int, elapsed: float, boss_time_s: float, boss_frac: float) -> Dictionary:
	## 輸咗都有魔晶: pays out by progress, capped at GameData.LOSE_REWARD_CAP_FRAC
	## of the clear reward, and nothing at all inside the anti-farm window.
	var replay := is_cleared(n)   # a loss on an already-cleared level pays less
	var reward := GameData.level_lose_reward(n, kills, elapsed, boss_time_s, boss_frac, replay)
	if reward > 0:
		add_crystals(reward)  # also saves
	return {
		"crystals": reward,
		"replay": replay,
		"progress": GameData.lose_progress(kills, elapsed, boss_time_s, boss_frac),
		"cap": GameData.level_lose_max(n, replay),
		"too_short": elapsed < GameData.LOSE_MIN_TIME,
		"boss_frac": clampf(boss_frac, 0.0, 1.0),
	}

func next_level() -> int:
	return highest_level + 1

# --- bestiary sightings -----------------------------------------------------
func seen_key(fam: String, lvl: int, boss: bool) -> String:
	return "%s_boss" % fam if boss else "%s_%d" % [fam, lvl]

func has_seen(fam: String, lvl: int, boss: bool) -> bool:
	return seen.get(seen_key(fam, lvl, boss), false)

## Called from Battle._spawn_monster, i.e. potentially several times inside one
## frame of a wave. It used to save_game() on every FIRST sighting — a synchronous
## JSON stringify + file write in the middle of gameplay. Sightings are now marked
## in memory and flushed on a short debounce (and forced at the end of a battle /
## on app exit), so nothing is lost but nothing writes mid-wave either.
const SEEN_FLUSH_DELAY := 1.5
var _seen_dirty: bool = false
var _seen_flush_t: float = 0.0

func mark_seen(fam: String, lvl: int, boss: bool) -> void:
	var k := seen_key(fam, lvl, boss)
	if not seen.get(k, false):
		seen[k] = true
		_seen_dirty = true
		_seen_flush_t = SEEN_FLUSH_DELAY

func flush_pending_save() -> void:
	if _seen_dirty:
		save_game()

func _process(delta: float) -> void:
	if not _seen_dirty:
		return
	# real seconds: this must not run 5x faster just because the battle is on 5x
	_seen_flush_t -= delta / maxf(0.01, Engine.time_scale)
	if _seen_flush_t <= 0.0:
		flush_pending_save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		flush_pending_save()

func family_any_seen(fam: String) -> bool:
	for lvl in range(1, 6):
		if has_seen(fam, lvl, false):
			return true
	return has_seen(fam, 0, true)

# --- persistence ------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"crystals": crystals,
		"unlocked_towers": unlocked_towers,
		"unlocked_spells": unlocked_spells,
		"tower_up": tower_up,
		"spell_up": spell_up,
		"highest_level": highest_level,
		"cleared": cleared,
		"settings": settings,
		"seen": seen,
		"version": save_version,
	}

func save_game() -> void:
	_seen_dirty = false   # every write persists `seen` too
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("無法寫入存檔")
		return
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()

func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		save_game()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("存檔格式不正確,改用預設值")
		return
	# Every field is defended individually: a save written by an older build (or
	# hand-edited / truncated) must degrade to the default, never crash a screen.
	# An EMPTY unlock list is treated as corrupt — with no towers the player can
	# place nothing and Upgrade._ready() indexes [0] on an empty array.
	crystals = maxi(0, _to_int(data.get("crystals", 0)))
	unlocked_towers = _to_int_array(data.get("unlocked_towers", []), [1, 2, 5, 13])
	unlocked_spells = _to_int_array(data.get("unlocked_spells", []), [1])
	tower_up = _to_lv_dict(data.get("tower_up", {}))
	spell_up = _to_lv_dict(data.get("spell_up", {}))
	highest_level = maxi(0, _to_int(data.get("highest_level", 0)))
	cleared = _to_dict(data.get("cleared", {}))
	settings = _to_dict(data.get("settings", {}))
	seen = _to_dict(data.get("seen", {}))
	# a save with no "version" key predates migrations, so it starts at 0 and
	# _migrate() brings it forward
	save_version = maxi(0, _to_int(data.get("version", 0)))
	if not settings.has("volume"):
		settings["volume"] = 0.8
	# round 8 added the two sub-bus sliders; a pre-round-8 save has neither, and
	# 1.0 on both reproduces exactly how that save used to sound
	if not settings.has("volume_bgm"):
		settings["volume_bgm"] = 1.0
	if not settings.has("volume_sfx"):
		settings["volume_sfx"] = 1.0
	if not settings.has("muted"):
		settings["muted"] = false
	# "" = never chosen -> follow the system locale on this and every later launch
	# until the player picks one in 設定.
	if not settings.has("locale"):
		settings["locale"] = ""

func _to_int(v) -> int:
	return int(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING] else 0

func _to_dict(d) -> Dictionary:
	return d if typeof(d) == TYPE_DICTIONARY else {}

func _to_int_array(a, fallback: Array) -> Array:
	var out := []
	if a is Array:
		for v in a:
			var n := _to_int(v)
			if n > 0 and not out.has(n):
				out.append(n)
	return out if not out.is_empty() else fallback.duplicate()

func _to_lv_dict(d) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d.keys():
			var arr := []
			if d[k] is Array:
				for v in d[k]:
					arr.append(maxi(0, mini(GameData.MAX_UP_LV, _to_int(v))))
			out[str(k)] = arr
	return out

# --- language ---------------------------------------------------------------
## The two shipping locales, in the order the settings screen lists them.
## `label` is deliberately NOT translated — a language picker has to read in the
## language it selects, or the player who cannot read the current one is stuck.
const LOCALES := [
	{"code": "zh_TW", "label": "中文"},
	{"code": "en", "label": "English"},
]

## Locale to use when the save has never recorded a choice: follow the system,
## with anything non-Chinese landing on English.
func default_locale() -> String:
	return "zh_TW" if OS.get_locale().begins_with("zh") else "en"

func current_locale() -> String:
	var code: String = str(settings.get("locale", ""))
	for l in LOCALES:
		if l.code == code:
			return code
	return default_locale()

## Push the persisted (or system-derived) language into the TranslationServer.
func apply_locale() -> void:
	TranslationServer.set_locale(current_locale())

## Change language and persist it. Callers are responsible for redrawing whatever
## is on screen — see Flow.set_locale(), which reloads the current scene.
func set_locale(code: String) -> void:
	settings["locale"] = code
	apply_locale()
	save_game()

## Push the persisted audio settings into the buses. Without this the saved
## 靜音 / 音量 only ever took effect if you re-toggled them in 設定 this session.
##
## Round 8 split one master volume into three: Master carries 總音量 and the mute
## toggle, and BGM / SFX / UI sit under it. Old saves have only "volume", so the
## two new keys fall back to 1.0 and such a save sounds exactly as it did.
const AUDIO_SUB_BUSES := {"BGM": "volume_bgm", "SFX": "volume_sfx", "UI": "volume_sfx"}

func apply_audio_settings() -> void:
	var vol: float = float(settings.get("volume", 0.8))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, vol)))
	AudioServer.set_bus_mute(0, bool(settings.get("muted", false)))
	for bus_name in AUDIO_SUB_BUSES:
		var idx := AudioServer.get_bus_index(bus_name)
		if idx < 0:
			continue     # bus layout not loaded (headless tools, older project)
		var v: float = float(settings.get(AUDIO_SUB_BUSES[bus_name], 1.0))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(0.0001, v)))

## 0..1 for one of the three sliders. `key` is a settings key, not a bus name.
func audio_volume(key: String) -> float:
	return clampf(float(settings.get(key, 0.8 if key == "volume" else 1.0)), 0.0, 1.0)

func set_audio_volume(key: String, v: float) -> void:
	settings[key] = clampf(v, 0.0, 1.0)
	apply_audio_settings()
	save_game()

func reset_save() -> void:
	crystals = 0
	unlocked_towers = [1, 2, 5, 13]
	unlocked_spells = [1]
	tower_up = {}
	spell_up = {}
	highest_level = 0
	cleared = {}
	# language is a device preference, not progress — a save wipe must not throw
	# the player back into a language they may not read
	var keep_locale = settings.get("locale", "")
	settings = {"volume": 0.8, "volume_bgm": 1.0, "volume_sfx": 1.0,
		"muted": false, "locale": keep_locale}
	seen = {}
	save_version = SAVE_VERSION   # a fresh save needs no migration
	rework_refund = 0
	save_game()
	apply_audio_settings()
