extends Node2D
class_name MonsterOverlay
## 全場怪物身上嘅「資訊層」——血條、詛咒印、詠唱環 —— 集中喺呢一個 node 畫。
##
## 舊版每隻怪喺自己 `_draw()` 度畫自己嗰條血條。表面睇落冇問題(一條血條
## 得兩個 `draw_rect`),但喺 Godot 嘅 2D renderer 度,一個 canvas item 嘅
## 繪圖指令同佢子 node 嘅 sprite 係**梅花間竹**排喺 render list 度:
##
##     怪1 血條 → 怪1 sprite → 怪2 血條 → 怪2 sprite → ...
##
## 每次由「矩形」轉去「貼圖」都斷一次 batch,所以 143 隻怪就係幾百次斷。
## 量到怪物身上嗰層佔咗高峰戰鬥 93 個 draw call。
##
## 而家血條全部喺呢個 node 一次過畫晒 —— 連續嘅 `draw_rect` 批得埋 ——
## 而怪物嗰邊 `Monster` 完全冇 `_draw()`,即係所有怪物 sprite 喺 render list
## 度變成連續一段。第二個好處係 `queue_redraw()` 由每幀 143 次變成 1 次。
##
## z 排喺怪物之上(21)。舊版一條血條係壓喺**自己**隻怪嘅 sprite 之下、
## 但喺**之前**嗰隻怪嘅 sprite 之上 —— 而怪物係 pooled,tree 次序係「邊個
## 先由池攞出嚟」,即係話舊版嗰個疊法本來就係隨機嘅。所以呢度揀咗一個
## 確定嘅答案:血條永遠睇得到。

var battle

var _marks: MultiMeshInstance2D
## curse_mark.png 係 64x96 代表 16x24 world px,而六角印嘅中心喺個框中心
## 下面 4 px。
const MARK_PX := 0.25
const MARK_OFFSET := -4.0

func _ready() -> void:
	z_index = 21
	_marks = Batch.layer(Assets.fx("curse_mark"), 200, 21)
	add_child(_marks)

func _process(_delta: float) -> void:
	if battle == null:
		return
	var mm: MultiMesh = _marks.multimesh
	var n := 0
	for m in battle.monsters:
		if not m.alive or m.curse_amp <= 0.0:
			continue
		if n >= mm.instance_count:
			break
		mm.set_instance_transform_2d(n, Batch.xform(
			m.global_position + Vector2(0, -m.size * 0.86 + MARK_OFFSET),
			Vector2.ONE * MARK_PX))
		mm.set_instance_color(n, Color.WHITE)
		n += 1
	mm.visible_instance_count = n
	queue_redraw()

func _draw() -> void:
	if battle == null:
		return
	# 先畫晒全部矩形(批得埋),之後先畫詠唱環嗰啲弧 —— 次序調轉嘅話每條
	# 血條同每個環就會梅花間竹,即係打返轉頭做返舊版嗰件事。
	for m in battle.monsters:
		if m.alive and not m.is_boss:
			_bar(m)
	for m in battle.monsters:
		if m.alive and m.channel_time > 0.0:
			_heal_cast(m)

func _bar(m) -> void:
	var frac: float = clampf(m.hp / m.max_hp, 0.0, 1.0)
	if frac >= 0.999 and m._heal_flash <= 0.0:
		return
	var o: Vector2 = m.global_position
	var w: float = m.size
	var y: float = o.y - m.size * 0.62
	var x: float = o.x - w * 0.5
	draw_rect(Rect2(x, y, w, 5), Color(0, 0, 0, 0.7))
	var col := Color(0.3, 0.9, 0.3)
	if frac < 0.3: col = Color(0.9, 0.25, 0.2)
	elif frac < 0.6: col = Color(0.95, 0.8, 0.2)
	# 視覺誠實: HP that came BACK is painted as a bright green cap on the bar that
	# fades out, so healing is never silent. Without it the bar just crept right
	# and the player read it as "my damage is doing nothing".
	if m._heal_flash > 0.0:
		var k: float = m._heal_flash / m.HEAL_FLASH_DUR
		var lift: float = 3.0 * k
		draw_rect(Rect2(x, y - lift, w * frac, 5 + lift * 2.0),
			Color(0.55, 1.0, 0.5, 0.35 + 0.45 * k))
	draw_rect(Rect2(x, y, w * frac, 5), col)

## The 詠唱 tell: a glowing ring that fills over the cast, drawn in green while
## the heal is still on the table and washing out to grey as damage eats it. A
## fully greyed ring means the cast will pay nothing.
func _heal_cast(m) -> void:
	var o: Vector2 = m.global_position
	var r: float = m.size * 0.85
	var k: float = 1.0 - clampf(m.channel_time / maxf(0.01, m.channel_total), 0.0, 1.0)
	var left: float = clampf(m.channel_heal / maxf(1.0, m.channel_heal0), 0.0, 1.0)
	var live := Color(0.45, 1.0, 0.42)
	var dead := Color(0.65, 0.65, 0.6)
	var col: Color = dead.lerp(live, left)
	draw_circle(o, r + 6.0, Color(live.r, live.g, live.b, 0.10 * left))
	draw_arc(o, r, 0.0, TAU, 40, Color(0, 0, 0, 0.45), 7.0)
	draw_arc(o, r, -PI * 0.5, -PI * 0.5 + TAU * k, 40, col, 5.0)
