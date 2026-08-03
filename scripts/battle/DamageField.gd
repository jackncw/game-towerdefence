extends Node2D
class_name DamageField
## 全場傷害數字喺呢一個 CanvasItem 度畫晒。
##
## 舊版每個數字係一個 `Label`。一個 Label = 一個 CanvasItem + 一個逐 item 嘅
## `modulate`(淡出用)+ 一個逐 item 嘅 `scale`(彈出用),而嗰兩樣都會斷
## batch —— 量到滿場 150 個數字 = 123 個 draw call。
##
## 而家:
##   * 淡出 → 傳去 `draw_string()` 嘅顏色參數(唔再係 item modulate)
##   * 彈出 → 用**字級**表達,而字級量化到每 4 級一格
##   * 同一格嘅數字一次過畫晒 —— 同一個字級 = 同一張字型圖集 = 一個 batch
##
## 描邊要行多一次(`draw_string_outline`),所以每一格係兩個 draw call:
## 先全部描邊,再全部字身。次序調轉(逐個數字「描邊+字身」)就等於打返轉頭
## 做返舊版嗰件事。

var pool: Pool

## 字級量化格。量化嘅係「比原本大咗幾多」而唔係字級本身,所以彈完之後
## 停低嗰個字級**一定啱返原數**(直接量化字級嘅話 46 會變成 48)。
## 每一格字級 Godot 都要開一張自己嘅字型圖集,所以格數直接寫落 VRAM。
## 普通數字彈幅細(×1.15)得兩格就夠;大字彈幅大(×1.6),用粗啲嘅格,
## 三格已經睇得出係一下「彈」。合共五個字級(原本兩個)。
const SIZE_STEP := 6
const SIZE_STEP_BIG := 12
const BASE_SIZE := 28
const BIG_SIZE := 46
const OUTLINE := 6
const BIG_OUTLINE := 8
## Label 嘅 pivot_offset 係 (40, 20),而佢闊 80 置中 —— 所以一個數字嘅
## 幾何中心喺 position + (40, 20),放大都係圍住嗰點。
const PIVOT := Vector2(40.0, 20.0)
const BOX_W := 80.0

var _font: Font
## 字級 -> 該格入面嘅數字
var _buckets: Dictionary = {}

func _ready() -> void:
	z_index = 60
	# 用返 Label 本來用嗰隻字型。**唔可以**用 ThemeDB.fallback_font ——
	# Godot 內建主題明文指定咗 Label 用 "Open Sans SemiBold",fallback_font
	# 由頭到尾冇被查過(呢個專案喺網頁版中文變豆腐格嗰次已經踩過一次)。
	_font = ThemeDB.get_default_theme().get_font("font", "Label")
	if _font == null:
		_font = ThemeDB.fallback_font

func _process(_delta: float) -> void:
	if pool != null:
		queue_redraw()

func _draw() -> void:
	if pool == null or _font == null:
		return
	for k in _buckets:
		(_buckets[k] as Array).clear()
	var live: Dictionary = pool.live_map()
	for iid in live:
		var d: DamageNumber = live[iid]
		var base: int = BIG_SIZE if d.big else BASE_SIZE
		var step: int = SIZE_STEP_BIG if d.big else SIZE_STEP
		var fs: int = base + int(round(float(base) * (d.pop - 1.0) / step)) * step
		# key 帶埋 big:兩種數字嘅描邊粗幼唔同,唔可以撈埋一格
		var key: int = fs * 2 + (1 if d.big else 0)
		if not _buckets.has(key):
			_buckets[key] = []
		(_buckets[key] as Array).append(d)
	for key in _buckets:
		var arr: Array = _buckets[key]
		if arr.is_empty():
			continue
		var fs: int = int(key) / 2
		var outline: int = BIG_OUTLINE if (int(key) % 2) == 1 else OUTLINE
		# 位置計一次,描邊同字身兩次都用返同一個 —— 兩次各計一次
		# get_string_size 就係逐幀量度成千次字串闊度。
		_pos.clear()
		for d in arr:
			_pos.append(_baseline(d, fs))
		for i in arr.size():
			var d: DamageNumber = arr[i]
			draw_string_outline(_font, _pos[i], d.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, fs, outline, Color(0, 0, 0, d.alpha))
		for i in arr.size():
			var d2: DamageNumber = arr[i]
			draw_string(_font, _pos[i], d2.text, HORIZONTAL_ALIGNMENT_LEFT,
				-1.0, fs, Color(d2.col.r, d2.col.g, d2.col.b, d2.alpha))

var _pos: Array[Vector2] = []

## `draw_string` 收嘅係**基線左端**,而 Label 收嘅係左上角。
##
## 兩件事要自己做返:
##   * 水平置中 —— **唔可以**靠 `draw_string` 嘅 `width` 參數。嗰個
##     `width` 係一個**裁切框**:一個 46 級嘅 "453" 闊過 80px,傳 80 落去
##     佢就會截走最尾嗰個位變成 "45"。舊版嗰個 Label 冇開 clip_text,
##     所以佢係**溢出**唔係裁切。所以呢度傳 -1(唔裁),自己量闊度置中。
##   * 垂直置中喺 pivot 上面,咁字級一大一細(彈出)嗰陣就係圍住同一點
##     脹縮,同舊版 `pivot_offset = (40, 20)` 嘅行為一致。
func _baseline(d: DamageNumber, fs: int) -> Vector2:
	var w: float = _font.get_string_size(d.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
	return Vector2(d.position.x + PIVOT.x - w * 0.5,
		d.position.y + PIVOT.y + _font.get_ascent(fs) - _font.get_height(fs) * 0.5)
