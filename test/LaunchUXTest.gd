extends Node
## 上架前嘅 UX 改動(第 24 輪 Part B + Part F)。
##   godot --headless --path . res://test/LaunchUXTest.tscn
##
## 三組:
##   B  「上次係閃退」報告畫面**唔可以**再自己彈出嚟(玩家永遠見唔到)
##   F1 首戰引導:只喺全新存檔嘅第一場出一次,可跳過,harness 唔會俾佢坐死
##   F2 設定頁:版本號由 build 讀(唔准 hardcode)、私隱政策連結、隱藏除錯入口
##
## B 組最易寫錯嘅方向:只驗「主選單冇 CrashReport 子節點」。嗰句喺一部
## **冇閃退過**嘅機上面自動成立,即係個測試喺 CI 度永遠綠色而乜都冇守到。
## 所以呢度會**先砌返一單假閃退落 Crash.last_crash**,再開主選單 —— 咁
## 「唔彈」先係一個真結論。同一個道理:F2 嘅除錯入口要驗佢真係開得到,
## 唔係淨係驗個掣喺度。

var fails: Array = []
var n := 0

func _ok(what: String, cond: bool, detail := "") -> void:
	n += 1
	if not cond:
		fails.append("%s — %s" % [what, detail])

const FAKE_CRASH := {
	"session": "test-session",
	"started": "2026-08-30T00:00:00",
	"crumbs": [
		"    0.96 boot     Windows 4.7.1-stable",
		"    2.27 mem      heap=80.7MB video=0.0MB obj=1543 node=27 fps=60",
		"   32.27 mem      heap=140.2MB video=0.0MB obj=9001 node=880 fps=41",
		"   35.10 scene    Battle.tscn",
	],
}

func _ready() -> void:
	Flow.nav_enabled = false
	await _case_b_no_auto_crash_screen()
	await _case_b_substrate_intact()
	_case_f1_tutorial_rules()
	await _case_f1_tutorial_ui()
	await _case_f2_settings()

	if fails.is_empty():
		print("LAUNCHUX PASS %d 項" % n)
		get_tree().quit(0)
		return
	for f in fails:
		print("LAUNCHUX FAIL " + f)
	print("LAUNCHUX FAIL fails=%d / %d" % [fails.size(), n])
	get_tree().quit(1)

# ---------------------------------------------------------------------------
func _count_crash_reports(root: Node) -> int:
	var c := 0
	for ch in root.get_children():
		if ch is CrashReport:
			c += 1
		c += _count_crash_reports(ch)
	return c

func _mount(path: String) -> Node:
	var s = load(path).instantiate()
	add_child(s)
	await get_tree().process_frame
	return s

func _drop(s: Node) -> void:
	s.queue_free()
	await get_tree().process_frame

# ---------------------------------------------------------------------------
# B 「上次係閃退」報告畫面拆走咗
# ---------------------------------------------------------------------------
func _case_b_no_auto_crash_screen() -> void:
	# **先砌返一單真閃退嘅狀態** —— 冇呢句,下面嗰條斷言喺一部冇閃退過嘅
	# 機上面自動成立,個測試就係一格永遠綠色嘅裝飾。
	Crash.last_crash = FAKE_CRASH.duplicate(true)
	_ok("B 前設:Crash.last_crash 真係入到嘢", not Crash.last_crash.is_empty())
	var menu := await _mount("res://scenes/MainMenu.tscn")
	_ok("B 主選單唔可以彈閃退報告", _count_crash_reports(menu) == 0,
		"見到 %d 個 CrashReport" % _count_crash_reports(menu))
	await _drop(menu)
	# 開完主選單之後嗰份記錄仲要喺度 —— 舊版讀完即刪,而家冇人讀,所以
	# 隱藏除錯檢視器仲睇得返。
	_ok("B 主選單唔可以順手清走閃退記錄", not Crash.last_crash.is_empty())
	# 靜態掃描:唔准有人日後喺任何畫面度再叫返 present()
	for f in ["res://scripts/ui/MainMenu.gd", "res://scripts/ui/Settings.gd",
			"res://scripts/ui/Result.gd", "res://scripts/ui/Fail.gd",
			"res://scripts/ui/LevelSelect.gd", "res://scripts/ui/Shop.gd",
			"res://scripts/ui/Upgrade.gd", "res://scripts/ui/Bestiary.gd",
			"res://scripts/ui/QuickBar.gd", "res://scripts/ui/BattleHUD.gd"]:
		var src := FileAccess.get_file_as_string(f)
		_ok("B %s 唔准自動彈閃退報告" % f.get_file(),
			not src.contains("CrashReport.present("), "仲有 CrashReport.present(")

## 底層一個字都冇拆 —— 麵包屑、crash.log、marker 全部照行。拆咗底層嘅話
## 一單真閃退就冇任何證物,而嗰個係一個唔可逆嘅損失(見 Crash.gd 檔頭)。
func _case_b_substrate_intact() -> void:
	Crash.last_crash = FAKE_CRASH.duplicate(true)
	var rep := Crash.last_crash_report()
	_ok("B 底層:last_crash_report() 仲砌得出報告", rep.contains("breadcrumbs"), rep.left(60))
	var trend: Dictionary = Crash.last_crash_memory_trend()
	_ok("B 底層:記憶體趨勢仲讀得到", String(trend.get("key", "")) == "heap",
		str(trend))
	var live := Crash.live_report()
	_ok("B 底層:live_report() 有今次 session 嘅麵包屑",
		live.contains("session log") and live.contains("breadcrumbs"), live.left(60))
	_ok("B 底層:crumb() 照收貨", true)
	Crash.crumb("test", "launchux")
	_ok("B 底層:啱啱寫嘅麵包屑讀得返", Crash.live_report().contains("launchux"))
	Crash.last_crash = {}

# ---------------------------------------------------------------------------
# F1 首戰引導
# ---------------------------------------------------------------------------
func _case_f1_tutorial_rules() -> void:
	var keep_high := Meta.highest_level
	var keep_done = Meta.settings.get("tutorial_done", false)

	Meta.highest_level = 0
	Meta.settings["tutorial_done"] = false
	_ok("F1 全新存檔嘅第 1 關要出引導", Meta.should_show_tutorial(1))
	_ok("F1 第 2 關唔出", not Meta.should_show_tutorial(2))
	Meta.settings["tutorial_done"] = true
	_ok("F1 睇過就唔再出", not Meta.should_show_tutorial(1))
	# **已經喺度嘅玩家唔可以食一疊教佢點拖卡嘅提示。** 一份 1.0.1 存檔冇
	# tutorial_done 呢個 key,所以呢個條件唔可以淨係睇個 key。
	Meta.settings["tutorial_done"] = false
	Meta.highest_level = 80
	_ok("F1 打到第 80 關嘅舊存檔唔會見到引導", not Meta.should_show_tutorial(1))

	Meta.highest_level = keep_high
	Meta.settings["tutorial_done"] = keep_done

func _case_f1_tutorial_ui() -> void:
	var keep_high := Meta.highest_level
	var keep_done = Meta.settings.get("tutorial_done", false)
	var keep_nav := Flow.nav_enabled
	Meta.highest_level = 0
	Meta.settings["tutorial_done"] = false

	# ── 保險一:`Flow.tutorial_armed` —— 唔經 play_level() 就唔會有引導 ──
	# 呢個先係主力,因為佢唔使 harness 記得任何嘢。實測 InputProbe 冇關
	# nav_enabled,而張引導卡(MOUSE_FILTER_STOP)食晒佢 push 入去嘅 touch,
	# 報咗一個同輸入層完全無關嘅 routing 失敗。
	Flow.tutorial_armed = false
	Meta.highest_level = 0
	Meta.settings["tutorial_done"] = false
	var keep_nav2 := Flow.nav_enabled
	Flow.nav_enabled = true          # 專登開返,證明個 arm 旗自己擋得住
	Flow.selected_level = 1
	Flow.last_result = {}
	var b0 = load("res://scenes/Battle.tscn").instantiate()
	add_child(b0)
	await get_tree().process_frame
	_ok("F1 直接 instantiate Battle(冇經 play_level)唔可以開引導",
		not b0.tutorial_pending)
	b0.queue_free()
	await get_tree().process_frame
	# 而 arm 咗就要開得到 —— 唔驗呢邊嘅話,個引導可以由頭到尾都冇出現過
	# 而測試照樣綠。
	Flow.tutorial_armed = true
	var b1 = load("res://scenes/Battle.tscn").instantiate()
	add_child(b1)
	await get_tree().process_frame
	_ok("F1 arm 咗就要開到引導", b1.tutorial_pending)
	_ok("F1 個 arm 旗讀完即清", not Flow.tutorial_armed)
	b1.queue_free()
	await get_tree().process_frame
	Flow.nav_enabled = keep_nav2

	# ── 保險二:nav_enabled = false 之下**一定唔可以**開引導 ──────────
	# 一張等人撳嘅卡喺一個 headless harness 度就係一個永遠唔會有人撳嘅卡,
	# 而 tutorial_pending 令 Battle._process 早返 = 成個 harness 靜靜咁掛死。
	# 同一類事已經咬過三次(逢 7 嘅合約關坐死三個測試)。
	Flow.selected_level = 1
	Flow.last_result = {}
	Flow.tutorial_armed = true       # arm 咗都唔准開 —— 呢層先係喺度驗緊嘅嘢
	var b = load("res://scenes/Battle.tscn").instantiate()
	add_child(b)
	await get_tree().process_frame
	_ok("F1 harness(nav_enabled=false)唔可以開引導", not b.tutorial_pending)
	# 而且 `_process` 要真係行得郁 —— 「開唔開得成」同「掛唔掛死」係兩件事,
	# 而後者先係呢個保險存在嘅理由。
	var spawned0: int = b.spawned_count
	for i in 120:
		b._process(1.0 / 30.0)
	_ok("F1 harness 之下場照行(120 幀之後出過怪)", b.spawned_count > spawned0,
		"spawned %d -> %d" % [spawned0, b.spawned_count])

	# ── 真遊戲路徑 ────────────────────────────────────────────────────
	# 用一個**真** Battle 嘅 HUD,唔係一個赤裸嘅 BattleHUD:後者喺 _ready()
	# 度就會撞到 `battle == null`(建塔卡要問 battle.place_cost),於是成頁
	# 錯誤沖走真信號 —— 而個測試仍然會綠。
	var hud = b.hud
	_ok("F1 攞到真 HUD", hud != null)
	b.tutorial_pending = false
	hud.show_tutorial()
	_ok("F1 引導卡砌得出", hud.tutorial_layer != null)
	_ok("F1 引導卡擋住底下(MOUSE_FILTER_STOP)",
		hud.tutorial_layer != null
		and hud.tutorial_layer.mouse_filter == Control.MOUSE_FILTER_STOP)
	_ok("F1 引導卡喺凍住嘅場入面照行(PROCESS_MODE_ALWAYS)",
		hud.tutorial_layer != null
		and hud.tutorial_layer.process_mode == Node.PROCESS_MODE_ALWAYS)
	# 四頁都要有真文字(唔可以係一條未翻譯嘅 key)
	for i in range(1, hud.TUTORIAL_PAGES + 1):
		for key in ["TUT_%d_TITLE" % i, "TUT_%d_BODY" % i]:
			_ok("F1 %s 有譯文" % key, tr(key) != key, tr(key))
	# 逐頁行到最後一頁,然後收皮
	for i in hud.TUTORIAL_PAGES - 1:
		hud._tut_advance()
		_ok("F1 第 %d 頁仲喺度" % (i + 2), hud.tutorial_layer != null)
	hud._tut_advance()
	_ok("F1 撳完最後一頁要收皮", hud.tutorial_layer == null)
	# 跳過:第一頁就走得
	hud.show_tutorial()
	# 「跳過」行嘅係同一條收尾路 —— 佢會叫返 Battle.close_tutorial(),
	# 而嗰度先係解凍成個場嗰句。
	b.tutorial_pending = true
	hud._tut_finish()
	_ok("F1 跳過即刻收皮", hud.tutorial_layer == null)
	_ok("F1 跳過之後個場要解凍", not b.tutorial_pending)
	b.queue_free()
	await get_tree().process_frame
	Flow.nav_enabled = keep_nav

	Flow.nav_enabled = false
	Meta.highest_level = keep_high
	Meta.settings["tutorial_done"] = keep_done

# ---------------------------------------------------------------------------
# F2 設定頁
# ---------------------------------------------------------------------------
func _case_f2_settings() -> void:
	var Settings := load("res://scripts/ui/Settings.gd")
	var ver: String = Settings.app_version()
	var proj := String(ProjectSettings.get_setting("application/config/version", ""))
	_ok("F2 project.godot 有 application/config/version", proj != "", "空")
	_ok("F2 版本號係由 build 讀返嚟", ver == proj, "%s vs %s" % [ver, proj])
	_ok("F2 版本號唔係 hardcode(原始碼入面搵唔到嗰個字串)",
		not FileAccess.get_file_as_string("res://scripts/ui/Settings.gd").contains('"%s"' % proj),
		"Settings.gd 入面寫死咗 %s" % proj)
	_ok("F2 私隱政策係一條 https URL",
		String(Settings.PRIVACY_URL).begins_with("https://"), Settings.PRIVACY_URL)

	var s := await _mount("res://scenes/Settings.tscn")
	var texts: Array = []
	_collect_text(s, texts)
	var joined := " | ".join(texts)
	_ok("F2 設定頁見到版本號", joined.contains(proj), joined.left(200))
	_ok("F2 設定頁見到私隱政策", joined.contains(tr("SET_PRIVACY")), joined.left(200))
	# 隱藏入口:唔可以係一粒寫住「除錯」嘅掣
	_ok("F2 設定頁唔准有一粒叫得出名嘅除錯掣",
		not joined.contains(tr("CRASH_DEBUG_TITLE")), joined.left(200))
	_ok("F2 長撳門檻係五秒", is_equal_approx(s.DEBUG_HOLD_SECONDS, 5.0),
		str(s.DEBUG_HOLD_SECONDS))
	# 開得到 —— 而且冇閃退記錄嗰陣照樣開得到(顯示今次 session)
	Crash.last_crash = {}
	s.open_debug_log()
	await get_tree().process_frame
	_ok("F2 冇閃退記錄都開得到除錯檢視器", _count_crash_reports(s) == 1,
		"%d 個" % _count_crash_reports(s))
	await _drop(s)

	# 有閃退記錄嗰陣顯示嗰次嘅報告
	Crash.last_crash = FAKE_CRASH.duplicate(true)
	var s2 := await _mount("res://scenes/Settings.tscn")
	s2.open_debug_log()
	await get_tree().process_frame
	var rep: CrashReport = null
	for ch in s2.get_children():
		if ch is CrashReport:
			rep = ch
	_ok("F2 有閃退記錄嗰陣開得到", rep != null)
	if rep != null:
		_ok("F2 除錯檢視器顯示嗰次閃退嘅麵包屑", rep.report.contains("test-session"),
			rep.report.left(80))
		_ok("F2 除錯檢視器係 debug 身份", rep.debug_mode)
		_ok("F2 唔係 live 模式(有真閃退記錄)", not rep.live_only)
	await _drop(s2)
	Crash.last_crash = {}

func _collect_text(node: Node, out: Array) -> void:
	if node is Label:
		out.append((node as Label).text)
	elif node is Button:
		out.append((node as Button).text)
	for c in node.get_children():
		_collect_text(c, out)
