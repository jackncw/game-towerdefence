extends Node
## Headless smoke test: spawns every family + boss, instantiates all 20 towers,
## casts all 15 spells, exercises select/sell/speed. Prints TEST markers so a
## grep for errors is meaningful. Not shipped with the game.

var battle
var t := 0.0
var did_setup := false
var spell_i := 1
var spell_timer := 0.0
var fam_i := 0
var fam_timer := 0.0
var boss_i := 0
var boss_timer := 2.0

func _ready() -> void:
	# unlock everything in-memory (no save) so HUD builds all bars
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Flow.selected_level = 3
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	print("TEST: battle instantiated")

func _process(delta: float) -> void:
	if battle == null or not is_instance_valid(battle):
		return
	t += delta
	battle.gold = 999999
	battle.base_shield = 999999   # never lose during the test

	if not did_setup and t > 0.4:
		did_setup = true
		_place_all_towers()
		print("TEST: placed %d towers" % battle.towers.size())

	# spawn one of each family (lv scaling) steadily
	fam_timer -= delta
	if fam_timer <= 0.0 and fam_i < GameData.FAMILY_ORDER.size():
		fam_timer = 0.35
		var fam: String = GameData.FAMILY_ORDER[fam_i]
		battle._spawn_monster(fam, 4, false, 0.0)
		battle._spawn_monster(fam, 2, false, 0.0)
		fam_i += 1

	# spawn each boss (made unkillable so no _win/save pollution)
	boss_timer -= delta
	if boss_timer <= 0.0 and boss_i < GameData.FAMILY_ORDER.size():
		boss_timer = 0.8
		var fam: String = GameData.FAMILY_ORDER[boss_i]
		var b = battle._spawn_monster(fam, 5, true, 0.0)
		b.max_hp = 1.0e12
		b.hp = 1.0e12
		if b.mech == "revive":
			battle.set_skeleton_lord(b)
		boss_i += 1
		print("TEST: spawned boss %s" % fam)

	# cast each spell once
	spell_timer -= delta
	if spell_timer <= 0.0 and spell_i <= 15:
		spell_timer = 0.3
		var pos := Vector2(540, 700)
		Spells.cast(battle, spell_i, pos)
		spell_i += 1
		if spell_i == 16:
			print("TEST: cast all 15 spells")

	# exercise select + speed cycle midway
	if abs(t - 4.0) < delta and battle.towers.size() > 0:
		battle._set_selected(battle.towers[0])
		battle.set_speed_index(2)
		print("TEST: selected tower + speed %s" % Battle.speed_label(battle.game_speed))

	# sell a tower late
	if abs(t - 6.0) < delta and battle.towers.size() > 3:
		battle.sell_tower(battle.towers[3])
		print("TEST: sold a tower, monsters=%d towers=%d" % [battle.monsters.size(), battle.towers.size()])

	if t > 9.0:
		print("TEST: COMPLETE monsters=%d towers=%d kills=%d" % [battle.monsters.size(), battle.towers.size(), battle.kills])
		get_tree().quit()

func _place_all_towers() -> void:
	# directly instantiate all 20 (bypass road/overlap checks) so every _process runs
	var TowerScript := load("res://scripts/battle/Tower.gd")
	var i := 0
	for id in range(1, 21):
		var col := i % 5
		var row := i / 5
		var pos := Vector2(140 + col * 190, 320 + row * 220)
		var tw = TowerScript.new()
		battle.towers_root.add_child(tw)
		tw.setup(battle, id, pos)
		battle.towers.append(tw)
		if tw.mech == "alchemy":
			battle.alchemy_towers.append(tw)
		elif tw.mech == "holy":
			battle.holy_towers.append(tw)
		i += 1
