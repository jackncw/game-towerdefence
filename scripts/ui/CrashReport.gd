extends Control
class_name CrashReport
## 除錯記錄檢視器。
##
## **第 24 輪(上架前)改咗佢嘅身份。** 佢本來係一個會自己彈出嚟嘅「上次係
## 閃退」畫面,住喺主選單 `_ready()` 度。而家玩家永遠唔會見到佢:唯一入口
## 係設定頁長撳版本號五秒(見 `Settings.gd`)。
##
## 點解淨係搬入面唔剷:user:// 喺 iOS 嘅網頁版係收喺 IndexedDB 入面 —— 唔係
## 一個檔案夾,係一個瀏覽器內部資料庫。玩家(同埋我)喺一部 iPhone 上面根本
## 掘唔到嗰個檔。一份寫咗但冇人讀得到嘅記錄同冇寫係一樣嘅,所以「行到出嚟
## 畀人睇 + 一撳複製得走」呢個能力要留住。變嘅淨係「幾時出現」。
##
## 兩種內容,自動揀:
##   * 有偵測到上次閃退  -> 顯示嗰次嘅報告(麵包屑 + 記憶體趨勢)
##   * 冇                -> 顯示**今次開機到而家**嘅麵包屑,咁佢喺一部
##                          冇閃退過嘅機上面都仲係有用(可以貼返個現場)

## 由呼叫者填。空 = 冇嘢報告(呢個節點會自己收皮)。
var report: String = ""
## `Crash.last_crash_memory_trend()` 嘅原樣:{"key": …, "values": […]}。
var trend: Dictionary = {}
## 標題/引言用邊套字。true = 由設定頁人手開嘅除錯檢視器。
var debug_mode: bool = false
## 冇閃退記錄,顯示緊今次開機嘅麵包屑。
var live_only: bool = false

var _copied: bool = false
var _copy_label: Label

## 除錯入口(設定頁長撳版本號)。**一定開得到** —— 冇閃退記錄就顯示今次
## 開機嘅麵包屑,而唔係乜都唔做(一個「撳完乜都冇發生」嘅隱藏功能同壞咗
## 一模一樣)。
static func present_debug(parent: Control) -> CrashReport:
	var r := CrashReport.new()
	r.debug_mode = true
	if Crash.last_crash.is_empty():
		r.live_only = true
		r.report = Crash.live_report()
		r.trend = {}
	else:
		r.report = Crash.last_crash_report()
		r.trend = Crash.last_crash_memory_trend()
	parent.add_child(r)
	return r

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 300
	# 底下嘅主選單唔可以撳得到 —— 個報告係一個 modal。
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.015, 0.01, 0.88)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var card := UI.panel_rect()
	card.position = Vector2(40, 200)
	card.size = Vector2(1000, 1420)
	add_child(card)

	var title := UI.title(tr("CRASH_DEBUG_TITLE" if debug_mode else "CRASH_TITLE"), 52)
	title.position = Vector2(60, 236)
	title.size = Vector2(960, 70)
	title.add_theme_color_override("font_color",
		UI.GOLD if debug_mode else UI.DANGER.lightened(0.35))
	add_child(title)

	var lead := UI.label(tr("CRASH_DEBUG_LEAD") if debug_mode else tr("CRASH_LEAD"), 26, UI.TEXT)
	lead.position = Vector2(80, 318)
	lead.size = Vector2(920, 96)
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(lead)

	if live_only:
		var note := UI.label(tr("CRASH_DEBUG_LIVE"), 24, UI.TEXT_DIM)
		note.position = Vector2(80, 432)
		note.size = Vector2(920, 60)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(note)
	else:
		add_child(_memory_strip())

	# 麵包屑本體。等寬字型:每行頭嗰個時間戳對齊咗先睇得出「幾時開始唔妥」。
	var box := ScrollContainer.new()
	box.position = Vector2(76, 630)
	box.size = Vector2(928, 830)
	box.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(box)
	TouchScroll.attach(box)
	var body := UI.label(report, 20, UI.TEXT_DIM)
	body.custom_minimum_size = Vector2(908, 0)
	body.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	box.add_child(body)

	var copy := UI.button("", Vector2(440, 116), UI.PANEL_HI, 32)
	copy.position = Vector2(76, 1480)
	_copy_label = UI.label(tr("CRASH_COPY"), 32, UI.TEXT)
	_copy_label.size = Vector2(440, 116)
	_copy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_copy_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	copy.add_child(_copy_label)
	copy.pressed.connect(_on_copy)
	add_child(copy)

	var go := UI.button(tr("CRASH_CLOSE" if debug_mode else "CRASH_CONTINUE"),
		Vector2(440, 116), UI.ACCENT, 32)
	go.position = Vector2(564, 1480)
	go.pressed.connect(queue_free)
	add_child(go)

## 記憶體趨勢。用一條摺線而唔係一串數字:「爆記憶體」嘅簽名係一條唔會落返
## 嚟嘅斜線,而嗰個形狀一眼睇得出,一串數字要人心算。
func _memory_strip() -> Control:
	var wrap := Control.new()
	wrap.position = Vector2(76, 428)
	wrap.size = Vector2(928, 180)
	var head := UI.label(tr("CRASH_MEMORY"), 26, UI.GOLD)
	head.position = Vector2(0, 0)
	head.size = Vector2(600, 36)
	wrap.add_child(head)
	var values: Array = trend.get("values", [])
	if values.size() < 2:
		var none := UI.label(tr("CRASH_MEMORY_NONE"), 22, UI.TEXT_DIM)
		none.position = Vector2(0, 42)
		none.size = Vector2(900, 40)
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wrap.add_child(none)
		return wrap
	var peak: float = 0.0
	for v in values:
		peak = maxf(peak, float(v))
	# 條線畫緊邊個數要寫喺個範圍旁邊。heap 升同 video 升係兩件事,而讀報告
	# 嗰個人淨係見到一條無名嘅斜線係判斷唔到嘅。
	var span := UI.label("%s — %s" % [
		tr("CRASH_MEMORY_" + str(trend.get("key", "")).to_upper()),
		tr("CRASH_MEMORY_RANGE").format(
			{"first": "%.1f" % float(values[0]), "last": "%.1f" % float(values[-1]),
			 "peak": "%.1f" % peak}),
	], 22, UI.TEXT)
	span.position = Vector2(0, 40)
	span.size = Vector2(900, 34)
	wrap.add_child(span)
	var plot := _Sparkline.new()
	plot.values = values
	plot.position = Vector2(0, 82)
	plot.size = Vector2(908, 90)
	wrap.add_child(plot)
	return wrap

func _on_copy() -> void:
	DisplayServer.clipboard_set(report)
	_copied = true
	if _copy_label != null:
		_copy_label.text = tr("CRASH_COPIED")
	UI.toast(self, tr("CRASH_COPIED"), UI.GOLD)

func was_copied() -> bool:
	return _copied

class _Sparkline extends Control:
	var values: Array = []

	func _draw() -> void:
		if values.size() < 2:
			return
		var lo: float = INF
		var hi: float = -INF
		for v in values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		# 一條平線都要有高度,唔係嘅話 span=0 會除零,而且「完全冇升過」
		# 本身就係一個結論,唔應該畫成一條貼住底嘅線。
		var span: float = maxf(hi - lo, 0.001)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.065, 0.05, 0.9))
		var pts := PackedVector2Array()
		for i in values.size():
			var x: float = size.x * float(i) / float(values.size() - 1)
			var y: float = size.y - (float(values[i]) - lo) / span * (size.y - 10.0) - 5.0
			pts.append(Vector2(x, y))
		draw_polyline(pts, UI.GOLD, 3.0)
		for p in pts:
			draw_circle(p, 4.0, UI.GOLD.lightened(0.3))
