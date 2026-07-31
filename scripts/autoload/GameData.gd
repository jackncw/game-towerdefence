extends Node
## Central static data: monster families, towers, spells, level generation.
## All balance numbers live here. Effective-stat computation also lives here so
## battle logic and UI share one source of truth.

const MAX_UP_LV := 15
const UP_COST_MULT := 1.35
## 每關敵人強度成長率 (wave_scale = WAVE_GROWTH^(n-1))
const WAVE_GROWTH := 1.13

# --- world-render scales (B1: on-screen readability; visual only, no balance) --
# Round 5 pixel-density rule: EVERY world sprite renders at the same integer
# 2x with NEAREST, so one source texel is always exactly two screen pixels.
# The old mixed 1.75 / 1.25 / 1.4 / 1.6 scales gave monsters, towers, the base
# and soldiers four different texel sizes (and non-integer scales smeared the
# grid). Sprite sources were resized instead: tower 64->44, base 112->96.
const RENDER_SCALE := 2.0     # monster sprite world scale -> lv1 64px, boss 192px
const TOWER_RENDER := 2.0     # tower sprite world scale (44px source -> 88px)
const BASE_RENDER := 2.0      # base marker world scale (96px source -> 192px)
const SOLDIER_RENDER := 2.0   # militia token world scale (20px source -> 40px)
const ROAD_WIDTH_SCALE := 1.15  # road polyline width scale (holds ~1.5 lv1 side by side)

# ---------------------------------------------------------------------------
# FAMILIES (10). base stats are for creature-level 1, un-scaled by game level.
# mechanic tags are read by Monster.gd. flying => ignores ground effects.
# ---------------------------------------------------------------------------
## `name` is a TRANSLATION KEY, not display text — resolve it with tr() at the
## point of display. Same for every other *_NAME / *_DESC / *_LORE below; the
## strings themselves live in res://i18n/game.csv.
var FAMILIES := {
	"goblin":  {"idx":1,  "name":"FAM_GOBLIN_NAME",   "hp":42,  "speed":52, "armor":2,  "mres":0,  "gold":4,  "flying":false, "mech":"basic",   "boss":"summon"},
	"wolf":    {"idx":2,  "name":"FAM_WOLF_NAME",     "hp":30,  "speed":92, "armor":0,  "mres":0,  "gold":4,  "flying":false, "mech":"basic",   "boss":"enrage"},
	"skeleton":{"idx":3,  "name":"FAM_SKELETON_NAME", "hp":40,  "speed":58, "armor":1,  "mres":5,  "gold":5,  "flying":false, "mech":"revive",  "boss":"revive_aura"},
	"golem":   {"idx":4,  "name":"FAM_GOLEM_NAME",    "hp":70,  "speed":40, "armor":12, "mres":0,  "gold":6,  "flying":false, "mech":"armored", "boss":"stoneskin"},
	"ghost":   {"idx":5,  "name":"FAM_GHOST_NAME",    "hp":44,  "speed":62, "armor":0,  "mres":25, "gold":6,  "flying":false, "mech":"phase",   "boss":"phase_fast"},
	"bat":     {"idx":6,  "name":"FAM_BAT_NAME",      "hp":36,  "speed":78, "armor":0,  "mres":10, "gold":5,  "flying":true,  "mech":"flying",  "boss":"dive"},
	"treant":  {"idx":7,  "name":"FAM_TREANT_NAME",   "hp":95,  "speed":44, "armor":4,  "mres":0,  "gold":7,  "flying":false, "mech":"regen",   "boss":"root_heal"},
	"beetle":  {"idx":8,  "name":"FAM_BEETLE_NAME",   "hp":58,  "speed":54, "armor":6,  "mres":0,  "gold":6,  "flying":false, "mech":"hardshell","boss":"reflect"},
	"cultist": {"idx":9,  "name":"FAM_CULTIST_NAME",  "hp":50,  "speed":56, "armor":2,  "mres":10, "gold":7,  "flying":false, "mech":"aura",    "boss":"mass_heal"},
	"slime":   {"idx":10, "name":"FAM_SLIME_NAME",    "hp":48,  "speed":50, "armor":1,  "mres":0,  "gold":4,  "flying":false, "mech":"split",   "boss":"split_birth"},
}
var FAMILY_ORDER := ["goblin","wolf","skeleton","golem","ghost","bat","treant","beetle","cultist","slime"]

# bestiary lore keys: mechanic blurb + boss skill blurb per family
var FAMILY_LORE := {
	"goblin":  {"mech":"FAM_GOBLIN_MECH",   "boss":"FAM_GOBLIN_BOSS"},
	"wolf":    {"mech":"FAM_WOLF_MECH",     "boss":"FAM_WOLF_BOSS"},
	"skeleton":{"mech":"FAM_SKELETON_MECH", "boss":"FAM_SKELETON_BOSS"},
	"golem":   {"mech":"FAM_GOLEM_MECH",    "boss":"FAM_GOLEM_BOSS"},
	"ghost":   {"mech":"FAM_GHOST_MECH",    "boss":"FAM_GHOST_BOSS"},
	"bat":     {"mech":"FAM_BAT_MECH",      "boss":"FAM_BAT_BOSS"},
	"treant":  {"mech":"FAM_TREANT_MECH",   "boss":"FAM_TREANT_BOSS"},
	"beetle":  {"mech":"FAM_BEETLE_MECH",   "boss":"FAM_BEETLE_BOSS"},
	"cultist": {"mech":"FAM_CULTIST_MECH",  "boss":"FAM_CULTIST_BOSS"},
	"slime":   {"mech":"FAM_SLIME_MECH",    "boss":"FAM_SLIME_BOSS"},
}

# ---------------------------------------------------------------------------
# BOSS-FIGHT ambient spawning. While the boss is alive the wave spawner keeps
# running (kills keep paying gold) at a reduced frequency; each boss overrides
# the baseline with its own profile so every boss fight paces differently.
# Battle.gd only reads these fields — no per-boss spawn logic in scripts.
#   rate         ambient spawn frequency as a fraction of the normal (pre-boss)
#                frequency. 0 = no ambient spawns (burst-only bosses).
#   pool         family list overriding the level's spawn families.
#   lvl_bonus    +N creature level on ambient spawns (clamped 1..5).
#   minion_regen ambient spawns regen this fraction of max hp per second.
#   burst        periodic squad: {first, interval, count_min, count_max, fam}.
# ---------------------------------------------------------------------------
const BOSS_SPAWN_BASE_RATE := 0.4
var BOSS_SPAWN := {
	"goblin":  {"rate":0.15},                                     # 哥布林王自己召喚增援
	"wolf":    {"rate":0.0,                                       # 狼王:平時無,狼群突襲
	            "burst":{"first":5.0, "interval":12.0, "count_min":3, "count_max":5, "fam":"wolf"}},
	"skeleton":{"rate":0.4},                                      # 骷髏君主:標準+復活光環
	"golem":   {"rate":0.25, "lvl_bonus":1},                      # 岩石巨像:少而精,單隻值錢
	"ghost":   {"rate":0.4, "pool":["ghost"]},                    # 幽靈女王:全幽靈族
	"bat":     {"rate":0.4, "pool":["bat"]},                      # 蝠魔霸主:只出飛行
	"treant":  {"rate":0.3, "minion_regen":0.01},                 # 遠古樹妖:小怪輕微再生
	"beetle":  {"rate":0.3, "pool":["beetle"]},                   # 甲蟲皇:少量硬殼甲蟲
	"cultist": {"rate":0.4, "pool":["cultist"]},                  # 大祭司:信徒受全場群療
	"slime":   {"rate":0.10},                                     # 史萊姆之母自己分裂產怪
}

func boss_spawn_profile(fam: String) -> Dictionary:
	return BOSS_SPAWN.get(fam, {"rate": BOSS_SPAWN_BASE_RATE})

# ---------------------------------------------------------------------------
# BOSS 回復上限. Applies to EVERY boss with a heal element, present or future —
# Monster routes all self-healing through one budget, so a new mechanic cannot
# quietly reintroduce the problem.
#
# "預期玩家 DPS" is measured, not guessed: in the 20-level balance playthrough
# the bosses WITHOUT any heal resolve in a median of ~16s, so the firepower a
# level expects of the player is boss_max_hp / BOSS_FIGHT_REF_SECONDS. A boss may
# claw back at most BOSS_HEAL_DPS_SHARE of that, which is exactly the condition
# that keeps the blood bar strictly falling for a player who is on curve
# (net progress = (1 - share) x DPS > 0).
#
# What this replaced: 遠古樹妖 regenerated 2%/s AND healed a flat 25% at 40% HP
# (3.5%/s equivalent, ~2.9x the ceiling) and 大祭司 healed ITSELF 12% every 7s
# (1.7%/s). Levels 3/13 and 17 ran 38-45s against a 16s median.
# ---------------------------------------------------------------------------
const BOSS_FIGHT_REF_SECONDS := 16.0
const BOSS_HEAL_DPS_SHARE := 0.20
## Sustained self-heal ceiling as a fraction of the boss's own max HP per second
## (0.20 / 16s = 1.25%/s).
const BOSS_HEAL_CAP_FRAC := BOSS_HEAL_DPS_SHARE / BOSS_FIGHT_REF_SECONDS
## A boss's heal mechanics REQUEST healing; the request is queued and paid out at
## no more than the ceiling per second. Banking the allowance and paying it as a
## lump was tried first and broke the actual promise: 大祭司's 7-second group heal
## dumped 8 seconds of budget in one frame, so the blood bar jumped up 3.4% even
## though the AVERAGE rate was legal. Metering makes "永遠淨向下" true frame by
## frame, not just on average. This is the most a boss may have queued.
const BOSS_HEAL_QUEUE_SECONDS := 8.0

func boss_heal_cap_per_sec(max_hp: float) -> float:
	return max_hp * BOSS_HEAL_CAP_FRAC

# --- 遠古樹妖: 低血自療 -> 有反制窗口嘅詠唱 ---------------------------------
## Cast time. Long enough to see, react and answer; short enough that it is a
## moment rather than a lull.
const TREANT_CHANNEL_TIME := 2.5
## Heal paid if the cast is never answered, as a fraction of max HP. Exempt from
## the per-second ceiling ON PURPOSE: it is not silent sustain, it is a telegraph
## the player is invited to beat, and damage dealt during the cast cancels it 1:1.
## Sized just UNDER the damage an on-curve player lands during the cast
## (TREANT_CHANNEL_TIME / BOSS_FIGHT_REF_SECONDS = 2.5/16 = 15.6% of max HP), so
## keeping up your expected DPS denies it completely and the blood bar still only
## goes down — while falling short of curve costs you the difference.
const TREANT_CHANNEL_HEAL := 0.15
## 骷髏君主嘅復活光環: how many times the aura may bring one minion back. Was
## UNBOUNDED, which is what made level 3/13 feel like damage simply did not
## count. HP restored per revive, first then subsequent.
const AURA_REVIVE_MAX := 2
const REVIVE_HP := [0.30, 0.15]

# per creature-level multipliers (index 1..5)
const LVL_HP := [0.0, 1.0, 1.35, 1.8, 2.4, 3.2]
const LVL_SPEED := [0.0, 1.0, 1.04, 1.08, 1.12, 1.16]
const LVL_GOLD := [0.0, 1.0, 1.4, 1.9, 2.6, 3.6]
const LVL_SIZE := [0, 32, 35, 37, 40, 44] # px, matches art

func family_ids() -> Array:
	return FAMILY_ORDER

## 賞金跟 wave_scale 縮放 (GOLD_WAVE_EXP)。
## 舊版:hp 乘 wave_scale,gold 完全唔乘 —— 第 20 關嘅怪 17 倍血,但掉落同第 1
## 關一模一樣。打死一隻要 17 倍時間,收入卻一樣,所以場內經濟由第 7 關開始就
## 追唔上,模擬玩家由第 10 關起連雜兵都清唔切(100 秒得 6-15 殺)。
## 用 0.45 次方而唔係線性:賞金要跟得上怪物變硬,但唔可以令後期變成金礦
## (0.6 試過會令第 14/17/20 關滿場塔仲剩兩萬幾金)。
const GOLD_WAVE_EXP := 0.45

func creature_stats(fam: String, lvl: int, wave_scale: float) -> Dictionary:
	var f: Dictionary = FAMILIES[fam]
	return {
		"hp": f.hp * LVL_HP[lvl] * wave_scale,
		"speed": f.speed * LVL_SPEED[lvl],
		"armor": f.armor + (lvl - 1),
		"mres": f.mres,
		"gold": int(round(f.gold * LVL_GOLD[lvl] * pow(wave_scale, GOLD_WAVE_EXP))),
		"flying": f.flying,
		"mech": f.mech,
		"size": LVL_SIZE[lvl],
		"is_boss": false,
	}

func boss_stats(fam: String, wave_scale: float) -> Dictionary:
	var f: Dictionary = FAMILIES[fam]
	return {
		"hp": f.hp * 14.0 * wave_scale,
		"speed": f.speed * 0.72,
		"armor": f.armor + 6,
		"mres": f.mres + 5,
		"gold": 0, # boss drops crystals, handled separately
		"flying": f.flying,
		"mech": f.mech,
		"boss_mech": f.boss,
		"size": 96,
		"is_boss": true,
	}

# ---------------------------------------------------------------------------
# TOWERS (20). Each: id,name,desc,mech,place_cost(gold),unlock(crystal),
# stats{} named fields, ups[6] each {name, stat, step, base_cost, kind}
#   kind: "add" (stat += step*lv), "pct" (stat = base*(1+step*lv)),
#         "prob" (stat += step*lv, capped 1.0)
# ---------------------------------------------------------------------------
var TOWERS := []

func _build_towers() -> void:
	# helper
	var t := func(id,name,desc,mech,place,unlock,stats,ups):
		TOWERS.append({"id":id,"name":name,"desc":desc,"mech":mech,
			"place_cost":place,"unlock":unlock,"stats":stats,"ups":ups})

	t.call(1,"TOWER_ARROW_NAME","TOWER_ARROW_DESC","arrow",60,0,
		{"dmg":10.0,"rate":2.2,"range":260.0,"crit":0.05,"critmult":1.8,"double":0.0},
		[U("UP_ATK","dmg",3.0,40,"add"),U("UP_RATE","rate",0.18,45,"add"),U("UP_RANGE","range",16.0,35,"add"),
		 U("UP_CRIT","crit",0.03,55,"prob"),U("UP_CRITDMG","critmult",0.18,50,"add"),U("UP_DOUBLE","double",0.05,70,"prob")])
	t.call(2,"TOWER_CANNON_NAME","TOWER_CANNON_DESC","cannon",110,0,
		{"dmg":34.0,"rate":0.7,"range":240.0,"splash":70.0,"armorpen":0.0,"knock":0.0},
		[U("UP_ATK","dmg",8.0,55,"add"),U("UP_RATE","rate",0.06,60,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_SPLASH","splash",8.0,50,"add"),U("UP_ARMORPEN","armorpen",0.05,60,"prob"),U("UP_KNOCKCHANCE","knock",0.05,55,"prob")])
	t.call(3,"TOWER_LIGHTNING_NAME","TOWER_LIGHTNING_DESC","lightning",130,120,
		{"dmg":14.0,"rate":1.1,"range":250.0,"chain":3.0,"falloff":0.35,"stun":0.0},
		[U("UP_ATK","dmg",4.0,55,"add"),U("UP_RATE","rate",0.1,55,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_CHAIN","chain",1.0,80,"add"),U("UP_FALLOFF","falloff",-0.02,60,"add"),U("UP_STUNCHANCE","stun",0.04,65,"prob")])
	t.call(4,"TOWER_FIREBALL_NAME","TOWER_FIREBALL_DESC","fireball",115,110,
		{"dmg":16.0,"rate":1.0,"range":250.0,"burn":6.0,"burndur":3.0,"detonate":0.0},
		[U("UP_ATK","dmg",4.5,50,"add"),U("UP_RATE","rate",0.1,55,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_BURN","burn",2.5,55,"add"),U("UP_BURNDUR","burndur",0.4,50,"add"),U("UP_DETONATE","detonate",0.05,70,"prob")])
	t.call(5,"TOWER_FROST_NAME","TOWER_FROST_DESC","frost",90,0,
		{"dmg":8.0,"rate":1.4,"range":230.0,"slow":0.25,"slowdur":1.5,"freeze":0.0},
		[U("UP_ATK","dmg",2.5,45,"add"),U("UP_RATE","rate",0.12,50,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_SLOWAMT","slow",0.03,55,"add"),U("UP_SLOWDUR","slowdur",0.2,50,"add"),U("UP_FREEZE","freeze",0.04,70,"prob")])
	t.call(6,"TOWER_POISON_NAME","TOWER_POISON_DESC","poison",120,140,
		{"dmg":4.0,"rate":1.2,"range":230.0,"pstack":3.0,"pmax":5.0,"pburst":0.0},
		[U("UP_ATK","dmg",1.5,45,"add"),U("UP_RATE","rate",0.1,50,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_PSTACK","pstack",1.2,60,"add"),U("UP_PMAX","pmax",1.0,70,"add"),U("UP_PBURST","pburst",10.0,65,"add")])
	t.call(7,"TOWER_SNIPER_NAME","TOWER_SNIPER_DESC","sniper",160,180,
		{"dmg":60.0,"rate":0.45,"range":460.0,"crit":0.15,"execute":0.0,"pierce":0.0},
		[U("UP_ATK","dmg",16.0,60,"add"),U("UP_RATE","rate",0.04,60,"add"),U("UP_RANGE","range",18.0,45,"add"),
		 U("UP_CRIT","crit",0.03,60,"prob"),U("UP_EXECUTE","execute",0.012,80,"add"),U("UP_PIERCE","pierce",1.0,75,"add")])
	t.call(8,"TOWER_GATLING_NAME","TOWER_GATLING_DESC","gatling",140,160,
		{"dmg":6.0,"rate":3.0,"range":220.0,"heatmax":2.0,"heatrate":0.12,"spread":0.0},
		[U("UP_ATK","dmg",1.8,55,"add"),U("UP_BASERATE","rate",0.2,55,"add"),U("UP_RANGE","range",14.0,40,"add"),
		 U("UP_HEATMAX","heatmax",0.2,60,"add"),U("UP_HEATRATE","heatrate",0.02,55,"add"),U("UP_SPREAD","spread",0.04,60,"prob")])
	# 平衡: range 520->400 (-23%), splash 90->70 (-22%)。評測到單塔波次傷害 +271%、
	# 混編 +177%,全場獨大;520 射程幾乎覆蓋成張地圖,擺邊都無所謂。
	t.call(9,"TOWER_MORTAR_NAME","TOWER_MORTAR_DESC","mortar",150,200,
		{"dmg":40.0,"rate":0.5,"range":400.0,"minrange":150.0,"splash":70.0,"frag":0.0,"scorch":0.0},
		[U("UP_ATK","dmg",10.0,60,"add"),U("UP_RATE","rate",0.04,60,"add"),U("UP_RANGE","range",20.0,45,"add"),
		 U("UP_SPLASH","splash",10.0,55,"add"),U("UP_FRAG","frag",1.0,70,"add"),U("UP_SCORCH","scorch",0.4,60,"add")])
	# 平衡: dmg 10->13 (+30%), 造價 170->145 (-15%)。評測到波次傷害 -69%、boss -1%,
	# 兩個情境都係全場最差,但造價係全場第二貴 —— 冇任何理由揀佢。
	t.call(10,"TOWER_BEAM_NAME","TOWER_BEAM_DESC","beam",145,220,
		{"dmg":13.0,"rate":10.0,"range":250.0,"rampmax":3.0,"ramprate":0.5,"meltarmor":0.0,"dual":0.0},
		[U("UP_DPS","dmg",3.0,60,"add"),U("UP_RANGE","range",14.0,45,"add"),U("UP_RAMPMAX","rampmax",0.3,65,"add"),
		 U("UP_RAMPRATE","ramprate",0.08,55,"add"),U("UP_MELTARMOR","meltarmor",0.4,60,"add"),U("UP_DUAL","dual",0.04,75,"prob")])
	t.call(11,"TOWER_SLOWFIELD_NAME","TOWER_SLOWFIELD_DESC","slowfield",100,150,
		{"dmg":0.0,"rate":1.0,"range":170.0,"slow":0.3,"vuln":0.0,"pulse":0.0,"pulserate":1.0,"bosseff":0.5},
		[U("UP_AREA","range",12.0,45,"add"),U("UP_SLOWAMT","slow",0.03,55,"add"),U("UP_VULN","vuln",0.03,60,"add"),
		 U("UP_PULSEDMG","pulse",6.0,60,"add"),U("UP_PULSERATE","pulserate",0.15,55,"add"),U("UP_BOSSEFF","bosseff",0.04,70,"prob")])
	t.call(12,"TOWER_ALCHEMY_NAME","TOWER_ALCHEMY_DESC","alchemy",100,160,
		{"dmg":0.0,"rate":0.4,"range":180.0,"gold":8.0,"killbonus":0.0,"critgold":0.0,"startgold":0.0},
		[U("UP_GOLDAMT","gold",3.0,55,"add"),U("UP_GOLDRATE","rate",0.05,60,"add"),U("UP_KILLRANGE","range",14.0,45,"add"),
		 U("UP_KILLBONUS","killbonus",0.05,60,"add"),U("UP_CRITGOLD","critgold",0.04,65,"prob"),U("UP_STARTGOLD","startgold",25.0,55,"add")])
	t.call(13,"TOWER_BARRACKS_NAME","TOWER_BARRACKS_DESC","barracks",90,0,
		{"dmg":6.0,"rate":1.2,"range":200.0,"soldierhp":40.0,"count":2.0,"respawn":5.0,"armor":0.0},
		[U("UP_SOLDIERDMG","dmg",2.0,50,"add"),U("UP_SOLDIERHP","soldierhp",10.0,50,"add"),U("UP_SOLDIERCOUNT","count",1.0,90,"add"),
		 U("UP_RESPAWN","respawn",-0.3,60,"add"),U("UP_SOLDIERARMOR","armor",1.0,55,"add"),U("UP_RALLY","range",14.0,40,"add")])
	t.call(14,"TOWER_BOOMERANG_NAME","TOWER_BOOMERANG_DESC","boomerang",115,150,
		{"dmg":12.0,"rate":1.0,"range":240.0,"count":1.0,"slow":0.0,"returnmult":1.0},
		[U("UP_ATK","dmg",3.5,50,"add"),U("UP_RATE","rate",0.1,55,"add"),U("UP_FLYDIST","range",16.0,45,"add"),
		 U("UP_BOOMCOUNT","count",1.0,80,"add"),U("UP_ADDSLOW","slow",0.03,60,"add"),U("UP_RETURNMULT","returnmult",0.1,60,"add")])
	t.call(15,"TOWER_THORN_NAME","TOWER_THORN_DESC","thorn",95,140,
		{"dmg":8.0,"rate":2.0,"range":150.0,"bleed":0.0,"slow":0.0,"heavymult":0.0},
		[U("UP_DAMAGE","dmg",2.5,50,"add"),U("UP_TRIGGERRATE","rate",0.2,55,"add"),U("UP_SEGLEN","range",12.0,45,"add"),
		 U("UP_BLEED","bleed",1.5,60,"add"),U("UP_ADDSLOW","slow",0.03,60,"add"),U("UP_HEAVYMULT","heavymult",0.06,60,"add")])
	# REWORK 輪:射程 300 -> 440(狙擊塔 460 同一檔,但仍然係第二遠)。總檢輪證實
	# 佢嘅樽頸唔係傷害係射程 —— boss 一路行,300 射程嘅 uptime 太短,加幾多 bossmult
	# 都補唔返。同時 splash 50 -> 26、bossmult 0.65 -> 1.9:power 由清雜兵搬去打單體
	# 大型,令「打 boss 贏、打雜兵海輸」呢個 tradeoff 真係存在(舊數值兩邊都贏,
	# 根本冇取捨)。dmg 22 -> 26 補返專注單體嘅損失。
	# 彈速 560 -> 900 喺 Tower._fire_missile:440 射程配 560 彈速要飛 0.79 秒,
	# 目標已經行咗;900 之下係 0.49 秒。
	t.call(16,"TOWER_MISSILE_NAME","TOWER_MISSILE_DESC","missile",150,200,
		{"dmg":14.0,"rate":0.9,"range":440.0,"bossmult":1.5,"splash":20.0,"salvo":1.0},
		[U("UP_ATK","dmg",6.0,60,"add"),U("UP_RATE","rate",0.08,60,"add"),U("UP_RANGE","range",16.0,45,"add"),
		 U("UP_BOSSMULT","bossmult",0.08,70,"add"),U("UP_SPLASH","splash",8.0,55,"add"),U("UP_SALVO","salvo",1.0,80,"add")])
	# ==== REWORK 輪:詛咒塔由「逐個施咒嘅攻擊塔」改造成「常駐詛咒光環」====
	# 舊設計數學上必輸:用一個塔位換 +26% 放大,即係放棄成座塔嘅輸出去換四分一,
	# 冇任何情境划算。新設計以塔位為單位重新推導 —— 設 D = 一座輸出塔 DPS,
	# 新詛咒塔本身零輸出:
	#   覆蓋 3 座:3D(1+X) 要贏 4D  ->  X > 1/3
	#   覆蓋 2 座:2D(1+X) + D 要和 4D  ->  X = 0.5
	#   覆蓋 1 座:1D(1+X) + 2D 要輸 4D  ->  X < 1.0
	# 三個條件嘅唯一交點就係 X = 0.50,所以 curse 基礎值 = 0.50。
	# 每級 +0.025,15 級後 0.875(覆蓋 3 座 = 5.6D vs 4D)。
	# 第二個入場理由:受詛咒狀態下死亡嘅敵人多掉 goldbonus% 金 —— 令佢同時係放大器
	# 同經濟塔,但只喺已經有輸出塔嘅位置先發揮,同鍊金塔(擺邊都穩定產金)係兩條路。
	# 基礎 25% 掉金:模擬中期一個光環大約覆蓋全場三成擊殺,即約 0.7 金/秒,
	# 遠低過鍊金塔嘅 3.2 金/秒純產出,唔會搶佢個位。
	t.call(17,"TOWER_CURSE_NAME","TOWER_CURSE_DESC","curse",120,180,
		{"dmg":0.0,"rate":0.0,"range":200.0,"curse":0.50,"goldbonus":0.25,
		 "linger":2.0,"slow":0.0,"bosseff":0.6},
		[U("UP_CURSE","curse",0.025,70,"add"),U("UP_AURARANGE","range",14.0,50,"add"),
		 U("UP_GOLDBONUS","goldbonus",0.025,60,"add"),U("UP_LINGER","linger",0.25,50,"add"),
		 U("UP_CURSESLOW","slow",0.02,60,"add"),U("UP_BOSSEFF","bosseff",0.025,65,"add")])
	t.call(18,"TOWER_HOLY_NAME","TOWER_HOLY_DESC","holy",140,190,
		{"dmg":14.0,"rate":1.2,"range":230.0,"aurahaste":0.1,"aurarange":150.0,"purify":0.0},
		[U("UP_ATK","dmg",4.0,55,"add"),U("UP_RATE","rate",0.1,55,"add"),U("UP_RANGE","range",14.0,45,"add"),
		 U("UP_AURAHASTE","aurahaste",0.02,65,"add"),U("UP_AURARANGE","aurarange",12.0,55,"add"),U("UP_PURIFY","purify",0.05,70,"prob")])
	t.call(19,"TOWER_MAGNET_NAME","TOWER_MAGNET_DESC","magnet",120,170,
		{"dmg":6.0,"rate":0.6,"range":200.0,"knock":40.0,"pulse":6.0,"knockslow":0.0,"heavyeff":0.5},
		[U("UP_KNOCKDIST","knock",6.0,55,"add"),U("UP_PULSERATE","rate",0.06,60,"add"),U("UP_AREA","range",14.0,45,"add"),
		 U("UP_PULSEDMG","pulse",3.0,55,"add"),U("UP_KNOCKSLOW","knockslow",0.03,60,"add"),U("UP_HEAVYEFF","heavyeff",0.04,65,"prob")])
	t.call(20,"TOWER_TELEPORT_NAME","TOWER_TELEPORT_DESC","teleport",130,210,
		{"dmg":2.0,"rate":0.7,"range":240.0,"tpchance":0.15,"tpdist":140.0,"stun":0.0,"cap":3.0},
		[U("UP_TPCHANCE","tpchance",0.02,70,"prob"),U("UP_TPRATE","rate",0.06,60,"add"),U("UP_RANGE","range",14.0,45,"add"),
		 U("UP_TPDIST","tpdist",10.0,55,"add"),U("UP_TPSTUN","stun",0.15,60,"add"),U("UP_TPCAP","cap",1.0,65,"add")])

func U(name:String, stat:String, step:float, base_cost:int, kind:String) -> Dictionary:
	return {"name":name,"stat":stat,"step":step,"base_cost":base_cost,"kind":kind}

# ---------------------------------------------------------------------------
# SPELLS (15). Each: id,name,desc,mech,cd(sec),needs_target(bool),
# stats{}, ups[3] {name,stat,step,base_cost,kind}
# ---------------------------------------------------------------------------
var SPELLS := []

func _build_spells() -> void:
	var s := func(id,name,desc,mech,cd,target,stats,ups):
		SPELLS.append({"id":id,"name":name,"desc":desc,"mech":mech,"cd":cd,
			"target":target,"stats":stats,"ups":ups})
	s.call(1,"SPELL_METEOR_NAME","SPELL_METEOR_DESC","meteor",8.0,true,
		{"dmg":120.0,"radius":120.0,"cd":8.0},
		[U("UP_DAMAGE","dmg",30.0,55,"add"),U("UP_AREA","radius",12.0,50,"add"),U("UP_CD","cd",-0.4,60,"add")])
	# 平衡: dmg 45->58 (+29%), bolts 6->7 (+17%)。評測到每秒冷卻傷害只有 18.8,
	# 係全部直傷魔法之中最低(隕石術 144、地震術 130、烈焰之牆 120),而佢冷卻
	# 仲要長過隕石術 —— 冇任何情境揀佢。
	s.call(2,"SPELL_STORMBOLT_NAME","SPELL_STORMBOLT_DESC","stormbolt",12.0,false,
		{"dmg":58.0,"bolts":7.0,"cd":12.0},
		[U("UP_DAMAGE","dmg",12.0,55,"add"),U("UP_BOLTS","bolts",1.0,65,"add"),U("UP_CD","cd",-0.6,60,"add")])
	s.call(3,"SPELL_FREEZENOVA_NAME","SPELL_FREEZENOVA_DESC","freezenova",16.0,false,
		{"dur":2.5,"slowafter":0.4,"cd":16.0},
		[U("UP_DURATION","dur",0.3,55,"add"),U("UP_SLOWAFTER","slowafter",0.04,55,"add"),U("UP_CD","cd",-0.8,60,"add")])
	s.call(4,"SPELL_MIASMA_NAME","SPELL_MIASMA_DESC","miasma",10.0,true,
		{"dps":25.0,"dur":6.0,"radius":110.0},
		[U("UP_POISONDPS","dps",7.0,55,"add"),U("UP_DURATION","dur",0.6,50,"add"),U("UP_AREA","radius",10.0,55,"add")])
	s.call(5,"SPELL_SUMMON_NAME","SPELL_SUMMON_DESC","summon",14.0,true,
		{"hp":80.0,"dmg":10.0,"count":3.0},
		[U("UP_SOLDIERHP","hp",20.0,55,"add"),U("UP_SOLDIERDMG","dmg",3.0,55,"add"),U("UP_COUNT","count",1.0,80,"add")])
	s.call(6,"SPELL_MIDAS_NAME","SPELL_MIDAS_DESC","midas",18.0,false,
		{"gold":120.0,"cd":18.0,"killbonus":0.0},
		[U("UP_GOLDAMOUNT","gold",30.0,55,"add"),U("UP_CD","cd",-1.0,60,"add"),U("UP_KILLGOLD","killbonus",0.05,60,"add")])
	s.call(7,"SPELL_TIMEWARP_NAME","SPELL_TIMEWARP_DESC","timewarp",16.0,false,
		{"slow":0.4,"dur":4.0,"cd":16.0},
		[U("UP_SLOWAMT","slow",0.04,55,"add"),U("UP_DURATION","dur",0.4,50,"add"),U("UP_CD","cd",-0.8,60,"add")])
	s.call(8,"SPELL_WARCRY_NAME","SPELL_WARCRY_DESC","warcry",20.0,false,
		{"haste":0.4,"dur":6.0,"cd":20.0},
		[U("UP_BOOST","haste",0.04,55,"add"),U("UP_DURATION","dur",0.5,50,"add"),U("UP_CD","cd",-1.0,60,"add")])
	s.call(9,"SPELL_BARRIER_NAME","SPELL_BARRIER_DESC","barrier",30.0,false,
		{"block":3.0,"cd":30.0,"reflect":0.0},
		[U("UP_BLOCK","block",1.0,90,"add"),U("UP_CD","cd",-1.5,60,"add"),U("UP_REFLECT","reflect",20.0,60,"add")])
	s.call(10,"SPELL_TORNADO_NAME","SPELL_TORNADO_DESC","tornado",14.0,true,
		{"push":160.0,"count":8.0,"cd":14.0},
		[U("UP_PUSH","push",20.0,55,"add"),U("UP_AFFECTCOUNT","count",2.0,60,"add"),U("UP_CD","cd",-0.7,60,"add")])
	s.call(11,"SPELL_QUAKE_NAME","SPELL_QUAKE_DESC","quake",18.0,false,
		{"pct":0.18,"bossdmg":300.0,"cd":18.0},
		[U("UP_PCTDMG","pct",0.02,60,"add"),U("UP_BOSSFLAT","bossdmg",80.0,60,"add"),U("UP_CD","cd",-0.9,60,"add")])
	s.call(12,"SPELL_FIREWALL_NAME","SPELL_FIREWALL_DESC","firewall",12.0,true,
		{"dps":40.0,"dur":5.0,"length":120.0},
		[U("UP_DPS","dps",10.0,55,"add"),U("UP_DURATION","dur",0.5,50,"add"),U("UP_LENGTH","length",12.0,55,"add")])
	s.call(13,"SPELL_SMITE_NAME","SPELL_SMITE_DESC","smite",10.0,true,
		{"dmg":350.0,"bossmult":0.4,"cd":10.0},
		[U("UP_DAMAGE","dmg",80.0,55,"add"),U("UP_BOSSMULT","bossmult",0.06,60,"add"),U("UP_CD","cd",-0.5,60,"add")])
	s.call(14,"SPELL_EMP_NAME","SPELL_EMP_DESC","emp",16.0,true,
		{"radius":130.0,"dur":2.5,"cd":16.0},
		[U("UP_AREA","radius",12.0,55,"add"),U("UP_DURATION_ALT","dur",0.3,55,"add"),U("UP_CD","cd",-0.8,60,"add")])
	s.call(15,"SPELL_BLACKHOLE_NAME","SPELL_BLACKHOLE_DESC","blackhole",22.0,true,
		{"dur":3.5,"radius":140.0,"dps":30.0},
		[U("UP_DURATION","dur",0.4,55,"add"),U("UP_AREA","radius",12.0,55,"add"),U("UP_DPS","dps",8.0,55,"add")])

# ---------------------------------------------------------------------------
# effective stats given upgrade levels dict {stat_or_dir_index: lv}
# up_levels is an Array[int] length = ups.size(), one level per direction.
# ---------------------------------------------------------------------------
func effective_stats(def: Dictionary, up_levels: Array) -> Dictionary:
	var s := (def.stats as Dictionary).duplicate(true)
	var ups: Array = def.ups
	for i in ups.size():
		var lv: int = up_levels[i] if i < up_levels.size() else 0
		if lv <= 0:
			continue
		var d: Dictionary = ups[i]
		var stat: String = d.stat
		var base: float = def.stats.get(stat, 0.0)
		match d.kind:
			"add":
				s[stat] = s.get(stat, 0.0) + d.step * lv
			"pct":
				s[stat] = base * (1.0 + d.step * lv)
			"prob":
				s[stat] = clampf(s.get(stat, 0.0) + d.step * lv, 0.0, 1.0)
	return s

func upgrade_cost(base_cost: int, current_lv: int) -> int:
	# cost of buying the (current_lv+1)-th level
	return int(round(base_cost * pow(UP_COST_MULT, current_lv)))

func tower_by_id(id: int) -> Dictionary:
	for t in TOWERS:
		if t.id == id:
			return t
	return {}

func spell_by_id(id: int) -> Dictionary:
	for sp in SPELLS:
		if sp.id == id:
			return sp
	return {}

# ---------------------------------------------------------------------------
# LEVEL generation. Infinite levels. Returns config for level N (1-based).
# ---------------------------------------------------------------------------
func level_config(n: int) -> Dictionary:
	# wave scaling: exponential HP/density growth. 1.16 compounds to 17.0x by
	# level 20, which no amount of gold or 魔晶 income could keep up with; 1.13
	# reaches 9.9x, which the (now wave-scaled) economy can actually track.
	var wave_scale := pow(WAVE_GROWTH, n - 1)
	# which families appear this level (2-3 families rotating)
	var base_i := (n - 1) % 10
	var fams := []
	fams.append(FAMILY_ORDER[base_i])
	fams.append(FAMILY_ORDER[(base_i + 3) % 10])
	if n % 2 == 0:
		fams.append(FAMILY_ORDER[(base_i + 6) % 10])
	# creature level band by game level
	var band := int((n - 1) / 9)  # 0 => lv1-2, 1 => lv2-3 ...
	var lmin: int = clampi(1 + band, 1, 5)
	var lmax: int = clampi(2 + band, 1, 5)
	# boss family
	var boss_fam: String = FAMILY_ORDER[base_i]
	# path template index
	var path_idx := (n - 1) % 6
	return {
		"level": n,
		"wave_scale": wave_scale,
		"families": fams,
		"lvl_min": lmin,
		"lvl_max": lmax,
		"boss_family": boss_fam,
		"path_idx": path_idx,
		"start_gold": 220 + n * 8,
		"boss_time": 60.0,
		"spawn_interval_start": 1.6,
		"spawn_interval_min": 0.45,
	}

# ---------------------------------------------------------------------------
# 魔晶 (meta currency) payouts. All three payout paths live here so the balance
# can be tuned in one place: 通關獎勵 / 首次通關獎勵 / 失敗按進度獎勵.
# ---------------------------------------------------------------------------
## Global multiplier on every 魔晶 payout. All three payout paths (通關 / 首通 /
## 失敗按進度) are expressed as base × this, so the ratios between them — and the
## rules layered on top (重玩減半, 失敗上限 40%, 10 秒內唔派) — are untouched by
## changing it. Round 7 shipped 3.0; dialled back to 2.0 the same day because
## ×3 made 魔晶 feel too plentiful in play (the 10-level sim also had a pure
## unlock-buyer clearing the whole shop by level 10 — see BALANCE_CHANGELOG).
const CRYSTAL_REWARD_MULT := 2.0

func level_crystal_reward(n: int) -> int:
	## 通關獎勵. Meta.on_level_cleared halves this on a replay.
	## Raised from the old 30+6n: it is also the base the 40% loss cap is taken
	## from, and at the old rate a stuck player earned too little per attempt to
	## afford even the cheapest upgrade level (35) after two tries.
	return int(round((36 + n * 8) * CRYSTAL_REWARD_MULT))

func level_first_clear_bonus(n: int) -> int:
	## 首次通關獎勵 — paid ONCE per level, on top of the clear reward. Kept
	## clearly bigger than the clear reward and growing faster with n so that
	## pushing into a NEW level always beats re-farming an old one.
	return int(round((40 + n * 10) * CRYSTAL_REWARD_MULT))

# --- loss payout ------------------------------------------------------------
# Losing pays a small progress-based amount so a failed run still feeds the
# 輸 -> 升級 -> 過到 loop. Progress is a weighted blend of how far into the
# wave you survived, how much you killed, and (if the boss showed up) how deep
# you cut into its HP. It is capped well below a clear so clearing always wins.
const LOSE_MIN_TIME := 10.0          # 開場 10 秒內結束嘅局唔派 (防秒退刷)
const LOSE_REWARD_CAP_FRAC := 0.40   # 上限 = 通關獎勵 * 40%
const LOSE_W_TIME := 0.35            # 捱到嘅時間 (滿分 = 撐到 boss 出場)
const LOSE_W_KILLS := 0.35           # 擊殺數
const LOSE_W_BOSS := 0.30            # 對 boss 造成嘅最大傷害百分比
const LOSE_EXPECTED_KILLS := 45.0    # boss 出場前大約刷出嘅怪數 = 擊殺分滿分線

func level_lose_cap(n: int) -> int:
	return int(floor(level_crystal_reward(n) * LOSE_REWARD_CAP_FRAC))

func lose_progress(kills: int, elapsed: float, boss_time_s: float, boss_frac: float) -> float:
	var t := clampf(elapsed / maxf(1.0, boss_time_s), 0.0, 1.0)
	var k := clampf(float(kills) / LOSE_EXPECTED_KILLS, 0.0, 1.0)
	var b := clampf(boss_frac, 0.0, 1.0)
	return clampf(LOSE_W_TIME * t + LOSE_W_KILLS * k + LOSE_W_BOSS * b, 0.0, 1.0)

func level_lose_reward(n: int, kills: int, elapsed: float, boss_time_s: float, boss_frac: float) -> int:
	if elapsed < LOSE_MIN_TIME:
		return 0
	var p := lose_progress(kills, elapsed, boss_time_s, boss_frac)
	if p <= 0.0:
		return 0
	# any real attempt past the anti-farm window pays at least 1
	return maxi(1, int(round(level_lose_cap(n) * p)))

func _ready() -> void:
	_build_towers()
	_build_spells()
