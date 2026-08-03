extends Node2D
class_name Fx
## Pooled short-lived visual effect: expanding ring, filled burst, or polyline
## (lightning/beam/chain). Purely cosmetic.
##
## Round-5 art pass: every effect used to be ONE flat shape — a burst was a
## plain translucent disc, a poison cloud was a solid green sticker and
## "lightning" was a smooth 3-segment polyline that read like a chart. They all
## sat a tier below the cel-shaded sprites. Now each kind is layered (core +
## mid + rim), lightning is jagged with a bright inner filament, and clouds are
## built from overlapping lumps so nothing reads as a vector primitive.
##
## 合批輪:**呢個 class 唔再畫嘢。** 佢淨係「一件仲生存緊嘅特效」嘅數據 ——
## 種類、位置、顏色、半徑、壽命。真正嘅畫喺 `FxRender`,佢每幀行一次全部
## live 嘅 fx,將佢哋砌成幾層 MultiMesh 同幾條 multiline。
##
## 點解要咁做:每個 fx 自己 `_draw()` 嗰陣,佢畫嘅係圓、弧、折線 —— 喺 Godot
## 嘅 2D renderer 入面 polygon **批唔埋**,一個就係一個 draw call。400 個 fx
## 同時存在量到 154 個 draw call;而家同一批嘢係 9 層,即係 9 個。

enum Kind { RING, BURST, LINE, ORB, SPARK }

var pool: Pool
var kind: int = Kind.RING
var col: Color = Color.WHITE
var _life: float = 0.0
var _dur: float = 0.35
var radius: float = 40.0
var pts: PackedVector2Array
var _jag: PackedVector2Array   # pre-jittered LINE geometry (see _build_jag)
var width: float = 4.0
var _vel: Vector2 = Vector2.ZERO
var _grav: float = 0.0
var diamond: bool = false
var _seed: int = 0

func _reset(p: Pool) -> void:
	_life = 0.0
	pool = p
	_seed = randi()

func ring(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.RING
	radius = r
	col = c
	_dur = dur
	_reset(p)

func burst(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.BURST
	radius = r
	col = c
	_dur = dur
	_reset(p)

func orb(pos: Vector2, r: float, c: Color, dur: float, p: Pool) -> void:
	global_position = pos
	kind = Kind.ORB
	radius = r
	col = c
	_dur = dur
	_reset(p)

func spark(pos: Vector2, vel: Vector2, r: float, c: Color, dur: float, p: Pool, grav := 340.0, dia := false) -> void:
	global_position = pos
	kind = Kind.SPARK
	radius = r
	col = c
	_vel = vel
	_grav = grav
	diamond = dia
	_dur = dur
	_reset(p)

func line(world_pts: PackedVector2Array, c: Color, w: float, dur: float, p: Pool) -> void:
	global_position = Vector2.ZERO
	kind = Kind.LINE
	pts = world_pts
	col = c
	width = w
	_dur = dur
	_reset(p)
	_build_jag()

## The jagged bolt geometry is FIXED for the life of the effect (that is the
## whole point of the deterministic _j() jitter — it must not boil). It used to
## be rebuilt inside _draw: a fresh PackedVector2Array plus a full subdivision
## pass per bolt PER FRAME, and with every gatling/beam/sniper/lightning tower
## drawing a bolt at 3x that was the busiest allocator in the battle.
func _build_jag() -> void:
	_jag = PackedVector2Array()
	if pts.size() < 2:
		return
	var idx := 0
	for i in range(pts.size() - 1):
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var n := (p1 - p0).orthogonal().normalized()
		var amp: float = minf(p0.distance_to(p1) * 0.16, 26.0)
		_jag.append(p0)
		for k in range(1, 4):
			idx += 1
			_jag.append(p0.lerp(p1, k / 4.0) + n * (_j(idx) - 0.5) * 2.0 * amp)
	_jag.append(pts[pts.size() - 1])

## 幾成壽命行咗 —— 0 = 啱啱出世,1 = 就快死。
func life_frac() -> float:
	return clampf(_life / maxf(0.0001, _dur), 0.0, 1.0)

## 提早收檔,把個 node 還返個 pool。特效預算爆咗嗰陣,一件重要嘅嘢(塔嘅主
## 攻擊光束)可以徵用最舊嗰個裝飾,而唔係自己靜靜唔畫。
func cut_short() -> void:
	_life = _dur
	if pool:
		pool.release(self)

func _process(delta: float) -> void:
	_life += delta
	if _life >= _dur:
		if pool:
			pool.release(self)
		return
	if kind == Kind.SPARK:
		global_position += _vel * delta
		_vel.y += _grav * delta
		_vel *= (1.0 - 2.0 * delta)   # air drag

## Deterministic per-instance jitter so a shape keeps its silhouette across
## frames instead of boiling (randf() every _draw would strobe).
func _j(i: int) -> float:
	var h := (_seed * 73856093) ^ (i * 19349663)
	return float(h & 1023) / 1023.0

## FxRender 讀嘅兩個窗口。爆炸嘅碎片角度同埋爆炸 / 氣團嘅隨機轉角都要用返
## **同一個** per-instance jitter,先至保住「每一下爆炸唔同樣」呢件事 ——
## 一張預繪貼圖本身係死嘅,變化係由呢度嚟。
func jitter(i: int) -> float:
	return _j(i)

func jag() -> PackedVector2Array:
	return _jag
