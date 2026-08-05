extends Node
## 合約關 UI 嘅截圖自查(第十七輪 v2)。
##
## 影六張:選關(合約關同最終關嘅標記)、入關說明窗、三選一卡片(低中高)、
## 揀完之後嘅 HUD badge、撳開嘅「本關合約」面板、第 100 關嘅十 boss 場面。
##
## 兩個 locale 各影一次 —— 英文闊過中文兩三倍,而合約卡上面全部都係長句
## (「簽下後總倍率 魔晶 x1.23 / 金幣 x1.10」),呢類字最容易爆框。
##
## 要 GPU,所以要 windowed 跑(Windows 個 GUI exe 會脫離 console,所以一定要
## 加 --log-file,再用 log 入面嘅 CONTRACT_SHOTS: DONE 做完成訊號):
##   Godot --path . tools/contract_shots.tscn --log-file build/cshots.log -- --locale=en

const VW := 1080
const VH := 1920

var OUTDIR := "res://qa/screenshots/round-17-contract/"
var sub: SubViewport
var done := false

func _ready() -> void:
	var suffix := "zh"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--locale="):
			var loc := a.substr(9)
			TranslationServer.set_locale(loc)
			suffix = "en" if loc.begins_with("en") else "zh"
	OUTDIR = OUTDIR.trim_suffix("/") + "-" + suffix + "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	print("CONTRACT_SHOTS: out=", OUTDIR)
	get_tree().create_timer(300.0).timeout.connect(func():
		if not done:
			push_warning("contract_shots timed out")
			get_tree().quit())

	# 一份「打到第 20 關」嘅存檔:合約關 7 / 14 解鎖咗,第 21 關可以挑戰
	Meta.highest_level = 20
	Meta.cleared = {}
	for n in range(1, 21):
		Meta.cleared[str(n)] = true
	Meta.crystals = 90000
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)

	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.transparent_bg = false
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame

	Flow.nav_enabled = false
	await _run()
	done = true
	print("CONTRACT_SHOTS: DONE")
	get_tree().quit()

func _run() -> void:
	# 1. 選關 —— 合約關(7 / 14)同最終關嘅標記
	await _shoot_scene("res://scenes/LevelSelect.tscn", "01_level_select")

	# 2-5. 合約關開場(v2):說明窗 -> 三選一(低中高各一)-> badge / 詳情面板
	var b = await _mount_battle(7)
	await _grab("02_contract_intro")
	# 撳「確定」:同 OK 掣做同一件事 —— 轉去卡片層
	b.hud._build_contract_panel(b.contract_offer)
	for i in 3:
		await get_tree().process_frame
	await _grab("03_contract_cards")
	# 揀中間嗰張(中風險)
	var offer: Array = b.contract_offer
	if offer.size() >= 2:
		b.choose_contract(int(offer[1]))
	for i in 4:
		await get_tree().process_frame
	await _grab("04_after_pick_hud")
	b.hud._toggle_contract_summary()
	for i in 3:
		await get_tree().process_frame
	await _grab("05_contract_status")
	b.hud.hide_contract()

	# 5. 結算畫面 —— 合約關贏同輸各一。
	#    直接砌 Flow.last_result 再掛畫面,同 SceneCheck 嘅 result#0 一樣做法:
	#    要驗嘅係「畫面點讀呢份結果」,唔係「點打到呢份結果」。
	Flow.last_result = {"win": true, "level": 21, "kills": 132,
		"crystals": 3820, "base": 1900, "first": 1920, "replay": false,
		"contract": true, "mult": 1.52, "contracts": [5]}
	await _shoot_scene("res://scenes/Result.tscn", "07_result_contract_win")
	Flow.last_result = {"win": false, "level": 21, "kills": 47,
		"crystals": 620, "progress": 0.52, "cap": 1180, "too_short": false,
		"boss_frac": 0.31, "time": 74.0, "boss_reached": true,
		"contract": true, "mult": 1.52, "contracts": [5]}
	await _shoot_scene("res://scenes/Fail.tscn", "08_fail_contract_loss")

	# 6. 第 100 關 —— 十 boss 場面
	var f = await _mount_battle(GameData.FINAL_LEVEL)
	f.gold = 999999
	# 快轉到第二潮出場,咁畫面上會同時有 boss 同雜兵
	var t := 0.0
	while t < 95.0:
		f._process(1.0 / 20.0)
		for root in [f.monsters_root, f.towers_root]:
			for c in root.get_children():
				if c.has_method("_process"):
					c._process(1.0 / 20.0)
		t += 1.0 / 20.0
	for i in 3:
		await get_tree().process_frame
	await _grab("06_final_level")

func _mount_battle(level: int):
	Flow.selected_level = level
	var b = load("res://scenes/Battle.tscn").instantiate()
	await _mount(b)
	return b

func _mount(node: Node) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 5:
		await get_tree().process_frame

func _shoot_scene(path: String, name: String) -> void:
	var inst: Node = load(path).instantiate()
	await _mount(inst)
	await _grab(name)

func _grab(name: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUTDIR) + name + ".png")
	print("SHOT ", name, " ", img.get_size())
