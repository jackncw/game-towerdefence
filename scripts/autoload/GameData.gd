extends Node
## Central static data: monster families, towers, spells, level generation.
## All balance numbers live here. Effective-stat computation also lives here so
## battle logic and UI share one source of truth.

const MAX_UP_LV := 15
const UP_COST_MULT := 1.35
## 每關敵人強度成長率 (wave_scale = WAVE_GROWTH^(n-1))
##
## 第十輪加咗第二段。理由唔係「後面要難啲」呢種感覺,係一個量出嚟嘅斷層:
## 二十關嘅曲線係喺一個「冇進化系統、而且六條軸永遠課唔滿」嘅世界入面
## 定同量嘅。進化上線之後,一個專精玩家喺第 24 關拎到 tier 2(輸出 x16)、
## 第 38 關拎到 tier 3(再 x16),而敵人喺 20→40 淨係 1.13^20 = 11.5 倍。
## BalanceSim --evolve 量到嘅結果就係一次過通過率 40/40 —— 難度曲線唔係
## 「變淺咗」,係由第 20 關開始就冇咗。
##
## 所以第 21 關起換一個較急嘅倍率。呢個唔係一堵牆:牆係「某一關特別難」,
## 而呢個係同一條指數曲線換咗個斜率,每一關都照樣比上一關難少少 ——
## 亦即係 brief 講嘅「沿用現有 wave scaling」。
##
## 第 1-20 關嘅 wave_scale 一個字都冇變(WAVE_LATE_FROM = 21),所以已經
## 量過、已經出過街嗰二十關嘅平衡完全冇被呢個改動掂過。
const WAVE_GROWTH := 1.13
const WAVE_LATE_FROM := 21
const WAVE_GROWTH_LATE := 1.28

## 第 n 關嘅敵人強度倍率。
func wave_scale(n: int) -> float:
	if n < WAVE_LATE_FROM:
		return pow(WAVE_GROWTH, n - 1)
	return pow(WAVE_GROWTH, WAVE_LATE_FROM - 2) \
		* pow(WAVE_GROWTH_LATE, n - WAVE_LATE_FROM + 1)
## 冇「基地生命值」呢樣嘢可以睇跌到幾多——一隻怪冇 Barrier 罩住走到底就係直接
## 輸,冧咗都冇一個「跌穿三成」嘅時刻存在。所以「危險」音效改以路程做距離代理:
## 一隻怪嘅路程比例(dist/route.total)第一次跨過呢個值,並且冇 Barrier 罩住
## (base_shield <= 0),就響一次——喺佢行到之前,俾玩家仲有一兩秒反應。行到嗰
## 一刻已經係敗局 jingle 嘅職責,唔係呢個音效嘅。見 Monster._process() /
## Battle._maybe_warn_base_danger()。
const BASE_DANGER_ROUTE_FRAC := 0.85

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
		TOWERS.append({"id":id,"kind":"tower","name":name,"desc":desc,"mech":mech,
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
	# ==== 第十輪:聖光塔由「局部攻速光環」改造成「全圖光環」====
	# 舊「光環範圍」軸係一條純粹買覆蓋率嘅軸 —— 入面冇任何決策,只有
	# 「買多啲一定好啲」。改成全圖之後,決策由「買唔買半徑」變成「擺唔擺
	# 第二座」,而後者先係一個真取捨(遞減疊加,見 HOLY_AURA_STACK)。
	# 空出嚟嗰條軸換成「聖光強度」:光環同時派攻擊力加成,所以聖光塔由
	# 「攻速機」變成「全隊放大器」—— 一個塔位換全場,而佢自己輸出唔強。
	# aurarange 呢個 stat 一併除名:全圖光環根本冇半徑呢個概念。
	t.call(18,"TOWER_HOLY_NAME","TOWER_HOLY_DESC","holy",140,190,
		{"dmg":14.0,"rate":1.2,"range":230.0,"aurahaste":0.1,"aurapower":0.0,"purify":0.0},
		[U("UP_ATK","dmg",4.0,55,"add"),U("UP_RATE","rate",0.1,55,"add"),U("UP_RANGE","range",14.0,45,"add"),
		 U("UP_AURAHASTE","aurahaste",0.02,65,"add"),U("UP_AURAPOWER","aurapower",0.025,60,"add"),U("UP_PURIFY","purify",0.05,70,"prob")])
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
# 巫教族反制 (第十輪 B)
#
# 問題唔係「巫師血厚」,係「巫師令其他嘢唔會死」—— 治療同加速光環。對住一個
# 回得返嘅目標加輸出係一場冇終點嘅軍備競賽,所以呢一組全部都係**削佢個回復**
# 或者**熄佢個光環**,唔係加傷害。
#
# 治療減免做成 Monster 上面一個通用狀態(heal_cut),唔係逐個機制各寫一套:
# 所有治療都經 request_heal(),所以將來加嘅任何治療來源自動受制,而唔係要人
# 記得返去補。同 boss 回復上限一樣,一個 enforcement point。
# ---------------------------------------------------------------------------
## 毒液塔「重傷」:中毒目標所受治療嘅減免。基礎 50%,而且跟住「每層毒傷」
## 一齊深化 —— 嗰條軸本來就係「毒得幾狠」,重傷幅度係同一件事嘅另一面。
const POISON_HEALCUT_BASE := 0.50
const POISON_HEALCUT_PER_PSTACK := 0.012
const POISON_HEALCUT_MAX := 0.85
## 光束塔「融甲蝕魔」:每級同時削幾多護甲同魔抗(舊版只削護甲,而且係當成
## 易傷處理,對魔抗 25 嘅幽靈完全冇用)。
const BEAM_SHRED_ARMOR := 0.45
const BEAM_SHRED_MRES := 0.55
const BEAM_SHRED_DUR := 2.5
## 「支援型單位」= 靠光環支撐同伴嘅族群。狙擊 / 導彈嘅優先目標、天雷誅殺嘅
## 增傷、黎明聖壇嘅增傷全部問呢一條。用 mech 而唔係 fam 名:任何將來加嘅
## 光環族自動計入。
const SUPPORT_MECHS := ["aura"]
const SUPPORT_BOSS_MECHS := ["mass_heal"]

func is_support_mech(mech_id: String, boss_mech_id: String) -> bool:
	return mech_id in SUPPORT_MECHS or boss_mech_id in SUPPORT_BOSS_MECHS

# ---------------------------------------------------------------------------
# 聖光塔全圖光環 (第十輪 C)
#
# 冇範圍限制之後,唯一嘅決策就係「擺幾多座」,所以疊加規則就係呢座塔嘅
# 全部平衡。遞減得夠急,第五座先唔會變成「再抄一次全場」——
# 1.00 / 0.60 / 0.30 / 0.15 / 0.08…:兩座 = 1.6 倍,五座 = 2.13 倍,
# 即係第二座抵、第五座唔抵,而嗰個正正就係要玩家答嘅問題。
# ---------------------------------------------------------------------------
const HOLY_AURA_STACK := [1.0, 0.6, 0.3, 0.15, 0.08]
const HOLY_AURA_STACK_TAIL := 0.04

func holy_stack_factor(index: int) -> float:
	return HOLY_AURA_STACK[index] if index < HOLY_AURA_STACK.size() else HOLY_AURA_STACK_TAIL

# ---------------------------------------------------------------------------
# 進化系統 (第十輪 D)
#
# 三級 tier。條件係「該項全部升級軸課滿 15 級」+ 一筆大額進化魔晶。
#
# 三個唔顯然嘅決定:
#
#  1. **倍率只打落「每秒輸出」嗰類 stat。** 射程、持續時間、機率、數量全部
#     唔乘 —— 一座 tier 3 塔唔應該有 256 倍射程,而一個 0.05 嘅機率乘 256
#     根本冇意義(封頂 1.0)。
#  2. **升級步長跟住同一個倍率放大。** 唔係嘅話 tier 3 一座塔嘅「+3 攻擊/級」
#     相對佢自己嘅基礎值細到冇意義,六條軸就變成裝飾。
#  3. **費用曲線接續,唔係重頭計。** upgrade_cost 收一個**全域**級數
#     lv + MAX_UP_LV*(tier-1),所以 tier 2 嘅第一級已經貴過 tier 1 嘅第十五級。
#     「進化唔係重來,係繼續」呢句嘢喺數字上面就係咁講。
#
# --- 逐階倍率點揀 (第十一輪重訂) --------------------------------------------
#
# 設計目標:**tier N+1 基礎 ≈ tier N 滿課 x 1.15**。即係話進化嗰一下要明顯
# 強過你之前課到盡嘅嘢(所以佢係一個躍升),但唔可以強到令新開嘅十五級變成
# 裝飾(所以佢唔係一個斷層,進化完仲有嘢追)。
#
# 呢個比例由兩樣嘢決定,而只有一樣係我哋揀嘅:
#   R    = 一件嘢六條(或者三條)軸課滿之後係佢自己基礎值嘅幾多倍 —— 由 ups 表決定
#   STEP = 逐階倍率 —— 我哋揀
#   tier N+1 基礎 / tier N 滿課 = STEP / R
# 所以 STEP = 1.15 x R。
#
# 第十輪用一個 16 服侍晒塔同魔法,而嗰個就係「進化上 tier 2 之後面板全部頂爆」
# 嘅來源。tools/tier_curve.gd 量到嘅 R 分佈解釋咗點解一個數服侍唔到兩邊:
#
#   塔  (六條軸)  R 中位數 12.75  ->  16 / 12.75 = 1.26 倍  (略高過目標)
#   魔法 (三條軸)  R 中位數  4.90  ->  16 /  4.90 = 3.27 倍  (**斷層**)
#
# 魔法只得三條軸,而其中一條通常係冷卻(唔係輸出),所以佢哋課到盡都只係
# 基礎值嘅五倍左右。同一個 16 打落去,一個 tier 2 魔法一出世就已經係佢
# tier 1 課足十五級嘅三倍幾 —— 之前課嗰十五級全部一鋪清袋。
#
# 所以兩邊各有各嘅 STEP,而兩個數都係由量出嚟嗰個 R 乘 1.15 得返:
const MAX_TIER := 3
## 進化嗰一下相對「上一階課到盡」嘅躍升幅度。
const TIER_JUMP := 1.15
## tools/tier_curve.gd 量到嘅 R 中位數。改咗 ups 表就要重跑佢再改呢兩個數,
## 唔係嘅話上面條 1.15 就變成一句冇兌現嘅說話。
const TOWER_AXIS_GAIN := 6.0
const SPELL_AXIS_GAIN := 4.9
const TIER_STEP_TOWER := TIER_JUMP * TOWER_AXIS_GAIN     # 14.66
const TIER_STEP_SPELL := TIER_JUMP * SPELL_AXIS_GAIN     # 5.64
## 跟住 tier 放大嘅 stat。全部都係「每秒幾多輸出 / 幾多金 / 幾多血」嗰類。
const TIER_SCALED_STATS := ["dmg", "dps", "pulse", "bleed", "pstack", "burn",
	"gold", "startgold", "soldierhp", "bossdmg", "hp", "reflect", "block"]

## 一件嘢喺第 `tier` 階嘅輸出倍率。塔同魔法唔同 step —— 見上面。
func tier_power(tier: int, is_tower := true) -> float:
	var step: float = TIER_STEP_TOWER if is_tower else TIER_STEP_SPELL
	return pow(step, clampi(tier, 1, MAX_TIER) - 1)

## 一個 def 係塔定魔法。`kind` 由 _build_towers / _build_spells 落,所以
## effective_stats() 唔使呼叫端話俾佢知 —— 一個要靠呼叫端記得傳嘅參數
## 遲早會有一個呼叫端唔記得傳,而嗰次就係一座塔靜靜咁用咗魔法嘅倍率。
static func def_is_tower(def: Dictionary) -> bool:
	return String(def.get("kind", "tower")) == "tower"

## 進化費。塔貴過魔法(六軸 vs 三軸,而且塔係場上嘅實體),第三階貴過第二階
## 四倍 —— 進化本身要係一個「儲一排」嘅決定,唔係順手撳嘅。
const EVOLVE_COST_TOWER := [0, 0, 6000, 24000]
const EVOLVE_COST_SPELL := [0, 0, 3600, 14400]

func evolve_cost(is_tower: bool, to_tier: int) -> int:
	var tbl: Array = EVOLVE_COST_TOWER if is_tower else EVOLVE_COST_SPELL
	return int(tbl[clampi(to_tier, 0, MAX_TIER)])

## 名 + 新機制一句。105 項嘅完整表 = 呢兩個字典 + tier 1 嘅原名,
## tools/dump_tiers.gd 直接由呢度 dump 出報告,所以報告同實際行為講唔埋
## 呢件事係冇可能發生。
var TOWER_TIERS := {}
var SPELL_TIERS := {}

func _tier(store: Dictionary, id: int, tier: int, name: String, mech: String) -> void:
	if not store.has(id):
		store[id] = {}
	store[id][tier] = {"name": name, "mech": mech}

func _build_tiers() -> void:
	var TT := func(id, t, n, m): _tier(TOWER_TIERS, id, t, n, m)
	TT.call(1, 2, "TOWER_ARROW_T2_NAME", "TOWER_ARROW_T2_MECH")
	TT.call(1, 3, "TOWER_ARROW_T3_NAME", "TOWER_ARROW_T3_MECH")
	TT.call(2, 2, "TOWER_CANNON_T2_NAME", "TOWER_CANNON_T2_MECH")
	TT.call(2, 3, "TOWER_CANNON_T3_NAME", "TOWER_CANNON_T3_MECH")
	TT.call(3, 2, "TOWER_LIGHTNING_T2_NAME", "TOWER_LIGHTNING_T2_MECH")
	TT.call(3, 3, "TOWER_LIGHTNING_T3_NAME", "TOWER_LIGHTNING_T3_MECH")
	TT.call(4, 2, "TOWER_FIREBALL_T2_NAME", "TOWER_FIREBALL_T2_MECH")
	TT.call(4, 3, "TOWER_FIREBALL_T3_NAME", "TOWER_FIREBALL_T3_MECH")
	TT.call(5, 2, "TOWER_FROST_T2_NAME", "TOWER_FROST_T2_MECH")
	TT.call(5, 3, "TOWER_FROST_T3_NAME", "TOWER_FROST_T3_MECH")
	TT.call(6, 2, "TOWER_POISON_T2_NAME", "TOWER_POISON_T2_MECH")
	TT.call(6, 3, "TOWER_POISON_T3_NAME", "TOWER_POISON_T3_MECH")
	TT.call(7, 2, "TOWER_SNIPER_T2_NAME", "TOWER_SNIPER_T2_MECH")
	TT.call(7, 3, "TOWER_SNIPER_T3_NAME", "TOWER_SNIPER_T3_MECH")
	TT.call(8, 2, "TOWER_GATLING_T2_NAME", "TOWER_GATLING_T2_MECH")
	TT.call(8, 3, "TOWER_GATLING_T3_NAME", "TOWER_GATLING_T3_MECH")
	TT.call(9, 2, "TOWER_MORTAR_T2_NAME", "TOWER_MORTAR_T2_MECH")
	TT.call(9, 3, "TOWER_MORTAR_T3_NAME", "TOWER_MORTAR_T3_MECH")
	TT.call(10, 2, "TOWER_BEAM_T2_NAME", "TOWER_BEAM_T2_MECH")
	TT.call(10, 3, "TOWER_BEAM_T3_NAME", "TOWER_BEAM_T3_MECH")
	TT.call(11, 2, "TOWER_SLOWFIELD_T2_NAME", "TOWER_SLOWFIELD_T2_MECH")
	TT.call(11, 3, "TOWER_SLOWFIELD_T3_NAME", "TOWER_SLOWFIELD_T3_MECH")
	TT.call(12, 2, "TOWER_ALCHEMY_T2_NAME", "TOWER_ALCHEMY_T2_MECH")
	TT.call(12, 3, "TOWER_ALCHEMY_T3_NAME", "TOWER_ALCHEMY_T3_MECH")
	TT.call(13, 2, "TOWER_BARRACKS_T2_NAME", "TOWER_BARRACKS_T2_MECH")
	TT.call(13, 3, "TOWER_BARRACKS_T3_NAME", "TOWER_BARRACKS_T3_MECH")
	TT.call(14, 2, "TOWER_BOOMERANG_T2_NAME", "TOWER_BOOMERANG_T2_MECH")
	TT.call(14, 3, "TOWER_BOOMERANG_T3_NAME", "TOWER_BOOMERANG_T3_MECH")
	TT.call(15, 2, "TOWER_THORN_T2_NAME", "TOWER_THORN_T2_MECH")
	TT.call(15, 3, "TOWER_THORN_T3_NAME", "TOWER_THORN_T3_MECH")
	TT.call(16, 2, "TOWER_MISSILE_T2_NAME", "TOWER_MISSILE_T2_MECH")
	TT.call(16, 3, "TOWER_MISSILE_T3_NAME", "TOWER_MISSILE_T3_MECH")
	TT.call(17, 2, "TOWER_CURSE_T2_NAME", "TOWER_CURSE_T2_MECH")
	TT.call(17, 3, "TOWER_CURSE_T3_NAME", "TOWER_CURSE_T3_MECH")
	TT.call(18, 2, "TOWER_HOLY_T2_NAME", "TOWER_HOLY_T2_MECH")
	TT.call(18, 3, "TOWER_HOLY_T3_NAME", "TOWER_HOLY_T3_MECH")
	TT.call(19, 2, "TOWER_MAGNET_T2_NAME", "TOWER_MAGNET_T2_MECH")
	TT.call(19, 3, "TOWER_MAGNET_T3_NAME", "TOWER_MAGNET_T3_MECH")
	TT.call(20, 2, "TOWER_TELEPORT_T2_NAME", "TOWER_TELEPORT_T2_MECH")
	TT.call(20, 3, "TOWER_TELEPORT_T3_NAME", "TOWER_TELEPORT_T3_MECH")
	var ST := func(id, t, n, m): _tier(SPELL_TIERS, id, t, n, m)
	ST.call(1, 2, "SPELL_METEOR_T2_NAME", "SPELL_METEOR_T2_MECH")
	ST.call(1, 3, "SPELL_METEOR_T3_NAME", "SPELL_METEOR_T3_MECH")
	ST.call(2, 2, "SPELL_STORMBOLT_T2_NAME", "SPELL_STORMBOLT_T2_MECH")
	ST.call(2, 3, "SPELL_STORMBOLT_T3_NAME", "SPELL_STORMBOLT_T3_MECH")
	ST.call(3, 2, "SPELL_FREEZENOVA_T2_NAME", "SPELL_FREEZENOVA_T2_MECH")
	ST.call(3, 3, "SPELL_FREEZENOVA_T3_NAME", "SPELL_FREEZENOVA_T3_MECH")
	ST.call(4, 2, "SPELL_MIASMA_T2_NAME", "SPELL_MIASMA_T2_MECH")
	ST.call(4, 3, "SPELL_MIASMA_T3_NAME", "SPELL_MIASMA_T3_MECH")
	ST.call(5, 2, "SPELL_SUMMON_T2_NAME", "SPELL_SUMMON_T2_MECH")
	ST.call(5, 3, "SPELL_SUMMON_T3_NAME", "SPELL_SUMMON_T3_MECH")
	ST.call(6, 2, "SPELL_MIDAS_T2_NAME", "SPELL_MIDAS_T2_MECH")
	ST.call(6, 3, "SPELL_MIDAS_T3_NAME", "SPELL_MIDAS_T3_MECH")
	ST.call(7, 2, "SPELL_TIMEWARP_T2_NAME", "SPELL_TIMEWARP_T2_MECH")
	ST.call(7, 3, "SPELL_TIMEWARP_T3_NAME", "SPELL_TIMEWARP_T3_MECH")
	ST.call(8, 2, "SPELL_WARCRY_T2_NAME", "SPELL_WARCRY_T2_MECH")
	ST.call(8, 3, "SPELL_WARCRY_T3_NAME", "SPELL_WARCRY_T3_MECH")
	ST.call(9, 2, "SPELL_BARRIER_T2_NAME", "SPELL_BARRIER_T2_MECH")
	ST.call(9, 3, "SPELL_BARRIER_T3_NAME", "SPELL_BARRIER_T3_MECH")
	ST.call(10, 2, "SPELL_TORNADO_T2_NAME", "SPELL_TORNADO_T2_MECH")
	ST.call(10, 3, "SPELL_TORNADO_T3_NAME", "SPELL_TORNADO_T3_MECH")
	ST.call(11, 2, "SPELL_QUAKE_T2_NAME", "SPELL_QUAKE_T2_MECH")
	ST.call(11, 3, "SPELL_QUAKE_T3_NAME", "SPELL_QUAKE_T3_MECH")
	ST.call(12, 2, "SPELL_FIREWALL_T2_NAME", "SPELL_FIREWALL_T2_MECH")
	ST.call(12, 3, "SPELL_FIREWALL_T3_NAME", "SPELL_FIREWALL_T3_MECH")
	ST.call(13, 2, "SPELL_SMITE_T2_NAME", "SPELL_SMITE_T2_MECH")
	ST.call(13, 3, "SPELL_SMITE_T3_NAME", "SPELL_SMITE_T3_MECH")
	ST.call(14, 2, "SPELL_EMP_T2_NAME", "SPELL_EMP_T2_MECH")
	ST.call(14, 3, "SPELL_EMP_T3_NAME", "SPELL_EMP_T3_MECH")
	ST.call(15, 2, "SPELL_BLACKHOLE_T2_NAME", "SPELL_BLACKHOLE_T2_MECH")
	ST.call(15, 3, "SPELL_BLACKHOLE_T3_NAME", "SPELL_BLACKHOLE_T3_MECH")

# ---------------------------------------------------------------------------
# 進化機制嘅數值。
#
# 全部擺埋一齊而唔係散落喺 Tower.gd / Spells.gd 入面,同 WAVE_GROWTH 同一個
# 理由:呢啲係**平衡數字**,而平衡數字要喺一個地方睇得晒先調得郁。
# 每一個都寫住佢係邊個 tier 嘅邊個機制,唔使揭返去對。
# ---------------------------------------------------------------------------
## 連續命中同一目標(箭 T2 鷹眼 / 狙 T2 標記 / 導彈 T2 鎖定)
const STREAK_MAX := 6
const STREAK_STEP := 0.08          # 箭塔每層 +8%
const MARK_STEP := 0.04            # 狙擊塔每層 +4%
const LOCKON_STEP := 0.06          # 導彈塔每層 +6%
## 箭 T3 神射殿:每 N 箭必爆兼貫穿
const SAGITTARIAN_EVERY := 5
const PIERCE_LINE_WIDTH := 46.0
## 加農 T3 攻城巨砲:破城彈永久削甲,可疊
const SIEGE_ARMOR_BREAK := 4.0
const SIEGE_ARMOR_BREAK_MAX := 12.0
## 雷電 T2 導電 / T3 落雷
const CONDUCTOR_BONUS := 0.25
const SKYFALL_RADIUS := 110.0
const SKYFALL_FRAC := 0.6
const SKYFALL_STUN := 0.5
## 火球 T2 餘燼 / T3 烈焰連鎖
const EMBER_DPS_FRAC := 0.8
const EMBER_DUR := 3.0
const EMBER_RADIUS := 62.0
## 冰霜 T2 凍傷
const FROSTBITE_FRAC := 0.35
## 毒 —— 重傷持續時間、T2 傳染、T3 崩解
const POISON_HEALCUT_DUR := 4.0
const PLAGUE_TARGETS := 3
const ROT_MAXHP_FRAC := 0.05
const ROT_MAX_TOTAL := 0.40
## 狙擊 T3 天罰:處決線倍率
const JUDGEMENT_EXEC_MULT := 2.2
## 機槍 T2 過熱噴發 / T3 彈鏈共鳴
const CYCLONE_BURST_FRAC := 1.6
const RESONANCE_SPREAD := 0.10
## 迫擊 T2 齊射 / T3 校射
const HEAVY_BATTERY_OFFSET := 90.0
const RANGEFIND_RADIUS := 120.0
const RANGEFIND_MAX := 3.0
const RANGEFIND_DMG := 0.15
const RANGEFIND_AREA := 0.20
## 光束 T2 折射 / T3 聚能爆發
const PRISM_RANGE := 180.0
const PRISM_FRAC := 0.5
const STELLAR_BURST_MULT := 2.5
const STELLAR_BURST_DUR := 3.0
## 力場 T2 牽引 / T3 時停
const GRAVITY_PULL := 26.0         # 每秒拉返幾多路程
const CHRONAL_PERIOD := 8.0
const CHRONAL_FREEZE := 1.0
## 鍊金 T2 金線
const FOUNDRY_STEP := 0.15
const FOUNDRY_FALLOFF := 0.7
## 兵營 T2 陣型 / T3 不屈
const FORMATION_RADIUS := 90.0
const FORMATION_ARMOR := 0.25
const FORMATION_DMG := 0.15
const TEMPLAR_BLAST := 6.0         # 陣亡爆炸傷害 = 士兵傷害 x 呢個
const TEMPLAR_BLAST_RADIUS := 90.0
## 迴旋鏢 T2 交叉 / T3 無盡迴旋
const TWINBLADE_ANGLE := 0.42      # 弧度
const TEMPEST_RETHROW := 0.35
## 荊棘 T2 纏繞 / T3 根系
const ENSNARE_DUR := 0.4
const WORLDROOT_LENGTH := 2.4
## 導彈 T3 核心彈頭
const DOOMSDAY_EVERY := 4
const DOOMSDAY_DMG := 3.0
const DOOMSDAY_AREA := 2.0
## 詛咒 T2 恐懼 / T3 獻祭
const DREAD_PERIOD := 2.2
const DREAD_PUSH := 34.0
const VOID_CHARGE_FULL := 24.0
const VOID_BURST := 90.0
## 聖光 T2 聖裁 / T3 復甦之光
const DAWN_SUPPORT_MULT := 1.5
const DAWN_AURA_CRIT := 0.10
const ORACLE_PERIOD := 12.0
## 磁力 T2 磁軌 / T3 極性反轉
const RAILSLAM_STEP := 0.30
const RAILSLAM_MAX := 4
const POLARITY_EVERY := 3
## 傳送 T3 放逐
const BANISH_CHANCE := 0.30

# --- 魔法進化機制 -----------------------------------------------------------
## 隕石 T2 隕石風暴 / T3 天隕滅世
const METEOR_SHOWER_COUNT := 3
const METEOR_SHOWER_FRAC := 0.35
const CATACLYSM_DPS_FRAC := 0.22
const CATACLYSM_DUR := 5.0
## 閃電風暴 T2 雷神之怒 / T3 萬雷天罰
const WRATH_SPLASH := 70.0
const WRATH_SPLASH_FRAC := 0.45
const SKYFALL_VULN := 0.20
const SKYFALL_VULN_DUR := 4.0
## 冰凍新星 T2 絕對零度 / T3 永凍紀元
const ABSZERO_VULN := 0.30
const ICEAGE_RADIUS := 520.0
const ICEAGE_EXTRA := 6.0
## 劇毒瘴氣 T2 腐蝕之霧
const CORROSIVE_ARMOR := 6.0
## 召喚 T3 英靈殿軍
const EINHERJAR_BLAST := 4.0
## 點金 T2 黃金洪流 / T3 邁達斯權柄
const GOLDEN_TIDE_BONUS := 0.50
const GOLDEN_TIDE_DUR := 10.0
const MIDAS_HIT_GOLD := 1
## 時間扭曲 T2 時之枷鎖 / T3 時光倒流
const CHRONO_ABILITY_SLOW := 0.50
const REWIND_SECONDS := 2.0
## 戰吼 T2 軍團號令 / T3 戰神降臨
const LEGION_POWER := 0.15
const AVATAR_SPLASH := 0.10
## 守護結界 T2 聖域屏障 / T3 不滅堡壘
const SANCTUARY_RADIUS := 230.0
const SANCTUARY_DPS_FRAC := 0.6
const SANCTUARY_DPS_MIN := 18.0
const SANCTUARY_DUR := 12.0
const BULWARK_REGEN_CAP := 4
## 龍捲風 T2 颶風之眼 / T3 天災風暴
const EYE_RADIUS := 150.0
const EYE_DUR := 3.0
const EYE_SLOW := 0.55
const GALE_TRUE_FRAC := 0.20
## 地震 T2 大地撕裂 / T3 世界崩塌
const RIFT_SLOW := 0.40
const RIFT_DUR := 3.0
const SHATTER_STUN := 1.2
const SHATTER_GROUND_DUR := 4.0
## 烈焰之牆 T2 煉獄之牆 / T3 不熄業火
const INFERNAL_ADVANCE := 55.0     # 每秒沿路推幾多路程
const PYRE_FEED := 0.6             # 每個死喺入面嘅敵人延長幾多秒
## 天雷誅殺 T2 神罰之矛
const SPEAR_SUPPORT_MULT := 1.2
## 磁暴脈衝 T2 癱瘓脈衝 / T3 系統崩潰
const PARALYSIS_AREA := 1.5
const PARALYSIS_DUR := 1.6
const BLACKOUT_LOCK := 5.0
## 黑洞 T2 奇點 / T3 事件視界
const SINGULARITY_RAMP := 0.35     # 每秒遞增幾多倍
const HORIZON_IMPLODE := 0.50      # 收場還返累積傷害嘅幾多

## 一件嘢喺某一階嘅顯示名。tier 1 就係佢原本個名。
func tier_name(def: Dictionary, is_tower: bool, tier: int) -> String:
	if tier <= 1:
		return String(def.get("name", ""))
	var store: Dictionary = TOWER_TIERS if is_tower else SPELL_TIERS
	var e: Dictionary = store.get(int(def.get("id", 0)), {})
	return String((e.get(tier, {}) as Dictionary).get("name", def.get("name", "")))

## 該階新增機制嘅一句描述。tier 1 冇「新機制」,返空字串。
func tier_mech_key(def: Dictionary, is_tower: bool, tier: int) -> String:
	if tier <= 1:
		return ""
	var store: Dictionary = TOWER_TIERS if is_tower else SPELL_TIERS
	var e: Dictionary = store.get(int(def.get("id", 0)), {})
	return String((e.get(tier, {}) as Dictionary).get("mech", ""))

# ---------------------------------------------------------------------------
# SPELLS (15). Each: id,name,desc,mech,cd(sec),needs_target(bool),
# stats{}, ups[3] {name,stat,step,base_cost,kind}
# ---------------------------------------------------------------------------
var SPELLS := []

func _build_spells() -> void:
	# `extra` 收 curve / control / 呢類唔係「一個數」嘅嘢。放最後而且有預設值,
	# 所以冇呢啲嘢嘅魔法一個字都唔使改。
	var s := func(id,name,desc,mech,cd,target,stats,ups,extra={}):
		var d := {"id":id,"kind":"spell","name":name,"desc":desc,"mech":mech,"cd":cd,
			"target":target,"stats":stats,"ups":ups}
		for k in extra:
			d[k] = extra[k]
		SPELLS.append(d)
	# --- 第十二輪:魔法曲線重做 ----------------------------------------------
	# 三件事同時修,而佢哋其實係同一件事嘅三面:
	#
	#   1. **存在感**。怪物血量係指數(第 40 關 wave_scale 1426x),而魔法傷害
	#      係固定絕對值,所以滿級隕石去到第 20 關已經冇聲冇氣。答案唔係「加大
	#      個絕對值」(嗰個追唔到指數),係俾傷害有一份**按目標生命上限**嘅
	#      成份 —— 地震術一直都係咁計,而佢正正就係唯一一個唔會過時嘅魔法。
	#      `dmgpct` / `dpspct` / `bosspct` 就係嗰份。
	#   2. **無縫控場**。凍結/暈眩類本來同時有「加持續」同「減冷卻」兩條軸,
	#      而兩條軸夾埋嘅終點就係「永遠凍住」。控場秒數改用逐階終點曲線,
	#      上限釘死喺冷卻嘅 0.7 以下,而騰出嚟嗰條軸改成一個**唔延長覆蓋**
	#      嘅強化(冰凍新星:凍結期間受傷加成)。
	#   3. **進化倒退**。有天花板嘅維度(秒數、百分比、範圍、冷卻)以前完全
	#      唔跟 tier 走,所以一進化就跌返基礎值。而家全部行 `curve`,而 curve
	#      嘅跨階交界係恆等接駁。
	s.call(1,"SPELL_METEOR_NAME","SPELL_METEOR_DESC","meteor",8.0,true,
		{"dmg":120.0,"radius":120.0,"cd":8.0,"dmgpct":0.0},
		[U("UP_DAMAGE","dmg",30.0,55,"add"),U("UP_AREA","radius",12.0,50,"add"),U("UP_CD","cd",-0.4,60,"add")],
		{"curve":{"radius":[300.0,360.0,420.0],"cd":[5.0,4.5,4.0],
			"dmgpct":[0.06,0.10,0.15]}})
	# 平衡: dmg 45->58 (+29%), bolts 6->7 (+17%)。評測到每秒冷卻傷害只有 18.8,
	# 係全部直傷魔法之中最低(隕石術 144、地震術 130、烈焰之牆 120),而佢冷卻
	# 仲要長過隕石術 —— 冇任何情境揀佢。
	s.call(2,"SPELL_STORMBOLT_NAME","SPELL_STORMBOLT_DESC","stormbolt",12.0,false,
		{"dmg":95.0,"bolts":9.0,"cd":12.0,"dmgpct":0.0},
		[U("UP_DAMAGE","dmg",12.0,55,"add"),U("UP_BOLTS","bolts",1.0,65,"add"),U("UP_CD","cd",-0.6,60,"add")],
		{"curve":{"bolts":[24.0,30.0,36.0],"cd":[6.0,5.2,4.6],
			"dmgpct":[0.05,0.09,0.14]}})
	# 冰凍新星 —— 用戶報上嚟嗰個無限控場就係呢個:滿級持續 7.0 秒、冷卻 4.0 秒。
	# 「減冷卻」嗰條軸拎走咗,換成 `vuln`(凍結期間受傷加成)。呢個唔係隨手揀
	# 嘅代替品:佢係第二階「絕對零度」本來就有嘅機制,而家由一個進化獎勵變成
	# 一條由第一級起就課得到嘅軸 —— 即係話「凍得耐啲」嘅獎勵改成咗「凍住嗰陣
	# 打得痛啲」,強度照升,但**唔會**延長覆蓋。冷卻固定 16 秒。
	s.call(3,"SPELL_FREEZENOVA_NAME","SPELL_FREEZENOVA_DESC","freezenova",16.0,false,
		{"dur":2.0,"slowafter":0.30,"vuln":0.10,"cd":16.0},
		[U("UP_DURATION","dur",0.0,55,"add"),U("UP_SLOWAFTER","slowafter",0.0,55,"add"),U("UP_FROSTVULN","vuln",0.0,60,"add")],
		{"control":"dur",
		 "curve":{"dur":[4.5,7.0,9.0],"slowafter":[0.45,0.58,0.70],
			"vuln":[0.25,0.40,0.60]}})
	# healcut = 範圍內敵人所受治療嘅減免。呢個係巫教族反制嘅魔法半邊:
	# 巫師靠光環治療續命,而「打多啲」對一個回得返嘅目標係冇上限嘅軍備競賽,
	# 「回少啲」先係一個有終點嘅答案。
	# 劇毒瘴氣 —— 減回復由一個固定 0.70 變成一條**課得上去**嘅曲線,而第三階
	# 終點係 1.00,即係喺霧入面完全封住回復。點解要去到 100%:巫教族靠群療
	# 續命,而任何 < 100% 嘅減免都只係將軍備競賽推遲 —— 90% 減免遇著一個回血
	# 夠快嘅陣容仍然係回得返。100% 先係一個**有終點**嘅答案,而佢要行到第三階
	# 先拎到手,所以佢係一個目標,唔係一個預設。
	# 範圍冇咗自己嗰條軸(改咗俾減回復),所以佢跟進化走。
	s.call(4,"SPELL_MIASMA_NAME","SPELL_MIASMA_DESC","miasma",10.0,true,
		{"dps":18.0,"dur":6.0,"radius":110.0,"healcut":0.20,"dpspct":0.0},
		[U("UP_POISONDPS","dps",7.0,55,"add"),U("UP_DURATION","dur",0.0,50,"add"),U("UP_HEALCUT","healcut",0.0,55,"add")],
		{"curve":{"dur":[12.0,15.0,18.0],"healcut":[0.55,0.80,1.00],
			"radius":[180.0,220.0,260.0],"dpspct":[0.014,0.026,0.038]}})
	s.call(5,"SPELL_SUMMON_NAME","SPELL_SUMMON_DESC","summon",14.0,true,
		{"hp":80.0,"dmg":10.0,"count":3.0},
		[U("UP_SOLDIERHP","hp",20.0,55,"add"),U("UP_SOLDIERDMG","dmg",3.0,55,"add"),U("UP_COUNT","count",0.0,80,"add")],
		{"curve":{"count":[8.0,11.0,14.0]}})
	s.call(6,"SPELL_MIDAS_NAME","SPELL_MIDAS_DESC","midas",18.0,false,
		{"gold":120.0,"cd":18.0,"killbonus":0.0},
		[U("UP_GOLDAMOUNT","gold",30.0,55,"add"),U("UP_CD","cd",0.0,60,"add"),U("UP_KILLGOLD","killbonus",0.0,60,"add")],
		{"curve":{"cd":[9.0,7.6,6.6],"killbonus":[0.60,0.85,1.10]}})
	# 時間扭曲 —— 減速封頂 0.65。舊版滿級 slow = 0.4 + 0.04*15 = **1.00**,
	# 即係全場完全停低,而佢自稱係一個「拖慢」魔法。封頂喺 SLOW_IS_CONTROL
	# (0.80)以下,所以佢由頭到尾都係一個減速,唔會偷偷變成一個定身。
	s.call(7,"SPELL_TIMEWARP_NAME","SPELL_TIMEWARP_DESC","timewarp",16.0,false,
		{"slow":0.30,"dur":4.0,"cd":16.0},
		[U("UP_SLOWAMT","slow",0.0,55,"add"),U("UP_DURATION","dur",0.0,50,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"curve":{"slow":[0.45,0.56,0.65],"dur":[5.5,6.5,7.2],"cd":[12.0,11.0,10.5]}})
	s.call(8,"SPELL_WARCRY_NAME","SPELL_WARCRY_DESC","warcry",20.0,false,
		{"haste":0.4,"dur":6.0,"cd":20.0},
		[U("UP_BOOST","haste",0.0,55,"add"),U("UP_DURATION","dur",0.0,50,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"curve":{"haste":[0.80,1.10,1.45],"dur":[10.0,12.0,14.0],"cd":[14.0,12.5,11.5]}})
	s.call(9,"SPELL_BARRIER_NAME","SPELL_BARRIER_DESC","barrier",30.0,false,
		{"block":3.0,"cd":30.0,"reflect":0.0},
		[U("UP_BLOCK","block",1.0,90,"add"),U("UP_CD","cd",0.0,60,"add"),U("UP_REFLECT","reflect",20.0,60,"add")],
		{"curve":{"cd":[18.0,16.0,15.0]}})
	s.call(10,"SPELL_TORNADO_NAME","SPELL_TORNADO_DESC","tornado",14.0,true,
		{"push":160.0,"count":8.0,"cd":14.0},
		[U("UP_PUSH","push",0.0,55,"add"),U("UP_AFFECTCOUNT","count",0.0,60,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"curve":{"push":[460.0,560.0,660.0],"count":[20.0,26.0,32.0],
			"cd":[7.0,6.2,5.6]}})
	# 地震術 —— 佢一直都係唯一一個唔會過時嘅魔法,因為佢本來就係按生命上限
	# 計數。呢一輪做嘅係將佢對 boss 嗰半邊都改成同一個道理(`bosspct`),
	# 因為固定 300 傷害對一個 79 萬血嘅第 40 關 boss 一樣係零。
	# `stunlen` 由一個常數(SHATTER_STUN)變成一個 stat,咁控場不變式先掃得到佢。
	s.call(11,"SPELL_QUAKE_NAME","SPELL_QUAKE_DESC","quake",18.0,false,
		{"pct":0.18,"bossdmg":300.0,"cd":18.0,"bosspct":0.0,"stunlen":0.0},
		[U("UP_PCTDMG","pct",0.0,60,"add"),U("UP_BOSSFLAT","bossdmg",80.0,60,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"control":"stunlen",
		 "curve":{"pct":[0.42,0.62,0.85],"cd":[8.0,7.0,6.5],
			"bosspct":[0.04,0.06,0.09],"stunlen":[0.0,0.0,1.2]}})
	s.call(12,"SPELL_FIREWALL_NAME","SPELL_FIREWALL_DESC","firewall",12.0,true,
		{"dps":40.0,"dur":5.0,"length":120.0,"dpspct":0.0},
		[U("UP_DPS","dps",10.0,55,"add"),U("UP_DURATION","dur",0.0,50,"add"),U("UP_LENGTH","length",0.0,55,"add")],
		{"curve":{"dur":[12.0,14.0,16.0],"length":[300.0,360.0,420.0],
			"dpspct":[0.025,0.040,0.060]}})
	# supportmult = 對「支援型單位」嘅增傷。巫師 / 大祭司係後排關鍵目標,
	# 而一個單體點名法術本來就係為咗「揀邊個死」而存在 —— 呢個加成只係
	# 令佢真係做得到嗰件事。
	s.call(13,"SPELL_SMITE_NAME","SPELL_SMITE_DESC","smite",10.0,true,
		{"dmg":350.0,"bossmult":0.4,"cd":10.0,"supportmult":1.2,"dmgpct":0.0},
		[U("UP_DAMAGE","dmg",80.0,55,"add"),U("UP_BOSSMULT","bossmult",0.0,60,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"curve":{"bossmult":[0.80,1.10,1.45],"cd":[7.0,6.0,5.5],
			"dmgpct":[0.03,0.05,0.08]}})
	# EMP —— 第二個無限控場來源。舊版滿級暈眩 7.0 秒 / 冷卻 4.0 秒,而且第二階
	# 仲要再乘 PARALYSIS_DUR(1.6)—— 即係 11.2 秒暈眩配 4 秒冷卻。兩個乘數
	# (PARALYSIS_AREA / PARALYSIS_DUR)拆走咗,改為直接寫入逐階曲線,因為
	# 一個藏喺 Spells.gd 嘅乘數係掃描斷言睇唔到嘅 —— 而睇唔到就等於守唔到。
	s.call(14,"SPELL_EMP_NAME","SPELL_EMP_DESC","emp",16.0,true,
		{"radius":130.0,"dur":1.2,"cd":16.0},
		[U("UP_AREA","radius",0.0,55,"add"),U("UP_DURATION_ALT","dur",0.0,55,"add"),U("UP_CD","cd",0.0,60,"add")],
		{"control":"dur",
		 "curve":{"radius":[310.0,380.0,450.0],"dur":[2.6,3.8,5.0],
			"cd":[9.0,8.5,8.0]}})
	s.call(15,"SPELL_BLACKHOLE_NAME","SPELL_BLACKHOLE_DESC","blackhole",22.0,true,
		{"dur":3.0,"radius":140.0,"dps":30.0,"cd":22.0,"dpspct":0.0},
		[U("UP_DURATION","dur",0.0,55,"add"),U("UP_AREA","radius",0.0,55,"add"),U("UP_DPS","dps",8.0,55,"add")],
		{"control":"dur",
		 "curve":{"dur":[6.0,8.0,10.0],"radius":[320.0,380.0,440.0],
			"dpspct":[0.030,0.050,0.075]}})

# ---------------------------------------------------------------------------
# effective stats given upgrade levels dict {stat_or_dir_index: lv}
# up_levels is an Array[int] length = ups.size(), one level per direction.
# ---------------------------------------------------------------------------
## `tier` 放大「每秒輸出」嗰類 stat **同埋佢哋自己嗰條軸嘅步長**。
##
## 步長一定要一齊放大:唔係嘅話 tier 3 箭塔嘅基礎傷害係 2560,而「攻擊力」
## 軸每級仲係 +3 —— 十五級加埋 45,對住 2560 等於零。六條軸就會由「進化之後
## 重新開放嘅選擇」變成裝飾品,而條 brief 講明係「重開 15 級繼續課」。
## 一個 stat 課滿之後相對基礎值嘅倍率 R = (base + 15*step) / base。
func stat_ratio(def: Dictionary, stat: String) -> float:
	var base: float = float((def.stats as Dictionary).get(stat, 0.0))
	if base <= 0.0:
		return 1.0
	var add: float = 0.0
	for d in def.ups:
		if String(d.stat) == stat and String(d.kind) == "add":
			add += float(d.step) * MAX_UP_LV
	return maxf(1.0, (base + add) / base)

## 一個 stat 喺第 `tier` 階嘅幾何倍率。
##
## 第十一輪用一個**全域**倍率(塔 14.66 / 魔法 5.64,由 R 嘅**中位數**乘 1.15
## 得返)。中位數嘅意思就係一半嘅嘢喺佢上面 —— 而任何 R > STEP 嘅 stat,
## 進化嗰一刻都會**倒退**:tier N+1 嘅基礎值 (base*STEP) 細過 tier N 課滿
## (base*R)。量到嘅 R 去到塔 51.00 / 魔法 6.00,即係話呢個倒退一直都喺度,
## 只不過冇人逐個 stat 對過數。
##
## 所以倍率改成**逐個 stat**:照用全域 STEP,但如果嗰個 stat 自己嘅 R 要求
## 更高,就跟佢。`max()` 嘅意思係「冇一個 stat 會倒退,而本來冇問題嗰啲
## 一個字都冇變」—— R 細過中位數嘅嘢(佔一半)power 曲線完全同上一輪一樣。
## 註:呢度**唔再**夾一個 `max(glob, JUMP*R)` 落去。
##
## 嗰個下限本來係用嚟擋「進化倒退」嘅,但單調性而家由 effective_stats() 入面
## 條 carry(下一階起點 = 上一階終點)無條件保證,所以個下限係多餘嘅 ——
## 而且佢有害:佢將 dmg 嘅倍率釘死喺 1.15*R_dmg(塔嗰邊 ≈ 14.66),搞到
## TOWER_AXIS_GAIN 由 12.75 調到 2.0 都**量唔到分別**(量過:4.35 同 2.0
## 兩次跑出嚟嘅最深推進一模一樣)。拎走之後呢個常數先至真係一個掣。
func stat_tier_mult(def: Dictionary, stat: String, tier: int) -> float:
	var glob: float = TIER_STEP_TOWER if def_is_tower(def) else TIER_STEP_SPELL
	return pow(glob, clampi(tier, 1, MAX_TIER) - 1)

## 「逐階終點」曲線。`curve[t-1]` = 第 t 階**第 15 級**嗰個值;第 t 階第 0 級
## 就係第 t-1 階嘅終點(第一階由 `stats` 嘅基礎值起)。
##
## 點解唔用幾何倍率:呢啲係**有天花板**嘅維度 —— 控場秒數、減速百分比、
## 減回復百分比。乘 5.64 一階對一個百分比冇意義,而對一個凍結秒數就係
## 「無縫控場」本身。逐階終點寫得出「我想佢喺嗰一階去到幾多」,而且跨階
## 交界係**恆等接駁**(t+1 第 0 級 ≡ t 第 15 級),所以單調性唔使靠斷言去
## 追,佢係砌出嚟就已經成立。
func curve_value(base: float, curve: Array, tier: int, lv: int) -> float:
	var t: int = clampi(tier, 1, MAX_TIER)
	var start: float = base if t <= 1 else float(curve[t - 2])
	var end_v: float = float(curve[t - 1])
	var f: float = clampf(float(lv) / float(MAX_UP_LV), 0.0, 1.0)
	return start + (end_v - start) * f

## 「非輸出」類 stat(射程、射速、暴擊、爆炸範圍…)每一階嘅步長衰減幾多。
##
## 點解要有:單調性(需求 3)要求下一階嘅起點接得住上一階嘅終點,而如果
## 之後仲以**原速**再課十五級,三階夾埋就係一個冇邊界嘅數 —— 射程由 260
## 一路碌到 980,即係全塔覆蓋成塊板,而量出嚟就係第 21-40 關最深推進由 35%
## 塌到 3%(等於散步)。
##
## 0.30 嘅意思係:進化保住你之前課落去嗰啲(唔倒退),但同一條軸喺新一階
## 嘅**邊際**回報大幅收細。射程 500 -> 572 -> 593,仲係升,但唔會離地。
## 輸出類(dmg / dps)唔受呢個影響 —— 佢哋本來就要跟得上指數怪血。
const NONSCALED_STEP_DECAY := 0.30

func _axis_step(d: Dictionary, stat: String, scaled: bool, def: Dictionary, tier: int) -> float:
	if scaled:
		return d.step * stat_tier_mult(def, stat, tier)
	return d.step * pow(NONSCALED_STEP_DECAY, maxi(0, clampi(tier, 1, MAX_TIER) - 1))

func _axis_index(def: Dictionary, stat: String) -> int:
	for i in (def.ups as Array).size():
		if String((def.ups[i] as Dictionary).stat) == stat:
			return i
	return -1

func effective_stats(def: Dictionary, up_levels: Array, tier := 1) -> Dictionary:
	var s := (def.stats as Dictionary).duplicate(true)
	var base_stats: Dictionary = def.stats
	var curves: Dictionary = def.get("curve", {})
	# 1. 幾何倍率 —— 淨係打「輸出」類,而且逐個 stat 自己嘅倍率。
	for stat in s.keys():
		if curves.has(stat):
			continue      # 有曲線嘅唔行倍率,佢自己講晒每一階去到幾多
		if stat in TIER_SCALED_STATS:
			s[stat] = float(s[stat]) * stat_tier_mult(def, stat, tier)
	# 2. 升級軸。
	var ups: Array = def.ups
	for i in ups.size():
		var d: Dictionary = ups[i]
		var stat: String = d.stat
		var lv: int = up_levels[i] if i < up_levels.size() else 0
		if curves.has(stat):
			s[stat] = curve_value(float(base_stats.get(stat, 0.0)), curves[stat], tier, lv)
			continue
		if d.kind == "pct":
			if lv > 0:
				s[stat] = float(s.get(stat, 0.0)) * (1.0 + d.step * lv)
			continue
		# 「進化唔准倒退」嘅通用做法 —— 唔使逐件嘢寫表。
		#
		# 舊版:tier N+1 嘅基礎值 = 原基礎值 × 倍率,而倍率只打「輸出」類 stat。
		# 即係話射速、射程、暴擊率、爆炸範圍、擊退…… 全部一進化就跌返出廠值,
		# 而玩家喺上一階課咗十五級落去嗰啲**一鋪清袋**。掃出嚟係 20 座塔 196 項。
		#
		# 新版:每一階嘅起點 = max(原基礎 × 該階倍率, 上一階課滿嗰個值)。
		# `max` 係關鍵 —— 本來就冇問題嗰啲(輸出類,倍率大過課滿倍率)一個字
		# 都冇變,而會倒退嗰啲就至少接返上一階嘅終點。相等係可以嘅:進化嗰
		# 一刻唔會變差,而跟住十五級係新賺嘅。
		var scaled: bool = stat in TIER_SCALED_STATS
		var lower: bool = stat in LOWER_IS_BETTER
		var base0: float = float(base_stats.get(stat, 0.0))
		var baseline: float = base0
		for t in range(2, clampi(tier, 1, MAX_TIER) + 1):
			var prev_step: float = _axis_step(d, stat, scaled, def, t - 1)
			var prev_max: float = baseline + prev_step * MAX_UP_LV
			var own: float = base0 * (stat_tier_mult(def, stat, t) if scaled else 1.0)
			baseline = minf(own, prev_max) if lower else maxf(own, prev_max)
		var step: float = _axis_step(d, stat, scaled, def, tier)
		if d.kind == "prob":
			# 機率唔跟 tier 放大 —— 一個 0.05 嘅機率乘 256 冇意義(封頂 1.0)。
			# 但步長一定要同上面條 carry 用**同一個** `step`:用返 d.step 嘅話,
			# 該階實際課到嘅值就會大過下一階接得住嗰個起點,而咁樣就係倒退。
			s[stat] = clampf(baseline + step * lv, 0.0, 1.0)
		else:
			s[stat] = baseline + step * lv
	# 3. 有曲線但**冇佔一條升級軸**嘅 stat(dmgpct / healcut 嗰類)。
	#    佢哋跟進化走,唔跟課金走 —— 即係用該階嘅終點值。
	for stat in curves.keys():
		if _axis_index(def, stat) < 0:
			s[stat] = curve_value(float(base_stats.get(stat, 0.0)),
				curves[stat], tier, MAX_UP_LV)
	return s

# ---------------------------------------------------------------------------
# 控場不變式
# ---------------------------------------------------------------------------
## 「愈細愈好」嘅維度。單調性斷言對呢啲要反過嚟睇 —— 一個由 8 秒跌到 4 秒
## 嘅冷卻係變強咗,唔係倒退。
const LOWER_IS_BETTER := ["cd"]

## 一個減速去到幾多先算「等於定咗喺度」。0.80 = 得返兩成速度。
const SLOW_IS_CONTROL := 0.80
## 控場持續時間相對冷卻嘅上限。dur < cd * 呢個數。
const CONTROL_MAX_CD_FRAC := 0.7

## 一個魔法喺呢個配置之下,**最長嗰段連續控場**有幾多秒,同埋佢嘅冷卻。
## `def.control` 講明邊個 stat 係控場窗口(冇 = 唔控場)。
##
## 點解要有一個 function 而唔係喺測試度逐款寫:一條「唔准無縫控場」嘅規矩
## 如果每加一款魔法都要有人記得去測試度補一行,佢就唔係一條規矩,係一個
## 習慣。呢度係唯一嘅出數點,測試同遊戲問同一個。
func spell_control(def: Dictionary, up_levels: Array, tier := 1) -> Dictionary:
	var s := effective_stats(def, up_levels, tier)
	var out := {"dur": 0.0, "cd": float(s.get("cd", def.get("cd", 0.0))), "kind": ""}
	var c: String = String(def.get("control", ""))
	if c != "" and s.has(c):
		out["dur"] = float(s[c])
		out["kind"] = c
	# 一個夠深嘅減速同定身冇分別,所以佢要行同一條規矩。
	for stat in ["slow", "slowafter"]:
		if float(s.get(stat, 0.0)) >= SLOW_IS_CONTROL:
			var d: float = float(s.get("dur", 0.0))
			if d > out["dur"]:
				out["dur"] = d
				out["kind"] = stat
	return out

## 升級價曲線 —— 兩段。
##
## 舊版係一條純幾何線 base * 1.35^lv,而喺 15 級之下佢嘅尾巴大到荒謬:
## 第 15 級收 base * 1.35^14 = 45 倍 base,亦即係**最後三級貴過頭十二級加埋**。
## 呢件事一直冇人察覺,係因為冇任何嘢需要「六條軸全部課滿」——
## 而進化嘅門檻正正就係嗰件事。第一次量度(BalanceSim --evolve)拎到嘅答案係
## tier 2 喺第 32 關先出現,而目標係 15-25;拆開條數之後,樽頸唔係進化費
## (6000,佔 7%),係六條軸嘅尾巴(75000,佔 88%)。
##
## 所以尾段換一個較平嘅倍率:頭 KNEE 級照舊 1.35(早期每一級都要係一個
## 感覺得到嘅決定),之後轉 1.10。六條軸課滿由 254.6 x base 跌到 96.6 x base
## (38%),而頭六級一個仙都冇平過 —— 即係話呢個改動完全冇掂到頭十五關嘅
## 節奏,佢淨係令一條**本來冇人行得完**嘅路變成行得完。
##
## 注意:C(N)(玩家下一級升級嘅中位價,見 UPGRADE_COST_BASE)係由呢條曲線
## 量出嚟嘅,而敗仗獎勵釘住 C(N)。改完呢度就要重跑 --curve 再擬合,唔係
## 敗仗獎勵會靜靜咁飄離佢應該追蹤嗰樣嘢。
const UP_COST_KNEE := 6
const UP_COST_MULT_LATE := 1.10

func upgrade_cost(base_cost: int, current_lv: int) -> int:
	# cost of buying the (current_lv+1)-th level
	var head: int = mini(maxi(0, current_lv), UP_COST_KNEE)
	var tail: int = maxi(0, current_lv - UP_COST_KNEE)
	return int(round(base_cost * pow(UP_COST_MULT, head) * pow(UP_COST_MULT_LATE, tail)))

## 同一條曲線,但級數係**全域**嘅:tier 2 嘅第 0 級接住 tier 1 嘅第 15 級。
## 所以進化之後嗰六條軸唔係「平返晒重新嚟過」,而係繼續向上 —— 呢個係
## 「進化唔係重來」呢句設計話喺價錢上面嘅講法,亦都係防止玩家靠進化
## 洗白一個貴嘅升級軸。
func upgrade_cost_at(base_cost: int, current_lv: int, tier: int) -> int:
	return upgrade_cost(base_cost, current_lv + MAX_UP_LV * (clampi(tier, 1, MAX_TIER) - 1))

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
# 難度牆 —— 機制留住,內容**故意清空**。
#
# 「牆」係指「第一次到呢關預期會輸,投資之後就過到」嘅關卡,用嚟定期觸發
# 「輸 -> 升級 -> 過到」呢個主循環。第九輪整套起咗、量咗,然後**冇出街**:
# 量度做唔到設計目標,而出一批未達標嘅牆會令二十關嘅難度曲線變差。
# `WALLS` 係空嘅,所以 level_config() 對每一關嘅行為同加牆之前一模一樣。
#
# 要重新開返呢個功能嘅人:**先讀完下面四件事**,唔好由零再試一次。
# 完整數字喺 BALANCE_CHANGELOG.md「第九輪」,量度工具係 BalanceSim --walls。
#
#   1. `add_fams`(喺家族名單後面加)方向係錯嘅,已經移除。
#      _spawn_wave_monster() 由 cfg.families **均勻抽**,所以加一個家族 = 溝淡
#      原有每一個。第 7 關基礎係遠古樹妖(13.6 血/金)+ 史萊姆(12.0)—— 全遊戲
#      最貴嗰兩隻;加咗蝙蝠(7.2)+ 信徒(7.1)之後平均由 12.8 跌到 9.5,
#      **幅牆令佢平咗四分一**。而且加怪 -> 多擊殺 -> 多金 -> 多塔(第 7 關由
#      12.5 座變 32 座),每幅加怪嘅牆都自己出錢買起自己嘅解藥。
#
#   2. `pool`(整個取代家族名單,語義同 BOSS_SPAWN 嘅 `pool` 一樣)係啱嘅機制,
#      而且有效:同一幅牆嘅「最遠推進」由 11% 升到 96%,由「贏到離晒譜」變成
#      「真係差啲守唔住」。呢條路仲喺度,見 level_config() 下面。
#
#   3. 但 level_config() 只讀 `pool` 同 `spawn_min`,而家族表嘅血/金比只得
#      7.1 到 13.6(1.9 倍),所以**真正令一關變難嘅只有密度**。而密度會蓋過
#      幅牆想教嘅嘢:第 7 關嘅軸係「續航戰」,但要令佢難就要 spawn_min 0.105,
#      結果同場 162 隻,玩家實際感覺到嘅係「屍體太多」。三幅牆入面只有第 13 關
#      (軸本身就係屍體數)曾經達標 —— 嗰度密度同軸係同一個方向。
#
#   4. 「組成差距」(換陣容玩家 vs 只買升級玩家嘅通過率之差)**由頭到尾冇正過**。
#      即係話冇一幅牆真係逼到人換陣容,而嗰個係牆存在嘅唯一理由。淨係將首通率
#      調入區間但差距仍然係 0,係一張砌出嚟嘅表,唔係一幅牆。
#
# 結論:要令呢件事成立,缺嘅係一個**唔靠密度**嘅難度掣(例如關卡專屬嘅家族強度
# 乘數,或者容許 `pool` 指定權重令貴嘅家族佔多數),唔係再調 spawn_min。
#
# i18n 入面 LEVELSEL_DANGER 同 WALL_HINT_7/13/18 四條 key 特登留低:佢哋唔使錢,
# 而且記錄咗三幅牆本來想教嘅嘢(續航戰 / 屍體數 / 屍體數 x 減傷)。
#
# 週期 20 而唔係 10:10 會令第 17 同第 18 關連住兩幅牆,而「牆與牆之間維持合理
# 操作一次過」係設計目標之一。20 之下間距係 6-5-9 循環。
const WALL_FIRST := 7
const WALL_PERIOD := 20
const WALL_OFFSETS := [0, 6, 11]     # -> 7, 13, 18,然後 27/33/38、47/53/58 …

## 空 = 一幅牆都冇。呢個唔係「仲未填」,係量度之後嘅決定 —— 見上面四點。
## test/WallTest.gd 有一條 assertion 守住佢係空嘅,而且會叫你返嚟讀呢段。
var WALLS := {}

## **時間表**:呢一關係邊一個牆位?返 WALLS 嘅 key(7/13/18),唔喺時間表上面返 0。
##
## 純週期算術,同 WALLS 有冇內容完全無關 —— 即使 WALLS 係空,wall_slot(7) 一樣返 7。
## 想問「呢一關實際上係咪一幅牆」嘅,用 is_wall(),嗰個問嘅係內容。
func wall_slot(n: int) -> int:
	if n < WALL_FIRST:
		return 0
	var k: int = (n - WALL_FIRST) % WALL_PERIOD
	return WALL_FIRST + k if k in WALL_OFFSETS else 0

func wall_def(n: int) -> Dictionary:
	var slot: int = wall_slot(n)
	return WALLS.get(slot, {}) if slot > 0 else {}

## **內容**:呢一關實際上係咪一幅牆?即係「佢喺時間表上面,而且嗰個位有嘢」。
##
## 呢個係大部分呼叫者想要嘅答案,所以個名畀咗佢。WALLS 空嘅時候佢對每一關都返
## false —— 同 level_config(n).is_wall 一致。
##
## 曾經寫成 `wall_slot(n) > 0`(即係問時間表),而嗰個係一個陷阱:WALLS 清空之後,
## is_wall(7) 仍然返 true,所以任何「係牆就標記/警告」嘅 UI 都會喺三關普通關卡上面
## 畫危險標記。要問時間表嘅,直接叫 wall_slot()。
func is_wall(n: int) -> bool:
	return not wall_def(n).is_empty()

func wall_hint_key(n: int) -> String:
	return String(wall_def(n).get("hint", ""))

# ---------------------------------------------------------------------------
# LEVEL generation. Infinite levels. Returns config for level N (1-based).
# ---------------------------------------------------------------------------
func level_config(n: int) -> Dictionary:
	# wave scaling: exponential HP/density growth. 1.16 compounds to 17.0x by
	# level 20, which no amount of gold or 魔晶 income could keep up with; 1.13
	# reaches 9.9x, which the (now wave-scaled) economy can actually track.
	# 第 21 關起轉第二段斜率 —— 見 WAVE_GROWTH_LATE。
	var wave_scale := self.wave_scale(n)
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
	var cfg := {
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
		"is_wall": false,
	}
	# 難度牆疊喺程序生成之上。Battle.gd 完全唔知道有「牆」呢回事 —— 佢照讀
	# families / spawn_interval_min,所以牆嘅每一個改動都留喺呢個檔案入面。
	var w: Dictionary = wall_def(n)
	if not w.is_empty():
		# `pool` REPLACES the family list, exactly as GameData.BOSS_SPAWN's `pool`
		# does for the boss phase. Appending was tried in round 9 and measured to
		# make two of the three walls EASIER than their neighbours — see the WALLS
		# comment above for the numbers.
		if w.has("pool"):
			var pool: Array = []
			for f in w["pool"]:
				if not (String(f) in pool):     # 重複會令均勻抽變咗加權抽
					pool.append(String(f))
			cfg["families"] = pool
		if w.has("spawn_min"):
			cfg["spawn_interval_min"] = float(w["spawn_min"])
		cfg["is_wall"] = true
	return cfg

# ---------------------------------------------------------------------------
# 魔晶 (meta currency) payouts. All three payout paths live here so the balance
# can be tuned in one place: 通關獎勵 / 首次通關獎勵 / 失敗按進度獎勵.
# ---------------------------------------------------------------------------
## Global multiplier on every 魔晶 payout, kept as the single dial to turn if the
## whole economy needs shifting. The round-8 recalibration is baked into the base
## constants below instead, so this sits at 1.0.
const CRYSTAL_REWARD_MULT := 1.0

## Round 8: the payouts are GEOMETRIC, not linear.
##
## The old 36+8n / 40+10n were flat lines under an upgrade cost curve that is
## base*1.35^lv, so they fell further behind every level. `--curve` measured the
## gap: 通關/C(N) — the clear reward over the price of the player's next upgrade
## level — drifted from 1.38 at level 5 down to 0.81 at level 20. Payouts now
## grow at REWARD_GROWTH per level, which holds that ratio roughly flat instead.
##
## The starting values are the old numbers at ×3 (the floor this round was told
## not to go below: 3*(36+8) = 132 and 3*(40+10) = 150), and every later level
## pays MORE than the old ×3 line did, because 1.13 > the old curve's effective
## 1.082 growth.
const REWARD_GROWTH := 1.13
const REWARD_BASE_CLEAR := 132.0
const REWARD_BASE_FIRST := 150.0

func level_crystal_reward(n: int) -> int:
	## 通關獎勵. Meta.on_level_cleared halves this on a replay.
	return int(round(REWARD_BASE_CLEAR * pow(REWARD_GROWTH, n - 1) * CRYSTAL_REWARD_MULT))

func level_first_clear_bonus(n: int) -> int:
	## 首次通關獎勵 — paid ONCE per level, on top of the clear reward, so pushing
	## into a NEW level always beats re-farming an old one.
	return int(round(REWARD_BASE_FIRST * pow(REWARD_GROWTH, n - 1) * CRYSTAL_REWARD_MULT))

# --- the measured cost curve ------------------------------------------------
## C(N): what the player's NEXT upgrade level costs by the time they reach level
## N. This is MEASURED, not designed — `BalanceSim --curve` samples the median
## next-level price across the axes a reasonable player is actually investing in,
## and these two numbers are the geometric fit to that table (45 -> 804 over 20
## levels).
##
## It has to be measured because it is ENDOGENOUS: pay the player more and they
## buy deeper, so their next upgrade costs more. Round 8 checked this directly by
## running the whole curve at ×3 payouts — C(20) went 242 -> 596 and 通關/C(20)
## landed on 0.99, the same place it sat at ×1. That is why the round-7 answer
## ("turn the multiplier up") could not work, and why the loss payout below is
## pinned to this curve rather than to a percentage of the clear reward.
##
## If the upgrade cost curve or the payouts move, re-run --curve and refit these,
## or the loss payout silently drifts off the thing it is supposed to track.
##
## 第十輪重新擬合,而且**換咗個模型**。升級價曲線加咗第二段(UP_COST_KNEE)
## 之後,實測 C(N) 由 45 → 804 變成 45 → 439,而舊嘅擬合仍然以 1.1668 增長 ——
## 即係敗仗獎勵由第 13 關起越飄越高,到第 20 關已經係 C(20) 嘅 2.3 倍。呢個
## 唔係「派多咗」咁簡單:敗仗獎勵存在嘅唯一理由就係釘住「輸一場 = 一級升級」,
## 而一個派 2.3 級嘅敗仗會令「贏」變成一個可選項。
##
## 直接換個增長率解決唔到:實測 C(N) 而家喺對數空間係**凹**嘅(頭段 1.178/關,
## 後段 1.082/關),一條幾何線點擬合都會喺中段跌穿實測值 —— 試過對數最小二乘,
## 結果係 20 關入面得 14 關滿足「輸一場 >= 一級」。
##
## 所以呢度用返同一個形狀:兩段。C(N) 之所以係兩段,係因為升級價曲線本身
## 就係兩段 —— 模型跟返被模型嘅嘢嘅形狀,擬合就唔使靠緩衝硬食。
## 實測對照:C(1) 45 vs 45、C(10) 199 vs 199、C(20) 439 vs 438。
const UPGRADE_COST_BASE := 45.0
const UPGRADE_COST_GROWTH := 1.178        # 頭段(對應升級價嘅 1.35 段)
const UPGRADE_COST_GROWTH_LATE := 1.082   # 後段(對應升級價嘅 1.10 段)
const UPGRADE_COST_KNEE := 9              # 以 n-1 計

func typical_upgrade_cost(n: int) -> int:
	var x: int = maxi(1, n) - 1
	var head: int = mini(x, UPGRADE_COST_KNEE)
	var tail: int = maxi(0, x - UPGRADE_COST_KNEE)
	return int(round(UPGRADE_COST_BASE * pow(UPGRADE_COST_GROWTH, head)
		* pow(UPGRADE_COST_GROWTH_LATE, tail)))

# --- loss payout ------------------------------------------------------------
# Losing pays a small progress-based amount so a failed run still feeds the
# 輸 -> 升級 -> 過到 loop. Progress is a weighted blend of how far into the
# wave you survived, how much you killed, and (if the boss showed up) how deep
# you cut into its HP. It is capped well below a clear so clearing always wins.
const LOSE_MIN_TIME := 10.0          # 開場 10 秒內結束嘅局唔派 (防秒退刷)
## 上限 = 通關獎勵 * this. Raised from 0.40 in round 8. The cap is what you would
## get at PERFECT progress (survived to the boss, 45 kills, boss stripped to
## zero) — i.e. a run you almost won. Measured real losses score p = 0.44..0.61,
## so the payout a stuck player actually sees is ~45-55% of a clear, not 90%.
## A first clear still pays 2.2x the very best possible loss.
const LOSE_REWARD_CAP_FRAC := 0.90
## Losing a level you have ALREADY cleared pays this fraction. This is the whole
## anti-farm rule: without it, the cheapest way to earn was to load level 1,
## leak on purpose, and collect a full progress payout forever. A player stuck on
## a NEW level is unaffected and keeps the full amount.
const LOSE_REPLAY_FRAC := 0.30
## 一場「有合理進度」嘅敗仗要實付到一級升級. Progress that scores this much is what
## a real failed attempt measures at — BalanceSim recorded p = 0.44 and 0.61 on
## the two genuine losses it produced — so the payout is calibrated at this point
## on the curve rather than at the (unreachable) top of it.
const LOSE_TYPICAL_PROGRESS := 0.5
## 1.15, not 1.0, because C(N) is measured data with real scatter (levels 13-16
## came in at 327 / 363 / 441 / 449) and the constants above are a smooth
## least-squares fit through it. At 1.10 the fit dips under the measured cost at
## level 7 and the "輸一場 = 一級" promise quietly fails there; 1.15 clears every
## level in the table and still sits inside the 1.0-1.2 design band.
const LOSE_TARGET_C_MULT := 1.15     # 敗仗 / C(N) at typical progress
const LOSE_W_TIME := 0.35            # 捱到嘅時間 (滿分 = 撐到 boss 出場)
const LOSE_W_KILLS := 0.35           # 擊殺數
const LOSE_W_BOSS := 0.30            # 對 boss 造成嘅最大傷害百分比
const LOSE_EXPECTED_KILLS := 45.0    # boss 出場前大約刷出嘅怪數 = 擊殺分滿分線

func level_lose_cap(n: int) -> int:
	return int(floor(level_crystal_reward(n) * LOSE_REWARD_CAP_FRAC))

## The most a loss on level `n` can actually pay. Since round 8 the payout is the
## SMALLER of a cost-curve target and the cap, and which one binds changes with
## the level (the target is lower early, the cap is lower late) — so the fail
## screen must quote this rather than level_lose_cap(), or the number it shows a
## player at low levels is one they can never reach.
func level_lose_max(n: int, replay := false) -> int:
	var m := minf(LOSE_TARGET_C_MULT * float(typical_upgrade_cost(n)) / LOSE_TYPICAL_PROGRESS,
		float(level_lose_cap(n)))
	if replay:
		m *= LOSE_REPLAY_FRAC
	return int(round(m))

func lose_progress(kills: int, elapsed: float, boss_time_s: float, boss_frac: float) -> float:
	var t := clampf(elapsed / maxf(1.0, boss_time_s), 0.0, 1.0)
	var k := clampf(float(kills) / LOSE_EXPECTED_KILLS, 0.0, 1.0)
	var b := clampf(boss_frac, 0.0, 1.0)
	return clampf(LOSE_W_TIME * t + LOSE_W_KILLS * k + LOSE_W_BOSS * b, 0.0, 1.0)

func level_lose_reward(n: int, kills: int, elapsed: float, boss_time_s: float,
		boss_frac: float, replay := false) -> int:
	if elapsed < LOSE_MIN_TIME:
		return 0
	var p := lose_progress(kills, elapsed, boss_time_s, boss_frac)
	if p <= 0.0:
		return 0
	# Pinned to the cost curve, not to a share of the clear reward: the design
	# goal is "一場有進度嘅敗仗 = 一級升級", and at p = LOSE_TYPICAL_PROGRESS this
	# pays exactly LOSE_TARGET_C_MULT x C(N). Linear in p through the origin, so
	# a barely-there attempt still pays barely anything.
	var amount := LOSE_TARGET_C_MULT * float(typical_upgrade_cost(n)) \
		* (p / LOSE_TYPICAL_PROGRESS)
	# The cap only bites at high progress, which is the case where paying a full
	# upgrade level twice over would start to compete with actually winning.
	amount = minf(amount, float(level_lose_cap(n)))
	if replay:
		amount *= LOSE_REPLAY_FRAC
	# any real attempt past the anti-farm window pays at least 1
	return maxi(1, int(round(amount)))

func _ready() -> void:
	_build_towers()
	_build_spells()
	_build_tiers()
