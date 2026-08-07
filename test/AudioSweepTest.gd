extends Node
## 逐個播晒**每一個**音效檔,確認佢真係入到 mixer 響到。
##
## 點解 `AudioTest.gd` 唔夠:嗰個驗嘅係**系統**(bus 路由、去重、時間縮放),
## 用少數幾個代表性音效。呢度驗嘅係**素材** —— 65 個檔逐個由 QOA 解返出嚟、
## 餵入 mixer、真係混出非零樣本。一個爆咗嘅 `.sample`(或者一個 import 設定
## 改錯咗嘅檔)喺 AudioTest 度捉唔到,因為佢根本冇播過嗰個檔。
##
## 「真係響咗」點量:開一條自己嘅 bus,掛一個 `AudioEffectCapture`,播完
## 抽返實際混出嚟嗰啲樣本,睇最大振幅。呢個做法答嘅問題比「有冇播過」強 ——
## 一個解碼成功但全靜音嘅檔一樣捉得到 —— 而且喺 headless dummy 同真 WASAPI
## 兩個後端都穩定答到 65/65,所以佢入得 `run_tests.ps1`,開窗跑就順便驗埋
## 真後端。
##
## 探測階段用**最短**嗰個音效(55ms 嘅 ui_click)。一個連咁短都抽唔到樣本嘅
## 後端會令成個 sweep 報 SKIP,而唔係將五個最常聽到嘅短音效報做壞咗 ——
## 一個報錯嘢嘅測試比一個唔跑嘅測試差。
##
## 跑法:
##   Godot --headless --path . res://test/AudioSweepTest.tscn
##   Godot --path . res://test/AudioSweepTest.tscn        # 順便驗真音訊後端

const DIR := "res://assets/generated_audio/"

var fails: Array = []
var played: int = 0

## 自己開一條 bus,掛一個 `AudioEffectCapture`。唔改遊戲本身四條 bus 嘅任何
## 嘢 —— 呢個 harness 收工之後要將 AudioServer 還原返一模一樣。
const CAP_BUS := "SweepCapture"
var _capture: AudioEffectCapture
var _cap_idx: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().create_timer(300.0).timeout.connect(func():
		print("AUDIOSWEEP: TIMEOUT"); get_tree().quit(2))
	AudioServer.set_bus_mute(0, false)
	_make_capture_bus()

	var names := _all_sound_names()
	print("AUDIOSWEEP: 檔案 %d 個" % names.size())

	var p := AudioStreamPlayer.new()
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.bus = CAP_BUS
	add_child(p)
	await _idle(4)

	# 探針用**最短**嗰個音效,唔係第一個。一個「對長 BGM 答得到、對 55ms 短音
	# 答唔到」嘅驅動,如果用長音效探測就會通過探測,然後將五個最短亦即係玩家
	# 最常聽到嗰五個音效報做壞咗。
	var probe := _shortest(names)
	if await _peak(p, Audio.stream(probe)) <= 0.0:
		print("AUDIOSWEEP SKIP — 呢個音訊後端連 %s(%.0fms)都抽唔到樣本出嚟,"
			% [probe, Audio.stream(probe).get_length() * 1000.0]
			+ "答唔到呢條問題。")
		_drop_capture_bus()
		get_tree().quit(0)
		return

	for n in names:
		var st := Audio.stream(n)
		if st == null:
			fails.append("%s:載入唔到" % n)
			continue
		if st.get_length() <= 0.0:
			fails.append("%s:長度 0" % n)
			continue
		if await _peak(p, st) <= 0.0:
			fails.append("%s:混出嚟嘅樣本全部係 0(長度 %.3fs)" % [n, st.get_length()])
		else:
			played += 1

	print("AUDIOSWEEP: 播得到 %d / %d" % [played, names.size()])
	for f in fails:
		print("AUDIOSWEEP   FAIL %s" % f)
	_drop_capture_bus()
	print("AUDIOSWEEP %s fails=%d" % ["PASS" if fails.is_empty() else "FAIL", fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)

func _make_capture_bus() -> void:
	_cap_idx = AudioServer.bus_count
	AudioServer.add_bus(_cap_idx)
	AudioServer.set_bus_name(_cap_idx, CAP_BUS)
	# 靜音送去揚聲器嗰邊,但 capture 效果坐喺靜音之前,所以樣本照拎到。
	# 跑一次呢個測試唔應該嘈足二十秒。
	AudioServer.set_bus_mute(_cap_idx, true)
	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(_cap_idx, _capture)

func _drop_capture_bus() -> void:
	if _cap_idx >= 0 and _cap_idx < AudioServer.bus_count:
		AudioServer.remove_bus(_cap_idx)
	_cap_idx = -1

## 播一次,由 bus 上面嘅 `AudioEffectCapture` 抽返實際嘅輸出樣本,返最大振幅。
##
## **點解唔用 `get_playback_position()`**(試過,冇用):嗰個數係由音訊執行緒
## 按 mix block 更新嘅,而一個 55-90ms 嘅音效隨時喺兩次更新之間已經播完 ——
## 量過,同一份 code 連跑四次分別報 65/65、63/65、63/65、62/65,而每次「壞咗」
## 嘅係邊幾個都唔同。一個間歇性講大話嘅測試,比一個唔存在嘅測試更加浪費時間。
##
## `AudioEffectCapture` 坐喺 bus 鏈入面,拎到嘅係**真正被混出嚟嗰啲樣本**。
## 佢答嘅問題亦都強啲:唔單止「個 mixer 食過呢個 stream」,而係「呢個檔真係
## 出到聲」—— 一個解碼成功但全靜音嘅 `.sample` 一樣會被捉到。
func _peak(p: AudioStreamPlayer, st: AudioStream) -> float:
	_capture.clear_buffer()
	p.stream = st
	p.play()
	# 等夠 min(音效長度, 300ms) 加少少餘裕,俾音訊執行緒混完先讀。
	var want_ms := mini(300, maxi(60, int(st.get_length() * 1000.0))) + 80
	var deadline := Time.get_ticks_msec() + want_ms
	var peak := 0.0
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var n := _capture.get_frames_available()
		if n > 0:
			for v in _capture.get_buffer(n):
				peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
	p.stop()
	return peak

func _shortest(names: Array) -> String:
	var best := ""
	var best_len := INF
	for n in names:
		var st := Audio.stream(n)
		if st != null and st.get_length() > 0.0 and st.get_length() < best_len:
			best_len = st.get_length()
			best = n
	return best

func _all_sound_names() -> Array:
	var out: Array = []
	var d := DirAccess.open(DIR)
	if d == null:
		return out
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if f.ends_with(".wav"):
			out.append(f.get_basename())
		f = d.get_next()
	d.list_dir_end()
	out.sort()
	return out

func _idle(n: int) -> void:
	for i in n:
		await get_tree().process_frame
