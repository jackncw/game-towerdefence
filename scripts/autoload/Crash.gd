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

var _crumbs: Array = []
var _dirty: bool = false
var _last_flush_ms: int = 0
var _session_id: String = ""
var _closed: bool = false

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
	if not _dirty or not enabled:
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

func _process(_delta: float) -> void:
	_maybe_flush()

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
