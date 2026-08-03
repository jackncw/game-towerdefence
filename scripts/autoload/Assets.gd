extends Node
## Texture loader with caching + procedural fallback so the game never crashes
## if a generated sprite is missing. Filenames follow docs/design/CONTRACT.md.

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

## `tier` 預設 0 = 「用玩家而家嗰階」。呼叫端絕大部分想要嘅就係咁,而
## 明確傳一個 tier 係俾升級介面嘅預覽同圖鑑用 —— 嗰兩處要畫一個玩家
## **仲未擁有**嘅階級。
func tower(id: int, tier := 0) -> Texture2D:
	var t: int = Meta.tower_tier(id) if tier <= 0 else tier
	return _load(GEN + "towers/tower_%d%s.png" % [id, _tier_suffix(t)],
		64, Color(0.5, 0.5, 0.6))

func spell(id: int, tier := 0) -> Texture2D:
	var t: int = Meta.spell_tier(id) if tier <= 0 else tier
	return _load(GEN + "spells/spell_%d%s.png" % [id, _tier_suffix(t)],
		64, Color(0.4, 0.5, 0.8))

## tier 1 冇後綴 —— 三十五個原檔名一個都唔改,所以任何一個仲未識 tier 嘅
## 呼叫端(工具、舊測試)照樣攞返原本嗰張圖。
func _tier_suffix(tier: int) -> String:
	return "" if tier <= 1 else "_t%d" % tier

func coin() -> Texture2D:
	return _load(GEN + "ui/coin.png", 40, Color(1.0, 0.82, 0.1))

func crystal() -> Texture2D:
	return _load(GEN + "ui/crystal.png", 40, Color(0.5, 0.35, 0.95))

func base_tex() -> Texture2D:
	return _load(GEN + "ui/base.png", 96, Color(0.4, 0.7, 1.0))

func soldier() -> Texture2D:
	return _load(GEN + "ui/soldier.png", 20, Color(0.7, 0.7, 0.75))

## 魔法召喚民兵 — a separate sprite from soldier() so the two never read alike.
func militia() -> Texture2D:
	return _load(GEN + "ui/militia.png", 20, Color(0.62, 0.86, 1.0))

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
	# 圖鑑 / 升級介面預覽會即刻要下一階嗰張,而佢哋唔喺戰鬥入面 —— 所以
	# 呢度只暖玩家**而家**用緊嗰階,唔連埋預覽一齊拉,免得每一場戰鬥開場
	# 都白白 load 咗七十張永遠唔會出現喺場上嘅圖。
	coin(); crystal(); base_tex(); soldier(); militia()

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
