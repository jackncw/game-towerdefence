extends Node
## Central static data: monster families, towers, spells, level generation.
## All balance numbers live here. Effective-stat computation also lives here so
## battle logic and UI share one source of truth.

const MAX_UP_LV := 15
const UP_COST_MULT := 1.35

# ---------------------------------------------------------------------------
# 關卡總數同難度分段 (第十五輪:由 40 關延伸到 100 關)
#
# 舊版係兩段幾何曲線 (1.13 到第 20 關,之後 1.28)。1.28 一路推到第 100 關
# 係 1.28^80 = 2.5e9 倍 —— 唔係「難」,係一個冇人夠火力嘅數。而更加要緊
# 嘅係反方向:實測 --evolve 喺第 21-40 關嘅平均最深推進係 4-11%,即係話
# 一個進化咗嘅玩家由第 20 關開始就係散步。兩件事一齊發生,因為舊曲線嘅
# 斜率同**玩家實際攞得到嘅力量**冇對過數。
#
# 而家逐段對數。每一段對應 brief 嘅一條設計目標,而段嘅斜率係由「嗰一段
# 玩家可以攞到幾多力量」倒推:
#
#   1-10   體驗關     白板玩家要贏得到           -> 最平
#   11-40  逼升級     力量來源 = 升級軸 (~12x)
#   41-70  逼進化一次 力量來源 = tier 2 (~6.9x 再乘軸)
#   71-99  逼雙階段 3 力量來源 = tier 3
#   100    最終關     另外再乘 FINAL_SCALE
#
# 段與段之間係**連續**嘅:每段由上一段嘅終點起,所以冇任何一關會出現
# 「突然平咗」或者跳崖 —— Gate 7(難度單調)喺呢度就已經係砌出嚟嘅,
# 唔使靠斷言去追。
# ---------------------------------------------------------------------------
const FINAL_LEVEL := 100
## `to` = 呢一段最後嗰關;`g` = 段內**難度指數**每關嘅成長率。
##
## 注意呢啲係難度指數嘅斜率,唔係雜兵血量嘅斜率 —— 見 difficulty() / wave_scale()。
## 每一段嘅數字都係由「嗰一段玩家實際攞得到幾多力量」倒推,而嗰個係量出嚟嘅
## (test/GateSim --mode=power 直接行買嘢政策再問 Meta.tower_stats):
##
##   原型      力量上限(以第 1 關做 1)   對應段落
##   A1 穩步   10.4x                       11-40 要收喺呢度以內
##   A2 tier2  77.9x                       41-70
##   A3 tier3  ~400x(未滿課)              71-99
##   A4 滿級   ~550x + 三個滿級魔法         100
## 第二段拆咗做兩截(11-16 同 17-40),而嗰個唔係一個擬合出嚟嘅殘留:
## 第 11 關就係「逼你升級」呢一段嘅入口,而入口本身就要係一個坡。體驗關
## 嘅難度要低到一個乜都冇買嘅玩家都贏得到(Gate 2),而「逼你升級」要求
## 玩家一路企喺邊緣(Gate 3 嘅凍結測試 —— 五關冇升級就打唔郁)。呢兩個
## 要求之間隔咗一個真實嘅距離,而 11-16 就係行完佢嗰六關。
## 七段。三段係**門檻坡**(11-16、41-46、65-70),其餘四段係段內嘅平穩爬升。
##
## 點解要有坡:每一段嘅設計目標之間隔住一個真實嘅距離。第 10 關要平到一個
## 乜都冇買嘅玩家贏得到(Gate 2),而第 17 關開始要一個唔升級就打唔郁嘅
## 玩家企喺邊緣(Gate 3)—— 呢兩個要求之間差咗三倍幾,而三倍幾唔可能喺
## 一關之內出現(嗰個就係一堵牆),亦都唔可以攤勻三十關(嗰個就係兩段
## 目標都達唔到)。坡係中間嗰個答案:六關,每關明顯難咗,但每關都仲係
## 上一關嘅延續。
##
## 41-46 同 65-70 兩段坡對應「逼你進化一次」同「逼你雙階段 3」嘅入口,
## 道理一模一樣。
## ==== 第十八輪:全條曲線重校 ====
## 金幣 v3 令一關嘅塔數由「平均 7 座」變成 20(1-10)→ 33(11-20)→ 42
## (21-40)→ 48(41-50),而舊曲線每一段嘅斜率都係喺「7 座」上面倒推嘅。
## 唔跟住加難度嘅話,量出嚟就係 A1(永不進化嘅原型)喺 41-50 關贏 90%
## —— 亦即係 Jack 實試講嗰句「隨便起幾座塔就輕鬆一次過完前 50 關」嘅
## 模擬版證據。
##
## 補償倍率 M(n) = 新難度 ÷ 第十七輪同一關嘅難度:
##   M(10) 1.76   M(16) 3.83   M(40) 5.75   M(46) 8.45   M(70) 8.66   M(99) 11.5
## 1-10 段特登**唔**補足(塔數 ×2.9 但難度只 ×1.76)—— Gate 2 要求白板玩家
## 贏得到體驗關,而金幣 v3 之下佢哋鋪得起 20 座塔。
##
## 每一段點解係呢個數(調嘅次序就係下面嘅次序,每一步都係一個實測):
const WAVE_BANDS := [
	{"to": 10, "g": 1.150},    # 體驗關
	{"to": 16, "g": 1.400},    # 坡:入「逼你升級」
	## 1.105 → 1.140 → 1.115 → **1.125**。1.140 之下 A1 喺第 37-40 關實測 0%,
	## 即係「逼你進化」嗰堵牆企咗喺 37 而唔係設計講嘅 41(Gate 3a 要第 40 關
	## 都仲有 ≥30%);平返落 1.115 之後 A1 11-40 坐喺 95%,而 Gate 3a 由 60%
	## 減到 30% 嘅**意思**就係容許呢一段真係難 —— 唔用返嗰個空間等於呢條 gate
	## 冇改過。1.125 係「用得着但唔踩爆逐關下限」嘅折衷。
	## 呢一段每加一分,41-46 個坡就除返一分,所以難度(46) 由頭到尾冇郁過。
	{"to": 40, "g": 1.125},    # 逼你升級
	{"to": 46, "g": 1.386},    # 坡:入「逼你進化一次」
	{"to": 56, "g": 1.125},    # 逼你進化一次
	## 1.450 → **1.360**(唯一一段**減**咗嘅)。難度補償只補咗**金幣**(場內
	## 塔數),冇補**魔晶**(元進度)—— 而魔晶收入係跟住勝率行嘅,所以成條
	## 曲線 ×13 之後,A3 喺 57-70 嗰個雙坡度輸到冇錢課:實測佢去到第 100 關
	## 個主力魔法仲停喺 tier 2(即係「逼你雙階段 3」呢個段目標喺模擬入面
	## 從來冇達成過),71-99 勝率 8% 反而**低過** A2 嘅 25%,兩個原型倒掛。
	## 對策唔係再加難度,係換形狀:呢個坡拍平,令 A3 有錢行完進化。
	{"to": 62, "g": 1.360},    # 坡(急):入「逼你雙階段 3」
	## 1.240 → 1.200 → 1.245 → 1.290 → **1.365**。呢個坡就係 71-99 段嘅
	## **入口**,而 Gate 5a 由 ≤18% 減半到 ≤9% 嘅意思就係 A2 一入 71 段就要死。
	## 逐步實測(A2 71-99 / A3 71-99):
	##   1.200 → A2 喺 71-72 仲係 100%
	##   1.245 → A2 21.3%
	##   1.290 → A2 22.6% / A3 62.1%  ← A2 啲勝場全部堆喺 71-84
	##   1.365 → 呢個數(相對 1.240 係 ×1.60)
	## 每次都係 A3 有大截餘裕(gate 只要 ≥28%)先至再加 —— 呢個坡係唯一
	## 一個「淨係打 A2 唔打 A3」嘅位,因為 TIER_JUMP 1.70→1.95 令 A3 嘅
	## tier-3 火力同步 ×1.32,而 A2 只 ×1.15。
	{"to": 70, "g": 1.365},    # 坡(收):接返落平段,唔好一步踩落去
	## 1.054 → 1.0605 → 1.075 → 1.0637 → **1.0466**。入口每抬高一分,段內
	## 斜率就除返同一分 —— 難度(99) 由頭到尾冇郁過(所以 FINAL_SCALE 亦都
	## 唔使跟住改),郁嘅淨係「段入口 vs 段尾」嘅分佈。
	{"to": 99, "g": 1.0466},   # 逼你雙階段 3
]
## 第 100 關嘅**難度指數**倍率(相對第 99 關)。
##
## 佢細過 1,而嗰個唔係手民之誤:第 100 關嘅難度唔係嚟自指數,係嚟自**編排**
## —— 十隻 boss 同場,而一關普通關得一隻。後期嘅輸出幾乎全部都係倒落 boss
## 血條度,所以「十隻」本身就抵得住大約六倍指數。實測:A4 喺第 99 關(指數
## 107,000)贏得輕鬆,但喺第 100 關指數 28,000 之下只贏得一成三 —— 即係話
## 呢一關嘅**有效**難度仍然係全遊戲最高,大約係第 99 關嘅 1.7 倍。
##
## 副作用係第 100 關嘅雜兵比第 99 關軟。呢個係有意留低嘅:嗰一場要玩家睇得
## 清楚十條血條,而唔係俾雜兵蓋住。
## 0.26 -> 0.23(第十七輪):第 100 關嘅**絕對**難度要比第十五輪高返一截
## —— boss 歸一化令十 boss 車輪戰入面最毒嗰幾隻(群療/俯衝/相位)軟咗,
## 而固定塔價又令 A4 喺呢關起到 24 座塔,兩件事夾埋 A4 勝率由 10% 衝上
## 45%(Gate 6b 上限 30%)。0.19(絕對難度同十五輪持平)實測 45%;0.164
## 加埋 63-70/71-99 兩段斜率嘅提升,絕對難度 ≈ 十五輪 x1.9(63-70 段每次
## 加斜率,呢度就要除返,唔係 Gate 6 個窄窗口會陪其他段亂郁 —— 0.20 之下
## A4 final 實測 15%,呢個 0.164 就係 0.20 ÷ 1.24^8/1.21^8,保持嗰個數)。
## 實測 lv100 嘅單場結果對初始條件極敏感(同一絕對難度,20 seed 之間可以
## 由 15% 跳到 40%)—— 呢個 gate 要用 48 seed 先讀得準。0.175 係將 48-seed
## 均值擺喺 10-30 窗口中間嘅擬合值。
## 0.21 -> 0.055(第十八輪)。難度指數整條 ×13 之後,第 100 關嘅絕對難度
## (= 指數 × FINAL_SCALE)如果照舊就係 668,853 —— A4 實測 **0/16**。A4 係
## 一個**授予**嘅 build,佢唔食金幣 v3 帶嚟嘅塔數增長全部(佢喺呢關起 ~45 座,
## 十七輪係 24 座),所以佢嘅力量只升咗 ~2.5 倍,唔係 13 倍。呢個掣就係
## 「除返嗰個差」:0.055 之下第 100 關嘅絕對難度 ≈ 十七輪 ×2.5。
## 副作用(第 100 關雜兵比第 99 關軟)照舊,而且更明顯 —— 見上面嘅設計理由。
## (0.055 -> 0.073:TIER_JUMP 1.70 -> 1.95 令 A4 嘅滿級 tier-3 陣容強咗
## 三成二,呢度乘返同一個數,第 100 關嘅**相對**難度先至冇被順手改掉。
## 之後 63-70 個坡再 ×1.40 令難度(99) 一齊升,而第 100 關嘅絕對難度唔應該
## 順手跟住升 —— 0.073 ÷ 1.40 = 0.052。)
const FINAL_SCALE := 0.052

var _diff_cache: Array = []

func _build_wave_cache() -> void:
	_diff_cache = [0.0, 1.0]          # index = 關數;第 1 關 = 1.0
	var cur := 1.0
	var n := 2
	for band in WAVE_BANDS:
		while n <= int(band["to"]):
			cur *= float(band["g"])
			_diff_cache.append(cur)
			n += 1
	_diff_cache.append(cur * FINAL_SCALE)   # 第 100 關

## 第 n 關有幾難 —— **呢條先係難度嘅權威定義**,唔係 wave_scale。
##
## 點解要分開兩個概念(第十五輪改嘅):一關嘅實際壓力唔淨止係「一隻怪幾多血」,
## 仲有「一隻怪係幾多級」同「一秒出幾多隻」。舊版三樣嘢各自跟自己嘅曲線行,
## 而怪物等級帶係一個**階梯**(第 13/25/37/49 關各跳一級),所以實際難度喺
## 嗰四關各自跳咗三成幾 —— 一個冇人設計過、亦都冇人量過嘅斷層,而且佢係
## Gate 7(難度單調)嘅天然敵人。
##
## 而家反過嚟:difficulty() 係設計品,而雜兵血量係**由佢除返出嚟**嘅結果。
## 怪物等級同密度想點行都得(佢哋而家係純粹嘅變化同視覺),總壓力照樣係
## 設計嗰條平滑曲線。
func difficulty(n: int) -> float:
	if n <= 1:
		return 1.0
	if n < _diff_cache.size():
		return float(_diff_cache[n])
	var last: float = float(_diff_cache[FINAL_LEVEL - 1])
	return last * pow(float(WAVE_BANDS[WAVE_BANDS.size() - 1]["g"]), n - (FINAL_LEVEL - 1))

## 該關怪物等級帶嘅平均血量倍率,以第 1 關做 1。
func _lvl_hp_norm(n: int) -> float:
	var band: int = int(maxi(1, n) - 1) / LVL_BAND_EVERY
	var lo: int = clampi(1 + band, 1, 5)
	var hi: int = clampi(2 + band, 1, 5)
	var s := 0.0
	for l in range(lo, hi + 1):
		s += LVL_HP[l]
	return (s / float(hi - lo + 1)) / ((LVL_HP[1] + LVL_HP[2]) * 0.5)

## 密度倍率(出怪頻率相對第 1 關)。
func density(n: int) -> float:
	return 1.0 + DENSITY_GAIN * clampf(float(n - 1) / float(FINAL_LEVEL - 1), 0.0, 1.0)

const LVL_BAND_EVERY := 12
const DENSITY_GAIN := 0.30

## 路線長度歸一化(第十七輪)。六條 path 模板係 3/4/5 條橫掃,總長差成
## ±17% —— 路越長,怪喺塔火力下面行得越耐,同一份血量嘅**實際壓力**就
## 越細。呢個係同「等級帶樓梯」一模一樣嘅隱藏難度修正器:第十五輪已經
## 定咗「difficulty() 先係權威,等級/密度係自由變數」,path 長度冇理由
## 例外。唔歸一嘅後果喺 71-99 段最誇張:嗰段每關先 +4.6%,±17% 嘅路長
## 擺動等於 ±4 關 —— 實測 A2 喺自己前沿之後仲可以專贏長路關(75/78/81/84
## 全勝、隔籬短路關全敗),Gate 5a 同 Gate 7 嘅超標一大截係呢度嚟。
## 長路 -> 怪物血量按比例加硬,六款路嘅實際壓力先至一樣。
var _path_factor_cache: Array = []

func path_factor(n: int) -> float:
	if _path_factor_cache.is_empty():
		var tot: Array = []
		var s := 0.0
		for i in 6:
			var l: float = PathRoute.template(i).total
			tot.append(l)
			s += l
		for i in 6:
			_path_factor_cache.append(float(tot[i]) * 6.0 / s)
	return float(_path_factor_cache[(n - 1) % 6])

## 家族組合歸一化(第十七輪)。第三個隱藏難度修正器,同「等級帶樓梯」「path
## 長度」同類:每關嘅家族組合由 (n-1)%10 輪轉,而一個 spawn slot 嘅實際壓力
## ≈ 血 x 速度(「要幾多 DPS 先殺得切」:血係要打掉嘅量,速度係剩返幾多時間)
## —— 哥布林 slot 2,184、樹妖 4,180、史萊姆連分裂包 ~5,280,擺動成 1.8 倍。
## 樹妖+史萊姆做組合嗰啲關(17/27/...)實測係**每一個原型**都齊齊跌一截嘅
## 異常關(連 A3 都由 100% 跌落 60%),亦即係 Gate 3a 同 Gate 7 嘅唯一破口。
## 歸一之後家族組合變返「風味」:硬嘅家族出少啲血,快嘅家族一樣計埋速度。
##
## 分裂包 = 史萊姆一代分裂(子體 lvl-1、唔再分裂)嘅有效血量倍率,約 2.0
## (lv2 係 2.25、lv5 係 2.24,lv1 唔分裂 —— 用常數係一個接受咗嘅近似)。
const SLIME_SPLIT_PACK := 2.0
## 第十八輪:壓力公式加返**護甲同魔抗**。第十七輪嘅 hp x speed 漏咗佢哋,而
## 兩者喺 Monster.take_hit 都係一個乾淨嘅百分比減傷(phys: 1 - a/(a+50);
## magic: 1 - m/(m+60))—— 即係話佢哋係一個**純粹嘅有效血量倍率**,同 hp
## 一模一樣咁乘埋落去,冇任何理由唔入數。
##
## 症狀:第十八輪嘅 A1 喺 11-40 平均 87%,但第 18(甲蟲+哥布林+岩石巨像,
## 三族齊齊有甲)、第 24(岩石巨像 12 甲 + 樹妖回復)兩關實測 0% —— Gate 3a
## 要求逐關 ≥30%。呢個唔係「難度曲線太斜」,係一個冇入曲線嘅家族修正器。
##
## 玩家傷害嘅物理/魔法比例用 0.7 / 0.3(主力塔 = 箭塔物理,主力魔法 = 隕石)。
## 呢個係一個近似 —— 一個全魔法 build 睇到嘅有效血量會唔同,但曲線係為
## 「一個合理玩家」設計嘅,而合理玩家嘅輸出七成喺塔度。
const PHYS_SHARE := 0.7
const ARMOR_K := 50.0
const MRES_K := 60.0
var _fam_press_mean := 0.0

## 護甲/魔抗換算成有效血量倍率。
func _resist_mult(armor: float, mres: float) -> float:
	return PHYS_SHARE * (armor + ARMOR_K) / ARMOR_K \
		+ (1.0 - PHYS_SHARE) * (mres + MRES_K) / MRES_K

## 雜兵機制嘅有效血量係數(第十八輪)。同 BOSS_MECH_TOUGH 完全同一個道理,
## 只不過嗰個係 boss 嗰邊,呢個一直冇人做過 —— 而十關輪轉入面家族係**成組**
## 出現嘅,所以佢哋唔會互相抵銷,係堆埋一齊。
##   revive    骷髏:AURA_REVIVE_MAX 之下有效血量 1 + 0.30 + 0.15(碼度寫住)
##   regen     樹妖:回復咬走一截 DPS
##   aura      巫教:佢哋 buff 成波怪,即係一隻嘅存在令其他隻更硬
##   hardshell 甲蟲:每下傷害封頂 12% 血 —— 對大單體傷害係一堵牆
##   phase     幽靈:相位期間食唔到嘢
##   flying    蝙蝠:地面效果(火場/荊棘/緩速力場)全部落唔到佢身上
## split 唔喺呢度 —— 佢有自己嗰個 SLIME_SPLIT_PACK(數量,唔係硬度)。
const FAM_MECH_TOUGH := {
	"basic": 1.0, "revive": 1.45, "armored": 1.0, "phase": 1.10,
	"flying": 1.05, "regen": 1.15, "hardshell": 1.10, "aura": 2.00,
	"split": 1.0,
}
## aura 由 1.25 加到 2.00(第十八輪,第二步):巫教嘅光環唔係一個「自己硬啲」
## 嘅效果 —— 佢每 0.6 秒幫**周圍每一隻**回自己血量嘅 3%(= 5%/秒),而大祭司
## 嘅 boss 期 pool 係**全巫教**,即係一舊互相回血嘅怪。N 隻埋堆嘅有效血量係
## 超線性,一個 1.25 嘅係數量緊「一隻巫教」,唔係量緊嗰舊嘢。實測第 39 關
## (巫教 + 妖狼,大祭司 boss)係 Gate 3a 最後一個唔達標嘅關,A1 勝率 0%,
## 而同段平均 92%。

func _fam_pressure(fam: String) -> float:
	var f: Dictionary = FAMILIES[fam]
	var p: float = float(f.hp) * float(f.speed) \
		* _resist_mult(float(f.armor), float(f.mres)) \
		* float(FAM_MECH_TOUGH.get(String(f.mech), 1.0))
	if String(f.mech) == "split":
		p *= SLIME_SPLIT_PACK
	return p

## 家族組合歸一化(第十七輪版本,只計雜兵期)。第十八輪之後**唔再直接用**
## —— 佢已經被 `level_wave_norm()` 包住(雜兵期 + boss 期)。留住做診斷同對照。
func fam_mix_norm(n: int) -> float:
	## 第 100 關嘅家族係另外指定(全部十族),平均壓力自動係 1 —— 直接返。
	if is_final_level(n):
		return 1.0
	if _fam_press_mean <= 0.0:
		var s := 0.0
		for k in FAMILY_ORDER:
			s += _fam_pressure(String(k))
		_fam_press_mean = s / float(FAMILY_ORDER.size())
	var fams: Array = level_families(n)
	var s2 := 0.0
	for k in fams:
		s2 += _fam_pressure(String(k))
	return (s2 / float(fams.size())) / _fam_press_mean

# ---------------------------------------------------------------------------
# 關卡壓力歸一化 level_wave_norm()(第十八輪)。第八個隱藏修正器。
#
# 第十七輪嘅 fam_mix_norm 只計**雜兵期**嘅家族組合。但 boss 一出場,雜兵嘅
# 出怪頻率同怪種**兩樣都會變**(`BOSS_SPAWN`:rate 0.10↔0.70 差七倍、`pool`
# 換晒怪種、`lvl_bonus` 加一級、`burst` 突襲隊),而 boss 期佔一關三分一時間。
# 換句話講:一關嘅總壓力有三分一冇入過任何一條歸一化。
#
# 症狀:Gate 3a(A1 11-40 逐關 ≥30%)喺 1.125 之下淨係三關唔達標 —— 第 18
# (甲蟲皇,rate 0.70 + pool 全甲蟲)、第 24(岩石巨像,rate 0.65 + lvl_bonus)、
# 第 39(大祭司,pool 全巫教 —— 而巫教係 aura,佢哋互相 buff)。而同段其餘
# 二十七關全部 90-100%。三隻都係「boss 期出怪最毒」嗰批。
#
# 做法同 level_gold_norm 完全對稱,只不過權重用 _fam_pressure 而唔係掉金:
#   Y(n) = 雜兵期出怪數 × 該關家族平均壓力
#        + boss 期出怪數 × boss 期怪種平均壓力(連 lvl_bonus 嘅血量帶)
#        + 突襲隊數 × 突襲怪種壓力
# 再除返同一個等級帶入面二十關(家族輪轉 10 × 單雙數 2)嘅平均 Y。
# 平均難度一個字都冇郁 —— 郁嘅只係「邊幾關特別毒」嗰個擺動。
# ---------------------------------------------------------------------------
## boss 期嘅壓力**唔全額**入歸一化(掉金嗰邊就照全額)。
##
## 點解兩邊唔同:掉金量嘅係一個固定 90 秒窗,boss 期實實在在有 30 秒;但
## 壓力唔係 —— boss 期幾長由**玩家幾快殺得死 boss** 決定,而一關係喺 boss
## 死嗰刻完結嘅。一個爆發型 build(A2 = tier 2 課滿)喺慢 boss 關 1-6 秒
## 就秒殺咗隻 boss,所以嗰段圍城根本冇發生過 —— 全額補償等於幫佢哋將
## 「圍城很兇」呢件事換成「雜兵軟啲」,而佢哋食唔到圍城只食到雜兵。
##
## 實測:全額(1.0)之下 A2 喺 71-84 坐喺 35%(Gate 5a 上限 9%),而佢
## 全部勝場都係 goblin / golem / beetle 三隻慢 boss 嘅關(71/74/78/81/84)
## —— 同第十七輪記錄嘅一模一樣嗰個 pattern。0.5 係「圍城平均只發生一半」
## 嘅折衷:弱 build 照食全套(佢哋殺唔快),爆發 build 唔再攞到折扣。
const BOSS_PHASE_WEIGHT := 0.5
var _lwn_cache: Dictionary = {}

## 等級帶 band 之下,怪物等級 +bonus 之後嘅平均血量倍率變化。
func _lvl_bonus_hp(band: int, bonus: int) -> float:
	var lo: int = clampi(1 + band, 1, 5)
	var hi: int = clampi(2 + band, 1, 5)
	var a := 0.0
	var c := 0.0
	for l in range(lo, hi + 1):
		a += LVL_HP[clampi(l + bonus, 1, 5)]
		c += LVL_HP[l]
	return a / maxf(0.001, c)

func _wave_yield(band: int, r: int) -> float:
	var base_i: int = r % 10
	var fams: Array = [FAMILY_ORDER[base_i], FAMILY_ORDER[(base_i + 3) % 10]]
	if r % 2 == 1:                     # r = (n-1)%20,所以 r 單數 = n 雙數
		fams.append(FAMILY_ORDER[(base_i + 6) % 10])
	var a := 0.0
	for f in fams:
		a += _fam_pressure(String(f))
	a /= float(fams.size())
	var y: float = WAVE_PHASE_SPAWNS * a
	var boss_fam: String = FAMILY_ORDER[base_i]
	var p: Dictionary = boss_spawn_profile(boss_fam)
	var pool: Array = p.get("pool", fams)
	var ab := 0.0
	for f in pool:
		ab += _fam_pressure(String(f))
	ab = ab / float(pool.size()) * _lvl_bonus_hp(band, int(p.get("lvl_bonus", 0)))
	y += BOSS_PHASE_WEIGHT * BOSS_PHASE_SECONDS \
		* float(p.get("rate", BOSS_SPAWN_BASE_RATE)) / 0.45 * ab
	var bu: Dictionary = p.get("burst", {})
	if not bu.is_empty():
		y += BOSS_PHASE_WEIGHT * BOSS_PHASE_SECONDS / maxf(1.0, float(bu["interval"])) \
			* (float(bu["count_min"]) + float(bu["count_max"])) * 0.5 \
			* _fam_pressure(String(bu.get("fam", boss_fam)))
	return y

func level_wave_norm(n: int) -> float:
	if is_final_level(n):
		return 1.0
	var band: int = _band_of(n)
	if not _lwn_cache.has(band):
		var tbl: Array = []
		var s := 0.0
		for r in GOLD_ROT:
			var y: float = _wave_yield(band, r)
			tbl.append(y)
			s += y
		var mean: float = maxf(0.001, s / float(GOLD_ROT))
		var out: Array = []
		for r in GOLD_ROT:
			out.append(float(tbl[r]) / mean)
		_lwn_cache[band] = out
	return float((_lwn_cache[band] as Array)[(maxi(1, n) - 1) % GOLD_ROT])

## 第 n 關出邊幾多個家族(2-3 個輪轉)。level_config 同 fam_mix_norm 都問呢度
## —— 兩邊各自寫一次嘅話,選族公式一改,歸一化就靜靜咁對唔上。
func level_families(n: int) -> Array:
	var base_i := (n - 1) % 10
	var fams := [FAMILY_ORDER[base_i], FAMILY_ORDER[(base_i + 3) % 10]]
	if n % 2 == 0:
		fams.append(FAMILY_ORDER[(base_i + 6) % 10])
	return fams

## 雜兵嘅血量倍率 = 難度 x 路長因子 ÷(等級帶 x 密度 x 關卡壓力)。
func wave_scale(n: int) -> float:
	return difficulty(n) * path_factor(n) \
		/ (_lvl_hp_norm(n) * density(n) * level_wave_norm(n))

## boss 冇「怪物等級帶」呢回事(佢永遠係 boss),而且佢係一隻,唔受密度影響
## —— 所以佢直接跟難度指數,唔跟雜兵嗰條。冇呢個分別嘅話,怪物等級一跳
## boss 就會靜靜咁變弱三成。boss 行同一條路,所以路長因子一樣食。
func boss_scale(n: int) -> float:
	return difficulty(n) * path_factor(n)

func is_final_level(n: int) -> bool:
	return n == FINAL_LEVEL
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
const RENDER_SCALE := 2.0     # monster LOGICAL size scale -> lv1 64px, boss 192px
## 怪物 sprite 嘅世界縮放。
##
## 2026-08-06 怪物美術輪之前,怪物圖係 32-44px 嘅程序像素圖,啱啱好可以用
## RENDER_SCALE(2.0)整數放大。而家 60 張圖係由 sprite sheet 摳出嚟嘅手繪圖
## (tools/monster_cutout.py),源檔本身已經係接近顯示尺寸:
##   lv1-5  PNG = 顯示尺寸 × 1.25  ->  縮放 1 / 1.25 = 0.8
##   boss   PNG = 顯示尺寸 × 0.75  ->  縮放 1 / 0.75 = 4/3
## 兩個數同源圖尺寸係一對一綁死嘅 —— 改一邊冇改另一邊,全場怪物即刻大細錯。
## **顯示尺寸本身冇變**(lv1 仍然 64px、boss 仍然 192px 高度級數),`size`
## (血條 / 特效半徑 / 傷害數字位置)仍然行 RENDER_SCALE,一步都冇郁。
const MON_ART_SCALE := 0.8
const MON_ART_SCALE_BOSS := 4.0 / 3.0
## 第二十輪:2.0 -> 0.6875(= 88/128)。畫面上嘅塔仍然係 88px 闊,一步都冇郁
## —— 郁咗嘅係**源圖解像度**:塔 sprite 由程序生成嘅 44px 換成由 sprite sheet
## 摳出嚟嘅 128px 高手繪圖(見 tools/tower_cutout.py)。舊圖喺 camera zoom 2.0
## 之下係 4 倍放大,而家係 1.4 倍縮細。
##
## 呢個數同 tower_cutout.py 嘅 `CANVAS`(128)/ `GROUND_Y`(125)綁死,改一個
## 冇改另外兩個 = 全場塔即刻大細錯 / 浮起或者陷落地面。接地線 125/128 就係舊
## 圖嘅 43/44,所以射程圈、選中光圈、ghost 預覽、詛咒符文、聖光光柱全部原位。
const TOWER_RENDER := 0.6875  # tower sprite world scale (128px source -> 88px)
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
## 第十七輪:goblin/golem/beetle 三個**慢 boss** 族嘅 rate 由 0.15/0.25/0.30
## 拉上 0.55/0.65/0.70。理由:慢 boss 行唔到基地,「拖幾耐都得」令佢哋嘅關
## 喺前沿變成零風險磨血位 —— A2 喺 71-99 剩低嘅贏**全部**係呢三族 boss 嘅
## 關(78/81/84 全勝,難度差成倍都照贏),boss 血加幾多都冇用(時間無限)。
## 慢 boss 嘅威脅唔係佢本人,係攻城:圍城部隊要迫玩家喺「殺 boss」同
## 「守線」之間分火力,拖得越耐漏怪風險越高。快 boss 族照舊 —— 佢哋本人
## 已經係倒數計時器。
var BOSS_SPAWN := {
	"goblin":  {"rate":0.55},                                     # 哥布林王:召喚大軍圍城
	"wolf":    {"rate":0.0,                                       # 狼王:平時無,狼群突襲
	            "burst":{"first":5.0, "interval":12.0, "count_min":3, "count_max":5, "fam":"wolf"}},
	"skeleton":{"rate":0.4},                                      # 骷髏君主:標準+復活光環
	"golem":   {"rate":0.65, "lvl_bonus":1},                      # 岩石巨像:精兵圍城
	"ghost":   {"rate":0.4, "pool":["ghost"]},                    # 幽靈女王:全幽靈族
	"bat":     {"rate":0.4, "pool":["bat"]},                      # 蝠魔霸主:只出飛行
	"treant":  {"rate":0.3, "minion_regen":0.01},                 # 遠古樹妖:小怪輕微再生
	"beetle":  {"rate":0.7, "pool":["beetle"]},                   # 甲蟲皇:硬殼甲蟲圍城
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

# ---------------------------------------------------------------------------
# 場內金幣 vs 建塔成本 (第十八輪:金幣 v3)
#
# 第十五輪嘅答案係「兩條曲線同一個指數」:建塔價同金收入一齊跟
# difficulty^0.45 行。比率唔發散,但有兩個代價:(1) 建塔嘅「鬆緊」變成一個
# 100 關都唔變嘅常數,冇任何演進;(2) 同一座塔嘅標價隨關卡同場上塔數郁,
# 玩家睇唔明點解箭塔一時 60 一時 74。
#
# 第十七輪反轉槓桿:**建塔價完全固定**(def.place_cost),鬆緊全部交俾金幣
# 掉落曲線。呢個結構保留,但第十八輪換咗曲線本身同佢嘅**單位**:
#
#   舊(十七輪):曲線係一條「唔准發散」嘅安全繩 —— 1.0 爬到 1.40,而
#   KILL_GOLD_TUNE = 0.5 將絕對值壓到一關夠鋪 ~7 座塔。玩落嘅結果係 Jack
#   實試嘅嗰句「隨便起幾座塔就過到前 50 關」:塔少,所以每座塔嘅擺位同
#   升級都唔使諗,一條 build 由頭行到尾。
#
#   新(十八輪):曲線係一條**設計目標曲線**,單位係「呢一關淨靠打怪掉幣
#   起得到幾多座參考塔」(= G1)。G1 由第 1 關嘅 10 座爬到第 100 關嘅 40 座,
#   而爬嘅形狀跟返難度嘅分段:1-10 體驗、11-16 入門坡、17-40、41-70、71-100。
#   塔多咗三四倍,所以怪物曲線亦都同步重校(見 WAVE_BANDS)—— 兩件事係
#   同一個決定嘅兩面,唔可以淨做一邊。
#
# 「參考塔價」= 120 金,20 座塔基礎價嘅中位數(亦等於平均價 119 取整)。
# 用中位數而唔係箭塔嘅 60:G1 係一條經濟曲線,唔應該跟住某一座塔嘅平衡改動
# 一齊郁。tools/goldcurve.gd 就係量呢條曲線嘅工具(90 秒當量、雜兵即殺、
# boss 釘死,所以佢量嘅係**關卡派幾多錢**,同玩家打得好唔好無關)。
#
# 場內每一個金來源都要行同一條曲線,唔係鍊金塔同點金術會隨關數變成零。
# Battle.scale_gold() 係嗰個單一入口(怪物掉落已經喺 kill_gold_unit 度乘咗,
# 所以佢唔使再經)。因為所有來源同一條曲線,G2(經濟技能上限)嘅比率
# **結構上同關卡無關** —— 量一關等於量一百關。
# ---------------------------------------------------------------------------
## G1 目標曲線嘅分母。改呢個數等於重定義成條曲線,唔好順手郁。
const REF_TOWER_COST := 120.0
## 金幣倍率嘅分段成長率,結構同 WAVE_BANDS 一模一樣(`to` = 呢段最後嗰關,
## `g` = 段內每關嘅成長率)。每一段嘅終點就係 G1 嘅設計目標:
##
##   關     倍率    G1(可建塔數)   對應難度段
##   1      1.000   10             體驗關
##   10     1.450   14.5           體驗關尾
##   16     2.050   20.5           入門坡尾(≥20 喺呢度達成)
##   40     2.700   27             逼你升級
##   70     2.957   33(連精英)    逼你進化一次
##   100    3.390   40(連精英)    逼你雙階段 3 / 最終關
##
## 點解入門坡(11-16)係全條曲線最斜嗰段:難度喺嗰六關本身就係一個坡
## (WAVE_BANDS g=1.230),而「逼你升級」呢個設計目標要求玩家企喺邊緣 ——
## 邊緣嘅意思係塔夠多但唔夠強,所以塔數要喺呢六關一次過鋪夠,之後嘅
## 八十四關先慢慢加。反過嚟講:1-10 關 G1 由 10 爬到 15,係要體驗關真係
## 有「起唔起呢座」嘅決定,而唔係開場就鋪滿。
## 註:41 關之後嘅兩段**特登比前面平**,唔係手民之誤 —— 精英怪由第 41 關起
## 出場,而佢哋掉 ELITE_GOLD_MULT(1.9)倍金。精英率由 6% 爬到 20%,即係
## 一條「唔喺呢張表入面」嘅 +5% → +18% 收入曲線。呢兩段除返佢,實際 G1
## 先至係設計嗰條線(實測驗證:第 60 關量到 31.4 座,表面倍率只計到 30.9)。
const GOLD_BANDS := [
	{"to": 10,  "g": 1.04222},
	{"to": 16,  "g": 1.05930},
	{"to": 40,  "g": 1.01155},
	{"to": 70,  "g": 1.00304},
	{"to": 100, "g": 1.00456},
]
var _gold_cache: Array = []

func _build_gold_cache() -> void:
	_gold_cache = [0.0, 1.0]
	var cur := 1.0
	var n := 2
	for band in GOLD_BANDS:
		while n <= int(band["to"]):
			cur *= float(band["g"])
			_gold_cache.append(cur)
			n += 1

## 一關嘅「金單位」。所有金額(起手金、鍊金塔產出、怪物掉落)都以佢做單位。
## 建塔價**唔喺入面** —— 佢係固定價,而呢條曲線同固定價嘅比就係 G1。
func gold_scale(n: int) -> float:
	if _gold_cache.is_empty():
		_build_gold_cache()
	if n <= 1:
		return 1.0
	if n < _gold_cache.size():
		return float(_gold_cache[n])
	return float(_gold_cache[_gold_cache.size() - 1])

## 殺敵掉金嘅全域係數。佢淨係做一件事:將 G1 嘅**絕對值**釘喺第 1 關 = 10 座。
## 形狀由 GOLD_BANDS 話事,呢度只係搬高條線。
##
## 0.5 -> 1.83(第十八輪):十七輪嗰個 0.5 係為咗抵銷「拆走遞增塔價」帶嚟
## 嘅塔數上升,而嗰個抵銷本身就係「隨便起幾座就完到前 50 關」嘅來源。
## 而家反方向:塔數要係設計目標,難度跟塔數走。
##
## 起手金**唔食**呢個係數(佢行 gold_scale),所以開局買到幾多座係另一條掣。
## (1.83 -> 1.92 係最後一步微調:1.83 之下實測第 1 關 9.78 座、第 99 關 36.8 座,
## 兩頭都爭少少;+5% 之後係 10.3 / 38.6,兩頭都入返 G1 嘅窗。)
const KILL_GOLD_TUNE := 1.92

## 怪物掉落要除返「等級帶 x 密度」,理由同 wave_scale 一模一樣。
##
## 唔除嘅話:一隻第 60 關嘅 5 級怪掉 LVL_GOLD[5] = 3.6 倍金,而且一秒出多
## 三成隻,即係全場金收入係第 1 關嘅 4.7 倍,但建塔價得 1 倍單位 —— 而嗰個
## 就係實測到「31-50 關比率 44、51-70 關比率 95」嘅來源。呢個唔係「金太多」,
## 係兩條曲線根本冇對齊。
func _lvl_gold_norm(n: int) -> float:
	var band: int = int(maxi(1, n) - 1) / LVL_BAND_EVERY
	var lo: int = clampi(1 + band, 1, 5)
	var hi: int = clampi(2 + band, 1, 5)
	var s := 0.0
	for l in range(lo, hi + 1):
		s += LVL_GOLD[l]
	return (s / float(hi - lo + 1)) / ((LVL_GOLD[1] + LVL_GOLD[2]) * 0.5)

## 史萊姆掉金包 = 一隻史萊姆連兩隻子體嘅掉金倍率。**跟怪物等級帶行**,唔係
## 一個常數:lv1 史萊姆唔分裂(包 = 1.0),而頭十二關嘅等級帶係 1-2,即係
## 一半史萊姆冇子體。用常數 2.45 嘅話,頭十二關嘅史萊姆關會被高估四成幾,
## 而 G1 曲線就會喺嗰幾關凹一忽 —— 實測第 10 關量到 8.7 座(第 1 關 10.4)。
## (血量嗰邊嘅 SLIME_SPLIT_PACK 照舊用常數 2.0:佢餵嘅係難度曲線,而難度
## 曲線本來就有 ±5% 嘅容差;G1 係一條要逐關對得上嘅設計曲線,冇同一份容差。)
func _slime_gold_pack(n: int) -> float:
	var band: int = _band_of(n)
	var lo: int = clampi(1 + band, 1, 5)
	var hi: int = clampi(2 + band, 1, 5)
	var s := 0.0
	for l in range(lo, hi + 1):
		s += 1.0 if l <= 1 else (1.0 + float(SPLIT_COUNT) * SPLIT_GOLD_FRAC
			* LVL_GOLD[l - 1] / LVL_GOLD[l])
	return s / float(hi - lo + 1)

## 史萊姆一代分裂幾多隻 / 子體掉金折扣 —— Monster.SPLIT_COUNT 同
## Battle.SPLIT_GOLD_FRAC 嘅數據層鏡像。歸一化要知道實際派幾多,而唔係
## 圖鑑講幾多:漏咗 0.25 折嗰陣,史萊姆關被高估四成,量出嚟就係第 20 關
## 明明應該多過第 16 關但實測少 13%。
const SPLIT_COUNT := 2
const SPLIT_GOLD_FRAC := 0.25

func _fam_gold(fam: String, band: int) -> float:
	var f: Dictionary = FAMILIES[fam]
	var g: float = float(f.gold)
	if String(f.mech) == "split":
		g *= _slime_gold_pack(band * LVL_BAND_EVERY + 1)
	return g

# ---------------------------------------------------------------------------
# 關卡掉金歸一化 level_gold_norm()(第十八輪)。第五、第六個隱藏修正器,
# 兩個都**只影響收入**,合併成一條:
#
#   5. 家族組合。十族嘅基礎掉金由 4 到 7,而史萊姆仲要連分裂體一齊計 ——
#      「呢一關派幾多錢」本來係跟家族輪轉擺 ±20%(實測第 10 關 233 金、
#      第 15 關 330 金,相鄰十關差四成)。
#   6. boss 期嘅出怪。boss 一出場,雜兵頻率就改跟 BOSS_SPAWN[boss 族].rate,
#      而十族之間由 0.10(史萊姆之母)去到 0.70(甲蟲皇)—— 差七倍;有啲
#      boss 仲要換晒怪種(`pool`)或者加一級(`lvl_bonus`)。90 秒當量入面
#      boss 期佔三分一。boss **血量**嘅家族差異第十七輪已經歸一
#      (boss_hp_coeff),收入嗰邊當時冇人量過。
#
# 做法:計一關嘅「掉金產量權重」Y(n) = 雜兵期出怪數 x 該關家族平均掉金
#      + boss 期出怪數 x boss 期怪種平均掉金 + 突襲隊數 x 突襲怪種掉金,
# 再除返**同一個等級帶入面二十關(= 家族輪轉 10 x 單雙數 2 嘅最小公倍數)
# 嘅平均 Y**。即係話輪轉照轉、風味照有,但一關派幾多錢只由 GOLD_BANDS 話事。
# ---------------------------------------------------------------------------
const BOSS_PHASE_SECONDS := 30.0
## 雜兵期(60 秒,間隔由 1.6 lerp 落 0.45)出到嘅怪數,以 density 做單位:
## ∫dt/interval = (60/1.15)·ln(1.6/0.45) = 66.2。density 兩期都食,所以喺
## 呢個比率入面消掉,唔使出現。
const WAVE_PHASE_SPAWNS := 66.2
const GOLD_ROT := 20
var _lgn_cache: Dictionary = {}

func _band_of(n: int) -> int:
	return int(maxi(1, n) - 1) / LVL_BAND_EVERY

## 等級帶 band 之下,怪物等級 +bonus 之後嘅平均掉金倍率變化。
func _lvl_bonus_gold(band: int, bonus: int) -> float:
	var lo: int = clampi(1 + band, 1, 5)
	var hi: int = clampi(2 + band, 1, 5)
	var a := 0.0
	var c := 0.0
	for l in range(lo, hi + 1):
		a += LVL_GOLD[clampi(l + bonus, 1, 5)]
		c += LVL_GOLD[l]
	return a / maxf(0.001, c)

## 第 r 個輪轉位(r = (n-1) % 20)喺等級帶 band 之下嘅掉金產量權重。
func _gold_yield(band: int, r: int) -> float:
	var base_i: int = r % 10
	var fams: Array = [FAMILY_ORDER[base_i], FAMILY_ORDER[(base_i + 3) % 10]]
	if r % 2 == 1:                     # r = (n-1)%20,所以 r 單數 = n 雙數
		fams.append(FAMILY_ORDER[(base_i + 6) % 10])
	var a := 0.0
	for f in fams:
		a += _fam_gold(String(f), band)
	a /= float(fams.size())
	var y: float = WAVE_PHASE_SPAWNS * a
	var boss_fam: String = FAMILY_ORDER[base_i]
	var p: Dictionary = boss_spawn_profile(boss_fam)
	var pool: Array = p.get("pool", fams)
	var ab := 0.0
	for f in pool:
		ab += _fam_gold(String(f), band)
	ab = ab / float(pool.size()) * _lvl_bonus_gold(band, int(p.get("lvl_bonus", 0)))
	y += BOSS_PHASE_SECONDS * float(p.get("rate", BOSS_SPAWN_BASE_RATE)) / 0.45 * ab
	var bu: Dictionary = p.get("burst", {})
	if not bu.is_empty():
		y += BOSS_PHASE_SECONDS / maxf(1.0, float(bu["interval"])) \
			* (float(bu["count_min"]) + float(bu["count_max"])) * 0.5 \
			* _fam_gold(String(bu.get("fam", boss_fam)), band)
	return y

func level_gold_norm(n: int) -> float:
	if is_final_level(n):
		return 1.0
	var band: int = _band_of(n)
	if not _lgn_cache.has(band):
		var tbl: Array = []
		var s := 0.0
		for r in GOLD_ROT:
			var y: float = _gold_yield(band, r)
			tbl.append(y)
			s += y
		var mean: float = maxf(0.001, s / float(GOLD_ROT))
		var out: Array = []
		for r in GOLD_ROT:
			out.append(float(tbl[r]) / mean)
		_lgn_cache[band] = out
	return float((_lgn_cache[band] as Array)[(maxi(1, n) - 1) % GOLD_ROT])

func kill_gold_unit(n: int) -> float:
	return KILL_GOLD_TUNE * gold_scale(n) \
		/ (_lvl_gold_norm(n) * density(n) * level_gold_norm(n))

# ---------------------------------------------------------------------------
# 建塔成本:固定價 (第十七輪)
#
# 第十五輪嘅「每多一座貴 3%」同「跟關卡縮放」兩個機制都拆咗。理由:標價
# 唔透明(同一座塔一時 60 一時 74),而佢哋想做嘅嘢(唔准無限建塔)而家
# 由金幣掉落曲線一個掣做晒 —— 收入封頂咗,塔數自然封頂,唔使喺價錢度
# 落第二重手。TradeDisplayTest 嘅「顯示價 == 扣賬價」斷言喺固定價之下
# 係恆等式。
# ---------------------------------------------------------------------------
## 起手金。以「第一座塔嘅價」做單位嚟睇:200 / 60 = 3.3 座箭塔。
const START_GOLD_BASE := 200.0

## 起一座 `id` 要幾多金。固定價:唔隨關卡,唔隨場上已建數量。
func place_cost(id: int) -> int:
	var def := tower_by_id(id)
	if def.is_empty():
		return 0
	return int(def.place_cost)

# ---------------------------------------------------------------------------
# ELITE AFFIX (第十五輪)
#
# 第九輪嘅難度牆死喺一個具體嘅缺口:「真正令一關變難嘅只有密度,而密度會
# 蓋過幅牆想教嘅嘢」。affix 就係嗰個缺口嘅答案 —— 一個**唔靠密度**嘅難度掣。
# 同一個怪數、同一個屍體數,但入面有一成係打法唔同嘅個體。
#
# 三個設計約束:
#   1. 每個 affix 只改一樣嘢,而嗰樣嘢要對應一種**已經存在**嘅反制。
#      (硬 -> 破甲/魔法;快 -> 控場;護 -> 減甲/真傷;再生 -> 減回復)
#   2. 精英怪掉多啲金。佢係一個機會,唔淨係一個懲罰。
#   3. 一眼認得出:sprite 加色 + 大一格。玩家要睇得出「呢隻唔同」。
# ---------------------------------------------------------------------------
const ELITE_AFFIXES := [
	{"id": "brute",  "name": "ELITE_BRUTE",  "hp": 2.2, "speed": 0.88, "armor": 0,  "mres": 0,  "regen": 0.0,   "tint": Color(1.25, 0.72, 0.62)},
	{"id": "swift",  "name": "ELITE_SWIFT",  "hp": 1.3, "speed": 1.42, "armor": 0,  "mres": 0,  "regen": 0.0,   "tint": Color(0.72, 1.25, 1.15)},
	{"id": "warded", "name": "ELITE_WARDED", "hp": 1.5, "speed": 0.96, "armor": 12, "mres": 25, "regen": 0.0,   "tint": Color(0.85, 0.9, 1.35)},
	{"id": "vital",  "name": "ELITE_VITAL",  "hp": 1.6, "speed": 0.94, "armor": 0,  "mres": 0,  "regen": 0.018, "tint": Color(0.75, 1.3, 0.78)},
]
## 精英怪掉幾多倍金。低過佢嘅血量倍率 —— 佢係一個機會,唔係一個提款機。
const ELITE_GOLD_MULT := 1.9
const ELITE_SIZE_MULT := 1.18

func elite_affix(idx: int) -> Dictionary:
	return ELITE_AFFIXES[posmod(idx, ELITE_AFFIXES.size())]

## 普通關嘅精英出現率。**只喺第 41 關之後開始**:41 係「逼你進化一次」嗰段
## 嘅起點,而 affix 存在嘅理由就係喺嗰度做一個唔靠密度嘅難度掣。體驗關同
## 「逼升級」嗰段一隻精英都冇,因為嗰兩段要教嘅嘢係基本操作同升級循環。
## 合約關另計 —— 佢嘅精英化係玩家自己揀返嚟嘅(見 CONTRACTS)。
const ELITE_FROM_LEVEL := 41
const ELITE_CHANCE_AT_START := 0.06
const ELITE_CHANCE_AT_END := 0.20

func elite_chance(n: int) -> float:
	if n < ELITE_FROM_LEVEL:
		return 0.0
	var t: float = clampf(float(n - ELITE_FROM_LEVEL) / float(FINAL_LEVEL - ELITE_FROM_LEVEL), 0.0, 1.0)
	return lerpf(ELITE_CHANCE_AT_START, ELITE_CHANCE_AT_END, t)

func creature_stats(fam: String, lvl: int, wave_scale: float, gold_unit := 1.0) -> Dictionary:
	var f: Dictionary = FAMILIES[fam]
	return {
		"hp": f.hp * LVL_HP[lvl] * wave_scale,
		"speed": f.speed * LVL_SPEED[lvl],
		"armor": f.armor + (lvl - 1),
		"mres": f.mres,
		"gold": int(round(f.gold * LVL_GOLD[lvl] * gold_unit)),
		"flying": f.flying,
		"mech": f.mech,
		"size": LVL_SIZE[lvl],
		"is_boss": false,
	}

## boss 家族壓力歸一化(第十七輪)。第四個隱藏難度修正器:boss 血 = 家族血
## x14,而家族血同速度差幾倍,機制強度(群療/復活光環/相位/俯衝)again 差
## 幾倍 —— 實測 A2/A3 喺自己前沿嘅輸贏**完全**跟 boss 家族走:全勝
## goblin/golem/beetle(慢重甲、機制溫和),全敗 wolf/skeleton/ghost/bat/
## cultist(快/復活/相位/群療),擺動係 0% <-> 100%,Gate 7 嘅段內孤島全部
## 係佢。歸一:boss 有效壓力 = 血 x 速度 x 機制係數,釘喺全家族**平均**
## (即係平均難度唔郁,得擺動冇咗)。家族風味保留喺速度/護甲/機制本身 ——
## 狼 boss 仲係快而脆,樹妖 boss 仲係慢而厚,但唔再係「撞正邊隻就輸」。
##
## 機制係數係實測導出嘅相對強度估值,唔係擬合精確值 —— 佢要做嘅只係將
## 0%<->100% 嘅擺動壓落 gate 容忍帶以內。第一版用 1.2-1.35 嘅溫和係數,
## 實測前沿嘅輸贏照舊完全跟 boss 家族走:A2 喺第 84 關贏 golem boss
## (難度係第 71 關 1.8 倍)但喺第 72 關輸 wolf boss —— 即係機制強度嘅
## 真實差距係 ~2 倍級,唔係三成。呢版嘅係數就係按嗰個實測 spread 校。
## 第二步(0.75/0.8 -> 0.65/0.7):20-seed 實測 A2 喺 71-99 剩低嘅贏
## **全部**集中喺 summon/stoneskin/reflect boss 嘅關(71/74/78/81/84),
## 即係呢三個「溫和機制」嘅係數仲係高估咗佢哋 —— 再落一格,佢哋嘅 boss
## 血再高 15%,前沿嘅慢 boss 孤島先剷得平。
const BOSS_MECH_TOUGH := {
	"summon": 0.65, "enrage": 1.7, "revive_aura": 1.7, "stoneskin": 0.7,
	"phase_fast": 1.9, "dive": 2.0, "root_heal": 1.1, "reflect": 0.7,
	"mass_heal": 2.1, "split_birth": 0.9,
}
var _boss_pressure_mean := 0.0

func _boss_tough(f: Dictionary) -> float:
	return float(BOSS_MECH_TOUGH.get(String(f.boss), 1.0))

## 呢個家族嘅 boss 基礎血量(乘 boss_scale 之前)。
## boss 嘅護甲/魔抗(`boss_stats`:家族值 +6 / +5)第十七輪冇入呢條歸一化,
## 而佢同雜兵嗰邊一樣係一個純粹嘅有效血量倍率 —— 岩石巨像 boss 18 甲 = ×1.36,
## 甲蟲皇 12 甲 = ×1.24,哥布林王 8 甲 = ×1.16。實測第 18(甲蟲皇)同第 24
## (岩石巨像)兩關嘅 A1 勝率係 0%,而同段平均 90%。
func boss_hp_coeff(fam: String) -> float:
	if _boss_pressure_mean <= 0.0:
		var s := 0.0
		for k in FAMILY_ORDER:
			var f: Dictionary = FAMILIES[k]
			s += float(f.hp) * 14.0 * float(f.speed) * _boss_tough(f) \
				* _resist_mult(float(f.armor) + 6.0, float(f.mres) + 5.0)
		_boss_pressure_mean = s / float(FAMILY_ORDER.size())
	var f2: Dictionary = FAMILIES[fam]
	return _boss_pressure_mean / (float(f2.speed) * _boss_tough(f2)
		* _resist_mult(float(f2.armor) + 6.0, float(f2.mres) + 5.0))

func boss_stats(fam: String, wave_scale: float) -> Dictionary:
	var f: Dictionary = FAMILIES[fam]
	return {
		"hp": boss_hp_coeff(fam) * wave_scale,
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
	## `extra` 收 curve 呢類唔係「一個數」嘅嘢,同 _build_spells 一樣嘅寫法。
	## 放最後而且有預設值,所以冇 curve 嘅十九座塔一個字都唔使改。
	var t := func(id,name,desc,mech,place,unlock,stats,ups,extra={}):
		var d := {"id":id,"kind":"tower","name":name,"desc":desc,"mech":mech,
			"place_cost":place,"unlock":unlock,"stats":stats,"ups":ups}
		for k in extra:
			d[k] = extra[k]
		TOWERS.append(d)

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
	# ==== 第十八輪:鍊金塔全面重校(G2)====
	# 舊數值係一個冇人量過嘅發散源:gold 8 x rate 0.4 已經係 3.2 金/秒(當時
	# 一關雜兵掉落總共先得 ~320 金,即係一座零升級嘅鍊金塔差唔多等於成關嘅
	# 掉落),而 `gold` 同 `startgold` 兩個 stat 仲要喺 TIER_SCALED_STATS 入面
    # —— 塔嘅 tier 倍率係 14.66,第三階就係 215 倍。一座滿課 T3 鍊金塔量出嚟
	# 係成千金/秒。之所以一直冇人見到,係因為 GateSim 只升級**輸出塔**,鍊金塔
	# 永遠停喺第一階第零級。
	#
	# 而家四條金軸全部改行 `curve`(逐階終點),即係話佢哋完全唔食 tier 幾何
	# 倍率,每一階去到幾多係寫出嚟嘅。G2 嘅目標:三座 T3 滿課鍊金塔 = 當關總金
	# x1.22 左右。
	#   gold       每次產出(未乘 gold_scale)
	#   rate       每秒產出次數
	#   killbonus  射程內擊殺嘅額外掉金(唔跨塔疊加,Battle 撞到第一座就 break)
	#   critgold   產出暴擊機率(x2)—— 舊版呢條軸**完全冇實作**,見 Tower._fire_alchemy
	#   startgold  落塔嗰刻一次過入賬
	t.call(12,"TOWER_ALCHEMY_NAME","TOWER_ALCHEMY_DESC","alchemy",100,160,
		{"dmg":0.0,"rate":0.35,"range":180.0,"gold":1.2,"killbonus":0.0,"critgold":0.0,"startgold":0.0},
		[U("UP_GOLDAMT","gold",0.0,55,"add"),U("UP_GOLDRATE","rate",0.0,60,"add"),U("UP_KILLRANGE","range",14.0,45,"add"),
		 U("UP_KILLBONUS","killbonus",0.0,60,"add"),U("UP_CRITGOLD","critgold",0.0,65,"prob"),U("UP_STARTGOLD","startgold",0.0,55,"add")],
		{"curve":{"gold":[1.10,1.16,1.20],"rate":[0.50,0.56,0.60],
			"killbonus":[0.042,0.054,0.066],"critgold":[0.10,0.14,0.18],
			"startgold":[6.0,8.0,10.0]}})
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
		{"dmg":0.0,"rate":0.0,"range":200.0,"curse":0.50,"goldbonus":0.15,
		 "linger":2.0,"slow":0.0,"bosseff":0.6},   # goldbonus 0.25 -> 0.15:見下面 curve
		[U("UP_CURSE","curse",0.025,70,"add"),U("UP_AURARANGE","range",14.0,50,"add"),
		 U("UP_GOLDBONUS","goldbonus",0.0,60,"add"),U("UP_LINGER","linger",0.25,50,"add"),
		 U("UP_CURSESLOW","slow",0.02,60,"add"),U("UP_BOSSEFF","bosseff",0.025,65,"add")],
		## 第十八輪:掉金軸改行 curve(G2)。舊版 0.25 + 0.025x15 = 0.625,再連
		## 跨階 carry 去到 T3 大約 +76% —— 一座塔就食走 G2 全部預算。curve 之下
		## T3 滿課 = +35%,而佢只喺光環覆蓋到嘅擊殺度數,所以實際落袋約 +15%。
		{"curve":{"goldbonus":[0.20, 0.25, 0.31]}})
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
##
## 第十五輪由 1.15 調到 1.45,而理由係量出嚟嘅。Gate 5 要求「A2(tier 2)
## 喺第 71-99 關勝率 ≤15% 而 A3(tier 3)≥55%」—— 即係話兩個 build 之間要
## 有一段容得落二十九關嘅距離。1.15 之下量到嘅距離只有 3.8 倍(A2 大約喺
## 難度 9000 死,A3 撐到 34000),而三十關嘅曲線就算平到每關 +3.2% 都要
## 用掉 2.5 倍 —— 所以 A2 死唔切,實測 71-99 仲有 19.5%。
##
## 躍升幅度打落 tier 3 係**平方**(tier 3 = STEP^2),所以呢個掣對「A2 vs A3」
## 呢個距離嘅槓桿最大:1.15 -> 1.45 令 tier 2 強 26%,但 tier 3 強 59%。
## 1.70 -> 1.95(第十八輪):Gate 5a 由 ≤18% 減半到 ≤9%,即係 A2 要喺 71-99
## 段入口就死;但 Gate 5b 同時要 A3 喺同一段有 ≥28%。實測 1.70 之下兩者太貼:
## A2 喺 71-72 仲係 100%,而 A3 喺 73-77 已經跌到 50%——「加難度殺 A2」同
## 「A3 要撐得住」係同一個掣嘅兩個方向,所以要嘅唔係難度,係**距離**。
## 呢個掣打落 tier 3 係平方,所以 1.70 -> 1.95 令 tier 2 強 15% 但 tier 3
## 強 32% —— 淨係擴闊咗 A2 同 A3 之間嗰段,而 71 段入口同步抬高 ×1.365
## (WAVE_BANDS 63-70)就啱啱好淨係 A2 死。(第十五輪由 1.15 調到 1.45
## 用嘅係同一條推理,同一個 gate。)
const TIER_JUMP := 1.95
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
## 明顯 —— 進化本身要係一個「儲一排」嘅決定,唔係順手撳嘅。
## (第十七輪試過將魔法 T3 減到 9000 去催 A3 早完成雙 tier-3 —— 實測完成
## 時點紋絲不動:樽頸係進化前置嘅三條軸要課滿,唔係呢舊費用。回退。)
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
## 點金術 T2「黃金洪流」嘅掉金加成**下限**。佢同 killbonus 軸係 maxf 關係
## (Spells.gd),唔係疊加 —— 所以佢真正嘅作用係「啱啱進化、一條軸都未課」
## 嗰刻都即刻有感覺。0.50 -> 0.06:0.50 之下 T2 未課軸都已經超出 G2 全部預算。
const GOLDEN_TIDE_BONUS := 0.06
const GOLDEN_TIDE_DUR := 10.0
## T3「邁達斯權柄」:期間敵人每中一下掉一金。
const MIDAS_HIT_GOLD := 1
## …但**每炮封頂**呢麼多金(第十八輪加)。冇呢個上限嘅話呢條收入同場上塔數
## 成正比而且冇邊界 —— 20 座塔一秒打中 30 下,即係一炮 300 金,而經濟曲線
## 越後期塔越多,佢就越發散。呢個係同 path 長度 / 家族組合同一類嘅隱藏修正器,
## 只不過佢喺經濟嗰邊。封頂之下佢係一個「開場一輪金雨」嘅演出,唔係一條收入。
const MIDAS_HIT_CAP := 10
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
## 第二十輪:地震術對**非 boss** 嘅殺傷力封頂。
##
## 問題唔係「傷害大」,係「一炮清場」。滿級 T3 打 85% 生命上限,而場上有四十
## 座塔喺度磨,所以隨時都有大半波怪血量低過 85% —— 一撳落去成波消失,連掉金
## 都一次過入晒。魔法變咗一粒「贏掉呢一波」掣,而塔喺嗰半秒入面冇存在過。
##
## 兩個獨立成因,所以要兩步一齊改:
##   1. 倍率本身太高            -> pct 曲線 0.42/0.62/0.85 落到 0.30/0.38/0.46
##   2. 冇任何嘢阻止佢補刀      -> 呢個下限:地震術唔可以令一隻非 boss 小怪
##                                跌穿生命上限嘅 12%。
##
## 第 2 點先係關鍵嗰步。淨係減倍率嘅話,血量低過新倍率嗰批照樣一炮死,而
## 「有幾多隻低過」係由塔火力決定,唔係由魔法決定 —— 即係話個殺傷比率仍然
## 會隨住玩家塔陣變強而升返上去,呢個 nerf 撐唔過三十關。有咗下限之後,
## 「地震術唔負責殺,佢負責震冧同打殘,補刀係塔嘅事」就變成一條結構性嘅
## 身份,唔係一個等人再調嘅數字。
##
## **控場完全冇郁**:RIFT_SLOW / SHATTER_STUN / SHATTER_GROUND_DUR 一個字都
## 冇改,`stunlen` 曲線亦冇改。nerf 傷害唔 nerf 控場。
## boss 嗰半邊(bossdmg / bosspct)亦都完全冇郁。
const QUAKE_MOB_FLOOR := 0.12

## 一次地震對一隻**非 boss** 敵人實際打幾多。
static func quake_mob_damage(hp: float, max_hp: float, pct: float) -> float:
	return maxf(0.0, minf(max_hp * pct, hp - max_hp * QUAKE_MOB_FLOOR))
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
	# ==== 第十八輪:點金術重校(G2)====
	# 舊數值有三重放大疊喺一齊:(1) `gold` 喺 TIER_SCALED_STATS 入面,魔法
	# tier 倍率 5.64,第三階 31.8 倍 —— T3 滿課一炮 18,126 金;(2) killbonus
	# 曲線去到 +110% 掉金,而 dur 10 秒配 6.6 秒冷卻即係**全程覆蓋**,等於
	# 成關掉金翻倍;(3) T3 每中一下掉一金,而場上塔越多呢個數越大,冇上限。
	# 三樣夾埋就係 Jack 講嗰句「用咗比唔用多幾倍」。
	#
	# 機制身份唔改:佢仍然係「一撳跳一舊錢」。改嘅係三樣嘢全部行 curve /
	# 封頂,而三者嘅預算加埋 = 當關總金 x1.30(G2 中位)。
	#   gold       一炮嘅即時金(未乘 gold_scale)。佔預算 ~60%,佢係身份。
	#   cd         13 秒(舊 6.6)—— 一炮大過兩炮細,「跳錢」先睇得見。
	#   killbonus  期間掉金加成,由 +110% 收到 +8%。
	s.call(6,"SPELL_MIDAS_NAME","SPELL_MIDAS_DESC","midas",18.0,false,
		{"gold":20.0,"cd":18.0,"killbonus":0.0},
		[U("UP_GOLDAMOUNT","gold",0.0,55,"add"),U("UP_CD","cd",0.0,60,"add"),U("UP_KILLGOLD","killbonus",0.0,60,"add")],
		{"curve":{"gold":[24.0,26.0,28.0],"cd":[15.0,14.0,13.0],
			"killbonus":[0.035,0.05,0.065]}})
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
		 # 第二十輪:pct 0.42/0.62/0.85 -> 0.30/0.38/0.46(見 QUAKE_MOB_FLOOR
		 # 嗰段)。cd / bosspct / stunlen 一個字冇改。
		 "curve":{"pct":[0.30,0.38,0.46],"cd":[8.0,7.0,6.5],
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
# 完整數字喺 docs/design/BALANCE_CHANGELOG.md「第九輪」,量度工具係 BalanceSim --walls。
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

# ===========================================================================
# 風險合約關 (第十七輪 v2:一關一卡)
#
# 「賭出嚟嘅晶石」。逢 7 嘅倍數關,**入關時**三選一,揀嘅嗰張合約
# (怪物增益 + 獎勵倍率)生效**成關**。v1 嘅逐段抽卡 + 疊加規則作廢。
#
# v2 嘅三個結構性決定,同埋點解:
#
#  1. **一關只揀一次。** v1 逐段五抽令玩家喺一場入面被打斷五次,而「背住
#     乜」要靠一個疊加面板先講得清。一關一卡之下,卡面 = 成關嘅全部規則,
#     冇疊加、冇「簽下後總倍率」呢種二階數。
#
#  2. **三張卡保證低/中/高風險各一張。** v1 只保證「起碼一張 risk 0」,
#     所以有機會出「三張都係中高風險」嘅局。而家每一級各出一張,「唔賭 /
#     細賭 / 全押」三個選項每一次都齊 —— 三級嘅幅度定義見 CONTRACTS 表頭。
#
#  3. **倍率封頂改為單卡上限。** 冇疊加就冇雪球,封頂由「疊加牆」(2.5)
#     變成「單卡設計上限」CONTRACT_MULT_CAP = 2.0:任何一張卡嘅晶石/金幣
#     倍率都唔准超過佢,dread_pact 就釘喺頂。contract_accumulate() 照 min
#     一次做防呆,GateSim 嘅 gate1(入咗 run_tests)有 GATE1B 斷言守住張表。
#
# 通關先兌現倍率、輸場照派普通輸場晶石 —— 呢兩條 v1 規則保留。
#
# 三級風險嘅定義(幅度都係「成關背住」嘅新結構,v1 嘅單卡數字係疊加件,
# 唔可以直接比較):
#   低 risk 0  單軸細增益,等效通關壓力 +8-12%    晶石 x1.22-1.30 金 <=x1.15
#   中 risk 1  單軸中度或功能性增益,+20-35%       晶石 x1.45-1.55 金 <=x1.30
#   高 risk 2  深軸或多軸,+50-80%                 晶石 x1.75-2.00 金 <=x1.25
#
# 低風險唔係 x1:Gate 8 要求「唔賭」嘅合約關收入都係普通關 1.1-1.3 倍,
# 而倍率只喺通關兌現、輸場冇份,所以卡面倍率要高過目標比率先追得到
# (實測 x1.2x 嘅卡面落袋大約係 1.1x)。
#
# 增益欄位:
#   hp / speed  血量、速度嘅**額外**比例        armor / mres  加多少點
#   regen       每秒回復 max_hp 嘅幾多          dense  出怪密度額外比例
#   elite       精英出現率(加落關卡本身嗰個)   noslow 免疫減速(布林)
# ===========================================================================
const CONTRACT_EVERY := 7
const CONTRACT_CHOICES := 3
## 單卡倍率上限(晶石同金幣各自計)。設計上限,唔係疊加牆 —— 表入面唔准有
## 卡超過佢,最高嗰張(dread_pact)就係釘喺呢個數。
const CONTRACT_MULT_CAP := 2.0

var CONTRACTS := [
	# --- risk 0(低):單軸細增益。每次抽卡固定出一張。----------------------
	{"id":"tithe_flesh", "risk":0, "name":"CONTRACT_TITHE_FLESH", "buff":{"hp":0.12},                "crystal":1.28, "gold":1.00},
	{"id":"tithe_haste", "risk":0, "name":"CONTRACT_TITHE_HASTE", "buff":{"speed":0.08},             "crystal":1.25, "gold":1.10},
	{"id":"tithe_plate", "risk":0, "name":"CONTRACT_TITHE_PLATE", "buff":{"armor":5.0},              "crystal":1.26, "gold":1.00},
	{"id":"tithe_ward",  "risk":0, "name":"CONTRACT_TITHE_WARD",  "buff":{"mres":12.0},              "crystal":1.26, "gold":1.00},
	{"id":"tithe_swarm", "risk":0, "name":"CONTRACT_TITHE_SWARM", "buff":{"dense":0.12},             "crystal":1.22, "gold":1.15},
	# --- risk 1(中):一條軸,一個明確反制。每次抽卡固定出一張。------------
	{"id":"iron_pact",   "risk":1, "name":"CONTRACT_IRON",   "buff":{"hp":0.35},                     "crystal":1.52, "gold":1.00},
	{"id":"swift_pact",  "risk":1, "name":"CONTRACT_SWIFT",  "buff":{"speed":0.20},                  "crystal":1.50, "gold":1.00},
	{"id":"ward_pact",   "risk":1, "name":"CONTRACT_WARD",   "buff":{"mres":25.0},                   "crystal":1.45, "gold":1.00},
	{"id":"plate_pact",  "risk":1, "name":"CONTRACT_PLATE",  "buff":{"armor":13.0},                  "crystal":1.45, "gold":1.00},
	{"id":"regen_pact",  "risk":1, "name":"CONTRACT_REGEN",  "buff":{"regen":0.015},                 "crystal":1.48, "gold":1.15},
	{"id":"swarm_pact",  "risk":1, "name":"CONTRACT_SWARM",  "buff":{"dense":0.30},                  "crystal":1.45, "gold":1.30},
	{"id":"unbound_pact","risk":1, "name":"CONTRACT_UNBOUND","buff":{"noslow":true},                 "crystal":1.50, "gold":1.00},
	# --- risk 2(高):深軸或多軸。每次抽卡固定出一張。----------------------
	{"id":"titan_pact",  "risk":2, "name":"CONTRACT_TITAN",  "buff":{"hp":0.80},                     "crystal":1.85, "gold":1.00},
	{"id":"elite_pact",  "risk":2, "name":"CONTRACT_ELITE",  "buff":{"elite":0.25},                  "crystal":1.80, "gold":1.15},
	{"id":"hunt_pact",   "risk":2, "name":"CONTRACT_HUNT",   "buff":{"speed":0.35,"noslow":true},    "crystal":1.90, "gold":1.00},
	{"id":"abyss_pact",  "risk":2, "name":"CONTRACT_ABYSS",  "buff":{"hp":0.50,"regen":0.012,"armor":9.0}, "crystal":1.85, "gold":1.25},
	{"id":"dread_pact",  "risk":2, "name":"CONTRACT_DREAD",  "buff":{"elite":0.30,"dense":0.20},     "crystal":2.00, "gold":1.00},
]

func is_contract_level(n: int) -> bool:
	## 第 100 關唔係合約關 —— 佢係終極戰,唔應該有第二套規則疊落去。
	return n > 0 and n % CONTRACT_EVERY == 0 and n != FINAL_LEVEL

func contract_by_id(cid: String) -> int:
	for i in CONTRACTS.size():
		if String(CONTRACTS[i]["id"]) == cid:
			return i
	return -1

## 抽三張卡:低/中/高風險**各一張**,順序固定 [低, 中, 高] —— 卡面嘅風險
## 色帶由上到下永遠係綠/琥珀/紅,玩家唔使逐張讀完先知邊張深邊張淺。
## 用 `randi()`,所以 harness `seed()` 之後結果係可重複嘅。
func contract_draw() -> Array:
	var out: Array = []
	for risk in CONTRACT_CHOICES:
		var tier: Array = []
		for i in CONTRACTS.size():
			if int(CONTRACTS[i]["risk"]) == risk:
				tier.append(i)
		if not tier.is_empty():
			out.append(tier[randi() % tier.size()])
	return out

## 把已揀合約(v2 之下最多一張)結算成「怪物增益 + 兩個倍率」。UI、戰鬥同
## 模擬全部問呢一個,所以「卡片顯示嘅狀態」同「怪物實際食到嘅增益」冇可能
## 講唔埋。空 array = 未簽約,全部返中性值。
func contract_accumulate(taken: Array) -> Dictionary:
	var buff := {"hp": 0.0, "speed": 0.0, "armor": 0.0, "mres": 0.0,
		"regen": 0.0, "dense": 0.0, "elite": 0.0, "noslow": false}
	var crystal := 1.0
	var gold := 1.0
	for i in taken:
		if i < 0 or i >= CONTRACTS.size():
			continue
		var c: Dictionary = CONTRACTS[i]
		for k in (c["buff"] as Dictionary):
			if k == "noslow":
				buff["noslow"] = true
			else:
				buff[k] = float(buff[k]) + float(c["buff"][k])
		crystal *= float(c["crystal"])
		gold *= float(c["gold"])
	return {
		"buff": buff,
		"crystal": minf(crystal, CONTRACT_MULT_CAP),
		"gold": minf(gold, CONTRACT_MULT_CAP),
		"crystal_raw": crystal,
		"gold_raw": gold,
		"capped": crystal > CONTRACT_MULT_CAP or gold > CONTRACT_MULT_CAP,
	}

## 一張卡嘅增益寫成一句人睇得明嘅字。UI 同報告共用,所以卡面永遠對得住數據。
func contract_buff_text(idx: int) -> String:
	if idx < 0 or idx >= CONTRACTS.size():
		return ""
	var b: Dictionary = CONTRACTS[idx]["buff"]
	var parts: Array = []
	# 百分比數字統一經 Upgrade.fmt_pct_num(整數預設、有需要先一位小數)——
	# 舊版 regen 硬寫 "%.1f",疊到 4% 嗰陣會印「4.0%」。armor/mres 係扁平點數,
	# 唔係百分比,照舊整數。
	if b.has("hp"):
		parts.append(tr("CONTRACT_B_HP").format({"n": Upgrade.fmt_pct_num(float(b["hp"]) * 100.0)}))
	if b.has("speed"):
		parts.append(tr("CONTRACT_B_SPEED").format({"n": Upgrade.fmt_pct_num(float(b["speed"]) * 100.0)}))
	if b.has("armor"):
		parts.append(tr("CONTRACT_B_ARMOR").format({"n": "%.0f" % float(b["armor"])}))
	if b.has("mres"):
		parts.append(tr("CONTRACT_B_MRES").format({"n": "%.0f" % float(b["mres"])}))
	if b.has("regen"):
		parts.append(tr("CONTRACT_B_REGEN").format({"n": Upgrade.fmt_pct_num(float(b["regen"]) * 100.0)}))
	if b.has("dense"):
		parts.append(tr("CONTRACT_B_DENSE").format({"n": Upgrade.fmt_pct_num(float(b["dense"]) * 100.0)}))
	if b.has("elite"):
		parts.append(tr("CONTRACT_B_ELITE").format({"n": Upgrade.fmt_pct_num(float(b["elite"]) * 100.0)}))
	if b.has("noslow"):
		parts.append(tr("CONTRACT_B_NOSLOW"))
	return "、".join(parts) if TranslationServer.get_locale().begins_with("zh") else ", ".join(parts)

## 一張卡嘅倍率寫成一句字。
func contract_mult_text(idx: int) -> String:
	if idx < 0 or idx >= CONTRACTS.size():
		return ""
	var c: Dictionary = CONTRACTS[idx]
	var parts: Array = []
	if float(c["crystal"]) > 1.001:
		parts.append(tr("CONTRACT_M_CRYSTAL").format({"n": "%.2f" % float(c["crystal"])}))
	if float(c["gold"]) > 1.001:
		parts.append(tr("CONTRACT_M_GOLD").format({"n": "%.2f" % float(c["gold"])}))
	return "  ".join(parts)

# ===========================================================================
# 第 100 關 —— 終極戰
#
# 「全部 boss 種類一次過輪流/同場出現」。分三潮而唔係十隻一次過:十隻同場
# 嘅話畫面上分唔清邊條血條係邊隻,而且十個 boss 機制一齊行(復活光環 + 群療
# + 分裂 + 狼群)係一鑊冇人睇得明嘅粥。三潮之下每一潮係一個睇得出嘅陣容,
# 而三潮加埋仍然係「全部十隻」。
#
# 潮與潮之間唔等清場:下一潮嘅計時由上一潮出場嗰刻起計,所以拖得耐就一定
# 會撞到重疊 —— 「多試幾場先過到」嘅壓力來源就係呢個,唔係一個更大嘅血條。
# ===========================================================================
const FINAL_WAVES := [
	{"at":  30.0, "fams": ["goblin", "wolf", "skeleton"]},
	{"at":  92.0, "fams": ["golem", "ghost", "bat", "treant"]},
	{"at": 160.0, "fams": ["beetle", "cultist", "slime"]},
]
## 終極戰嘅 boss 血量相對一隻普通 boss。十隻疊埋唔可以每隻都係足血,唔係
## 佢就唔係「難」而係「長」。0.55 之下十隻加埋 = 5.5 隻 boss 嘅血,而佢哋
## 係同場嘅,所以實際壓力遠高過 5.5 隻順序出場。
const FINAL_BOSS_HP_FRAC := 0.55

# ---------------------------------------------------------------------------
# LEVEL generation. Infinite levels. Returns config for level N (1-based).
# ---------------------------------------------------------------------------
func level_config(n: int) -> Dictionary:
	# wave scaling: exponential HP/density growth. 1.16 compounds to 17.0x by
	# level 20, which no amount of gold or 魔晶 income could keep up with; 1.13
	# reaches 9.9x, which the (now wave-scaled) economy can actually track.
	# 第 21 關起轉第二段斜率 —— 見 WAVE_GROWTH_LATE。
	var wave_scale := self.wave_scale(n)
	# which families appear this level (2-3 families rotating) — the shared
	# helper, because fam_mix_norm() must see exactly the same list
	var base_i := (n - 1) % 10
	var fams: Array = level_families(n)
	# creature level band by game level
	## 第十五輪由 /9 拉到 /12:曲線由 40 關變 100 關,而 /9 之下第 37 關已經
	## 全部係 5 級怪,即係最後六十幾關嘅怪物等級係一條平線。/12 之下要去到
	## 第 49 關先封頂,多咗十二關嘅視覺同數值變化。
	var band := int((n - 1) / LVL_BAND_EVERY)  # 0 => lv1-2, 1 => lv2-3 ...
	var lmin: int = clampi(1 + band, 1, 5)
	var lmax: int = clampi(2 + band, 1, 5)
	# boss family
	var boss_fam: String = FAMILY_ORDER[base_i]
	# path template index
	var path_idx := (n - 1) % 6
	## 密度輕微跟關數行。**輕微**係一個決定,唔係一個保守:第九輪嘅牆量到
	## 密度會蓋過所有其他難度軸(玩家實際感覺到嘅係「屍體太多」),而屍體
	## 數亦都係效能上限。難度主力交俾血量曲線同 affix,密度只做少少陪襯。
	var dens: float = density(n)
	var cfg := {
		"level": n,
		"wave_scale": wave_scale,
		"boss_scale": boss_scale(n),
		"kill_gold_unit": kill_gold_unit(n),
		"difficulty": difficulty(n),
		"families": fams,
		"lvl_min": lmin,
		"lvl_max": lmax,
		"boss_family": boss_fam,
		"path_idx": path_idx,
		## 開場金同建塔成本行同一條曲線,所以「開場買得起幾多座」係一個常數。
		"start_gold": int(round(START_GOLD_BASE * gold_scale(n))),
		"boss_time": 60.0,
		"spawn_interval_start": 1.6 / dens,
		"spawn_interval_min": 0.45 / dens,
		"elite_chance": elite_chance(n),
		"is_contract": is_contract_level(n),
		"is_final": is_final_level(n),
		"is_wall": false,
	}
	if cfg["is_final"]:
		# 終極戰:雜兵照出(俾玩家有金收入同鍊金塔有嘢做),但主角係十隻 boss。
		cfg["families"] = FAMILY_ORDER.duplicate()
		cfg["lvl_min"] = 4
		cfg["lvl_max"] = 5
		cfg["boss_time"] = FINAL_WAVES[0]["at"]
		cfg["final_waves"] = FINAL_WAVES
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
## 第十五輪:單一幾何增長換成**分段**,同 WAVE_BANDS 一樣分段,而且分段點
## 一樣 —— 因為兩者答緊同一個問題嘅兩面:「呢一段要玩家攞到幾多力量」。
##
## 段嘅斜率係由**累積**收入倒推,唔係由「每關派幾多」拍出嚟:
##   L41 A2 要一座塔 + 一個魔法上到 tier 2  -> 累積 ~9 萬
##   L71 A3 要兩件嘢都上到 tier 3           -> 累積 ~42 萬
##   L100 A4 滿級                            -> 累積 ~160 萬(仲爭少少,所以要 farm)
## 由呢三點反解出嚟就係下面三段。頭段特別急(1.30)係因為升級價喺頭六級
## 本身就係 1.35 一級 —— 派彩要追得上嗰段,唔係第 5 關就買唔起嘢。
const REWARD_BANDS := [
	{"to": 10, "g": 1.100},
	{"to": 40, "g": 1.115},
	## 1.030 -> 1.038(第十七輪):A3 嘅雙 tier-3 完成點本來落喺 85-95,
	## 令 71-99 段內出現「S2 深谷 -> S3 返生」嘅 U 形(Gate 7 判倒掛)。
	## 呢段加薪令佢嘅段內曲線拍返平(實測 blocks 78/75/75)。A2 食同一份
	## 糧會變強 —— 嗰邊由後期金幣曲線(第十八輪之後係 GOLD_BANDS 最後兩段)
	## 收返,唔再鬥難度。
	{"to": 70, "g": 1.038},
	# 第 71 關之後**唔再加**。呢個唔係「懶得調」:實測到 A3 喺第 91-99 關
	# 嘅勝率比第 81-90 關**高咗 26 點**(56% -> 82%),而嗰個倒掛嘅來源就係
	# 呢一段嘅收入 —— 佢喺升級軸已經飽和嘅時候繼續派錢,錢就會流去「鋪闊」
	# (多解鎖幾個魔法、多課幾座塔),而鋪闊嘅戰力增長快過難度曲線。
	# 派平咗之後,呢一段嘅意思變成「元進度基本上行完,剩返嘅係操作」——
	# 而嗰個先係「雙階段 3 之後仲有 29 關」應該講嘅嘢。
	# 1.010 -> 1.000(第十七輪):71-99 段加硬咗之後,A3 嘅前沿入咗段內,
	# 而佢喺段內嘅收入增長令 91-99 嘅勝率(73%)反高過 81-90(60%)——
	# 十五輪嗰個倒掛喺新斜率下翻返出嚟。段內派彩完全揸平,倒掛先斷根。
	{"to": 99, "g": 1.000},
]
const REWARD_BASE_CLEAR := 55.0
const REWARD_BASE_FIRST := 62.0
## 第 100 關派多啲 —— 佢係一場要試好多次先贏得到嘅仗,而每一次失敗都要
## 買得到落一次嘅本錢。
const FINAL_REWARD_MULT := 2.5

var _reward_cache: Array = []
var _cumreward_cache: Array = []

func _build_reward_cache() -> void:
	_reward_cache = [0.0, 1.0]
	var cur := 1.0
	var n := 2
	for band in REWARD_BANDS:
		while n <= int(band["to"]):
			cur *= float(band["g"])
			_reward_cache.append(cur)
			n += 1
	_reward_cache.append(cur * FINAL_REWARD_MULT)   # 第 100 關
	# 累積(通關 + 首通),typical_upgrade_cost() 用嚟推玩家嘅預算
	_cumreward_cache = [0.0]
	var acc := 0.0
	for i in range(1, _reward_cache.size()):
		acc += (REWARD_BASE_CLEAR + REWARD_BASE_FIRST) * float(_reward_cache[i]) * CRYSTAL_REWARD_MULT
		_cumreward_cache.append(acc)

func reward_scale(n: int) -> float:
	if n <= 1:
		return 1.0
	if n < _reward_cache.size():
		return float(_reward_cache[n])
	var last: float = float(_reward_cache[FINAL_LEVEL - 1])
	return last * pow(float(REWARD_BANDS[REWARD_BANDS.size() - 1]["g"]), n - (FINAL_LEVEL - 1))

func level_crystal_reward(n: int) -> int:
	## 通關獎勵. Meta.on_level_cleared halves this on a replay.
	return int(round(REWARD_BASE_CLEAR * reward_scale(n) * CRYSTAL_REWARD_MULT))

func level_first_clear_bonus(n: int) -> int:
	## 首次通關獎勵 — paid ONCE per level, on top of the clear reward, so pushing
	## into a NEW level always beats re-farming an old one.
	return int(round(REWARD_BASE_FIRST * reward_scale(n) * CRYSTAL_REWARD_MULT))

## 打到第 n 關為止,一個一次過通關嘅玩家總共攞過幾多魔晶。
func cumulative_reward(n: int) -> float:
	if n <= 0:
		return 0.0
	if n < _cumreward_cache.size():
		return float(_cumreward_cache[n])
	var acc: float = float(_cumreward_cache[_cumreward_cache.size() - 1])
	for k in range(_cumreward_cache.size(), n + 1):
		acc += (REWARD_BASE_CLEAR + REWARD_BASE_FIRST) * reward_scale(k) * CRYSTAL_REWARD_MULT
	return acc

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
## 第十五輪換咗**模型**,唔係換數字。
##
## 舊版係一條(兩段)幾何線,由 20 關嘅實測擬合出嚟。延伸到 100 關之後
## 佢即刻壞:實際升級價有一個**天花板**(一條軸最貴嗰級 = base x 1.35^6
## x 1.10^38 ≈ 249 x base ≈ 1.4 萬),而一條幾何線去到第 100 關會叫到
## 23 萬。敗仗獎勵釘住呢個數,所以擬合一飄,敗仗就會派到「一場輸 = 十六級」。
##
## 而家直接計,唔擬合。C(N) 呢個概念本身就係一句可以computed嘅說話:
##
##   「玩家到第 N 關為止賺過嘅錢,攤落佢鋪開嗰幾條軸,買到第幾級,
##     而第幾級嘅**下一級**要幾錢」
##
## 兩個輸入(累積派彩、鋪開幾多條軸)都係設計品,唔係實測殘差,所以:
##   * 改派彩曲線,C(N) 自己跟住郁 —— 敗仗獎勵冇可能再靜靜咁飄離佢
##     應該追蹤嗰樣嘢(呢個係舊模型每一輪都要人手重擬合嘅原因)。
##   * 曲線自動飽和:軸課滿咗就唔會再貴,所以第 80 關同第 100 關嘅
##     C(N) 差唔多,而嗰個就係事實。
##
## TYPICAL_AXES 係「一個合理玩家同時鋪開幾多條軸」。呢個數細啲 = 課得深啲
## = C(N) 高啲,所以佢係一個真掣,而唔係一個殘差。
##
## 第十五輪由 9 調到 14,而理由係一條**兌現唔到嘅承諾**:9 之下量到嘅
## 通關獎勵 / C(N) 喺第 9-19 關只有 1.06,而敗仗獎勵封頂係通關嘅 0.9 倍
## —— 即係話「輸一場 = 一級升級」呢句話喺嗰幾關數學上唔可能成立
## (0.9 x 1.06 = 0.95 < 1)。
##
## 14 唔係為咗遷就個上限拍出嚟嘅:佢係**實際政策**嘅數。GateSim 嘅 A1 買嘢
## 政策係「主力塔六軸 + 主力魔法三軸,之後鋪去核心塔」,跑完一百關實際掂過
## 嘅軸數係十幾條,唔係九條。9 呢個數來自一個舊 harness 嘅 CORE_COUNT x
## CORE_DIRS,而嗰個 harness 已經唔係而家量緊嘢嗰個。
const TYPICAL_AXES := 14.0
## 平均一條升級軸嘅基價(20 座塔 x 6 條 + 15 個魔法 x 3 條嘅中位數)。
const TYPICAL_AXIS_BASE := 55
## 一個乜都未買嘅玩家買嘅唔係中位數嗰條軸,係**最平嗰條**(箭塔射程 35)。
## 冇呢個 ramp,第 1 關嘅 C(N) 會報 55 而實際係 35,而敗仗獎勵封頂就會喺
## 嗰一關(而且淨係嗰一關)跌穿「輸一場 = 一級」。ramp 喺頭六級之內收斂 ——
## 六級之後玩家已經鋪開咗,中位數先至係啱嘅描述。
const MIN_AXIS_BASE := 35
const AXIS_BASE_RAMP := 6.0

func _axis_base_at(lv: int) -> int:
	var t: float = clampf(float(lv) / AXIS_BASE_RAMP, 0.0, 1.0)
	return int(round(lerpf(float(MIN_AXIS_BASE), float(TYPICAL_AXIS_BASE), t)))

var _cost_cache: Dictionary = {}

func typical_upgrade_cost(n: int) -> int:
	var key: int = maxi(1, n)
	if _cost_cache.has(key):
		return int(_cost_cache[key])
	var budget: float = cumulative_reward(key) / TYPICAL_AXES
	var lv := 0
	var spent := 0.0
	var cap: int = MAX_UP_LV * MAX_TIER
	while lv < cap:
		var c: float = float(upgrade_cost(_axis_base_at(lv), lv))
		if spent + c > budget:
			break
		spent += c
		lv += 1
	var out: int = upgrade_cost(_axis_base_at(lv), mini(lv, cap - 1))
	_cost_cache[key] = out
	return out

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
	_build_wave_cache()
	_build_gold_cache()
	_build_reward_cache()
	_build_towers()
	_build_spells()
	_build_tiers()
