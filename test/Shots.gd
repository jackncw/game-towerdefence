extends Node
const OUT := "C:/Users/User/AppData/Local/Temp/claude/C--Users-User-Desktop-Jack-AI-Claude-016-game---tower-defence/3263504b-bc02-456c-8ebf-728f75252863/scratchpad/"
var done := false

func _ready() -> void:
	get_tree().create_timer(80.0).timeout.connect(func(): if not done: get_tree().quit())
	Flow.last_result = {"win": true, "level": 2, "kills": 42, "crystals": 60, "replay": true}
	Meta.highest_level = 5
	Meta.cleared = {"1": true, "2": true, "3": true, "4": true, "5": true}
	Meta.crystals = 3200
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	await get_tree().process_frame
	await _shoot_battle()
	for s in [["res://scenes/MainMenu.tscn","menu"],["res://scenes/Shop.tscn","shop"],
			  ["res://scenes/Upgrade.tscn","upgrade"],["res://scenes/Gallery.tscn","gallery"],
			  ["res://scenes/Result.tscn","result"]]:
		await _shoot(s[0], s[1])
	done = true
	print("SHOTS: DONE")
	get_tree().quit()

func _grab(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT + "shot_" + name + ".png")
	print("SHOT ", name, " ", img.get_size())

func _shoot(path: String, name: String) -> void:
	var inst = load(path).instantiate()
	add_child(inst)
	for i in 5:
		await get_tree().process_frame
	_grab(name)
	inst.queue_free()
	await get_tree().process_frame

func _shoot_battle() -> void:
	Flow.selected_level = 4
	var battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.gold = 9000
	var ids := [1, 2, 3, 5, 13, 12, 16, 10]
	var placed := 0
	for gx in range(2, 13):
		for gy in range(4, 18):
			if placed >= ids.size(): break
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos) and battle.place_tower(ids[placed], pos):
				placed += 1
	for i in 10:
		battle._spawn_monster(GameData.FAMILY_ORDER[i % 3], 3, false, i * 30.0)
	battle.elapsed = 58.0
	for i in 90:
		await get_tree().process_frame
	_grab("battle")
	print("battle placed=", placed)
	battle.queue_free()
	await get_tree().process_frame
