extends Node
## 第 100 關嘅**完成鏈**:十隻 boss 全滅 → 停 spawner → 清場 → 結算勝利。
##   godot --headless --path . res://test/Level100CompletionTest.tscn
##
## 呢個 test 存在嘅原因係一單真機 bug:打死頭幾隻 boss 之後小怪無限生成,關卡
## 永遠完成唔到。當時 Gate 6a/6b 兩條都 PASS,因為 harness 嗰邊「掛死」同
## 「打輸」喺讀數上面一模一樣(`_play` 撞到 ATTEMPT_TIMEOUT 就 `win=false`)。
## 所以呢度斷言嘅唔係勝率,係**結算一定會發生**:
##
##   A  順序殺(一潮一潮,每隻隔幾秒)
##   B  亂序殺(潮與潮之間交叉,最後死嗰隻係第一潮嘅)
##   C  極速殺(十隻同一幀死)
##   D  拖長殺(每隻之間隔 20 秒,期間雜兵狂出)
##   E  逐潮清乾淨(打死頭三隻 → 等下一潮 → 再清,即係真機報告嗰個玩法)
##
## 每個 case 都要:boss 全滅之後 WIN_GRACE 秒內 `ended` 同 `Flow.last_result.win`,
## 而且結算之後 spawner 唔可以再吐怪。
##
## 關鍵嘅陷阱(亦即係原本個 bug):`Battle.final_bosses` 入面裝住嘅係**池化**
## 節點。一隻 boss 死咗 → `_remove()` → `Pool.release()` → 落返 free stack 頂;
## 下一次雜兵 spawn 就 `pop_back()` 攞返同一個節點出嚟,`setup()` 再 `alive = true`。
## 於是「boss 死晒未?」呢條問題會由一隻**雜兵**答 —— 而佢係生存嘅。

const DT := 1.0 / 30.0
const LEVEL := 100
## boss 全滅之後容許幾多秒先結算。真答案係「同一幀」,但留一點餘裕俾將來
## 加死亡動畫之類嘅嘢。
const WIN_GRACE := 1.0
## 一個 case 最多行幾多模擬秒 —— 撞到就係掛死,唔係「打輸」。
const CASE_LIMIT := 900.0

var fails: Array[String] = []
var checked := 0

func _ok(what: String, cond: bool) -> void:
	checked += 1
	if not cond:
		fails.append(what)

func _ready() -> void:
	get_tree().create_timer(600.0, true, false, true).timeout.connect(
		func(): print("L100 TIMEOUT"); get_tree().quit(1))
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)

	await _case_order("A 順序殺", "seq", 3.0)
	await _case_order("B 亂序殺", "shuffle", 3.0)
	await _case_order("C 極速殺(同一幀)", "seq", 0.0)
	await _case_order("D 拖長殺(每隻隔 20 秒)", "seq", 20.0)
	await _case_wave_by_wave()
	await _case_no_early_win()
	await _case_no_stale_pool_alias()

	if fails.is_empty():
		print("L100 PASS fails=0 (%d 項)" % checked)
		get_tree().quit(0)
		return
	for f in fails:
		print("  FAIL " + f)
	print("L100 FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

# ---------------------------------------------------------------------------
func _mk():
	Flow.selected_level = LEVEL
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	get_tree().paused = true
	# 唔可以輸 —— 呢個 test 量嘅係「贏得成」,唔係「守得住」。
	b.base_shield = 99999999
	b.gold = 99999999
	return b

func _drop(b) -> void:
	get_tree().paused = false
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

## 行一幀:Battle + 所有活住嘅子節點,同 GateSim._step 一樣。
func _step(b) -> void:
	b._process(DT)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(DT)

## 保證殺死一隻 boss。
##
## 唔可以淨係叫一次 `take_true` —— 岩石巨像個 boss 機制係石化(`invuln_time`),
## 而 `take_hit` 撞到無敵係直接 return。原本淨係打一下嘅版本喺石化窗口入面
## 等於冇打過,而個 test 就會報一個**假**嘅失敗(睇落同真 bug 一模一樣)。
func _kill_boss(b, m) -> bool:
	var guard := 0
	while is_instance_valid(m) and m.alive and guard < 200:
		m.invuln_time = 0.0
		m.take_true(1.0e9)
		guard += 1
		if is_instance_valid(m) and m.alive:
			_step(b)
	return not (is_instance_valid(m) and m.alive)

## 行到十隻 boss 全部出齊(三潮都放咗)。
func _advance_to_all_spawned(b) -> float:
	var t := 0.0
	while b.final_bosses.size() < 10 and t < CASE_LIMIT and not b.ended:
		_step(b)
		t += DT
	return t

## 行 `secs` 秒,或者行到結算為止。
func _run(b, secs: float) -> void:
	var t := 0.0
	while t < secs and not b.ended:
		_step(b)
		t += DT

## boss 全滅之後,喺 WIN_GRACE 秒之內一定要結算。
func _expect_win(b, tag: String) -> void:
	var t := 0.0
	while not b.ended and t < WIN_GRACE:
		_step(b)
		t += DT
	_ok("%s:boss 全滅之後 %.1f 秒內要結算(而家 ended=%s)" % [tag, WIN_GRACE, str(b.ended)],
		b.ended)
	if not b.ended:
		return
	_ok("%s:結算要係勝利" % tag, bool(Flow.last_result.get("win", false)))
	# 個不變式本身,唔係佢嘅後果:死咗嘅要剔清,死亡計數要啱。
	_ok("%s:十隻都要記低死咗(而家 %d)" % [tag, b.final_boss_dead], b.final_boss_dead == 10)
	_ok("%s:final_bosses 要清空(而家 %d)" % [tag, b.final_bosses.size()],
		b.final_bosses.is_empty())
	# 結算之後個場要乾淨,而且 spawner 唔可以再吐怪。
	_ok("%s:結算之後場上唔可以仲有怪(而家 %d)" % [tag, b.monsters.size()],
		b.monsters.is_empty())
	var before: int = b.spawned_count
	_run(b, 5.0)
	_ok("%s:結算之後 spawner 要停(5 秒又出咗 %d 隻)"
		% [tag, b.spawned_count - before], b.spawned_count == before)

## 十隻 boss 出齊之後,用 `order` 嘅次序、每隻之間隔 `gap` 秒殺。
func _case_order(tag: String, order: String, gap: float) -> void:
	var b = await _mk()
	var t: float = await _advance_to_all_spawned(b)
	_ok("%s:三潮十隻要出得齊(而家 %d 隻,%.0f 秒)" % [tag, b.final_bosses.size(), t],
		b.final_bosses.size() == 10)
	if b.final_bosses.size() != 10:
		await _drop(b)
		return
	var idx: Array = []
	for i in b.final_bosses.size():
		idx.append(i)
	if order == "shuffle":
		# 一個固定嘅「亂」序 —— 可重複,而且最後死嗰隻係第一潮嘅第一隻。
		idx = [4, 9, 2, 7, 1, 5, 8, 3, 6, 0]
	# 快照:殺嘅過程入面 final_bosses 唔會變,但節點會俾池回收,所以要記住
	# 對象本身。
	var bosses: Array = b.final_bosses.duplicate()
	var dead := 0
	for k in idx.size():
		if _kill_boss(b, bosses[idx[k]]):
			dead += 1
		if gap > 0.0 and k < idx.size() - 1:
			_run(b, gap)
			if b.ended:
				break
	_ok("%s:十隻要真係死得晒(而家 %d)" % [tag, dead], dead == 10)
	_expect_win(b, tag)
	await _drop(b)

## 真機報告嗰個玩法:一潮出、即刻清乾淨、等下一潮。
func _case_wave_by_wave() -> void:
	var tag := "E 逐潮清乾淨"
	var b = await _mk()
	var t := 0.0
	var killed := 0
	while killed < 10 and t < CASE_LIMIT and not b.ended:
		_step(b)
		t += DT
		for m in b.final_bosses.duplicate():
			if is_instance_valid(m) and m.alive and m.is_boss:
				if _kill_boss(b, m):
					killed += 1
	_ok("%s:十隻都要死得晒(而家 %d,%.0f 秒)" % [tag, killed, t], killed == 10)
	_expect_win(b, tag)
	await _drop(b)

## 反面:潮與潮之間嘅空窗**唔可以**當贏。
##
## 修法入面有一個每幀跑嘅安全網(`_spawn_logic` 度嗰句 `if final_all_dead()`),
## 而佢最容易錯嘅方向就係呢個 —— 第一潮清乾淨嗰刻場上一隻 boss 都冇。
func _case_no_early_win() -> void:
	var tag := "G 潮之間唔可以提早結算"
	var b = await _mk()
	# 行到第一潮出場
	var t := 0.0
	while b.final_bosses.is_empty() and t < CASE_LIMIT and not b.ended:
		_step(b)
		t += DT
	var w1: Array = b.final_bosses.duplicate()
	_ok("%s:第一潮要有 3 隻(而家 %d)" % [tag, w1.size()], w1.size() == 3)
	for m in w1:
		_kill_boss(b, m)
	_ok("%s:第一潮清晒之後場上唔應該仲有 boss" % tag, b.final_bosses.is_empty())
	_ok("%s:但係唔可以結算(仲有兩潮未出)" % tag, not b.ended)
	# 行到第二潮出場為止,期間一路唔可以結算
	var t2 := 0.0
	while b.final_bosses.is_empty() and t2 < 120.0 and not b.ended:
		_step(b)
		t2 += DT
	_ok("%s:等到第二潮出場之前都唔可以結算(等咗 %.0f 秒)" % [tag, t2], not b.ended)
	_ok("%s:第二潮要出到嚟" % tag, not b.final_bosses.is_empty())
	await _drop(b)

## 個 bug 本身嘅結構證據:一隻死咗嘅 boss 俾池回收成雜兵之後,唔可以再算入
## 「boss 未死晒」。呢個 case 唔靠時序運氣 —— 佢直接砌返嗰個狀態。
func _case_no_stale_pool_alias() -> void:
	var tag := "F 池回收別名"
	var b = await _mk()
	var t: float = await _advance_to_all_spawned(b)
	if b.final_bosses.size() != 10:
		_ok("%s:三潮十隻要出得齊(而家 %d,%.0f 秒)" % [tag, b.final_bosses.size(), t], false)
		await _drop(b)
		return
	var bosses: Array = b.final_bosses.duplicate()
	for m in bosses:
		_kill_boss(b, m)
		# 逐隻死完即刻迫個池交返同一個節點出嚟做雜兵 —— free stack 係 LIFO,
		# 所以 pop_back() 攞到嘅就係啱啱死嗰隻。
		if not b.ended:
			b._spawn_monster("goblin", 5, false, 0.0)
	_ok("%s:十隻死晒之後,就算節點俾池回收咗做雜兵都要結算" % tag, b.ended)
	if b.ended:
		_ok("%s:結算要係勝利" % tag, bool(Flow.last_result.get("win", false)))
	await _drop(b)
