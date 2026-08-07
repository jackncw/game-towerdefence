extends Node
## Part 0 診斷工具:量 GateSim 模擬玩家嘅**擺塔位質素**。
##
## GateSim._spots() 攞晒 build 區入面全部合法格,再**按沿路程序**排(
## `route.nearest_dist_param`),然後由頭到尾順住擺。呢個排序講嘅係「最近嘅
## 路點喺路嘅幾多%」,唔係「離條路有幾遠」—— 所以一個喺地圖角落、離路
## 400px、但最近路點啱啱係路嘅開頭嘅格,會**排喺第一批**擺。
##
## 呢個 harness 印出頭 N 個會被擺嘅位:離路距離、以及「射程 260 之內覆蓋到
## 幾多路程」。再對照一個按覆蓋率排序嘅「強策略」次序,量兩者嘅覆蓋率差。
##
## 用法:godot --headless --path . res://test/StratDiag.tscn -- --lv=20 --n=14

const RANGE_REF := 260.0     # 箭塔基礎射程

var lv := 20
var n_towers := 14

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.nav_enabled = false
	get_tree().paused = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lv="):
			lv = int(a.substr(5))
		elif a.begins_with("--n="):
			n_towers = int(a.substr(4))
	await _run()
	get_tree().paused = false
	print("STRATDIAG REPORT-ONLY(擺位策略診斷,冇斷言)")
	get_tree().quit(0)

func _run() -> void:
	Flow.selected_level = lv
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame

	var spots: Array = _all_spots(b)
	print("DIAG lv=%d 合法格=%d 路長=%.0f" % [lv, spots.size(), b.route.total])

	# --- 現行排序:沿路程序 -------------------------------------------------
	var cur: Array = spots.duplicate()
	cur.sort_custom(func(a, c): return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))
	# --- 強策略排序:覆蓋路程長度(打和先睇沿路早) -------------------------
	var strong: Array = spots.duplicate()
	var cov := {}
	for p in spots:
		cov[p] = _coverage(b, p, RANGE_REF)
	strong.sort_custom(func(a, c):
		if abs(float(cov[a]) - float(cov[c])) > 1.0:
			return float(cov[a]) > float(cov[c])
		return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))

	print("DIAG HDR rank cur_x cur_y cur_dist cur_cov str_x str_y str_dist str_cov")
	var sc := 0.0
	var ss := 0.0
	for i in mini(n_towers, spots.size()):
		var a: Vector2 = cur[i]
		var s: Vector2 = strong[i]
		sc += float(cov[a])
		ss += float(cov[s])
		print("DIAG ROW %d %.0f %.0f %.0f %.0f %.0f %.0f %.0f %.0f"
			% [i, a.x, a.y, b.route.dist_to_route(a), float(cov[a]),
			s.x, s.y, b.route.dist_to_route(s), float(cov[s])])
	print("DIAG SUM n=%d cur_cov_total=%.0f strong_cov_total=%.0f ratio=%.2f"
		% [n_towers, sc, ss, ss / maxf(1.0, sc)])
	# 零覆蓋(完全打唔到路)嘅塔有幾多座
	var dead := 0
	for i in mini(n_towers, spots.size()):
		if float(cov[cur[i]]) <= 0.0:
			dead += 1
	print("DIAG DEAD cur=%d/%d" % [dead, mini(n_towers, spots.size())])
	b.queue_free()
	await get_tree().process_frame

## 射程 r 覆蓋到幾多路程(沿路取樣 8px)
func _coverage(b, p: Vector2, r: float) -> float:
	var tot: float = b.route.total
	var d := 0.0
	var hit := 0.0
	while d < tot:
		if b.route.pos_at(d).distance_to(p) <= r:
			hit += 8.0
		d += 8.0
	return hit

func _all_spots(b) -> Array:
	var out: Array = []
	var step := 74.0
	var lo: Vector2 = b.BUILD_MIN
	var hi: Vector2 = b.BUILD_MAX
	var y: float = lo.y
	while y <= hi.y:
		var x: float = lo.x
		while x <= hi.x:
			var p: Vector2 = b.snap(Vector2(x, y))
			if b.can_place(p):
				out.append(p)
			x += step
		y += step
	return out
