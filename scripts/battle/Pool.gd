extends RefCounted
class_name Pool
## Generic node pool. Nodes must implement pool_reset(...) via setup and be
## re-usable. Inactive nodes are hidden + process-disabled and kept parented.

var _free: Array = []
var _factory: Callable
var _parent: Node
# Instance ids currently sitting in _free. The double-release guard used to be
# `_free.has(n)` — a linear scan run on EVERY release, which with hundreds of
# pooled fx/damage numbers churning at 3x speed was O(n^2) per frame.
var _idle: Dictionary = {}
# Nodes currently handed out. Kept so a caller can ask "which live node is
# closest to expiring?" when the budget is full — without it, a full pool can
# only refuse, and refusing is how a 稜鏡塔 beam silently disappeared at 3x.
var _live: Dictionary = {}
var _made: int = 0

func _init(factory: Callable, parent: Node) -> void:
	_factory = factory
	_parent = parent

func acquire() -> Node:
	var n: Node
	if _free.is_empty():
		n = _factory.call()
		_parent.add_child(n)
		_made += 1
	else:
		n = _free.pop_back()
		_idle.erase(n.get_instance_id())
	if n is CanvasItem:
		n.visible = true
	n.process_mode = Node.PROCESS_MODE_INHERIT
	_live[n.get_instance_id()] = n
	return n

func release(n: Node) -> void:
	if n is CanvasItem:
		n.visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	var iid := n.get_instance_id()
	_live.erase(iid)
	if not _idle.has(iid):
		_idle[iid] = true
		_free.append(n)

## Nodes currently handed out, in no particular order.
func live_nodes() -> Array:
	return _live.values()

## 同上,但唔起一個新 Array —— 逐幀行一次幾百個 fx 嘅渲染迴圈用呢個,
## `values()` 每幀配置一個新 Array 出嚟就係逐幀垃圾。
func live_map() -> Dictionary:
	return _live

## 最早派出去嗰個仲未還嘅 node。Godot 嘅 Dictionary 保住插入次序,所以行第一個
## key 就係最舊 —— 唔使起一個 400 個元素嘅 Array 出嚟排序。
func oldest_live() -> Node:
	for iid in _live:
		return _live[iid]
	return null

func idle_count() -> int:
	return _free.size()

## Nodes handed out and not yet returned. Callers use this to budget cosmetic
## spawns instead of letting a busy frame grow the pool without limit.
func live_count() -> int:
	return _made - _free.size()

## Instantiate `n` nodes up front so a busy moment never pays for node creation
## + add_child inside the frame that needs them.
func prewarm(n: int) -> void:
	while _free.size() < n:
		var node: Node = _factory.call()
		_parent.add_child(node)
		_made += 1
		release(node)
