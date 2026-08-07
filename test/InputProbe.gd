extends Node
## Verifies the placement/spell input fix in three isolated parts:
##  1 ROUTING  : a synthetic touch reaches _handle_tap (the chain is wired)
##  2 COORDS   : screen_to_world exactly inverts the on-screen transform, at
##               default view AND under zoom+pan (B2 correctness)
##  3 ACTION   : _handle_tap(world) places a tower / lands a meteor there (A1/A2)

var battle

func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func():
		print("PROBE: TIMEOUT"); get_tree().quit())
	Meta.unlocked_towers = [1, 2, 5, 13]
	Meta.unlocked_spells = [1]
	Flow.selected_level = 1
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame
	battle.gold = 9000

	# 1 ROUTING: push a touch (build mode) and confirm the tap handler ran
	battle.request_build(1)
	battle._last_tap_ms = 0
	var down := InputEventScreenTouch.new()
	down.index = 0; down.pressed = true; down.position = Vector2(400, 800)
	battle.get_viewport().push_input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0; up.pressed = false; up.position = Vector2(400, 800)
	battle.get_viewport().push_input(up)
	await get_tree().process_frame
	var bad := 0
	var r1: bool = battle._last_tap_ms != 0
	bad += 0 if r1 else 1
	print("PROBE[1 ROUTING] touch reached _handle_tap: %s" %
		("OK" if r1 else "FAIL"))
	battle.cancel_modes()

	# 2 COORDS: on-screen pos of a world point, then invert it back
	var ok_default := _coord_ok(Vector2(300, 500)) and _coord_ok(Vector2(760, 1200))
	bad += 0 if ok_default else 1
	print("PROBE[2 COORDS] default view round-trip: %s" % ("OK" if ok_default else "FAIL"))
	battle._zoom_at(1.7, Vector2(540, 900))
	battle.cam.position += Vector2(140, 220)
	battle._clamp_cam()
	await get_tree().process_frame
	var ok_zoom := _coord_ok(Vector2(300, 500)) and _coord_ok(Vector2(760, 1200))
	bad += 0 if ok_zoom else 1
	print("PROBE[2 COORDS] zoom=%.2f+pan round-trip: %s" %
		[battle.cam.zoom.x, "OK" if ok_zoom else "FAIL"])
	battle._reset_view()
	await get_tree().process_frame

	# 3 ACTION: place a tower at a valid spot via _handle_tap
	var spot := _find_spot()
	battle.request_build(1)
	battle._handle_tap(spot)
	await get_tree().process_frame
	var placed: bool = battle.towers.size() == 1 and \
		battle.towers[0].global_position.distance_to(spot) < 60.0
	bad += 0 if placed else 1
	print("PROBE[3 ACTION] place tower at tapped world: %s" % ("OK" if placed else "FAIL"))

	# 3b meteor lands where tapped and damages a monster
	var mpos := Vector2(540, 700)
	var mon = battle._spawn_monster("goblin", 3, false, 0.0)
	mon.dist = battle.route.nearest_dist_param(mpos)
	mon.position = mpos
	var hp0: float = mon.hp
	battle.request_spell(1)
	battle._handle_tap(mpos)
	await get_tree().process_frame
	var dmg: float = hp0 - mon.hp
	var r5: bool = dmg > 0.0 and battle.spell_cd.get(1, 0.0) > 0.0
	bad += 0 if r5 else 1
	print("PROBE[3 ACTION] meteor at tapped world dmg=%.0f cd=%.1f: %s" %
		[dmg, battle.spell_cd.get(1, 0.0), "OK" if r5 else "FAIL"])

	# 第 21 輪:以前無論幾多項 FAIL 都係 quit(0),而套裝只睇 exit code 同
	# 「最後一行有冇 PASS/FAIL 字」—— 即係話呢五項全部肥佬都可以報綠。
	print("PROBE %s fails=%d (5 項)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(0 if bad == 0 else 1)

func _coord_ok(world: Vector2) -> bool:
	# canvas_transform maps world -> the coordinate space that input events use
	var sp: Vector2 = battle.get_viewport().get_canvas_transform() * world
	var back: Vector2 = battle.screen_to_world(sp)
	return back.distance_to(world) < 0.5

func _find_spot() -> Vector2:
	for gx in range(3, 12):
		for gy in range(4, 17):
			var p: Vector2 = battle.snap(Vector2(gx * 74, gy * 74))
			if battle.can_place(p):
				return p
	return Vector2(234, 450)
