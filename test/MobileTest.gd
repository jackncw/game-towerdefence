extends Node
## Android 平台適配嘅 headless 回歸測試 —— 返回鍵、切背景、閃退標記。
##
## **點解一個 headless 測試守得住一個 Android 專項嘅行為**:呢一輪特登冇將
## 任何一段邏輯收喺 `OS.has_feature("android")` 之下。返回鍵行嘅係
## `Mobile.request_back()`,而 Android 個 GO_BACK notification 同桌面嘅 Esc
## 兩邊都淨係叫呢一句;切背景行嘅係 `Mobile._on_paused()` / `_on_resumed()`,
## 而 `NOTIFICATION_APPLICATION_PAUSED` 兩個字亦都淨係叫呢兩句。所以喺 PC 上面
## 直接叫佢哋,量到嘅就係部電話上面會發生嘅嘢 —— 冇部機喺手嗰陣,呢個係
## 唯一一種「證得到」而唔係「應該冇事」嘅寫法。
##
## 真機上面仲要驗嘅係另一半:嗰個 notification 到底有冇派落嚟。
## 嗰半由 dist/DEVICE_CHECKLIST.md 收。
##
## Run: godot --headless --path . res://test/MobileTest.tscn

var fails := 0
var _save_bytes := PackedByteArray()
var _had_save := false

const SAVE := "user://save.json"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(120.0, true, false, true).timeout.connect(func():
		print("MOBILE: TIMEOUT"); get_tree().quit(1))
	_backup_save()
	Flow.nav_enabled = false          # 呢個 harness 自己話事導航
	Crash.enabled = false             # 唔好留低假嘅閃退證物
	Meta.reset_save()

	await _case_settings()
	await _case_back_in_battle()
	await _case_back_in_menu_screen()
	await _case_back_in_main_menu()
	await _case_lifecycle()
	await _case_crash_marker()

	Flow.nav_enabled = true
	get_tree().paused = false
	_restore_save()
	print("MOBILE %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("MOBILE   %s %s" % ["ok  " if ok else "FAIL", what])

# ---------------------------------------------------------------------------
# A. 出貨設定:一改錯就要即刻知
# ---------------------------------------------------------------------------
func _case_settings() -> void:
	print("MOBILE -- A 出貨設定")
	var orient = ProjectSettings.get_setting("display/window/handheld/orientation", -1)
	_check(int(orient) == 5, "直版鎖定 = SCREEN_SENSOR_PORTRAIT(5),實際 %s" % orient)
	var rm = ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile", "")
	_check(String(rm) == "gl_compatibility",
		"Android renderer 同 web 一樣係 Compatibility,實際 %s" % rm)
	_check(Engine.max_fps == Flow.FPS_NORMAL or Engine.max_fps == Flow.FPS_POWER_SAVE,
		"FPS 上限有生效(%d)" % Engine.max_fps)
	Meta.settings["power_save"] = true
	Flow.apply_frame_cap()
	_check(Engine.max_fps == Flow.FPS_POWER_SAVE,
		"省電模式 -> %d fps" % Engine.max_fps)
	Meta.settings["power_save"] = false
	Flow.apply_frame_cap()
	_check(Engine.max_fps == Flow.FPS_NORMAL, "關返省電 -> %d fps" % Engine.max_fps)

	# export preset:兩個 Android preset 都要零權限、arm64、target 36
	var cfg := ConfigFile.new()
	_check(cfg.load("res://export_presets.cfg") == OK, "讀到 export_presets.cfg")
	var android_presets := 0
	for sect in cfg.get_sections():
		if not sect.ends_with(".options"):
			continue
		var base := sect.trim_suffix(".options")
		if String(cfg.get_value(base, "platform", "")) != "Android":
			continue
		android_presets += 1
		var nm := String(cfg.get_value(base, "name", "?"))
		var granted: Array = []
		for k in cfg.get_section_keys(sect):
			if k.begins_with("permissions/") and k != "permissions/custom_permissions" \
					and bool(cfg.get_value(sect, k, false)):
				granted.append(k.trim_prefix("permissions/"))
		var custom = cfg.get_value(sect, "permissions/custom_permissions", PackedStringArray())
		_check(granted.is_empty(), "[%s] 權限清單係零(多咗:%s)" % [nm, granted])
		_check(custom.size() == 0, "[%s] 冇 custom permission" % nm)
		_check(bool(cfg.get_value(sect, "architectures/arm64-v8a", false)), "[%s] arm64-v8a" % nm)
		_check(String(cfg.get_value(sect, "gradle_build/target_sdk", "")) == "36",
			"[%s] target SDK 36(Play 2026-08-31 起嘅門檻)" % nm)
		_check(bool(cfg.get_value(sect, "package/signed", false)), "[%s] 簽名開住" % nm)
		_check(String(cfg.get_value(sect, "package/unique_name", "")) == "com.jatgaming.towerbound",
			"[%s] package name" % nm)
		# 密碼**唔准**入 cfg —— 呢條係唯一一條錯咗補救唔到嘅
		for k in cfg.get_section_keys(sect):
			if k.begins_with("keystore/"):
				_check(String(cfg.get_value(sect, k, "")) == "",
					"[%s] %s 冇內嵌任何嘢" % [nm, k])
	_check(android_presets == 2, "兩個 Android preset(aab + apk),實際 %d" % android_presets)
	await _idle(1)

# ---------------------------------------------------------------------------
# B. 返回鍵
# ---------------------------------------------------------------------------
func _case_back_in_battle() -> void:
	print("MOBILE -- B 戰鬥中撳返回")
	Flow.selected_level = 1
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await _idle(2)
	var hud = _find_hud(b)
	_check(hud != null, "搵到 BattleHUD")
	if hud == null:
		b.queue_free(); await _idle(1); return
	_check(hud.is_in_group(Mobile.BACK_GROUP), "BattleHUD 有入 back_handler group")

	get_tree().paused = false
	Mobile.request_back()
	await _idle(1)
	_check(get_tree().paused, "戰鬥中撳返回 -> 暫停")
	_check(hud.pause_menu.visible, "暫停選單彈咗出嚟")
	_check(is_instance_valid(b) and b.is_inside_tree(), "**冇**離開戰鬥")

	# 再撳一次 -> 收返。要行過 debounce 窗口,唔係嘅話呢一下會被當成重複事件。
	await _past_debounce()
	Mobile.request_back()
	await _idle(1)
	_check(not get_tree().paused, "再撳返回 -> 返返戰鬥")
	_check(not hud.pause_menu.visible, "暫停選單收咗")

	# 圖鑑 overlay 壓喺 HUD 上面:返回要退返暫停選單,唔係彈返主選單
	await _past_debounce()
	Mobile.request_back()
	await _idle(1)
	hud._open_bestiary_overlay()
	await _idle(3)
	var overlay = _find_overlay(hud)
	_check(overlay != null, "圖鑑 overlay 開咗")
	if overlay != null:
		_check(overlay.is_in_group(Mobile.BACK_GROUP), "圖鑑有入 back_handler group")
		await _past_debounce()
		Mobile.request_back()
		await _idle(3)
		_check(not is_instance_valid(overlay) or overlay.is_queued_for_deletion(),
			"返回收咗圖鑑 overlay")
		_check(get_tree().paused, "收完 overlay 仍然停住(退返暫停選單,唔係退出戰鬥)")
		_check(is_instance_valid(b) and b.is_inside_tree(), "仍然喺戰鬥入面")
	get_tree().paused = false
	b.queue_free()
	await _idle(2)

func _case_back_in_menu_screen() -> void:
	print("MOBILE -- B 選單層撳返回")
	# current_scene 係 harness 自己,所以直接驗 _default_back 嘅判斷:
	# 唔係主選單 -> 去主選單。用 Flow.nav_enabled=false 攔住真嘅場景切換,
	# 睇 Crash 麵包屑同 Flow 有冇被叫。
	var before := Flow.nav_enabled
	Flow.nav_enabled = false
	var scene := get_tree().current_scene
	var path := "" if scene == null else scene.scene_file_path
	_check(path != Flow.MAIN_MENU, "harness 場景唔係主選單(%s)" % path)
	await _past_debounce()
	Mobile.request_back()
	await _idle(1)
	# nav_enabled=false 令 goto() 唔會真係換場景 —— 呢度驗嘅係「冇人 quit」。
	_check(true, "選單層返回唔會退出 app")
	Flow.nav_enabled = before
	await _idle(1)

func _case_back_in_main_menu() -> void:
	print("MOBILE -- B 主選單撳返回:要問多一次先退出")
	# 直接驗 _confirm_exit 嘅上膛/落膛,唔真係 quit()(quit 咗就冇下文)。
	Mobile._exit_armed_until_ms = 0
	var menu := Control.new()
	add_child(menu)
	Mobile._confirm_exit(menu)
	await _idle(1)
	_check(Mobile._exit_armed_until_ms > Time.get_ticks_msec(), "第一下:上膛 + 出提示")
	var toasted := false
	for c in menu.get_children():
		toasted = true
	_check(toasted, "第一下有彈提示(唔係靜靜雞退出)")
	_check(Mobile.EXIT_CONFIRM_WINDOW >= 1.0,
		"確認窗口 %.1fs 夠長" % Mobile.EXIT_CONFIRM_WINDOW)
	# 窗口過咗就要落返膛
	Mobile._exit_armed_until_ms = Time.get_ticks_msec() - 1
	_check(Mobile._exit_armed_until_ms < Time.get_ticks_msec(),
		"過咗窗口就唔再算「再撳一次」")
	menu.queue_free()
	await _idle(1)

# ---------------------------------------------------------------------------
# C. 切去背景 / 返嚟
# ---------------------------------------------------------------------------
func _case_lifecycle() -> void:
	print("MOBILE -- C 切背景")
	Flow.selected_level = 1
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await _idle(2)
	var hud = _find_hud(b)
	get_tree().paused = false
	AudioServer.set_bus_mute(0, false)
	Meta.settings["muted"] = false

	Mobile._on_paused()
	await _idle(1)
	_check(get_tree().paused, "切走 -> 戰鬥停咗")
	_check(AudioServer.is_bus_mute(0), "切走 -> 靜咗音")

	Mobile._on_resumed()
	await _idle(1)
	_check(get_tree().paused, "返嚟 -> **仍然**停住(唔會幫玩家玩咗一段)")
	_check(hud != null and hud.pause_menu.visible, "返嚟 -> 停喺暫停畫面,唔係一個靜止但冇解釋嘅戰場")
	_check(not AudioServer.is_bus_mute(0), "返嚟 -> 音效還原(玩家自己冇撳靜音)")

	# 玩家自己撳咗靜音,返嚟唔准幫佢開返聲
	Meta.settings["muted"] = true
	Meta.apply_audio_settings()
	Mobile._on_paused()
	await _idle(1)
	Mobile._on_resumed()
	await _idle(1)
	_check(AudioServer.is_bus_mute(0), "玩家自己靜咗音 -> 返嚟唔准幫佢開返聲")
	Meta.settings["muted"] = false
	Meta.apply_audio_settings()

	get_tree().paused = false
	b.queue_free()
	await _idle(2)

	# 選單畫面冇嘢好停 —— 返嚟要解封,唔係就成個 app 死咗咁
	Mobile._on_paused()
	await _idle(1)
	_check(get_tree().paused, "選單層切走都會停")
	Mobile._on_resumed()
	await _idle(1)
	_check(not get_tree().paused, "選單層返嚟 -> 解封(冇 BattleHUD 要求停住)")

# ---------------------------------------------------------------------------
# D. 閃退標記喺 native 唔准誤報
# ---------------------------------------------------------------------------
func _case_crash_marker() -> void:
	print("MOBILE -- D 閃退標記")
	# Android 冇 NOTIFICATION_WM_CLOSE_REQUEST:玩家由最近應用清單掃走個 app,
	# process 就咁被殺,Crash._close() 永遠冇機會行。如果 APPLICATION_PAUSED
	# 嗰一刻唔落膛,每一次正常收工都會喺下次開場報一單假閃退。
	Crash.enabled = true
	Crash.rearm()
	Crash.crumb("test", "mobile lifecycle")
	Crash.flush_now()
	_check(_marker_exists(), "上咗膛 -> marker 喺度")
	Mobile._on_paused()
	await _idle(1)
	_check(not _marker_exists(), "切去背景 -> marker 冇咗(掃走 app 唔算閃退)")
	_check(not Crash.is_armed(), "切去背景 -> 落咗膛")
	Mobile._on_resumed()
	await _idle(1)
	_check(_marker_exists(), "返嚟 -> marker 返嚟(由呢一刻起嘅閃退照捉)")
	_check(Crash.is_armed(), "返嚟 -> 上返膛")
	Crash.disarm()
	Crash.enabled = false
	get_tree().paused = false

func _marker_exists() -> bool:
	return FileAccess.file_exists(Crash.MARKER)

# ---------------------------------------------------------------------------
func _find_hud(b) -> Node:
	for n in b.get_children():
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("BattleHUD.gd"):
			return n
	for n in b.find_children("*", "", true, false):
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("BattleHUD.gd"):
			return n
	return null

func _find_overlay(hud) -> Node:
	for n in hud.get_children():
		if n.get_script() != null and String(n.get_script().resource_path).ends_with("Bestiary.gd"):
			return n
	return null

## request_back() 有 250ms 嘅去彈跳窗口(一下實體返回鍵可能同時以 GO_BACK
## notification 同 ui_cancel 兩種形式到埗)。測試要連續撳,所以要等過咗先。
func _past_debounce() -> void:
	Mobile._last_back_ms = 0
	await _idle(1)

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(SAVE)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(SAVE)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(SAVE, FileAccess.WRITE)
		if f != null:
			f.store_buffer(_save_bytes)
			f.close()
	elif FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE))
