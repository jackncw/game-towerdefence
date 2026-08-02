extends Label
class_name DamageNumber
## Pooled floating damage / reward number.

var _vel: Vector2
var _life: float = 0.0
var _dur: float = 0.7
var _pool: Pool
var _was_big := false
const POP_DUR := 0.16
var _pop0: float = 1.0

func _ready() -> void:
	add_theme_font_size_override("font_size", 28)
	add_theme_color_override("font_outline_color", Color(0, 0, 0))
	add_theme_constant_override("outline_size", 6)
	z_index = 60
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func setup(pos: Vector2, txt: String, col: Color, pool: Pool, big := false) -> void:
	_pool = pool
	text = txt
	# scatter the spawn point + fan out sideways so an AoE volley never stacks
	# into an unreadable vertical column.
	position = pos - Vector2(40, 10) + Vector2(randf_range(-46, 46), randf_range(-26, 6))
	custom_minimum_size = Vector2(80, 0)
	size = Vector2(80, 0)
	pivot_offset = Vector2(40, 20)
	add_theme_color_override("font_color", col)
	# font size / outline changes force a full text re-shape, so only touch them
	# when this label is actually switching between the normal and big style
	if _was_big != big:
		_was_big = big
		add_theme_font_size_override("font_size", 46 if big else 28)
		add_theme_constant_override("outline_size", 8 if big else 6)
	_vel = Vector2(randf_range(-95, 95), (-120 if big else -95) + randf_range(-25, 25))
	_life = 0.0
	_dur = 0.85 if big else 0.6
	modulate.a = 1.0
	rotation = 0.0
	# pop-in: big crits punch bigger and settle. Driven by _life below rather than
	# a per-number Tween — an AoE volley at 3x spawns these by the hundred and the
	# Tween allocation cost dwarfed the label itself.
	_pop0 = 1.6 if big else 1.15
	scale = Vector2(_pop0, _pop0)

func _process(delta: float) -> void:
	_life += delta
	position += _vel * delta
	_vel.y += 120 * delta
	modulate.a = clampf(1.0 - _life / _dur, 0.0, 1.0)
	if _life < POP_DUR:
		var k := _life / POP_DUR
		var sc: float = lerpf(_pop0, 1.0, k * (2.0 - k))   # ease-out
		scale = Vector2(sc, sc)
	elif scale.x != 1.0:
		scale = Vector2.ONE
	if _life >= _dur and _pool:
		_pool.release(self)
