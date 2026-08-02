extends Control
class_name CrashReport
## 「上次係閃退」嘅報告畫面。開機第一個畫面(主選單)見到 Crash.last_crash
## 有嘢就彈呢個。
##
## 點解要有一個畫面而唔係淨係寫入 user://logs/:
##
## user:// 喺 iOS 嘅網頁版係收喺 IndexedDB 入面 —— 唔係一個檔案夾,係一個
## 瀏覽器內部資料庫。玩家(同埋我)喺一部 iPhone 上面根本掘唔到嗰個檔。
## 一份寫咗但冇人讀得到嘅記錄同冇寫係一樣嘅,所以呢一輪嘅閃退證物要**行到
## 出嚟畀人睇**,而且要一撳就複製得走。
##
## 三個掣:複製、繼續遊戲。冇「唔好再顯示」—— 呢個畫面一世只會喺一單真閃退
## 之後出現一次(marker 讀完即刪),而如果佢日日出現,咁佢日日都係啱嘅。

## 由呼叫者填。空 = 冇嘢報告(呢個節點會自己收皮)。
var report: String = ""
var trend: Array = []

var _copied: bool = false
var _copy_label: Label

## 掛喺 `parent` 上面。上次唔係閃退就乜都唔做,返 false。
static func present(parent: Control) -> bool:
	if Crash.last_crash.is_empty():
		return false
	var r := CrashReport.new()
	r.report = Crash.last_crash_report()
	r.trend = Crash.last_crash_memory_trend()
	# 讀完就當交咗差:同一單閃退唔會喺下一次開場再彈一次。
	Crash.last_crash = {}
	parent.add_child(r)
	return true

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

	var title := UI.title(tr("CRASH_TITLE"), 52)
	title.position = Vector2(60, 236)
	title.size = Vector2(960, 70)
	title.add_theme_color_override("font_color", UI.DANGER.lightened(0.35))
	add_child(title)

	var lead := UI.label(tr("CRASH_LEAD"), 26, UI.TEXT)
	lead.position = Vector2(80, 318)
	lead.size = Vector2(920, 96)
	lead.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lead.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	add_child(lead)

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

	var go := UI.button(tr("CRASH_CONTINUE"), Vector2(440, 116), UI.ACCENT, 32)
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
	if trend.size() < 2:
		var none := UI.label(tr("CRASH_MEMORY_NONE"), 22, UI.TEXT_DIM)
		none.position = Vector2(0, 42)
		none.size = Vector2(900, 40)
		wrap.add_child(none)
		return wrap
	var peak: float = 0.0
	for v in trend:
		peak = maxf(peak, float(v))
	var span := UI.label(tr("CRASH_MEMORY_RANGE").format(
		{"first": "%.1f" % float(trend[0]), "last": "%.1f" % float(trend[-1]),
		 "peak": "%.1f" % peak}), 22, UI.TEXT)
	span.position = Vector2(0, 40)
	span.size = Vector2(900, 34)
	wrap.add_child(span)
	var plot := _Sparkline.new()
	plot.values = trend
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
