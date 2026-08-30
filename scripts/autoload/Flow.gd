extends Node
## Transient cross-scene state + simple scene routing.

var selected_level: int = 1
var last_result: Dictionary = {}   # filled by Battle before entering Result/Fail
## 圖鑑撳一張卡就跳去升級介面,而且要落喺嗰件嘢上面。
## {"type": "tower"/"spell", "id": n};升級介面讀完即刻清走 —— 佢係一次性嘅
## 導航意圖,唔係一個「上次揀咗邊個」嘅記憶。
var upgrade_focus: Dictionary = {}

const MAIN_MENU := "res://scenes/MainMenu.tscn"
const LEVEL_SELECT := "res://scenes/LevelSelect.tscn"
const SHOP := "res://scenes/Shop.tscn"
const UPGRADE := "res://scenes/Upgrade.tscn"
const BATTLE := "res://scenes/Battle.tscn"
const RESULT := "res://scenes/Result.tscn"
const FAIL := "res://scenes/Fail.tscn"
const SETTINGS := "res://scenes/Settings.tscn"
## **開發工具,唔喺出貨版入面。** 主選單由 2026-08-02 起冇咗佢嘅入口,而
## export_presets.cfg 亦都唔再打包佢 —— 所以喺一個匯出咗嘅 build 度
## `Flow.goto(GALLERY)` 會載入失敗。由原始碼跑嘅工具同測試照用得。
const GALLERY := "res://scenes/Gallery.tscn"
const BESTIARY := "res://scenes/Bestiary.tscn"
const QUICKBAR := "res://scenes/QuickBar.tscn"

## Subset of Noto Sans TC (SIL OFL 1.1) covering the game's on-screen characters.
## Rebuild with tools/subset_font.py after adding text with new characters.
const UI_FONT := preload("res://assets/fonts/NotoSansTC-Subset.ttf")

# ---------------------------------------------------------------------------
# 幀率上限
# ---------------------------------------------------------------------------
## 呢個遊戲由頭到尾冇設過 `Engine.max_fps`,而 Godot 嘅預設係 0 = 唔封頂,
## 靠 vsync 擋。喺一部 60Hz 機上面睇落冇事,但喺 120Hz / 144Hz 嘅電話上面
## vsync 擋喺 120,即係**每秒要畫多一倍**。
##
## 而呢個遊戲逐幀嘅工作量係實牙實齒嘅:每座詛咒塔嘅地面符文、每座受聖光照住
## 嘅塔嘅三粒繞行光點、每一個 fx 都係逐幀 `queue_redraw()` 重畫(量到戰鬥高峰
## 期約 900 個 draw call 一幀)。畫兩倍咁多幀 = 做兩倍咁多嘢 = 熱兩倍。
##
## 60 對一個直向塔防嚟講肉眼同 120 分唔出 —— 呢度冇快速瞄準、冇第一人稱視角。
const FPS_NORMAL := 60
## 省電模式。預設關,玩家喺設定自己揀。30fps 喺呢個遊戲仍然順(怪物移動係
## 線性插值,唔係逐幀動畫),但耗電同發熱再少一半。
const FPS_POWER_SAVE := 30

## 幀率上限跟設定行。任何時候改咗省電設定都要再叫一次。
func apply_frame_cap() -> void:
	Engine.max_fps = FPS_POWER_SAVE if power_save() else FPS_NORMAL

func power_save() -> bool:
	return bool(Meta.settings.get("power_save", false))

## 非戰鬥畫面俾 OS 抖一抖。
##
## 點解唔順手將選單跌到 30fps(本來諗住咁做):圖鑑、商店、選關全部係
## `TouchScroll` 嘅慣性捲動,而慣性捲動喺 30fps 係睇得出一格格咁跳嘅。慳嗰
## 少少電唔值得成個遊戲最常掂嘅手感變差。`low_processor_usage_mode` 唔郁幀率,
## 佢係喺每個 loop iteration 之間放返 CPU 俾作業系統,所以一個乜都冇郁緊嘅
## 選單畫面唔會空轉。
##
## **戰鬥場景一定要收返 false** —— 嗰度每一毫秒都要用嚟趕 16.7ms 個預算。
func set_idle_friendly(on: bool) -> void:
	OS.low_processor_usage_mode = on

func _ready() -> void:
	apply_frame_cap()
	# Global CJK-capable font so all 繁體中文 renders.
	#
	# Android 行同網頁版一模一樣嗰條路,唔行 SystemFont。理由唔係方便:
	# SystemFont 要求「部機上面搵到呢啲 family name 其中一個」,而 Android 各家
	# 廠商嘅字型清單唔一樣(Godot 喺 Android 上面亦都冇 Windows 嗰種完整 family
	# 查詢),搵唔到就成版中文出豆腐格 —— 而呢種失敗喺一部冇喺手嘅機上面
	# 睇唔到,只會由玩家嚟報。打包咗嘅 subset(253 KB,本來就已經為咗網頁版
	# 入咗 pack)係一個唔使靠部機嘅答案,而且嗰條 code path 已經喺真瀏覽器
	# 度驗過。
	if OS.has_feature("web") or OS.has_feature("mobile"):
		_install_bundled_cjk_font()
	else:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Microsoft JhengHei", "微軟正黑體", "PMingLiU", "Microsoft YaHei",
			"Noto Sans CJK TC", "Noto Sans CJK SC", "Source Han Sans", "sans-serif"])
		sf.allow_system_fallback = true
		ThemeDB.fallback_font = sf
	ThemeDB.fallback_font_size = 28


## Browsers expose no system fonts, so the built-in Open Sans has nothing to fall
## back on and every CJK glyph draws as a tofu box. Android has fonts but no
## dependable way to ask for them by family name, so it takes the same road.
##
## Setting ThemeDB.fallback_font is NOT enough: the built-in theme assigns Open
## Sans to Label/Button explicitly, so the fallback_font is never consulted. The
## bundled subset has to be hung off those fonts' own `fallbacks` chains instead.
## Doing it this way keeps Latin text in Open Sans exactly as on desktop.
func _install_bundled_cjk_font() -> void:
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
	# 幀率上限同 CPU 讓步喺呢度跟畫面走。放喺 Flow 而唔係放喺 Battle._ready():
	# 測試 harness 直接 instantiate Battle 而唔經 goto(),而佢哋要自己話事跑幾
	# 快(perf3x 要解封頂先量得到真數)。經呢條路入場先受管。
	set_idle_friendly(path != BATTLE)
	apply_frame_cap()
	get_tree().change_scene_to_file(path)

## 首戰引導只可以喺**玩家由介面入場**嗰條路出現(第 24 輪)。
##
## 點解要一個旗而唔係靠 `nav_enabled`:`nav_enabled` 要每一個 harness 自己
## 記得關,而實測有 harness 冇關(`InputProbe` 就係)—— 佢直接 instantiate
## 一個 Battle,於是嗰張等人撳嘅引導卡(MOUSE_FILTER_STOP)食晒佢 push 入去
## 嘅 touch,而個測試報一個同輸入層完全無關嘅 routing 失敗。
##
## 呢個旗反過嚟:**只有 `play_level()` 會 arm 佢**,而 `Battle._ready()` 一讀
## 就即刻清走。任何直接 instantiate Battle 嘅 code(全部 harness、art_export、
## 截圖工具)由結構上就見唔到引導,唔使佢哋記得任何嘢。
var tutorial_armed: bool = false

## 讀完即清 —— 一次入場只 arm 一次。
func consume_tutorial_armed() -> bool:
	var v := tutorial_armed
	tutorial_armed = false
	return v

func play_level(n: int) -> void:
	selected_level = n
	tutorial_armed = true
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
