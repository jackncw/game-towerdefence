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
## 快捷列 —— 戰鬥底欄常駐嗰 6 格。0 = 空格,位置有意義(第 i 格就係畫面第 i 格),
## 所以呢個 Array 唔可以用 _to_int_array() 讀:嗰個會隔走 0 又會去重,
## 兩樣都會令「第 3 格係空」變成「冇第 3 格」。
const QUICK_SLOTS := 6
const QUICK_DEFAULT := [1, 2, 5, 13, 0, 0]
var quick_slots: Array = QUICK_DEFAULT.duplicate()
var save_version: int = SAVE_VERSION   # migrations already applied to this save

# --- save migrations --------------------------------------------------------
## Bump when an existing save needs fixing up on load. Each step is one-way and
## runs exactly once; `save_version` is persisted so it never re-runs.
##   1 — 詛咒塔 rework: the tower changed from a per-target attack to a standing
##       aura and four of its six upgrade directions no longer exist. Anything
##       already spent on it is refunded in full and the new axes start at 0.
##   2 — 聖光塔 rework: the aura became field-wide, so the 「光環範圍」 direction
##       no longer exists. Everything spent on that ONE axis is refunded and the
##       replacement (「聖光強度」) starts at 0. The other five axes are untouched
##       — unlike the 詛咒塔 rework, this tower kept its identity.
const SAVE_VERSION := 2
## The 詛咒塔's PRE-rework upgrade base costs, in the pre-rework axis order
## (詛咒幅度 / 施咒頻率 / 射程 / 詛咒持續 / 附帶減速 / 死亡詛咒擴散). Frozen here on
## purpose — GameData now holds the NEW costs, so the refund has to be computed
## from a copy of the old table.
const CURSE_OLD_BASE_COSTS := [60, 55, 45, 55, 60, 65]
const CURSE_TOWER_ID := 17
## 聖光塔 rework (v2). Only ONE axis died — index 4, the old 「光環範圍」 at base
## cost 55. Frozen here for the same reason as the 詛咒塔 table above: GameData
## now holds the REPLACEMENT axis's cost, so the refund has to be computed from a
## copy of the old number, not from live data.
const HOLY_TOWER_ID := 18
const HOLY_OLD_AURARANGE_DIR := 4
const HOLY_OLD_AURARANGE_BASE_COST := 55
## Set by the migration for the UI to show once, then cleared by whoever shows it.
var rework_refund: int = 0
## Which rework the pending refund came from, so the screen can name it.
## "" = nothing pending, "curse" = v1, "holy" = v2.
var rework_kind: String = ""

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
		rework_kind = "curse"
	if save_version < 2:
		var holy := _refund_holy_aurarange()
		if holy > 0:
			rework_refund += holy
			rework_kind = "holy"
	save_version = SAVE_VERSION
	save_game()

## 聖光塔 rework (v2): refund the single dead axis and reset it to 0, leaving the
## other five levels exactly where the player left them.
##
## Reads the RAW stored array rather than tower_levels(): tower_levels() pads and
## trims against the NEW axis list, and while the count happens to be unchanged
## here (still six), relying on that would make this migration silently wrong the
## day the tower gains or loses a direction.
func _refund_holy_aurarange() -> int:
	var key := str(HOLY_TOWER_ID)
	var old = tower_up.get(key, null)
	if not (old is Array) or (old as Array).size() <= HOLY_OLD_AURARANGE_DIR:
		return 0
	var lv: int = maxi(0, int(old[HOLY_OLD_AURARANGE_DIR]))
	if lv <= 0:
		return 0
	var refund := 0
	for k in lv:
		refund += GameData.upgrade_cost(HOLY_OLD_AURARANGE_BASE_COST, k)
	old[HOLY_OLD_AURARANGE_DIR] = 0        # 新軸由 0 起
	tower_up[key] = old
	crystals += refund
	return refund

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
	return GameData.effective_stats(GameData.tower_by_id(id), tower_levels(id), tower_tier(id))

func spell_stats(id: int) -> Dictionary:
	return GameData.effective_stats(GameData.spell_by_id(id), spell_levels(id), spell_tier(id))

# --- 進化階級 (tier) --------------------------------------------------------
## 一件嘢而家喺第幾階。冇記錄 = 第一階,所以每一份舊存檔都係「全部 tier 1」,
## 唔使遷移,亦都冇「舊檔冇呢個欄位就爆」呢個問題。
var tower_tiers: Dictionary = {}   # "id" -> int
var spell_tiers: Dictionary = {}

func tower_tier(id: int) -> int:
	return clampi(int(tower_tiers.get(str(id), 1)), 1, GameData.MAX_TIER)

func spell_tier(id: int) -> int:
	return clampi(int(spell_tiers.get(str(id), 1)), 1, GameData.MAX_TIER)

func item_tier(id: int, is_tower: bool) -> int:
	return tower_tier(id) if is_tower else spell_tier(id)

## 全部升級軸都課滿咗未 —— 進化嘅門檻。
func all_axes_maxed(id: int, is_tower: bool) -> bool:
	var levels: Array = tower_levels(id) if is_tower else spell_levels(id)
	if levels.is_empty():
		return false
	for lv in levels:
		if int(lv) < GameData.MAX_UP_LV:
			return false
	return true

func axes_maxed_count(id: int, is_tower: bool) -> Array:
	var levels: Array = tower_levels(id) if is_tower else spell_levels(id)
	var done := 0
	for lv in levels:
		if int(lv) >= GameData.MAX_UP_LV:
			done += 1
	return [done, levels.size()]

func can_evolve(id: int, is_tower: bool) -> bool:
	return item_tier(id, is_tower) < GameData.MAX_TIER and all_axes_maxed(id, is_tower)

func evolve_cost(id: int, is_tower: bool) -> int:
	return GameData.evolve_cost(is_tower, item_tier(id, is_tower) + 1)

## 進化。單一寫入,同其餘每一筆購買一樣 —— 扣錢、升階、歸零升級軸,
## 三樣一齊落地或者一樣都唔落地。
##
## 升級軸歸零但**唔退錢**:已經課落去嘅嘢化成 tier 躍升本身。退錢會令進化
## 變成一個免費 respec,而嗰個係一個完全唔同嘅功能。
func evolve(id: int, is_tower: bool) -> bool:
	if not can_evolve(id, is_tower):
		return false
	if not _take_crystals(evolve_cost(id, is_tower)):
		return false
	var key := str(id)
	if is_tower:
		tower_tiers[key] = tower_tier(id) + 1
		tower_up[key] = _zeroed(GameData.tower_by_id(id).ups.size())
	else:
		spell_tiers[key] = spell_tier(id) + 1
		spell_up[key] = _zeroed(GameData.spell_by_id(id).ups.size())
	save_game()
	Audio.play("sfx_evolve")
	return true

func _zeroed(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(0)
	return a

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
	Audio.play("sfx_crystal_gain")
	crystals += amount
	save_game()

func is_tower_unlocked(id: int) -> bool:
	return unlocked_towers.has(id)

func is_spell_unlocked(id: int) -> bool:
	return unlocked_spells.has(id)

## 洗乾淨快捷列:長度補到 6、未解鎖同唔存在嘅 id 當空格、同一座塔唔准佔兩格。
##
## 呢個唔係防駭係防舊存檔 —— round 9 之前嘅存檔冇呢個欄位,而一個 reset 過嘅
## 存檔可能仲留住一個佢已經冇咗嘅塔。載入之後一定要叫,而且一定要喺
## unlocked_towers 讀完之後先叫。
func _sanitize_quick_slots() -> void:
	var out: Array = []
	var used: Dictionary = {}
	for i in QUICK_SLOTS:
		var id: int = _to_int(quick_slots[i]) if i < quick_slots.size() else 0
		if id > 0 and is_tower_unlocked(id) and not used.has(id):
			used[id] = true
			out.append(id)
		else:
			out.append(0)
	quick_slots = out

## 指派一座塔落第 `slot` 格。id = 0 即係清空。
## 塔本來喺另一格嘅話兩格對調,唔會出現同一座塔佔兩格 —— 兩格一樣嘅嘢
## 等於白白嘥咗一格,而玩家唔會知自己做咗呢件事。
func set_quick_slot(slot: int, id: int) -> void:
	if slot < 0 or slot >= QUICK_SLOTS:
		return
	if id > 0 and not is_tower_unlocked(id):
		return
	if id > 0:
		var old: int = quick_slots.find(id)
		if old >= 0:
			quick_slots[old] = quick_slots[slot]
	quick_slots[slot] = id
	save_game()

func swap_quick_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= QUICK_SLOTS or b >= QUICK_SLOTS or a == b:
		return
	var t: int = _to_int(quick_slots[a])
	quick_slots[a] = quick_slots[b]
	quick_slots[b] = t
	save_game()

func quick_slot_ids() -> Array:
	return quick_slots.duplicate()

## 新解鎖嘅塔自動入第一個空格 —— 即係預設嘅「四座初始塔 + 最新解鎖兩座」。
## 六格滿咗就唔再自動郁:嗰陣個列已經係玩家排過嘅嘢,一次解鎖唔應該打亂佢。
func _fill_quick_slot(id: int) -> void:
	if quick_slots.has(id):
		return
	var i: int = quick_slots.find(0)
	if i >= 0:
		quick_slots[i] = id

func unlock_tower(id: int) -> bool:
	if is_tower_unlocked(id) or not _take_crystals(GameData.tower_by_id(id).unlock):
		return false
	unlocked_towers.append(id)
	_fill_quick_slot(id)
	Audio.play("sfx_unlock")
	save_game()
	return true

func unlock_spell(id: int) -> bool:
	if is_spell_unlocked(id) or not _take_crystals(spell_unlock_cost(id)):
		return false
	unlocked_spells.append(id)
	save_game()
	Audio.play("sfx_unlock")
	return true

func spell_unlock_cost(id: int) -> int:
	return int(30 + id * 12)

func buy_tower_upgrade(id: int, dir: int) -> bool:
	var levels := tower_levels(id)
	if dir < 0 or dir >= levels.size():
		return false
	if levels[dir] >= GameData.MAX_UP_LV:
		return false
	if not _take_crystals(tower_up_cost(id, dir)):
		return false
	levels[dir] += 1
	save_game()
	Audio.play("sfx_upgrade")
	return true

func buy_spell_upgrade(id: int, dir: int) -> bool:
	var levels := spell_levels(id)
	if dir < 0 or dir >= levels.size():
		return false
	if levels[dir] >= GameData.MAX_UP_LV:
		return false
	if not _take_crystals(spell_up_cost(id, dir)):
		return false
	levels[dir] += 1
	save_game()
	Audio.play("sfx_upgrade")
	return true

## 價錢用**全域**級數:tier 2 嘅第 0 級接住 tier 1 嘅第 15 級,唔係由頭計。
func tower_up_cost(id: int, dir: int) -> int:
	var levels := tower_levels(id)
	var base: int = GameData.tower_by_id(id).ups[dir].base_cost
	return GameData.upgrade_cost_at(base, levels[dir], tower_tier(id))

func spell_up_cost(id: int, dir: int) -> int:
	var levels := spell_levels(id)
	var base: int = GameData.spell_by_id(id).ups[dir].base_cost
	return GameData.upgrade_cost_at(base, levels[dir], spell_tier(id))

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
	# real seconds: this must not run faster just because the battle is on 3x
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
		"quick_slots": quick_slots,
		"tower_tiers": tower_tiers,
		"spell_tiers": spell_tiers,
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
	quick_slots = _to_slot_array(data.get("quick_slots", []))
	unlocked_spells = _to_int_array(data.get("unlocked_spells", []), [1])
	tower_up = _to_lv_dict(data.get("tower_up", {}))
	spell_up = _to_lv_dict(data.get("spell_up", {}))
	# 冇呢兩個欄位嘅存檔(round 10 之前)一律當全部 tier 1 —— 冇遷移步驟,
	# 因為「冇記錄 = 第一階」本身就係 tower_tier() 嘅預設。
	tower_tiers = _to_tier_dict(data.get("tower_tiers", {}))
	spell_tiers = _to_tier_dict(data.get("spell_tiers", {}))
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
	# 一定要喺 unlocked_towers 讀完之後 —— 清洗嘅規則要用到「呢座塔解鎖咗未」
	_sanitize_quick_slots()

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

## quick_slots 專用。_to_int_array 唔用得:佢會隔走 0(而 0 喺呢度係「空格」
## 呢個意思)又會去重,兩樣都會令位置資訊冇咗。長度唔啱就落預設。
func _to_slot_array(a) -> Array:
	if not (a is Array) or (a as Array).size() != QUICK_SLOTS:
		return QUICK_DEFAULT.duplicate()
	var out: Array = []
	for v in a:
		out.append(maxi(0, _to_int(v)))
	return out

## tier 專用。夾硬 clamp 落 1..MAX_TIER:一份手改過嘅存檔寫住 tier 9 唔應該
## 令一座塔攞到一個根本冇畫過嘅 sprite 同一個冇定義過嘅倍率。
func _to_tier_dict(d) -> Dictionary:
	var out := {}
	if d is Dictionary:
		for k in d.keys():
			out[str(k)] = clampi(_to_int(d[k]), 1, GameData.MAX_TIER)
	return out

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
	quick_slots = QUICK_DEFAULT.duplicate()
	unlocked_spells = [1]
	tower_up = {}
	spell_up = {}
	tower_tiers = {}
	spell_tiers = {}
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
	rework_kind = ""
	save_game()
	apply_audio_settings()
