extends Node
## Localization regression harness. Headless, exit code = result.
##   godot --headless --path . test/I18nTest.tscn
## Covers: both locales load, EVERY key in i18n/game.csv resolves in BOTH
## locales, every key referenced from GameData resolves, the first-launch
## system-locale rule, and that a language choice survives a save round-trip.

const CSV := "res://i18n/game.csv"
const LOCALES := ["zh_TW", "en"]

var pass_n := 0
var fail_n := 0

func _check(ok: bool, what: String) -> void:
	if ok:
		pass_n += 1
	else:
		fail_n += 1
		print("FAIL: ", what)

func _ready() -> void:
	Flow.nav_enabled = false
	var restore_locale: String = str(Meta.settings.get("locale", ""))

	_test_locales_registered()
	var keys := _csv_keys()
	_test_every_key_translates(keys)
	_test_gamedata_keys(keys)
	_test_no_leftover_cjk_in_english(keys)
	_test_default_locale()
	_test_persistence()

	Meta.settings["locale"] = restore_locale
	Meta.apply_locale()
	Meta.save_game()

	print("I18N: %d passed, %d failed" % [pass_n, fail_n])
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------------------
func _csv_keys() -> Array:
	var f := FileAccess.open(CSV, FileAccess.READ)
	_check(f != null, "i18n/game.csv is readable")
	if f == null:
		return []
	var header := f.get_csv_line()
	_check(header.size() == 3 and header[1] == "zh_TW" and header[2] == "en",
		"csv header is keys,zh_TW,en (got %s)" % [header])
	var keys := []
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 3 or row[0].strip_edges() == "":
			continue
		keys.append(row[0])
		_check(row[1].strip_edges() != "", "%s has a zh_TW string" % row[0])
		_check(row[2].strip_edges() != "", "%s has an en string" % row[0])
	f.close()
	_check(keys.size() > 200, "csv holds the full key set (%d)" % keys.size())
	_check(keys.size() == _unique(keys).size(), "no duplicate keys in the csv")
	return keys

func _unique(a: Array) -> Array:
	var out := []
	for v in a:
		if not out.has(v):
			out.append(v)
	return out

func _test_locales_registered() -> void:
	var loaded := TranslationServer.get_loaded_locales()
	for l in LOCALES:
		_check(loaded.has(l), "locale %s is registered (loaded: %s)" % [l, loaded])

## The real漏譯 test: tr() returning the key verbatim means the row is missing.
func _test_every_key_translates(keys: Array) -> void:
	for l in LOCALES:
		TranslationServer.set_locale(l)
		var missing := []
		for k in keys:
			if tr(k) == k:
				missing.append(k)
		_check(missing.is_empty(), "[%s] every csv key resolves (missing: %s)"
			% [l, missing.slice(0, 8)])

## Everything GameData stores as a key has to exist in the csv — a typo here
## would ship a raw KEY_NAME onto a card in both languages.
func _test_gamedata_keys(keys: Array) -> void:
	var referenced := []
	for t in GameData.TOWERS:
		referenced.append(t.name)
		referenced.append(t.desc)
		for up in t.ups:
			referenced.append(up.name)
	for sp in GameData.SPELLS:
		referenced.append(sp.name)
		referenced.append(sp.desc)
		for up in sp.ups:
			referenced.append(up.name)
	for fam in GameData.FAMILY_ORDER:
		referenced.append(GameData.FAMILIES[fam].name)
		referenced.append(GameData.FAMILY_LORE[fam].mech)
		referenced.append(GameData.FAMILY_LORE[fam].boss)
	var upg: GDScript = load("res://scripts/ui/Upgrade.gd")
	var consts: Dictionary = upg.get_script_constant_map()
	for m in (consts["TOWER_MECH"] as Dictionary).values():
		referenced.append(m[1])
	for m in (consts["SPELL_MECH"] as Dictionary).values():
		referenced.append(m[1])
	var unknown := []
	for k in referenced:
		if not keys.has(k):
			unknown.append(k)
	_check(unknown.is_empty(), "every GameData/Upgrade key exists in the csv (%s)"
		% [_unique(unknown)])
	_check(referenced.size() > 250, "the data tables really were scanned (%d refs)"
		% referenced.size())

## Guard against a half-finished row: an "English" string still holding 漢字.
func _test_no_leftover_cjk_in_english(keys: Array) -> void:
	TranslationServer.set_locale("en")
	# 語言 / 中文 are deliberately kept in the English language picker so a player
	# who cannot read English can still find their way back.
	var allowed := ["SET_LANGUAGE", "BESTIARY_UNKNOWN"]
	var bad := []
	for k in keys:
		if allowed.has(k):
			continue
		for c in tr(k):
			if c.unicode_at(0) >= 0x3000:
				bad.append(k)
				break
	_check(bad.is_empty(), "no CJK left in the English column (%s)" % [bad])

func _test_default_locale() -> void:
	# empty setting = never chosen -> follow OS. Both branches are asserted
	# against the same rule the game uses, and the rule itself against OS.
	Meta.settings["locale"] = ""
	var sys := OS.get_locale()
	var want := "zh_TW" if sys.begins_with("zh") else "en"
	_check(Meta.default_locale() == want,
		"first launch follows system locale %s -> %s (got %s)"
		% [sys, want, Meta.default_locale()])
	_check(Meta.current_locale() == want, "unset save uses the system default")
	# a stored junk value must not strand the player in an unloadable locale
	Meta.settings["locale"] = "de_CH"
	_check(Meta.current_locale() == want, "an unknown stored locale falls back to the default")
	# a real choice always wins over the system
	Meta.settings["locale"] = "en"
	_check(Meta.current_locale() == "en", "a stored choice overrides the system locale")
	Meta.settings["locale"] = "zh_TW"
	_check(Meta.current_locale() == "zh_TW", "…in both directions")

func _test_persistence() -> void:
	Meta.set_locale("en")
	_check(TranslationServer.get_locale() == "en", "set_locale applies immediately")
	_check(tr(GameData.tower_by_id(1).name) == "Arrow Tower",
		"tower names follow the locale (%s)" % tr(GameData.tower_by_id(1).name))
	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.READ)
	_check(f != null, "save.json exists after set_locale")
	if f != null:
		var d = JSON.parse_string(f.get_as_text())
		f.close()
		_check(typeof(d) == TYPE_DICTIONARY
			and str((d.get("settings", {}) as Dictionary).get("locale", "")) == "en",
			"the choice is written to save.json")
	# reload from disk the way a fresh launch would
	Meta.load_game()
	Meta.apply_locale()
	_check(Meta.current_locale() == "en", "the choice survives a reload")
	_check(TranslationServer.get_locale() == "en", "…and is re-applied on launch")
	# a save wipe must not drop the player into a language they cannot read
	Meta.reset_save()
	_check(Meta.current_locale() == "en", "reset_save keeps the language choice")
	Meta.set_locale("zh_TW")
	_check(tr(GameData.tower_by_id(1).name) == "箭塔",
		"switching back restores 繁中 (%s)" % tr(GameData.tower_by_id(1).name))
