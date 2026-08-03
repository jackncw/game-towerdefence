extends Node2D
class_name DamageNumber
## Pooled floating damage / reward number.
##
## 合批輪:呢個 class **由 `Label` 變成一件數據**。佢仲係 pooled、仲係跟同一
## 條拋物線同淡出曲線,但佢自己唔再畫 —— 畫嘅係 `DamageField`,一個 node 用
## `draw_string()` 畫晒成場。
##
## 點解:一個 `Label` 就係一個獨立嘅 CanvasItem,有自己嘅 transform、自己嘅
## `modulate`(淡出),而**逐個 item 嘅 modulate 會斷 batch**。量到滿場
## 150 個傷害數字 = 123 個 draw call,即係一個數字一個 draw call,係高峰戰鬥
## 入面第三大嗰嚿。而家淡出係傳去 `draw_string()` 嘅顏色參數,唔再係 item
## 嘅 modulate,所有字形共用同一張字型圖集,批得埋。
##
## 唯一保留唔到嘅係「彈出」嗰下放大:`draw_set_transform()` 一樣會斷 batch,
## 所以放大改為**用字級**表達,而字級量化到每 4 級一格再按格分組畫 —— 見
## DamageField.gd。

var vel: Vector2
var life: float = 0.0
var dur: float = 0.7
var text: String = ""
var col: Color = Color.WHITE
var big: bool = false
var _pool: Pool
const POP_DUR := 0.16
var _pop0: float = 1.0
## 畫嗰陣要嘅兩個數:而家嘅透明度同而家嘅放大倍率。
var alpha: float = 1.0
var pop: float = 1.0

func setup(pos: Vector2, txt: String, c: Color, pool: Pool, is_big := false) -> void:
	_pool = pool
	text = txt
	col = c
	big = is_big
	# scatter the spawn point + fan out sideways so an AoE volley never stacks
	# into an unreadable vertical column.
	position = pos - Vector2(40, 10) + Vector2(randf_range(-46, 46), randf_range(-26, 6))
	vel = Vector2(randf_range(-95, 95), (-120 if is_big else -95) + randf_range(-25, 25))
	life = 0.0
	dur = 0.85 if is_big else 0.6
	alpha = 1.0
	# pop-in: big crits punch bigger and settle. Driven by `life` below rather than
	# a per-number Tween — an AoE volley at 3x spawns these by the hundred and the
	# Tween allocation cost dwarfed the label itself.
	_pop0 = 1.6 if is_big else 1.15
	pop = _pop0

func _process(delta: float) -> void:
	life += delta
	position += vel * delta
	vel.y += 120 * delta
	alpha = clampf(1.0 - life / dur, 0.0, 1.0)
	if life < POP_DUR:
		var k := life / POP_DUR
		pop = lerpf(_pop0, 1.0, k * (2.0 - k))   # ease-out
	else:
		pop = 1.0
	if life >= dur and _pool:
		_pool.release(self)
