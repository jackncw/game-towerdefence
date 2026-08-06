extends Node
## G1「可建塔數」曲線嘅量度器(第十八輪)。
##
## 點解要一個獨立工具,唔用 GateSim --mode=econ:econ 量嘅係「一個 A1 玩家實際
## 收到幾多」—— 佢同**打得好唔好**耦合(打得差就早死、收入少),所以佢係一個
## 玩家指標,唔係一條設計曲線。G1 要釘嘅係關卡本身派幾多錢,一個同 build 無關
## 嘅數。
##
## 做法:開一場真 Battle,每一格 tick 將場上**所有雜兵即刻擊殺**(force die,
## 分裂照分、精英照計、掉金全部行真嘅 on_monster_killed 路徑),boss 就釘死喺
## 路程 0 唔准行(佢一行到底就輸咗,而輸咗就唔係一條曲線係一個 artifact)。
## 跑足 REF_SECONDS 秒 —— 60 秒雜兵期 + 30 秒 boss 期,同第十七輪嘅「90 秒
## 當量收入」同一把尺。
##
## 用法:
##   godot --headless --path . res://tools/goldcurve.tscn -- --seeds=5
##   godot --headless --path . res://tools/goldcurve.tscn -- --levels=1,10,20,50,100

const DT := 1.0 / 30.0
const REF_SECONDS := 90.0
## 參考塔價 —— G1 嘅分母。20 座塔基礎價嘅中位數(亦等於平均價 119 取整),
## 所以佢唔跟任何單一塔種嘅平衡改動走。定義寫死喺呢度,報告直接引。
const REF_TOWER_COST := 120.0

var seeds := 5
var levels: Array = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Flow.nav_enabled = false
	get_tree().paused = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--levels="):
			for s in a.substr(9).split(","):
				levels.append(int(s))
	if levels.is_empty():
		for n in range(1, 101):
			levels.append(n)
	await _run()
	get_tree().paused = false
	get_tree().quit(0)

func _run() -> void:
	print("GOLD MODE=curve ref_cost=%d ref_seconds=%.0f seeds=%d" % [int(REF_TOWER_COST), REF_SECONDS, seeds])
	print("GOLD HDR lv income start_gold kills towers_buildable towers_with_start")
	for n in levels:
		var inc := 0.0
		var kil := 0.0
		for s in seeds:
			seed(0x901D + n * 7919 + s * 104729)
			var r: Dictionary = await _one(int(n))
			inc += float(r.income)
			kil += float(r.kills)
		inc /= float(seeds)
		kil /= float(seeds)
		var sg: int = int(GameData.level_config(int(n)).start_gold)
		print("GOLD ROW %d %.0f %d %.0f %.2f %.2f" % [
			n, inc, sg, kil, inc / REF_TOWER_COST, (inc + float(sg)) / REF_TOWER_COST])

func _one(n: int) -> Dictionary:
	Flow.selected_level = n
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	var g0: int = b.gold
	var t := 0.0
	while t < REF_SECONDS and not b.ended:
		if b.contract_pending:
			# 合約關:揀低風險嗰張(同 GateSim 難度讀數嘅 safe 策略一致)。
			# **`choose_contract` 收嘅係合約 id,唔係第幾張** —— 傳 0 落去
			# 通常唔喺 offer 入面,個 call 就靜靜咁 return,而 `continue` 又
			# 唔加時間,即刻變死循環(第 28 關卡足半個鐘先發現)。
			if b.contract_offer.is_empty():
				break
			b.choose_contract(int(b.contract_offer[0]))
			continue
		b._process(DT)
		for c in b.monsters_root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(DT)
		_reap(b)
		t += DT
	var res := {"income": b.gold - g0, "kills": b.kills}
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true
	return res

## 雜兵即殺、boss 釘死。force=true 只係跳過復活(骷髏),分裂同掉金照行 ——
## 分裂體係史萊姆關收入嘅一大截,唔可以計漏。
func _reap(b) -> void:
	for m in b.monsters.duplicate():
		if not is_instance_valid(m) or not m.alive:
			continue
		if m.is_boss:
			m.dist = 0.0
			m.hp = m.max_hp
		else:
			m._die(true)
