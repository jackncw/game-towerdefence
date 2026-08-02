extends Node
## 三階曲線嘅量度工具。答一條問題:**進化係一個躍升定一個斷層?**
##
##   godot --headless --path . res://tools/tier_curve.tscn
##
## 設計目標(第十一輪 D):
##   tier N 滿課  <  tier N+1 基礎  ≈  tier N 滿課 x 1.15
## 即係話進化嗰一下要明顯強過你之前課到盡嘅嘢,但唔可以強到令新開嘅十五級
## 變成裝飾 —— 「進化之後仲有嘢追」呢句話喺數字上面就係「tier N+1 滿課
## 遠高過 tier N+1 基礎」。
##
## 呢個比例由兩樣嘢決定,而只有其中一樣係我哋揀嘅:
##   R      = 一件嘢**六條軸課滿**之後係佢自己基礎值嘅幾多倍(由 ups 表決定)
##   TIER   = GameData.TIER_POWER 嘅逐階倍率(我哋揀)
## tier N+1 基礎 / tier N 滿課 = TIER / R。所以 TIER 應該 = 1.15 x R。
##
## R 逐座塔都唔同(10 到 13 之間),所以呢個工具印出成個分佈,而 TIER_POWER
## 跟**中位數**行 —— 一個倍率服侍二十座塔,中位數係唯一一個唔會偏袒任何一
## 座嘅選法。

const TARGET_JUMP := 1.15
const OUT := "res://build/tier_curve.md"

## 每件嘢嘅「輸出」點量。攻擊塔 = 每秒傷害;冇傷害嘅塔各自有自己嗰個
## 「每秒產出乜」。逐座寫明,唔靠猜 —— 一個猜錯咗嘅指標會令下面成張表
## 講一個唔存在嘅故事。
func _output(def: Dictionary, s: Dictionary, is_tower: bool) -> float:
	if not is_tower:
		# 魔法:傷害型用 dmg / dps,其餘用佢自己嗰條被 tier 放大嘅軸。
		# 冰凍新星 / 時間扭曲 / 戰吼 / 龍捲風 / 磁暴 一條跟階嘅軸都冇(佢哋賣
		# 嘅係時間同位移,唔係數值),所以佢哋唔入 R 嘅統計 —— 返 0 = 唔計。
		# 舊版返 1.0,而嗰五個 1.00 直接將中位數由 4.9 拉到 6.0,再由中位數
		# 推出嚟嘅逐階倍率就錯足兩成。
		for k in ["dmg", "dps", "gold", "bossdmg", "hp", "block"]:
			if float(s.get(k, 0.0)) > 0.0:
				return float(s[k])
		return 0.0
	match String(def.mech):
		"alchemy":
			return float(s.get("gold", 0.0)) * float(s.get("rate", 0.0))
		"slowfield":
			return float(s.get("pulse", 0.0)) * float(s.get("pulserate", 0.0))
		"curse":
			# 詛咒塔零輸出,佢賣嘅係放大率 —— 而放大率唔跟 tier 走。用掉金加成
			# (goldbonus 都唔跟)…即係話呢座塔根本冇一個跟 tier 嘅輸出指標,
			# 所以佢唔入 R 嘅統計。返 0 = 「唔計」。
			return 0.0
		"barracks":
			return float(s.get("dmg", 0.0)) * float(s.get("rate", 0.0)) * float(s.get("count", 1.0))
		"thorn", "magnet":
			return maxf(float(s.get("dmg", 0.0)), float(s.get("pulse", 0.0))) \
				* float(s.get("rate", 1.0))
		_:
			return float(s.get("dmg", 0.0)) * float(s.get("rate", 0.0))

func _levels(n: int, lv: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(lv)
	return a

func _ready() -> void:
	var lines := PackedStringArray()
	lines.append("# 三階曲線量度 (tools/tier_curve.gd)")
	lines.append("")
	lines.append("逐階倍率:塔 x%.2f、魔法 x%.2f。設計目標 tier N+1 基礎 / tier N 滿課 = %.2f"
		% [GameData.TIER_STEP_TOWER, GameData.TIER_STEP_SPELL, TARGET_JUMP])
	lines.append("")
	var ratios: Dictionary = {"塔": [], "魔法": []}
	for pair in [["塔", GameData.TOWERS, true], ["魔法", GameData.SPELLS, false]]:
		lines.append("## %s" % pair[0])
		lines.append("")
		lines.append("| # | 名 | R(滿課/基礎) | T1 基礎 | T1 滿課 | T2 基礎 | T2/T1滿 | T2 滿課 | T3 基礎 | T3/T2滿 | T3 滿課 |")
		lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
		for def in (pair[1] as Array):
			var n: int = def.ups.size()
			var zero := _levels(n, 0)
			var full := _levels(n, GameData.MAX_UP_LV)
			var v: Array = []
			for t in range(1, GameData.MAX_TIER + 1):
				v.append(_output(def, GameData.effective_stats(def, zero, t), pair[2]))
				v.append(_output(def, GameData.effective_stats(def, full, t), pair[2]))
			if v[0] <= 0.0:
				lines.append("| %d | %s | — | (冇跟階嘅輸出指標) | | | | | | | |"
					% [int(def.id), tr(def.name)])
				continue
			var R: float = v[1] / v[0]
			(ratios[pair[0]] as Array).append(R)
			lines.append("| %d | %s | %.2f | %.1f | %.1f | %.1f | **%.2f** | %.1f | %.1f | **%.2f** | %.1f |"
				% [int(def.id), tr(def.name), R,
				v[0], v[1], v[2], v[2] / v[1], v[3], v[4], v[4] / v[3], v[5]])
		lines.append("")
	lines.append("## 總結")
	lines.append("")
	lines.append("| 類別 | 件數 | R 最低 | R 中位 | R 最高 | 目標逐階倍率 (1.15 x 中位) | 現行 | 實際跳幅 |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for kind in ["塔", "魔法"]:
		var arr: Array = ratios[kind]
		if arr.is_empty():
			continue
		arr.sort()
		var med: float = _median(arr)
		var cur: float = GameData.tier_power(2, kind == "塔")
		lines.append("| %s | %d | %.2f | %.2f | %.2f | **%.2f** | %.2f | **%.2f** |"
			% [kind, arr.size(), arr[0], med, arr[-1],
			TARGET_JUMP * med, cur, cur / med])
		print("TIERCURVE %s: n=%d R min=%.2f med=%.2f max=%.2f -> 目標逐階倍率 %.2f (現行 %.2f, 跳幅 %.2f)"
			% [kind, arr.size(), arr[0], med, arr[-1], TARGET_JUMP * med, cur, cur / med])
	lines.append("")
	lines.append("跳幅 = tier N+1 基礎 / tier N 滿課。目標 %.2f。" % TARGET_JUMP)
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
		print("TIERCURVE wrote %s" % OUT)
	get_tree().quit(0)

## 中位數。偶數就取中間兩個嘅平均 —— 二十座塔入面「第十座」同「第十一座」
## 邊個做中位,唔應該由陣列長度嘅奇偶決定。
func _median(sorted_arr: Array) -> float:
	var n: int = sorted_arr.size()
	if n % 2 == 1:
		return float(sorted_arr[n / 2])
	return 0.5 * (float(sorted_arr[n / 2 - 1]) + float(sorted_arr[n / 2]))
