extends Node
## Atlas 守門測試(合批輪加)。
##
## 合批輪將細圖砌埋做兩頁 atlas,而 `Assets._load()` 係「表入面有就用 atlas,
## 冇就 load 原檔」。呢個 fallback 好處係安全,壞處係**靜**:一張漏咗入表嘅圖
## 照樣行得,只係佢自己一個 draw call —— 即係合批輪嘅成果會一路一路蝕返,而
## 冇人會見到任何錯誤訊息。
##
## 所以呢度逐張問返轉頭:應該入 atlas 嘅,係咪真係返一個 AtlasTexture,而且
## region 嘅尺寸啱唔啱。順便守住反方向:平鋪嘅地面同路面**唔可以**入 atlas
## (入咗就會連隔籬格一齊鋪)。

var fails: Array[String] = []
var checked := 0

func _ready() -> void:
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)

	for fam in GameData.FAMILY_ORDER:
		for lvl in range(1, 6):
			_want_atlas("monster %s_%d" % [fam, lvl], Assets.monster(fam, lvl))
		_want_atlas("boss %s" % fam, Assets.monster_boss(fam))
	for id in range(1, 21):
		for tier in range(1, 4):
			_want_atlas("tower %d t%d" % [id, tier], Assets.tower(id, tier))
	for id in range(1, 16):
		for tier in range(1, 4):
			_want_atlas("spell %d t%d" % [id, tier], Assets.spell(id, tier))
	_want_atlas("coin", Assets.coin())
	_want_atlas("crystal", Assets.crystal())
	_want_atlas("base", Assets.base_tex())
	_want_atlas("soldier", Assets.soldier())
	_want_atlas("militia", Assets.militia())
	for t in ["deco_rock1", "deco_rock2", "deco_bones", "deco_skull", "deco_grass",
			"deco_crack", "deco_bush", "deco_pebbles", "deco_stump", "deco_banner", "portal"]:
		_want_atlas("tile %s" % t, Assets.tile(t))
	# 合批輪新加嘅特效貼圖。佢哋入唔到 atlas 嘅話,每一層 MultiMesh 就自己
	# 一個 texture,即係特效嗰邊由 9 個 draw call 變返 9 個唔同 batch。
	for f in ["spark", "spark_hi", "coin", "coin_hi", "burst", "burst_core", "orb",
			"bar", "curse_haze", "curse_rune", "curse_mote", "curse_mark",
			"holy_mote", "holy_core"]:
		_want_atlas("fx %s" % f, Assets.fx(f))
	for u in ["ic_pause", "ic_play", "ic_ff", "ic_sound", "ic_mute", "ic_back",
			"ic_shop", "ic_skull", "ic_stats", "ic_up"]:
		_want_atlas("ui %s" % u, Assets.ui(u))

	# 反方向:平鋪嘅嘢一定唔可以入 atlas
	_want_plain("tile ground", Assets.tile("ground"))
	_want_plain("tile road", Assets.tile("road"))
	# 全屏背景太大,入咗就一張圖食晒成頁
	_want_plain("ui menu_bg", Assets.ui("menu_bg"))

	print("ATLAS: %d entries in map" % Assets.atlas_entries())
	if fails.is_empty():
		print("AtlasTest: PASS (%d textures checked)" % checked)
		get_tree().quit(0)
	else:
		for f in fails:
			print("  FAIL " + f)
		print("AtlasTest: FAIL (%d / %d)" % [fails.size(), checked])
		get_tree().quit(1)

func _want_atlas(label: String, tex: Texture2D) -> void:
	checked += 1
	if tex == null:
		fails.append("%s -> null" % label)
		return
	if not (tex is AtlasTexture):
		fails.append("%s -> %s(唔喺 atlas 入面)" % [label, tex.get_class()])
		return
	var at: AtlasTexture = tex
	if at.region.size.x <= 0.0 or at.region.size.y <= 0.0:
		fails.append("%s -> 空 region" % label)
	elif at.atlas == null:
		fails.append("%s -> 冇底圖" % label)

func _want_plain(label: String, tex: Texture2D) -> void:
	checked += 1
	if tex is AtlasTexture:
		fails.append("%s -> 唔應該入 atlas(佢要平鋪)" % label)
