extends Node
## Android(同將來 iOS)平台行為。呢個 autoload 係「native 手機同其他平台唔同
## 嘅嘢」嘅**唯一**一個地方 —— 網頁版嗰套住喺 `Web.gd`,兩份唔會互相踩。
##
## 三件事:
##
##   1. **返回鍵 / 返回手勢**。Android 撳返回,引擎會向成棵 tree 派
##      `NOTIFICATION_WM_GO_BACK_REQUEST`。Godot 嘅預設反應係**即刻退出 app**
##      —— 一個玩緊第 47 關嘅玩家唔小心撩到手勢邊就冇咗成場。呢度接住佢,
##      逐層退:戰鬥中開暫停選單、選單層退返主選單、主選單先問多一次。
##
##   2. **切去背景**。`NOTIFICATION_APPLICATION_PAUSED` 係「跟住可能永遠冇下一
##      幀」嗰一刻(玩家撳 home、來電、被系統殺)。要喺嗰一刻暫停 + 靜音 +
##      落實存檔;返嚟**唔會**自動幫玩家取消暫停 —— 見 `_on_resumed()`。
##
##   3. **閃退偵測喺 native 唔可以誤報**。`Crash.gd` 靠一個「開場落、正常收場
##      刪」嘅 marker 檔。但 Android **冇** `NOTIFICATION_WM_CLOSE_REQUEST`:
##      玩家由最近應用清單掃走個 app,個 process 就咁被殺,`_close()` 永遠冇
##      機會行 —— 即係每一次正常收工都會喺下次開場報一單假閃退。所以喺
##      native,`APPLICATION_PAUSED` 就係「由呢一刻起唔算閃退」嗰條線
##      (同網頁版 `pagehide` 嘅取捨一樣,見 Crash.disarm() 嘅註解)。
##
## 桌面上面除咗 Esc 會行返同一條返回路徑之外乜都唔做;網頁版連 Esc 都照行,
## 但唔會真係 quit()(瀏覽器 tab 關唔到自己)。可以喺 PC 上面行到同一條
## code path,呢件事本身就係要求 —— 冇部 Android 機喺手嘅時候,
## `test/BackNavTest.tscn` 靠嘅就係佢。

## 「呢部係咪 native 手機」。Android / iOS 都答 true,網頁版答 false
## (就算個瀏覽器行喺電話上面 —— 嗰個 case 由 Web.gd 管)。
func is_mobile() -> bool:
	return OS.has_feature("mobile") and not OS.has_feature("web")

# ---------------------------------------------------------------------------
# 返回鍵
# ---------------------------------------------------------------------------
## 想自己食返回鍵嘅畫面加入呢個 group,並且實作 `handle_back() -> bool`。
## 返 true = 「我食咗」,返 false = 「唔關我事,傳落去」。
const BACK_GROUP := "back_handler"

## 主選單撳一次返回之後,幾耐之內再撳一次先算「確認退出」。
const EXIT_CONFIRM_WINDOW := 2.5

var _exit_armed_until_ms: int = 0
## 同一下返回鍵可能同時以 GO_BACK notification **同** ui_cancel 兩種形式到埗
## (視乎引擎版本同鍵盤 mapping)。冇呢個窗口嘅話,「開暫停選單」會即刻被
## 第二次呼叫關返,睇落好似個掣壞咗。
var _last_back_ms: int = 0
const BACK_DEBOUNCE_MS := 250

func _ready() -> void:
	# 暫停之後仲要收到返回鍵同 resume —— 唔係嘅話開咗暫停選單就冇得再撳返回。
	process_mode = Node.PROCESS_MODE_ALWAYS

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			request_back()
		# 網頁版嘅切走 / 切返由 `Web.gd` 全權處理(佢接 JS 嘅 visibilitychange /
		# pagehide,而且返嚟嗰陣要還原**玩家自己嗰個**暫停狀態,同 native 呢邊
		# 「一律停喺暫停畫面」係相反嘅取捨)。就算將來某個 Godot 版本開始喺
		# web 都派呢兩個 notification,呢一行都令兩套邏輯唔會撞。
		NOTIFICATION_APPLICATION_PAUSED:
			if not OS.has_feature("web"):
				_on_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			if not OS.has_feature("web"):
				_on_resumed()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_back()

## 一下「返回」。逐層問:最深嗰個 back handler 行先,冇人食就跌落預設路徑。
func request_back() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_back_ms < BACK_DEBOUNCE_MS:
		return
	_last_back_ms = now
	var tree := get_tree()
	if tree == null:
		return
	Crash.crumb("back", "request")
	for n in _handlers_deepest_first(tree):
		if n.has_method("handle_back") and bool(n.call("handle_back")):
			return
	_default_back(tree)

## 深度大嘅行先:圖鑑 overlay 掛喺 BattleHUD 之下,所以佢一定要問得先。
func _handlers_deepest_first(tree: SceneTree) -> Array:
	var out: Array = []
	for n in tree.get_nodes_in_group(BACK_GROUP):
		if n is Node and n.is_inside_tree():
			out.append(n)
	out.sort_custom(func(a, b): return _depth(a) > _depth(b))
	return out

func _depth(n: Node) -> int:
	var d := 0
	var p := n.get_parent()
	while p != null:
		d += 1
		p = p.get_parent()
	return d

## 冇人食嗰陣:唔喺主選單就退返主選單,喺主選單就問多一次先退出。
func _default_back(tree: SceneTree) -> void:
	var scene := tree.current_scene
	var path := "" if scene == null else scene.scene_file_path
	if path != Flow.MAIN_MENU and path != "":
		tree.paused = false
		Flow.goto(Flow.MAIN_MENU)
		return
	_confirm_exit(scene)

func _confirm_exit(scene: Node) -> void:
	var now := Time.get_ticks_msec()
	if now < _exit_armed_until_ms:
		Crash.crumb("back", "exit confirmed")
		Meta.flush_pending_save()
		Crash.flush_now()
		Crash.disarm()
		# 網頁版關唔到自己個 tab,quit() 落去係一個乜都唔會發生嘅假動作。
		if not OS.has_feature("web"):
			get_tree().quit()
		return
	_exit_armed_until_ms = now + int(EXIT_CONFIRM_WINDOW * 1000.0)
	if scene is Control:
		UI.toast(scene, tr("TOAST_EXIT_CONFIRM"), UI.GOLD)

# ---------------------------------------------------------------------------
# App 生命週期
# ---------------------------------------------------------------------------
## 呢兩個 notification 喺桌面同網頁版都唔會嚟,所以唔使 guard 平台;
## 但測試要叫得到,所以佢哋係 public。
func _on_paused() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.paused = true
	AudioServer.set_bus_mute(0, true)
	Crash.crumb("app", "paused (background)")
	Crash.flush_now()
	Meta.flush_pending_save()
	# 最後一步。順序同 Web.suspend() 一樣:flush 咗麵包屑先 disarm,
	# 咁最後嗰批麵包屑仍然入得到 log,但個 marker 唔會留低嚟報假閃退。
	Crash.disarm()

## 返嚟。**唔會**自動幫玩家取消暫停 —— 佢切走嗰陣可能係接電話,眼唔喺部機
## 度;一返嚟就恢復戰鬥等於幫佢玩咗一段。戰鬥畫面停喺暫停選單,選單畫面
## 就冇嘢好停,直接解封。
func _on_resumed() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# 唔係直接 set_bus_mute(0, false):玩家自己撳咗靜音嘅話,返嚟唔應該幫佢開返聲。
	Meta.apply_audio_settings()
	Crash.rearm()
	Crash.crumb("app", "resumed")
	var held := false
	for n in tree.get_nodes_in_group(BACK_GROUP):
		if n.has_method("hold_paused") and bool(n.call("hold_paused")):
			held = true
	if not held:
		tree.paused = false
