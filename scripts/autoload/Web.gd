extends Node
## 網頁版專項。桌面同 Android 上面呢個 autoload 除咗佔一個 node 之外**乜都唔做** —
## 每一段都喺 `OS.has_feature("web")` 之下,所以第十一輪嘅 iOS 修補冇任何一條
## 路徑會改到已經量過嘅桌面行為。
##
## 三件事:
##
##   1. **切走就暫停 + 收聲**。iOS Safari 一 background 就會凍住 rAF,而遊戲
##      唔知道自己停咗;返嚟第一幀嘅 delta 會係幾秒,一次過推進成場戰鬥。
##      同時 AudioContext 喺 background 係 suspended,但個 bus 仲係開住 ——
##      返嚟嗰下會補播一堆積壓咗嘅音效。
##      事件由 web/head_include.js 收,經 window.__tfVisibility 叫返落嚟。
##
##   2. **DPR / 記憶體麵包屑**。JS 嗰邊已經封咗 devicePixelRatio 上限 2,呢度
##      淨係將「真實 DPR 幾多、封咗未」寫入閃退報告 —— 一單 iPhone 閃退如果
##      唔知部機 DPR 幾多,個報告就少咗最關鍵嗰個數。
##
##   3. **池上限收窄**。web 冇得同 desktop 用同一份預算,見 Battle.gd 嘅
##      fx / damage-number cap。呢度提供嗰個問題嘅唯一答案(is_web()),
##      所以將來要改係改一個地方。

## 一個 JavaScriptObject。一定要 keep 住個 reference —— create_callback() 返嘅
## 嘢一被 GC 收,JS 嗰邊個 function 就變成 undefined,而個 bug 會係「切走切返
## 幾次之後就唔再暫停」呢種偶發嘢。
var _visibility_cb = null
## 網頁暫停之前個遊戲本來係咪已經暫停(玩家自己撳咗暫停選單)。返嚟嗰陣要
## 還原返呢個,唔係嘅話「暫停 → 切走 → 切返」會自動幫玩家取消咗暫停。
var _was_paused: bool = false
var _suspended: bool = false

func _ready() -> void:
	# 暫停之後仲要行得到 —— 唔係嘅話 resume() 永遠冇機會執行。
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not is_web():
		return
	_note_display_env()
	_install_lifecycle_hook()

## 「而家係咪網頁版」。所有 web 專項分支問呢一個。
func is_web() -> bool:
	return OS.has_feature("web")

# ---------------------------------------------------------------------------
func _note_display_env() -> void:
	var real := 1.0
	var capped := 1.0
	var v = JavaScriptBridge.eval(
		"(window.__tfDpr ? window.__tfDpr.real : (window.devicePixelRatio || 1))", true)
	if v != null:
		real = float(v)
	var c = JavaScriptBridge.eval(
		"(window.__tfDpr ? window.__tfDpr.capped : (window.devicePixelRatio || 1))", true)
	if c != null:
		capped = float(c)
	var win := DisplayServer.window_get_size()
	Crash.crumb("web", "dpr %.2f->%.2f  drawable %dx%d  ua %s"
		% [real, capped, win.x, win.y, _short_ua()])

func _short_ua() -> String:
	var ua = JavaScriptBridge.eval("(navigator.userAgent || '')", true)
	if ua == null:
		return "?"
	return String(ua).substr(0, 90)

func _install_lifecycle_hook() -> void:
	_visibility_cb = JavaScriptBridge.create_callback(_on_visibility)
	var win = JavaScriptBridge.get_interface("window")
	if win == null:
		return
	win.__tfVisibility = _visibility_cb
	# 頁面可能喺引擎起身之前就已經俾人切走過一次 —— head_include 記住咗最後
	# 嗰個狀態,而家補返。
	JavaScriptBridge.eval(
		"if (window.__tfFlushVisibility) { window.__tfFlushVisibility(); }", true)

func _on_visibility(args: Array) -> void:
	var hidden: bool = bool(args[0]) if args.size() > 0 else true
	if hidden:
		suspend()
	else:
		resume()

# ---------------------------------------------------------------------------
func suspend() -> void:
	if _suspended:
		return
	_suspended = true
	var tree := get_tree()
	if tree == null:
		return
	_was_paused = tree.paused
	tree.paused = true
	AudioServer.set_bus_mute(0, true)
	# 切走本身就係閃退前最常見嗰一步(系統喺 background 收記憶體),所以佢
	# 要留喺麵包屑入面。
	Crash.crumb("web", "hidden (was_paused=%s)" % _was_paused)
	Crash.flush_now()
	Meta.flush_pending_save()

func resume() -> void:
	if not _suspended:
		return
	_suspended = false
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = _was_paused
	# 唔係直接 set_bus_mute(0, false):玩家自己撳咗靜音嘅話,返嚟唔應該幫佢開返聲。
	Meta.apply_audio_settings()
	Crash.crumb("web", "visible")

func is_suspended() -> bool:
	return _suspended
