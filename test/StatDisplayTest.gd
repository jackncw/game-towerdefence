extends Node
## 「升級介面上面每一個數字 = 玩家實戰見到嘅真數」—— 逐項對數。
##   godot --headless --path . test/StatDisplayTest.tscn
##
## 點解要一條專門嘅測試而唔係睇幾眼:
##
## 第十一輪報上嚟嘅 bug 係「劇毒瘴氣每秒毒傷 15 級顯示 130,進化之後升級欄
## 變返 25 → 32」。個 root cause 係 Upgrade._now_next() 叫 effective_stats()
## 冇傳 tier,所以 tier 參數食咗預設值 1。呢種錯**淨係喺已經進化嘅東西上面
## 出現**,而進化要六條軸課滿 15 級 + 6000 魔晶 —— 即係話冇一個人手測試流程
## 會行到嗰個狀態,而一個 for 迴圈行到。
##
## 對數嘅方法唔係「重新計一次」(咁樣就係將同一個錯抄兩次),而係:
##   顯示側 = Upgrade.now_next_values()      —— UI 唯一嘅出數點
##   引擎側 = Meta.tower_stats() / spell_stats() —— Tower.gd / Spells.gd 真正讀嗰個
## 兩邊由完全唔同嘅路入,所以佢哋夾得啱先有意思。
##
## 覆蓋:20 塔 x 6 軸 x 3 tier x 4 個等級向量 + 15 魔法 x 3 軸 x 3 tier x 4。

const UPG := preload("res://scripts/ui/Upgrade.gd")

## 四個等級向量:未課、中段、滿課,加一個唔平均嘅 —— 唔平均嗰個先捉得到
## 「用錯條軸嘅等級」呢類 off-by-one。
const LEVEL_PATTERNS := ["zero", "mid", "max", "ragged"]

var pass_n := 0
var fail_n := 0
var compared := 0
## 用第十輪嗰條(唔傳 tier 嘅)路計出嚟、同引擎唔夾嘅數字有幾多個。
var legacy_wrong := 0
var _first_failures: Array = []

func _check(ok: bool, what: String) -> void:
	if ok:
		pass_n += 1
	else:
		fail_n += 1
		if _first_failures.size() < 12:
			_first_failures.append(what)
		print("FAIL: ", what)

## 浮點對浮點。用相對誤差:tier 3 嘅傷害去到六位數,而一個絕對 epsilon
## 喺嗰個量級係冇意義嘅。
func _same(a: float, b: float) -> bool:
	return absf(a - b) <= maxf(1e-6, absf(b) * 1e-6)

func _levels_for(n: int, pattern: String) -> Array:
	var out: Array = []
	for i in n:
		match pattern:
			"zero": out.append(0)
			"mid": out.append(7)
			"max": out.append(GameData.MAX_UP_LV)
			_: out.append((i * 5 + 3) % (GameData.MAX_UP_LV + 1))
	return out

func _ready() -> void:
	Flow.nav_enabled = false
	var saved := Meta.to_dict().duplicate(true)

	for def in GameData.TOWERS:
		_audit(def, true)
	for def in GameData.SPELLS:
		_audit(def, false)
	_teeth()

	# 還原玩家存檔 —— 呢條測試搞過 Meta 入面每一件嘢。
	Meta.tower_up = saved["tower_up"]
	Meta.spell_up = saved["spell_up"]
	Meta.tower_tiers = saved["tower_tiers"]
	Meta.spell_tiers = saved["spell_tiers"]
	Meta.save_game()

	print("STATDISPLAY: %d passed, %d failed (%d 個數字對過;第十輪嗰條路會有 %d 個顯示錯)"
		% [pass_n, fail_n, compared, legacy_wrong])
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------------------
func _engine_stats(id: int, is_tower: bool) -> Dictionary:
	return Meta.tower_stats(id) if is_tower else Meta.spell_stats(id)

func _set_state(id: int, is_tower: bool, tier: int, levels: Array) -> void:
	var key := str(id)
	if is_tower:
		Meta.tower_tiers[key] = tier
		Meta.tower_up[key] = levels.duplicate()
	else:
		Meta.spell_tiers[key] = tier
		Meta.spell_up[key] = levels.duplicate()

func _audit(def: Dictionary, is_tower: bool) -> void:
	var id: int = def.id
	var n: int = def.ups.size()
	var label: String = "%s#%d" % ["塔" if is_tower else "魔法", id]
	for tier in range(1, GameData.MAX_TIER + 1):
		for pattern in LEVEL_PATTERNS:
			var levels := _levels_for(n, pattern)
			_set_state(id, is_tower, tier, levels)
			var engine := _engine_stats(id, is_tower)
			for dir in n:
				var stat: String = def.ups[dir].stat
				var shown: Array = UPG.now_next_values(def, levels, tier, dir)

				# 0. 舊 bug 嘅規模。用第十輪嗰條路(唔傳 tier)計一次,同引擎對,
				#    數住有幾多個數字曾經係錯嘅。呢個數唔會令測試失敗 —— 佢係
				#    一份記錄:「呢條測試守住緊幾多」。
				var legacy: Array = UPG.now_next_values(def, levels, 1, dir)
				if not _same(float(legacy[0]), float(engine.get(stat, 0.0))):
					legacy_wrong += 1

				# 1. 「而家」= 引擎而家真係用緊嗰個數
				compared += 1
				_check(_same(float(shown[0]), float(engine.get(stat, 0.0))),
					"%s t%d %s [%s] 而家值 顯示=%s 引擎=%s"
					% [label, tier, stat, pattern, shown[0], engine.get(stat, 0.0)])

				# 2. 「下一級」= 真係買咗之後引擎會用嗰個數。用真嘅購買狀態,
				#    唔係再計一次公式 —— 呢一步先分得出「公式啱」同「UI 啱」。
				var bumped := levels.duplicate()
				bumped[dir] = mini(int(levels[dir]) + 1, GameData.MAX_UP_LV)
				_set_state(id, is_tower, tier, bumped)
				var after := _engine_stats(id, is_tower)
				if not _same(float(legacy[1]), float(after.get(stat, 0.0))):
					legacy_wrong += 1
				compared += 1
				_check(_same(float(shown[1]), float(after.get(stat, 0.0))),
					"%s t%d %s [%s] 下一級 顯示=%s 引擎=%s"
					% [label, tier, stat, pattern, shown[1], after.get(stat, 0.0)])
				_set_state(id, is_tower, tier, levels)

			# 3. 效能面板嗰幾條 bar 讀嘅係同一個 dictionary。呢條 assertion
			#    守住將來冇人「順手」改返去讀 def.stats(即係 tier 1 基數)。
			if is_tower:
				for core in ["dmg", "rate", "range"]:
					compared += 1
					_check(_same(float(engine.get(core, 0.0)),
						float(GameData.effective_stats(def, levels, tier).get(core, 0.0))),
						"%s t%d 效能面板 %s [%s]" % [label, tier, core, pattern])

## 測試自己有冇牙。如果 tier 完全冇入到數,上面全部 assertion 一樣會綠 ——
## 因為兩邊會一齊錯。所以要證明:同一組等級之下,tier 2 嘅數真係大過 tier 1。
func _teeth() -> void:
	var def: Dictionary = GameData.spell_by_id(4)      # 劇毒瘴氣,報告入面嗰個
	var maxed := _levels_for(def.ups.size(), "max")
	var t1: Array = UPG.now_next_values(def, maxed, 1, 0)
	var t2: Array = UPG.now_next_values(def, [0, 0, 0], 2, 0)
	# 第十二輪:基礎每秒毒傷由 25 調到 18(佢喺 --spells bench 度係全表最高,
	# 417.8 對隕石 203.9),所以滿課由 130 變 123。呢度對嘅係「顯示側同引擎側
	# 講唔講同一個數」,唔係「嗰個數係幾多」—— 所以跟住 GameData 出數,
	# 唔再硬寫一個會隨平衡飄走嘅常數。
	var engine_dps: float = float(GameData.effective_stats(def, maxed, 1).dps)
	_check(_same(float(t1[0]), engine_dps),
		"劇毒瘴氣 tier 1 滿課每秒毒傷:顯示 %s vs 引擎 %.1f" % [t1[0], engine_dps])
	# 進化嘅契約係「唔會變弱」,唔係「一定變強」——  carry 令下一階嘅起點
	# 啱啱好接住上一階嘅終點,而相等係需求 3 明文接受嘅(「只會變強或者持平」)。
	_check(float(t2[0]) >= float(t1[0]) - 0.001,
		"進化之後嘅起步值唔細過 tier 1 滿課 (t2=%s t1=%s)" % [t2[0], t1[0]])
	# 而 tier 1 嘅公式套喺 tier 2 身上就係嗰單 bug 嘅樣:25 → 32。
	var wrong: Array = UPG.now_next_values(def, [0, 0, 0], 1, 0)
	_check(not _same(float(t2[0]), float(wrong[0])),
		"tier 2 嘅顯示唔等於 tier 1 嘅顯示(舊 bug 嘅簽名)")
