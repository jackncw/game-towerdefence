extends Node
## Crash marker 嘅上膛 / 落膛邏輯。
##
## 點解要有一個 headless 測試,而唔係淨係喺瀏覽器度試:瀏覽器嗰邊驗嘅係
## 「事件有冇接到」,呢度驗嘅係「接到之後做得啱唔啱」。後者先係將來最容易
## 靜靜雞壞返嘅嘢 —— 例如有人喺 disarm 之後加一句 crumb(),而 crumb() 會
## 觸發 _maybe_flush(),於是個 marker 又寫返出嚟,誤報就返嚟咗。
##
## Run: godot --headless --path . res://test/CrashArmTest.tscn

var _fails: Array = []

func _ready() -> void:
	# 呢個測試要真係寫檔,所以唔可以照抄其他測試嗰句 Crash.enabled = false
	Crash.enabled = true
	Crash.rearm()
	Crash.crumb("test", "arm-test 開始")
	Crash.flush_now()
	_ok("開場之後 marker 應該喺度", _marker_exists())
	_ok("開場之後應該係上咗膛", Crash.is_armed())

	# --- disarm:marker 要即刻冇咗 -------------------------------------------
	Crash.disarm()
	_ok("disarm 之後 marker 要冇咗", not _marker_exists())
	_ok("disarm 之後係落咗膛", not Crash.is_armed())

	# --- 落咗膛之後再記麵包屑,唔准將 marker 寫返出嚟 ------------------------
	# 呢個係最容易 regress 嘅一條。切走之後遊戲仲會繼續派麵包屑(暫停、存檔、
	# 音效還原),而其中任何一句 crumb() 都會叫 _maybe_flush()。
	Crash.crumb("test", "落咗膛之後嘅麵包屑")
	Crash.flush_now()
	_ok("落咗膛之後 crumb+flush 都唔准寫返 marker", not _marker_exists())

	# --- rearm:marker 要返嚟(bfcache 恢復嘅 tab 會繼續玩) ------------------
	Crash.rearm()
	_ok("rearm 之後 marker 要返嚟", _marker_exists())
	_ok("rearm 之後係上返膛", Crash.is_armed())

	# --- 麵包屑冇斷 ----------------------------------------------------------
	# disarm 期間淨係唔寫檔,唔係唔記錄 —— 唔係嘅話「切走之前做過乜」
	# 呢一段就會喺報告入面消失,而嗰段正正係最有用嗰段。
	var txt := FileAccess.get_file_as_string(Crash.MARKER)
	_ok("落咗膛期間嘅麵包屑仍然要喺 rearm 之後嘅 marker 入面",
		txt.find("落咗膛之後嘅麵包屑") >= 0)

	# --- 正常收場 ------------------------------------------------------------
	Crash._close()
	_ok("_close() 之後 marker 要冇咗", not _marker_exists())

	if _fails.is_empty():
		print("CRASHARM PASS fails=0")
		get_tree().quit(0)
	else:
		for f in _fails:
			print("CRASHARM FAIL " + f)
		print("CRASHARM FAIL fails=%d" % _fails.size())
		get_tree().quit(1)

func _marker_exists() -> bool:
	return FileAccess.file_exists(Crash.MARKER)

func _ok(what: String, cond: bool) -> void:
	if not cond:
		_fails.append(what)
