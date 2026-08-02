extends Node
## 由 GameData 直接 dump 出完整嘅 105 項 tier 表(35 個項目 x 3 個 tier),
## 兩種語言,markdown 表格,寫入 build/tier_table.md。
##
## 點解要一個工具而唔係手寫一份表落報告度:一份手寫嘅表由簽字嗰一刻就開始
## 同程式碼分家。呢個 dump 讀嘅係遊戲真正用緊嗰兩個字典同真正嘅 tr(),
## 所以「報告寫住嘅嘢」同「玩家見到嘅嘢」講唔埋呢件事係冇可能發生嘅。
##
##   godot --headless --path . res://tools/dump_tiers.tscn

const OUT := "res://build/tier_table.md"

func _ready() -> void:
	var lines := PackedStringArray()
	lines.append("# 進化 tier 表 — 35 個項目 x 3 階 = 105 項")
	lines.append("")
	lines.append("由 `tools/dump_tiers.gd` 讀 `GameData.TOWER_TIERS` / `SPELL_TIERS` 產生。")
	lines.append("塔倍率:tier 1 = x%.0f、tier 2 = x%.1f、tier 3 = x%.0f(只打落每秒輸出類 stat)。"
		% [GameData.tier_power(1), GameData.tier_power(2), GameData.tier_power(3)])
	lines.append("魔法倍率:tier 1 = x%.0f、tier 2 = x%.1f、tier 3 = x%.0f。魔法只得三條軸,"
		% [GameData.tier_power(1, false), GameData.tier_power(2, false),
		GameData.tier_power(3, false)]
		+ "課滿只係基礎值嘅五倍左右,所以佢哋要一個細啲嘅逐階倍率先唔會斷層 —— 見 GameData.TIER_STEP_SPELL。")
	lines.append("進化費:塔 %d / %d 魔晶,魔法 %d / %d 魔晶。" % [
		GameData.EVOLVE_COST_TOWER[2], GameData.EVOLVE_COST_TOWER[3],
		GameData.EVOLVE_COST_SPELL[2], GameData.EVOLVE_COST_SPELL[3]])
	lines.append("")
	_section(lines, "塔 (20 x 3 = 60)", GameData.TOWERS, true)
	_section(lines, "魔法 (15 x 3 = 45)", GameData.SPELLS, false)
	lines.append("")
	lines.append("**合共 %d 項。**" % _count())
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	if f == null:
		push_error("寫唔到 " + OUT)
		get_tree().quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("TIERDUMP wrote %s (%d items)" % [OUT, _count()])
	get_tree().quit(0)

func _count() -> int:
	return (GameData.TOWERS.size() + GameData.SPELLS.size()) * GameData.MAX_TIER

func _section(lines: PackedStringArray, title: String, defs: Array, is_tower: bool) -> void:
	lines.append("## " + title)
	lines.append("")
	lines.append("| # | 階 | 繁中 | English | 新機制 (繁中) | New mechanic (EN) |")
	lines.append("|---|---|---|---|---|---|")
	for d in defs:
		for tier in range(1, GameData.MAX_TIER + 1):
			var nk: String = GameData.tier_name(d, is_tower, tier)
			var mk: String = GameData.tier_mech_key(d, is_tower, tier)
			lines.append("| %d | T%d | %s | %s | %s | %s |" % [
				int(d.id), tier, _tr(nk, "zh_TW"), _tr(nk, "en"),
				"— (基礎形態)" if mk == "" else _tr(mk, "zh_TW"),
				"— (base form)" if mk == "" else _tr(mk, "en")])
	lines.append("")

## 逐格切換 locale 而唔係跑兩次:一次過出一張雙語表,兩欄一定係同一行資料,
## 唔會出現「中文表同英文表對唔上」呢種只有讀者先發現到嘅錯位。
func _tr(key: String, locale: String) -> String:
	if key == "":
		return ""
	TranslationServer.set_locale(locale)
	return tr(key).replace("|", "\\|")
