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

func _ready() -> void:
	# Global CJK-capable font so all 繁體中文 renders (picks an installed system
	# font; falls back gracefully across platforms).
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft JhengHei", "微軟正黑體", "PMingLiU", "Microsoft YaHei",
		"Noto Sans CJK TC", "Noto Sans CJK SC", "Source Han Sans", "sans-serif"])
	sf.allow_system_fallback = true
	ThemeDB.fallback_font = sf
	ThemeDB.fallback_font_size = 28

## Headless harnesses instantiate Battle directly and own their own navigation.
## A finished battle queues Flow.goto on a 0.2-0.6s timer, and that timer keeps
## running while the harness sets up the next level — swapping the root scene out
## from under it mid-run. Harnesses clear this; the game never touches it.
var nav_enabled: bool = true

func goto(path: String) -> void:
	if not nav_enabled:
		return
	get_tree().change_scene_to_file(path)

func play_level(n: int) -> void:
	selected_level = n
	goto(BATTLE)
