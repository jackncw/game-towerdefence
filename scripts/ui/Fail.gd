extends Control

func _ready() -> void:
	# was a flat maroon fill with every stat floating as bare text, while the win
	# screen framed its stats in a panel — same moment, two different looks
	UI.menu_backdrop(self, Color(0.92, 0.34, 0.26, 0.6))
	var r: Dictionary = Flow.last_result
	var lv: int = r.get("level", 1)

	add_child(UI.banner_title("防線失守!", 168, 760, 60))
	var sub := UI.title("有怪物攻入基地 — 第 %d 關" % lv, 34)
	sub.position = Vector2(0, 306); sub.size = Vector2(1080, 50)
	add_child(sub)

	var panel := UI.panel_rect()
	panel.position = Vector2(190, 382)
	panel.size = Vector2(700, 366)
	add_child(panel)

	var skull := UI.tex_rect(Assets.ui("ic_skull"), Vector2(70, 70))
	skull.position = Vector2(315, 26)
	panel.add_child(skull)
	var kills := UI.title("擊殺數: %d" % r.get("kills", 0), 42)
	kills.position = Vector2(0, 108); kills.size = Vector2(700, 56)
	panel.add_child(kills)

	# A loss now pays out by progress (kills + time survived + boss damage), so
	# the screen shows what was earned and points at the next rung of progress
	# rather than just telling the player they got nothing.
	var reward: int = r.get("crystals", 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.position = Vector2(0, 176); row.size = Vector2(700, 56)
	row.add_child(UI.label("獲得魔晶", 36, UI.TEXT))
	row.add_child(UI.tex_rect(Assets.crystal(), Vector2(44, 44)))
	row.add_child(UI.label(str(reward), 42, UI.CRYSTAL))
	panel.add_child(row)

	var msg := "擊敗 boss 可獲得更多!"
	if r.get("too_short", false):
		msg = "戰鬥太短,今次冇魔晶獎勵"
	elif r.get("boss_reached", false):
		msg = "已擊傷首領 %d%% — 擊敗佢可獲得更多!" % int(round(r.get("boss_frac", 0.0) * 100.0))
	var note := UI.label(msg, 28, Color(0.86, 0.76, 0.62))
	note.position = Vector2(20, 240); note.size = Vector2(660, 40)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(note)

	var prog := UI.label("戰鬥進度 %d%% (失敗上限 %d 魔晶)"
		% [int(round(r.get("progress", 0.0) * 100.0)), r.get("cap", 0)],
		24, Color(0.74, 0.64, 0.56))
	prog.position = Vector2(20, 292); prog.size = Vector2(660, 36)
	prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(prog)

	var retry := UI.button("重試本關", Vector2(500, 130), UI.ACCENT, 40)
	retry.position = Vector2(290, 780)
	retry.pressed.connect(func(): Flow.play_level(lv))
	add_child(retry)
	var home := UI.button("返回主選單", Vector2(500, 110), UI.PANEL, 34)
	home.position = Vector2(290, 940)
	home.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(home)
