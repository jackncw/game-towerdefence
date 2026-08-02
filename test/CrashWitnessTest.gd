extends Node
## 閃退報告本身係咪一件**證物**。
##
## 點解要有:第二份真閃退報告(session 1785668463-98604)入面,55 分鐘、
## 30 幾個採樣,`static=` 每一次都係 `0.0MB`。量過之後確定咗成因唔喺遊戲度:
## `Performance.MEMORY_STATIC` 喺 release export template 之下係硬編碼 0
## (同一份 code 同一部機:debug 報 78.8MB 而且跟得住一舊 +4MB 嘅分配,
## release 報 0 而且分配咗 12MB 都唔郁)。
##
## 而 `Crash.last_crash_memory_trend()` parse 嘅正正就係 `static=`。即係話
## 第十一輪特登起嗰條「用嚟分 OOM 定被系統掉走」嘅記憶體曲線,喺**每一個
## 出街版本**入面都係一條貼住零嘅平線 —— 而佢喺畫面上面睇落同「記憶體好平穩」
## 一模一樣。一個永遠讀零嘅溫度計唔係讀數,係一個謊。
##
## 所以呢個測試守住兩件事:
##   1. 出街版報得出一個**真**嘅 heap 數(網頁版 = wasm linear memory)。
##   2. 攞唔到嗰陣要講「攞唔到」,唔可以印一個 0.0MB 扮數據。
##
##   godot --headless --path . res://test/CrashWitnessTest.tscn

var fails := 0

## 真嘢:上面嗰單閃退報告嘅麵包屑,原文照抄(採樣行同前後文各留幾條)。
## 用真報告而唔係自己砌一串,係因為呢個測試要答嘅問題就係「當時嗰份報告
## 講唔講到嘢」。
const REAL_CRUMBS := [
	"    0.28 boot     Web 4.7.1-stable (official)",
	"    0.41 mem      static=0.0MB video=31.3MB obj=1583 node=63 fps=1",
	"   30.41 mem      static=0.0MB video=45.9MB obj=2016 node=216 fps=60",
	"   34.71 battle   開場 lv=37 路線=0 家族=[\"treant\", \"slime\"]",
	"   60.42 mem      static=0.0MB video=49.0MB obj=2594 node=571 fps=60",
	"  120.45 mem      static=0.0MB video=49.3MB obj=2925 node=853 fps=50",
	"  180.52 mem      static=0.0MB video=49.2MB obj=3117 node=1048 fps=41",
	" 3047.38 mem      static=0.0MB video=50.8MB obj=2580 node=520 fps=60",
	" 3197.51 mem      static=0.0MB video=54.0MB obj=2150 node=216 fps=60",
	" 3287.53 mem      static=0.0MB video=55.4MB obj=2923 node=832 fps=60",
]

func _ready() -> void:
	Crash.enabled = false
	_case_real_report_says_something()
	_case_trend_names_its_series()
	_case_no_fake_zero()
	_case_live_line_has_real_memory()
	print("CRASHWITNESS %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func ok(cond: bool, what: String) -> void:
	if not cond:
		fails += 1
		print("  FAIL: " + what)

# ---------------------------------------------------------------------------
## 條曲線唔可以係一條平線。呢一單真閃退嘅記憶體**的確**一路向上(video 由
## 31.3 升到 55.4 而且一次都冇跌返),所以一份讀得到嘢嘅報告一定要見到佢升。
func _case_real_report_says_something() -> void:
	Crash.last_crash = {"crumbs": REAL_CRUMBS}
	var t: Dictionary = Crash.last_crash_memory_trend()
	var v: Array = t.get("values", [])
	ok(v.size() >= 5, "真報告要抽到起碼 5 個採樣點,而家 %d 個" % v.size())
	if v.size() < 2:
		return
	var lo: float = INF
	var hi: float = -INF
	for x in v:
		lo = minf(lo, float(x))
		hi = maxf(hi, float(x))
	ok(hi > lo, "條曲線係一條平線(全部 %.1f)—— 一個永遠讀同一個數嘅監測冇講到嘢" % lo)
	ok(hi > 0.0, "條曲線全部係零 —— 讀緊一個喺出街版硬編碼 0 嘅 monitor")
	ok(float(v[-1]) > float(v[0]), "最後一點應該高過第一點(31.3 -> 55.4)")

## 報告要講得出佢畫緊邊個數。一條冇名嘅曲線讀者冇得判斷佢信唔信得過。
func _case_trend_names_its_series() -> void:
	Crash.last_crash = {"crumbs": REAL_CRUMBS}
	var t: Dictionary = Crash.last_crash_memory_trend()
	ok(t.has("key"), "trend 要話返自己畫緊乜")
	ok(str(t.get("key", "")) != "", "trend 嘅名唔可以係空")
	ok(str(t.get("key", "")) != "static",
		"唔可以再畫 static —— 佢喺每一個出街版都係 0")

## 出街版嘅採樣行入面唔可以再有 `static=`。
##
## 唔係「唔好睇佢」咁簡單 —— 佢喺 release template 之下係硬編碼 0,即係話佢
## 每一次都會印一個 `static=0.0MB`,而嗰串字喺報告入面讀落去係「記憶體用得
## 好少」。一個假讀數比冇讀數更加壞,因為佢會令人收工。
##
## (`video=0.0MB` 唔喺呢條規則入面:headless 冇 renderer,嗰個零係真嘅。)
func _case_no_fake_zero() -> void:
	var line := Crash.mem_line()
	ok(line.find("static=") < 0,
		"mem_line() 仲印緊 static= —— 佢喺出街版永遠係 0:%s" % line)

## 每一行採樣都要起碼有一個**喺出街版真係郁得到**嘅記憶體數字。
func _case_live_line_has_real_memory() -> void:
	var line := Crash.mem_line()
	ok(line.find("heap=") >= 0, "採樣行要有 heap= —— 出街版嘅 heap 係唯一貼近 OOM 嗰個數")
	ok(line.find("video=") >= 0, "採樣行要有 video=")
	# headless 冇 renderer,video 一定係 0,所以呢度唔可以要求佢 > 0。
	# 但 heap 就一定要係一個真數或者一個明明白白嘅 "n/a"。
	var i := line.find("heap=")
	var rest := line.substr(i + 5).split(" ")[0]
	ok(rest == "n/a" or rest.ends_with("MB"),
		"heap= 之後要係一個 MB 數或者 n/a,而家係 '%s'" % rest)
	ok(rest != "0.0MB", "heap=0.0MB 係一個假數,攞唔到就要寫 n/a")
