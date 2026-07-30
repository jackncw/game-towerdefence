extends Node
## Instantiate every UI scene once to catch _ready build errors. Headless.

var scenes := [
	"res://scenes/MainMenu.tscn",
	"res://scenes/LevelSelect.tscn",
	"res://scenes/Shop.tscn",
	"res://scenes/Upgrade.tscn",
	"res://scenes/Result.tscn",
	"res://scenes/Fail.tscn",
	"res://scenes/Settings.tscn",
	"res://scenes/Gallery.tscn",
	"res://scenes/Bestiary.tscn",
]

# Result/Fail read different fields per outcome, so each payout shape is built
# once: first clear (bonus row), replay (halved, no bonus), progress loss and
# the sub-10s loss that pays nothing.
var result_variants := [
	{"win": true, "level": 2, "kills": 42, "crystals": 112, "base": 52, "first": 60, "replay": false},
	{"win": true, "level": 2, "kills": 42, "crystals": 26, "base": 26, "first": 0, "replay": true},
]
var fail_variants := [
	{"win": false, "level": 4, "kills": 31, "crystals": 18, "progress": 0.66, "cap": 27,
		"too_short": false, "boss_frac": 0.42, "time": 71.0, "boss_reached": true},
	{"win": false, "level": 4, "kills": 0, "crystals": 0, "progress": 0.0, "cap": 27,
		"too_short": true, "boss_frac": 0.0, "time": 4.0, "boss_reached": false},
]

func _ready() -> void:
	# give Result/Fail some data
	Flow.last_result = result_variants[0]
	# make level select show a few cards
	Meta.highest_level = 3
	Meta.cleared = {"1": true, "2": true, "3": true}
	await get_tree().process_frame
	for path in scenes:
		var ps := load(path)
		if ps == null:
			print("CHECK FAIL load ", path)
			continue
		var inst = ps.instantiate()
		add_child(inst)
		await get_tree().process_frame
		await get_tree().process_frame
		print("CHECK OK ", path)
		inst.queue_free()
		await get_tree().process_frame
	for i in result_variants.size():
		await _build_variant("res://scenes/Result.tscn", result_variants[i], "result#%d" % i)
	for i in fail_variants.size():
		await _build_variant("res://scenes/Fail.tscn", fail_variants[i], "fail#%d" % i)
	print("CHECK: ALL DONE")
	get_tree().quit()

func _build_variant(path: String, data: Dictionary, label: String) -> void:
	Flow.last_result = data
	var inst = load(path).instantiate()
	add_child(inst)
	await get_tree().process_frame
	await get_tree().process_frame
	print("CHECK OK %s (%s)" % [path, label])
	inst.queue_free()
	await get_tree().process_frame
