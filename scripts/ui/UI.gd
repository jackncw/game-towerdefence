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

## 快捷列幾何。BattleHUD 用佢排戰鬥底欄,QuickBar 用佢 1:1 畫預覽 —— 兩邊共用
## 同一份數,先至講得出「你喺設定畫面見到嘅就係戰鬥入面嗰行」。
##
## 102 高唔係就手揀嘅:塔 icon 60 + 4 上邊距 + 價錢行 26 = 90,而觸控目標最短邊
## 要 >=88,所以 102 同時滿足兩個限制又剩返少少呼吸位。7 格(6 塔槽 + 更多)
## 喺 1040 闊入面每格 141,夠位擺 60px icon 加一個四位數價錢。
const QUICK_RECT := Rect2(20, 1586, 1040, 102)
const QUICK_CELLS := 7        # 6 個塔槽 + 「更多」
const QUICK_GAP := 8.0

static func quick_cell_w() -> float:
	return (QUICK_RECT.size.x - (QUICK_CELLS - 1) * QUICK_GAP) / float(QUICK_CELLS)

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
	_click_sound(b)
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
	_click_sound(b)
	return b

## Every button built through this file clicks. Hooking it here rather than at
## each call site is the only way it stays true — there are ~90 buttons across
## the game and any new screen gets it for free.
static func _click_sound(b: BaseButton) -> void:
	b.pressed.connect(func(): Audio.play("ui_click"))

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

## `smooth` = 呢張圖係咪手繪圖(唔係像素美術)。
##
## 全場 UI 圖示一直行 NEAREST,因為佢哋係 gen_art.py 畫嘅像素 sticker,而顯示
## 尺寸大部分係源圖嘅整數倍。第十九 / 二十輪之後,怪物、塔、魔法三批已經換成
## 由 sprite sheet 摳出嚟嘅手繪圖,而佢哋喺 UI 度嘅顯示尺寸(60 / 84 / 88 /
## 128 / 176 / 264)對 128 或者 64 嚟講全部唔係整數倍 —— NEAREST 之下會逐格
## 食走成行像素,升級介面嗰個 264px 大圖尤其明顯。所以呢批要 LINEAR。
## 舊嘅程序像素圖就算擺喺 smooth 呼叫端都要行返 NEAREST。
##
## 呢個唔係潔癖:魔法 icon 有四格喺源圖度冇,仲行緊 gen_art.py 嗰套 44px
## 像素畫法(見 tools/magic_cutout.py 嘅 MISSING)。升級介面個展示位係
## 264px,44 x 6 啱啱好整數倍 —— NEAREST 之下佢係一張**銳利**嘅像素畫,
## 一行 LINEAR 就變一撻糊。新圖 64 / 128px 唔係整數倍,情況啱啱相反。
## 所以判斷唔可以淨係睇呼叫端,要睇嗰張圖本身係邊一代。
const _PIXEL_ART_MAX := 48

static func tex_rect(tex: Texture2D, size: Vector2, smooth := false) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = size
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var hand_drawn: bool = smooth and tex != null \
		and maxf(tex.get_size().x, tex.get_size().y) > _PIXEL_ART_MAX
	t.texture_filter = (CanvasItem.TEXTURE_FILTER_LINEAR if hand_drawn
		else CanvasItem.TEXTURE_FILTER_NEAREST)
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

## 一條 stat bar 佔幾高。Upgrade.box_height() 要同呢個數對齊,所以佢住喺呢度。
const STAT_BAR_H := 74
## 三段分區嘅底色。tier 1 最暗、tier 3 最亮 —— 一個「越後面越貴重」嘅漸變,
## 而唔係三隻分得出但冇次序嘅顏色。
const TIER_ZONE := [Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.17)]

## A labelled horizontal stat bar: [icon] name .......... value / gradient fill.
## frac (0..1) sets fill length (relative strength among peers). fill_tex picks
## the gradient (bar_gold9 / bar_green9 / bar_crystal9).
##
## `bands` = 呢件嘢每一階**滿課**落喺呢條刻度嘅邊(0..1),由細到大,長度
## MAX_TIER-1。有 bands 就會喺 track 底畫三段淺色分區 + 界線,所以一條 bar
## 除咗講「而家幾強」仲講埋「一階夠唔夠、仲有幾多段路」。空 = 唔畫。
## `tier` = 玩家而家嗰階,用嚟將佢自己嗰段分區畫光啲。
static func stat_bar(icon_name: String, name: String, value_txt: String,
		frac: float, fill_tex := "bar_gold9", width := 620,
		bands: Array = [], tier := 0) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(width, STAT_BAR_H if not bands.is_empty() else 62)
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
	var inner := width - 68.0
	# 分區喺 fill 之前入 track,所以佢哋永遠喺條 bar 下面 —— 佢哋係刻度,唔係數值。
	if not bands.is_empty():
		var edges: Array = [0.0]
		for b in bands:
			edges.append(clampf(float(b), 0.0, 1.0))
		edges.append(1.0)
		for i in range(edges.size() - 1):
			var x0: float = float(edges[i]) * inner
			var x1: float = float(edges[i + 1]) * inner
			if x1 - x0 < 0.5:
				continue
			var zone := ColorRect.new()
			zone.color = TIER_ZONE[mini(i, TIER_ZONE.size() - 1)]
			# 玩家而家嗰段亮啲:一條 bar 上面「你喺邊一段」係第一眼要答嘅問題。
			if tier == i + 1:
				zone.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.20)
			zone.position = Vector2(4 + x0, 3)
			zone.size = Vector2(x1 - x0, 12)
			zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
			track.add_child(zone)
	var fill := TextureRect.new()
	fill.texture = Assets.ui(fill_tex)
	fill.position = Vector2(4, 3)
	fill.size = Vector2(inner * clampf(frac, 0.03, 1.0), 12)
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	# 界線最後入,所以佢喺 fill 上面 —— 一條已經越過咗 tier 1 界線嘅 bar,
	# 條界線要仲睇得到,唔係嘅話「我過咗第一段」呢件事就冇咗。
	if not bands.is_empty():
		for b in bands:
			var tick := ColorRect.new()
			tick.color = Color(0.10, 0.08, 0.06, 0.85)
			tick.position = Vector2(4 + clampf(float(b), 0.0, 1.0) * inner - 1.0, 1)
			tick.size = Vector2(2, 16)
			tick.mouse_filter = Control.MOUSE_FILTER_IGNORE
			track.add_child(tick)
		for i in bands.size():
			var num := label(_ROMAN[mini(i + 1, _ROMAN.size() - 1)], 15, TEXT_DIM)
			num.position = Vector2(50 + 4 + clampf(float(bands[i]), 0.0, 1.0) * inner - 14, 58)
			num.size = Vector2(28, 16)
			num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(num)
	return row

const _ROMAN := ["", "I", "II", "III"]

## 階級徽章 —— 羅馬數字。tier 1 都畫:呢個徽章嘅位置係「面板標題旁」,
## 而喺嗰度「你係第一階」係一句有用嘅話(tier_pips 唔畫 tier 1 係因為佢貼喺
## 幾十張卡嘅角落,情況唔同)。
static func tier_badge(tier: int) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(64, 40)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", frame_box("card9", 12, 4, 2))
	p.size = Vector2(64, 40)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(p)
	var l := label(_ROMAN[clampi(tier, 1, 3)], 24,
		GOLD if tier >= 3 else (Color(0.85, 0.92, 1.0) if tier == 2 else PARCH))
	l.size = Vector2(64, 40)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	return wrap

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
	# The toast IS the game's refusal channel (魔晶不足, 冷卻中, 唔可以起喺呢度), so
	# the error sound belongs here and not at each of the call sites. A GOLD toast
	# is a notice, not a refusal, so it stays silent.
	if col != GOLD:
		Audio.play("ui_error")
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

## 階級星星。一粒 = tier 1(唔畫)、兩粒 = tier 2、三粒 = tier 3,貼喺卡嘅
## 右上角。
##
## 用星星唔用數字:呢個角落喺快捷槽度得 141px 闊,而一個「T2」要一個夠大先
## 讀得到嘅字級,搶咗塔 icon 嘅位。星星數得出,而且喺 3x 之下用餘光都分得到。
## tier 1 特登唔畫任何嘢 —— 三十五件嘢入面絕大部分成世都係 tier 1,而喺每一
## 張卡上面畫一粒「你冇進化過」嘅星等於將雜訊變成常態。
static func tier_pips(tier: int, size := 14.0) -> Control:
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tier <= 1:
		wrap.visible = false
		return wrap
	wrap.custom_minimum_size = Vector2(size * tier + 4.0 * (tier - 1), size)
	wrap.size = wrap.custom_minimum_size
	for i in tier:
		var p := tex_rect(Assets.ui("ic_star"), Vector2(size, size))
		p.position = Vector2(i * (size + 4.0), 0)
		p.modulate = Color(1.0, 0.88, 0.35) if tier >= 3 else Color(0.85, 0.92, 1.0)
		wrap.add_child(p)
	return wrap

## Brief horizontal shake (denied action feedback).
static func shake(node: Control) -> void:
	var x0: float = node.position.x
	var tw := node.create_tween()
	for i in 4:
		var dx: float = 14.0 * (1.0 - i / 4.0)
		tw.tween_property(node, "position:x", x0 + dx, 0.04)
		tw.tween_property(node, "position:x", x0 - dx, 0.04)
	tw.tween_property(node, "position:x", x0, 0.04)
