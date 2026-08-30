extends Node
## BOSS 開場傷害上限(第 21 輪,Gate 5a 嘅真解)。
##   godot --headless --path . test/BossFloorTest.tscn
##
## 呢個 test 問三條問題,而三條都係「結構鎖有冇漏」而唔係「數字啱唔啱」:
##   A  一炮天文數字傷害殺唔死 boss,而且要打足 GameData.boss_min_fight_seconds()
##      先死得。**每一條扣血嘅路都要驗**(take_hit 三種 dtype、DoT、按生命
##      上限計嗰批魔法),因為漏一條就等於漏一個秒 boss 捷徑。
##   B  正常火力(on-curve = 16 秒打死)一滴傷害都唔會俾食走。呢條係「唔准
##      變成拖時間懲罰」嗰句嘅可驗證版本。
##   C  雜兵完全唔受影響 —— 個鎖淨係 boss。
##
## 做法同其他 harness 一樣:`get_tree().paused = true` + 手動餵 delta,
## 所以同幀率無關、可重複。

const DT := 1.0 / 60.0
## 唔可以用逢 7 嘅倍數關 —— 嗰啲係合約關,開場即刻凍住成個場等玩家揀卡,
## 而症狀係「所有同時間有關嘅斷言一齊靜靜咁失敗」。呢個坑已經咬過
## BossHealTest / BossSpawnTest / SoakTest 三次。
const LEVEL := 12

var fails: Array[String] = []
var checked := 0

func _ok(what: String, cond: bool) -> void:
	checked += 1
	if not cond:
		fails.append(what)

func _ready() -> void:
	get_tree().create_timer(120.0, true, false, true).timeout.connect(
		func(): print("BOSSFLOOR TIMEOUT"); get_tree().quit(1))
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)

	await _case_one_shot_immune()
	await _case_min_fight_seconds()
	await _case_bank_cannot_stockpile()
	await _case_on_curve_untouched()
	await _case_mobs_unaffected()
	_case_constants()
	_case_no_other_hp_path()
	await _case_final_wave_exempt()
	await _report_walk()

	if fails.is_empty():
		print("BOSSFLOOR PASS fails=0 (%d 項)" % checked)
		get_tree().quit(0)
		return
	for f in fails:
		print("  FAIL " + f)
	print("BOSSFLOOR FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

# ---------------------------------------------------------------------------
func _mk() -> Node:
	Flow.selected_level = LEVEL
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	get_tree().paused = true
	b.gold = 99999999
	b.base_shield = 99999999
	b.boss_time = 1.0e9
	b.spawn_timer = 1.0e9
	b.cfg.spawn_interval_start = 1.0e9
	b.cfg.spawn_interval_min = 1.0e9
	return b

## 用哥布林王,唔用岩石巨像。巨像個 boss 機制係 stoneskin —— 每 6 秒無敵
## 1.5 秒,而 `take_hit` 對 invuln 係直接 return,唔經個漏桶。咁樣量到嘅
## 「最短 boss 戰」會混咗無敵秒數落去,而個測試會靜靜咁量緊另一件事。
## 甲蟲(hardshell / reflect)同樣唔用:佢哋喺漏桶之前已經改咗傷害。
## 哥布林王係 summon(淨係加雜兵),對自己嘅受傷零影響。
func _boss(b) -> Object:
	return b._spawn_monster("goblin", 5, true, b.route.total * 0.15)

func _kill(b) -> void:
	get_tree().paused = false
	b.queue_free()
	await get_tree().process_frame

## 每一條扣血嘅路,一炮 1e9 都唔可以殺死 boss。
func _case_one_shot_immune() -> void:
	var paths: Array = [
		["phys", func(m): m.take_hit(1.0e9, "phys")],
		["magic", func(m): m.take_hit(1.0e9, "magic")],
		["true", func(m): m.take_true(1.0e9)],
		["DoT(灼燒/劇毒/戰吼濺射)", func(m): m._deal_dot(1.0e9, Color.WHITE)],
		["按生命上限(天雷誅殺 bosspct)", func(m): m.take_true(m.max_hp * 5.0)],
		["按生命上限(龍捲風 GALE_TRUE_FRAC)",
			func(m): m.take_true(m.max_hp * GameData.GALE_TRUE_FRAC * 20.0)],
	]
	for row in paths:
		var b = await _mk()
		var m = _boss(b)
		var hp0: float = m.hp
		(row[1] as Callable).call(m)
		_ok("一炮 %s 唔可以秒死 boss(而家 hp=%.0f / %.0f)" % [row[0], m.hp, hp0],
			m.alive and m.hp > 0.0)
		# 滿桶 = BOSS_OPEN_BANK_SECONDS 秒額度,所以第一炮應該食到而且**只**食到
		# 嗰個額度 —— 少過就係鎖得太緊,多過就係漏。
		var want: float = GameData.BOSS_OPEN_BANK_SECONDS \
			* GameData.boss_open_dmg_cap_per_sec(m.max_hp)
		_ok("一炮 %s 應該打甩 %.0f(= 滿桶),實際 %.0f" % [row[0], want, hp0 - m.hp],
			absf((hp0 - m.hp) - want) <= maxf(1.0, want * 0.02))
		await _kill(b)

## 由滿桶開始,持續無限傷害 —— boss 死嗰一刻應該就係 boss_min_fight_seconds()。
func _case_min_fight_seconds() -> void:
	var b = await _mk()
	var m = _boss(b)
	var t: float = 0.0
	var want: float = GameData.boss_min_fight_seconds()
	while m.alive and t < want * 3.0 + 1.0:
		m._process(DT)
		if not m.alive:
			break
		m.take_hit(1.0e9, "true")
		t += DT
	_ok("無限傷害之下 boss 要行足 %.2f 秒先死,實際 %.2f 秒" % [want, t],
		absf(t - want) <= 4.0 * DT)
	await _kill(b)

## 「唔開火儲一大舊再一次過爆」呢條路要封死 —— 個桶封頂喺
## BOSS_OPEN_BANK_SECONDS,擺喺度唔打十秒都唔會儲多過嗰個數。
func _case_bank_cannot_stockpile() -> void:
	var b = await _mk()
	var m = _boss(b)
	for i in int(10.0 / DT):
		m._process(DT)
	var hp0: float = m.hp
	m.take_true(1.0e9)
	var want: float = GameData.BOSS_OPEN_BANK_SECONDS \
		* GameData.boss_open_dmg_cap_per_sec(m.max_hp)
	_ok("擺 10 秒唔打,桶都唔可以儲多過 %.0f;實際一炮打甩 %.0f" % [want, hp0 - m.hp],
		(hp0 - m.hp) <= want * 1.02)
	_ok("擺 10 秒唔打之後 boss 仲要生存", m.alive)
	await _kill(b)

## on-curve 玩家 = BOSS_FIGHT_REF_SECONDS 秒打死,即係逐幀 max_hp/16*dt。
## 呢種火力一滴都唔可以俾食走 —— 唔係嘅話個鎖就變咗拖時間懲罰。
func _case_on_curve_untouched() -> void:
	for mult in [1.0, 2.0]:
		var b = await _mk()
		var m = _boss(b)
		var per_frame: float = m.max_hp / GameData.BOSS_FIGHT_REF_SECONDS * DT * mult
		var dealt: float = 0.0
		var hp0: float = m.hp
		var steps := 0
		while m.alive and steps < int(GameData.BOSS_FIGHT_REF_SECONDS / DT) + 60:
			m._process(DT)
			if not m.alive:
				break
			m.take_hit(per_frame, "true")
			dealt += per_frame
			steps += 1
		var landed: float = hp0 - maxf(0.0, m.hp)
		# 「送出去嘅」入面有一份係**溢殺** —— 最後嗰下打死佢嗰陣,超出剩餘血
		# 嘅部分冇地方落。所以要比嘅係 min(送出, 佢有幾多血),唔係送出總數;
		# 第一版就係漏咗呢一句,報咗兩個 0.1% 嘅假失敗。
		var expect: float = minf(dealt, hp0)
		_ok("%.0fx on-curve 火力唔可以俾食走(送 %.0f,血 %.0f,落地 %.0f)"
			% [mult, dealt, hp0, landed], landed >= expect * 0.999)
		await _kill(b)

func _case_mobs_unaffected() -> void:
	var b = await _mk()
	var m = b._spawn_monster("goblin", 5, false, b.route.total * 0.15)
	m.take_true(1.0e9)
	_ok("個鎖淨係 boss —— 雜兵照樣一炮死", not m.alive)
	await _kill(b)

func _case_constants() -> void:
	_ok("開場上限速率要高過期望 DPS(唔係就係拖時間懲罰)",
		GameData.BOSS_OPEN_DPS_SHARE > 1.0)
	_ok("最短 boss 戰要短過中位數 boss 戰(%.1f < %.1f)"
		% [GameData.boss_min_fight_seconds(), GameData.BOSS_FIGHT_REF_SECONDS],
		GameData.boss_min_fight_seconds() < GameData.BOSS_FIGHT_REF_SECONDS)
	_ok("最短 boss 戰要係一場仗唔係一個時間點(>= 4 秒)",
		GameData.boss_min_fight_seconds() >= 4.0)

## 唔係斷言,係報數:6 秒嘅保證窗口入面,boss 行咗成條路嘅幾多 %。
## 「唔准喺 boss 未行出開場區之前秒佢」呢句嘢要有一個數先至講得出係咪做到。
func _report_walk() -> void:
	var want: float = GameData.boss_min_fight_seconds()
	var line: Array = []
	for lv in [12, 40, 71, 84, 99]:
		Flow.selected_level = lv
		var b = load("res://scenes/Battle.tscn").instantiate()
		add_child(b)
		await get_tree().process_frame
		get_tree().paused = true
		b.boss_time = 1.0e9
		b.spawn_timer = 1.0e9
		b.cfg.spawn_interval_start = 1.0e9
		b.cfg.spawn_interval_min = 1.0e9
		var m = b._spawn_monster("goblin", 5, true, 0.0)
		var d0: float = m.dist
		for i in int(want / DT):
			m._process(DT)
		var frac: float = (m.dist - d0) / maxf(1.0, b.route.total)
		line.append("lv%d %.1f%%" % [lv, frac * 100.0])
		get_tree().paused = false
		b.queue_free()
		await get_tree().process_frame
	print("BOSSFLOOR INFO 保證窗口 %.1f 秒,boss 喺窗口入面行咗:%s"
		% [want, " / ".join(line)])

## Part D.2 嘅結構證據:除咗 Monster.gd 自己,全 project 冇第二度直接扣怪血。
##
## 上面嗰啲 case 逐條驗過已知嘅扣血路,但「已知」呢兩個字先係風險所在 ——
## 20 座塔 × 3 階 × 15 個魔法 × 3 階夾埋幾百個組合,逐個試唔現實,而且下一輪
## 加嘅嘢一樣試唔到。所以呢度改為驗一條**不變式**:所有傷害都一定要經
## `take_hit` / `take_true` / `_deal_dot`,即係一定會經 `_boss_absorb`。
## 邊個檔案直接寫 `m.hp -= x` 就係一條繞過咗個鎖嘅新路,而佢唔會報錯。
func _case_no_other_hp_path() -> void:
	# 白名單:第 100 關十隻 boss 減血之後要補滿(Battle._spawn_final_wave),
	# 嗰個係設定血量唔係扣血。
	var allow: Array = ["m.hp = m.max_hp"]
	var files: Array = ["Battle", "Tower", "Projectile", "Boomerang", "Spells",
		"Hazard", "Soldier", "Fx", "DamageField"]
	for fname in files:
		var path := "res://scripts/battle/%s.gd" % fname
		if not FileAccess.file_exists(path):
			continue
		var txt := FileAccess.get_file_as_string(path)
		var n := 0
		for raw in txt.split("\n"):
			n += 1
			var line: String = raw.strip_edges()
			if line.begins_with("#"):
				continue
			var hit: bool = line.find(".hp -=") >= 0 or line.find(".hp =") >= 0
			if not hit:
				continue
			var ok := false
			for a in allow:
				if line.find(a) >= 0:
					ok = true
			_ok("%s.gd:%d 直接寫怪物 hp,繞過咗 _boss_absorb —— 「%s」"
				% [fname, n, line], ok)

## 第 100 關嗰十隻 boss 豁免,而**只有**佢哋豁免。
##
## 呢個 case 兩邊都要驗:豁免真係生效(唔係嘅話 Gate 6b 會由 16.7% 跌到 6.2%),
## 同埋豁免冇漏去第 71-99 關(漏咗嘅話成個鎖等於冇裝,而 5a 唔會有任何變化 ——
## 一個「乜都冇發生」嘅結果同一個「機制冇效」嘅結果喺讀數上面一模一樣)。
func _case_final_wave_exempt() -> void:
	# (a) 第 100 關:最終波嗰十隻要秒得死
	Flow.selected_level = 100
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	get_tree().paused = true
	b.base_shield = 99999999
	# 直接推到最終波出場(_final_wave_logic 靠 elapsed 同 _final_wave_i)
	var guard := 0
	while b.final_bosses.is_empty() and guard < 20000:
		b._process(DT)
		guard += 1
	_ok("第 100 關要放到最終波出嚟(而家 %d 隻)" % b.final_bosses.size(),
		not b.final_bosses.is_empty())
	if not b.final_bosses.is_empty():
		var fm = b.final_bosses[0]
		_ok("最終波嗰隻要標咗豁免", bool(fm.floor_exempt))
		## **傷害要按佢自己嘅血量計,唔可以寫死一個絕對數。**
		## 呢一句本來寫住 `take_true(1.0e9)`,而第 24 輪 `FINAL_SCALE` 由 0.052
		## 校準到 0.55(×10.6)之後,第 100 關嘅 boss 血量升穿咗 1e9 —— 於是
		## 一個**平衡常數**令一條**機制斷言**跪低。呢個測試問嘅係「呢隻有冇
		## 被漏桶擋住」,唔係「1e9 夠唔夠殺」,所以個數要跟住佢自己嘅血量行。
		fm.take_true(fm.max_hp * 10.0)
		_ok("最終波嗰隻要秒得死(唔係嘅話 Gate 6b 會跌穿)—— 血量 %.0f" % fm.max_hp,
			not fm.alive)
	get_tree().paused = false
	b.queue_free()
	await get_tree().process_frame

	# (b) 普通關嘅 boss 唔可以標到豁免
	var b2 = await _mk()
	var m2 = _boss(b2)
	_ok("普通關嘅 boss 唔可以有豁免", not bool(m2.floor_exempt))
	m2.take_true(1.0e9)
	_ok("普通關嘅 boss 照樣秒唔死", m2.alive)
	await _kill(b2)
