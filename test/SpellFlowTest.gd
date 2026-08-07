extends Node
## Verifies spell request flow: instant spells fire on icon press (no aim);
## targeted spells enter aim mode then cast on map tap; re-press cancels aim.

var battle

func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func(): get_tree().quit())
	# temporarily unlock an instant (8 warcry) + targeted (13 smite) spell
	Meta.unlocked_spells = [1, 8, 13]
	Flow.selected_level = 1
	battle = load("res://scenes/Battle.tscn").instantiate()
	add_child(battle)
	await get_tree().process_frame
	await get_tree().process_frame

	# instant: warcry (id 8, target=false) -> casts now, no aim, cd set, buff on
	battle.request_spell(8)
	var bad := 0
	var instant_ok: bool = battle.aiming_spell == 0 and battle.spell_cd.get(8, 0.0) > 0.0 and battle.warcry_haste > 0.0
	print("SFLOW instant(warcry): aim=%d cd=%.1f haste=%.2f -> %s" % [
		battle.aiming_spell, battle.spell_cd.get(8, 0.0), battle.warcry_haste,
		"OK" if instant_ok else "FAIL"])
	bad += 0 if instant_ok else 1

	# targeted: smite (id 13) -> enters aim
	battle.request_spell(13)
	print("SFLOW targeted enter-aim: aim=%d -> %s" % [
		battle.aiming_spell, "OK" if battle.aiming_spell == 13 else "FAIL"])
	bad += 0 if battle.aiming_spell == 13 else 1
	# re-press cancels aim
	battle.request_spell(13)
	print("SFLOW targeted re-press cancels: aim=%d -> %s" % [
		battle.aiming_spell, "OK" if battle.aiming_spell == 0 else "FAIL"])
	bad += 0 if battle.aiming_spell == 0 else 1

	# targeted tap with a monster in range -> casts + damages
	battle.request_spell(13)
	var mpos := Vector2(540, 700)
	var mon = battle._spawn_monster("goblin", 3, false, 0.0)
	mon.dist = battle.route.nearest_dist_param(mpos)
	mon.position = mpos
	var hp0: float = mon.hp
	battle._handle_tap(mpos)
	await get_tree().process_frame
	var dmg: float = hp0 - mon.hp
	print("SFLOW targeted cast on tap: dmg=%.0f aim=%d cd=%.1f -> %s" % [
		dmg, battle.aiming_spell, battle.spell_cd.get(13, 0.0),
		"OK" if dmg > 0.0 and battle.aiming_spell == 0 else "FAIL"])
	bad += 0 if (dmg > 0.0 and battle.aiming_spell == 0) else 1

	# restore default unlocks (leave save untouched: this test never saved spells)
	# 第 21 輪:以前四項全部肥佬都照 quit(0),而套裝只睇 exit code —— 即係
	# 呢個測試由寫出嚟嗰日起就冇守過任何嘢。
	print("SFLOW %s fails=%d (4 項)" % ["PASS" if bad == 0 else "FAIL", bad])
	get_tree().quit(0 if bad == 0 else 1)
