extends Node
## Regression test for "網頁版畫面拉長失真".
##
## The bug had two halves, both of which this guards:
##   1 project stretch was canvas_items/EXPAND. Expand never distorts by itself,
##     but the whole UI is laid out in absolute 1080x1920 coordinates, so an
##     expanded viewport put the nav bars and cards outside the design rect.
##   2 the web export forced a 9:16 CSS box on a canvas whose DRAWING BUFFER was
##     the full browser window (canvas_resize_policy=2 sizes the buffer to
##     window.innerWidth/Height). Measured on the live build: buffer 1910x860
##     (aspect 2.22) squeezed into a 483x860 box (aspect 0.5625) — a 3.95x
##     horizontal squash. Fixed by letting the canvas fill the window so buffer
##     and box always agree, and letting stretch/aspect=keep letterbox instead.
##
## Asserted here:
##   A the project settings that make distortion impossible are in place
##   B at every window aspect from ultra-wide to ultra-tall, the stretch
##     transform scales X and Y by the SAME factor (that IS "no distortion"),
##     and the 1080x1920 frame stays inside the window and centred
##   C the web export shell does not reimpose an aspect-ratio on the canvas

var fails := 0
var _tree: SceneTree

## Largest X-vs-Y scale difference that still counts as undistorted (0.5%).
## Whole-pixel rounding of the letterbox rect accounts for up to ~0.1%.
const ANISO_MAX := 0.005

const SHAPES := [
	Vector2i(1080, 1920),   # exact design ratio
	Vector2i(1920, 1080),   # desktop landscape
	Vector2i(2560, 1080),   # ultra-wide
	Vector2i(412, 915),     # phone portrait (taller than 9:16)
	Vector2i(844, 390),     # phone landscape
	Vector2i(360, 800),     # tall narrow phone
	Vector2i(768, 1024),    # tablet portrait (wider than 9:16)
]

func _ready() -> void:
	_tree = get_tree()
	_case_settings()
	_case_transform()
	_case_shell()
	print("STRETCH %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("STRETCH   %s %s" % ["ok  " if ok else "FAIL", what])

func _case_settings() -> void:
	print("STRETCH -- A project settings")
	var mode = ProjectSettings.get_setting("display/window/stretch/mode", "")
	var aspect = ProjectSettings.get_setting("display/window/stretch/aspect", "")
	_check(mode == "canvas_items", "stretch/mode = canvas_items (實際 %s)" % mode)
	_check(aspect == "keep", "stretch/aspect = keep,唔係 expand/ignore (實際 %s)" % aspect)
	var w = ProjectSettings.get_setting("display/window/size/viewport_width", 0)
	var h = ProjectSettings.get_setting("display/window/size/viewport_height", 0)
	_check(int(w) == 1080 and int(h) == 1920, "設計解析度仍然係 1080x1920 (實際 %sx%s)" % [w, h])

func _case_transform() -> void:
	print("STRETCH -- B 任何視窗比例都唔變形")
	var win := get_window()
	var restore := win.size
	for s in SHAPES:
		win.size = s
		# the stretch transform is recomputed on the size change; read it back
		var xf: Transform2D = win.get_final_transform()
		var sx: float = xf.x.x
		var sy: float = xf.y.y
		if is_zero_approx(sx) and is_zero_approx(sy):
			_check(false, "%dx%d 攞唔到 stretch transform(headless 限制)" % [s.x, s.y])
			continue
		# Not exact equality: Godot rounds the letterboxed viewport rect to whole
		# pixels, so e.g. 1920x1080 gives 607/1080 vs 1080/1920 = 0.082% apart —
		# half a pixel across 607, invisible. ANISO_MAX is the "no visible
		# distortion" line; the bug this test exists for was 395%.
		var aniso: float = absf(sx - sy) / maxf(sx, sy)
		_check(aniso <= ANISO_MAX,
			"%4dx%-4d 等比縮放 sx=%.4f sy=%.4f (偏差 %.3f%%)"
			% [s.x, s.y, sx, sy, aniso * 100.0])
		# the 1080x1920 frame must fit inside the window and be centred
		var fw: float = 1080.0 * sx
		var fh: float = 1920.0 * sy
		_check(fw <= float(s.x) + 1.0 and fh <= float(s.y) + 1.0,
			"%4dx%-4d 畫面 %.0fx%.0f 塞得入視窗" % [s.x, s.y, fw, fh])
		_check(absf(xf.origin.x - (float(s.x) - fw) * 0.5) <= 1.5
				and absf(xf.origin.y - (float(s.y) - fh) * 0.5) <= 1.5,
			"%4dx%-4d 置中 (origin %.1f,%.1f 對 %.1f,%.1f)"
			% [s.x, s.y, xf.origin.x, xf.origin.y,
			(float(s.x) - fw) * 0.5, (float(s.y) - fh) * 0.5])
	win.size = restore

func _case_shell() -> void:
	print("STRETCH -- C web export shell")
	var cfg := ConfigFile.new()
	if cfg.load("res://export_presets.cfg") != OK:
		_check(false, "讀到 export_presets.cfg")
		return
	# find the preset NAMED "Web", then read its own .options section — matching
	# on ".options" alone also picks up the Android preset
	var opts := ""
	for sect in cfg.get_sections():
		if sect.ends_with(".options"):
			continue
		if str(cfg.get_value(sect, "name", "")) == "Web":
			opts = sect + ".options"
	if opts == "" or not cfg.has_section(opts):
		_check(false, "搵到 Web preset 嘅 options section")
		return
	var head := str(cfg.get_value(opts, "html/head_include", ""))
	var policy := int(cfg.get_value(opts, "html/canvas_resize_policy", -1))
	_check(head != "", "搵到 Web preset 嘅 head_include")
	# this is the exact line that caused the 3.95x squash
	_check(not head.contains("aspect-ratio"),
		"head_include 冇再迫 canvas 做固定 aspect-ratio")
	_check(head.contains("width:100%") and head.contains("height:100%"),
		"canvas 填滿視窗,所以繪圖 buffer 同顯示框永遠一致")
	_check(policy == 2, "canvas_resize_policy = 2 (Adaptive,buffer 跟視窗) (實際 %d)" % policy)
