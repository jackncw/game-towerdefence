extends Node
## 手繪資產嘅 texture_filter 守門。
##   godot --headless --path . test/ArtFilterTest.tscn
##
## 點解要有呢個 test:第十九 / 二十輪換完手繪美術之後,「呢張圖行 NEAREST
## 定 LINEAR」由「全場一律 NEAREST」變成「睇嗰張圖係邊一代」。而揀錯咗嘅
## 症狀係**畫面起格** —— 冇 error、冇 warning、冇 crash,只有肉眼睇得出。
## 第二十輪就係咁樣漏低咗圖鑑兩個怪物頭像位同建塔 ghost,直到收官輪先執返。
##
## 規則:凡係由 `Assets.monster/monster_boss/tower/spell` 出嘅圖(= 摳圖摳返嚟
## 嗰三批手繪圖)一律要 LINEAR。**唔可以用「源圖大過 48px」做判斷** —— 升級
## 介面嗰啲元素背板同平台係 360px 嘅程序像素圖,佢哋照舊 NEAREST 先啱。
## 認圖用嘅係 instance 身份:`Assets._load()` 有 path cache,同一個路徑永遠
## 返同一個 Texture2D instance,所以「掃出嚟嗰張」同「Assets 俾嘅嗰張」係
## 同一個物件。
##
## 掃嘅係**真正砌好嘅場景**,唔係 source code —— 呼叫端傳唔傳 `smooth` 只係
## 手段,呢度問嘅係結果。

var _hand_drawn: Dictionary = {}       # instance_id -> 名
var fails: Array[String] = []
var checked := 0

func _ok(what: String, cond: bool) -> void:
	checked += 1
	if not cond:
		fails.append(what)

func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): get_tree().quit(1))
	Flow.nav_enabled = false
	Meta.reset_save()
	# 全解鎖 + 全部見過:剪影卡照樣擺 TextureRect,但未解鎖嘅塔 / 魔法卡唔會,
	# 掃唔到就等於冇掃。
	Meta.highest_level = 40
	Meta.crystals = 999999
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	for f in GameData.FAMILY_ORDER:
		for lv in range(1, 6):
			Meta.seen["%s_%d" % [f, lv]] = true
		Meta.seen["%s_boss" % f] = true
	_build_index()

	await _scan_bestiary()
	await _scan_upgrade()
	await _scan_shop()
	await _scan_battle_hud()
	_case_placer()
	_ok("掃到起碼 60 個手繪 TextureRect(掃唔到就係呢個 test 自己壞咗)",
		checked >= 60)

	if fails.is_empty():
		print("ArtFilterTest: PASS (%d 項)" % checked)
		get_tree().quit(0)
		return
	for f in fails:
		print("  FAIL " + f)
	print("ArtFilterTest: FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

func _build_index() -> void:
	for f in GameData.FAMILY_ORDER:
		for lv in range(1, 6):
			_mark(Assets.monster(f, lv), "怪物 %s lv%d" % [f, lv])
		_mark(Assets.monster_boss(f), "怪物 %s boss" % f)
	for id in range(1, 21):
		for t in range(1, 4):
			_mark(Assets.tower(id, t), "塔 %d t%d" % [id, t])
	for id in range(1, 16):
		for t in range(1, 4):
			_mark(Assets.spell(id, t), "魔法 %d t%d" % [id, t])

func _mark(tex: Texture2D, name: String) -> void:
	if tex != null:
		_hand_drawn[tex.get_instance_id()] = name

func _scan_bestiary() -> void:
	for tab in ["monster", "tower", "spell"]:
		var sc = load("res://scenes/Bestiary.tscn").instantiate()
		add_child(sc)
		await get_tree().process_frame
		sc._switch_tab(tab)
		await get_tree().process_frame
		await get_tree().process_frame
		_walk(sc, "圖鑑/" + tab)
		# 怪物頁仲要逐個 slot 掃 —— boss 大圖(_detail_panel)同格仔頭像
		# (_slot_button)走兩條唔同嘅路,只掃預設 slot 會漏咗其中一條。
		if tab == "monster":
			for slot in [0, 5]:
				sc.sel_slot = slot
				sc._rebuild()
				await get_tree().process_frame
				_walk(sc, "圖鑑/怪物/slot%d" % slot)
		sc.queue_free()
		await get_tree().process_frame

func _scan_upgrade() -> void:
	for kind in [["tower", 18], ["spell", 11]]:
		var sc = load("res://scenes/Upgrade.tscn").instantiate()
		add_child(sc)
		await get_tree().process_frame
		sc.sel_type = String(kind[0])
		sc.sel_id = int(kind[1])
		sc._rebuild()
		await get_tree().process_frame
		_walk(sc, "升級/" + String(kind[0]))
		sc.queue_free()
		await get_tree().process_frame

func _scan_shop() -> void:
	var sc = load("res://scenes/Shop.tscn").instantiate()
	add_child(sc)
	await get_tree().process_frame
	await get_tree().process_frame
	_walk(sc, "商店")
	sc.queue_free()
	await get_tree().process_frame

## 戰鬥 HUD:建塔卡片列 + 魔法卡片列 + 選中塔嗰塊詳情。
func _scan_battle_hud() -> void:
	Flow.selected_level = 1
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	await get_tree().process_frame
	_walk(b, "戰鬥HUD")
	b.queue_free()
	await get_tree().process_frame

## 建塔 ghost 唔係 TextureRect,佢係 `Battle._Placer` 度 draw_texture_rect
## 畫出嚟。所以佢躲得過上面成個掃描 —— 要獨立驗。
func _case_placer() -> void:
	Flow.selected_level = 1
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	_ok("建塔 ghost(_Placer)要 LINEAR:佢畫 128px 手繪塔圖 @0.6875",
		b._placer.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
	b.queue_free()

func _walk(node: Node, where: String) -> void:
	if node is TextureRect:
		var tr := node as TextureRect
		if tr.texture != null and _hand_drawn.has(tr.texture.get_instance_id()):
			_ok("%s 嘅「%s」行緊 texture_filter=%d,手繪圖一定要 LINEAR(=%d)" % [
				where, String(_hand_drawn[tr.texture.get_instance_id()]),
				tr.texture_filter, CanvasItem.TEXTURE_FILTER_LINEAR],
				tr.texture_filter == CanvasItem.TEXTURE_FILTER_LINEAR)
	for c in node.get_children():
		_walk(c, where)
