extends Node
## 第二十輪 —— 地震術減弱嘅驗收基準。
##
##   godot --headless --path . res://test/QuakeNerfTest.tscn
##
## 三條斷言,對應簡報三個要求:
##   1. 殺傷率  滿級 T3 喺 71–99 段**任何**一關,單次施放殺死當關標準小怪波
##              嘅比例 ≤ KILL_CAP。收緊咗:簡報畀 40%,呢度釘 0% —— 因為
##              QUAKE_MOB_FLOOR 令佢**結構性**唔可能殺死一隻非 boss,所以
##              呢條斷言唔係「而家啱啱好收貨」,係「以後都唔可能超標」。
##   2. 控場    RIFT_SLOW / RIFT_DUR / SHATTER_STUN / SHATTER_GROUND_DUR /
##              stunlen 曲線一個字都唔准變。nerf 傷害唔 nerf 控場。
##   3. 存在感  一炮仍然要打甩滿血小怪至少 PRESENCE_FLOOR 成血,而對 boss
##              嗰半邊完全冇郁(bosspct 曲線照舊)。
##
## 點解「一波怪」要模擬血量分佈,唔可以齊齊整整當佢哋滿血:
## 滿血之下舊值 0.85 一樣殺唔死人(0.85 < 1.0),量出嚟會係 0% —— 即係話一個
## 「全部滿血」嘅 bench 睇唔到 Jack 報嘅問題。真正出事嘅場面係**打緊嗰陣**:
## 四十座塔喺度磨,成波怪散落喺各種血量,而地震術一炮就將所有低過 pct 嗰啲
## 一次過收割。所以呢度掃一系列血量分佈(由「啱啱出閘」到「半死」),每個
## 分佈量一次,再報最差嗰個。

const KILL_CAP := 0.0            # 收緊自簡報嘅 0.40
const PRESENCE_FLOOR := 0.25     # 一炮至少要打甩滿血小怪兩成半血
const WAVE_N := 40               # 一波當四十隻

## 血量分佈:每個係「呢一波怪嘅血量喺 [lo, 1.0] 之間均勻分佈」。
## lo = 1.0 就係全部滿血(啱啱出閘),lo = 0.05 就係俾塔磨到快死。
const HP_SPREADS := [1.00, 0.70, 0.40, 0.20, 0.05]

var fails := 0
var lines: Array = []

func _ready() -> void:
	Crash.enabled = false
	_case_kill_rate()
	_case_before_after()
	_case_control_untouched()
	_case_presence()
	for l in lines:
		print(l)
	print("QUAKENERF %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + what)

func _maxed(def: Dictionary) -> Array:
	var a: Array = []
	for i in (def.ups as Array).size():
		a.append(GameData.MAX_UP_LV)
	return a

## 一波 WAVE_N 隻怪,血量喺 [lo, 1.0] 均勻分佈,食一炮之後死幾多隻。
func _kills(max_hp: float, pct: float, lo: float) -> int:
	var dead := 0
	for i in WAVE_N:
		var frac: float = lo if WAVE_N <= 1 else lo + (1.0 - lo) * float(i) / float(WAVE_N - 1)
		var hp: float = max_hp * frac
		if hp - GameData.quake_mob_damage(hp, max_hp, pct) <= 0.0:
			dead += 1
	return dead

func _case_kill_rate() -> void:
	var def: Dictionary = GameData.spell_by_id(11)
	var s: Dictionary = GameData.effective_stats(def, _maxed(def), 3)
	var pct: float = float(s.pct)
	lines.append("殺傷率(滿級 T3,pct=%.2f,一波 %d 隻)" % [pct, WAVE_N])
	lines.append("%-6s %-12s %10s %10s %s" % ["關", "標準小怪HP", "血量分佈", "殺死", "判定"])
	var worst := 0.0
	var worst_at := ""
	for lvl in range(71, 100):
		var cfg: Dictionary = GameData.level_config(lvl)
		var ws: float = GameData.wave_scale(lvl)
		var mob: Dictionary = GameData.creature_stats(
			String(cfg.families[0]), int(cfg.lvl_max), ws)
		var mhp: float = float(mob.hp)
		for lo in HP_SPREADS:
			var frac: float = float(_kills(mhp, pct, lo)) / float(WAVE_N)
			if frac > worst:
				worst = frac
				worst_at = "第%d關 / 分佈 %.2f" % [lvl, lo]
			# 只印每十關一行,唔係印 145 行
			if lvl % 10 == 1 and is_equal_approx(lo, 0.40):
				lines.append("%-6d %-12.0f %10.2f %9.0f%% %s"
					% [lvl, mhp, lo, frac * 100, "OK" if frac <= KILL_CAP else "超標"])
	ok(worst <= KILL_CAP, "殺傷率上限:71–99 段最差嗰個係 %.1f%%(%s),門檻 %.0f%%"
		% [worst * 100, worst_at, KILL_CAP * 100])
	lines.append("71–99 段 × %d 個血量分佈 最差殺傷率:%.1f%%(門檻 %.0f%%)"
		% [HP_SPREADS.size(), worst * 100, KILL_CAP * 100])

## 減弱前後對照。舊值寫死喺度(pct 0.42/0.62/0.85、冇下限),所以份報告
## 引嘅數字係跑得返嘅,唔係人手抄一次。
const OLD_PCT := [0.42, 0.62, 0.85]

func _case_before_after() -> void:
	var def: Dictionary = GameData.spell_by_id(11)
	lines.append("")
	lines.append("減弱前 / 後對照(一波 %d 隻,血量喺 [分佈, 1.0] 均勻)" % WAVE_N)
	lines.append("%-6s %-8s %14s %14s" % ["階", "血量分佈", "舊:殺死", "新:殺死"])
	for t in range(1, GameData.MAX_TIER + 1):
		var new_pct: float = float(GameData.effective_stats(def, _maxed(def), t).pct)
		var old_pct: float = float(OLD_PCT[t - 1])
		for lo in HP_SPREADS:
			var old_dead := 0
			for i in WAVE_N:
				var frac: float = lo + (1.0 - lo) * float(i) / float(WAVE_N - 1)
				if frac <= old_pct:            # 舊式:冇下限,打得穿就死
					old_dead += 1
			lines.append("%-6s %-8.2f %13.0f%% %13.0f%%"
				% ["t%d" % t, lo, 100.0 * old_dead / WAVE_N,
				   100.0 * _kills(1.0, new_pct, lo) / WAVE_N])
	lines.append("單次施放對滿血小怪嘅傷害:t1 %.0f%%->%.0f%%  t2 %.0f%%->%.0f%%  t3 %.0f%%->%.0f%%"
		% [OLD_PCT[0] * 100, float(GameData.effective_stats(def, _maxed(def), 1).pct) * 100,
		   OLD_PCT[1] * 100, float(GameData.effective_stats(def, _maxed(def), 2).pct) * 100,
		   OLD_PCT[2] * 100, float(GameData.effective_stats(def, _maxed(def), 3).pct) * 100])

## 控場不變式 —— 呢一輪唔准郁到嘅嘢,逐個釘死。
func _case_control_untouched() -> void:
	ok(is_equal_approx(GameData.RIFT_SLOW, 0.40), "RIFT_SLOW 要 0.40")
	ok(is_equal_approx(GameData.RIFT_DUR, 3.0), "RIFT_DUR 要 3.0")
	ok(is_equal_approx(GameData.SHATTER_STUN, 1.2), "SHATTER_STUN 要 1.2")
	ok(is_equal_approx(GameData.SHATTER_GROUND_DUR, 4.0), "SHATTER_GROUND_DUR 要 4.0")
	var def: Dictionary = GameData.spell_by_id(11)
	var stun: Array = []
	var cds: Array = []
	var bosspct: Array = []
	for t in range(1, GameData.MAX_TIER + 1):
		var s: Dictionary = GameData.effective_stats(def, _maxed(def), t)
		stun.append(float(s.get("stunlen", 0.0)))
		cds.append(float(s.cd))
		bosspct.append(float(s.get("bosspct", 0.0)))
	ok(is_equal_approx(stun[2], 1.2), "T3 震暈秒數要維持 1.2,而家 %.2f" % stun[2])
	ok(is_equal_approx(cds[0], 8.0) and is_equal_approx(cds[1], 7.0)
		and is_equal_approx(cds[2], 6.5), "冷卻曲線要維持 8/7/6.5")
	ok(is_equal_approx(bosspct[2], 0.09), "對 boss 嘅生命上限比例要維持 9%%")
	lines.append("控場不變式:震暈 %.2f 秒、拖慢 %.0f%%/%.0f 秒、震落地面 %.0f 秒、"
		% [stun[2], GameData.RIFT_SLOW * 100, GameData.RIFT_DUR,
		   GameData.SHATTER_GROUND_DUR]
		+ "冷卻 %.1f/%.1f/%.1f —— 全部同減弱前一致" % [cds[0], cds[1], cds[2]])

func _case_presence() -> void:
	var def: Dictionary = GameData.spell_by_id(11)
	lines.append("")
	lines.append("存在感(對一隻滿血小怪一炮打甩幾多成)")
	for t in range(1, GameData.MAX_TIER + 1):
		var s: Dictionary = GameData.effective_stats(def, _maxed(def), t)
		# 滿血目標:hp = max_hp = 1.0
		var frac: float = GameData.quake_mob_damage(1.0, 1.0, float(s.pct))
		ok(frac >= PRESENCE_FLOOR, "存在感:t%d 只打甩 %.0f%%,低過 %.0f%% 下限"
			% [t, frac * 100, PRESENCE_FLOOR * 100])
		lines.append("  t%d  對滿血小怪 %.0f%%   對 boss %.0f%% + %.0f 固定"
			% [t, frac * 100, float(s.get("bosspct", 0.0)) * 100,
			   float(s.get("bossdmg", 0.0))])
