extends Node
## 塔位容量盤點(第十八輪 Part 0)。
##
## 「合法格」唔等於「擺得落幾多座」:snap 格距 74px 而 TOWER_SPACING 係 78px
## —— 即係話兩個**正交相鄰**嘅格互相排斥(74 < 78),斜對角就得(104.6 > 78)。
## 所以真容量係一個棋盤格填充,大約係合法格數嘅一半,而唔係佢本身。
##
## 呢個工具用同 GateSim._spots() 一模一樣嘅格網同 can_place(),再貪心咁逐個
## 落假塔(只計位,唔起真塔),量六款 path 模板嘅**實際**容量。
##
## 用法:godot --headless --path . res://tools/slotcap.tscn

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.nav_enabled = false
	get_tree().paused = true
	await _run()
	get_tree().paused = false
	get_tree().quit(0)

func _run() -> void:
	print("CAP HDR lv tmpl route_len cells packed_74 packed_free")
	for lv in range(1, 7):
		Flow.selected_level = lv
		Flow.last_result = {}
		var b = load("res://scenes/Battle.tscn").instantiate()
		b.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(b)
		await get_tree().process_frame
		var cells: Array = _cells(b)
		print("CAP ROW %d %d %.0f %d %d %d" % [
			lv, (lv - 1) % 6, b.route.total, cells.size(),
			_pack(b, cells), _pack(b, _cells_fine(b, 26.0))])
		b.queue_free()
		await get_tree().process_frame

## GateSim._spots() 嘅格網(snap 74px)
func _cells(b) -> Array:
	var out: Array = []
	var y: float = b.BUILD_MIN.y
	while y <= b.BUILD_MAX.y:
		var x: float = b.BUILD_MIN.x
		while x <= b.BUILD_MAX.x:
			var p: Vector2 = b.snap(Vector2(x, y))
			if b.can_place(p):
				out.append(p)
			x += 74.0
		y += 74.0
	return out

## 唔靠 snap 格嘅細網 —— 量「理論上最多擺幾多」(自由擺位嘅上限)
func _cells_fine(b, step: float) -> Array:
	var out: Array = []
	var y: float = b.BUILD_MIN.y
	while y <= b.BUILD_MAX.y:
		var x: float = b.BUILD_MIN.x
		while x <= b.BUILD_MAX.x:
			var p := Vector2(x, y)
			if b.can_place(p):
				out.append(p)
			x += step
		y += step
	return out

## 貪心填充:逐個位落,同已落嘅保持 TOWER_SPACING。
func _pack(b, cells: Array) -> int:
	var taken: Array[Vector2] = []
	for p in cells:
		var ok := true
		for q in taken:
			if q.distance_to(p) < b.TOWER_SPACING:
				ok = false
				break
		if ok:
			taken.append(p)
	return taken.size()
