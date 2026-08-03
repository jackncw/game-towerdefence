extends RefCounted
class_name Batch
## 合批小工具:起一個「一次 draw call 畫幾百件同款嘢」嘅 MultiMeshInstance2D。
##
## 點解要有呢個檔:呢個遊戲戰鬥高峰期量到一幀 1053 個 draw call,而入面最大
## 嗰幾嚿(每座塔嘅聖光光點、詛咒符文、火星、金幣、爆炸)全部都係「同一張圖、
## 同一個 material、得位置同顏色唔同」——即係 MultiMesh 嘅教科書情況。
##
## 用 ArrayMesh 自己砌四邊形而唔係 QuadMesh:QuadMesh 係 3D primitive,佢嘅
## UV 上下方向同 2D canvas 相反,而「圖上下倒轉」係一個好易寫出嚟又好難一眼
## 睇得出嘅 bug。自己砌就冇得含糊。

## 一塊 w x h 嘅四邊形,原點喺正中,UV 由 `uv0` 去 `uv1`。
##
## UV 要收得,係因為 **`MultiMeshInstance2D` 唔識 `AtlasTexture` 嘅 region**:
## 佢淨係攞底層 texture 去畫個 mesh,而 mesh 嘅 UV 0..1 指嘅係**成頁 atlas**。
## 呢個 bug 喺截圖對比度好認 —— 每一下爆炸變成一格格嘅細圖(即係成頁 atlas
## 塞咗入個爆炸嘅四邊形)。所以 region 要焗落 UV 度,由 `layer()` 代勞。
static func quad(w: float, h: float, uv0 := Vector2.ZERO, uv1 := Vector2.ONE) -> ArrayMesh:
	var verts := PackedVector3Array([
		Vector3(-w * 0.5, -h * 0.5, 0.0), Vector3(w * 0.5, -h * 0.5, 0.0),
		Vector3(w * 0.5, h * 0.5, 0.0), Vector3(-w * 0.5, h * 0.5, 0.0)])
	var uvs := PackedVector2Array([
		Vector2(uv0.x, uv0.y), Vector2(uv1.x, uv0.y),
		Vector2(uv1.x, uv1.y), Vector2(uv0.x, uv1.y)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

## 一層 MultiMesh。`tex` 決定四邊形嘅大細(1 texel = 1 world px @ scale 1),
## 所以呼叫端寫 scale 嗰陣諗嘅係「呢張圖要幾大」而唔係「個 mesh 有幾大」。
##
## `cap` 係一次過開定嘅 instance 上限 —— instance_count 改一次就重新配置一次
## buffer,而喺一個每幀特效數量都喺度跳嘅戰鬥入面,逐幀改 instance_count 就係
## 逐幀重新配置。改 visible_instance_count 先係平嗰個。
## `unit` = true 就用一塊 1x1 嘅四邊形,由呼叫端經 transform 嘅兩條軸決定形狀
## (閃電同碎片嗰啲一條一條嘅嘢用)。
static func layer(tex: Texture2D, cap: int, z: int, filter := CanvasItem.TEXTURE_FILTER_LINEAR, unit := false) -> MultiMeshInstance2D:
	# AtlasTexture 要拆返做「底圖 + UV 範圍」—— 見 quad() 上面嗰段。順帶一提
	# 咁樣做完之後所有 fx 層用嘅係**同一張**底圖,即係佢哋之間都批得埋。
	var base: Texture2D = tex
	var uv0 := Vector2.ZERO
	var uv1 := Vector2.ONE
	var w := float(tex.get_width())
	var h := float(tex.get_height())
	if tex is AtlasTexture:
		var at: AtlasTexture = tex
		base = at.atlas
		var aw := float(at.atlas.get_width())
		var ah := float(at.atlas.get_height())
		uv0 = Vector2(at.region.position.x / aw, at.region.position.y / ah)
		uv1 = Vector2(at.region.end.x / aw, at.region.end.y / ah)
		w = at.region.size.x
		h = at.region.size.y
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.mesh = quad(1.0, 1.0, uv0, uv1) if unit else quad(w, h, uv0, uv1)
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var node := MultiMeshInstance2D.new()
	node.multimesh = mm
	node.texture = base
	node.texture_filter = filter
	node.z_index = z
	return node

## 一個 instance 嘅 2D transform。分開一個 helper 係因為 Transform2D 有四個
## 唔同嘅 constructor,而揀錯嗰個(例如 (x_axis, y_axis, origin) 當成
## (rotation, scale, skew, position))唔會報錯,只會畫錯。
static func xform(pos: Vector2, sc: Vector2, rot := 0.0) -> Transform2D:
	return Transform2D(rot, sc, 0.0, pos)

## 由一條線段砌 transform:x 軸沿線段、y 軸係線寬。畫閃電同爆炸碎片用。
static func bar(p0: Vector2, p1: Vector2, width: float) -> Transform2D:
	var d := p1 - p0
	var l := d.length()
	if l < 0.0001:
		return Transform2D(0.0, Vector2.ZERO, 0.0, p0)
	var x := d / l
	return Transform2D(x * l, x.orthogonal() * width, (p0 + p1) * 0.5)
