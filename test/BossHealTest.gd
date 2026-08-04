extends Node
## Regression test for the boss 回復 rework. Covers EVERY boss family, not just
## the two that were reported, because the rules are meant to be structural:
##
##   A 血條淨向下 — damaged at exactly the level's expected DPS
##     (boss_max_hp / GameData.BOSS_FIGHT_REF_SECONDS), no boss's HP ever climbs
##     above where it already was. This is the whole point of the ceiling.
##   B 回復上限 — left completely alone, a boss's sustained self-heal never
##     exceeds GameData.BOSS_HEAL_CAP_FRAC of its max HP per second.
##   C 樹妖詠唱 — the low-HP heal is a 2.5s cast, not an instant; damage during
##     the cast cancels it 1:1; a stun breaks it outright; left alone it pays.
##   D 復活光環 — a skeleton minion revives at most GameData.AURA_REVIVE_MAX
##     times while the 骷髏君主 lives (it used to be unbounded).
##   E 視覺誠實 — any restored HP arms the green rebound flash and a floating
##     number, so healing can never happen silently.
##
## Everything is stepped manually at a fixed dt with the tree paused, so the
## numbers are frame-rate independent. Backs up and restores the real save.json.

const DT := 1.0 / 30.0

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	_tree.paused = true
	seed(0xB055)
	await _case_a_monotonic()
	await _case_b_cap()
	await _case_c_channel()
	await _case_d_revive()
	await _case_e_feedback()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	print("BOSSHEAL %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("BOSSHEAL   %s %s" % ["ok  " if ok else "FAIL", what])

# --- A: the blood bar only goes down at on-curve DPS -------------------------
func _case_a_monotonic() -> void:
	print("BOSSHEAL -- A 血條淨向下(火力達標)")
	for i in GameData.FAMILY_ORDER.size():
		var fam: String = GameData.FAMILY_ORDER[i]
		var lv: int = i + 1                       # level whose boss family this is
		var b = await _start(lv)
		var boss: Monster = _spawn_boss(b, fam)
		var dps: float = boss.max_hp / GameData.BOSS_FIGHT_REF_SECONDS
		var peak: float = boss.hp
		var worst_rise := 0.0
		var t := 0.0
		while t < GameData.BOSS_FIGHT_REF_SECONDS * 2.0 and boss.alive:
			boss.take_true(dps * DT)
			if not boss.alive:
				break
			_step(b, DT)
			t += DT
			worst_rise = maxf(worst_rise, boss.hp - peak)
			peak = minf(peak, boss.hp)
		# 0.5% of max HP of slack: one frame of capped regen can land between the
		# damage tick and the sample without the bar visibly moving.
		var tol: float = boss.max_hp * 0.005
		_check(worst_rise <= tol,
			"第%2d關 %-8s boss 血條冇回升 (最大回升 %.2f%% max_hp, 用時 %.1fs)"
			% [lv, fam, 100.0 * worst_rise / boss.max_hp, t])
		await _end(b)

# --- B: sustained self-heal ceiling ------------------------------------------
func _case_b_cap() -> void:
	print("BOSSHEAL -- B 回復上限 %.2f%% max_hp/s" % [100.0 * GameData.BOSS_HEAL_CAP_FRAC])
	for fam in GameData.FAMILY_ORDER:
		var b = await _start(1)
		var boss: Monster = _spawn_boss(b, fam)
		# knock it down once, then leave it entirely alone and watch it recover
		boss.hp = boss.max_hp * 0.3
		var hp0: float = boss.hp
		var secs := 20.0
		var t := 0.0
		while t < secs and boss.alive:
			_step(b, DT)
			t += DT
		var gained: float = maxf(0.0, boss.hp - hp0)
		var rate: float = gained / t / boss.max_hp
		# the 詠唱 payout is a designed, telegraphed exception; allow for one of
		# them landing inside the window on top of the sustained ceiling
		var allowance: float = GameData.BOSS_HEAL_CAP_FRAC
		if boss.boss_mech == "root_heal":
			allowance += GameData.TREANT_CHANNEL_HEAL / secs
		_check(rate <= allowance * 1.05,
			"%-8s 自療 %.3f%%/s <= 上限 %.3f%%/s" % [fam, rate * 100.0, allowance * 100.0])
		await _end(b)

# --- C: the treant cast is a real window -------------------------------------
func _case_c_channel() -> void:
	print("BOSSHEAL -- C 樹妖詠唱")
	# c1: it is a cast, not an instant, and it pays if ignored
	var b = await _start(8)
	var boss: Monster = _spawn_boss(b, "treant")
	boss.hp = boss.max_hp * 0.35
	_step(b, DT)
	_check(boss.channel_time > 0.0, "低血觸發詠唱(唔係即時回復)")
	_check(boss.rooted_time > 0.0, "詠唱期間定身")
	var hp_at_cast: float = boss.hp
	var t := 0.0
	while t < GameData.TREANT_CHANNEL_TIME + 0.4:
		_step(b, DT)
		t += DT
	_check(boss.channel_time <= 0.0, "詠唱時間 ~%.1fs 之後結束" % GameData.TREANT_CHANNEL_TIME)
	var paid: float = boss.hp - hp_at_cast
	_check(paid > boss.max_hp * GameData.TREANT_CHANNEL_HEAL * 0.85,
		"完全唔理會回復 %.1f%% max_hp" % [100.0 * paid / boss.max_hp])
	await _end(b)

	# c2: on-curve damage during the cast denies it completely
	b = await _start(8)
	boss = _spawn_boss(b, "treant")
	boss.hp = boss.max_hp * 0.35
	_step(b, DT)
	_check(boss.channel_time > 0.0, "第二次一樣觸發到詠唱")
	var dps: float = boss.max_hp / GameData.BOSS_FIGHT_REF_SECONDS
	var before: float = boss.hp
	var dealt := 0.0
	t = 0.0
	while boss.channel_time > 0.0 and t < 5.0:
		boss.take_true(dps * DT)
		dealt += dps * DT
		_step(b, DT)
		t += DT
	_check(boss.channel_heal <= 0.0, "詠唱期間打足預期 DPS,回復額被清零")
	var mid: float = boss.hp
	_step(b, DT)
	_check(boss.hp <= mid + boss.max_hp * GameData.BOSS_HEAL_CAP_FRAC * DT * 2.0,
		"詠唱結束冇補血,淨低得返受上限管住嘅持續回復")
	# 樹妖 also regenerates, which the ceiling meters; the bar must still be net
	# down by the damage minus at most that metered trickle
	# +3 frames of slack: `t` is the loop counter, but the ceiling also ticked on
	# the frame that closed the cast and on the one sampled after it
	var regen_max: float = boss.max_hp * GameData.BOSS_HEAL_CAP_FRAC * (t + 3.0 * DT) + 1.0
	_check(boss.hp <= before - dealt + regen_max,
		"血條淨向下 (%.0f -> %.0f,打咗 %.0f,持續回復上限 %.0f)"
		% [before, boss.hp, dealt, regen_max])
	await _end(b)

	# c3: a stun breaks it outright
	b = await _start(8)
	boss = _spawn_boss(b, "treant")
	boss.hp = boss.max_hp * 0.35
	_step(b, DT)
	_check(boss.channel_time > 0.0, "第三次一樣觸發到詠唱")
	var hp_stun: float = boss.hp
	boss.apply_stun(0.5)
	_step(b, DT)
	_check(boss.channel_time <= 0.0, "暈眩即刻打斷詠唱")
	t = 0.0
	while t < 2.0:
		_step(b, DT)
		t += DT
	# only the metered sustained regen may have moved the bar — none of the 15%
	# the cast was going to pay
	_check(boss.hp <= hp_stun + boss.max_hp * GameData.BOSS_HEAL_CAP_FRAC * (t + 0.2),
		"打斷之後冇收到詠唱回復 (%.0f -> %.0f,持續回復上限 %.0f)"
		% [hp_stun, boss.hp, boss.max_hp * GameData.BOSS_HEAL_CAP_FRAC * t])
	await _end(b)

# --- D: the revive aura is bounded -------------------------------------------
func _case_d_revive() -> void:
	print("BOSSHEAL -- D 骷髏復活光環")
	var b = await _start(3)
	var boss: Monster = _spawn_boss(b, "skeleton")
	var minion: Monster = b._spawn_monster("skeleton", 3, false, 100.0)
	var revives := 0
	for i in 8:
		if not minion.alive:
			break
		minion.take_true(minion.max_hp * 2.0)
		if minion.alive:
			revives += 1
	_check(revives == GameData.AURA_REVIVE_MAX,
		"光環下小兵最多復活 %d 次(實際 %d)" % [GameData.AURA_REVIVE_MAX, revives])
	_check(not minion.alive, "用晒次數之後真係死得")
	# without the aura it is the plain one-shot revive
	b.skeleton_boss_alive = null
	var solo: Monster = b._spawn_monster("skeleton", 3, false, 100.0)
	var solo_revives := 0
	for i in 5:
		if not solo.alive:
			break
		solo.take_true(solo.max_hp * 2.0)
		if solo.alive:
			solo_revives += 1
	_check(solo_revives == 1, "冇光環時仍然係普通一次復活(實際 %d)" % solo_revives)
	_check(boss.alive, "boss 自己唔會復活咁啱死咗")
	await _end(b)

# --- E: healing is never silent ----------------------------------------------
func _case_e_feedback() -> void:
	print("BOSSHEAL -- E 視覺誠實")
	var b = await _start(9)
	var boss: Monster = _spawn_boss(b, "cultist")
	boss.hp = boss.max_hp * 0.5
	var before_live: int = b.dmg_pool.live_count()
	var got: float = boss.request_heal(boss.max_hp * 0.05, true)
	_check(got > 0.0, "request_heal 有回血 (%.0f)" % got)
	_check(boss._heal_flash > 0.0, "回血即刻 arm 咗綠色回跳 flash")
	# the floating number is banked then flushed, so run a frame
	_step(b, DT)
	_check(b.dmg_pool.live_count() > before_live, "回血有浮動數字彈出")
	await _end(b)

	# The one that actually got missed the first time: a boss's heal is METERED
	# to ~1.25%/s, i.e. ~0.02% of the bar per frame. A frame-to-frame comparison
	# never clears any sane threshold, so slow regen stayed completely silent on
	# the boss bar. The band is measured from a low-water mark instead.
	b = await _start(8)
	boss = _spawn_boss(b, "treant")
	if b.hud == null:
		_check(false, "Battle 有 HUD 可以驗 boss 血條")
	else:
		boss.hp = boss.max_hp * 0.55
		_step(b, DT)
		_check(not b.hud.boss_heal_rect.visible, "冇回血時冇綠色條")
		var t := 0.0
		while t < 3.0:
			_step(b, DT)              # nothing but the metered regen
			t += DT
		_check(b.hud.boss_heal_rect.visible,
			"慢速再生都睇得見:boss 血條有綠色回復段 (寬 %.1fpx)"
			% b.hud.boss_heal_rect.size.x)
		# and it resets the moment the player lands a hit
		boss.take_true(boss.max_hp * 0.05)
		_step(b, DT)
		_check(not b.hud.boss_heal_rect.visible, "再受傷之後綠色段清零")
	await _end(b)

# ---------------------------------------------------------------------------
## **唔好用逢 7 嘅倍數關做 harness 場景。** 第十五輪起佢哋係合約關:開場即刻
## 攤三張卡並且凍結成個場(Battle._open_contract_offer),而一個唔識答佢嘅
## harness 會坐喺度乜都唔郁 —— 症狀係「所有同時間有關嘅斷言一齊靜靜咁失敗」,
## 而唔係一個講得出原因嘅錯誤。
func _start(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await _tree.process_frame
	b.base_shield = 100000
	b.boss_time = 1.0e9        # we own boss spawning; no ambient wave interference
	return b

## Spawn `fam`'s boss the way Battle would, minus the wave around it.
func _spawn_boss(b, fam: String) -> Monster:
	var m: Monster = b._spawn_monster(fam, 5, true, 0.0)
	b.boss_ref = m
	b.boss_spawned = true
	b.boss_profile = GameData.boss_spawn_profile(fam)
	if m.mech == "revive":
		b.skeleton_boss_alive = m
	return m

func _end(b) -> void:
	b.queue_free()
	await _tree.process_frame
	_tree.paused = true

func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
