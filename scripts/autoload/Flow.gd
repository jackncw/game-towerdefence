extends Node
## Transient cross-scene state + simple scene routing.

var selected_level: int = 1
var last_result: Dictionary = {}   # filled by Battle before entering Result/Fail

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const SHOP := "res://scenes/Shop.tscn"
const UPGRADE := "res://scenes/Upgrade.tscn"
const BATTLE := "res://scenes/Battle.tscn"
const RESULT := "res://scenes/Result.tscn"
const FAIL := "res://scenes/Fail.tscn"
const SETTINGS := "res://scenes/Settings.tscn"
const GALLERY := "res://scenes/Gallery.tscn"
const BESTIARY := "res://scenes/Bestiary.tscn"
const QUICKBAR := "res://scenes/QuickBar.tscn"

## Subset of Noto Sans TC (SIL OFL 1.1) covering the game's on-screen characters.
## Rebuild with tools/subset_font.py after adding text with new characters.
const UI_FONT := preload("res://assets/fonts/NotoSansTC-Subset.ttf")

func _ready() -> void:
	# Global CJK-capable font so all 繁體中文 renders.
	if OS.has_feature("web"):
		_install_web_cjk_font()
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Microsoft JhengHei", "微軟正黑體", "PMingLiU", "Microsoft YaHei",
			"Noto Sans CJK TC", "Noto Sans CJK SC", "Source Han Sans", "sans-serif"])
		sf.allow_system_fallback = true
		ThemeDB.fallback_font = sf
	ThemeDB.fallback_font_size = 28


## Browsers expose no system fonts, so the built-in Open Sans has nothing to fall
## back on and every CJK glyph draws as a tofu box.
##
## Setting ThemeDB.fallback_font is NOT enough: the built-in theme assigns Open
## Sans to Label/Button explicitly, so the fallback_font is never consulted. The
## bundled subset has to be hung off those fonts' own `fallbacks` chains instead.
## Doing it this way keeps Latin text in Open Sans exactly as on desktop.
func _install_web_cjk_font() -> void:
	var theme := ThemeDB.get_default_theme()
	for type_name in theme.get_font_type_list():
		for font_name in theme.get_font_list(type_name):
			_chain_fallback(theme.get_font(font_name, type_name))
	_chain_fallback(theme.default_font)
	_chain_fallback(ThemeDB.fallback_font)


func _chain_fallback(f: Font) -> void:
	if f == null or f == UI_FONT:
		return
	var chain := f.fallbacks
	if not chain.has(UI_FONT):
		chain.append(UI_FONT)
		f.fallbacks = chain

## Headless harnesses instantiate Battle directly and own their own navigation.
## A finished battle queues Flow.goto on a 0.2-0.6s timer, and that timer keeps
## running while the harness sets up the next level — swapping the root scene out
## from under it mid-run. Harnesses clear this; the game never touches it.
var nav_enabled: bool = true

func goto(path: String) -> void:
	if not nav_enabled:
		return
	Crash.crumb("scene", path.get_file())
	get_tree().change_scene_to_file(path)

func play_level(n: int) -> void:
	selected_level = n
	goto(BATTLE)

## Switch language and make it visible immediately, including on the screen the
## player is standing on. Every screen in this game builds its whole Control tree
## from tr() in _ready(), so nothing observes TranslationServer after the fact —
## Godot's automatic Control re-translation only covers text left AS a raw key,
## which is almost nothing here. Reloading the current scene re-runs those
## _ready()s and is the one refresh path that cannot miss a label.
func set_locale(code: String) -> void:
	if code == Meta.current_locale():
		return
	Crash.crumb("locale", code)
	Meta.set_locale(code)
	if nav_enabled:
		get_tree().reload_current_scene()
