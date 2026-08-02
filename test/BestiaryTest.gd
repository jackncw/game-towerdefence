extends Node
## 圖鑑。三個分頁 —— 怪物 / 塔 / 魔法。
##   godot --headless --path . test/BestiaryTest.tscn
##
## 怪物頁嗰半邊問嘅係「見過嘅嘢有冇記低同埋過唔過得到重啟」;塔同魔法頁
## (第十一輪加)問嘅係「三十五件嘢每一件都砌得出一張卡,而卡上面每一個
## 狀態都揀啱咗」——
##   未喺商店解鎖  -> 剪影 + 解鎖價,冇數值
##   已解鎖未進化  -> 全彩 + 實際數值 + 六條軸,而 tier 2/3 係剪影
##   已進化        -> 到咗嗰階全彩
## 呢三個狀態舊圖鑑一律用「???」,而「???」答唔到「我要做啲乜」。

var pass_n := 0
var fail_n := 0

func _ok(label: String, cond: bool, detail := "") -> void:
	if cond:
		pass_n += 1
	else:
		fail_n += 1
		print("BTEST FAIL %s — %s" % [label, detail])

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func(): get_tree().quit(1))
	Flow.nav_enabled = false
	Meta.reset_save()

	await _case_sightings()
	await _case_monster_page()
	await _case_catalogue()
	await _case_jump()

	print("BTEST: %d passed, %d failed" % [pass_n, fail_n])
	get_tree().quit(0 if fail_n == 0 else 1)

# ---------------------------------------------------------------------------
func _case_sightings() -> void:
	_ok("A 新存檔冇任何目擊", Meta.seen.is_empty())
	Meta.mark_seen("goblin", 1, false)
	Meta.mark_seen("goblin", 2, false)
	Meta.mark_seen("goblin", 0, true)
	Meta.mark_seen("wolf", 3, false)
	_ok("A 記得住見過嘅", Meta.has_seen("goblin", 1, false) and Meta.has_seen("goblin", 0, true)
		and Meta.has_seen("wolf", 3, false))
	_ok("A 冇見過嘅唔會當見過", not Meta.has_seen("slime", 1, false))
	_ok("A family_any_seen", Meta.family_any_seen("goblin") and not Meta.family_any_seen("slime"))
	# 目擊係批次寫嘅(mark_seen 唔再逐隻寫檔 —— 嗰個係波次中間嘅磁碟停頓),
	# 所以要同 Battle._exit_tree 一樣先 flush 再讀返。
	Meta.flush_pending_save()
	Meta.seen = {}
	Meta.load_game()
	_ok("A 重啟之後仲喺度", Meta.has_seen("goblin", 1, false) and Meta.has_seen("wolf", 3, false))

func _case_monster_page() -> void:
	var scene = load("res://scenes/Bestiary.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	_ok("B 開喺第一個見過嘅族", scene.fam_idx == 0, "fam_idx=%d" % scene.fam_idx)
	_ok("B 預設分頁係怪物", scene.tab == "monster", scene.tab)
	scene._turn(1)
	await get_tree().process_frame
	scene.sel_slot = 5
	scene._rebuild()
	await get_tree().process_frame
	_ok("B 翻頁 + boss 詳情砌得返", scene.page_root.get_child_count() > 0)
	scene.queue_free()
	await get_tree().process_frame

## 三十五張卡,每一張都要喺三個擁有狀態底下砌得出。呢個 case 唔係睇樣,
## 係睇「有冇一張卡喺某個狀態底下會炸」—— 而一張卡入面有 tier 名、tier 機制、
## 剪影、實際數值同六條軸,全部都有各自嘅 null 路。
func _case_catalogue() -> void:
	# 一個「中途」存檔:啲嘢有啲買咗有啲冇,有一件已經進化。
	Meta.reset_save()
	Meta.unlocked_towers = [1, 2, 5, 13, 7]
	Meta.unlocked_spells = [1, 4]
	Meta.tower_tiers["1"] = 2
	Meta.spell_tiers["4"] = 3
	Meta.tower_up["1"] = [3, 15, 0, 0, 0, 0]
	for t in ["tower", "spell"]:
		var scene = load("res://scenes/Bestiary.tscn").instantiate()
		add_child(scene)
		await get_tree().process_frame
		scene._switch_tab(t)
		await get_tree().process_frame
		await get_tree().process_frame
		var cards := _cards(scene)
		var want: int = GameData.TOWERS.size() if t == "tower" else GameData.SPELLS.size()
		_ok("C [%s] 每件嘢一張卡" % t, cards.size() == want,
			"%d cards, want %d" % [cards.size(), want])
		_ok("C [%s] 翻頁箭嘴收起咗" % t, not (scene._pager[0] as Control).visible)
		# 未解鎖嘅唔可以有數值 —— 一張寫住 DPS 嘅未解鎖卡等於劇透兼講大話
		# (嗰個數係「如果你有嘅話」,而佢冇)。
		var labels_locked := _labels(cards[_index_of_unowned(t)])
		_ok("C [%s] 未解鎖卡有解鎖價" % t, _has_digits(labels_locked))
		_ok("C [%s] 未解鎖卡標住未解鎖" % t,
			_contains(labels_locked, tr("BESTIARY_NOT_OWNED")))
		scene.queue_free()
		await get_tree().process_frame
	# 進化過嘅嘢喺卡上面要叫返新名,唔係原名
	var sc2 = load("res://scenes/Bestiary.tscn").instantiate()
	add_child(sc2)
	await get_tree().process_frame
	sc2._switch_tab("tower")
	await get_tree().process_frame
	await get_tree().process_frame
	var t2name := tr(GameData.tier_name(GameData.tower_by_id(1), true, 2))
	_ok("C 進化過嘅塔用返新名", _contains(_labels(_cards(sc2)[0]), t2name), t2name)
	sc2.queue_free()
	await get_tree().process_frame

## 撳一張卡就落到升級介面嗰件嘢上面。呢個係圖鑑同升級之間唯一嘅接口,
## 而佢斷咗嘅話冇任何嘢會報錯 —— 玩家只係落到一個「錯咗嘅」升級介面。
func _case_jump() -> void:
	Flow.upgrade_focus = {"type": "tower", "id": 7}
	var up = load("res://scenes/Upgrade.tscn").instantiate()
	add_child(up)
	await get_tree().process_frame
	_ok("D 升級介面落喺圖鑑指定嗰座塔", up.sel_id == 7 and up.sel_type == "tower",
		"sel=%s#%d" % [up.sel_type, up.sel_id])
	_ok("D 意圖讀完即刻清走", Flow.upgrade_focus.is_empty())
	up.queue_free()
	await get_tree().process_frame
	# 一個未解鎖嘅 id 唔可以揀得中:升級介面淨係處理你有嘅嘢
	Flow.upgrade_focus = {"type": "tower", "id": 20}
	var up2 = load("res://scenes/Upgrade.tscn").instantiate()
	add_child(up2)
	await get_tree().process_frame
	_ok("D 未解鎖嘅唔會被揀中", up2.sel_id != 20, "sel_id=%d" % up2.sel_id)
	up2.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
func _cards(scene) -> Array:
	for c in scene.page_root.get_children():
		if c is ScrollContainer:
			for box in c.get_children():
				if box is VBoxContainer:
					return box.get_children()
	return []

func _index_of_unowned(kind: String) -> int:
	var defs: Array = GameData.TOWERS if kind == "tower" else GameData.SPELLS
	for i in defs.size():
		var id: int = defs[i].id
		var owned: bool = (Meta.is_tower_unlocked(id) if kind == "tower"
			else Meta.is_spell_unlocked(id))
		if not owned:
			return i
	return 0

func _labels(node: Node) -> Array:
	var out: Array = []
	if node == null:
		return out
	if node is Label:
		out.append((node as Label).text)
	for c in node.get_children():
		out += _labels(c)
	return out

func _contains(labels: Array, needle: String) -> bool:
	for l in labels:
		if String(l).findn(needle) >= 0:
			return true
	return false

func _has_digits(labels: Array) -> bool:
	for l in labels:
		for ch in String(l):
			if ch >= "0" and ch <= "9":
				return true
	return false
