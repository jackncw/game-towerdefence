extends Node
## 量一件事,一件咋:`Crash.mem_line()` 入面每一個 Performance monitor,喺
## **debug** 同 **release** 兩種 build 之下分別報乜。
##
## 點解要有:第二份真閃退報告入面,`static=` 由頭到尾都係 `0.0MB` —— 55 分鐘
## 30 幾個採樣,video / obj / node / fps 全部郁,靜靜地淨係嗰個數唔郁。一個
## 真係 0.0 MB 嘅 static heap 係冇可能嘅,所以問題唔喺個遊戲度,喺個 monitor
## 度。而 `Crash.last_crash_memory_trend()` 恰恰就係 parse `static=` 嗰個數 ——
## 即係話成條 OOM 曲線可能係一條永遠貼住零嘅平線。
##
## 呢個 probe 唔靠記憶去斷定,佢兩邊都跑一次然後夾。
##
## 用法:
##   debug   : Godot_v4.7.1.exe --headless --path . res://tools/mem_probe.tscn
##   release : 匯出成 Windows console build 再直接行(見 tools/mem_probe.md)

const SAMPLES := 3
const GAP := 0.4

var _n := 0
var _t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[memprobe] build=%s debug_build=%s" % [
		"debug" if OS.is_debug_build() else "RELEASE",
		str(OS.is_debug_build()),
	])
	# 逐個 monitor 分開報,唔係淨係報 mem_line() —— 要睇得出邊一個係零。
	_dump("boot")

func _process(delta: float) -> void:
	_t += delta
	if _t < GAP:
		return
	_t = 0.0
	_n += 1
	# 分配一舊嘢先,咁「static 有冇郁」呢條問題先有意義。
	var ballast := PackedByteArray()
	ballast.resize(4 * 1024 * 1024)
	ballast.fill(_n)
	_dump("sample%d(+4MB)" % _n)
	if _n >= SAMPLES:
		print("[memprobe] done")
		get_tree().quit(0)

func _dump(tag: String) -> void:
	print("[memprobe] %-16s MEMORY_STATIC=%d  MEMORY_STATIC_MAX=%d  VIDEO=%d  obj=%d node=%d" % [
		tag,
		int(Performance.get_monitor(Performance.MEMORY_STATIC)),
		int(Performance.get_monitor(Performance.MEMORY_STATIC_MAX)),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	])
	print("[memprobe] %-16s mem_line: %s" % [tag, Crash.mem_line()])
