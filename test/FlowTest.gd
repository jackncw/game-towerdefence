extends Node
## End-to-end flow test — the acceptance walk, headless and asserted:
##   主選單 → 第 1 關通關 → 結算 → 商店買塔 → 升級介面買升級 → 輸一關 → 失敗畫面
##   → 怪物圖鑑 → 設定 → 選關
## Every screen is really instantiated and really built; every transition asserts
## on game state, not just "it did not crash". Any GDScript error during the run
## shows up in the log and fails the harness's error grep.
##
## Run: godot --headless --path . res://test/FlowTest.tscn
## Backs up and restores the real save.json.

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func():
		print("FLOW: TIMEOUT"); get_tree().quit(1))
	_backup_save()
	Flow.nav_enabled = false      # this harness owns navigation
	get_tree().paused = true
	Meta.reset_save()
	await _walk()
	get_tree().paused = false
	Flow.nav_enabled = true
	_restore_save()
	print("FLOW %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _walk() -> void:
	# --- 1. 主選單 ---------------------------------------------------------
	var menu = await _screen("res://scenes/MainMenu.tscn")
	_check(Meta.next_level() == 1, "全新存檔:主選單指向第 1 關")
	_check_no_dev_screens(menu)
	_check_export_excludes()
	await _drop(menu)

	# --- 2. 第 1 關,打到通關 ------------------------------------------------
	var b = await _battle(1)
	_check(b.gold == GameData.level_config(1).start_gold,
		"開場金幣 = 關卡設定 (%d)" % b.gold)
	b.gold = 9000
	var placed := 0
	for spot in _spots(b):
		if placed >= 14:
			break
		if b.place_tower(1 if placed % 3 else 7, spot):
			placed += 1
	_check(placed >= 10, "放到 %d 座塔" % placed)
	b.elapsed = b.boss_time + 0.1        # boss 即刻出場
	var t := 0.0
	while not b.ended and t < 200.0:
		_step(b, 1.0 / 30.0)
		t += 1.0 / 30.0
	_check(b.ended and Flow.last_result.get("win", false),
		"第 1 關通關 (用時 %.0fs, 擊殺 %d)" % [t, b.kills])
	_check(Meta.is_cleared(1) and Meta.highest_level == 1, "通關紀錄寫入 Meta")
	var crystals_after_win: int = Meta.crystals
	_check(crystals_after_win > 0, "通關派魔晶 (%d)" % crystals_after_win)
	await _drop(b)

	# --- 3. 結算畫面 -------------------------------------------------------
	var res = await _screen("res://scenes/Result.tscn")
	_check(int(Flow.last_result.get("first", 0)) > 0, "首次通關獎勵有派")
	await _drop(res)

	# --- 4. 商店:買一座塔 --------------------------------------------------
	Meta.crystals = 500
	var shop = await _screen("res://scenes/Shop.tscn")
	var owned0: int = Meta.unlocked_towers.size()
	var c0: int = Meta.crystals
	_check(Meta.unlock_tower(4), "商店解鎖火球塔")
	_check(Meta.unlocked_towers.size() == owned0 + 1, "解鎖後塔數 +1")
	_check(Meta.crystals == c0 - int(GameData.tower_by_id(4).unlock),
		"魔晶扣咗解鎖價 (%d -> %d)" % [c0, Meta.crystals])
	shop._refresh_all()                  # the real post-purchase UI refresh
	await _drop(shop)

	# --- 5. 升級介面:買一級升級 ---------------------------------------------
	var up = await _screen("res://scenes/Upgrade.tscn")
	up.sel_type = "tower"
	up.sel_id = 1
	up._rebuild()
	await _idle(3)
	var lv0: int = Meta.tower_levels(1)[0]
	var cost: int = Meta.tower_up_cost(1, 0)
	var c1: int = Meta.crystals
	up._try_buy(0, cost, up)
	await _idle(3)
	_check(Meta.tower_levels(1)[0] == lv0 + 1, "箭塔攻擊升到 lv%d" % Meta.tower_levels(1)[0])
	_check(Meta.crystals == c1 - cost, "魔晶扣咗升級價 (%d -> %d)" % [c1, Meta.crystals])
	# and the upgraded value really reaches the battlefield
	_check(float(Meta.tower_stats(1).dmg) > float(GameData.tower_by_id(1).stats.dmg),
		"升級後箭塔攻擊力真係高咗 (%.1f)" % Meta.tower_stats(1).dmg)
	await _drop(up)

	# --- 6. 輸一關(唔放塔) --------------------------------------------------
	var b2 = await _battle(2)
	var c2: int = Meta.crystals
	var t2 := 0.0
	while not b2.ended and t2 < 200.0:
		_step(b2, 1.0 / 30.0)
		t2 += 1.0 / 30.0
	_check(b2.ended and not Flow.last_result.get("win", true),
		"第 2 關唔放塔 -> 失守 (用時 %.0fs)" % t2)
	_check(not Meta.is_cleared(2), "輸咗唔會標記通關")
	_check(Meta.crystals >= c2, "失敗按進度派魔晶 (%d -> %d)" % [c2, Meta.crystals])
	await _drop(b2)

	# --- 7. 失敗畫面 -------------------------------------------------------
	var fail = await _screen("res://scenes/Fail.tscn")
	await _drop(fail)

	# --- 8. 圖鑑:打過兩關,應該見過嘢 ----------------------------------------
	Meta.flush_pending_save()
	_check(not Meta.seen.is_empty(), "圖鑑記錄咗 %d 種目擊" % Meta.seen.size())
	var bes = await _screen("res://scenes/Bestiary.tscn")
	await _drop(bes)

	# --- 9. 設定 + 選關 ----------------------------------------------------
	var st = await _screen("res://scenes/Settings.tscn")
	await _drop(st)
	var sel = await _screen("res://scenes/LevelSelect.tscn")
	await _drop(sel)

	# --- 10. 存檔真係寫咗落去 ------------------------------------------------
	var disk := FileAccess.get_file_as_string(Meta.SAVE_PATH)
	var d = JSON.parse_string(disk)
	_check(typeof(d) == TYPE_DICTIONARY, "save.json 讀得返")
	if typeof(d) == TYPE_DICTIONARY:
		_check(int(d.get("highest_level", 0)) == 1, "存檔記住最高通關 = 1")
		_check(int(d.get("crystals", -1)) == Meta.crystals, "存檔魔晶同記憶體一致")
		_check((d.get("tower_up", {}).get("1", [0]))[0] == 1, "存檔記住箭塔升級")

# ---------------------------------------------------------------------------
## 出貨版唔可以有路去開發畫面。
##
## 兩邊都要查,因為佢哋擋唔同嘅嘢:
##   * **主選單冇入口** —— 玩家撳唔到。一粒掣好易喺重排選單嗰陣「順手」加返。
##   * **export 唔打包** —— 就算有人加返一粒掣,出貨版都冇嗰個檔。
## 淨係做第一樣,下一個改主選單嘅人可以靜靜咁還原;淨係做第二樣,還原完就
## 變成一個載入失敗嘅掣。
##
## 美術畫廊本身冇刪:tools/art_export.gd 同 SoakTest 由原始碼開得到佢。
const DEV_ONLY_SCENES := ["res://scenes/Gallery.tscn"]
## 開發畫面喺出貨腳本入面嘅名。`Flow.GALLERY` 係嗰個常數,而場景路徑本身
## 係任何人繞過個常數嘅寫法。
const DEV_ONLY_TOKENS := ["Flow.GALLERY", "scenes/Gallery.tscn"]
## 常數自己嘅宣告喺 Flow.gd,佢一定要提到個名。
const DEV_TOKEN_HOME := "Flow.gd"

## 第一版係去撳主選單每一粒掣,睇吓有冇切場景。佢**假綠**:掣接住嘅係
## lambda,而 `Flow.goto()` 喺 `nav_enabled = false` 之下(即係呢個 harness)
## 未行到麵包屑嗰行就已經 return,所以量到零條路,而「冇路去畫廊」就係
## 喺零條路入面成立 —— 一條乜都證明唔到嘅斷言。
##
## 改為問 source:出貨嗰批腳本(scripts/**)入面,冇一句**程式碼**提到開發
## 畫面。註解照計唔中 —— 上面 MainMenu.gd 嗰段解釋點解拎走佢,而嗰段要留得低。
func _check_no_dev_screens(_menu: Node) -> void:
	var lines := SourceScan.code_lines(["res://scripts"], [DEV_TOKEN_HOME])
	_check(lines.size() > 400, "真係掃過出貨腳本 (%d 行程式碼)" % lines.size())
	for token in DEV_ONLY_TOKENS:
		var hits: Array = []
		for l in lines:
			if String(l.code).contains(token):
				hits.append("%s:%d" % [String(l.file).get_file(), int(l.line_no)])
		_check(hits.is_empty(), "出貨腳本冇提 %s (%s)" % [token, hits.slice(0, 4)])

## 出貨嗰份 pack 有冇打包開發畫面 —— 問 export_presets.cfg,唔係問檔案系統。
func _check_export_excludes() -> void:
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		_check(false, "讀到 export_presets.cfg")
		return
	var checked := 0
	for sect in cfg.get_sections():
		if sect.ends_with(".options"):
			continue
		var preset_name := String(cfg.get_value(sect, "name", ""))
		var ex := String(cfg.get_value(sect, "exclude_filter", ""))
		if preset_name == "":
			continue
		checked += 1
		for dev in DEV_ONLY_SCENES:
			_check(ex.contains(dev.trim_prefix("res://")),
				"[%s] exclude_filter 隔走 %s" % [preset_name, dev])
	_check(checked >= 2, "掃過每一個 export preset (%d 個)" % checked)

func _screen(path: String):
	var n = load(path).instantiate()
	n.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(n)
	await _idle(3)
	_check(n.get_child_count() > 0, "%s 建到畫面 (%d 個子節點)"
		% [path.get_file(), n.get_child_count()])
	return n

func _battle(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await _idle(1)
	return b

func _drop(n) -> void:
	n.queue_free()
	await _idle(1)
	get_tree().paused = true

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

func _spots(b) -> Array:
	var out: Array = []
	for gy in range(3, 21):
		for gx in range(1, 15):
			var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
			if b.can_place(p):
				out.append(p)
	return out

func _check(ok: bool, label: String) -> void:
	if not ok:
		fails += 1
	print("FLOW %s: %s" % ["ok" if ok else "FAIL", label])

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
