extends Node
## Texture loader with caching + procedural fallback so the game never crashes
## if a generated sprite is missing. Filenames follow CONTRACT.md.

const GEN := "res://assets/generated/"
var _cache: Dictionary = {}
var _fallback: Dictionary = {}

func _load(path: String, fallback_size: int, fallback_col: Color) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	if tex == null:
		tex = _make_fallback(fallback_size, fallback_col)
	_cache[path] = tex
	return tex

func _make_fallback(size: int, col: Color) -> Texture2D:
	var key := "%d_%s" % [size, str(col)]
	if _fallback.has(key):
		return _fallback[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# simple bordered blob
	for y in size:
		for x in size:
			var cx := x - size / 2.0
			var cy := y - size / 2.0
			var d := sqrt(cx * cx + cy * cy)
			if d < size * 0.42:
				img.set_pixel(x, y, col)
			elif d < size * 0.47:
				img.set_pixel(x, y, Color(0, 0, 0, 1))
	var tex := ImageTexture.create_from_image(img)
	_fallback[key] = tex
	return tex

func monster(fam: String, lvl: int) -> Texture2D:
	var f: Dictionary = GameData.FAMILIES[fam]
	return _load(GEN + "monsters/%s_%d.png" % [fam, lvl], GameData.LVL_SIZE[lvl], _fam_col(fam))

func monster_boss(fam: String) -> Texture2D:
	return _load(GEN + "monsters/%s_boss.png" % fam, 96, _fam_col(fam))

func tower(id: int) -> Texture2D:
	return _load(GEN + "towers/tower_%d.png" % id, 64, Color(0.5, 0.5, 0.6))

func spell(id: int) -> Texture2D:
	return _load(GEN + "spells/spell_%d.png" % id, 64, Color(0.4, 0.5, 0.8))

func coin() -> Texture2D:
	return _load(GEN + "ui/coin.png", 40, Color(1.0, 0.82, 0.1))

func crystal() -> Texture2D:
	return _load(GEN + "ui/crystal.png", 40, Color(0.5, 0.35, 0.95))

func base_tex() -> Texture2D:
	return _load(GEN + "ui/base.png", 96, Color(0.4, 0.7, 1.0))

func soldier() -> Texture2D:
	return _load(GEN + "ui/soldier.png", 20, Color(0.7, 0.7, 0.75))

## Generic UI texture (frames, icons, badges). Falls back to a flat panel colour.
func ui(name: String) -> Texture2D:
	return _load(GEN + "ui/%s.png" % name, 48, Color(0.4, 0.42, 0.5))

## Terrain / decoration tile (ground, road, deco_*, portal).
func tile(name: String) -> Texture2D:
	return _load(GEN + "tiles/%s.png" % name, 64, Color(0.3, 0.3, 0.34))

## Warm the texture cache for everything a battle can show. _load() otherwise
## does a synchronous ResourceLoader.load() the FIRST time each sprite appears —
## i.e. a disk hit in the middle of a wave. With 60 monster sprites plus towers
## and spell icons that produced repeatable frame spikes mid-fight, which is
## exactly what breaks a 30fps budget on a low-end device.
func prewarm_battle(families: Array, boss_family: String) -> void:
	var fams := families.duplicate()
	if not fams.has(boss_family):
		fams.append(boss_family)
	for f in fams:
		for lvl in range(1, 6):
			monster(f, lvl)
		monster_boss(f)
	for id in Meta.unlocked_towers:
		tower(id)
	for id in Meta.unlocked_spells:
		spell(id)
	coin(); crystal(); base_tex(); soldier()

func _fam_col(fam: String) -> Color:
	match fam:
		"goblin": return Color(0.35, 0.65, 0.25)
		"wolf": return Color(0.45, 0.5, 0.62)
		"skeleton": return Color(0.9, 0.9, 0.85)
		"golem": return Color(0.5, 0.45, 0.4)
		"ghost": return Color(0.6, 0.85, 0.9)
		"bat": return Color(0.55, 0.3, 0.7)
		"treant": return Color(0.45, 0.55, 0.25)
		"beetle": return Color(0.2, 0.35, 0.35)
		"cultist": return Color(0.55, 0.2, 0.35)
		"slime": return Color(0.55, 0.85, 0.3)
	return Color(0.7, 0.7, 0.7)
