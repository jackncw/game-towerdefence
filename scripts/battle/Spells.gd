extends RefCounted
class_name Spells
## Stateless spell resolver. cast() reads effective stats from Meta and applies
## the effect to the battle. Returns true if cast succeeded (target valid).
##
## Round-5 presentation pass (visual only — no stat, cost or timing changed):
##   * seven spells (summon / midas / timewarp / warcry / barrier / tornado /
##     firewall) previously had NO on-screen performance at all; every spell now
##     shows where it happened and to whom.
##   * the big ones leaned on a full-screen colour wash (meteor 0.28, freeze
##     0.42, emp 0.22) which washed the board out and hid the very thing it was
##     announcing. Washes are now a thin accent (<=0.16) and the impact is
##     carried by world-space rings/bursts/debris instead.

## A layered impact: shockwave ring + fireball + debris. `power` scales it.
static func _impact(battle, pos: Vector2, r: float, c: Color, power := 1.0) -> void:
	battle.spawn_fx_ring(pos, r * 1.25, c.lightened(0.25))
	battle.spawn_fx_burst(pos, r, c, 0.45)
	battle.spawn_fx_burst(pos, r * 0.55, c.lightened(0.5), 0.3)
	battle.spawn_sparks(pos, int(10 * power), c, 260.0 * power, 6.0, 0.65)

## Concentric rings travelling out from a point — used for the全場 spells so
## they read as one event sweeping the map rather than a flat coloured disc.
static func _shockwaves(battle, pos: Vector2, r: float, c: Color, n := 3) -> void:
	for i in n:
		battle.spawn_fx_ring_dur(pos, r * (0.45 + 0.28 * i), c, 0.45 + 0.13 * i)


## 一次傷害 = 固定值 + 目標生命上限嘅一份。
##
## 點解要有兩份:怪物血量係指數成長(第 40 關 wave_scale 1426 倍),所以任何
## 固定傷害去到後段都等於零 —— 用戶報上嚟嘅「滿級隕石術喺第 20 關已經零存在
## 感」就係呢件事。淨用百分比又會令頭幾關嘅細怪打唔死(佢哋血少,一成血
## 等於冇)。兩份加埋先至兩頭都成立。
static func _dmg(s: Dictionary, m) -> float:
	return float(s.get("dmg", 0.0)) + float(s.get("dmgpct", 0.0)) * m.max_hp

static func cast(battle, id: int, pos: Vector2) -> bool:
	var s: Dictionary = Meta.spell_stats(id)
	var def: Dictionary = GameData.spell_by_id(id)
	var centre := Vector2(540, 960)
	# 進化階級。每個 mech 入面用 t2 / t3 兩個 bool,keep 住每一段照原本咁讀。
	var tier: int = Meta.spell_tier(id)
	var t2: bool = tier >= 2
	var t3: bool = tier >= 3
	match def.mech:
		"meteor":
			# the rock itself: a long burning streak in from off-screen
			battle.spawn_line(PackedVector2Array([pos + Vector2(-620, -1180),
				pos + Vector2(-150, -300), pos]), Color(1, 0.72, 0.32), 16, 0.22)
			battle.spawn_line(PackedVector2Array([pos + Vector2(-560, -1120),
				pos]), Color(1, 0.94, 0.7), 6, 0.18)
			_impact(battle, pos, s.radius, Color(1, 0.5, 0.2), 1.8)
			_shockwaves(battle, pos, s.radius * 1.5, Color(1, 0.66, 0.3), 3)
			battle.spawn_sparks(pos, 22, Color(0.5, 0.36, 0.28), 340.0, 7.0, 0.9, 620.0)
			battle.shake(16.0, 0.45)
			battle.flash(Color(1, 0.55, 0.25, 0.14), 0.3)
			for m in battle.monsters_in_radius(pos, s.radius, true):
				m.take_hit(_dmg(s, m), "magic")
			# T2 隕石風暴:主隕石之後跟三粒小嘅,散落喺周圍
			if t2:
				for i in GameData.METEOR_SHOWER_COUNT:
					var sp: Vector2 = pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) \
						* s.radius * 1.4
					_impact(battle, sp, s.radius * 0.5, Color(1, 0.6, 0.25), 0.7)
					for m2 in battle.monsters_in_radius(sp, s.radius * 0.55, true):
						m2.take_hit(_dmg(s, m2) * GameData.METEOR_SHOWER_FRAC, "magic")
			# T3 天隕滅世:著彈點留低熔岩地帶
			if t3:
				battle.spawn_hazard(pos, s.radius * 0.85,
					s.dmg * GameData.CATACLYSM_DPS_FRAC, GameData.CATACLYSM_DUR,
					Hazard.Kind.DOT, Color(1, 0.45, 0.15), true,
					{"dpspct": float(s.get("dmgpct", 0.0)) * GameData.CATACLYSM_DPS_FRAC})
		"stormbolt":
			var n := int(s.bolts)
			var list: Array = battle.all_monsters()
			list.shuffle()
			for i in mini(n, list.size()):
				var m = list[i]
				m.take_hit(_dmg(s, m), "magic")
				# T2 雷神之怒:每道閃電喺落點小範圍濺射
				if t2:
					for o in battle.monsters_in_radius(m.global_position,
							GameData.WRATH_SPLASH, true):
						if o != m:
							o.take_hit(_dmg(s, o) * GameData.WRATH_SPLASH_FRAC, "magic")
				# T3 萬雷天罰:被擊中嘅嘢一段時間內受到嘅所有傷害被放大
				if t3 and m.alive:
					m.apply_vuln(GameData.SKYFALL_VULN, GameData.SKYFALL_VULN_DUR)
				var mp: Vector2 = m.global_position
				battle.spawn_line(PackedVector2Array([mp + Vector2(randf_range(-60, 60), -900),
					mp + Vector2(randf_range(-40, 40), -400), mp]),
					Color(0.72, 0.9, 1.0), 7, 0.2)
				battle.spawn_fx_burst(mp, 46, Color(0.8, 0.94, 1.0), 0.28)
				battle.spawn_sparks(mp, 5, Color(0.8, 0.94, 1.0), 200.0, 4.0, 0.4)
			battle.flash(Color(0.7, 0.85, 1.0, 0.10), 0.2)
			battle.shake(5.0, 0.2)
		"freezenova":
			# a wave crossing the whole board + one frost bloom per victim, so
			# you can see exactly who got caught (the old flat disc showed none)
			var ice := Color(0.62, 0.9, 1.0)
			_shockwaves(battle, centre, 1500, ice, 3)
			for m in battle.all_monsters():
				# T2 絕對零度:凍結期間所受傷害大幅提高
				if t2:
					m.apply_vuln(float(s.get("vuln", 0.0)) + GameData.ABSZERO_VULN, s.dur)
				else:
					# vuln 由第一級起就課得到 —— 佢係「減冷卻」嗰條軸嘅代替品。
					m.apply_vuln(float(s.get("vuln", 0.0)), s.dur)
				m.apply_freeze(s.dur)
				m.apply_slow(s.slowafter, 2.0)
				battle.spawn_fx_burst(m.global_position, 40, ice, 0.4)
				battle.spawn_sparks(m.global_position, 4, Color(0.85, 0.97, 1.0),
					120.0, 5.0, 0.5, 80.0, true)
			battle.flash(Color(0.75, 0.92, 1.0, 0.16), 0.3)
			battle.shake(6.0, 0.25)
			# T3 永凍紀元:解凍之後留低一片冰原,繼續拖慢經過嘅嘢
			if t3:
				battle.spawn_hazard(centre, GameData.ICEAGE_RADIUS, 0.0,
					s.dur + GameData.ICEAGE_EXTRA, Hazard.Kind.SLOW,
					Color(0.7, 0.92, 1.0), false)
		"miasma":
			# healcut = 巫教族反制嘅魔法半邊。丟落一隊巫師身上,群療就補唔返。
			var mia := {"healcut": float(s.get("healcut", 0.0))}
			if t2:      # 腐蝕之霧:護甲被蝕
				mia["shred_armor"] = GameData.CORROSIVE_ARMOR
			if t3:      # 瘟疫爆發:死喺霧入面就再生一團
				mia["seed"] = true
			mia["dpspct"] = float(s.get("dpspct", 0.0))
			battle.spawn_hazard(pos, s.radius, s.dps, s.dur, Hazard.Kind.DOT, Color(0.5, 0.9, 0.2), false, mia)
			battle.spawn_fx_burst(pos, s.radius * 0.8, Color(0.5, 0.9, 0.2), 0.5)
			battle.spawn_sparks(pos, 10, Color(0.62, 0.95, 0.3), 130.0, 6.0, 0.9, -40.0)
		"summon":
			# 召喚陣成形嘅聲。派一次(唔係逐個兵派)—— 幾個陣同時亮起係一個
			# 法術嘅一下,唔係三下。同 sfx_spell_summon 疊住播:嗰個係「有嘢
			# 嚟緊」嘅號角,呢個係地上個陣本身喺度畫緊。
			Audio.play("sfx_summon_circle")
			# a rally beacon so the call-to-arms is visible, not just 3 tokens
			var rd: float = battle.route.nearest_dist_param(pos)
			for i in int(s.count):
				var off := randf_range(-45, 45)
				var sp: Vector2 = battle.route.pos_at(clampf(rd + off, 0.0, battle.route.total - 10))
				battle.spawn_line(PackedVector2Array([sp + Vector2(0, -320), sp]),
					Color(0.68, 0.86, 1.0), 8, 0.3)
				battle.spawn_fx_ring(sp, 60, Color(0.6, 0.82, 1.0))
				battle.spawn_sparks(sp, 6, Color(0.75, 0.9, 1.0), 150.0, 5.0, 0.5)
				var sd = battle.spawn_soldier(rd + off, s.hp, s.dmg, 2.0, null, 20.0, true)
				if sd:
					sd.shielded = t2       # T2 召喚聖騎:首次致命傷免疫
					if t3:                 # T3 英靈殿軍:陣亡爆炸 + 分時間畀同袍
						sd.death_blast = s.dmg * GameData.EINHERJAR_BLAST
						sd.share_life = true
		"midas":
			var paid: int = battle.scale_gold(s.gold)   # 一次過派錢,唔係涓滴收入
			battle.add_gold(paid, true)
			battle.spawn_damage(pos, paid, Color(1, 0.85, 0.2), true)
			# a coin fountain at the cast point and over the base
			battle.spawn_coin_pop(pos, 10)
			battle.spawn_coin_pop(battle.base_pos + Vector2(0, -40), 8)
			battle.spawn_fx_ring(pos, 90, Color(1, 0.85, 0.25))
			# T2 黃金洪流:即時金之外,一段時間內所有擊殺額外掉金
			if t2:
				battle.midas_bonus = maxf(battle.midas_bonus, GameData.GOLDEN_TIDE_BONUS)
				battle.midas_time = maxf(battle.midas_time, GameData.GOLDEN_TIDE_DUR)
			# T3 邁達斯權柄:期間敵人每被打中一次就掉一點金
			if t3:
				battle.midas_hit_gold = GameData.MIDAS_HIT_GOLD
				battle.midas_time = maxf(battle.midas_time, GameData.GOLDEN_TIDE_DUR)
			if s.killbonus > 0.0:
				battle.midas_bonus = maxf(battle.midas_bonus, float(s.killbonus))
				battle.midas_time = maxf(battle.midas_time, 10.0)
		"timewarp":
			battle.set_enemy_slow(s.slow, s.dur)
			# T2 時之枷鎖:敵人嘅技能節拍一齊被拖慢(boss_timer 直接推遲)
			if t2:
				battle.ability_slow = GameData.CHRONO_ABILITY_SLOW
				battle.ability_slow_time = s.dur
			for m in battle.all_monsters():
				battle.spawn_fx_ring(m.global_position, 44, Color(0.62, 0.8, 1.0))
				# T3 時光倒流:全場退回幾秒前嘅位置
				if t3:
					m.displace(m.base_speed * GameData.REWIND_SECONDS, false)
			_shockwaves(battle, centre, 1400, Color(0.6, 0.78, 1.0), 2)
			battle.flash(Color(0.6, 0.75, 1.0, 0.10), 0.35)
		"warcry":
			battle.set_warcry(s.haste, s.dur)
			# T2 軍團號令:攻速之外連攻擊力一齊加;T3 戰神降臨:攻擊附帶真傷濺射
			battle.warcry_power = GameData.LEGION_POWER if t2 else 0.0
			battle.warcry_splash = GameData.AVATAR_SPLASH if t3 else 0.0
			# every tower flares — the buff is on THEM, so show it on them
			for t in battle.towers:
				if not is_instance_valid(t):
					continue
				battle.spawn_fx_ring(t.global_position, 66, Color(1, 0.78, 0.35))
				battle.spawn_sparks(t.global_position, 5, Color(1, 0.86, 0.45),
					170.0, 5.0, 0.5, 240.0, true)
			_shockwaves(battle, battle.base_pos, 900, Color(1, 0.8, 0.35), 2)
			battle.flash(Color(1, 0.8, 0.4, 0.10), 0.25)
		"barrier":
			battle.base_shield += int(s.block)
			battle.barrier_reflect = s.reflect
			# T2 聖域屏障:結界存在期間基地附近持續受傷
			if t2:
				battle.spawn_hazard(battle.base_pos, GameData.SANCTUARY_RADIUS,
					s.reflect * GameData.SANCTUARY_DPS_FRAC + GameData.SANCTUARY_DPS_MIN,
					GameData.SANCTUARY_DUR, Hazard.Kind.DOT, Color(0.55, 0.82, 1.0), false)
			# T3 不滅堡壘:每擋一隻就回一層,直到上限
			battle.barrier_regen = GameData.BULWARK_REGEN_CAP if t3 else 0
			# a shield dome snapping shut over the keep
			for i in 3:
				battle.spawn_fx_ring_dur(battle.base_pos, 230 - i * 60,
					Color(0.55, 0.82, 1.0), 0.5 + i * 0.1)
			battle.spawn_fx_burst(battle.base_pos, 120, Color(0.6, 0.85, 1.0), 0.45)
			battle.spawn_sparks(battle.base_pos, 12, Color(0.7, 0.9, 1.0), 220.0, 6.0, 0.7, -60.0)
		"tornado":
			var list2: Array = battle.monsters_sorted_by_progress()
			var cnt := 0
			for m in list2:
				var p0: Vector2 = m.global_position
				m.displace(s.push)
				# a visible funnel: stacked rings + dust dragged backwards
				for k in 3:
					battle.spawn_fx_ring_dur(p0 + Vector2(0, -k * 26), 34 + k * 16,
						Color(0.78, 0.82, 0.74), 0.4 + k * 0.08)
				battle.spawn_sparks(p0, 6, Color(0.72, 0.68, 0.58), 210.0, 5.0, 0.55, 90.0)
				# T3 天災風暴:落地時按生命上限收一筆真傷
				if t3:
					m.take_true(m.max_hp * GameData.GALE_TRUE_FRAC)
				cnt += 1
				if cnt >= int(s.count):
					break
			# T2 颶風之眼:龍捲風原地留低,持續推回進入嘅嘢
			if t2:
				battle.spawn_hazard(pos, GameData.EYE_RADIUS, 0.0, GameData.EYE_DUR,
					Hazard.Kind.SLOW, Color(0.78, 0.82, 0.74), false,
					{"slow": GameData.EYE_SLOW})
		"quake":
			for m in battle.all_monsters():
				# T3 世界崩塌:飛行單位被震落地面(短暫變成地面單位),
				# 所以佢哋唔再係「地震無關」—— 呢個係地震術最大嘅盲點。
				if m.flying and t3:
					m.ground_time = maxf(m.ground_time, GameData.SHATTER_GROUND_DUR)
				if m.flying and not t3:
					continue
				if m.is_boss:
					m.take_true(s.bossdmg + float(s.get("bosspct", 0.0)) * m.max_hp)
				else:
					m.take_true(m.max_hp * s.pct)
				if not m.alive:
					continue
				# T2 大地撕裂:裂縫拖慢地面單位;T3 世界崩塌:直接震暈
				if t3:
					m.apply_stun(float(s.get("stunlen", 0.0)))
				elif t2:
					m.apply_slow(GameData.RIFT_SLOW, GameData.RIFT_DUR)
				battle.spawn_sparks(m.global_position, 5, Color(0.55, 0.42, 0.3),
					180.0, 5.0, 0.6, 700.0)
			# ground waves rolling out + dust kicked up across the field
			_shockwaves(battle, centre, 1600, Color(0.66, 0.5, 0.34), 3)
			for i in 7:
				var dp := Vector2(randf_range(80, 1000), randf_range(220, 1780))
				battle.spawn_sparks(dp, 6, Color(0.55, 0.42, 0.3), 240.0, 6.0, 0.7, 700.0)
			battle.flash(Color(0.7, 0.5, 0.32, 0.12), 0.3)
			battle.shake(20.0, 0.6)
		"firewall":
			# T2 煉獄之牆:火牆沿路推進;T3 不熄業火:死喺入面就燒得更耐
			var fw := {}
			if t2:
				fw["advance"] = GameData.INFERNAL_ADVANCE
			if t3:
				fw["feed"] = GameData.PYRE_FEED
			fw["dpspct"] = float(s.get("dpspct", 0.0))
			battle.spawn_hazard(pos, s.length * 0.6, s.dps, s.dur, Hazard.Kind.DOT, Color(1, 0.5, 0.2), true, fw)
			# flames erupting along the covered stretch of road
			var rd2: float = battle.route.nearest_dist_param(pos)
			for i in 5:
				var fp: Vector2 = battle.route.pos_at(clampf(
					rd2 + (i - 2) * s.length * 0.22, 0.0, battle.route.total - 10))
				battle.spawn_fx_burst(fp, 54, Color(1, 0.52, 0.18), 0.45)
				battle.spawn_sparks(fp, 6, Color(1, 0.7, 0.25), 200.0, 5.0, 0.7, -120.0)
			battle.shake(5.0, 0.2)
		"smite":
			# 支援型單位優先做目標 —— 一個單體點名法術嘅意義就係「揀邊個死」,
			# 而巫師 / 大祭司永遠係嗰個答案(見 GameData.SUPPORT_MECHS)。
			var m2 = battle.target_support_first(pos, 240.0, Callable(battle, "nearest_any"))
			if m2 == null:
				return false
			var d: float = _dmg(s, m2) * (1.0 + (s.bossmult if m2.is_boss else 0.0))
			if m2.is_support():
				# T2 神罰之矛再加一倍有多
				d *= (1.0 + float(s.get("supportmult", 0.0))
					+ (GameData.SPEAR_SUPPORT_MULT if t2 else 0.0))
			var hp_before: float = m2.hp
			m2.take_hit(d, "magic")
			# T3 審判日:溢出嘅傷害轉移到最近另一個敵人
			if t3 and not m2.alive:
				var over: float = maxf(0.0, d - hp_before)
				if over > 0.0:
					var nxt = battle.nearest_other(m2.global_position, 260.0, [m2])
					if nxt:
						nxt.take_hit(over, "magic")
			var tp: Vector2 = m2.global_position
			battle.spawn_line(PackedVector2Array([tp + Vector2(0, -1100),
				tp + Vector2(0, -420), tp]), Color(1, 1, 0.66), 12, 0.28)
			_impact(battle, tp, 84, Color(1, 1, 0.72), 1.2)
			battle.flash(Color(1, 1, 0.75, 0.12), 0.2)
			battle.shake(9.0, 0.3)
		"emp":
			# T2 癱瘓脈衝:範圍同時間一齊大幅延長(光環封鎖跟住暈眩,所以
			# 延長暈眩就係延長「巫師唔准做嘢」呢件事本身)
			# 範圍同暈眩秒數而家全部喺逐階曲線入面 —— 一個藏喺呢度嘅乘數
			# 係控場不變式掃描唔到嘅,而掃唔到就守唔到。
			var emp_r: float = s.radius
			var emp_d: float = s.dur
			var hit: Array = battle.monsters_in_radius(pos, emp_r, true)
			for m3 in hit:
				m3.apply_stun(emp_d)
				# T3 系統崩潰:增益全清,而且一段時間內唔可以再獲得
				if t3:
					m3.apply_buff_lock(emp_d + GameData.BLACKOUT_LOCK)
				# an arc reaching from the epicentre to each stunned target
				battle.spawn_line(PackedVector2Array([pos, m3.global_position]),
					Color(0.72, 0.48, 1.0), 5, 0.25)
				battle.spawn_fx_ring(m3.global_position, 38, Color(0.7, 0.45, 1.0))
			_impact(battle, pos, s.radius, Color(0.62, 0.32, 0.92), 1.3)
			battle.flash(Color(0.6, 0.35, 0.95, 0.12), 0.22)
		"blackhole":
			# T2 奇點:傷害逐秒遞增;T3 事件視界:結束時內爆
			var bh := {}
			if t2:
				bh["ramp"] = GameData.SINGULARITY_RAMP
			if t3:
				bh["implode"] = GameData.HORIZON_IMPLODE
			bh["dpspct"] = float(s.get("dpspct", 0.0))
			battle.spawn_hazard(pos, s.radius, s.dps, s.dur, Hazard.Kind.BLACKHOLE, Color(0.4, 0.2, 0.6), false, bh)
			for i in 3:
				battle.spawn_fx_ring_dur(pos, s.radius * (1.4 - i * 0.3),
					Color(0.55, 0.3, 0.85), 0.5)
			battle.spawn_fx_burst(pos, s.radius * 0.5, Color(0.35, 0.16, 0.55), 0.5)
			battle.shake(6.0, 0.3)
	# 法術聲派喺呢度,唔係派喺 match 之前。`smite` 揾唔到目標會 return false ——
	# 冇施放、冇入 cooldown、乜都冇發生 —— 而舊寫法照樣響咗一下完整嘅神罰聲。
	# 一個「乜都冇做」嘅點擊出到一個「做咗嘢」嘅聲,係最難查嘅嗰種騙人回饋。
	# 呢度係 cast() 唯一嘅成功出口,所以擺喺呢度先真係「派得成先出聲」。
	Audio.play_spell(String(def.mech))
	return true
