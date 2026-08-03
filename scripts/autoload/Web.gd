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
	# 最後一步:除低 crash marker。
	#
	# head_include.js 喺 `visibilitychange`(切 tab)同 `pagehide`(熄 tab /
	# 離開 / 入 bfcache)兩個事件都會叫落嚟,而 iOS Safari 上面 `beforeunload`
	# 根本唔可靠 —— pagehide 先係實際會嚟嗰個。呢兩種情況都係玩家正常收工,
	# 唔可以當閃退。順序好重要:flush 咗麵包屑先 disarm,咁最後嗰批麵包屑
	# 仍然入得到 log,但個 marker 唔會留低。
	Crash.disarm()

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
	# 落返 marker。由 bfcache 恢復返嚟嘅 tab 會繼續玩落去,所以由呢一刻起
	# 嘅閃退要照捉 —— 唔 rearm 就等於之後成個 session 都冇咗閃退偵測。
	Crash.rearm()
	Crash.crumb("web", "visible (armed=%s)" % str(Crash.is_armed()))

func is_suspended() -> bool:
	return _suspended

# ---------------------------------------------------------------------------
# Heap
# ---------------------------------------------------------------------------
## 呢個 tab 而家問作業系統攞咗幾多 bytes。0 = 攞唔到(唔係「用咗零」)。
##
## 點解要有:`Performance.MEMORY_STATIC` 喺 **release export template** 之下係
## 硬編碼 0 —— 量過:同一份 code、同一部機,debug 報 78.8MB 而且跟得住一舊
## +4MB 嘅分配,release 報 0 而且分配咗 12MB 都唔郁。即係話出街版嘅閃退報告
## 一直冇一個真嘅記憶體數字,而 iOS 殺 tab 睇嘅就正正係呢個數。
##
## 攞邊個數:emscripten 嘅 linear memory(`HEAP8.length`)。wasm 嘅 memory
## **只增不減**,所以佢就係「呢個 process 喺系統手上面佔住幾多」,亦即係
## iOS 個 tab 上限度緊嗰樣嘢。
##
## 點解唔用第二啲:
##   * `performance.memory` —— Chromium 專有,Safari 冇。iPhone 上面等於冇。
##   * `performance.measureUserAgentSpecificMemory()` —— 要 crossOriginIsolated,
##     而 GitHub Pages 冇 COOP/COEP header(呢個專案行單線程正正就係因為咁)。
##     喺真瀏覽器度量過:`crossOriginIsolated === false`。
##
## `engine` 係 Godot 自己嘅 `index.html` 喺頂層 `const` 出嚟嘅,所以 eval 見到佢。
## 佢一日改名,呢度就返 0,而 0 會喺報告上面印做 `n/a` —— 睇得見嘅失敗,
## 唔係一個扮數據嘅零。
const _HEAP_JS := """(function () {
  try {
    if (typeof engine !== 'undefined' && engine && engine.rtenv
        && engine.rtenv.HEAP8) { return engine.rtenv.HEAP8.length; }
  } catch (e) { /* fall through */ }
  try {
    if (window.performance && performance.memory
        && performance.memory.usedJSHeapSize) {
      return performance.memory.usedJSHeapSize;
    }
  } catch (e) { /* fall through */ }
  return 0;
})()"""

# ---------------------------------------------------------------------------
# Session 開關訊號(localStorage)
# ---------------------------------------------------------------------------
## 點解唔可以淨係靠 Crash.gd 嗰個 marker **檔案**:
##
## 個檔住喺 `user://`,而網頁版嘅 `user://` 係 emscripten 嘅 IDBFS —— 寫落去
## 之後仲要等一次**非同步**嘅 IndexedDB 同步先真係落地。`pagehide` 嗰一刻
## 個 tab 隨時就死,同步做唔完。
##
## 實測(tools/web_lifecycle_probe.py,2026-08-03):淨係刪檔嘅版本,
## 「切 tab」過關(之後仲有兩秒俾佢同步),但「熄 tab」同「返轉頭之後再熄」
## 兩種都繼續誤報 —— 刪除根本冇落到 IndexedDB。
##
## `localStorage` 係**同步**API,setItem/removeItem 一返嚟就已經持久化。
## 所以「上一次收唔收得正常」呢個一 bit 訊號放喺呢度,唔放喺個檔度。
## 麵包屑照舊留喺個檔(嗰啲係打緊機嗰陣寫,有大把時間同步)。
## 實作住咗喺 `Crash.gd`(`_ls_set` / `_ls_clear` / `_ls_get`),唔喺呢度 ——
## autoload 次序係 Crash 行先、Web 最尾,而個訊號喺 `Crash._ready()` 就要用,
## 嗰一刻 `Web` 呢個 singleton 仲未存在。呢度淨係留低指路。

func heap_bytes() -> int:
	if not is_web():
		return 0
	var v = JavaScriptBridge.eval(_HEAP_JS, true)
	if v == null:
		return 0
	return int(float(v))
