extends Node
## 難度牆嘅**機制**測試。
##
## 第九輪之後 `GameData.WALLS` 係空嘅 —— 三幅牆起咗、量咗、冇出街(原因見
## GameData.gd `WALLS` 上面嗰段同 BALANCE_CHANGELOG「第九輪」)。所以呢度唔再測
## 內容(冇內容可測),改為測**機制**:合併嗰條路仍然係 level_config() 嘅一部分,
## 每一關都行過佢,所以佢壞咗係一個會影響全部二十關嘅 bug。
##
## 做法係喺測試入面**臨時塞一個假牆**入 WALLS,驗合併行為,然後還原。
##
##   E  空表 —— WALLS 係空嘅(有人加返內容嘅時候會叫佢返去讀個發現)
##   W  週期 —— 7/13/18 之後每 20 關重複,中間嘅關唔可以喺時間表上面
##   M  機制 —— 塞個假牆入去:pool 要完全取代、spawn_min 要覆蓋、is_wall 要翻轉
##   B  基準 —— WALLS 空嘅時候,**全部二十關**都同冇牆嘅程序生成一模一樣
##   N  非牆關 —— 原本就有嘅嗰個 case,一個字冇改
##   H  提示 —— 保留低嘅四條 i18n key 兩種語言都仲譯到

var fails := 0

func _ready() -> void:
	_case_empty()
	_case_period()
	_case_mechanism()
	_case_all_levels_baseline()
	_case_hints()
	print("WALL %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _case_empty() -> void:
	## 呢條唔係「仲未填」嘅提醒,係一個量度結論嘅守衛。有人想加返內容嘅話,先去
	## 讀 GameData.gd `WALLS` 上面嗰四點 —— 尤其係「組成差距由頭到尾冇正過」同
	## 「密度係唯一嘅難度掣,而佢會蓋過幅牆想教嘅嘢」。
	_ok("E WALLS 係空嘅", GameData.WALLS.is_empty(),
		("WALLS 有 %d 個 entry —— 加返內容之前請讀 GameData.gd WALLS 上面嗰段同 "
		% GameData.WALLS.size()) + "BALANCE_CHANGELOG 第九輪,唔好由零再試一次")

func _case_period() -> void:
	## 呢個 case 問嘅係**時間表**,所以直接叫 wall_slot() —— 佢係嗰條純算術,同 WALLS
	## 有冇內容無關。唔用 is_wall():嗰個(而家)答嘅係「有冇內容」,WALLS 空之下
	## 對每一關都會返 false,呢度就乜都測唔到。
	for n in [7, 13, 18, 27, 33, 38, 47, 53, 58]:
		_ok("W 第 %d 關係牆位" % n, GameData.wall_slot(n) > 0, "wall_slot(%d) = 0" % n)
	# 呢啲關必須唔係牆位。特別留意 17 / 23 / 28 —— 如果週期寫成 10 而唔係 20,
	# 佢哋就會變牆,而 17 同 18 連住兩幅牆會令「牆與牆之間可以一次過」直接失效
	for n in [1, 6, 8, 12, 14, 17, 19, 20, 23, 26, 28, 34, 39]:
		_ok("W 第 %d 關唔係牆位" % n, GameData.wall_slot(n) == 0,
			"wall_slot(%d) = %d" % [n, GameData.wall_slot(n)])
	# 週期性:第 n 關同第 n+20 關要係同一個牆位
	for n in [7, 13, 18]:
		_ok("W 第 %d 關同第 %d 關同一個位" % [n, n + 20],
			GameData.wall_slot(n) == GameData.wall_slot(n + 20),
			"slot %d vs %d" % [GameData.wall_slot(n), GameData.wall_slot(n + 20)])
	# 20 關入面剛剛好三個牆位
	var count := 0
	for n in range(1, 21):
		if GameData.wall_slot(n) > 0:
			count += 1
	_ok("W 頭 20 關有 3 個牆位", count == 3, "got %d" % count)
	# is_wall() 問嘅係內容,唔係時間表 —— WALLS 空之下佢對牆位都要返 false。
	# 呢條就係守住嗰個陷阱:曾經 is_wall() = wall_slot() > 0,所以清空 WALLS 之後
	# 任何「係牆就畫危險標記」嘅 UI 會喺三關普通關卡上面亂畫。
	for n in [7, 13, 18]:
		_ok("W 第 %d 關係牆位但 is_wall() 要睇內容" % n, not GameData.is_wall(n),
			"WALLS 空但 is_wall(%d) 返 true" % n)

## 塞一個假牆入 WALLS,驗 level_config() 嘅合併,然後還原。
##
## 個假定義刻意揀啲同程序生成**唔可能撞啱**嘅嘢:pool 用兩個唔會同時出現喺第 7 關
## 嘅家族,spawn_min 用一個唔等於預設 0.45 嘅值。咁樣「合併冇行到」同「合併行咗但
## 啱好一樣」先分得開。
const M_SLOT := 7

func _case_mechanism() -> void:
	var saved: Dictionary = GameData.WALLS.duplicate(true)
	# 合併之前嘅樣,用嚟做對照
	var before: Dictionary = GameData.level_config(M_SLOT)
	var proc_fams: Array = Array(before.families).duplicate()
	var proc_boss: String = String(before.boss_family)

	GameData.WALLS[M_SLOT] = {
		"pool": ["wolf", "beetle"],
		"spawn_min": 0.21,
		"hint": "WALL_HINT_7",
	}
	var cfg: Dictionary = GameData.level_config(M_SLOT)

	_ok("M pool 完全取代家族名單", Array(cfg.families) == ["wolf", "beetle"],
		"families=%s(期望 [wolf, beetle])" % str(cfg.families))
	_ok("M 程序生成嗰批真係被換走", Array(cfg.families) != proc_fams,
		"合併之後仲係 %s" % str(proc_fams))
	_ok("M spawn_min 覆蓋到", is_equal_approx(float(cfg.spawn_interval_min), 0.21),
		"spawn_interval_min=%.3f(期望 0.21)" % float(cfg.spawn_interval_min))
	_ok("M cfg.is_wall 翻轉", bool(cfg.get("is_wall", false)), "is_wall 仲係 false")
	_ok("M GameData.is_wall() 跟住內容翻轉", GameData.is_wall(M_SLOT),
		"塞咗內容入去但 is_wall(%d) 仲係 false" % M_SLOT)
	_ok("M hint key 攞得返", GameData.wall_hint_key(M_SLOT) == "WALL_HINT_7",
		"wall_hint_key=%s" % GameData.wall_hint_key(M_SLOT))
	_ok("M boss 唔會被 pool 改到", String(cfg.boss_family) == proc_boss,
		"boss %s -> %s" % [proc_boss, String(cfg.boss_family)])

	# pool 入面重複嘅家族要被濾走,否則均勻抽會變咗加權抽
	GameData.WALLS[M_SLOT] = {"pool": ["wolf", "wolf", "beetle"]}
	var dup: Dictionary = GameData.level_config(M_SLOT)
	_ok("M pool 內嘅重複會被濾走", Array(dup.families) == ["wolf", "beetle"],
		"families=%s" % str(dup.families))
	# 冇寫 spawn_min 嘅牆唔應該郁到出怪間隔
	_ok("M 冇寫 spawn_min 就唔郁", is_equal_approx(float(dup.spawn_interval_min), 0.45),
		"spawn_interval_min=%.3f(期望 0.45)" % float(dup.spawn_interval_min))

	GameData.WALLS = saved
	# 呢度本來仲有一句「還原之後 WALLS 仲係空」。刪咗:saved 就係 WALLS 開始
	# 嗰刻嘅副本,而嗰刻佢係空嘅,所以嗰句真正做緊嘅事係「攞 {} 出嚟問佢空唔空」
	# —— 點改 level_config 都紅唔到。下面兩句先係真證據:還原之後 is_wall() 同
	# level_config() 都要跟返個新內容行,即係個還原真係入到去。
	_ok("M 還原之後 is_wall() 返 false", not GameData.is_wall(M_SLOT), "is_wall 仲係 true")
	_ok("M 還原之後第 %d 關返返基準" % M_SLOT,
		Array(GameData.level_config(M_SLOT).families) == proc_fams,
		"families=%s want %s" % [str(GameData.level_config(M_SLOT).families), str(proc_fams)])

func _case_all_levels_baseline() -> void:
	## WALLS 空 = 每一關都必須同「從來冇加過牆」一模一樣。呢個 case 覆蓋**全部二十關**
	## (包括三個牆位 7/13/18),所以佢係「牆真係冇出街」嘅直接證據。
	for n in range(1, 21):
		var cfg: Dictionary = GameData.level_config(n)
		var want: Array = _procedural_families(n)
		_ok("B 第 %d 關冇被牆改過" % n, Array(cfg.families) == want,
			"got %s want %s" % [str(cfg.families), str(want)])
		_ok("B 第 %d 關 spawn 間隔係預設" % n,
			is_equal_approx(float(cfg.spawn_interval_min), 0.45),
			"got %.3f" % float(cfg.spawn_interval_min))
		_ok("B 第 %d 關冇標記做牆" % n, not bool(cfg.get("is_wall", false)), "is_wall true")

## level_config() 入面嗰條程序生成規則,喺呢度獨立重算一次做對照。
func _procedural_families(n: int) -> Array:
	var base_i: int = (n - 1) % 10
	var want: Array = [GameData.FAMILY_ORDER[base_i],
		GameData.FAMILY_ORDER[(base_i + 3) % 10]]
	if n % 2 == 0:
		want.append(GameData.FAMILY_ORDER[(base_i + 6) % 10])
	return want

## `_case_non_wall_untouched` 喺呢度拆走咗。佢行 [1,5,8,12,14,19,20] 七關,用嘅
## 係同 _procedural_families() 一模一樣嗰條式(當時抄咗一份 inline),斷言嘅亦係
## 同三句 —— 即係 _case_all_levels_baseline 行 1..20 嗰個嘅真子集。兩個一齊擺
## 喺度,報告會多七關嘅 ok 行,但捉唔到多一個 bug:任何令佢紅嘅改動,強嗰個一定
## 先紅。留返強嗰個。

func _case_hints() -> void:
	## 四條 key 特登留低,等牆返嚟嗰陣用,亦都記錄咗三幅牆本來想教嘅嘢
	## (續航戰 / 屍體數 / 屍體數 x 減傷)。佢哋而家冇 code 引用,所以呢度係唯一
	## 守住佢哋唔被翻譯清理掃走嘅嘢。
	for key in ["LEVELSEL_DANGER", "WALL_HINT_7", "WALL_HINT_13", "WALL_HINT_18"]:
		for loc in ["zh_TW", "en"]:
			TranslationServer.set_locale(loc)
			var txt: String = tr(key)
			_ok("H %s / %s 譯咗" % [key, loc], txt != key and txt.strip_edges() != "",
				"tr(%s) returned the key itself" % key)
	TranslationServer.set_locale(Meta.current_locale())
	# WALLS 空 = 冇一關攞得到 hint(包括牆位本身)
	for n in [5, 7, 13, 18]:
		_ok("H 第 %d 關而家冇 hint" % n, GameData.wall_hint_key(n) == "",
			"level %d returned '%s'" % [n, GameData.wall_hint_key(n)])

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("WALL ok   %s" % label)
	else:
		fails += 1
		print("WALL FAIL %s — %s" % [label, detail])
