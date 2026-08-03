extends Node
## 效能輪立咗嘅幾條不變式,寫成斷言。
##
## 點解值得有一個測試:呢幾樣嘢**壞咗係睇唔出嘅**。幀率上限唔見咗,遊戲照玩,
## 只係部電話熱返;`low_processor_usage_mode` 唔小心喺戰鬥度開咗,畫面照出,
## 只係高峰期掉幀。兩樣都唔會有人喺開發機上面察覺,直到有人喺電話上面玩耐咗。
##
## Run: godot --headless --path . res://test/PerfGuardTest.tscn

var _fails: Array = []

func _ready() -> void:
	Crash.enabled = false
	var keep: bool = bool(Meta.settings.get("power_save", false))

	# --- 1. 預設封 60 -------------------------------------------------------
	Meta.settings["power_save"] = false
	Flow.apply_frame_cap()
	_eq("預設幀率上限", Engine.max_fps, Flow.FPS_NORMAL)
	_ok("60 唔可以係 0(0 = 唔封頂,即係冇咗個 cap)", Flow.FPS_NORMAL > 0)

	# --- 2. 省電模式封 30 ---------------------------------------------------
	Meta.settings["power_save"] = true
	Flow.apply_frame_cap()
	_eq("省電模式幀率上限", Engine.max_fps, Flow.FPS_POWER_SAVE)
	_ok("省電模式一定要低過正常", Flow.FPS_POWER_SAVE < Flow.FPS_NORMAL)

	# --- 3. 設定讀返嚟仍然生效 ----------------------------------------------
	# 一個「今次開機生效、下次開機唔見咗」嘅慳電掣係最難察覺嗰種壞法。
	Meta.settings["power_save"] = false
	Flow.apply_frame_cap()
	Meta.settings["power_save"] = true
	Flow.apply_frame_cap()
	_eq("改完設定即刻生效", Engine.max_fps, Flow.FPS_POWER_SAVE)
	Meta.settings["power_save"] = keep
	Flow.apply_frame_cap()

	# --- 4. 戰鬥唔准讓 CPU --------------------------------------------------
	# low_processor_usage_mode 喺戰鬥度開咗 = 每個 loop iteration 白白瞓一覺,
	# 而戰鬥高峰期每一毫秒都要用嚟趕 16.7ms 個預算。
	Flow.set_idle_friendly(true)
	_ok("選單可以讓 CPU", OS.low_processor_usage_mode)
	Flow.set_idle_friendly(false)
	_ok("戰鬥一定唔讓 CPU", not OS.low_processor_usage_mode)

	# --- 5. FX / 傷害數字上限仲喺度 -----------------------------------------
	# 呢兩個 cap 係之前幾輪擋 frame spike 嘅嘢。冇人會特登刪佢,但一個
	# 「順手調大啲睇下靚啲」嘅改動就會靜靜雞放走 900 個逐幀重畫嘅節點。
	_ok("FX 硬上限 <= 400", Battle.FX_HARD_CAP <= 400)
	_ok("FX 軟上限 < 硬上限", Battle.FX_SOFT_CAP < Battle.FX_HARD_CAP)
	_ok("傷害數字硬上限 <= 150", Battle.DMG_HARD_CAP <= 150)
	_ok("傷害數字軟上限 < 硬上限", Battle.DMG_SOFT_CAP < Battle.DMG_HARD_CAP)

	if _fails.is_empty():
		print("PERFGUARD PASS fails=0")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("PERFGUARD FAIL " + f)
		print("PERFGUARD FAIL fails=%d" % _fails.size())
		get_tree().quit(1)

func _eq(what: String, got, want) -> void:
	if got != want:
		_fails.append("%s: 得 %s,想要 %s" % [what, str(got), str(want)])

func _ok(what: String, cond: bool) -> void:
	if not cond:
		_fails.append(what)
