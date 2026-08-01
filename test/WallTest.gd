extends Node
## 難度牆嘅結構測試。
##
## 呢度唔量難唔難 —— 嗰個要跑模擬(BalanceSim --walls)。呢度量嘅係「牆擺得啱唔啱
## 位、成份有冇入到、冇牆嘅關有冇被污染」,即係一堆改完數值之後好易靜靜雞壞咗
## 而又冇人察覺嘅嘢。
##
##   W  週期 —— 7/13/18 之後每 20 關重複,中間嘅關唔可以係牆
##   C  成份 —— 每幅牆該加嘅家族真係入咗 cfg.families
##   N  非牆關 —— families / spawn_interval_min 同加牆之前一模一樣
##   H  提示 —— 每幅牆有 hint key,而且兩種語言都譯咗

var fails := 0

func _ready() -> void:
	_case_period()
	_case_content()
	_case_non_wall_untouched()
	_case_hints()
	print("WALL %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _case_period() -> void:
	for n in [7, 13, 18, 27, 33, 38, 47, 53, 58]:
		_ok("W 第 %d 關係牆" % n, GameData.is_wall(n), "is_wall(%d) = false" % n)
	# 呢啲關必須唔係牆。特別留意 17 / 23 / 28 —— 如果週期寫成 10 而唔係 20,
	# 佢哋就會變牆,而 17 同 18 連住兩幅牆會令「牆與牆之間可以一次過」直接失效
	for n in [1, 6, 8, 12, 14, 17, 19, 20, 23, 26, 28, 34, 39]:
		_ok("W 第 %d 關唔係牆" % n, not GameData.is_wall(n), "is_wall(%d) = true" % n)
	# 週期性:第 n 關同第 n+20 關要係同一幅牆
	for n in [7, 13, 18]:
		_ok("W 第 %d 關同第 %d 關同一幅" % [n, n + 20],
			GameData.wall_slot(n) == GameData.wall_slot(n + 20),
			"slot %d vs %d" % [GameData.wall_slot(n), GameData.wall_slot(n + 20)])
	# 20 關入面剛剛好三幅
	var count := 0
	for n in range(1, 21):
		if GameData.is_wall(n):
			count += 1
	_ok("W 頭 20 關有 3 幅牆", count == 3, "got %d" % count)

func _case_content() -> void:
	# 第 7 關:對空 + 治療
	var c7: Dictionary = GameData.level_config(7)
	_ok("C7 標記做牆", bool(c7.get("is_wall", false)), "is_wall missing/false")
	_ok("C7 有飛行族 (bat)", "bat" in c7.families, "families=%s" % str(c7.families))
	_ok("C7 有治療族 (cultist)", "cultist" in c7.families, "families=%s" % str(c7.families))
	_ok("C7 boss 仲係樹妖", String(c7.boss_family) == "treant",
		"boss=%s" % String(c7.boss_family))

	# 第 13 關:分裂 + 密度
	var c13: Dictionary = GameData.level_config(13)
	_ok("C13 標記做牆", bool(c13.get("is_wall", false)), "is_wall missing/false")
	_ok("C13 有分裂族 (slime)", "slime" in c13.families, "families=%s" % str(c13.families))
	_ok("C13 spawn 間隔收窄", float(c13.spawn_interval_min) < 0.45,
		"spawn_interval_min=%.3f" % float(c13.spawn_interval_min))
	_ok("C13 boss 仲係骷髏", String(c13.boss_family) == "skeleton",
		"boss=%s" % String(c13.boss_family))

	# 第 18 關:護甲同魔抗同場
	var c18: Dictionary = GameData.level_config(18)
	_ok("C18 標記做牆", bool(c18.get("is_wall", false)), "is_wall missing/false")
	_ok("C18 有魔抗族 (ghost)", "ghost" in c18.families, "families=%s" % str(c18.families))
	var has_armor := false
	for f in c18.families:
		if float(GameData.FAMILIES[f].armor) >= 6.0:
			has_armor = true
	_ok("C18 同場有高甲族", has_armor, "families=%s 冇一個 armor>=6" % str(c18.families))
	_ok("C18 boss 仲係甲蟲", String(c18.boss_family) == "beetle",
		"boss=%s" % String(c18.boss_family))

	# 家族唔可以重複 —— 重複會令 _spawn_wave_monster 嘅隨機權重歪咗
	for n in [7, 13, 18]:
		var f: Array = GameData.level_config(n).families
		var uniq: Dictionary = {}
		for x in f:
			uniq[x] = true
		_ok("C%d 家族冇重複" % n, uniq.size() == f.size(), "families=%s" % str(f))

func _case_non_wall_untouched() -> void:
	## 非牆關要同「冇加過牆」一模一樣。程序生成嘅規則喺 level_config 入面寫死,
	## 所以呢度直接重算一次同一條式做對照 —— 如果 merge 寫漏咗個 if,呢個 case
	## 就會捉到「所有關都加咗 bat」呢類最貴嘅 bug。
	for n in [1, 5, 8, 12, 14, 19, 20]:
		var cfg: Dictionary = GameData.level_config(n)
		var base_i: int = (n - 1) % 10
		var want: Array = [GameData.FAMILY_ORDER[base_i],
			GameData.FAMILY_ORDER[(base_i + 3) % 10]]
		if n % 2 == 0:
			want.append(GameData.FAMILY_ORDER[(base_i + 6) % 10])
		_ok("N 第 %d 關家族冇被污染" % n, Array(cfg.families) == want,
			"got %s want %s" % [str(cfg.families), str(want)])
		_ok("N 第 %d 關 spawn 間隔冇被污染" % n,
			is_equal_approx(float(cfg.spawn_interval_min), 0.45),
			"got %.3f" % float(cfg.spawn_interval_min))
		_ok("N 第 %d 關冇標記做牆" % n, not bool(cfg.get("is_wall", false)), "is_wall true")

func _case_hints() -> void:
	for n in [7, 13, 18]:
		var key: String = GameData.wall_hint_key(n)
		_ok("H 第 %d 關有 hint key" % n, key != "", "empty hint key")
		if key == "":
			continue
		for loc in ["zh_TW", "en"]:
			TranslationServer.set_locale(loc)
			var txt: String = tr(key)
			_ok("H %s / %s 譯咗" % [key, loc], txt != key and txt.strip_edges() != "",
				"tr(%s) returned the key itself" % key)
	TranslationServer.set_locale(Meta.current_locale())
	_ok("H 非牆關冇 hint", GameData.wall_hint_key(5) == "",
		"level 5 returned '%s'" % GameData.wall_hint_key(5))

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("WALL ok   %s" % label)
	else:
		fails += 1
		print("WALL FAIL %s — %s" % [label, detail])
