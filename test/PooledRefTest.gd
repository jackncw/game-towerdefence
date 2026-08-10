extends Node
## 池化節點嘅**身份規則**。
##   godot --headless --path . res://test/PooledRefTest.tscn
##
## 呢個 test 守住嘅唔係一個功能,係一條**規則**:
##
##   `Pool.release()` 唔係 `queue_free()`。個節點會坐喺 free stack 頂,而下一次
##   `acquire()` 就攞返同一個節點,`setup()` 再將 `alive` 設返 true。所以**任何
##   跨幀持有嘅池化節點參照,唔驗 generation(`serial`)就一定係錯嘅。**
##   `is_instance_valid()` 一啲保護作用都冇 —— 個節點由頭到尾都有效,佢淨係
##   換咗身份。
##
## 呢條規則第 23 輪由一單真機 bug 度學返嚟(第 100 關十隻 boss 死晒但關卡永遠
## 唔結算,小怪無限出)。個 bug 本身喺 `test/Level100CompletionTest` 度守住;
## 呢度守嘅係**同一類**嘅其餘現場,因為當時全 project 掃出七個。
##
## 三組:
##   A  機制本身 —— `Pool.live()` 對「回收咗」呢件事真係識講唔
##   B  逐個現場 —— 每一個跨幀持有者,砌返「參照已經轉世」嗰個狀態,斷言佢
##      唔會認錯人
##   C  靜態掃描 —— 新加嘅 code 唔可以再引入一個「淨係問 alive」嘅跨幀檢查

const DT := 1.0 / 60.0
## 唔可以用逢 7 嘅倍數關(合約關開場凍住成個場)。同 BossFloorTest 一樣嘅坑。
const LEVEL := 12

var fails: Array[String] = []
var checked := 0

func _ok(what: String, cond: bool) -> void:
	checked += 1
	if not cond:
		fails.append(what)

func _ready() -> void:
	get_tree().create_timer(180.0, true, false, true).timeout.connect(
		func(): print("POOLREF TIMEOUT"); get_tree().quit(1))
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)

	await _case_pool_live_contract()
	await _case_recycle_is_lifo()
	await _case_streak_target()
	await _case_gatling_heat()
	await _case_beam_ramp()
	await _case_conductor()
	await _case_boss_ref()
	await _case_skeleton_lord()
	await _case_barracks_roster()
	_case_static_scan()

	if fails.is_empty():
		print("POOLREF PASS fails=0 (%d 項)" % checked)
		get_tree().quit(0)
		return
	for f in fails:
		print("  FAIL " + f)
	print("POOLREF FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

# ---------------------------------------------------------------------------
func _mk():
	Flow.selected_level = LEVEL
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	get_tree().paused = true
	b.gold = 99999999
	b.base_shield = 99999999
	# 自然刷怪會打亂 pool 嘅次序,而呢個 test 要**自己**控制邊個節點幾時被回收。
	b.boss_time = 1.0e9
	b.spawn_timer = 1.0e9
	b.cfg.spawn_interval_start = 1.0e9
	b.cfg.spawn_interval_min = 1.0e9
	return b

func _drop(b) -> void:
	get_tree().paused = false
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

## 殺一隻怪,再即刻 spawn 一隻 —— free stack 係 LIFO,所以新嗰隻**就係**同一個
## 節點。返新嗰隻。
func _recycle(b, m):
	m.take_true(1.0e9)
	return b._spawn_monster("goblin", 1, false, 0.0)

# --- A. 機制 ----------------------------------------------------------------
func _case_pool_live_contract() -> void:
	var b = await _mk()
	var m = b._spawn_monster("goblin", 1, false, 0.0)
	var s0: int = int(m.serial)
	_ok("A serial 要係非零", s0 != 0)
	_ok("A 生存緊嘅參照要攞得返", Pool.live(m, s0) == m)
	_ok("A null 參照要返 null", Pool.live(null, 0) == null)
	var m2 = _recycle(b, m)
	_ok("A 回收之後係同一個節點(LIFO 前提成立)", m2 == m)
	_ok("A 回收之後個節點仲係 valid(所以 is_instance_valid 擋唔到)",
		is_instance_valid(m))
	_ok("A 回收之後個節點會答『我生存』(所以 alive 都擋唔到)", m.alive)
	_ok("A 但 serial 一定要變咗", int(m.serial) != s0)
	_ok("A 舊 serial 攞唔返嘢 —— 呢個就係成條規則", Pool.live(m, s0) == null)
	_ok("A 新 serial 攞得返", Pool.live(m2, int(m2.serial)) == m2)
	await _drop(b)

func _case_recycle_is_lifo() -> void:
	# 呢個 case 存在嘅理由:上面每一個 case 都靠「殺完即刻 spawn 會攞返同一個
	# 節點」呢個前提。如果 Pool 改成 FIFO,呢批 test 會全部靜靜咁變成「乜都
	# 冇驗過」而仍然係綠色 —— 一個假嘅安全感。
	var b = await _mk()
	var same := 0
	for i in 5:
		var m = b._spawn_monster("goblin", 1, false, 0.0)
		if _recycle(b, m) == m:
			same += 1
	_ok("A pool 要係 LIFO(5 次回收攞返同一個節點,實際 %d 次)" % same, same == 5)
	await _drop(b)

# --- B. 逐個現場 ------------------------------------------------------------
func _tower(b, id: int, pos: Vector2 = Vector2(300, 300)):
	var t = b.place_tower_at(id, pos) if b.has_method("place_tower_at") else null
	if t == null:
		t = Tower.new()
		b.towers_root.add_child(t)
		t.setup(b, id, pos)
		b.towers.append(t)
	return t

## 鷹眼 / 鷹巢 / 多管火箭嘅「連續命中層數」。
func _case_streak_target() -> void:
	var b = await _mk()
	var t = _tower(b, 7)          # 狙擊塔 —— 三座用 streak 嘅其中一座
	var m = b._spawn_monster("goblin", 1, false, 0.0)
	t._bump_streak(m)
	t._bump_streak(m)
	_ok("B streak 對住同一隻要疊上去(而家 %d)" % t._streak, t._streak == 2)
	var m2 = _recycle(b, m)
	var n: int = t._bump_streak(m2)
	_ok("B 目標俾池回收之後,層數要由 1 重新數起(而家 %d)" % n, n == 1)
	await _drop(b)

## 機槍塔嘅熱度。
func _case_gatling_heat() -> void:
	var b = await _mk()
	var t = _tower(b, 8)          # 機槍塔
	_ok("B(前提)8 號要係機槍塔(而家 %s)" % t.mech, t.mech == "gatling")
	var m = b._spawn_monster("goblin", 1, false, 0.0)
	t.last_target = m
	t.last_target_serial = int(m.serial)
	_ok("B 同一隻目標要認得返", t._same_target(t.last_target, t.last_target_serial, m))
	var m2 = _recycle(b, m)
	_ok("B 回收之後唔可以認錯人(熱度會唔重置)",
		not t._same_target(t.last_target, t.last_target_serial, m2))
	await _drop(b)

## 光束塔嘅蓄能。用同一組欄位,所以驗嘅係「重置真係會發生」。
func _case_beam_ramp() -> void:
	var b = await _mk()
	var t = _tower(b, 10)         # 光束塔 —— 用真塔,唔好夾硬改 mech
	_ok("B(前提)10 號要係光束塔(而家 %s)" % t.mech, t.mech == "beam")
	var m = b._spawn_monster("goblin", 1, false, 0.0)
	t.last_target = m
	t.last_target_serial = int(m.serial)
	t.beam_ramp = 5.0
	var m2 = _recycle(b, m)
	# _proc_beam 會自己揀目標,而場上得返 m2 一隻,所以佢一定揀到佢。
	t.range_val = 99999.0
	t._proc_beam(DT)
	_ok("B 目標俾池回收之後,光束蓄能要清零(而家 %.2f)" % t.beam_ramp,
		t.beam_ramp <= 0.001)
	_ok("B 而且要重新鎖返新嗰隻", t.last_target_serial == int(m2.serial))
	await _drop(b)

## 雷霆之柱嘅導體標記。
func _case_conductor() -> void:
	var b = await _mk()
	var t = _tower(b, 3)          # 雷霆塔
	_ok("B(前提)3 號要係雷霆塔(而家 %s)" % t.mech, t.mech == "lightning")
	var m = b._spawn_monster("goblin", 1, false, 0.0)
	t._conductor = m
	t._conductor_serial = int(m.serial)
	_ok("B 導體生存緊要攞得返", Pool.live(t._conductor, t._conductor_serial) == m)
	var m2 = _recycle(b, m)
	_ok("B 導體俾池回收之後要當冇標記過(唔係就會送 CONDUCTOR_BONUS 畀一隻無辜嘅怪)",
		Pool.live(t._conductor, t._conductor_serial) == null)
	_ok("B 而且個節點本身仲係 valid + alive —— 舊嗰個檢查喺呢度會中招",
		is_instance_valid(m2) and m2.alive)
	await _drop(b)

## HUD 嘅 boss 血條 + 敗仗派彩用嘅 boss_ref。
func _case_boss_ref() -> void:
	var b = await _mk()
	var boss = b._spawn_monster("goblin", 5, true, 0.0)
	b.set_boss_ref(boss)
	_ok("B boss_ref 生存緊要攞得返", Pool.live(b.boss_ref, b.boss_ref_serial) == boss)
	# 直接砌返「參照過期」嘅狀態:唔經 on_boss_killed(佢會自己清)。
	b._remove(boss)
	b.set_boss_ref(boss)           # 扮返 _remove 之前嗰個值(serial 仲係舊嗰個)
	var m2 = b._spawn_monster("goblin", 1, false, 0.0)
	_ok("B boss 節點俾池回收成雜兵之後,boss_ref 要當佢死咗",
		Pool.live(b.boss_ref, b.boss_ref_serial) == null)
	_ok("B(前提)嗰個節點真係俾回收咗", m2 == boss)
	await _drop(b)

## 骷髏君主 —— 佢決定全場骷髏有幾多條命。
func _case_skeleton_lord() -> void:
	var b = await _mk()
	var lord = b._spawn_monster("skeleton", 5, true, 0.0)
	b.set_skeleton_lord(lord)
	_ok("B 君主生存緊要攞得返", b.skeleton_lord() == lord)
	b._remove(lord)
	b.set_skeleton_lord(lord)
	var m2 = b._spawn_monster("skeleton", 1, false, 0.0)
	_ok("B 君主節點俾回收之後,skeleton_lord() 要返 null", b.skeleton_lord() == null)
	_ok("B(前提)嗰個節點真係俾回收咗", m2 == lord)
	await _drop(b)

## 兵營名冊。士兵一樣係池化嘅。
func _case_barracks_roster() -> void:
	var b = await _mk()
	var sd = b.spawn_soldier(100.0, 50.0, 5.0, 0.0, null)
	_ok("B 士兵要有 serial", int(sd.serial) != 0)
	var t = _tower(b, 13)         # 兵營
	_ok("B(前提)13 號要係兵營(而家 %s)" % t.mech, t.mech == "barracks")
	t.soldiers.append([sd, int(sd.serial)])
	_ok("B 名冊入面生存緊嘅要數得到", t.live_soldiers().size() == 1)
	# 殺咗佢,再由**另一個**來源攞返同一個節點(模擬第二座兵營 / 召喚魔法)。
	sd._die()
	var sd2 = b.spawn_soldier(100.0, 50.0, 5.0, 0.0, null)
	_ok("B(前提)士兵節點真係俾回收咗", sd2 == sd)
	_ok("B 死咗嘅名額要清走 —— 唔係嘅話呢座兵營永遠唔會補兵(而畫面上睇唔出)",
		t.live_soldiers().size() == 0)
	_ok("B 而且個節點仲係 valid + alive", is_instance_valid(sd) and sd.alive)
	await _drop(b)

# --- C. 靜態掃描 ------------------------------------------------------------
## 新 code 唔可以再引入一個「跨幀參照淨係問 is_instance_valid / alive」嘅檢查。
##
## 呢個 case 唔係要捉晒所有情況(做唔到),係要令**同一個錯法**唔可以無聲無息
## 咁再出現一次:全部已知嘅跨幀池化參照欄位,喺 code 入面出現嗰陣都一定要
## 喺同一行見到 `Pool.live(` 或者一個已批核嘅用法。
const GUARDED := {
	"scripts/battle/Tower.gd": ["_conductor", "last_target", "_streak_target"],
	"scripts/battle/Battle.gd": ["boss_ref", "skeleton_boss_alive"],
	"scripts/ui/BattleHUD.gd": ["boss_ref"],
}
## 呢啲行係「寫入 / 清除 / 宣告」,唔係「讀取再信佢」,所以唔使驗 serial。
## `set_boss_ref` / `set_skeleton_lord` 本身就係寫入口(而且個名入面**含住**
## 欄位名,所以唔列出嚟就會捉錯自己嘅 setter)。
const WRITE_OPS := ["= null", "= m", "= tgt", "= best", "= sd", "var ", "==", "!=",
	"_serial", "erase", "append", "duplicate", "Pool.live(",
	"set_boss_ref", "set_skeleton_lord"]

func _case_static_scan() -> void:
	for path in GUARDED:
		var txt := FileAccess.get_file_as_string("res://" + path)
		if txt.is_empty():
			_ok("C 讀得到 %s" % path, false)
			continue
		var n := 0
		for raw in txt.split("\n"):
			n += 1
			var line: String = raw.strip_edges()
			if line.begins_with("#"):
				continue
			for field in GUARDED[path]:
				if line.find(field) < 0:
					continue
				var ok := false
				for w in WRITE_OPS:
					if line.find(w) >= 0:
						ok = true
						break
				_ok("C %s:%d 讀一個跨幀池化參照但冇經 Pool.live() —— 「%s」"
					% [path, n, line], ok)

	# `boss_ref` / `skeleton_boss_alive` 嘅**寫入**一定要經 setter。
	#
	# 呢條規則唔係潔癖:分開兩句寫嘅話,漏咗 serial 嗰半**唔會報錯**,個參照
	# 淨係會由第一刻起就當自己死咗。`test/BossHealTest` 真係中過招,而症狀係
	# 「復活光環冇效」同「boss 血條冇綠色回復段」—— 兩件表面上完全無關嘅事。
	# 唯一容許直接寫嗰兩個欄位嘅地方,就係 setter 自己 —— 所以掃嘅時候要
	# 記住而家喺邊個 func 入面,唔可以靠行號(行號一改 code 就作廢)。
	const SETTERS := ["set_boss_ref", "set_skeleton_lord"]
	for path in ["scripts/battle/Battle.gd", "test/BossHealTest.gd",
			"test/BalanceSim.gd", "test/Autopilot.gd"]:
		var txt2 := FileAccess.get_file_as_string("res://" + path)
		var ln := 0
		var cur_func := ""
		for raw in txt2.split("\n"):
			ln += 1
			var line: String = raw.strip_edges()
			if line.begins_with("func "):
				cur_func = line.substr(5).split("(")[0]
			if line.begins_with("#") or line.begins_with("var "):
				continue
			if cur_func in SETTERS:
				continue
			for field in ["boss_ref", "skeleton_boss_alive"]:
				# 只捉「賦值」,唔捉比較(`== m`)。
				if line.find(field + " = ") < 0:
					continue
				_ok("C %s:%d 直接寫 %s,冇經 set_boss_ref() / set_skeleton_lord() —— 「%s」"
					% [path, ln, field, line], false)

	# 反面:上面成個白名單嘅價值全部押喺 `Pool.live(` 呢個字串上面。佢一旦
	# 改名或者搬走,靜態掃描會靜靜咁**全部通過**(因為 WRITE_OPS 撞唔到)。
	# 所以呢度用一個**行為**斷言釘住個名同埋佢係 static 可呼叫:
	# 「一個唔存在嘅節點一定要答 null」。
	_ok("C Pool.live() 要仲叫呢個名而且 static 呼叫得到", Pool.live(null, 0) == null)
