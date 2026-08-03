extends Node
## 常設閃退記錄 (crash logging)。唔係一次性嘅除錯工具 —— 佢係出街版嘅一部分。
##
## 點解要有:GDScript 冇任何「捉得住 crash」嘅 API。一個真正嘅 process 死亡
## (SIGSEGV / abort / OOM / 引擎自己 CRASH_COND)唔會俾腳本機會執手尾,所以
## 「等下次閃退嗰陣打開 debugger 睇」呢個做法喺一部電話上面永遠做唔到。
## 唯一行得通嘅係:**閃退之前就已經寫低咗**。
##
## 兩層:
##
##   1. 引擎自己嘅 file logging(project.godot 嘅 debug/file_logging/*)。
##      佢寫 user://logs/godot.log,入面有 push_error / 腳本錯誤嘅完整 stack
##      trace,而且係喺引擎層 flush,所以 crash 前嗰幾行留得低。
##   2. 呢個 autoload 嘅**未關門標記**:開場即刻寫一個 session marker,
##      正常退出先刪走。下次開場如果見到舊 marker 仲喺度,咁上一次就係
##      非正常結束 —— 即刻將嗰次嘅麵包屑抄入 user://logs/crash.log。
##
## 麵包屑(breadcrumb)係一個環形 buffer:去咗邊個畫面、開咗第幾關、擺咗幾多座
## 塔、幾多隻怪、time_scale 幾多、語言切過冇。閃退報告冇呢啲就淨係得一句
## 「佢閃退咗」,而嗰句係冇用嘅。
##
## 成本:麵包屑係**事件**唔係逐幀 —— 場景切換、開場收場、放塔放魔法、語言切換。
## 寫檔用 FLUSH_MIN_MS 限流,而且淨係喺有新麵包屑嗰陣先寫。

const LOG_DIR := "user://logs/"
const MARKER := LOG_DIR + "session.open"
const CRASH_LOG := LOG_DIR + "crash.log"
## 環形 buffer 長度。太短就見唔到「閃退之前做過乜」,太長就每次 flush 都寫成
## 版嘢。64 大約蓋得住一場完整戰鬥嘅所有里程碑。
const CRUMB_MAX := 64
## 兩次寫檔之間最少隔幾多真實毫秒。放塔連環撳嗰陣一秒可以有十幾個麵包屑,
## 而每個都 flush 一次就係喺遊戲主循環度做十幾次同步寫檔。
const FLUSH_MIN_MS := 250

## 記憶體採樣週期(真實秒)。
##
## 點解要有:一單 iOS Safari 嘅「閃退之後自動重開」係作業系統因為記憶體超限
## 殺咗個 tab,而嗰個死法**唔會**留低任何 stack trace —— 引擎冇死,個 process
## 係俾人由外面熄咗。所以唯一嘅證物就係死之前嗰條記憶體曲線。
##
## 30 秒唔係求其揀:一場戰鬥大約 90-150 秒,即係一場留低 3-5 點,而環形
## buffer 64 條裝得落成場戰鬥嘅里程碑加呢啲採樣。再密就會將真正嘅事件
## (放塔 / 施法 / 場景切換)擠出個 ring 之外,而嗰啲先係「佢做緊乜」。
const MEM_SAMPLE_SECONDS := 30.0

var _crumbs: Array = []
var _dirty: bool = false
# ---------------------------------------------------------------------------
# Session 開關訊號(網頁版:localStorage)
# ---------------------------------------------------------------------------
## 點解唔可以淨係靠下面個 marker **檔案**:
##
## 個檔住喺 `user://`,而網頁版嘅 `user://` 係 emscripten 嘅 IDBFS —— 寫或者刪
## 之後仲要等一次**非同步**嘅 IndexedDB 同步先真係落地。`pagehide` 嗰一刻個 tab
## 隨時就死,同步做唔完。
##
## 實測(tools/web_lifecycle_probe.py,2026-08-03):淨係刪檔嘅版本,「切 tab」
## 過關(之後仲有兩秒俾佢同步),但「熄 tab」同「返轉頭之後再熄」兩種都繼續
## 誤報 —— 刪除根本冇落到 IndexedDB。
##
## `localStorage` 係**同步** API,setItem/removeItem 一返嚟就已經持久化。所以
## 「上一次收唔收得正常」呢個一 bit 訊號放喺呢度。麵包屑照舊留喺個檔(嗰啲係
## 打緊機嗰陣寫,有大把時間同步)。
##
## 點解呢三個 helper 住喺 Crash 而唔係 Web:autoload 次序係 Crash 行先、Web 最尾,
## 而呢個訊號喺 `Crash._ready()` 就要用。喺嗰一刻 `Web` 個 singleton 仲未存在。
const _LS_KEY := "tf_session_open"

func _ls_set(session: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("try{localStorage.setItem('%s','%s');}catch(e){}"
		% [_LS_KEY, session], true)

func _ls_clear() -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("try{localStorage.removeItem('%s');}catch(e){}" % _LS_KEY, true)

func _ls_get() -> String:
	if not OS.has_feature("web"):
		return ""
	var v = JavaScriptBridge.eval("(localStorage.getItem('%s')||'')" % _LS_KEY, true)
	return "" if v == null else String(v)

## Marker 而家擺唔擺喺度。false = 「由呢一刻起,死咗都唔算閃退」。
##
## 點解要有:marker 靠 `_close()` 刪,而 `_close()` 掛喺 WM_CLOSE_REQUEST /
## EXIT_TREE / PREDELETE 三個通知上面。桌面熄窗口會派,但**網頁版熄 tab 一個
## 都唔會派** —— 個 process 係俾瀏覽器直接殺,腳本冇最後一口氣。結果每一次
## 正常熄 tab 都留低一個活 marker,下次開場就報一單根本冇發生過嘅閃退。
## 真玩家幾乎次次中,而報告畫面一彈,佢就以為個遊戲壞咗。
##
## Web.gd 喺 pagehide / 切走嗰陣叫 disarm(),返轉頭(pageshow,包括 bfcache
## 恢復)叫 rearm()。disarm 之後仍然照記麵包屑,淨係唔寫檔 —— 咁 rearm 返嚟
## 之後條 ring 係連續嘅,唔會斷咗一橛。
var _armed: bool = true
var _last_flush_ms: int = 0
var _session_id: String = ""
var _closed: bool = false
var _mem_t: float = 0.0

## 上一次啟動如果係閃退,呢度會有嗰次嘅完整記錄(開場之後即刻可以讀)。
## 空 Dictionary = 上次正常退出。測試同 UI 都靠呢個,唔使自己去 parse 個檔。
var last_crash: Dictionary = {}

## 關咗就唔寫任何檔。headless 嘅測試批次唔想每一個 test scene 都留低一個
## 「上次閃退」嘅假陽性(佢哋大部分係 quit() 收場,而 quit() 行得正常),
## 但真正想測呢個機制嘅測試會自己開返。
var enabled: bool = true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_session_id = "%d-%d" % [Time.get_unix_time_from_system(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_detect_previous_crash()
	# 開場即刻落 localStorage 標記(網頁版先有效),同 marker 檔一齊構成
	# 「呢個 session 開住」呢個狀態。
	_ls_set(_session_id)
	crumb("boot", "%s %s" % [OS.get_name(), Engine.get_version_info().get("string", "?")])

# ---------------------------------------------------------------------------
# 麵包屑
# ---------------------------------------------------------------------------
## 記一件「閃退報告入面想見到」嘅事。`tag` 係類別(scene / battle / place /
## spell / locale …),`detail` 係一行人睇得明嘅字。
func crumb(tag: String, detail := "") -> void:
	if not enabled:
		return
	_crumbs.append("%8.2f %-8s %s" % [Time.get_ticks_msec() / 1000.0, tag, detail])
	while _crumbs.size() > CRUMB_MAX:
		_crumbs.pop_front()
	_dirty = true
	_maybe_flush()

## 一件「唔正常但仲未死」嘅事。同時入麵包屑同引擎 log(後者會連 stack 一齊
## 寫落 godot.log),所以一單真閃退之前嘅警號兩邊都搵得返。
func note(msg: String) -> void:
	crumb("note", msg)
	push_error("[Crash] " + msg)

func _maybe_flush(force := false) -> void:
	if not _dirty or not enabled or not _armed:
		return
	var now := Time.get_ticks_msec()
	if not force and now - _last_flush_ms < FLUSH_MIN_MS:
		return
	_last_flush_ms = now
	_dirty = false
	var f := FileAccess.open(MARKER, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"session": _session_id,
		"pid": OS.get_process_id(),
		"started": Time.get_datetime_string_from_system(),
		"crumbs": _crumbs,
	}, "\t"))
	f.close()

## 「而家寫落去」。切走 / 收場呢類「跟住可能就冇下一幀」嘅時刻用。
func flush_now() -> void:
	_maybe_flush(true)

## 由呢一刻起,就算個 process 冇聲冇氣咁死咗都唔算閃退。
##
## 網頁版嘅 pagehide 就係「可能永遠冇下一幀」嗰一刻,而佢同時亦都係**正常
## 離開**最常見嘅樣。兩者喺瀏覽器層面分唔開,所以呢度揀咗「唔報」:一單漏報
## 嘅閃退,代價係少咗一份報告;一單誤報,代價係每個正常收工嘅玩家下次開場
## 都見到一版「上一次係閃退」,而嗰個會直接摧毀呢份報告嘅可信度。
func disarm() -> void:
	if not _armed:
		return
	_armed = false
	# localStorage 行先:佢係同步兼即時持久,而刪個檔要等 IDBFS 非同步同步,
	# 喺 pagehide 嗰一刻多數趕唔切(見 Web.gd 嘅 _LS_KEY 註解)。
	_ls_clear()
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(MARKER)

## 返轉頭(pageshow,包括由 bfcache 恢復)。要即刻落返 marker —— 唔落嘅話
## 由呢一刻之後嘅真閃退就冇人記得低,而 bfcache 恢復嘅 tab 係會繼續玩落去嘅。
func rearm() -> void:
	if _armed:
		return
	_armed = true
	_ls_set(_session_id)
	_dirty = true
	_maybe_flush(true)

func is_armed() -> bool:
	return _armed

func _process(delta: float) -> void:
	# 真實秒:一場 3x 嘅戰鬥唔應該三倍速咁採樣。
	_mem_t -= delta / maxf(0.01, Engine.time_scale)
	if _mem_t <= 0.0:
		_mem_t = MEM_SAMPLE_SECONDS
		crumb("mem", mem_line())
	_maybe_flush()

## 呢個 process 而家佔住幾多 bytes。0 = **量唔到**,唔係「用咗零」。
##
## 網頁版行 wasm linear memory(見 `Web.heap_bytes()`)。其餘平台行
## `MEMORY_STATIC` —— 但要知佢喺 release template 之下係硬編碼 0,所以桌面
## 出街版一樣會係 0,一樣會印做 `n/a`。呢個係引擎嘅界限,唔係一個可以喺呢度
## 補返嘅數;報告要做嘅係**唔好扮**自己知。
func heap_bytes() -> int:
	var web_heap := Web.heap_bytes()
	if web_heap > 0:
		return web_heap
	return int(Performance.get_monitor(Performance.MEMORY_STATIC))

## 一行記憶體快照。分開一個 function 因為閃退報告畫面都要用同一個格式 ——
## 玩家貼上嚟嗰段同我哋喺 log 入面睇嗰段係同一樣嘢。
##
## `heap=` 攞唔到嗰陣寫 `n/a` 而唔係 `0.0MB`。呢個分別唔係修辭:第一份同
## 第二份真閃退報告都印住 `static=0.0MB`,而嗰個數喺畫面上面同「記憶體好平穩」
## 完全分唔開,所以兩份報告都被讀成「唔似 OOM」。一個永遠讀零嘅溫度計要睇得出
## 佢係壞咗。
func mem_line() -> String:
	var heap := heap_bytes()
	var heap_s := "n/a" if heap <= 0 else "%.1fMB" % (float(heap) / 1048576.0)
	var video_mb := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0
	return "heap=%s video=%.1fMB obj=%d node=%d fps=%d" % [
		heap_s, video_mb,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.TIME_FPS)),
	]

## 閃退報告畫面要嘅嘢,一次過。空 Dictionary = 上次正常收場。
func last_crash_report() -> String:
	if last_crash.is_empty():
		return ""
	var lines: Array = []
	lines.append("塔防要塞 / Tower Fortress — crash report")
	lines.append("session: %s" % last_crash.get("session", "?"))
	lines.append("started: %s" % last_crash.get("started", "?"))
	lines.append("detected: %s" % Time.get_datetime_string_from_system())
	lines.append("device: %s %s" % [OS.get_name(), OS.get_model_name()])
	lines.append("engine: %s" % Engine.get_version_info().get("string", "?"))
	lines.append("--- breadcrumbs (oldest first) ---")
	for c in last_crash.get("crumbs", []):
		lines.append(str(c))
	return "\n".join(lines)

## 畫趨勢嗰陣可以揀嘅數,由最有用去到最冇用。
##
## **`static` 唔喺入面,而且唔可以加返。** 佢喺每一個 release export template
## 之下都係硬編碼 0(量過:debug 78.8MB / release 0,同一份 code 同一部機),
## 所以佢畫出嚟嘅永遠係一條貼住零嘅平線 —— 而嗰條平線讀落去係「記憶體好穩定」。
## 頭兩份真閃退報告就係咁樣被讀錯嘅。
const TREND_KEYS := ["heap", "video"]

## 麵包屑入面嘅記憶體採樣,由舊到新。閃退報告用佢畫一條「死之前升緊定平緊」
## 嘅趨勢 —— 一個孤零零嘅數字答唔到「係咪 OOM」呢條問題,一條線就答得到。
##
## 返 `{"key": "heap"/"video"/"", "values": [...]}`。要有個 `key` 係因為一條
## **冇名**嘅曲線冇得判斷信唔信得過:heap 升緊同 video 升緊係兩件唔同嘅事,
## 而讀報告嗰個人要知佢睇緊邊一樣。`key == ""` = 呢份報告冇任何記憶體證據,
## 而咁講好過畫一條假線。
func last_crash_memory_trend() -> Dictionary:
	for key in TREND_KEYS:
		var out: Array = []
		var needle: String = str(key) + "="
		for c in last_crash.get("crumbs", []):
			var s := str(c)
			var i := s.find(needle)
			if i < 0:
				continue
			var tail := s.substr(i + needle.length())
			# `n/a` = 嗰個 build 攞唔到呢個數。跳過,唔可以當佢係 0。
			if tail.begins_with("n/a"):
				continue
			var mb := tail.split("MB")[0]
			if not mb.is_valid_float():
				continue
			out.append(float(mb))
		if out.size() >= 2:
			return {"key": key, "values": out}
	return {"key": "", "values": []}

# ---------------------------------------------------------------------------
# 開場偵測 / 收場
# ---------------------------------------------------------------------------
## Marker 仲喺度 = 上次冇行過 _close()。_close() 喺 WM_CLOSE_REQUEST、
## EXIT_TREE 同 quit() 都會行,所以剩返嘅可能性就係 process 被殺 —— 閃退。
##
## 但要先排除一個假陽性:**另一個仲行緊嘅 instance**。開發同測試機上面兩個
## process 同時開得,而第二個見到第一個嘅活 marker 就會報一單根本冇發生過嘅
## 閃退。所以 marker 入面記住 pid,見到嗰個 pid 仲活住就當佢係兄弟唔係屍體,
## 乜都唔做(連刪都唔刪 —— 嗰個 marker 係人哋嘅)。
func _detect_previous_crash() -> void:
	if not FileAccess.file_exists(MARKER):
		return
	# 網頁版:個 marker 檔講唔到嘢。刪佢要等 IDBFS 非同步同步,而 pagehide
	# 之後個 tab 即刻死,所以一個**正常**熄咗嘅 tab 都會留低個檔。真正嘅
	# 一 bit 訊號喺 localStorage(同步、即時持久)。個檔淨係用嚟攞麵包屑。
	if OS.has_feature("web") and _ls_get() == "":
		print("[Crash] 上一次收得正常(localStorage),清走殘留 marker")
		DirAccess.remove_absolute(MARKER)
		return
	var txt := FileAccess.get_file_as_string(MARKER)
	var data = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		data = {"crumbs": [txt]}
	var pid: int = int(data.get("pid", 0))
	if pid > 0 and pid != OS.get_process_id() and OS.is_process_running(pid):
		print("[Crash] 另一個 instance (pid %d) 仲行緊,唔當佢係閃退" % pid)
		return
	last_crash = data
	var f := FileAccess.open(CRASH_LOG, FileAccess.READ_WRITE if FileAccess.file_exists(CRASH_LOG) else FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line("")
		f.store_line("=== 上一次啟動非正常結束 (偵測時間 %s) ===" % Time.get_datetime_string_from_system())
		f.store_line("session: %s  started: %s" % [data.get("session", "?"), data.get("started", "?")])
		for c in data.get("crumbs", []):
			f.store_line("  " + str(c))
		f.close()
	# 印出嚟先:headless 跑嘅時候 stdout 就係唯一睇得到嘅嘢
	print("[Crash] 偵測到上一次啟動非正常結束,已寫入 %s" % CRASH_LOG)
	for c in data.get("crumbs", []):
		print("[Crash]   " + str(c))
	DirAccess.remove_absolute(MARKER)

## 正常收場。刪 marker = 「呢次唔算閃退」。
func _close() -> void:
	if _closed:
		return
	_closed = true
	if FileAccess.file_exists(MARKER):
		DirAccess.remove_absolute(MARKER)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE \
			or what == NOTIFICATION_PREDELETE:
		_close()
