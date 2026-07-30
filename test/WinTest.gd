extends Node
## Verify full win path: boss dies -> _win -> Meta.on_level_cleared -> save.

var battle
var reported := false

func _ready() -> void:
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Flow.selected_level = 1
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	battle.gold = 999999
	# ring the path start with strong towers
	var placed := 0
	for gx in range(2, 13):
		for gy in range(3, 8):
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos) and battle.place_tower(1 if placed % 2 == 0 else 7, pos):
				placed += 1
	print("WINTEST placed=", placed)
	# jump to boss time
	battle.elapsed = 60.5

func _process(_d: float) -> void:
	if battle == null or not is_instance_valid(battle) or reported:
		return
	if battle.ended:
		reported = true
		print("WINTEST ended win=", Flow.last_result.get("win"),
			" crystals=", Flow.last_result.get("crystals"),
			" highest=", Meta.highest_level,
			" cleared1=", Meta.is_cleared(1),
			" saveExists=", FileAccess.file_exists(Meta.SAVE_PATH))
		get_tree().quit()
