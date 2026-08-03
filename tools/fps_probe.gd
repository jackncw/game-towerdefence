extends Node
## 「個幀率上限係咪真係鎖到?」——喺一個真窗口度量三次。
##
## 點解唔可以用 mem_soak 嗰個負載嚟答:嗰個係合成最壞負載(40 座塔、3x、
## 魔法連放),喺開發機上面本來就跑 46-59fps,即係話個 60 上限根本未輪到佢
## 做約束。要睇個 cap 有冇用,就要揀一個**唔封頂會衝上去**嘅畫面 —— 而嗰啲
## 正正就係手機上面最耗電嘅場景:靜態選單同輕負載早關,GPU 冇嘢做就一路畫
## 到 120/144。
##
## 三段,每段 SEG_S 秒,同一個畫面:
##   1. max_fps = 0        —— 部機盡力跑到幾多
##   2. 遊戲預設 cap       —— 應該貼住 Flow.FPS_NORMAL
##   3. 省電模式 cap       —— 應該貼住 Flow.FPS_POWER_SAVE
##
## 用法(要開窗):
##   Godot --path . tools/fps_probe.tscn -- --scene=res://scenes/MainMenu.tscn --seconds=8

const SEG_S := 8.0

var scene_path := "res://scenes/MainMenu.tscn"
var seg := SEG_S

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--scene="):
			scene_path = a.substr(8)
		elif a.begins_with("--seconds="):
			seg = maxf(2.0, float(a.substr(10)))
	Crash.enabled = false
	Flow.nav_enabled = false
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	Meta.crystals = 999999
	var inst: Node = load(scene_path).instantiate()
	add_child(inst)
	for i in 10:
		await get_tree().process_frame

	var keep: bool = bool(Meta.settings.get("power_save", false))
	print("FPSPROBE scene=%s seg=%.0fs" % [scene_path, seg])

	Engine.max_fps = 0
	await _measure("解封頂 (max_fps=0)", 0)

	Meta.settings["power_save"] = false
	Flow.apply_frame_cap()
	await _measure("遊戲預設 cap", Flow.FPS_NORMAL)

	Meta.settings["power_save"] = true
	Flow.apply_frame_cap()
	await _measure("省電模式 cap", Flow.FPS_POWER_SAVE)

	Meta.settings["power_save"] = keep
	Flow.apply_frame_cap()
	print("FPSPROBE DONE")
	get_tree().quit(0)

## 量一段。頭一秒唔計 —— 換完 max_fps 之後主循環要幾幀先穩定落嚟。
func _measure(label: String, want: int) -> void:
	var t := 0.0
	while t < 1.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	var frames := 0
	var ms: Array = []
	t = 0.0
	while t < seg:
		await get_tree().process_frame
		var d := get_process_delta_time()
		t += d
		frames += 1
		ms.append(d * 1000.0)
	ms.sort()
	var p95: float = float(ms[mini(ms.size() - 1, int(ms.size() * 0.95))])
	var avg: float = float(frames) / t
	var verdict := ""
	if want > 0:
		verdict = "  -> %s (想要 <= %d)" % ["鎖到" if avg <= want + 3.0 else "冇鎖到", want]
	print("FPSPROBE %-18s max_fps=%-4d 實測 %6.1f fps  p95 %5.2f ms  (%d frames)%s"
		% [label, Engine.max_fps, avg, p95, frames, verdict])
