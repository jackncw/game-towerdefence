extends Node
## 第二十輪 —— 守住「塔 / 魔法圖唔會靜靜雞俾程序生成嘅舊圖冚返」。
##
##   godot --headless --path . res://test/TowerArtTest.tscn
##
## 點解要一個測試去守呢件事:`gen_art.py` 嘅 `main()` 只要有人加返一行
## `gen_towers()`,60 張手繪塔圖就會一次過變返舊嗰套 44px 程序圖,而且
## **完全冇錯誤訊息** —— 遊戲照行,測試照過,淨係美術倒退咗一整輪。
## round-19 怪物嗰輪食過同一劑,所以呢一輪一開始就落閘。
##
## 五條:
##   A 尺寸    60 張塔圖一律 128 高(tower_cutout.py 嘅 CANVAS)。舊程序圖係
##             44x44,所以呢條一冚就即刻紅。
##   B 接地線  同一座塔三個 tier 嘅實心底邊要對齊(±2px)。錯咗 = 進化跳位。
##   C 錨點    TOWER_RENDER x 畫布 = 88px 顯示闊度,同接地點喺 node 之下 42px
##             —— 呢兩個數就係射程圈 / 選中光圈 / ghost 對得正嘅前提。
##   D 魔法    41 張新 icon 一律 64x64;淨低嗰四格(待補清單)仍然係 44x44。
##             呢條同時守住反方向:有人一次過重出 45 張,新 icon 全冇咗。
##   E 通透    每張圖都要有真.透明像素。摳圖漏咗 alpha 嘅話會出一個綠色方框。

const CANVAS_H := 128
const GROUND_Y := 125
const NEW_SPELL := 64
const OLD_SPELL := 44
## 待補清單 —— 2026-08-07 收官輪清零(四張補圖由 magic_cutout.py 嘅 SINGLES
## 摳入遊戲)。同 tools/magic_cutout.py 嘅 MISSING、gen_art.py 嘅
## PROCEDURAL_SPELLS 一致,三處要一齊改。留住個常數係為咗
## (a) 將來再有格對唔到號嗰陣有位寫,(b) 下面 _case_spell_all_new() 會斷言
## 佢係空 —— 即係「唔准偷偷退返去程序圖」呢條規則有人守。
const STILL_PROCEDURAL: Array = []

var fails: Array[String] = []
var checked := 0

func _ready() -> void:
	_case_tower_size()
	_case_ground_line()
	_case_anchor()
	_case_spell_size()
	_case_spell_all_new()
	if fails.is_empty():
		print("TowerArtTest: PASS (%d 項)" % checked)
		get_tree().quit(0)
		return          # quit() 只係「請求」退出,唔加呢句會照行落去印埋 FAIL 嗰行
	for f in fails:
		print("  FAIL " + f)
	print("TowerArtTest: FAIL (%d / %d)" % [fails.size(), checked])
	get_tree().quit(1)

func _ok(what: String, cond: bool) -> void:
	checked += 1
	if not cond:
		fails.append(what)

## 由原檔(唔經 atlas)攞返實際像素 —— atlas 入面已經 extrude 過,量錯位。
func _img(path: String) -> Image:
	var t: Texture2D = load(path)
	return null if t == null else t.get_image()

func _solid_bottom(img: Image) -> int:
	for y in range(img.get_height() - 1, -1, -1):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				return y
	return -1

func _case_tower_size() -> void:
	for id in range(1, 21):
		for tier in range(1, 4):
			var p := "res://assets/generated/towers/tower_%d%s.png" % [
				id, "" if tier == 1 else "_t%d" % tier]
			var img := _img(p)
			_ok("塔 %d t%d 讀唔到" % [id, tier], img != null)
			if img == null:
				continue
			_ok("塔 %d t%d 高度要 %d,而家 %d —— 44 嘅話就係俾 gen_towers() 冚返舊圖"
				% [id, tier, CANVAS_H, img.get_height()], img.get_height() == CANVAS_H)
			var has_clear := false
			for y in [0, 2]:
				for x in [0, img.get_width() - 1]:
					if img.get_pixel(x, y).a < 0.02:
						has_clear = true
			_ok("塔 %d t%d 四角冇透明像素 —— 摳圖漏咗 alpha" % [id, tier], has_clear)

func _case_ground_line() -> void:
	for id in range(1, 21):
		var gs: Array = []
		for tier in range(1, 4):
			var img := _img("res://assets/generated/towers/tower_%d%s.png" % [
				id, "" if tier == 1 else "_t%d" % tier])
			if img != null:
				gs.append(_solid_bottom(img))
		if gs.size() != 3:
			continue
		var spread: int = int(gs.max()) - int(gs.min())
		_ok("塔 %d 三個 tier 嘅接地線散開咗 %d px(%s)—— 進化會跳位"
			% [id, spread, str(gs)], spread <= 2)
		_ok("塔 %d 接地線 %s 唔喺 %d 附近 —— 射程圈 / 選中光圈會對唔正"
			% [id, str(gs), GROUND_Y], absi(int(gs[0]) - GROUND_Y) <= 2)

func _case_anchor() -> void:
	# 呢三個數綁死:改一個冇改另外兩個,全場塔即刻大細錯 / 浮起或者陷落地面。
	var disp: float = CANVAS_H * GameData.TOWER_RENDER
	_ok("128 x TOWER_RENDER 要等於 88px 顯示尺寸,而家 %.2f" % disp,
		is_equal_approx(disp, 88.0))
	var foot: float = (GROUND_Y - CANVAS_H / 2.0) * GameData.TOWER_RENDER
	_ok("接地點要喺 node 之下 42px(舊圖 43/44 嗰個位),而家 %.2f" % foot,
		absf(foot - 42.0) <= 1.0)

func _case_spell_size() -> void:
	for id in range(1, 16):
		for tier in range(1, 4):
			var img := _img("res://assets/generated/spells/spell_%d%s.png" % [
				id, "" if tier == 1 else "_t%d" % tier])
			_ok("魔法 %d t%d 讀唔到" % [id, tier], img != null)
			if img == null:
				continue
			var want: int = OLD_SPELL if STILL_PROCEDURAL.has([id, tier]) else NEW_SPELL
			_ok("魔法 %d t%d 要 %dpx,而家 %dpx%s" % [id, tier, want, img.get_width(),
				"" if want == NEW_SPELL else "(呢格喺待補清單,應該仲係舊圖)"],
				img.get_width() == want)
			# 手繪 icon 一定有透明角(圓角 badge)。程序圖係四四方方填滿,
			# 所以呢一項就係「有冇被 gen_art 冚返轉頭」嘅獨立證據 —— 唔靠
			# 尺寸,因為將來有人改咗 44 -> 64 再畫程序圖就呃得過上面嗰項。
			if want == NEW_SPELL:
				_ok("魔法 %d t%d 四隻角應該透明(手繪 badge 圓角)" % [id, tier],
					img.get_pixel(0, 0).a < 0.5
					and img.get_pixel(img.get_width() - 1, 0).a < 0.5)

## 待補清單清零之後,「唔准退返程序圖」變成一條可以斷言嘅規則。
func _case_spell_all_new() -> void:
	_ok("待補清單應該係空,而家仲有 %d 格" % STILL_PROCEDURAL.size(),
		STILL_PROCEDURAL.is_empty())
