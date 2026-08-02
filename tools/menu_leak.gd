extends Node
## 重放一單真閃退嘅麵包屑,逐步量記憶體。
##
##   Godot --path . tools/menu_leak.tscn -- --loops=6
##
## 2026-08-02 由用戶部 iPhone 收返嚟嘅閃退報告係咁樣:
##
##     0.59 boot   /  5.80 Shop  /  7.63 MainMenu /  8.30 Upgrade
##    15.86 MainMenu / 17.58 Upgrade / 21.34 MainMenu / 22.76 Gallery
##    31.04 MainMenu   <- 之後死
##
## 三件事值得留意:**冇入過戰鬥**、**31 秒**、**死之前最後去咗美術畫廊**。
## 即係話個死因(如果係記憶體)喺選單流程入面,唔喺戰場 —— 而戰場先係之前
## 幾輪落過功夫嘅地方(池上限、fx 預算)。選單流程唯一會單向增長嘅嘢就係
## 「切場景之後有冇還返」,所以呢個工具問嘅就係嗰條:同一串畫面行幾轉,
## static memory / 物件數 / 節點數會唔會一轉高過一轉。
##
## 用真 change_scene_to_file(唔係 add_child):Godot 係**延遲**釋放現行場景嘅,
## 而一個「加咗又即刻 free」嘅測試根本行唔到同一條路。

func _ready() -> void:
	# change_scene_to_file() 會釋放**現行場景**,而呢個節點就係現行場景。
	# 所以真正跑嘢嗰個 driver 要掛喺 root 底下做現行場景嘅兄弟,唔係掛喺呢度 ——
	# 唔係嘅話佢第一次切場景就連自己一齊 free 咗,全部 await 永遠唔會 resume,
	# 個 process 就靜靜咁坐喺主選單度直到有人殺佢。
	# (SoakTest 有一模一樣嘅註解,而我第一版照樣中招。)
	var drv := _Driver.new()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--loops="):
			drv.loops = maxi(1, int(a.substr(8)))
	get_tree().root.call_deferred("add_child", drv)


class _Driver extends Node:
	const STEPS := [
		["MainMenu", "res://scenes/MainMenu.tscn"],
		["Shop", "res://scenes/Shop.tscn"],
		["MainMenu", "res://scenes/MainMenu.tscn"],
		["Upgrade", "res://scenes/Upgrade.tscn"],
		["MainMenu", "res://scenes/MainMenu.tscn"],
		["Upgrade", "res://scenes/Upgrade.tscn"],
		["MainMenu", "res://scenes/MainMenu.tscn"],
		["Gallery", "res://scenes/Gallery.tscn"],
		["MainMenu", "res://scenes/MainMenu.tscn"],
	]
	## 每轉入面有幾多個 MainMenu —— 用嚟由 rows 入面揀返每轉最後嗰個。
	const MENUS_PER_LOOP := 5

	var loops := 6
	var rows: Array = []

	func _ready() -> void:
		# 呢個工具唔應該自己留低一個「上次閃退」嘅假陽性
		Crash.enabled = false
		Meta.unlocked_towers = range(1, 21)
		Meta.unlocked_spells = range(1, 16)
		Meta.crystals = 999999
		await get_tree().process_frame
		_sample("boot", 0)
		for i in loops:
			for st in STEPS:
				await _goto(String(st[1]))
				_sample(String(st[0]), i + 1)
		_report()
		get_tree().quit(0)

	func _goto(path: String) -> void:
		get_tree().change_scene_to_file(path)
		# 切場景係延遲嘅,而舊場景要下一幀先真係走。多等幾幀,連 queue_free 同
		# RenderingServer 嗰邊嘅回收都行完先量 —— 唔係就會量到一啲仲未死嘅嘢。
		for i in 12:
			await get_tree().process_frame

	func _sample(label: String, loop: int) -> void:
		rows.append({
			"loop": loop,
			"label": label,
			"static_mb": float(Performance.get_monitor(Performance.MEMORY_STATIC)) / 1048576.0,
			"video_mb": float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / 1048576.0,
			"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		})

	func _report() -> void:
		print("LEAK  loop | screen    | static MB | video MB | objects | nodes | orphans")
		for r in rows:
			print("LEAK  %4d | %-9s | %9.2f | %8.2f | %7d | %5d | %7d"
				% [r.loop, r.label, r.static_mb, r.video_mb, r.objects, r.nodes, r.orphans])
		# 每一轉**收場嗰個 MainMenu** 先係可比嘅點:同一個畫面、同一個狀態。
		var menus: Array = []
		for r in rows:
			if r.label == "MainMenu" and r.loop > 0:
				menus.append(r)
		var per_loop: Array = []
		var i := MENUS_PER_LOOP - 1
		while i < menus.size():
			per_loop.append(menus[i])
			i += MENUS_PER_LOOP
		print("LEAK ---- 每轉收場時嘅主選單 ----")
		for r in per_loop:
			print("LEAK  第 %d 轉: static %.2f MB  video %.2f MB  objects %d  nodes %d"
				% [r.loop, r.static_mb, r.video_mb, r.objects, r.nodes])
		if per_loop.size() >= 2:
			var a: Dictionary = per_loop[0]
			var b: Dictionary = per_loop[-1]
			var n: int = per_loop.size() - 1
			print("LEAK 由第 1 轉到第 %d 轉:static %+.2f MB (%+.3f MB/轉),objects %+d (%+.1f/轉),nodes %+d"
				% [per_loop.size(), b.static_mb - a.static_mb,
				(b.static_mb - a.static_mb) / float(n),
				b.objects - a.objects, float(b.objects - a.objects) / float(n),
				b.nodes - a.nodes])
