extends Node
## 診斷:71-99 段嘅逐關結構(第 24 輪 Part E)。
## 印出每關嘅 boss 家族 / level_wave_norm / wave_scale / path_factor,
## 再用唔同 BOSS_PHASE_WEIGHT 重算 level_wave_norm 做對照。

func _ready() -> void:
	var lo := 61
	var hi := 99
	print("lv  bossfam   path   lwn    wave_scale  diff      fams")
	for n in range(lo, hi + 1):
		var fams: Array = GameData.level_families(n)
		print("%3d %-9s %.3f  %.3f  %10.1f  %9.0f  %s" % [
			n, GameData.FAMILY_ORDER[(n - 1) % 10], GameData.path_factor(n),
			GameData.level_wave_norm(n), GameData.wave_scale(n),
			GameData.difficulty(n), ",".join(fams)])
	# 對照:唔同 boss 期權重之下嘅 lwn(自己重算,唔改常數)
	print("")
	print("=== level_wave_norm @ 唔同 BOSS_PHASE_WEIGHT(band = 第 71-99 關嘅等級帶)===")
	print("lv  bossfam    w=0.50  w=0.35  w=0.25  w=0.00")
	for n in range(lo, hi + 1):
		var line := "%3d %-9s " % [n, GameData.FAMILY_ORDER[(n - 1) % 10]]
		for w in [0.5, 0.35, 0.25, 0.0]:
			line += "  %.3f" % _lwn_at(n, float(w))
		print(line)
	get_tree().quit()

## level_wave_norm 嘅複製品,但 BOSS_PHASE_WEIGHT 由外面畀 —— 唔郁真常數,
## 所以呢個工具唔會影響任何量度。
func _lwn_at(n: int, w: float) -> float:
	var band: int = int(maxi(1, n) - 1) / GameData.LVL_BAND_EVERY
	var tbl: Array = []
	var s := 0.0
	for r in GameData.GOLD_ROT:
		var y: float = _yield_at(band, r, w)
		tbl.append(y)
		s += y
	var mean: float = maxf(0.001, s / float(GameData.GOLD_ROT))
	return float(tbl[(maxi(1, n) - 1) % GameData.GOLD_ROT]) / mean

func _yield_at(band: int, r: int, w: float) -> float:
	var base_i: int = r % 10
	var fams: Array = [GameData.FAMILY_ORDER[base_i], GameData.FAMILY_ORDER[(base_i + 3) % 10]]
	if r % 2 == 1:
		fams.append(GameData.FAMILY_ORDER[(base_i + 6) % 10])
	var a := 0.0
	for f in fams:
		a += GameData._fam_pressure(String(f))
	a /= float(fams.size())
	var y: float = GameData.WAVE_PHASE_SPAWNS * a
	var boss_fam: String = GameData.FAMILY_ORDER[base_i]
	var p: Dictionary = GameData.boss_spawn_profile(boss_fam)
	var pool: Array = p.get("pool", fams)
	var ab := 0.0
	for f in pool:
		ab += GameData._fam_pressure(String(f))
	ab = ab / float(pool.size()) * GameData._lvl_bonus_hp(band, int(p.get("lvl_bonus", 0)))
	y += w * GameData.BOSS_PHASE_SECONDS * float(p.get("rate", GameData.BOSS_SPAWN_BASE_RATE)) / 0.45 * ab
	var bu: Dictionary = p.get("burst", {})
	if not bu.is_empty():
		y += w * GameData.BOSS_PHASE_SECONDS / maxf(1.0, float(bu["interval"])) \
			* (float(bu["count_min"]) + float(bu["count_max"])) * 0.5 \
			* GameData._fam_pressure(String(bu.get("fam", boss_fam)))
	return y
