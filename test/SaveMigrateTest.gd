extends Node
## 舊存檔遷移回歸(第十五輪加)。
##
## 呢一輪改咗曲線、換咗經濟模型、加咗合約關同第 100 關,但**存檔格式一個
## 欄位都冇改**。所以呢個測試要證明嘅唔係「遷移有冇行」,係一件更嚴格嘅事:
##
##   一份第十四輪寫低嘅存檔,喺第十五輪載入之後,每一項進度都同寫低嗰陣
##   一模一樣 —— 冇蒸發、冇被 clamp、冇被「新版預設值」蓋走。
##
## 點解要特登測:呢一輪加咗 `FINAL_LEVEL = 100` 同選關介面嘅封頂,而封頂
## 呢類改動最典型嘅 bug 就係順手 clamp 埋存檔入面嘅 highest_level。另外
## `TYPICAL_AXES` / 派彩曲線改咗會令 `typical_upgrade_cost()` 郁,而如果有
## 邊個地方用佢嚟推算存檔內容,舊檔就會被改寫。
##
## Run: godot --headless --path . res://test/SaveMigrateTest.tscn

var _fails: Array = []
var _n := 0
var _save_bytes := PackedByteArray()
var _had_save := false

## 一份第十四輪嘅存檔:打到第 40 關、六座塔、三個魔法、箭塔 tier 2、
## 隕石術 tier 2、快捷列排過、圖鑑見過嘢、語言揀咗英文。
const OLD_SAVE := {
	"crystals": 48213,
	"unlocked_towers": [1, 2, 5, 13, 7, 3],
	"unlocked_spells": [1, 2, 11],
	"tower_up": {"1": [15, 15, 15, 15, 15, 15], "2": [8, 6, 4, 0, 0, 0], "7": [3, 2, 1, 0, 0, 0]},
	"spell_up": {"1": [15, 15, 15], "2": [4, 3, 2]},
	"highest_level": 40,
	"settings": {"volume": 0.55, "volume_bgm": 0.8, "volume_sfx": 0.9,
		"muted": false, "locale": "en", "power_save": true},
	"seen": {"goblin_1": true, "goblin_boss": true, "wolf_3": true},
	"version": 2,
	"quick_slots": [7, 1, 2, 0, 5, 13],
	"tower_tiers": {"1": 2},
	"spell_tiers": {"1": 2},
}

func _ready() -> void:
	_had_save = FileAccess.file_exists(Meta.SAVE_PATH)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

	var cleared := {}
	for n in range(1, 41):
		cleared[str(n)] = true
	var old: Dictionary = OLD_SAVE.duplicate(true)
	old["cleared"] = cleared

	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(old, "\t"))
	f.close()

	Meta.load_game()
	Meta._migrate()

	# --- 資源同進度 ---------------------------------------------------------
	_ok("魔晶冇蒸發", Meta.crystals == 48213, "crystals=%d" % Meta.crystals)
	_ok("最高關數保持 40", Meta.highest_level == 40, "highest=%d" % Meta.highest_level)
	_ok("四十關通關記錄齊", Meta.cleared.size() == 40, "cleared=%d" % Meta.cleared.size())
	_ok("第 40 關仲係已通關", Meta.is_cleared(40), "is_cleared(40)=false")
	_ok("第 41 關仲未通關", not Meta.is_cleared(41), "is_cleared(41)=true")
	_ok("下一關 = 41", Meta.next_level() == 41, "next=%d" % Meta.next_level())

	# --- 解鎖 ---------------------------------------------------------------
	_ok("六座塔照解鎖", Meta.unlocked_towers.size() == 6, str(Meta.unlocked_towers))
	_ok("三個魔法照解鎖", Meta.unlocked_spells.size() == 3, str(Meta.unlocked_spells))
	for id in [1, 2, 5, 13, 7, 3]:
		_ok("塔 %d 仲喺度" % id, Meta.is_tower_unlocked(id), "唔見咗")

	# --- 升級軸同進化階 -----------------------------------------------------
	_ok("箭塔六軸全滿", Meta.tower_levels(1) == [15, 15, 15, 15, 15, 15], str(Meta.tower_levels(1)))
	_ok("加農塔軸保持", Meta.tower_levels(2).slice(0, 3) == [8, 6, 4], str(Meta.tower_levels(2)))
	_ok("箭塔仲係 tier 2", Meta.tower_tier(1) == 2, "tier=%d" % Meta.tower_tier(1))
	_ok("隕石術仲係 tier 2", Meta.spell_tier(1) == 2, "tier=%d" % Meta.spell_tier(1))
	_ok("隕石術三軸全滿", Meta.spell_levels(1) == [15, 15, 15], str(Meta.spell_levels(1)))

	# --- 設定 / 快捷列 / 圖鑑 -----------------------------------------------
	_ok("語言保持英文", Meta.current_locale() == "en", Meta.current_locale())
	_ok("音量保持", is_equal_approx(float(Meta.settings.get("volume", 0)), 0.55),
		str(Meta.settings.get("volume")))
	_ok("省電設定保持", bool(Meta.settings.get("power_save", false)), "power_save=false")
	_ok("快捷列保持", Meta.quick_slot_ids() == [7, 1, 2, 0, 5, 13], str(Meta.quick_slot_ids()))
	_ok("圖鑑記錄保持", Meta.has_seen("goblin", 0, true) and Meta.has_seen("wolf", 3, false),
		str(Meta.seen))

	# --- 新內容對舊檔嘅意義 -------------------------------------------------
	## 舊檔停喺第 40 關,而新內容(第 41-100 關、合約關、最終關)全部要
	## **接得上**:第 41 關要開得到,而 42(= 6x7)之後嘅合約關要標記得到。
	_ok("新關卡接得上(第 41 關可挑戰)", 41 <= Meta.highest_level + 1, "41 開唔到")
	_ok("第 42 關係合約關", GameData.is_contract_level(42), "42 唔係合約關")
	_ok("第 40 關唔係合約關", not GameData.is_contract_level(40), "40 變咗合約關")
	_ok("第 100 關係最終關", GameData.is_final_level(100), "100 唔係最終關")
	_ok("舊檔冇被寫入合約欄位", not Meta.to_dict().has("contracts"),
		"to_dict 多咗欄位")

	# --- 寫返出去再載入,唔准有嘢走樣 ---------------------------------------
	Meta.save_game()
	var c0: int = Meta.crystals
	var t0: Array = Meta.tower_levels(1).duplicate()
	Meta.load_game()
	_ok("來回一次魔晶唔變", Meta.crystals == c0, "%d vs %d" % [Meta.crystals, c0])
	_ok("來回一次升級軸唔變", Meta.tower_levels(1) == t0, str(Meta.tower_levels(1)))
	_ok("來回一次 tier 唔變", Meta.tower_tier(1) == 2, "tier=%d" % Meta.tower_tier(1))

	# 還原真存檔
	if _had_save:
		var g := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		g.store_buffer(_save_bytes)
		g.close()
	elif FileAccess.file_exists(Meta.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.SAVE_PATH))

	if _fails.is_empty():
		print("SAVEMIGRATE PASS %d 項" % _n)
		get_tree().quit(0)
	else:
		for x in _fails:
			print("SAVEMIGRATE FAIL " + x)
		print("SAVEMIGRATE FAIL fails=%d / %d" % [_fails.size(), _n])
		get_tree().quit(1)

func _ok(name: String, cond: bool, detail := "") -> void:
	_n += 1
	if not cond:
		_fails.append("%s — %s" % [name, detail])
