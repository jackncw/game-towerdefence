extends Node2D
class_name FxRender
## 全部特效嘅**畫**都喺呢度,一個 node 畫晒成場。
##
## 點解要抽出嚟:舊版每一個 `Fx` 都係一個有 `_draw()` 嘅 Node2D,每幀
## `queue_redraw()` 再畫 3-20 個 primitive。喺 Godot 嘅 2D renderer 入面,
## **矩形(sprite)先批得埋,polygon / polyline 每一個都係自己一個 draw call**,
## 而 ring / burst / orb / spark 全部係圓同弧 —— 即係 polygon。高峰戰鬥有
## 400 個 fx 同時存在,量到佢哋佔 154 個 draw call。
##
## 而家一個 fx = 幾個 MultiMesh instance(或者幾條 multiline 線段),而
## MultiMesh 一層 = **一個** draw call,唔理入面有一個定四百個 instance。
##
## 一個貫穿全個檔嘅手法:顏色由 instance color 帶,貼圖淨係帶形狀同**相對**
## alpha。例如爆炸嘅煙圈原本係 `Color(col.r*0.35, col.g*0.30, col.b*0.30,
## a*0.42)`,貼圖嗰個像素就烘 (0.35, 0.30, 0.30, 0.42),乘上 instance color
## (col.rgb, a) 之後同原式一模一樣 —— 一張貼圖服務得晒所有顏色嘅爆炸。
##
## 一個 fx 唔再有自己嘅 `_draw()`;`Fx` 而家淨係一件**數據**(位置、壽命、
## 顏色),睇 Fx.gd 個註解。

## 各層嘅 instance 上限。Battle.FX_HARD_CAP 係 400,而一個爆炸最多用
## 1 個本體 + 1 個核心 + 4 條碎片,所以碎片層要 4 倍。
const CAP := 420
const BAR_CAP := 1720

## 圓環用幾多段。同舊版 `draw_arc(..., 32, ...)` 一樣,所以幾何完全一致。
const RING_SEG := 32

var pool: Pool

var _spark: MultiMeshInstance2D
var _spark_hi: MultiMeshInstance2D
var _coin: MultiMeshInstance2D
var _coin_hi: MultiMeshInstance2D
var _burst: MultiMeshInstance2D
var _burst_core: MultiMeshInstance2D
var _bar: MultiMeshInstance2D
var _orb: MultiMeshInstance2D
var _lines: _LineDraw

## 單位圓上嘅 32 個方向,起一次就唔使逐幀行 32 次 cos/sin。
var _unit: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	_unit.resize(RING_SEG + 1)
	for i in RING_SEG + 1:
		var a: float = TAU * float(i) / float(RING_SEG)
		_unit[i] = Vector2(cos(a), sin(a))
	# 畫嘅次序 = 加入嘅次序(全部同一個 z)。舊版 fx 之間嘅次序係「邊個先由
	# pool 攞出嚟」,即係本來就冇特定次序,所以任何一個固定次序都成立。
	_orb = Batch.layer(Assets.fx("orb"), CAP, 0)
	_burst = Batch.layer(Assets.fx("burst"), CAP, 0)
	_burst_core = Batch.layer(Assets.fx("burst_core"), CAP, 0)
	_bar = Batch.layer(Assets.fx("bar"), BAR_CAP, 0, CanvasItem.TEXTURE_FILTER_LINEAR, true)
	_lines = _LineDraw.new()
	_lines.owner_render = self
	_spark = Batch.layer(Assets.fx("spark"), CAP, 0)
	_spark_hi = Batch.layer(Assets.fx("spark_hi"), CAP, 0)
	_coin = Batch.layer(Assets.fx("coin"), CAP, 0)
	_coin_hi = Batch.layer(Assets.fx("coin_hi"), CAP, 0)
	for n in [_orb, _burst, _burst_core, _bar, _lines, _spark, _spark_hi, _coin, _coin_hi]:
		add_child(n)

## 貼圖入面各自嘅「參考尺寸」(texture px)。sprite 嘅 scale = 想要嘅 world
## 尺寸 / 呢個數。寫死喺呢度而唔係散落各處,係因為佢哋同 gen_art.py 入面
## 嗰段 `gen_fx()` 係一對一綁死嘅 —— 改一邊唔改另一邊就會靜靜咁畫錯大細。
const SPARK_REF := 25.6      # spark.png / coin.png 嘅本體半徑
const BURST_REF := 100.0     # burst.png 嘅 br
const CORE_REF := 56.0       # burst_core.png 嘅半徑
const ORB_REF := 80.0        # orb.png 嘅 orr

func _process(_delta: float) -> void:
	if pool == null:
		return
	var n_spark := 0
	var n_coin := 0
	var n_burst := 0
	var n_core := 0
	var n_bar := 0
	var n_orb := 0
	_lines.begin()
	var mm_spark: MultiMesh = _spark.multimesh
	var mm_spark_hi: MultiMesh = _spark_hi.multimesh
	var mm_coin: MultiMesh = _coin.multimesh
	var mm_coin_hi: MultiMesh = _coin_hi.multimesh
	var mm_burst: MultiMesh = _burst.multimesh
	var mm_core: MultiMesh = _burst_core.multimesh
	var mm_bar: MultiMesh = _bar.multimesh
	var mm_orb: MultiMesh = _orb.multimesh
	var live: Dictionary = pool.live_map()
	for iid in live:
		var f: Fx = live[iid]
		var fr: float = f.life_frac()
		var a: float = 1.0 - fr
		var c := Color(f.col.r, f.col.g, f.col.b, a)
		match f.kind:
			Fx.Kind.SPARK:
				var rr2: float = f.radius * (1.0 - fr * 0.5)
				var sc := Vector2.ONE * (rr2 / SPARK_REF)
				var xf := Batch.xform(f.global_position, sc)
				if f.diamond:
					if n_coin < CAP:
						mm_coin.set_instance_transform_2d(n_coin, xf)
						mm_coin.set_instance_color(n_coin, c)
						mm_coin_hi.set_instance_transform_2d(n_coin, xf)
						mm_coin_hi.set_instance_color(n_coin, Color(1, 1, 1, a))
						n_coin += 1
				elif n_spark < CAP:
					mm_spark.set_instance_transform_2d(n_spark, xf)
					mm_spark.set_instance_color(n_spark, c)
					mm_spark_hi.set_instance_transform_2d(n_spark, xf)
					mm_spark_hi.set_instance_color(n_spark, Color(1, 1, 1, a))
					n_spark += 1
			Fx.Kind.BURST:
				var br: float = f.radius * (0.42 + fr * 0.85)
				if n_burst < CAP:
					mm_burst.set_instance_transform_2d(n_burst, Batch.xform(
						f.global_position, Vector2.ONE * (br / BURST_REF), f.jitter(3) * TAU))
					mm_burst.set_instance_color(n_burst, c)
					n_burst += 1
				var cr: float = br * (0.34 - fr * 0.24)
				if cr > 0.0 and n_core < CAP:
					mm_core.set_instance_transform_2d(n_core, Batch.xform(
						f.global_position, Vector2.ONE * (cr / CORE_REF)))
					mm_core.set_instance_color(n_core, Color(1, 1, 1, a))
					n_core += 1
				for i in 4:
					if n_bar >= BAR_CAP:
						break
					var a2: float = TAU * i / 4.0 + f.jitter(i + 40) * 1.2
					var v := Vector2(cos(a2), sin(a2))
					mm_bar.set_instance_transform_2d(n_bar, Batch.bar(
						f.global_position + v * br * 1.05,
						f.global_position + v * br * (1.15 + fr * 0.55), 4.0))
					mm_bar.set_instance_color(n_bar, Color(c.r, c.g, c.b, a * 0.7))
					n_bar += 1
			Fx.Kind.ORB:
				if n_orb < CAP:
					var orr: float = f.radius * (0.8 + fr * 0.35)
					mm_orb.set_instance_transform_2d(n_orb, Batch.xform(
						f.global_position, Vector2.ONE * (orr / ORB_REF), f.jitter(7) * TAU))
					mm_orb.set_instance_color(n_orb, c)
					n_orb += 1
			Fx.Kind.RING:
				_push_ring(f, fr, a)
			Fx.Kind.LINE:
				_push_bolt(f, fr, a)
	mm_spark.visible_instance_count = n_spark
	mm_spark_hi.visible_instance_count = n_spark
	mm_coin.visible_instance_count = n_coin
	mm_coin_hi.visible_instance_count = n_coin
	mm_burst.visible_instance_count = n_burst
	mm_core.visible_instance_count = n_core
	mm_bar.visible_instance_count = n_bar
	mm_orb.visible_instance_count = n_orb
	_lines.queue_redraw()

## 衝擊波圓環。三層(闊而淡嘅尾 / 本體 / 白色前沿)嘅**線寬係固定嘅**
## (11 / 5 / 2 px),郁嘅只係半徑 —— 所以佢烘唔到落一張貼圖度(放大貼圖
## 會連線寬一齊放大,而環嘅半徑喺一個 fx 嘅生命入面會脹大四倍)。
##
## 解法唔係 shader,係 `draw_multiline`:佢將**所有**線段砌成一個 polygon
## command,即係一個 draw call。三個固定線寬 = 三個 draw call,畫幾多個環
## 都係三個。幾何同 `draw_arc(..., 32, ...)` 逐點對逐點一樣。
func _push_ring(f: Fx, fr: float, a: float) -> void:
	var rr: float = f.radius * (0.35 + fr)
	var p: Vector2 = f.global_position
	_lines.ring(p, rr * 0.9, Color(f.col.r, f.col.g, f.col.b, a * 0.35), 0, _unit)
	_lines.ring(p, rr, Color(f.col.r, f.col.g, f.col.b, a), 1, _unit)
	_lines.ring(p, rr, Color(1, 1, 1, a * 0.55), 2, _unit)

## 閃電 / 光束。幾何早就喺 `Fx._build_jag()` 烘好(唔會 boil),呢度淨係
## 將佢推入對應線寬嘅桶。線寬跟住 fx 嘅參數同壽命變,所以要分桶 ——
## 量化到 0.5px 一格,實測落嚟同時存在嘅桶得十幾個。
func _push_bolt(f: Fx, fr: float, a: float) -> void:
	var jag: PackedVector2Array = f.jag()
	if jag.size() < 2:
		return
	var fade: float = 1.0 - fr * 0.4
	_lines.bolt(jag, Color(f.col.r, f.col.g, f.col.b, a * 0.30), f.width * 2.6 * fade)
	_lines.bolt(jag, Color(f.col.r, f.col.g, f.col.b, a), f.width * fade)
	_lines.bolt(jag, Color(1, 1, 1, a * 0.75), maxf(1.5, f.width * 0.35))

## 所有圓環同閃電嘅線都畫喺呢**一個** CanvasItem 度,再按線寬合併成
## multiline。分開一個 inner class 係為咗佢喺兄弟節點嘅次序度佔一個位,
## 即係「線」呢一層喺爆炸之上、火星之下 —— 一個固定嘅疊法。
class _LineDraw extends Node2D:
	## 三個固定嘅環線寬,同舊版 `Fx._draw()` 入面嗰三個 draw_arc 一樣。
	const RING_W := [11.0, 5.0, 2.0]
	var owner_render: FxRender
	var _rp: Array[PackedVector2Array] = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var _rc: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	## 線寬(×2 取整)-> 線段點 / 顏色
	var _bp: Dictionary = {}
	var _bc: Dictionary = {}

	func begin() -> void:
		for i in 3:
			_rp[i].clear()
			_rc[i].clear()
		_bp.clear()
		_bc.clear()

	func ring(centre: Vector2, r: float, col: Color, layer: int, unit: PackedVector2Array) -> void:
		if r <= 0.5:
			return
		var pts: PackedVector2Array = _rp[layer]
		var cols: PackedColorArray = _rc[layer]
		var base: int = pts.size()
		var n: int = FxRender.RING_SEG
		pts.resize(base + n * 2)
		cols.resize(cols.size() + n)
		var cbase: int = cols.size() - n
		for i in n:
			pts[base + i * 2] = centre + unit[i] * r
			pts[base + i * 2 + 1] = centre + unit[i + 1] * r
			cols[cbase + i] = col
		_rp[layer] = pts
		_rc[layer] = cols

	func bolt(jag: PackedVector2Array, col: Color, w: float) -> void:
		var key: int = maxi(1, int(round(w * 2.0)))
		if not _bp.has(key):
			_bp[key] = PackedVector2Array()
			_bc[key] = PackedColorArray()
		var pts: PackedVector2Array = _bp[key]
		var cols: PackedColorArray = _bc[key]
		var segs: int = jag.size() - 1
		var base: int = pts.size()
		pts.resize(base + segs * 2)
		var cbase: int = cols.size()
		cols.resize(cbase + segs)
		for i in segs:
			pts[base + i * 2] = jag[i]
			pts[base + i * 2 + 1] = jag[i + 1]
			cols[cbase + i] = col
		_bp[key] = pts
		_bc[key] = cols

	func _draw() -> void:
		for i in 3:
			if _rp[i].size() >= 2:
				draw_multiline_colors(_rp[i], _rc[i], RING_W[i], true)
		for key in _bp:
			var pts: PackedVector2Array = _bp[key]
			if pts.size() >= 2:
				draw_multiline_colors(pts, _bc[key], float(key) * 0.5, true)
