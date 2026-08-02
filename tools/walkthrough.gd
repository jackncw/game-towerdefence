extends Node
## Round-5 acceptance run: play the real flow — main menu -> level select ->
## level 1 fought to a win -> result — in the shipping portrait resolution, and
## grab a frame every few seconds so the whole journey can be reviewed for
## visual jolts. Unlike art_export this does NOT pre-pose anything: the battle
## runs its own spawner, the towers are bought out of real gold and the win
## screen is whatever the battle actually produced.
##   Godot --path . tools/walkthrough.tscn -- --out=res://r5_walk/

const VW := 1080
const VH := 1920

var OUTDIR := "res://r5_walk/"
var sub: SubViewport
var shot := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			OUTDIR = a.substr(6)
	if not OUTDIR.ends_with("/"):
		OUTDIR += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit())
	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	await _run()
	print("WALK: DONE")
	get_tree().quit()

func _grab(tag: String) -> void:
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	shot += 1
	var img := sub.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUTDIR) + "w%02d_%s.png" % [shot, tag])
	print("WALK ", shot, " ", tag)

func _mount(node: Node) -> void:
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	sub.add_child(node)
	for i in 4:
		await get_tree().process_frame

func _run() -> void:
	Meta.highest_level = 1
	Meta.crystals = 300
	await _mount(load("res://scenes/MainMenu.tscn").instantiate())
	await _grab("menu")
	await _mount(load("res://scenes/LevelSelect.tscn").instantiate())
	await _grab("levelselect")

	Flow.selected_level = 1
	var b: Node = load("res://scenes/Battle.tscn").instantiate()
	await _mount(b)
	b.set_speed_index(2)          # x3 (the fastest tier), so a full level fits the budget
	await _grab("battle_start")

	# buy towers the way a player would: whenever gold allows, drop the next
	# unlocked tower on the first legal spot found.
	var buy_order := [1, 5, 1, 13, 5, 1, 2, 1]
	var bought := 0
	var frames := 0
	var next_shot := 240
	var boss_shots := 0
	# `ended` flips the instant the boss dies, one frame BEFORE Battle navigates
	# to the result screen. We must stop there: Flow.goto swaps the ROOT scene,
	# which frees this harness mid-await (that is what killed the first run).
	while frames < 6000 and is_instance_valid(b) and not b.ended:
		await get_tree().process_frame
		frames += 1
		if bought < buy_order.size():
			var def := GameData.tower_by_id(buy_order[bought])
			if b.gold >= def.place_cost and _try_place(b, buy_order[bought]):
				bought += 1
		if frames >= next_shot:
			next_shot += 900
			await _grab("battle_t%04d" % frames)
		var boss_up: bool = b.boss_spawned and b.boss_ref != null and is_instance_valid(b.boss_ref)
		if boss_shots < 3 and boss_up and frames % 90 == 0:
			boss_shots += 1
			await _grab("battle_boss%d" % boss_shots)
	await _grab("battle_end")
	# Stop here. Battle._win() has already queued Flow.goto(RESULT), which swaps
	# the ROOT scene and would free this harness mid-await; the result screen is
	# captured by art_export (09_result) instead.
	print("WALK: level 1 cleared, ended=", b.ended if is_instance_valid(b) else "freed")

func _try_place(battle: Node, id: int) -> bool:
	for gy in range(4, 21):
		for gx in range(2, 13):
			var pos: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(pos) and battle.place_tower(id, pos):
				return true
	return false
