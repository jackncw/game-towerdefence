extends Node
## Visual confirmation for the boss-heal rework (視覺誠實 acceptance item).
## Renders, at full 1080x1920 through a SubViewport, the moments the rework is
## supposed to make legible, then quits. Needs a GPU — run WINDOWED:
##   Godot --path . tools/heal_shots.tscn --log-file <log> -- --out=heal_shots
## 輸出永遠喺 res://qa/ 之下 —— 見 tools/art_export.gd 嘅 QA_ROOT 註解:
## Web export 嘅排除表係人手維護嘅目錄名單,而人手名單已經漏咗兩次。
## Treat "HEAL_SHOTS: DONE" in the log plus the PNGs as the completion signal;
## the Windows GUI exe detaches from the console.

const VW := 1080
const VH := 1920

const ArtExport := preload("res://tools/art_export.gd")

var OUTDIR := ArtExport.QA_ROOT + "heal_shots/"
var sub: SubViewport
var done := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			OUTDIR = ArtExport.qa_dir(a.substr(6))
	if not OUTDIR.ends_with("/"):
		OUTDIR += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTDIR))
	print("HEAL_SHOTS: out=", OUTDIR)
	get_tree().create_timer(300.0).timeout.connect(func():
		if not done:
			push_warning("heal_shots timed out")
			get_tree().quit())
	Flow.nav_enabled = false
	Meta.crystals = 4000
	Meta.unlocked_towers = range(1, 21)
	sub = SubViewport.new()
	sub.size = Vector2i(VW, VH)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.disable_3d = true
	add_child(sub)
	await get_tree().process_frame
	await _run()
	done = true
	print("HEAL_SHOTS: DONE")
	get_tree().quit()

func _run() -> void:
	# --- 1/2/3: 遠古樹妖 詠唱 (第 7 關) -------------------------------------
	var b = await _battle(7)
	var boss: Monster = _boss(b, "treant")
	boss.hp = boss.max_hp * 0.35
	await _frames(2)
	await _grab("01_treant_cast_start")     # ring just opened, heal fully green
	await _frames(30)
	await _grab("02_treant_cast_mid")       # ring half filled
	# eat into the pending heal so the ring washes out to grey
	for i in 40:
		boss.take_true(boss.max_hp * 0.005)
		await _frames(1)
	await _grab("03_treant_cast_denied")    # ring greyed = this cast pays nothing
	b.queue_free()
	await _frames(2)

	# --- 4: 大祭司 群療,boss 血條綠色回跳 (第 9 關) ------------------------
	b = await _battle(9)
	boss = _boss(b, "cultist")
	boss.hp = boss.max_hp * 0.55
	boss.heal_pending = boss.max_hp * 0.12
	# the ceiling meters that out at 1.25%/s, so let it actually run — the green
	# band grows from the low-water mark rather than appearing in one frame
	await _frames(150)
	await _grab("04_boss_bar_heal_rebound")
	b.queue_free()
	await _frames(2)

	# --- 5: 骷髏小兵復活,怪物血條綠色回跳 + 綠色數字 (第 3 關) -------------
	b = await _battle(3)
	boss = _boss(b, "skeleton")
	var minion: Monster = b._spawn_monster("skeleton", 3, false, b.route.total * 0.45)
	minion.take_true(minion.max_hp * 2.0)   # dies -> revives at 30%
	await _frames(2)
	await _grab("05_minion_revive")
	b.queue_free()
	await _frames(2)

# ---------------------------------------------------------------------------
func _battle(level: int):
	for c in sub.get_children():
		c.queue_free()
	await get_tree().process_frame
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	sub.add_child(b)
	await _frames(4)
	b.base_shield = 100000
	b.boss_time = 1.0e9        # we place the boss ourselves
	return b

func _boss(b, fam: String) -> Monster:
	var m: Monster = b._spawn_monster(fam, 5, true, b.route.total * 0.42)
	b.boss_ref = m
	b.boss_spawned = true
	b.boss_profile = GameData.boss_spawn_profile(fam)
	if m.mech == "revive":
		b.skeleton_boss_alive = m
	if b.hud:
		b.hud.show_boss(m)
	return m

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _grab(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = sub.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUTDIR) + name + ".png")
	print("HEAL_SHOTS ", name, " ", img.get_size())
