extends RefCounted
class_name UI
## Shared UI styling helpers so every screen looks like one system and the two
## currencies are always colour-coded the same way.

## Warm palette (round-4 UI redo, after gameUI.jpg / upgradeUI.jpg): deep-brown
## wood + bronze/gold, parchment plates, warm cream text. Cool greys retired.
const GOLD := Color(1.0, 0.82, 0.28)
const CRYSTAL := Color(0.74, 0.52, 0.98)   # magic-currency accent (kept purple)
const BG := Color(0.11, 0.085, 0.065)      # deep warm brown-black
const PANEL := Color(0.30, 0.22, 0.15)
const PANEL_HI := Color(0.40, 0.29, 0.18)
const ACCENT := Color(0.46, 0.72, 0.40)    # warm green (confirm / go)
const TEXT := Color(0.97, 0.93, 0.83)      # warm cream
const TEXT_DIM := Color(0.78, 0.70, 0.58)  # muted parchment
const DANGER := Color(0.86, 0.38, 0.26)    # warm red
const PARCH := Color(0.82, 0.71, 0.51)     # parchment

static func _style(col: Color, radius := 12, border := 0, border_col := Color.BLACK) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border > 0:
		s.border_width_left = border
		s.border_width_right = border
		s.border_width_top = border
		s.border_width_bottom = border
		s.border_color = border_col
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s

# --- textured 9-patch theme (warm wood/bronze frames from assets/generated/ui)
# Each frame bakes its decoration inside a fixed border ring; the texture_margin
# MUST equal that ring width or the center smears. Looked up per texture here so
# call sites never have to know it (the `margin` arg is a fallback only).
const _TEX_MARGIN := {
	"panel9": 30, "panel_dark9": 30, "panel_parch9": 30,
	"btn9": 24, "btn_accent9": 24, "btn_danger9": 24,
	"banner_gold9": 24, "card9": 22, "slot9": 20, "bar_track9": 10,
}

static func frame_box(tex_name: String, margin := 18, cml := 20, cmt := 10,
		modulate := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = Assets.ui(tex_name)
	var tm: int = _TEX_MARGIN.get(tex_name, margin)
	s.texture_margin_left = tm
	s.texture_margin_right = tm
	s.texture_margin_top = tm
	s.texture_margin_bottom = tm
	s.content_margin_left = cml
	s.content_margin_right = cml
	s.content_margin_top = cmt
	s.content_margin_bottom = cmt
	s.modulate_color = modulate
	return s

# map a semantic colour to the matching stone-button texture set
static func _btn_tex_for(col: Color) -> String:
	if col == ACCENT: return "btn_accent9"
	if col == DANGER: return "btn_danger9"
	if col == GOLD: return "banner_gold9"
	return "btn9"

static func button(text: String, min_size := Vector2(200, 96), col := PANEL_HI, fs := 34) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	b.add_theme_constant_override("outline_size", 5)
	var tex := _btn_tex_for(col)
	b.add_theme_stylebox_override("normal", frame_box(tex))
	b.add_theme_stylebox_override("hover", frame_box(tex, 18, 20, 10, Color(1.18, 1.18, 1.18)))
	# keep the button's own colour when pressed (a shared brown "pressed" frame
	# turned a green confirm button brown mid-tap — a state/identity mismatch);
	# darken + inset instead so it still reads as "pushed in".
	b.add_theme_stylebox_override("pressed",
		frame_box(tex, 18, 20, 12, Color(0.62, 0.62, 0.66)))
	b.add_theme_stylebox_override("disabled", frame_box(tex, 18, 20, 10, Color(0.5, 0.5, 0.55)))
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.57, 0.62))
	return b

## Square icon button (top-bar controls). icon_name = a ui/*.png without extension.
static func icon_button(icon_name: String, size := Vector2(100, 100), col := PANEL_HI) -> Button:
	# dark stone base so the bright white icon reads with strong contrast
	var b := Button.new()
	b.custom_minimum_size = size
	b.add_theme_stylebox_override("normal", frame_box("card9", 16, 6, 6))
	b.add_theme_stylebox_override("hover", frame_box("card9", 16, 6, 6, Color(1.2, 1.2, 1.2)))
	b.add_theme_stylebox_override("pressed", frame_box("card9", 16, 6, 6, Color(0.72, 0.72, 0.78)))
	var isz := size * 0.58
	var ic := tex_rect(Assets.ui(icon_name), isz)
	ic.position = (size - isz) * 0.5
	b.add_child(ic)
	b.set_meta("icon", ic)
	return b

static func label(text: String, fs := 30, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

static func title(text: String, fs := 56) -> Label:
	var l := label(text, fs, TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	return l

static func panel_rect() -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", frame_box("panel9", 22, 24, 16))
	return p

## Recessed dark inner panel (stat blocks, headers).
static func panel_dark() -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", frame_box("panel_dark9", 20, 22, 14))
	return p

static func tex_rect(tex: Texture2D, size: Vector2) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

static func fullscreen_bg(root: Control, col := BG) -> void:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = col
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)

static func currency_row(coin_tex: Texture2D, amount: int, col: Color, fs := 34) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.add_child(tex_rect(coin_tex, Vector2(44, 44)))
	var l := label(str(amount), fs, col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	h.add_child(l)
	return h

## Light parchment plate (headers, stat sheet).
static func panel_parch() -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", frame_box("panel_parch9", 24, 26, 18))
	return p

## A labelled horizontal stat bar: [icon] name .......... value / gradient fill.
## frac (0..1) sets fill length (relative strength among peers). fill_tex picks
## the gradient (bar_gold9 / bar_green9 / bar_crystal9).
static func stat_bar(icon_name: String, name: String, value_txt: String,
		frac: float, fill_tex := "bar_gold9", width := 620) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(width, 62)
	var ic := tex_rect(Assets.ui(icon_name), Vector2(40, 40))
	ic.position = Vector2(2, 8)
	row.add_child(ic)
	var nm := label(name, 26, TEXT)
	nm.position = Vector2(50, 4)
	nm.size = Vector2(220, 34)
	row.add_child(nm)
	var val := label(value_txt, 26, GOLD)
	val.position = Vector2(width - 220, 4)
	val.size = Vector2(216, 34)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	val.add_theme_constant_override("outline_size", 4)
	row.add_child(val)
	# track
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", frame_box("bar_track9", 10, 4, 2))
	track.position = Vector2(50, 40)
	track.size = Vector2(width - 60, 18)
	row.add_child(track)
	var fill := TextureRect.new()
	fill.texture = Assets.ui(fill_tex)
	fill.position = Vector2(4, 3)
	fill.size = Vector2((width - 68) * clampf(frac, 0.03, 1.0), 12)
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	return row

## A gold MAX seal medallion.
static func badge_max(size := Vector2(72, 72)) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = size
	var seal := tex_rect(Assets.ui("badge_max"), size)
	wrap.add_child(seal)
	var t := label("MAX", 22, Color(0.35, 0.22, 0.05))
	t.size = size
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wrap.add_child(t)
	return wrap

## Floating warm toast near screen-top ("魔晶不足!還差 XX"). Attaches to `root`.
static func toast(root: Control, msg: String, col := DANGER) -> void:
	var p := panel_dark()
	p.add_theme_stylebox_override("panel", frame_box("banner_gold9", 22, 26, 14)
		if col == GOLD else frame_box("panel_dark9", 22, 26, 14))
	var l := label(msg, 32, TEXT)
	l.add_theme_color_override("font_color", col.lightened(0.3))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# a Panel is not a container, so without this the Label kept its own minimum
	# size at (0,0) and the text drew off the top-left of the plate
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	# measure instead of assuming a fixed advance per character: a 繁中 glyph is
	# ~1 em wide and a Latin one ~0.55 em, so the old length*24 sized the English
	# toast half again too wide
	var fnt: Font = l.get_theme_font("font")
	var w := 360.0
	if fnt != null:
		w = maxf(w, fnt.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x + 80.0)
	else:
		w = maxf(w, msg.length() * 24.0 + 80.0)
	w = minf(w, 1000.0)
	p.size = Vector2(w, 78)
	p.position = Vector2((1080.0 - w) * 0.5, 300)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.z_index = 200
	root.add_child(p)
	var tw := root.create_tween()
	tw.tween_property(p, "position:y", 240.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

## Shared menu backdrop: the warm ember-night art + a SOFT scrim gradient.
## Every non-battle screen uses this so they stop being flat single-colour voids
## (result was green, fail was maroon — two palette orphans) and so the backdrop
## never shows a hard seam where a scrim rectangle used to start.
## `glow` tints a soft band behind the title area (green on win, red on loss).
static func menu_backdrop(root: Control, glow := Color(0, 0, 0, 0)) -> void:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = Assets.ui("menu_bg")
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	if glow.a > 0.0:
		var g := TextureRect.new()
		g.texture = Assets.ui("scrim")
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.flip_v = true
		g.modulate = glow
		g.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(g)
	var scrim := TextureRect.new()
	scrim.texture = Assets.ui("scrim")
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(scrim)

## Title on a bronze banner plate (used to be bare floating text on some screens
## while others had a plate — this makes the header treatment one thing).
static func banner_title(text: String, y: float, w := 720.0, fs := 60) -> Control:
	var wrap := Control.new()
	wrap.position = Vector2((1080.0 - w) * 0.5, y)
	wrap.size = Vector2(w, 118)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", frame_box("banner_gold9", 24, 20, 8))
	p.size = Vector2(w, 118)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(p)
	var l := label(text, fs, Color(0.26, 0.15, 0.05))
	l.size = Vector2(w, 118)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	return wrap

## Themed slider. Godot's default HSlider is a flat grey square-cornered widget
## — the last unstyled cool-grey control left in the game.
static func slider(width := 560.0) -> HSlider:
	var sl := HSlider.new()
	sl.custom_minimum_size = Vector2(width, 60)
	# vertical content margin gives the track real height — at 2px it drew as a
	# hairline that read as an unfinished widget
	var track := frame_box("bar_track9", 10, 6, 10)
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_icon_override("grabber", Assets.ui("ic_star"))
	sl.add_theme_icon_override("grabber_highlight", Assets.ui("ic_star"))
	var fill := frame_box("bar_gold9", 10, 6, 9)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.add_theme_constant_override("center_grabber", 1)
	return sl

## Brief horizontal shake (denied action feedback).
static func shake(node: Control) -> void:
	var x0: float = node.position.x
	var tw := node.create_tween()
	for i in 4:
		var dx: float = 14.0 * (1.0 - i / 4.0)
		tw.tween_property(node, "position:x", x0 + dx, 0.04)
		tw.tween_property(node, "position:x", x0 - dx, 0.04)
	tw.tween_property(node, "position:x", x0, 0.04)
