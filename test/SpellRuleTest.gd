extends Node
## 第十二輪:三條寫成硬性不變式嘅魔法規矩,加一張存在感 bench 表。
##
## 呢三條唔係「呢一輪修好咗嘅三個 bug」,係「呢三件事以後唔准再發生」。
## 分別喺:一個修好咗嘅數值下一次有人調曲線就會靜靜咁反轉,而一條掃全部
## 組合嘅斷言唔會 —— 佢喺 CI 度每次都問返同一條問題。
##
##   godot --headless --path . res://test/SpellRuleTest.tscn

var fails := 0
var lines: Array = []

## 存在感門檻(需求 4)。全部魔法用同一把尺,唔係逐款各有各講法。
##
## 「一次滿級施放」對**當關標準小怪**造成嘅傷害,要佔佢生命上限幾多。
## 0.60 = 一炮打甩六成血。點解揀 0.60 而唔係「殺死一波嘅 30%」:後者
## 量到嘅係「有幾多隻企喺爆炸範圍入面」,即係一個關於刷怪密度同走位嘅數,
## 而唔係一個關於魔法本身嘅數 —— 同一個魔法喺兩個路線會量到兩個答案。
## 用「對單一目標打甩幾多成血」就同密度無關,而 AoE 嘅範圍優勢係額外賺嘅。
const PRESENCE_MOB := 0.60
## 對 boss 嘅門檻。boss 血係小怪嘅十四倍,所以呢個數細好多先合理。
const PRESENCE_BOSS := 0.05

## 每一階「預期會喺邊一段關卡用」。tier 2 @ 24 關、tier 3 @ 38 關(第十一輪
## 量到嘅實際出現關卡),所以 bench 就喺嗰幾關度問「呢一刻佢仲有冇聲氣」。
const BENCH_LEVEL := [12, 30, 40]

func _ready() -> void:
	Crash.enabled = false
	_case_control_invariant()
	_case_monotonic(GameData.SPELLS, "魔法")
	_case_monotonic(GameData.TOWERS, "塔")
	_case_miasma_healcut()
	_bench_presence()
	for l in lines:
		print(l)
	print("SPELLRULE %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + what)

# ---------------------------------------------------------------------------
# 需求 1 — 唔准無縫控場
# ---------------------------------------------------------------------------
## 15 款 × 3 階 × 15 級 = 675 個組合,逐個問:控場持續 < 冷卻 × 0.7。
##
## 掃全部三個 tier 而唔係淨係最尾嗰個,係因為「進化之後先爆」同「一開始就爆」
## 係兩個唔同嘅 bug,而報告要分得出係邊一個。
func _case_control_invariant() -> void:
	var checked := 0
	var worst := 0.0
	var worst_who := ""
	for def in GameData.SPELLS:
		for tier in range(1, GameData.MAX_TIER + 1):
			for lv in range(1, GameData.MAX_UP_LV + 1):
				var levels: Array = []
				for i in (def.ups as Array).size():
					levels.append(lv)
				var c: Dictionary = GameData.spell_control(def, levels, tier)
				checked += 1
				var dur: float = float(c.dur)
				var cd: float = float(c.cd)
				if dur <= 0.0:
					continue          # 呢款喺呢個配置之下唔控場
				var limit: float = cd * GameData.CONTROL_MAX_CD_FRAC
				var ratio: float = dur / maxf(0.001, cd)
				if ratio > worst:
					worst = ratio
					worst_who = "%s t%d lv%d (%s %.2fs / cd %.2fs)" % [
						def.mech, tier, lv, c.kind, dur, cd]
				ok(dur < limit,
					"%s t%d lv%d:控場 %.2fs 唔細過冷卻 %.2fs 嘅 0.7 倍 (%.2fs)"
					% [def.mech, tier, lv, dur, cd, limit])
	ok(checked == 675, "應該掃 675 個組合,實際 %d" % checked)
	lines.append("控場不變式:%d 個組合,最貼近上限 = %s (%.0f%% of cd,上限 70%%)"
		% [checked, worst_who, worst * 100.0])

# ---------------------------------------------------------------------------
# 需求 3 — 進化嚴格單調
# ---------------------------------------------------------------------------
## 進化嗰一刻(上一階課滿 -> 下一階全部歸零)冇任何一個維度變差。
##
## 對比嘅係**真實嘅兩個狀態**:tier N 六/三條軸全 15 級,對 tier N+1 全 0 級
## (進化會將軸歸零,所以嗰個就係玩家撳完進化之後嗰一秒真正攞喺手上面嘅嘢)。
func _case_monotonic(defs: Array, label: String) -> void:
	var regressions := 0
	for def in defs:
		var n: int = (def.ups as Array).size()
		var maxed: Array = []
		var zero: Array = []
		for i in n:
			maxed.append(GameData.MAX_UP_LV)
			zero.append(0)
		for t in range(1, GameData.MAX_TIER):
			var before: Dictionary = GameData.effective_stats(def, maxed, t)
			var after: Dictionary = GameData.effective_stats(def, zero, t + 1)
			for stat in before.keys():
				if not after.has(stat):
					continue
				var a: float = float(before[stat])
				var b: float = float(after[stat])
				var lower_better: bool = stat in GameData.LOWER_IS_BETTER
				var good: bool = (b <= a + 1e-6) if lower_better else (b >= a - 1e-6)
				if not good:
					regressions += 1
				ok(good, "%s %s t%d->t%d 「%s」倒退:%.3f -> %.3f%s"
					% [label, def.mech, t, t + 1, stat, a, b,
					   "(愈細愈好)" if lower_better else ""])
	lines.append("%s 進化單調性:%d 件 × 2 個交界,倒退 %d 項" % [label, defs.size(), regressions])

# ---------------------------------------------------------------------------
# 需求 2 — 劇毒瘴氣封回復
# ---------------------------------------------------------------------------
func _case_miasma_healcut() -> void:
	var def: Dictionary = GameData.spell_by_id(4)
	var maxed := [GameData.MAX_UP_LV, GameData.MAX_UP_LV, GameData.MAX_UP_LV]
	var got: Array = []
	for t in range(1, GameData.MAX_TIER + 1):
		got.append(float(GameData.effective_stats(def, maxed, t).get("healcut", 0.0)))
	ok(got[0] >= 0.50 and got[0] <= 0.60, "瘴氣 t1 滿級減回復要喺 50-60%%,而家 %.0f%%" % (got[0] * 100))
	ok(got[1] >= 0.75 and got[1] <= 0.85, "瘴氣 t2 滿級減回復要喺 75-85%%,而家 %.0f%%" % (got[1] * 100))
	ok(is_equal_approx(got[2], 1.0), "瘴氣 t3 滿級減回復要係 100%%,而家 %.0f%%" % (got[2] * 100))
	# 「減 100%」要真係等於「回 0」,唔係「回好少」—— 呢個係一條行為斷言,
	# 唔係一條數值斷言:Monster.heal() 入面條式一日寫錯,個數字仍然係 1.00。
	var m := Monster.new()
	m.alive = true
	m.max_hp = 1000.0
	m.hp = 500.0
	m.heal_cut = got[2]
	m.heal_cut_time = 1.0
	var healed: float = m.request_heal(300.0, true)
	ok(is_zero_approx(healed), "t3 瘴氣覆蓋之下實測回復量要係 0,而家 %.2f" % healed)
	m.free()
	lines.append("劇毒瘴氣減回復:t1 %.0f%% / t2 %.0f%% / t3 %.0f%%(實測回復 %.2f)"
		% [got[0] * 100, got[1] * 100, got[2] * 100, healed])

# ---------------------------------------------------------------------------
# 需求 4 — 存在感 bench
# ---------------------------------------------------------------------------
## 一次滿級施放,對「當關標準小怪」同「當關 boss」各打甩幾多成血。
##
## 標準小怪 = 嗰一關家族表中間嗰隻、生物等級取該關嘅上限(即係嗰關最硬嗰批
## 雜兵,唔係最軟嗰批)—— 用最硬嗰批做分母,量到嘅係下限。
func _bench_presence() -> void:
	lines.append("")
	lines.append("存在感 bench(一次滿級施放 ÷ 目標生命上限;門檻 小怪 %.0f%% / boss %.0f%%)"
		% [PRESENCE_MOB * 100, PRESENCE_BOSS * 100])
	lines.append("%-12s %-6s %8s %8s %8s %s" % ["魔法", "階", "關", "對小怪", "對boss", "判定"])
	for def in GameData.SPELLS:
		var n: int = (def.ups as Array).size()
		var maxed: Array = []
		for i in n:
			maxed.append(GameData.MAX_UP_LV)
		for t in range(1, GameData.MAX_TIER + 1):
			var lvl: int = BENCH_LEVEL[t - 1]
			var s: Dictionary = GameData.effective_stats(def, maxed, t)
			var ws: float = GameData.wave_scale(lvl)
			var cfg: Dictionary = GameData.level_config(lvl)
			var fam: String = String(cfg.families[0])
			var mob: Dictionary = GameData.creature_stats(fam, int(cfg.lvl_max), ws)
			var boss: Dictionary = GameData.boss_stats(String(cfg.boss_family), ws)
			var mob_frac: float = _cast_damage(def, s, float(mob.hp), false) / float(mob.hp)
			var boss_frac: float = _cast_damage(def, s, float(boss.hp), true) / float(boss.hp)
			var is_dmg: bool = _is_damage_spell(def)
			var pass_ok: bool = (not is_dmg) or mob_frac >= PRESENCE_MOB or boss_frac >= PRESENCE_BOSS
			ok(pass_ok, "存在感:%s t%d @第%d關 —— 對小怪 %.1f%%、對 boss %.1f%%,兩個門檻都過唔到"
				% [def.mech, t, lvl, mob_frac * 100, boss_frac * 100])
			lines.append("%-12s %-6s %8d %7.1f%% %7.1f%% %s" % [
				def.mech, "t%d" % t, lvl, mob_frac * 100, boss_frac * 100,
				("OK" if pass_ok else "低") if is_dmg else "—(輔助/控場,用相對值)"])

## 呢款魔法係咪靠傷害做嘢。輔助 / 控場型唔用傷害門檻 —— 佢哋嘅效果本身就係
## 相對值(減速 %、減回復 %、加攻 %),唔會俾關卡成長溝淡,所以佢哋嘅「存在感」
## 由需求 1 / 2 嗰兩條斷言守,唔係由呢度守。
func _is_damage_spell(def: Dictionary) -> bool:
	return String(def.mech) in ["meteor", "stormbolt", "miasma", "quake",
		"firewall", "smite", "blackhole"]

## 一次施放對一個 `hp` 血嘅目標打幾多。DoT 類計成個持續時間嘅總量。
func _cast_damage(def: Dictionary, s: Dictionary, hp: float, is_boss: bool) -> float:
	var flat: float = float(s.get("dmg", 0.0)) + float(s.get("dmgpct", 0.0)) * hp
	match String(def.mech):
		"meteor", "stormbolt":
			return flat
		"smite":
			return flat * (1.0 + (float(s.get("bossmult", 0.0)) if is_boss else 0.0))
		"quake":
			if is_boss:
				return float(s.get("bossdmg", 0.0)) + float(s.get("bosspct", 0.0)) * hp
			return hp * float(s.get("pct", 0.0))
		"miasma", "firewall", "blackhole":
			var dps: float = float(s.get("dps", 0.0)) + float(s.get("dpspct", 0.0)) * hp
			return dps * float(s.get("dur", 0.0))
	return 0.0
