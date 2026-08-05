extends Node
## 節點洩漏回歸:「開咗又關,還唔還得清」。
##
## 點解要同 SoakTest 分家:SoakTest 問「連續咁玩會唔會死」,佢答唔到「係邊一
## 個開關循環喺度滲」。一單真閃退報告(2026-08-02,iPhone,31 秒,冇入過戰鬥)
## 指住嘅係**選單流程**,而選單流程唯一會單向增長嘅嘢就係「切走之後有冇還返」。
##
## 三個循環,每個行 CYCLES 轉,每轉之後量 OBJECT_NODE_COUNT:
##   A. 戰鬥場景 instantiate -> queue_free
##   B. 戰鬥入面嘅 overlay(暫停選單 / 抽屜 / 圖鑑)開 -> 關
##   C. 選單場景 instantiate -> queue_free
##
## B 一定要喺 **paused** 之下做:唔 pause 嘅話 pool 會因為打緊仗而長高,而
## 嗰個增長係合法嘅(pool 去到高水位就唔再升),混埋落嚟就分唔清邊個係 leak。
## Pause 之後場上冇嘢郁,剩返嘅淨係 overlay 自己嘅節點 —— 就係要測嗰樣。
##
## 判斷:每個循環嘅**淨增長必須係 0**。孤兒節點(OBJECT_ORPHAN_NODE_COUNT)
## 亦都必須係 0 —— 一個 queue_free 咗但仲喺 ObjectDB 度嘅節點就係 leak 本身。
##
## Run: godot --headless --path . res://test/LeakTest.tscn

const CYCLES := 20
## 一個 queue_free 要下一幀先真係死,而 RenderingServer 嗰邊仲要多幾幀。
## 量得太早就會將「仲未死」讀成「洩漏」。
const SETTLE_FRAMES := 8

var _fails: Array = []
var _lines: Array = []

func _ready() -> void:
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.crystals = 999999
	await _settle()

	await _cycle_battle_scene()
	await _cycle_battle_overlays()
	await _cycle_contract_cards()
	await _cycle_menu_scenes()

	Flow.nav_enabled = true
	for l in _lines:
		print(l)
	if _fails.is_empty():
		print("LEAK PASS fails=0")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("LEAK FAIL " + f)
		print("LEAK FAIL fails=%d" % _fails.size())
		get_tree().quit(1)

func _settle() -> void:
	for i in SETTLE_FRAMES:
		await get_tree().process_frame

func _nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

func _orphans() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))

## 一個循環嘅收數。`base` 係第一轉之後嘅節點數 —— 唔用第零轉,因為第一轉會
## 順手暖埋 texture cache / autoload 嗰啲一次性嘢,而嗰啲唔係 leak。
func _check(name: String, base: int, last: int, orph: int) -> void:
	var grow := last - base
	_lines.append("LEAK  %-22s 第1轉後=%d  第%d轉後=%d  淨增長=%+d  孤兒=%d"
		% [name, base, CYCLES, last, grow, orph])
	if grow != 0:
		_fails.append("%s 節點淨增長 %+d(要求 0)" % [name, grow])
	if orph != 0:
		_fails.append("%s 孤兒節點 %d(要求 0)" % [name, orph])

# ---------------------------------------------------------------------------
# A. 戰鬥場景開關
# ---------------------------------------------------------------------------
func _cycle_battle_scene() -> void:
	var base := -1
	var last := 0
	for i in CYCLES:
		var b = load("res://scenes/Battle.tscn").instantiate()
		add_child(b)
		# 行夠幾幀等 pool prewarm、HUD 起完、第一批怪出咗
		for k in 6:
			await get_tree().process_frame
		b.queue_free()
		await _settle()
		Engine.time_scale = 1.0
		if i == 0:
			base = _nodes()
		last = _nodes()
	_check("戰鬥場景 x%d" % CYCLES, base, last, _orphans())

# ---------------------------------------------------------------------------
# B. 戰鬥入面嘅 overlay
# ---------------------------------------------------------------------------
func _cycle_battle_overlays() -> void:
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	for k in 6:
		await get_tree().process_frame
	# 凍結場面:pool 唔再長高,剩返嘅變化就淨係 overlay 自己
	get_tree().paused = true
	await _settle()

	var base := -1
	var last := 0
	for i in CYCLES:
		# 暫停選單
		b.hud._toggle_pause()
		await get_tree().process_frame
		# 圖鑑 overlay(由暫停選單開,關返自己 queue_free)
		b.hud._open_bestiary_overlay()
		for k in 3:
			await get_tree().process_frame
		var bs: Node = null
		for c in b.hud.get_children():
			if c.get_script() != null and c.get_script().resource_path.ends_with("Bestiary.gd"):
				bs = c
		if bs != null:
			bs._go_back()
		await _settle()
		# 抽屜
		b.hud._set_drawer(true)
		await get_tree().process_frame
		b.hud._set_drawer(false)
		await get_tree().process_frame
		# 收返暫停選單
		if get_tree().paused:
			b.hud._toggle_pause()
		get_tree().paused = true
		await _settle()
		if i == 0:
			base = _nodes()
		last = _nodes()
	_check("戰鬥 overlay x%d" % CYCLES, base, last, 0)

	get_tree().paused = false
	b.queue_free()
	await _settle()
	Engine.time_scale = 1.0

# ---------------------------------------------------------------------------
# D. 合約卡片開關(第十五輪)
#
# 合約卡片係整個遊戲入面**開關次數最密**嘅 overlay:一場合約關開五次,而一個
# farm 緊嘅玩家一晚可以打幾十場。佢又係一個逐次由零砌返嘅 Control 樹(三張卡
# 各自有色帶 / 兩個 clip / 五個 Label),所以佢正正就係「開咗又關,還唔還得清」
# 呢條問題嘅最壞情況。
# ---------------------------------------------------------------------------
func _cycle_contract_cards() -> void:
	Flow.selected_level = 7          # 逢 7 = 合約關
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	for k in 6:
		await get_tree().process_frame
	get_tree().paused = true
	# 開場果次抽卡已經攤咗喺度,收返佢先開始數。`contract_pending` 亦都要清 ——
	# 唔清嘅話「當前合約狀態」個掣會當你仲揀緊卡而直接 return,咁樣個循環就
	# 變成一個乜都冇做嘅循環,而一個乜都冇做嘅循環永遠唔會 fail。
	b.hud.hide_contract()
	b.contract_pending = false
	await _settle()
	var base := -1
	var last := 0
	for i in CYCLES:
		b.hud.show_contract(GameData.contract_draw())
		await get_tree().process_frame
		b.hud.hide_contract()
		await get_tree().process_frame
		# 「當前合約狀態」嗰個 summary 面板行嘅係同一條路,一併入循環
		b.hud._toggle_contract_summary()
		await get_tree().process_frame
		b.hud._toggle_contract_summary()
		await _settle()
		if i == 0:
			base = _nodes()
		last = _nodes()
	_check("合約卡片 x%d" % CYCLES, base, last, 0)
	get_tree().paused = false
	b.queue_free()
	await _settle()
	Engine.time_scale = 1.0
	Flow.selected_level = 1

# ---------------------------------------------------------------------------
# C. 選單場景開關
# ---------------------------------------------------------------------------
const MENUS := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Upgrade.tscn",
	"res://scenes/Bestiary.tscn",
	"res://scenes/QuickBar.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/LevelSelect.tscn",
]

func _cycle_menu_scenes() -> void:
	var base := -1
	var last := 0
	for i in CYCLES:
		for path in MENUS:
			var s = load(path).instantiate()
			add_child(s)
			for k in 3:
				await get_tree().process_frame
			s.queue_free()
			await get_tree().process_frame
		await _settle()
		if i == 0:
			base = _nodes()
		last = _nodes()
	_check("選單場景 x%d" % CYCLES, base, last, _orphans())
