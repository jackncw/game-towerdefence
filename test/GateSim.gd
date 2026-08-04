extends Node
## 五原型 x 100 關嘅驗收模擬 (第十五輪)。
##
## BalanceSim 量嘅係「一個合理玩家」—— 一條曲線,一個人。呢一輪嘅八條 gate
## 全部都係關於**唔同投資程度嘅玩家之間嘅距離**(A1 打唔郁而 A2 打得郁,就係
## 「逼你進化一次」呢句設計話嘅全部內容),所以量度單位一定要係「原型」。
##
##   A0 白板    唔升級唔進化
##   A1 穩步    升級軸照課,永遠唔進化
##   A2 進化一  主力塔 + 主力魔法上到 tier 2
##   A3 進化二  主力塔 + 主力魔法上到 tier 3
##   A4 天頂    三座滿級 tier 3 塔 + 四個滿級 tier 3 魔法(**直接授予**)
##
## A0-A3 係**打返嚟**嘅:由第 1 關開始逐關打落去,用當關實際攞到嘅魔晶買嘢,
## 冇任何注資。所以佢哋嘅勝率表同時就係一條 pacing 曲線。
##
## A4 唔同:佢係一個**狀態**("滿級階段 3"),唔係一段歷史。佢直接授予,而
## 佢量嘅係天花板 —— Gate 6 問嘅正正就係「一個課到盡嘅人打唔打得低第 100 關」。
##
## 每個 (原型, seed) 係一次完整 campaign:第 1 關打到第 100 關,輸咗照過下一關
## (唔停喺第一堵牆,唔係量唔到後面),但**魔晶收入照實**,所以打得差就真係
## 窮。勝率 = 幾多個 seed 喺嗰一關贏咗。
##
## 用法(seed 分片,可以並行跑):
##   godot --headless --path . res://test/GateSim.tscn -- --arch=A1 --seeds=4 --seed0=0
##   godot --headless --path . res://test/GateSim.tscn -- --mode=gate1
##   godot --headless --path . res://test/GateSim.tscn -- --mode=frozen --seeds=4
##   godot --headless --path . res://test/GateSim.tscn -- --mode=contract --seeds=6
##
## 輸出係機讀 ROW 行,由 tools/gate_report.py 合併同評 gate。
## 會備份同還原真 save.json。

const DT := 1.0 / 30.0
const ATTEMPT_TIMEOUT := 420.0
const CAMPAIGN_LEVELS := 100

## 主力 —— 兩件都係一開波就有嘅嘢,所以「幾時進化到」量嘅係經濟,唔係解鎖運。
const MAIN_TOWER := 1        # 箭塔
const MAIN_SPELL := 1        # 隕石術
const UNLOCK_TARGET := 6     # 想有幾多座塔可以揀
const SPELL_TARGET := 3
const CORE_COUNT := 3
const CORE_DIRS := ["dmg", "rate", "range"]

## A4 嘅天頂陣容 —— 條 brief 嘅字面:「滿級階段 3 塔 + 多款滿級階段 3 魔法」。
##
## 一座塔而唔係三座,係因為場上每座同型塔共用同一份升級 —— 一座課滿嘅箭塔
## 等於成排箭塔都課滿,所以「多課幾座塔」對戰力嘅邊際貢獻遠細過睇落。三個
## 魔法就真係三份獨立輸出。
##
## 呢個 build 嘅埋單價大約 220 萬魔晶,而一個一次過通關嘅玩家打到第 100 關
## 大約攞到 180 萬 —— 即係話 A4 唔係打到就自動有,係要再 farm 一排。呢個
## 係有意嘅:Gate 6 要「多試幾場先過到」,而唔係「打到就贏」。
const A4_TOWERS := [1]                       # 箭塔
const A4_SPELLS := [1, 11, 13]               # 隕石 / 地震 / 天雷誅殺

var arch := "A1"
var seeds := 4
var seed0 := 0
var mode := "sweep"
## 由第幾關開始打。**只對 A4 有意義** —— 佢個 build 係直接授予嘅,唔靠歷史,
## 所以跳過頭九十關唔會令佢變弱。A0-A3 一定要由第 1 關打起(經濟要真)。
var lv_from := 1
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	get_tree().paused = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--arch="):
			arch = a.substr(7)
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--seed0="):
			seed0 = int(a.substr(8))
		elif a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--from="):
			lv_from = int(a.substr(7))
	match mode:
		"power":
			_power_table()
		"gate1":
			_gate1_table()
		"final":
			await _final_test()
		"econ":
			await _econ_curve()
		"frozen":
			await _frozen_test()
		"contract":
			await _contract_test()
		_:
			await _sweep()
	get_tree().paused = false
	Flow.nav_enabled = true
	_restore_save()
	get_tree().quit(0)

# ===========================================================================
# MODE sweep — 一個原型 x N 個 seed 嘅完整 campaign
# ===========================================================================
func _sweep() -> void:
	print("GATE MODE=sweep arch=%s seeds=%d seed0=%d" % [arch, seeds, seed0])
	print("GATE HDR arch seed lv win frac kills towers gold_income gold_left tower_cost crystals cheapest start_gold")
	for si in seeds:
		var sd: int = seed0 + si
		seed(0xC0FFEE + sd * 7919)
		Meta.reset_save()
		if arch == "A4":
			_grant_a4()
		var start: int = lv_from if arch == "A4" else 1
		for lv in range(start, CAMPAIGN_LEVELS + 1):
			if arch != "A4":
				_spend(lv)
			var c0: int = Meta.crystals
			var cheap: int = _median_core_cost()
			var r: Dictionary = await _play(lv)
			print("GATE ROW %s %d %d %d %.4f %d %d %d %d %d %d %d %d"
				% [arch, sd, lv, 1 if r.win else 0, r.frac, r.kills, r.towers,
				r.income, r.gold_left, GameData.place_cost(_main_field_tower(), lv),
				Meta.crystals, cheap, int(GameData.level_config(lv).start_gold)])
			if lv % 10 == 0:
				# 每十關報一次 build 狀態,pacing 曲線由呢啲行砌返出嚟
				print("GATE BUILD %s %d %d T%d S%d axes=%d/%d crystals=%d cum=%d"
					% [arch, sd, lv, Meta.tower_tier(MAIN_TOWER), Meta.spell_tier(MAIN_SPELL),
					_total_levels(), _total_axes(), Meta.crystals, c0])

# ===========================================================================
# MODE power — 「玩家力量 vs 敵人硬度」嘅解析對照(唔使打)
# ===========================================================================
## 點解要有呢個 mode:一次 A1 campaign 要兩分鐘,而調難度曲線係一件要試幾十
## 次嘅事。但難度曲線嘅第一階近似其實計得出 —— 玩家力量 ≈ 主力塔 DPS x 塔數,
## 而塔數而家係一個常數(建塔成本同金收入同一條曲線),所以淨係 DPS。
##
## DPS 唔用公式估,係**真係行一次買嘢政策**再問 Meta.tower_stats() —— 即係
## 話呢個表用嘅係遊戲本身嘅升級價、進化價、tier 倍率同 carry 規則,冇一個
## 數係喺呢度重新寫過嘅。唯一嘅近似係「唔使打就當攞到通關獎勵」。
##
## 敵人硬度 = wave_scale x 該關怪物等級嘅平均血量倍率 x 密度。
##
## 對照出嚟嘅 ratio = 玩家 / 敵人,兩者都以第 1 關做 1.0。ratio 跌穿某條線
## 就係「打唔郁」,而每一段要跌穿邊條線就係 Gate 2-6。真勝率仍然要靠
## campaign 量,但呢個表講到邊一段嘅斜率離譜,唔使等兩分鐘。
func _power_table() -> void:
	print("GATE MODE=power")
	print("GATE HDR lv wave lvlhp dense enemy A1 A2 A3 A4 r1 r2 r3 r4")
	print("GATE INFO cum100=%.0f" % GameData.cumulative_reward(CAMPAIGN_LEVELS))
	var arches := ["A1", "A2", "A3"]
	var dps := {}          # arch -> Array(101)
	for a in arches:
		seed(1)
		Meta.reset_save()
		arch = a
		var row: Array = [0.0]
		for n in range(1, CAMPAIGN_LEVELS + 1):
			_spend(n)
			row.append(_dps_index())
			# 冇打就冇收入 —— 手動派通關 + 首通,即係一個一次過通關嘅玩家
			Meta.crystals += GameData.level_crystal_reward(n) + GameData.level_first_clear_bonus(n)
		dps[a] = row
	seed(1)
	Meta.reset_save()
	_grant_a4()
	var a4: float = _dps_index()
	var base_enemy: float = _enemy_index(1)
	var base_p: float = float((dps["A1"] as Array)[1])
	for n in range(1, CAMPAIGN_LEVELS + 1):
		var e: float = _enemy_index(n) / base_enemy
		var p1: float = float((dps["A1"] as Array)[n]) / base_p
		var p2: float = float((dps["A2"] as Array)[n]) / base_p
		var p3: float = float((dps["A3"] as Array)[n]) / base_p
		var p4: float = a4 / base_p
		print("GATE ROW %d %.2f %.2f %.2f %.2f %.1f %.1f %.1f %.1f %.2f %.2f %.2f %.2f"
			% [n, GameData.wave_scale(n), _lvlhp(n), _dense(n), e,
			p1, p2, p3, p4, p1 / e, p2 / e, p3 / e, p4 / e])

## 主力塔嘅每秒輸出。光束塔嗰種 rate=10 嘅冇特殊處理 —— 呢度永遠問箭塔,
## 所以呢個數係一個**指數**,唔係一個絕對 DPS。
func _dps_index() -> float:
	var st: Dictionary = Meta.tower_stats(MAIN_TOWER)
	var d: float = float(st.get("dmg", 0.0)) * float(st.get("rate", 0.0))
	# 魔法:每個已解鎖魔法嘅直傷 / 冷卻,加埋落去。要行**全部**魔法而唔淨係
	# 主力 —— A4 同 A3 嘅分別有一大半就係「多幾個滿級魔法」,只計主力嘅話
	# 呢個表會報 A3 = A4,而嗰個唔係真嘅。
	for sid in Meta.unlocked_spells:
		var ss: Dictionary = Meta.spell_stats(int(sid))
		var cd: float = maxf(1.0, float(ss.get("cd", 8.0)))
		d += (float(ss.get("dmg", 0.0)) + float(ss.get("dps", 0.0)) * float(ss.get("dur", 0.0))) / cd
	return d

func _lvlhp(n: int) -> float:
	var cfg: Dictionary = GameData.level_config(n)
	var lo: int = int(cfg.lvl_min)
	var hi: int = int(cfg.lvl_max)
	var s := 0.0
	for l in range(lo, hi + 1):
		s += GameData.LVL_HP[l]
	return s / maxf(1.0, float(hi - lo + 1))

func _dense(n: int) -> float:
	return 1.6 / float(GameData.level_config(n).spawn_interval_start)

func _enemy_index(n: int) -> float:
	return GameData.difficulty(n)

# ===========================================================================
# MODE final — 第 100 關嘅 A3 / A4 對照(唔使打成個 campaign)
# ===========================================================================
## Gate 6 要 A3 ≤5% 而 A4 10-30%,即係話第 100 關嘅難度要**啱啱好**落喺兩個
## build 嘅門檻之間。嗰個窗好窄,所以要試好多次 FINAL_SCALE,而每次都由第 1
## 關打一次 campaign 係四分鐘。
##
## 呢個 mode 用「派彩但唔打」嘅方式砌返 A3 喺第 100 關嘅 build(同 --mode=power
## 完全一樣嘅做法),再淨係打第 100 關。一次二十秒。
func _final_test() -> void:
	print("GATE MODE=final arch=%s seeds=%d 難度=%.0f" % [arch, seeds, GameData.difficulty(100)])
	var wins := 0
	for si in seeds:
		seed(0xF1A1 + si * 7919)
		Meta.reset_save()
		if arch == "A4":
			_grant_a4()
		else:
			for n in range(1, CAMPAIGN_LEVELS + 1):
				_spend(n)
				Meta.crystals += GameData.level_crystal_reward(n) + GameData.level_first_clear_bonus(n)
			_spend(CAMPAIGN_LEVELS)
		var r: Dictionary = await _play(CAMPAIGN_LEVELS)
		wins += 1 if r.win else 0
		print("GATE ROW %s %d %d %.4f" % [arch, si, 1 if r.win else 0, r.frac])
	print("GATE FINAL %s 勝率 %.0f%% (%d/%d)" % [arch, 100.0 * wins / maxf(1, seeds), wins, seeds])

# ===========================================================================
# MODE gate1 — 「輸一場 = 起碼升到一級」
# ===========================================================================
## 純算術,唔使打:敗仗獎勵釘死喺 typical_upgrade_cost(),而後者而家係由派彩
## 曲線直接計出嚟(見 GameData)。所以呢條 gate 係一條**恆等式檢查**,唔係一個
## 統計 —— 佢應該喺 100 關全部成立,而唔係「大部分成立」。
func _gate1_table() -> void:
	print("GATE MODE=gate1")
	print("GATE HDR lv lose_typ cost ratio clear cap contract_lose contract_ratio")
	var worst := 999.0
	var best := 0.0
	var bad := 0
	for n in range(1, CAMPAIGN_LEVELS + 1):
		var c: int = GameData.typical_upgrade_cost(n)
		# 一場「有合理進度」嘅敗仗 = LOSE_TYPICAL_PROGRESS
		var lose: int = GameData.level_lose_reward(n, int(GameData.LOSE_EXPECTED_KILLS * 0.5),
			30.0, 60.0, 0.35, false)
		var ratio: float = float(lose) / maxf(1.0, float(c))
		# 合約關:穩陣策略嘅倍率(五張 risk-0 卡)
		var cl: int = lose
		if GameData.is_contract_level(n):
			cl = int(round(float(lose) * _safe_mult()))
		var cr: float = float(cl) / maxf(1.0, float(c))
		worst = minf(worst, ratio)
		best = maxf(best, ratio)
		if ratio < 1.0:
			bad += 1
		print("GATE ROW %d %d %d %.3f %d %d %d %.3f"
			% [n, lose, c, ratio, GameData.level_crystal_reward(n),
			GameData.level_lose_max(n), cl, cr])
	print("GATE GATE1 min=%.3f max=%.3f below1=%d" % [worst, best, bad])

## 穩陣策略五張卡嘅晶石倍率(全部 risk 0,取平均倍率嘅五次方)。
func _safe_mult() -> float:
	var s := 0.0
	var n := 0
	for c in GameData.CONTRACTS:
		if int(c["risk"]) == 0:
			s += float(c["crystal"])
			n += 1
	return pow(s / maxf(1.0, float(n)), GameData.CONTRACT_PICKS)

# ===========================================================================
# MODE econ — 金幣 vs 建塔成本
# ===========================================================================
## 指標:「全場攞到嘅總金 ÷ 當關再起一座主力塔嘅成本」。呢個比率而家係由
## 結構保證唔發散嘅(兩條曲線同一個指數,見 GameData.gold_scale),所以呢個
## mode 量嘅係嗰個常數落喺邊,同埋結構有冇被邊個 mechanic 破壞。
func _econ_curve() -> void:
	print("GATE MODE=econ")
	print("GATE HDR lv income start_gold tower_cost ratio towers")
	seed(0xE0011)
	Meta.reset_save()
	for lv in range(1, CAMPAIGN_LEVELS + 1):
		_spend_a1(lv)
		var r: Dictionary = await _play(lv)
		var cost: int = GameData.place_cost(_main_field_tower(), lv)
		var total: int = int(r.income) + int(GameData.level_config(lv).start_gold)
		print("GATE ROW %d %d %d %d %.3f %d"
			% [lv, r.income, GameData.level_config(lv).start_gold, cost,
			float(total) / maxf(1.0, float(cost)), r.towers])

# ===========================================================================
# MODE frozen — Gate 3「停低唔升就好快打唔郁」
# ===========================================================================
## 攞第 N-5 關嘅 A1 build 去打第 N 關。實作:一路打 A1 campaign,每關收一份
## build 快照(升級軸 + tier + 解鎖),到第 N 關時額外用 N-5 嗰份快照再打一場。
##
## 快照要連**魔晶**都換返舊嗰個數咩?唔使 —— 場外魔晶唔會喺場入面用到,而
## 且要量嘅係「一個五關冇升級過嘅玩家」,唔係「一個窮咗嘅玩家」。
func _frozen_test() -> void:
	print("GATE MODE=frozen seeds=%d seed0=%d" % [seeds, seed0])
	print("GATE HDR seed lv live_win frozen_win frozen_frac")
	for si in seeds:
		var sd: int = seed0 + si
		seed(0xF0BE + sd * 7919)
		Meta.reset_save()
		var snaps: Array = []
		for lv in range(1, 46):        # Gate 3 只講 11-40,打到 45 收貨
			_spend_a1(lv)
			snaps.append(_snapshot())
			var live: Dictionary = await _play(lv)
			var fw := -1
			var ff := 0.0
			if lv >= 16 and lv <= 40:
				var keep: Dictionary = _snapshot()
				_restore_snapshot(snaps[lv - 6])   # snaps[i] = 第 i+1 關開波前
				var fr: Dictionary = await _play(lv)
				fw = 1 if fr.win else 0
				ff = fr.frac
				_restore_snapshot(keep)
			print("GATE ROW %d %d %d %d %.4f" % [sd, lv, 1 if live.win else 0, fw, ff])

# ===========================================================================
# MODE contract — Gate 8
# ===========================================================================
## 穩陣 vs 貪心,喺同一份 build 上面打同一批合約關同埋佢哋前後嘅普通關。
##
## 「期望晶石收入」= 實際入袋(通關就係通關獎勵、輸就係敗仗獎勵),唔係
## 「倍率」—— 一張 x1.45 嘅卡打到輸就唔係 1.45 倍收入,而 Gate 8 問嘅正正
## 係嗰個實際數。
func _contract_test() -> void:
	print("GATE MODE=contract seeds=%d" % seeds)
	print("GATE HDR seed lv kind strat win crystals frac")
	var levels: Array = []
	for n in range(7, CAMPAIGN_LEVELS):
		if GameData.is_contract_level(n):
			levels.append(n)
	for si in seeds:
		var sd: int = seed0 + si
		for strat in ["safe", "greedy"]:
			seed(0xC047 + sd * 7919)
			Meta.reset_save()
			_contract_strategy = strat
			for lv in range(1, CAMPAIGN_LEVELS + 1):
				_spend_a1(lv)
				var is_c: bool = GameData.is_contract_level(lv)
				var neighbour: bool = GameData.is_contract_level(lv - 1) \
					or GameData.is_contract_level(lv + 1)
				if not (is_c or neighbour):
					# 唔關事嘅關卡照打(經濟要真),但唔使出行
					await _play(lv)
					continue
				var c0: int = Meta.crystals
				var r: Dictionary = await _play(lv)
				print("GATE ROW %d %d %s %s %d %d %.4f"
					% [sd, lv, "contract" if is_c else "normal", strat,
					1 if r.win else 0, Meta.crystals - c0, r.frac])
	_contract_strategy = "safe"

## 合約關嘅自動策略。
##   safe   永遠揀風險最低嗰張(平手就揀晶石倍率最細)—— 一個唔想賭嘅人
##   greedy 永遠揀晶石倍率最高嗰張 —— 一個全押嘅人
## 難度 gate(2-7)一律用 safe 讀數:自選增益會污染難度讀數,而合約關嘅
## 難度應該同佢前後嘅普通關擺得埋一齊比較。
var _contract_strategy := "safe"

func _pick_contract(b) -> int:
	var offer: Array = b.contract_offer
	if offer.is_empty():
		return -1
	var best: int = int(offer[0])
	for i in offer:
		var c: Dictionary = GameData.CONTRACTS[int(i)]
		var bc: Dictionary = GameData.CONTRACTS[best]
		if _contract_strategy == "greedy":
			if float(c["crystal"]) > float(bc["crystal"]):
				best = int(i)
		else:
			if int(c["risk"]) < int(bc["risk"]) \
					or (int(c["risk"]) == int(bc["risk"]) and float(c["crystal"]) < float(bc["crystal"])):
				best = int(i)
	return best

# ===========================================================================
# 一場戰鬥
# ===========================================================================
func _play(level: int) -> Dictionary:
	var b = await _start(level)
	var start_gold: int = b.gold
	var spent := 0
	var spots := _spots(b)
	var spot_i := 0
	var t := 0.0
	var cast_t := 0.0
	while not b.ended and t < ATTEMPT_TIMEOUT:
		# 合約關:攤住卡就唔會有時間流逝(Battle._process 直接返),所以要
		# 喺呢度答佢,唔係就會空轉到 timeout。
		if b.contract_pending:
			var pick: int = _pick_contract(b)
			if pick < 0:
				break
			b.choose_contract(pick)
			continue
		while spot_i < spots.size():
			var id := _next_buy(b)
			if id == 0:
				break
			while spot_i < spots.size() and not b.can_place(spots[spot_i]):
				spot_i += 1
			if spot_i >= spots.size():
				break
			var cost: int = b.place_cost(id)
			if b.place_tower(id, spots[spot_i]):
				spent += cost
			spot_i += 1
		cast_t -= DT
		if cast_t <= 0.0:
			cast_t = 0.5
			_auto_cast(b)
		_step(b, DT)
		t += DT
	var res := {
		"win": b.ended and Flow.last_result.get("win", false),
		"time": t,
		"kills": b.kills,
		"towers": b.towers.size(),
		"income": b.gold + spent - start_gold,
		"gold_left": b.gold,
		"frac": float(b.sim_max_frac),
	}
	await _end(b)
	return res

## 魔法自動施放。冇呢樣嘢,A2/A3/A4 投資落魔法嗰半邊喺量度上面等於唔存在,
## 而 Gate 4/5 講明係「一種塔 + 一種魔法」。
##
## 規則簡單而且對每個原型一樣:冷卻好晒就放,單體嗰啲點名最深嗰隻,範圍
## 嗰啲點名最密嗰舊。呢個唔係最優打法,但佢對五個原型一模一樣,所以原型
## 之間嘅差距仍然只反映 build。
func _auto_cast(b) -> void:
	if b.monsters.is_empty():
		return
	var alive := 0
	for m in b.monsters:
		if m.alive:
			alive += 1
	if alive < 4 and not b.boss_spawned:
		return
	for id in Meta.unlocked_spells:
		if float(b.spell_cd.get(int(id), 0.0)) > 0.0:
			continue
		var def := GameData.spell_by_id(int(id))
		if def.is_empty():
			continue
		if bool(def.target):
			b._cast_spell_at(int(id), _cluster_pos(b))
		else:
			b._cast_spell_now(int(id))

## 最多怪聚埋嘅位。O(n^2) 但每 0.5 秒先行一次。
func _cluster_pos(b) -> Vector2:
	var best: Vector2 = b.base_pos
	var best_n := -1
	var live: Array = []
	for m in b.monsters:
		if m.alive:
			live.append(m)
	if live.is_empty():
		return best
	# boss 在場就直接點名 boss —— 單體魔法存在嘅理由就係佢
	if b.boss_ref != null and is_instance_valid(b.boss_ref) and b.boss_ref.alive:
		return b.boss_ref.global_position
	for m in live:
		var n := 0
		for o in live:
			if m.global_position.distance_squared_to(o.global_position) <= 150.0 * 150.0:
				n += 1
		if n > best_n:
			best_n = n
			best = m.global_position
	return best

# --- 買塔規則(五個原型共用)-----------------------------------------------
const SUPPORT := ["slowfield", "alchemy", "barracks", "frost", "magnet", "teleport", "curse", "holy", "thorn"]
const SUPPORT_SHARE := 0.35
const BOSS_SHARE := 0.35

func _next_buy(b) -> int:
	var want_support: bool = float(_support_count(b)) < float(maxi(1, b.towers.size())) * SUPPORT_SHARE
	var best := _pick(b, want_support)
	if best == 0:
		best = _pick(b, not want_support)
	return best

func _pick(b, support: bool) -> int:
	var best := 0
	var best_v := -1.0
	for id in Meta.unlocked_towers:
		var def := GameData.tower_by_id(int(id))
		if def.is_empty():
			continue
		var cost: int = b.place_cost(int(id))
		if cost > b.gold:
			continue
		if (def.mech in SUPPORT) != support:
			continue
		var v: float = _support_value(b, int(id), cost) if support else _damage_value(int(id), cost)
		if v > best_v:
			best_v = v
			best = int(id)
	return best

func _damage_value(id: int, cost: int) -> float:
	var st: Dictionary = Meta.tower_stats(id)
	var dps: float = float(st.get("dmg", 0.0)) * float(st.get("rate", 0.0))
	var boss_dps: float = dps * (1.0 + float(st.get("bossmult", 0.0)))
	return (dps * (1.0 - BOSS_SHARE) + boss_dps * BOSS_SHARE) / maxf(1.0, float(cost))

func _support_value(b, id: int, cost: int) -> float:
	if GameData.tower_by_id(id).mech == "curse" and _damage_tower_count(b) < 4:
		return -1.0
	return 1000.0 / maxf(1.0, float(cost))

func _damage_tower_count(b) -> int:
	var n := 0
	for t in b.towers:
		if not (t.mech in SUPPORT):
			n += 1
	return n

func _support_count(b) -> int:
	var n := 0
	for t in b.towers:
		if t.mech in SUPPORT:
			n += 1
	return n

## 場上最值得起嘅塔 —— 「再起一座主力塔要幾錢」呢條指標問嘅係佢。
func _main_field_tower() -> int:
	var best: int = MAIN_TOWER
	var best_v := -1.0
	for id in Meta.unlocked_towers:
		var def := GameData.tower_by_id(int(id))
		if def.is_empty() or def.mech in SUPPORT:
			continue
		var v: float = _damage_value(int(id), int(def.place_cost))
		if v > best_v:
			best_v = v
			best = int(id)
	return best

# ===========================================================================
# 原型嘅買嘢政策
# ===========================================================================
## A1 / A2 / A3 行**同一條**買嘢政策,唯一嘅分別係 `target_tier`。
##
## 第一版唔係咁:A1 平均鋪開三座塔嘅核心軸,A2 專攻一座。結果係佢哋喺第
## 11-40 關(兩個都仲未進化)嘅勝率係 25% 對 100% —— 即係話 Gate 4 量到嘅
## 「A1 打唔郁而 A2 打得郁」其實一大半係**專精 vs 鋪開**,唔係進化。一條
## 用嚟驗證進化系統嘅 gate,唔可以有一個更大嘅混淆變數坐喺入面。
func _spend(level: int) -> void:
	match arch:
		"A0":
			return                       # 白板:一個仙都唔使
		"A1":
			_spend_evolver(1)            # 永遠唔進化
		"A2":
			_spend_evolver(2)
		"A3":
			_spend_evolver(3)

## A1 嘅買嘢政策 —— **同 A1 原型完全一樣嗰條**。
##
## 本來呢度另外寫住一條「平均鋪開三座塔核心軸」嘅政策,而 A1 原型行嘅係
## `_spend_evolver(1)`(專攻主力)。兩條唔同嘅政策叫同一個名,結果就係
## frozen(Gate 3b)同 contract(Gate 8)量緊嘅「A1」根本唔係勝率表入面
## 嗰個 A1 —— 兩份數擺埋一齊比較就係比緊兩個唔同嘅人。
func _spend_a1(_level: int) -> void:
	_spend_evolver(1)

## A2 / A3:主力塔同主力魔法一齊向上,課滿就進化,去到 `target` 階為止。
##
## 呢個政策同 A1 用同一份收入,所以兩者之間嘅差距純粹係「錢用咗喺邊」——
## 而嗰個正正就係 Gate 4 / Gate 5 要量嘅嘢。
func _spend_evolver(target: int) -> void:
	var guard := 0
	while guard < 1200:
		guard += 1
		if Meta.unlocked_towers.size() < UNLOCK_TARGET and _buy_best_unlock():
			continue
		if Meta.unlocked_spells.size() < SPELL_TARGET and _buy_spell_unlock():
			continue
		# 夠條件就進化,而且進化排喺任何一級升級之前 —— 佢係嗰條路嘅出口。
		# 夠條件但唔夠錢就**儲**,唔好散去買第二啲嘢:嗰個就係「進化玩家」
		# 同「唔進化玩家」喺同一份收入下面嘅真實分別。
		var did := false
		var saving := false
		for pair in [[MAIN_TOWER, true], [MAIN_SPELL, false]]:
			var id: int = int(pair[0])
			var is_t: bool = bool(pair[1])
			if Meta.item_tier(id, is_t) >= target:
				continue
			if Meta.can_evolve(id, is_t):
				if Meta.can_afford(Meta.evolve_cost(id, is_t)):
					Meta.evolve(id, is_t)
					did = true
				else:
					saving = true
		if did:
			continue
		if saving:
			return
		# 主力塔六軸 + 主力魔法三軸,買最平嗰條。三個原型喺呢一步一模一樣。
		if _buy_cheapest_axis(MAIN_TOWER, true):
			continue
		if _buy_cheapest_axis(MAIN_SPELL, false):
			continue
		if _buy_core_upgrade():
			continue
		return

## A4 天頂 —— 直接授予。見檔案開頭:佢係一個狀態,唔係一段歷史。
func _grant_a4() -> void:
	for t in GameData.TOWERS:
		if not Meta.unlocked_towers.has(int(t.id)):
			Meta.unlocked_towers.append(int(t.id))
	for s in GameData.SPELLS:
		if not Meta.unlocked_spells.has(int(s.id)):
			Meta.unlocked_spells.append(int(s.id))
	for id in A4_TOWERS:
		Meta.tower_tiers[str(id)] = GameData.MAX_TIER
		Meta.tower_up[str(id)] = _maxed(GameData.tower_by_id(id).ups.size())
	for id in A4_SPELLS:
		Meta.spell_tiers[str(id)] = GameData.MAX_TIER
		Meta.spell_up[str(id)] = _maxed(GameData.spell_by_id(id).ups.size())
	Meta.crystals = 0
	Meta.save_game()

func _maxed(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(GameData.MAX_UP_LV)
	return a

# --- 買嘢原語 ---------------------------------------------------------------
func _buy_best_unlock() -> bool:
	var best := 0
	var best_cost := 1 << 30
	for t in GameData.TOWERS:
		var id: int = int(t.id)
		if Meta.is_tower_unlocked(id):
			continue
		var c: int = int(t.unlock)
		if c > 0 and c < best_cost:
			best_cost = c
			best = id
	if best == 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.unlock_tower(best)

func _buy_spell_unlock() -> bool:
	var best := 0
	var best_cost := 1 << 30
	for s in GameData.SPELLS:
		var id: int = int(s.id)
		if Meta.is_spell_unlocked(id):
			continue
		var c: int = Meta.spell_unlock_cost(id)
		if c < best_cost:
			best_cost = c
			best = id
	if best == 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.unlock_spell(best)

## 核心軸 = 頭 CORE_COUNT 座塔嘅 CORE_DIRS + 主力魔法嘅三條軸。
## 買最平嗰條 —— 唔係「平均鋪開」(嗰個模擬唔到人),亦唔係「全押一條」
## (嗰個買唔起進化條件)。
func _buy_core_upgrade() -> bool:
	var best_kind := ""
	var best_id := 0
	var best_dir := -1
	var best_cost := 1 << 30
	for id in _core_towers():
		var levels: Array = Meta.tower_levels(id)
		for d in levels.size():
			if String(GameData.tower_by_id(id).ups[d].stat) not in CORE_DIRS:
				continue
			if int(levels[d]) >= GameData.MAX_UP_LV:
				continue
			var c: int = Meta.tower_up_cost(id, d)
			if c < best_cost:
				best_cost = c; best_id = id; best_dir = d; best_kind = "tower"
	for sid in Meta.unlocked_spells:
		var slv: Array = Meta.spell_levels(int(sid))
		for d in slv.size():
			if int(slv[d]) >= GameData.MAX_UP_LV:
				continue
			var c: int = Meta.spell_up_cost(int(sid), d)
			if c < best_cost:
				best_cost = c; best_id = int(sid); best_dir = d; best_kind = "spell"
	if best_dir < 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.buy_tower_upgrade(best_id, best_dir) if best_kind == "tower" \
		else Meta.buy_spell_upgrade(best_id, best_dir)

func _buy_cheapest_axis(id: int, is_tower: bool) -> bool:
	var levels: Array = Meta.tower_levels(id) if is_tower else Meta.spell_levels(id)
	var best_dir := -1
	var best_cost := 1 << 30
	for d in levels.size():
		if int(levels[d]) >= GameData.MAX_UP_LV:
			continue
		var c: int = Meta.tower_up_cost(id, d) if is_tower else Meta.spell_up_cost(id, d)
		if c < best_cost:
			best_cost = c
			best_dir = d
	if best_dir < 0 or not Meta.can_afford(best_cost):
		return false
	return Meta.buy_tower_upgrade(id, best_dir) if is_tower \
		else Meta.buy_spell_upgrade(id, best_dir)

func _core_towers() -> Array:
	var out: Array = []
	for id in Meta.unlocked_towers:
		if not (GameData.tower_by_id(int(id)).mech in SUPPORT):
			out.append(int(id))
		if out.size() >= CORE_COUNT:
			break
	return out if not out.is_empty() else [MAIN_TOWER]

## Gate 1 嘅「最平一個有意義升級」。用**中位數**而唔係最細值:一條啱啱開軸
## 嘅升級永遠係全場最平,而「輸一場買到一條你根本唔想課嘅軸嘅第一級」唔係
## 呢條 gate 想講嘅嘢。中位數係 GameData.typical_upgrade_cost() 用緊嘅同一個
## 定義,所以模擬同數據層問嘅係同一條問題。
func _median_core_cost() -> int:
	var costs: Array = []
	for id in _core_towers():
		var levels: Array = Meta.tower_levels(id)
		for d in levels.size():
			if String(GameData.tower_by_id(id).ups[d].stat) in CORE_DIRS \
					and int(levels[d]) < GameData.MAX_UP_LV:
				costs.append(Meta.tower_up_cost(id, d))
	for sid in Meta.unlocked_spells:
		var slv: Array = Meta.spell_levels(int(sid))
		for d in slv.size():
			if int(slv[d]) < GameData.MAX_UP_LV:
				costs.append(Meta.spell_up_cost(int(sid), d))
	if costs.is_empty():
		return GameData.upgrade_cost(GameData.TYPICAL_AXIS_BASE, GameData.MAX_UP_LV * GameData.MAX_TIER - 1)
	costs.sort()
	return int(costs[costs.size() / 2])

func _total_levels() -> int:
	var n := 0
	for k in Meta.tower_up:
		for v in Meta.tower_up[k]:
			n += int(v)
	for k in Meta.spell_up:
		for v in Meta.spell_up[k]:
			n += int(v)
	return n

func _total_axes() -> int:
	var n := 0
	for k in Meta.tower_up:
		n += (Meta.tower_up[k] as Array).size()
	for k in Meta.spell_up:
		n += (Meta.spell_up[k] as Array).size()
	return maxi(1, n)

# --- build 快照(Gate 3)-----------------------------------------------------
func _snapshot() -> Dictionary:
	return {
		"tu": Meta.tower_up.duplicate(true),
		"su": Meta.spell_up.duplicate(true),
		"tt": Meta.tower_tiers.duplicate(true),
		"st": Meta.spell_tiers.duplicate(true),
		"ut": Meta.unlocked_towers.duplicate(),
		"us": Meta.unlocked_spells.duplicate(),
	}

func _restore_snapshot(s: Dictionary) -> void:
	Meta.tower_up = (s["tu"] as Dictionary).duplicate(true)
	Meta.spell_up = (s["su"] as Dictionary).duplicate(true)
	Meta.tower_tiers = (s["tt"] as Dictionary).duplicate(true)
	Meta.spell_tiers = (s["st"] as Dictionary).duplicate(true)
	Meta.unlocked_towers = (s["ut"] as Array).duplicate()
	Meta.unlocked_spells = (s["us"] as Array).duplicate()

# ===========================================================================
# harness 原語(同 BalanceSim 一樣:tree 全程 paused,逐個節點手動 _process)
# ===========================================================================
func _start(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

func _spots(b) -> Array:
	var out: Array = []
	var step := 74.0
	var lo: Vector2 = b.BUILD_MIN
	var hi: Vector2 = b.BUILD_MAX
	var y: float = lo.y
	while y <= hi.y:
		var x: float = lo.x
		while x <= hi.x:
			var p: Vector2 = b.snap(Vector2(x, y))
			if b.can_place(p):
				out.append(p)
			x += step
		y += step
	# 沿住路徑由出怪口排落去 —— 一個真人玩家就係咁鋪
	out.sort_custom(func(a, c): return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))
	return out

# --- save 備份 ---------------------------------------------------------------
func _backup_save() -> void:
	_had_save = FileAccess.file_exists(Meta.SAVE_PATH)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_bytes)
			f.close()
	elif FileAccess.file_exists(Meta.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.SAVE_PATH))
