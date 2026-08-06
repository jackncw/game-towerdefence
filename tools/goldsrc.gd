extends Node
## G2「經濟技能上限」嘅量度器(第十八輪)。
##
## 逐個金幣來源量「頂配全程使用」vs「完全唔用」嘅當關總金比率。
##
## 量法:同一場戰鬥、同一批**輸出塔**(箭塔 T3 滿課,佢哋負責殺嘢),兩臂
## 唯一嘅分別就係有冇加嗰個經濟來源上去。即係話呢個比率係經濟來源嘅**純
## 貢獻上限** —— 真人玩家用鍊金塔係要犧牲塔位嘅,呢度冇扣返,所以量到嘅數
## 一定 ≥ 實戰值。Gate 用呢個上限讀數。
##
## boss 釘住唔准死(佢一死就完場,而完場之後嘅時間唔存在,兩臂就唔同長度);
## 走到九成路嘅怪即殺,唔准佢行到基地(輸咗一樣係唔同長度)。
##
## 用法:godot --headless --path . res://tools/goldsrc.tscn -- --lv=30 --seeds=4
##      加 --verbose 會印塔陣同光環嘅診斷行。

const DT := 1.0 / 30.0
const REF_SECONDS := 90.0
const DMG_TOWER := 1        # 箭塔
const DMG_COUNT := 14       # 輸出塔數目 —— 夠殺晒,亦都係中期一個實際嘅塔陣
const ALCHEMY := 12
const CURSE := 17
const MIDAS := 6
const ALCHEMY_COUNT := 3    # 「頂配」= 三座鍊金塔(佢哋之間有 T2 金線加成)
const CURSE_COUNT := 1

var lv := 30
var seeds := 4
## 輸出塔數目。**要跟返嗰一關嘅 G1 行**:如果塔太少殺唔切,分母(打怪掉金)
## 就會偏低,而鍊金塔/點金術嘅絕對產出唔跟塔數走 —— 比率就會虛高。實測
## 第 69 關用 14 座塔量到鍊金塔 1.55(第 30 關同一套設定係 1.26),差嘅
## 唔係機制,係嗰個 build 喺第 69 關根本唔係一個 on-curve 玩家。
var dmg_count := DMG_COUNT
var _cursed_seen := 0
var _dbg := false
var _dbg_min := 1e9
var _dbg_amp := 0.0

## 真存檔要備份同還原 —— 呢個工具會 reset_save() 再授予滿級 build,而 Meta
## 會寫落 save.json。唔還原嘅話,跟住跑嘅任何一個測試都會喺一個滿課存檔上面
## 開波(實測後果:RegressionTest 嘅詛咒塔 case 讀到 T3 滿課數值,斷言「boss
## 食到但打折」報 FAIL,而遊戲本身冇任何嘢壞咗)。GateSim 一直有做,工具冇。
var _save_bytes := PackedByteArray()
var _had_save := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	get_tree().paused = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--lv="):
			lv = int(a.substr(5))
		elif a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--dmg="):
			dmg_count = maxi(1, int(a.substr(6)))
		elif a == "--dbg":
			_dbg = true
	await _run()
	get_tree().paused = false
	_restore_save()
	get_tree().quit(0)

func _backup_save() -> void:
	_had_save = FileAccess.file_exists(Meta.SAVE_PATH)
	if _had_save:
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_save_bytes)
			f.close()
	elif FileAccess.file_exists(Meta.SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Meta.SAVE_PATH))

func _run() -> void:
	print("G2 MODE=src lv=%d seeds=%d dmg_towers=%d" % [lv, seeds, dmg_count])
	print("G2 HDR arm gold ratio")
	var arms := ["none", "midas", "alchemy", "curse", "all"]
	var base := 0.0
	for arm in arms:
		var tot := 0.0
		for s in seeds:
			seed(0x62D + lv * 7919 + s * 104729)
			tot += float(await _one(String(arm)))
		tot /= float(seeds)
		if arm == "none":
			base = tot
		print("G2 ROW %s %.0f %.4f" % [arm, tot, tot / maxf(1.0, base)])

func _one(arm: String) -> float:
	Meta.reset_save()
	_grant(arm)
	Flow.selected_level = lv
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	var g0: int = b.gold
	b.gold = 1 << 24                      # 起塔唔准食入量度(建塔錢唔算收入)
	_place(b, arm)
	b.gold = g0                           # 收返起手金,由零開始計收入
	_cursed_seen = 0
	if _dbg:
		for t in b.curse_towers:
			print("G2 DBG curse pos=(%.0f,%.0f) rng=%.0f road_d=%.0f amp=%.2f gold=%.2f"
				% [t.global_position.x, t.global_position.y, t.range_val,
				b.route.dist_to_route(t.global_position),
				float(t.s.curse), float(t.s.goldbonus)])
	var t := 0.0
	var cast_t := 0.0
	while t < REF_SECONDS and not b.ended:
		if b.contract_pending:
			# choose_contract 收合約 id,唔係第幾張 —— 傳錯就靜靜咁 return,
			# 而 continue 唔加時間,即刻死循環。
			if b.contract_offer.is_empty():
				break
			b.choose_contract(int(b.contract_offer[0]))
			continue
		if arm == "midas" or arm == "all":
			cast_t -= DT
			if cast_t <= 0.0:
				cast_t = 0.25
				if float(b.spell_cd.get(MIDAS, 0.0)) <= 0.0:
					b._cast_spell_now(MIDAS)
		b._process(DT)
		for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
			for c in root.get_children():
				if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
					c._process(DT)
		_pin(b)
		t += DT
	if _dbg:
		print("G2 DBG2 arm=%s kills=%d cursed_frames=%d gold=%d min_d=%.0f max_amp=%.2f curse_reg=%d"
			% [arm, b.kills, _cursed_seen, b.gold, _dbg_min, _dbg_amp, b.curse_towers.size()])
	var income: float = float(b.gold)     # 起手金 + 場內收入 = 當關總金
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true
	return income

## boss 唔准死、唔准行;雜兵行到九成路就即殺 —— 兩臂要一樣長度先比得到。
func _pin(b) -> void:
	for m in b.monsters.duplicate():
		if not is_instance_valid(m) or not m.alive:
			continue
		if m.curse_gold > 0.0:
			_cursed_seen += 1
		if _dbg and not b.curse_towers.is_empty():
			var ct = b.curse_towers[0]
			_dbg_min = minf(_dbg_min, m.global_position.distance_to(ct.global_position))
			_dbg_amp = maxf(_dbg_amp, m.curse_amp)
		if m.is_boss:
			m.dist = minf(m.dist, b.route.total * 0.25)
			m.hp = m.max_hp
		elif m.dist > b.route.total * 0.9:
			m._die(true)

func _grant(arm: String) -> void:
	for t in GameData.TOWERS:
		if not Meta.unlocked_towers.has(int(t.id)):
			Meta.unlocked_towers.append(int(t.id))
	for s in GameData.SPELLS:
		if not Meta.unlocked_spells.has(int(s.id)):
			Meta.unlocked_spells.append(int(s.id))
	_max_tower(DMG_TOWER)
	if arm == "alchemy" or arm == "all":
		_max_tower(ALCHEMY)
	if arm == "curse" or arm == "all":
		_max_tower(CURSE)
	if arm == "midas" or arm == "all":
		Meta.spell_tiers[str(MIDAS)] = GameData.MAX_TIER
		Meta.spell_up[str(MIDAS)] = _maxed(GameData.spell_by_id(MIDAS).ups.size())
	Meta.crystals = 0

func _max_tower(id: int) -> void:
	Meta.tower_tiers[str(id)] = GameData.MAX_TIER
	Meta.tower_up[str(id)] = _maxed(GameData.tower_by_id(id).ups.size())

func _maxed(n: int) -> Array:
	var a: Array = []
	for i in n:
		a.append(GameData.MAX_UP_LV)
	return a

## 輸出塔先擺(覆蓋率排序),經濟塔擺喺跟住嗰批位 —— 兩臂嘅輸出塔位置
## 一模一樣,所以殺傷力一樣,分別淨係多咗嗰幾座經濟塔。
func _place(b, arm: String) -> void:
	var spots: Array = _spots(b)
	var i := 0
	for k in dmg_count:
		i = _place_one(b, spots, i, DMG_TOWER)
	# 經濟塔改用**沿路次序**擺(由出怪口數起),唔用覆蓋率次序。
	#
	# 點解:鍊金塔嘅 killbonus 同詛咒塔嘅 goldbonus 都係「射程內死亡先數」,
	# 而屍體全部堆喺玩家火力第一次接觸嘅嗰一段路。用覆蓋率次序擺嘅話,詛咒塔
	# 會落喺地圖中段一個「覆蓋最多路程」但**一隻怪都行唔到**嘅位 —— 實測第一
	# 版就係咁,量到嘅比率係 1.0000,而原因唔係機制壞咗,係塔擺錯位。
	# 呢個 gate 要量嘅係上限,所以經濟塔要擺喺屍體度。
	var kill: Array = spots.duplicate()
	kill.sort_custom(func(a, c): return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))
	var j := 0
	if arm == "alchemy" or arm == "all":
		for k in ALCHEMY_COUNT:
			j = _place_one(b, kill, j, ALCHEMY)
	if arm == "curse" or arm == "all":
		for k in CURSE_COUNT:
			j = _place_one(b, kill, j, CURSE)

func _place_one(b, spots: Array, i: int, id: int) -> int:
	while i < spots.size():
		if b.can_place(spots[i]) and b.place_tower(id, spots[i]):
			return i + 1
		i += 1
	return i

func _spots(b) -> Array:
	var out: Array = []
	var y: float = b.BUILD_MIN.y
	while y <= b.BUILD_MAX.y:
		var x: float = b.BUILD_MIN.x
		while x <= b.BUILD_MAX.x:
			var p: Vector2 = b.snap(Vector2(x, y))
			if b.can_place(p):
				out.append(p)
			x += 74.0
		y += 74.0
	var cov := {}
	for p in out:
		cov[p] = _coverage(b, p, 260.0)
	out.sort_custom(func(a, c):
		var ca: float = float(cov[a])
		var cc: float = float(cov[c])
		if absf(ca - cc) > 1.0:
			return ca > cc
		return b.route.nearest_dist_param(a) < b.route.nearest_dist_param(c))
	return out

func _coverage(b, p: Vector2, r: float) -> float:
	var tot: float = b.route.total
	var d := 0.0
	var hit := 0.0
	while d < tot:
		if b.route.pos_at(d).distance_to(p) <= r:
			hit += 8.0
		d += 8.0
	return hit
