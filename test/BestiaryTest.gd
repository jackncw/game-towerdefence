extends Node
## Verifies bestiary sightings persist to save.json and the Bestiary screen builds.

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit())
	Meta.reset_save()
	print("BTEST: start seen empty=%s" % Meta.seen.is_empty())

	# simulate spawns
	Meta.mark_seen("goblin", 1, false)
	Meta.mark_seen("goblin", 2, false)
	Meta.mark_seen("goblin", 0, true)   # boss
	Meta.mark_seen("wolf", 3, false)
	print("BTEST: has goblin_1=%s goblin_boss=%s wolf_3=%s slime_1=%s" % [
		Meta.has_seen("goblin", 1, false), Meta.has_seen("goblin", 0, true),
		Meta.has_seen("wolf", 3, false), Meta.has_seen("slime", 1, false)])
	print("BTEST: family_any_seen goblin=%s slime=%s" % [
		Meta.family_any_seen("goblin"), Meta.family_any_seen("slime")])

	# persistence: reload from disk. Sightings are batched (mark_seen no longer
	# writes the file per creature — that was a mid-wave disk hitch), so flush the
	# pending write first, exactly as Battle._exit_tree does at the end of a run.
	Meta.flush_pending_save()
	Meta.seen = {}
	Meta.load_game()
	print("BTEST: after reload goblin_1=%s wolf_3=%s (persisted=%s)" % [
		Meta.has_seen("goblin", 1, false), Meta.has_seen("wolf", 3, false),
		"OK" if Meta.has_seen("goblin", 1, false) and Meta.has_seen("wolf", 3, false) else "FAIL"])

	# build the Bestiary screen (scene mode) and the overlay mode
	var scene = load("res://scenes/Bestiary.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	print("BTEST: bestiary built, fam_idx=%d (expect goblin=0)" % scene.fam_idx)
	scene._turn(1)
	await get_tree().process_frame
	scene.sel_slot = 5
	scene._rebuild()
	await get_tree().process_frame
	print("BTEST: paged + boss detail rebuilt OK")
	scene.queue_free()

	var ov = load("res://scripts/ui/Bestiary.gd").new()
	ov.overlay = true
	add_child(ov)
	await get_tree().process_frame
	print("BTEST: overlay mode built OK")
	get_tree().quit()
