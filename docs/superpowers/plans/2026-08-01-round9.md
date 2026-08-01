# Round 9 Implementation Plan — 音效補完 / 難度牆 / 一手勢起塔

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 補齊全套音效(11 → 64)並接駁落實際遊戲事件;喺第 7/13/18 關(週期 20)加三幅用機制砌成嘅難度牆;將起塔由「開抽屜 + 拖放」改返一個手勢。

**Architecture:** 三部分互不依賴。音效繼續用 `tools/gen_audio.py` 嘅 numpy primitives 合成,`Audio.gd` 加幾張「事件 → 音名」註冊表同一個小節對齊嘅 BGM 交接;難度牆 100% 表達成 `GameData.gd` 一張表,`Battle.gd` 零改動;快捷列取代舊嘅「建造」把手,重用現有 `_card_gui → card_press/drag/release` 手勢鏈,釘選搬去主選單一個新畫面。

**Tech Stack:** Godot 4.7.1 (GDScript), Python 3 + numpy (音效生成), headless Godot 測試場景。

## Global Constraints

- Godot 執行檔:`C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe`(唔喺 PATH,每次寫全路徑)
- 基礎解像度 **1080×1920** portrait,`stretch canvas_items/expand`
- 所有玩家見到嘅文字一律行 `tr()` + `i18n/game.csv` 嘅 key,**唔准寫死中文或英文字串**;CSV 有 `keys,zh_TW,en` 三欄
- 加咗新字之後要跑 `python tools/subset_font.py`,否則 web 版會 tofu
- 音效檔一律 **16-bit mono 44.1kHz WAV**,出去 `assets/generated_audio/`
- 音名就係 bus 契約:`ui_*` → UI bus,`bgm_*` → BGM bus,其餘 → SFX bus
- 平衡數值一律落 `scripts/autoload/GameData.gd`,唔准散落 `Battle.gd`
- **GDScript 型別推斷陷阱(呢個 repo 中過好多次)**:`var x := untyped.method()` 會炒。`battle` / `m` / `tgt` / `def` 呢類變數係 untyped,所以一定要寫 `var x: Type = ...`
- **新增 / 改咗 PNG 或 WAV 之後必須跑一次 import**,否則 Godot 用緊 stale cache:
  `& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .`
- 每個 task 最後一步 commit,commit message 用完整句子講「做咗乜 + 點解」,結尾加
  `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`
- 測試一律 headless 跑,exit code 0 = pass:
  `& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/<Name>.tscn`

---

# PART 1 — 音效系統補完

## File Structure(Part 1)

| 檔 | 責任 |
|---|---|
| `tools/gen_audio.py` | 修改 — 加 `--verify` mode、加 53 個合成函數、補 `LOUDNESS` |
| `scripts/autoload/Audio.gd` | 修改 — 事件→音名註冊表(`DEATH_SOUND` / `HIT_SOUND` / `SPELL_SOUND` / 擴充 `TOWER_SOUND`)、小節對齊 BGM 交接 |
| `test/AudioTest.gd` | 修改 — 每張註冊表嘅每個名都要載到、bar 對齊嘅純函數測試 |
| `test/AudioHookTest.gd` + `.tscn` | 新增 — 跑一場真戰鬥,證明死亡/受擊/金幣/boss/勝負真係有派聲 |
| `scripts/battle/{Battle,Monster,Spells}.gd`、`scripts/autoload/Meta.gd`、`scripts/ui/MainMenu.gd` | 修改 — 接駁點 |

### 關於下面啲「合成配方」表

Task 1-5 入面每個音效函數用一行表格交代:**時長 + 用邊幾個 primitive + 點砌**。
呢啲行係規格,唔係佔位符 —— 照住寫就得,唔好即興換做第二種聲(換咗個音效組
就唔再係一套嘢)。基礎設施(primitives、`save()`、`LOUDNESS`、`SOUNDS` dict)
全部已經喺 `tools/gen_audio.py` 度,每個函數就係三到八行。

客觀關卡係 `python tools/gen_audio.py --verify`(Task 1 建立):冇 clipping、
冇近乎靜音、格式啱、loop 接口接得返。過到嗰關就算做完。

---

### Task 1: `--verify` 自查 + 死亡/受擊音(13 個)

**Files:**
- Modify: `tools/gen_audio.py`
- Modify: `scripts/autoload/Audio.gd`
- Modify: `test/AudioTest.gd`

**Interfaces:**
- Consumes: 現有 `gen_audio.py` primitives(`square/triangle/saw/sine/noise/sweep/adsr/perc/lowpass/highpass/bitcrush/pad/mix/seq/norm/fade_edges/save/note`)
- Produces:
  - `Audio.DEATH_SOUND: Dictionary` — family id(`"goblin"`…`"slime"`)→ 音名 String
  - `Audio.HIT_SOUND: Dictionary` — `"soft"`/`"hard"`/`"magic"` → 音名 String
  - `Audio.registered_sounds() -> Array` — 全部註冊表入面出現過嘅音名(去重、排序),後面每個 task 都會擴充呢個函數嘅來源
  - `python tools/gen_audio.py --verify` — 對每個已生成檔出一行 `名 時長 peak RMS clip數 loop接口差`,有問題 exit 1

- [ ] **Step 1: 喺 `Audio.gd` 加註冊表同 `registered_sounds()`**

喺 `TOWER_SOUND` 個 block 之後加:

```gdscript
## 每族一個死亡聲。共用一個「死亡」聲會令十族聽落一樣 —— 而玩家分辨怪物族群
## 嘅速度,喺 5x 之下係靠聽多過靠睇。
const DEATH_SOUND := {
	"goblin": "sfx_die_goblin", "wolf": "sfx_die_wolf",
	"skeleton": "sfx_die_skeleton", "golem": "sfx_die_golem",
	"ghost": "sfx_die_ghost", "bat": "sfx_die_bat",
	"treant": "sfx_die_treant", "beetle": "sfx_die_beetle",
	"cultist": "sfx_die_cultist", "slime": "sfx_die_slime",
}

## 受擊聲。三款按目標嘅防禦形態揀,唔係按傷害類型 —— 玩家要聽到嘅係「我打緊嘅
## 嘢硬唔硬」,唔係「我用緊乜屬性」(後者睇塔就知)。
const HIT_SOUND := {"soft": "sfx_hit_soft", "hard": "sfx_hit_hard", "magic": "sfx_hit_magic"}

## 每個註冊表引用過嘅音名。AudioTest 用佢做「改名唔會靜靜雞收聲」嘅防線:
## 任何一個表指去一個唔存在嘅檔,測試就紅,而唔係遊戲入面靜咗。
func registered_sounds() -> Array:
	var out: Dictionary = {}
	for e in TOWER_SOUND.values():
		out[String(e[0])] = true
	for n in DEATH_SOUND.values():
		out[String(n)] = true
	for n in HIT_SOUND.values():
		out[String(n)] = true
	var arr: Array = out.keys()
	arr.sort()
	return arr

## 按怪物嘅防禦形態揀受擊聲。門檻(甲 8 / 魔抗 15)取自 GameData.FAMILIES:
## golem(甲 12)同 beetle(甲 6,但 lvl 加成後過 8)算「硬」,ghost(魔抗 25)
## 同 bat(10)算「魔」,其餘算「軟」。
func play_hit(armor: float, mres: float) -> void:
	var key := "soft"
	if mres >= 15.0:
		key = "magic"
	elif armor >= 8.0:
		key = "hard"
	play_varied(String(HIT_SOUND[key]))

func play_death(fam: String) -> void:
	var n: String = String(DEATH_SOUND.get(fam, ""))
	if n != "":
		play_varied(n)
```

- [ ] **Step 2: 喺 `AudioTest.gd` 加註冊表 case**

喺 `_case_routing()` 之後加新函數,並喺 `_ready()` 嘅 `await _case_routing()` 之後加 `await _case_registry()`:

```gdscript
## 每張「事件 → 音名」表入面嘅每個名都要有實檔。呢個 case 存在嘅原因好具體:
## 改一個音名而唔改表,遊戲入面唯一嘅症狀係嗰個事件靜咗,而靜咗係冇人會即刻
## 發現嘅 bug。
func _case_registry() -> void:
	var names: Array = Audio.registered_sounds()
	_ok("G 註冊表非空", names.size() > 0, "registered_sounds() returned nothing")
	var missing: Array = []
	for n in names:
		if Audio.stream(String(n)) == null:
			missing.append(String(n))
	_ok("G 註冊咗嘅 %d 個音全部載到" % names.size(), missing.is_empty(),
		"missing: %s" % str(missing))
```

- [ ] **Step 3: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: FAIL — `G 註冊咗嘅 13 個音全部載到 — missing: [sfx_die_bat, sfx_die_beetle, ...]`(13 個新名,6 個舊 `sfx_atk_*` 應該冇事)

- [ ] **Step 4: 喺 `gen_audio.py` 加 `--verify`**

喺 `main()` 之上加:

```python
def verify():
    """Report the objective properties of every generated file.

    This exists because "sounds fine" is not a claim anyone can check later.
    Four things go wrong silently in a synthesised set and all four are visible
    in numbers: a clipped waveform (audible as crunch on loud speakers only), a
    sound whose RMS is far off its neighbours (it will bury or vanish under
    them), a loop whose ends do not meet (a tick once per bar, forever), and a
    file that is simply not there because a name was typo'd.
    """
    import glob
    bad = 0
    rows = []
    for path in sorted(glob.glob(os.path.join(OUT, "*.wav"))):
        name = os.path.splitext(os.path.basename(path))[0]
        with wave.open(path, "rb") as w:
            n = w.getnframes()
            pcm = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float64) / 32768.0
            sr = w.getframerate()
            ch = w.getnchannels()
            sw = w.getsampwidth()
        dur = n / float(sr)
        peak = float(np.max(np.abs(pcm))) if n else 0.0
        rms = float(np.sqrt(np.mean(pcm * pcm))) if n else 0.0
        clip = int(np.sum(np.abs(pcm) >= 0.999))
        seam = abs(float(pcm[0]) - float(pcm[-1])) if n else 0.0
        problems = []
        if sr != SR or ch != 1 or sw != 2:
            problems.append("format %dHz/%dch/%dbit" % (sr, ch, sw * 8))
        if clip > 0:
            problems.append("clip=%d" % clip)
        # A loop is the only kind that ticks; one-shots fade to silence anyway.
        if name.startswith("bgm_") and seam > 0.01:
            problems.append("loop seam %.4f" % seam)
        if rms < 0.02:
            problems.append("near silent")
        if problems:
            bad += 1
        rows.append((name, dur, peak, rms, clip, seam, problems))
    print("  %-24s %6s %6s %6s %5s %7s  %s"
          % ("name", "sec", "peak", "rms", "clip", "seam", "problems"))
    for name, dur, peak, rms, clip, seam, problems in rows:
        print("  %-24s %6.2f %6.3f %6.3f %5d %7.4f  %s"
              % (name, dur, peak, rms, clip, seam, ", ".join(problems) or "ok"))
    print("%d file(s), %d with problems" % (len(rows), bad))
    return 1 if bad else 0
```

同埋喺 `main()` 開頭加:

```python
    if len(argv) > 1 and argv[1] == "--verify":
        return verify()
```

- [ ] **Step 5: 寫 13 個合成函數**

每個都係一個 `def name(): ... return <numpy array>`,加落 `SOUNDS` dict。
下面每一行就係嗰個函數嘅規格 —— 用列出嘅 primitive、時長同特徵,唔好即興換做第二種聲。
全部最後過 `bitcrush(..., bits=6)` 保持同首批 11 個同一個 8-bit 質感。

| 函數 | 時長 | 合成配方 |
|---|---|---|
| `sfx_die_goblin` | 0.22 | `square(sweep(900, 300, d), d, duty=0.125) * perc(d, curve=8)` 尖叫,加 `highpass(noise(0.05), 3000) * perc(0.05, 12) * 0.4` 收尾 |
| `sfx_die_wolf` | 0.34 | `saw(sweep(420, 160, d), d) * adsr(d, .01, .06, .5, .18)` 嗥叫,`* (1 + 0.25*sin(2π*7*t(d)))` 抖音 |
| `sfx_die_skeleton` | 0.30 | 散骨:6 個 `square(note(72 - 4*i), 0.04, duty=.25) * perc(.04, 14)` 用 `place`-style 隨機間隔疊落一條 0.30 秒 zeros,乾、無低頻 |
| `sfx_die_golem` | 0.42 | 碎石:`lowpass(noise(d), 700) * perc(d, 3.5)` + 3 下 `sine(sweep(120, 40, .08), .08) * perc(.08, 9)` 錯開 |
| `sfx_die_ghost` | 0.46 | 消散:`triangle(sweep(700, 1800, d), d) * np.linspace(1, 0, int(SR*d))**2`,**冇 attack**(用 `np.linspace(0,1,int(SR*.08))` 起頭 fade in),加 `highpass(noise(d), 4000) * 0.15` |
| `sfx_die_bat` | 0.16 | `square(sweep(2600, 1400, d), d, duty=.125) * perc(d, 11)` 高頻吱聲,`bits=5` |
| `sfx_die_treant` | 0.40 | 折斷:`highpass(noise(.06), 2000) * perc(.06, 16)` 脆裂 + `triangle(sweep(220, 70, d), d) * perc(d, 4)` 倒下 |
| `sfx_die_beetle` | 0.24 | 脆殼:`highpass(noise(.08), 2500) * perc(.08, 13) * 0.9` + `square(sweep(520, 180, .18), .18, duty=.5) * perc(.18, 7)` |
| `sfx_die_cultist` | 0.38 | 吟唱斷掉:`saw(note(57), .16) * adsr(.16, .02, .04, .8, .04)` 突然轉 `saw(sweep(note(57), note(45), .22), .22) * perc(.22, 6)` 用 `seq()` 駁 |
| `sfx_die_slime` | 0.30 | 黏爆:`lowpass(noise(d), 1100) * perc(d, 5)` + `sine(sweep(300, 60, d), d) * perc(d, 4) * .7`,尾巴長、無高頻 |
| `sfx_hit_soft` | 0.07 | `lowpass(noise(d), 1800) * perc(d, 14) * .8` + `square(420, d, duty=.5) * perc(d, 16) * .4` |
| `sfx_hit_hard` | 0.10 | `lowpass(noise(d), 900) * perc(d, 10)` + `square(sweep(260, 150, d), d, duty=.5) * perc(d, 9)`,`bits=5` |
| `sfx_hit_magic` | 0.09 | `triangle(sweep(1800, 1150, d), d) * perc(d, 12)` + `highpass(noise(d), 5000) * perc(d, 16) * .35` |

同時喺 `LOUDNESS` 加(死亡同受擊喺 5x 之下每秒響幾十次,一定要坐低):

```python
    # 死亡 / 受擊:5x 之下一秒幾十次,坐低過攻擊聲先唔會蓋住成場
    **{("sfx_die_%s" % f): 0.085 for f in
       ["goblin", "wolf", "skeleton", "golem", "ghost", "bat",
        "treant", "beetle", "cultist", "slime"]},
    "sfx_hit_soft": 0.055, "sfx_hit_hard": 0.070, "sfx_hit_magic": 0.060,
```

- [ ] **Step 6: 生成 + import + 自查**

```powershell
python tools/gen_audio.py
python tools/gen_audio.py --verify
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
```
Expected: `--verify` 每行都係 `ok`,結尾 `0 with problems`,exit 0

- [ ] **Step 7: 跑測試,確認佢綠**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: `AUDIO PASS fails=0`,包括 `G 註冊咗嘅 13 個音全部載到`

- [ ] **Step 8: Commit**

```bash
git add tools/gen_audio.py scripts/autoload/Audio.gd test/AudioTest.gd assets/generated_audio/
git commit -m "$(cat <<'EOF'
Give every monster family its own death sound, and a way to check the set

Ten families shared no death sound at all, which meant the one moment the
player most needs to identify what just died was silent. Each family now has
one built from its own material — dry bone rattle, wet slime burst, crumbling
stone, a ghost that fades IN and out with no attack at all — plus three
hit sounds picked by how armoured the target is rather than by damage type,
because "is this thing hard" is what the player is actually asking.

gen_audio.py --verify reports duration, peak, RMS, clipped samples and loop
seam per file and exits non-zero on a problem, so "sounds fine" stops being
a claim nobody can re-check. Audio.registered_sounds() feeds a new AudioTest
case: any table pointing at a name with no file fails the suite instead of
going quietly silent in game.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 魔法音效(15 個)

**Files:**
- Modify: `tools/gen_audio.py`, `scripts/autoload/Audio.gd`

**Interfaces:**
- Consumes: Task 1 嘅 `registered_sounds()`
- Produces: `Audio.SPELL_SOUND: Dictionary` — spell `mech` String → 音名;`Audio.play_spell(mech: String) -> void`

- [ ] **Step 1: 加註冊表**

`Audio.gd`,`HIT_SOUND` 之後:

```gdscript
## 15 個魔法各有自己嘅聲。呢度冇用 archetype + pitch(塔嗰邊用嘅做法):
## 塔係一路重複咁響,pitch 已經夠分;魔法一場得幾次,每次都係一個決定,
## 所以每個都值一個自己嘅聲。
const SPELL_SOUND := {
	"meteor": "sfx_spell_meteor", "stormbolt": "sfx_spell_stormbolt",
	"freezenova": "sfx_spell_freezenova", "miasma": "sfx_spell_miasma",
	"summon": "sfx_spell_summon", "midas": "sfx_spell_midas",
	"timewarp": "sfx_spell_timewarp", "warcry": "sfx_spell_warcry",
	"barrier": "sfx_spell_barrier", "tornado": "sfx_spell_tornado",
	"quake": "sfx_spell_quake", "firewall": "sfx_spell_firewall",
	"smite": "sfx_spell_smite", "emp": "sfx_spell_emp",
	"blackhole": "sfx_spell_blackhole",
}

func play_spell(mech: String) -> void:
	var n: String = String(SPELL_SOUND.get(mech, ""))
	if n != "":
		play(n)
```

同埋喺 `registered_sounds()` 加:

```gdscript
	for n in SPELL_SOUND.values():
		out[String(n)] = true
```

- [ ] **Step 2: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: FAIL — `missing: [sfx_spell_barrier, sfx_spell_blackhole, ...]` 15 個

- [ ] **Step 3: 寫 15 個合成函數**

大魔法(meteor / blackhole / freezenova / quake)0.5–0.8 秒、有下沉低頻份量;
細魔法 <0.25 秒。全部加落 `SOUNDS`。

| 函數 | 時長 | 合成配方 |
|---|---|---|
| `sfx_spell_meteor` | 0.75 | 呼嘯 `lowpass(noise(.35), 1500) * np.linspace(0,1,int(SR*.35))**2` → `seq` 撞擊 `sine(sweep(180, 30, .40), .40) * perc(.40, 3.5)` + `lowpass(noise(.40), 600) * perc(.40, 3)` |
| `sfx_spell_stormbolt` | 0.30 | 7 下 `square(f_jitter, .035, duty=.125) * perc(.035, 10)`(`f` 用 `_rng.uniform(900, 2800)` 每下換)錯開 0.035s,`bits=5` |
| `sfx_spell_freezenova` | 0.60 | `triangle(sweep(2600, 900, d), d) * perc(d, 3)` + `triangle(sweep(5200, 1800, d), d) * perc(d, 5) * .35` + 開頭 `lowpass(noise(.10), 800) * perc(.10, 6) * .6` 爆開 |
| `sfx_spell_miasma` | 0.42 | `lowpass(noise(d), 900) - lowpass(noise(d), 200)` 帶通嘶聲 `* np.sin(np.linspace(0, np.pi, ...))`,加 `saw(sweep(90, 60, d), d) * perc(d, 3) * .4` 濁低頻 |
| `sfx_spell_summon` | 0.34 | 上行三音 `seq(*[square(note(57+k), .10, duty=.25) * perc(.10, 7) for k in (0, 4, 7)])`,加 `highpass(noise(.34), 4000) * perc(.34, 5) * .2` 魔法塵 |
| `sfx_spell_midas` | 0.30 | 金幣堆:5 下 `triangle(note(84 + _rng.integers(-3, 4)), .05) * perc(.05, 12)` 隨機錯開,`bits=7` 保留亮度 |
| `sfx_spell_timewarp` | 0.44 | 下沉:`saw(sweep(700, 180, d), d) * adsr(d, .02, .08, .6, .14)`,`* (1 + .15*sin(2π*3*t(d)))` 慢抖 |
| `sfx_spell_warcry` | 0.36 | `square(sweep(300, 460, d, "lin"), d, duty=.5) * adsr(d, .01, .05, .8, .10)` 上揚 + `lowpass(noise(d), 1200) * perc(d, 4) * .35` 人聲感 |
| `sfx_spell_barrier` | 0.40 | `sine(sweep(300, 620, .18), .18) * perc(.18, 5)` 升起 → `seq` `triangle(620, .22) * adsr(.22, .01, .03, .85, .08)` 穩定嗡鳴 |
| `sfx_spell_tornado` | 0.40 | `lowpass(noise(d), 2400) - lowpass(noise(d), 500)`,乘一個 `0.5 + 0.5*sin(2π*9*t(d))` 旋轉調變 |
| `sfx_spell_quake` | 0.70 | `sine(sweep(70, 26, d), d) * perc(d, 2.5)` 主體 + `lowpass(noise(d), 400) * perc(d, 2.2) * .8` 隆隆 + 3 下 `perc` 碎石點綴 |
| `sfx_spell_firewall` | 0.44 | `lowpass(noise(d), 2000) - lowpass(noise(d), 300)` 乘 `np.linspace(0,1,...)**0.6`(由左燒到右嘅感覺)+ `triangle(sweep(160, 110, d), d) * perc(d, 3) * .35` |
| `sfx_spell_smite` | 0.34 | 神聖:`saw(note(81), .06) * perc(.06, 9)` 前擊 → `seq` `triangle(note(69), .28) * adsr(.28, .005, .05, .7, .12)` + 五度 `triangle(note(76), .28) * ... * .5` |
| `sfx_spell_emp` | 0.28 | `square(sweep(2200, 120, d), d, duty=.125) * perc(d, 5)` 急降 + `highpass(noise(.06), 3500) * perc(.06, 14) * .5`,`bits=4` 最粗糙 |
| `sfx_spell_blackhole` | 0.80 | 吸入:`saw(sweep(120, 900, .55), .55) * np.linspace(0,1,int(SR*.55))**1.5` → `seq` `sine(sweep(900, 40, .25), .25) * perc(.25, 4)` 塌縮,全程加 `lowpass(noise(d), 300) * .3` |

`LOUDNESS` 加:大魔法 0.13,細魔法 0.10。

```python
    # 大魔法要有份量,但仲係要坐喺 jingle 之下
    "sfx_spell_meteor": 0.13, "sfx_spell_quake": 0.13,
    "sfx_spell_blackhole": 0.13, "sfx_spell_freezenova": 0.12,
```

- [ ] **Step 4: 生成 + import + 自查 + 跑測試**

```powershell
python tools/gen_audio.py
python tools/gen_audio.py --verify
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: `--verify` 0 problems;`AUDIO PASS fails=0`,`G 註冊咗嘅 28 個音全部載到`

- [ ] **Step 5: Commit**

```bash
git add tools/gen_audio.py scripts/autoload/Audio.gd assets/generated_audio/
git commit -m "$(cat <<'EOF'
Give each of the fifteen spells its own sound rather than a shared archetype

Towers reuse six archetypes separated by pitch, and that is right for them:
they fire constantly, so pitch is enough to tell a sniper from a gatling and
twenty near-identical samples would be twenty things to keep in tune. A spell
is different — it fires a few times a match and each cast is a decision, so
each one gets a sound of its own.

The four big ones (meteor, black hole, freeze nova, earthquake) run 0.6-0.8s
with real low-end weight; everything else stays under 0.25s so casting in a
busy field does not smear.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 塔音效補完(8 個)

**Files:**
- Modify: `tools/gen_audio.py`, `scripts/autoload/Audio.gd`

**Interfaces:**
- Produces: `TOWER_SOUND` 擴充到覆蓋全部 20 座塔;新音名 `sfx_atk_poison` / `_boomerang` / `_thorn` / `_magnet` / `_teleport` / `sfx_tower_barracks` / `sfx_aura_curse` / `sfx_field_slow`

- [ ] **Step 1: 改 `TOWER_SOUND`**

將 `Audio.gd` 現有嘅 `TOWER_SOUND` 全表換成:

```gdscript
## 20 座塔嘅攻擊聲。原本 17 座共用六個 archetype 靠 pitch 分,而 barracks /
## curse / slowfield 三座完全無聲 —— 因為佢哋冇「一發」可以對齊。
##
## 而家:仲有 archetype 嘅係聲音上真係同一件事嘅塔(箭/機槍/狙擊 = 同一個
## thwip 嘅輕重),而毒/迴旋鏢/荊棘/磁力/傳送呢五座各自有一個聽落唔似射擊嘅
## 機制,借 pitch 只會令佢哋聽落似「走音嘅箭塔」,所以改咗做專屬。
## 最後三座唔係攻擊,由各自嘅事件派聲,唔係逐幀。
const TOWER_SOUND := {
	"arrow":     ["sfx_atk_arrow", 1.00],
	"gatling":   ["sfx_atk_arrow", 1.35],
	"sniper":    ["sfx_atk_arrow", 0.72],
	"cannon":    ["sfx_atk_cannon", 1.00],
	"mortar":    ["sfx_atk_cannon", 0.82],
	"missile":   ["sfx_atk_cannon", 1.18],
	"lightning": ["sfx_atk_electric", 1.00],
	"fireball":  ["sfx_atk_fire", 1.00],
	"frost":     ["sfx_atk_frost", 1.00],
	"alchemy":   ["sfx_atk_frost", 1.45],
	"beam":      ["sfx_atk_beam", 1.00],
	"holy":      ["sfx_atk_beam", 1.30],
	# 專屬
	"poison":    ["sfx_atk_poison", 1.00],
	"boomerang": ["sfx_atk_boomerang", 1.00],
	"thorn":     ["sfx_atk_thorn", 1.00],
	"magnet":    ["sfx_atk_magnet", 1.00],
	"teleport":  ["sfx_atk_teleport", 1.00],
	# 唔係攻擊:出兵 / 光環刷新 / 力場脈衝,由各自事件派
	"barracks":  ["sfx_tower_barracks", 1.00],
	"curse":     ["sfx_aura_curse", 1.00],
	"slowfield": ["sfx_field_slow", 1.00],
}
```

- [ ] **Step 2: 跑測試,確認佢紅**

Expected: FAIL — `missing:` 8 個新名

- [ ] **Step 3: 寫 8 個合成函數**

| 函數 | 時長 | 合成配方 |
|---|---|---|
| `sfx_atk_poison` | 0.20 | 噴射:`lowpass(noise(d), 1400) - lowpass(noise(d), 350)` 乘 `perc(d, 5)`,加 `sine(sweep(200, 130, d), d) * perc(d, 6) * .35` 黏稠低頻,`bits=6` |
| `sfx_atk_boomerang` | 0.26 | 旋轉:`triangle(sweep(600, 900, d, "lin"), d)` 乘 `(0.45 + 0.55*np.sin(2π*14*t(d)))` 再乘 `perc(d, 3.5)` —— 旋轉調變係佢同箭塔嘅分別 |
| `sfx_atk_thorn` | 0.14 | 尖刺彈出:`square(sweep(1500, 2200, d, "lin"), d, duty=.125) * perc(d, 12)` + `highpass(noise(.05), 4000) * perc(.05, 15) * .5` |
| `sfx_atk_magnet` | 0.28 | 脈衝:`sine(sweep(90, 240, d, "lin"), d) * perc(d, 4)` 上行 + `square(180, d, duty=.5) * perc(d, 5) * .35`,深、無高頻 |
| `sfx_atk_teleport` | 0.18 | `square(sweep(400, 3000, d), d, duty=.125) * perc(d, 6)` 急升 + 反向 `square(sweep(3000, 400, d), d, duty=.125) * perc(d, 8) * .4` 疊上去,`bits=4` |
| `sfx_tower_barracks` | 0.30 | 出兵號角:`square(note(57), .12, duty=.25) * adsr(.12, .01, .03, .8, .04)` → `seq` `square(note(64), .18, duty=.25) * adsr(.18, .01, .03, .7, .06)` |
| `sfx_aura_curse` | 0.50 | 低沉環境:`saw(sweep(110, 88, d), d) * adsr(d, .12, .10, .55, .20)` + `triangle(note(45), d) * adsr(d, .12, .1, .5, .2) * .4`,慢起慢落,唔會突兀 |
| `sfx_field_slow` | 0.44 | 力場:`triangle(sweep(340, 250, d), d) * adsr(d, .08, .08, .6, .16)` 乘 `(1 + .18*np.sin(2π*5*t(d)))` 呼吸感 |

`LOUDNESS` 加:`sfx_aura_curse` 同 `sfx_field_slow` 坐低到 **0.06** —— 佢哋係環境聲,唔係事件聲,唔應該同攻擊搶。

- [ ] **Step 4: 生成 + import + 自查 + 跑測試**

Expected: `--verify` 0 problems;`G 註冊咗嘅 36 個音全部載到`

- [ ] **Step 5: Commit**

```bash
git add tools/gen_audio.py scripts/autoload/Audio.gd assets/generated_audio/
git commit -m "$(cat <<'EOF'
Stop three towers being silent, and stop five sounding like a detuned bow

兵營 / 詛咒 / 緩速力場 had no sound at all because none of them has a discrete
shot to sync one to. They get sounds tied to what they actually do — a two-note
muster call on spawn, a slow low drone when the curse aura refreshes, a
breathing field tone on the slow pulse — and the two ambient ones sit at RMS
0.06 so they stay underneath the shooting rather than competing with it.

毒 / 迴旋鏢 / 荊棘 / 磁力 / 傳送 were borrowing an archetype at a shifted
pitch. That works when the mechanic is the same thing at a different weight
(arrow / gatling / sniper), but none of these five is a bow, and a pitched-down
bow just reads as an out-of-tune arrow tower. Each now has its own: a wet
spray, a rotation-modulated whirr, a spike snap, a deep pulse, a rising and
falling pair for the teleport.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 系統音效 + jingle(15 個)

**Files:**
- Modify: `tools/gen_audio.py`, `scripts/autoload/Audio.gd`

**Interfaces:**
- Produces: `Audio.SYSTEM_SOUNDS: Array` — 15 個系統音名,俾 `registered_sounds()` 收錄

- [ ] **Step 1: 加註冊表**

```gdscript
## 系統音。金幣同魔晶嘅音色一定要分得開 —— 佢哋喺畫面上係兩種顏色兩個 icon,
## 聽落一樣就等於將呢個區分喺聽覺上撤銷咗。金幣 = 金屬、短、亮;
## 魔晶 = 玻璃、長尾、有 shimmer。
const SYSTEM_SOUNDS := [
	"sfx_gold_pop", "sfx_gold_bank", "sfx_crystal_gain",
	"sfx_upgrade", "sfx_unlock",
	"sfx_boss_warning", "sfx_base_danger",
	"jingle_win", "jingle_lose", "jingle_first_clear",
	"sfx_teleport_hit", "sfx_knockback", "sfx_summon_circle",
	"sfx_place_tower", "sfx_sell_tower",
]
```

`registered_sounds()` 加:

```gdscript
	for n in SYSTEM_SOUNDS:
		out[String(n)] = true
```

- [ ] **Step 2: 跑測試,確認佢紅**

Expected: FAIL — `missing:` 15 個

- [ ] **Step 3: 寫 15 個合成函數**

| 函數 | 時長 | 合成配方 |
|---|---|---|
| `sfx_gold_pop` | 0.08 | 金屬短亮:`triangle(note(88), d) * perc(d, 13)` + `triangle(note(95), d) * perc(d, 16) * .5`,`bits=7` |
| `sfx_gold_bank` | 0.16 | 上行兩粒 `seq(triangle(note(84), .07)*perc(.07,12), triangle(note(91), .09)*perc(.09,11))`,`bits=7` |
| `sfx_crystal_gain` | 0.38 | 玻璃長尾:`triangle(note(88), d) * perc(d, 3.5)` + `triangle(note(95), d) * perc(d, 4.5) * .55` + `triangle(note(100), d) * perc(d, 6) * .3`,尾長,**冇 noise**(noise 會令佢聽落似金屬) |
| `sfx_upgrade` | 0.34 | 上行三粒大調 `seq` `square(note(n), .10, duty=.25)*adsr(.10,.005,.03,.7,.03)` for n in (72, 76, 79) |
| `sfx_unlock` | 0.50 | 同上但四粒 (72, 76, 79, 84),最後一粒 0.22 秒 + `triangle(note(84), .22)*perc(.22,4)*.5` 疊亮 |
| `sfx_boss_warning` | 0.70 | 警號:兩下 `square(sweep(440, 330, .28, "lin"), .28, duty=.5) * adsr(.28,.02,.04,.85,.06)` 中間隔 0.07 秒靜音,加 `saw(note(33), .70)*adsr(.70,.05,.1,.5,.2)*.4` 低頻威脅 |
| `sfx_base_danger` | 0.44 | 心跳兩下 `sine(sweep(90, 45, .14), .14) * perc(.14, 6)` 隔 0.16 秒,加 `lowpass(noise(.44), 300)*perc(.44,3)*.3` |
| `jingle_win` | 1.30 | 大調上行 5 粒 (69, 73, 76, 81, 88),每粒 `square(note(n), .18, duty=.25)*adsr(.18,.01,.04,.7,.05)`,最後一粒 0.5 秒 + 三度五度和聲 `triangle` |
| `jingle_lose` | 1.10 | 小調下行 4 粒 (69, 65, 62, 57),每粒 `square(note(n), .24, duty=.5)*adsr(.24,.02,.05,.6,.08)`,最後加 `saw(note(45), .40)*perc(.40,3)*.5` |
| `jingle_first_clear` | 1.60 | `jingle_win` 嘅動機再上行一個八度 + `highpass(noise(1.6), 5000)*perc(1.6,2)*.15` 閃粉,末尾三音琶音 (88, 93, 96) |
| `sfx_teleport_hit` | 0.20 | `square(sweep(1800, 500, d), d, duty=.125)*perc(d,7)` + 反向 `square(sweep(500,1800,d), d, duty=.125)*perc(d,9)*.4`,`bits=4` |
| `sfx_knockback` | 0.18 | `lowpass(noise(d), 1000)*perc(d,7)` + `sine(sweep(220, 90, d), d)*perc(d,6)*.7` 推力感 |
| `sfx_summon_circle` | 0.46 | 法陣:`triangle(sweep(300, 700, d), d)*adsr(d,.10,.08,.7,.16)` + `highpass(noise(d), 3500)*perc(d,3)*.25` |
| `sfx_place_tower` | 0.18 | 落地:`lowpass(noise(.07), 800)*perc(.07,10)` 塵 + `square(sweep(300, 180, d), d, duty=.5)*perc(d,7)*.8` 夯實 |
| `sfx_sell_tower` | 0.22 | `sfx_place_tower` 嘅倒轉句法:`square(sweep(180, 320, d), d, duty=.5)*perc(d,7)` + 兩粒金幣 `triangle(note(84), .05)*perc(.05,12)` |

`LOUDNESS` 加:

```python
    # jingle 同警號係「而家停低聽我講」嘅時刻,所以坐高
    "jingle_win": 0.16, "jingle_lose": 0.16, "jingle_first_clear": 0.18,
    "sfx_boss_warning": 0.17, "sfx_base_danger": 0.15,
    # 金幣一秒可以響好多次
    "sfx_gold_pop": 0.055, "sfx_gold_bank": 0.09, "sfx_crystal_gain": 0.11,
```

- [ ] **Step 4: 生成 + import + 自查 + 跑測試**

Expected: `--verify` 0 problems;`G 註冊咗嘅 51 個音全部載到`

- [ ] **Step 5: Commit**

```bash
git add tools/gen_audio.py scripts/autoload/Audio.gd assets/generated_audio/
git commit -m "$(cat <<'EOF'
Add the fifteen system sounds, with gold and crystals deliberately unalike

The two currencies are colour-coded and icon-coded everywhere on screen, and
letting them share a "you got money" blip would quietly undo that distinction
in the one channel the player is using while looking at the battlefield
instead of the HUD. Gold is metallic, short and bright; 魔晶 is glass with a
long shimmering tail and no noise component at all — noise is what was making
early drafts of it read as metal.

Also here: win / lose / first-clear jingles, the boss klaxon, the base-in-
danger heartbeat, and the small physical sounds (place, sell, knockback,
teleport, summoning circle) that had nothing.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: 主選單 / boss BGM + 小節對齊交接

**Files:**
- Modify: `tools/gen_audio.py`, `scripts/autoload/Audio.gd`, `test/AudioTest.gd`

**Interfaces:**
- Produces:
  - `Audio.BGM_META: Dictionary` — 音名 → `{"bpm": float, "beats": int, "bars": int}`
  - `Audio.bar_seconds(meta: Dictionary) -> float` (static)
  - `Audio.time_to_bar(pos: float, meta: Dictionary) -> float` (static)
  - `Audio.queue_bgm(sound: String) -> void`

- [ ] **Step 1: 寫失敗嘅測試 —— 小節數學係純函數,headless 都測到**

`AudioTest.gd`,`_ready()` 入面 `await _case_registry()` 之後加 `await _case_bar_align()`,並加:

```gdscript
## 小節對齊嘅數學。呢個 case 存在嘅原因:真正嘅交接要有一個會推進嘅音訊驅動先
## 觀察到(headless 個 dummy 唔會),所以決定「幾時切」嗰條數獨立成純函數,
## 喺任何環境都答得到。切換本身嘅正確性 = 呢條數 + 一句 if,冇第三樣嘢。
func _case_bar_align() -> void:
	var meta := {"bpm": 132.0, "beats": 4, "bars": 8}
	var bar: float = Audio.bar_seconds(meta)
	_near("A 一個小節 = 60/132*4", bar, 1.8181818, 0.0005)
	_near("A 啱啱踩正線 -> 唔使等", Audio.time_to_bar(0.0, meta), 0.0, 0.0005)
	_near("A 小節中間 -> 等返差嗰段", Audio.time_to_bar(1.0, meta), bar - 1.0, 0.0005)
	_near("A 跨過一個小節之後照計", Audio.time_to_bar(bar + 0.5, meta), bar - 0.5, 0.0005)
	# 呢個係最重要嗰個:啱啱過線嘅位置絕對唔可以返一個完整小節,否則 boss 曲會
	# 白等成個小節先入,而個 bug 喺遊戲入面只會顯示為「有時慢咗」
	_ok("A 啱啱過線唔會白等成個小節",
		Audio.time_to_bar(bar * 2.0, meta) < 0.01,
		"got %.4f, want ~0" % Audio.time_to_bar(bar * 2.0, meta))
	# battle 同 boss 必須同 BPM,唔係「無縫」就係空話
	var b1: Dictionary = Audio.BGM_META.get("bgm_battle", {})
	var b2: Dictionary = Audio.BGM_META.get("bgm_boss", {})
	_ok("A battle / boss 同 BPM",
		not b1.is_empty() and not b2.is_empty()
		and is_equal_approx(float(b1.get("bpm", 0.0)), float(b2.get("bpm", -1.0))),
		"battle=%s boss=%s" % [str(b1), str(b2)])
	# 排隊之後未到線之前唔可以即刻換走
	Audio.play_bgm("bgm_battle")
	Audio.queue_bgm("bgm_boss")
	_ok("A 排咗隊但未切", Audio._bgm_pending == "bgm_boss" and Audio._bgm_name == "bgm_battle",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])
	Audio.stop_bgm()
	Audio._bgm_pending = ""
```

- [ ] **Step 2: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: FAIL — `Invalid call. Nonexistent function 'bar_seconds' in base 'Node (Audio.gd)'`

- [ ] **Step 3: 喺 `Audio.gd` 實作**

`play_bgm` 之上加:

```gdscript
## 每首 BGM 嘅節奏,用嚟計小節線。battle 同 boss 一定要同 BPM 同 key,
## 唔係咁「無縫」就淨係得個講字。
const BGM_META := {
	"bgm_menu":   {"bpm": 90.0,  "beats": 4, "bars": 8},
	"bgm_battle": {"bpm": 132.0, "beats": 4, "bars": 8},
	"bgm_boss":   {"bpm": 132.0, "beats": 4, "bars": 8},
}
## 幾近就當踩正線。一幀喺 60fps 係 0.0167 秒,所以呢個窗要闊過一幀,
## 唔係就會有時啱啱跳過條線,要等多成個小節先切到。
const BAR_SNAP := 0.05

var _bgm_pending: String = ""

static func bar_seconds(meta: Dictionary) -> float:
	return 60.0 / maxf(1.0, float(meta.get("bpm", 120.0))) * float(meta.get("beats", 4))

## 由播放位置 `pos` 去到下一條小節線仲要幾耐。啱啱踩正線返 0。
static func time_to_bar(pos: float, meta: Dictionary) -> float:
	var bar: float = bar_seconds(meta)
	if bar <= 0.0:
		return 0.0
	var into: float = fposmod(pos, bar)
	return 0.0 if into < 0.0005 or bar - into < 0.0005 else bar - into

## 排隊換 BGM,等下一條小節線先真係切。
##
## 即刻切試過,唔得:切喺小節中間會斷拍,而斷拍係聽得出嘅 —— 玩家唔會諗到
## 「換咗歌」,只會覺得「卡咗一下」。等最多一個小節(132bpm 之下 1.82 秒)
## 換返一個真係接得上嘅過渡,係抵嘅。
func queue_bgm(sound: String) -> void:
	if _bgm_name == sound and _bgm.playing:
		_bgm_pending = ""
		return
	_bgm_pending = sound

func _process(_delta: float) -> void:
	if _bgm_pending == "":
		return
	# 冇嘢喺度播 = 冇小節線可以等
	if not _bgm.playing:
		_commit_pending()
		return
	var meta: Dictionary = BGM_META.get(_bgm_name, {})
	if meta.is_empty():
		_commit_pending()
		return
	if time_to_bar(_bgm.get_playback_position(), meta) <= BAR_SNAP:
		_commit_pending()

func _commit_pending() -> void:
	var n: String = _bgm_pending
	_bgm_pending = ""
	play_bgm(n)
```

同埋喺 `stop_bgm()` 入面加 `_bgm_pending = ""`(停音樂之後唔應該仲有嘢排住隊)。

- [ ] **Step 4: 寫兩首 BGM**

`gen_audio.py`,`bgm_battle()` 之後:

```python
def bgm_menu():
    """Main menu: unhurried, major key, nothing urgent happening.

    Deliberately NOT the battle theme slowed down — the menu is where the
    player reads numbers and decides what to buy, and a driving loop makes
    that feel like something they are late for.
    """
    lead = [(0, 0, 1.0), (1, 4, 0.5), (1.5, 7, 0.5), (2, 4, 1.0), (3, 2, 1.0)]
    return _bgm_track(root=60, prog=[0, 5, 3, 7], bars=8, bpm=90,
                      lead_pattern=lead, duty=0.5) * 0.7


def bgm_boss():
    """Boss theme. SAME bpm and SAME root as bgm_battle on purpose — the
    handoff is timed to a bar line, and two tracks in different keys or tempos
    would still read as a cut no matter how well the moment was chosen.

    What makes it the boss version instead: a darker progression that leans on
    the flat sixth, the lead an octave down for weight, and a thinner duty
    cycle so it cuts through a field that is by now very busy.
    """
    lead = [(0, 0, 0.5), (0.5, 0, 0.5), (1, 8, 1.0), (2, 7, 0.5),
            (2.5, 5, 0.5), (3, 3, 1.0)]
    return _bgm_track(root=57, prog=[0, 8, 5, 3], bars=8, bpm=132,
                      lead_pattern=lead, duty=0.125) * 0.85
```

加落 `SOUNDS`,`LOUDNESS` 加 `"bgm_menu": 0.075, "bgm_boss": 0.09`。

**核對**:`bars=8, bpm=132, beats=4` → 8 × 4 × 60/132 = 14.545 秒,即 `bgm_battle` 同
`bgm_boss` 長度一模一樣,兩首嘅小節線永遠對得上。

- [ ] **Step 5: 生成 + import + 自查 + 跑測試**

```powershell
python tools/gen_audio.py
python tools/gen_audio.py --verify
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioTest.tscn
```
Expected: `--verify` 0 problems(包括兩首 BGM 嘅 `seam` < 0.01);`AUDIO PASS fails=0`

- [ ] **Step 6: 開窗跑多次,答返 headless 答唔到嗰條**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --path . res://test/AudioTest.tscn --log-file "$PWD\audio_windowed.log"
```
Expected: log 入面 `T 時間縮放` 嗰組唔再 SKIP,`AUDIO PASS fails=0 skips=0`。
(Windows 上 GUI exe 會脫離 console,所以一定要 `--log-file`,睇 log 而唔係睇 stdout。)

- [ ] **Step 7: Commit**

```bash
git add tools/gen_audio.py scripts/autoload/Audio.gd test/AudioTest.gd assets/generated_audio/
git commit -m "$(cat <<'EOF'
Hand off from battle to boss music on a bar line instead of cutting

Swapping the stream the instant the boss lands breaks the beat mid-bar, and a
broken beat does not read to a player as "the music changed" — it reads as
"the game stuttered". queue_bgm() now parks the request and Audio watches
get_playback_position() until the next bar line, at most 1.82s away at 132bpm.

The two tracks share bpm, bar count and root (A minor, 8 bars, 14.545s each)
so their bar lines coincide by construction; the boss version differs by a
darker progression, a lower lead and a thinner duty cycle rather than by tempo.

The decision of WHEN to switch is a pure function (time_to_bar) so it can be
tested headless, where no audio driver advances playback. Its sharpest case is
a position that has just crossed a line: returning a full bar there would make
the boss music arrive late, and in game that bug would look like nothing at all.

Also adds bgm_menu — unhurried and in a major key, not the battle loop slowed
down, because the menu is where the player reads numbers and decides.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: 接駁全部遊戲事件

**Files:**
- Modify: `scripts/battle/Battle.gd`, `scripts/battle/Monster.gd`, `scripts/battle/Spells.gd`, `scripts/autoload/Meta.gd`, `scripts/ui/MainMenu.gd`
- Create: `test/AudioHookTest.gd`, `test/AudioHookTest.tscn`

**Interfaces:**
- Consumes: `Audio.play_death/play_hit/play_spell/play/play_bgm/queue_bgm`(Task 1-5)
- Produces: `Audio.debug_log: Array` + `Audio.debug_capture: bool` — 開咗之後每個 `play()` / `play_bgm()` 嘅名都記低,俾測試觀察

- [ ] **Step 1: 喺 `Audio.gd` 加觀察窗**

```gdscript
## 測試用嘅觀察窗。冇呢個,「呢個事件有冇派聲」就只可以靠人手開音箱聽,
## 而咁樣嘅嘢冇人會喺每次改動之後重做一次。預設關,零成本。
var debug_capture: bool = false
var debug_log: Array = []
```

喺 `play()` 入面,`var s := stream(sound)` 之前(即係連「檔案唔存在」都要記低,
因為「派咗一個唔存在嘅名」正正就係要捉嘅 bug)加:

```gdscript
	if debug_capture:
		debug_log.append(sound)
```

喺 `play_bgm()` 嘅 `var s := stream(sound)` 之前加同樣三行。

- [ ] **Step 2: 寫失敗嘅測試**

`test/AudioHookTest.gd`:

```gdscript
extends Node
## 「呢個事件到底有冇出聲」嘅回歸測試。
##
## 音效最典型嘅壞法唔係響錯,係靜咗 —— 一個 typo 嘅音名、一個冇接駁嘅事件,
## 喺遊戲入面完全冇症狀,冇人會發現。所以呢度跑一場真戰鬥,開住 Audio 嘅
## 觀察窗,然後問:呢啲名有冇出現過。
##
##   H1  怪物死 / 受擊
##   H2  起塔 / 賣塔 / 金幣
##   H3  魔法
##   H4  boss 出場 -> 警號 + boss 曲排隊
##   H5  勝 / 敗 jingle
##
## 唔需要真嘅音訊驅動:呢度問嘅係「派唔派」,唔係「聽落點」。

var fails := 0
var _tree: SceneTree
var _save_bytes := PackedByteArray()
var _had_save := false

const DT := 1.0 / 30.0

func _ready() -> void:
	_tree = get_tree()
	process_mode = Node.PROCESS_MODE_ALWAYS
	_backup_save()
	Flow.nav_enabled = false
	_tree.paused = true
	seed(0xA0D10)
	await _case_battle_sounds()
	await _case_end_jingles()
	_tree.paused = false
	Flow.nav_enabled = true
	_restore_save()
	Meta.load_game()
	Audio.debug_capture = false
	Audio.debug_log.clear()
	print("AUDIOHOOK %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	_tree.quit(0 if fails == 0 else 1)

func _case_battle_sounds() -> void:
	Meta.reset_save()
	Meta.unlocked_towers = range(1, 21)
	Meta.unlocked_spells = range(1, 16)
	var b = await _start(1)
	b.gold = 99999
	b.boss_time = 6.0            # 唔使等成 60 秒先見到 boss
	Audio.debug_capture = true
	Audio.debug_log.clear()

	# 起塔 -> 起塔聲
	var spot: Vector2 = _free_spot(b)
	_ok("H2 揾到空地", spot != Vector2.INF, "no legal build spot on level 1")
	if spot != Vector2.INF:
		b.place_tower(1, spot)
		_heard("H2 起塔", "sfx_place_tower")

	# 跑到 boss 出場之後,一路殺緊怪
	var t := 0.0
	while t < 20.0 and not b.ended:
		_step(b, DT)
		t += DT

	_ok("H1 有怪死過", b.kills > 0, "kills=%d — 呢個 case 冇嘢可以觀察" % b.kills)
	_heard_any("H1 死亡聲", Audio.DEATH_SOUND.values())
	_heard_any("H1 受擊聲", Audio.HIT_SOUND.values())
	_heard("H2 金幣", "sfx_gold_pop")
	_ok("H4 boss 出咗場", b.boss_spawned, "boss never spawned in 20s")
	_heard("H4 boss 警號", "sfx_boss_warning")
	_ok("H4 boss 曲排咗隊或者已經切咗",
		Audio._bgm_pending == "bgm_boss" or Audio._bgm_name == "bgm_boss",
		"pending=%s now=%s" % [Audio._bgm_pending, Audio._bgm_name])

	# 每個魔法各施放一次
	Audio.debug_log.clear()
	for sp in GameData.SPELLS:
		Spells.cast(b, int(sp.id), Vector2(540, 900))
	for sp in GameData.SPELLS:
		_heard("H3 魔法 %s" % String(sp.mech), String(Audio.SPELL_SOUND[sp.mech]))

	# 賣塔
	Audio.debug_log.clear()
	if b.towers.size() > 0:
		b.sell_tower(b.towers[0])
		_heard("H2 賣塔", "sfx_sell_tower")
	await _end(b)

func _case_end_jingles() -> void:
	# 敗:直接叫 _lose(),唔使真係捱到失守
	Meta.reset_save()
	var b = await _start(1)
	Audio.debug_capture = true
	Audio.debug_log.clear()
	b._lose()
	_heard("H5 敗 jingle", "jingle_lose")
	await _end(b)

	# 勝 + 首通:第 1 關未通過,所以一次過驗到兩個
	Meta.reset_save()
	var b2 = await _start(1)
	Audio.debug_log.clear()
	b2._win()
	_heard("H5 勝 jingle", "jingle_win")
	_heard("H5 首通 jingle", "jingle_first_clear")
	await _end(b2)

# ---------------------------------------------------------------------------
func _heard(label: String, name: String) -> void:
	_ok(label, Audio.debug_log.has(name),
		"'%s' 冇派過。派過嘅:%s" % [name, str(Audio.debug_log)])

func _heard_any(label: String, names) -> void:
	for n in names:
		if Audio.debug_log.has(String(n)):
			_ok(label, true, "")
			return
	_ok(label, false, "冇一個派過:%s" % str(names))

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("AUDIOHOOK ok   %s" % label)
	else:
		fails += 1
		print("AUDIOHOOK FAIL %s — %s" % [label, detail])

func _free_spot(b) -> Vector2:
	for gy in range(3, 21):
		for gx in range(1, 15):
			var p: Vector2 = b.snap(Vector2(gx * 74.0, gy * 74.0))
			if b.can_place(p):
				return p
	return Vector2.INF

func _start(level: int):
	Flow.selected_level = level
	Flow.last_result = {}
	var b = load("res://scenes/Battle.tscn").instantiate()
	b.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(b)
	await get_tree().process_frame
	return b

func _end(b) -> void:
	b.queue_free()
	await get_tree().process_frame
	get_tree().paused = true

func _step(b, dt: float) -> void:
	b._process(dt)
	for root in [b.towers_root, b.monsters_root, b.proj_root, b.fx_root]:
		for c in root.get_children():
			if c.process_mode != Node.PROCESS_MODE_DISABLED and c.has_method("_process"):
				c._process(dt)

func _backup_save() -> void:
	if FileAccess.file_exists(Meta.SAVE_PATH):
		_had_save = true
		_save_bytes = FileAccess.get_file_as_bytes(Meta.SAVE_PATH)

func _restore_save() -> void:
	if _had_save:
		var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_save_bytes)
		f.close()
	else:
		var d := DirAccess.open("user://")
		if d != null and d.file_exists("save.json"):
			d.remove("save.json")
```

`test/AudioHookTest.tscn` —— 照 `test/AudioTest.tscn` 嘅樣,一個 Node 掛住個 script:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://test/AudioHookTest.gd" id="1"]

[node name="AudioHookTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioHookTest.tscn
```
Expected: FAIL —— `H1 死亡聲`、`H2 起塔`、`H3 魔法 *`、`H4 boss 警號`、`H5 * jingle` 全部紅

- [ ] **Step 4: 接駁**

`scripts/battle/Monster.gd`,`take_hit()` 入面 `_flash()` 嗰行之後加:

```gdscript
	Audio.play_hit(armor, mres)
```

`Monster.gd` `_die()` 入面(揾到 `func _die(` 之後,喺佢通知 battle 之前)加:

```gdscript
	Audio.play_death(fam)
```

`scripts/battle/Battle.gd`:

- `add_gold()` 開頭加 `Audio.play("sfx_gold_pop")`(`Audio.play` 有 60ms dedup,
  所以 5x 之下一場金幣雨會變成一串節奏,唔會變一嚿噪音)
- `place_tower()` 成功嗰個 return 之前加 `Audio.play("sfx_place_tower")`
- `sell_tower()` 開頭加 `Audio.play("sfx_sell_tower")`
- `_spawn_boss()` 結尾加:
```gdscript
	Audio.play("sfx_boss_warning")
	Audio.queue_bgm("bgm_boss")
```
- `on_reach_base()` 入面扣完 `base_shield` 之後加:
```gdscript
	# 基地危險:只喺跌穿三成嗰一刻響一次,唔係每次漏怪都響 —— 後者喺守唔住嘅
	# 局入面會變成連續警報,而連續警報等於冇警報
	if base_shield > 0 and float(base_shield) / float(_base_shield_max) < 0.30 \
			and not _danger_played:
		_danger_played = true
		Audio.play("sfx_base_danger")
```
  同時喺 Battle 加兩個變數,並喺 `_ready()` / `_build_world()` 設定 `_base_shield_max`:
```gdscript
var _base_shield_max: int = 1
var _danger_played: bool = false
```
  (`_base_shield_max = base_shield` 要喺 `base_shield` 初始化之後嗰行設。)
- `_win()` 加:
```gdscript
	Audio.stop_bgm()
	Audio.play("jingle_win")
	if not Meta.is_cleared(level):
		Audio.play("jingle_first_clear")
```
  **注意順序**:`Meta.on_level_cleared(level)` 一叫就會令 `is_cleared` 變 true,
  所以呢兩行必須擺喺佢之前。睇實際碼決定插邊。
- `_lose()` 加 `Audio.stop_bgm()` + `Audio.play("jingle_lose")`

`scripts/battle/Spells.gd` `cast()` 入面,`match def.mech:` 之前加:

```gdscript
	Audio.play_spell(String(def.mech))
```

`scripts/autoload/Meta.gd`:
- `add_crystals()` 加 `Audio.play("sfx_crystal_gain")`
- `unlock_tower()` / `unlock_spell()` 成功 return 之前加 `Audio.play("sfx_unlock")`
- `buy_tower_upgrade()` / `buy_spell_upgrade()` 成功 return 之前加 `Audio.play("sfx_upgrade")`

`scripts/ui/MainMenu.gd` `_ready()` 開頭加 `Audio.play_bgm("bgm_menu")`。

`scripts/battle/Battle.gd` 現有嘅 `Audio.play_bgm("bgm_battle")` 保持唔變 —— 由主選單
入戰鬥係換場景,唔需要小節對齊。

- [ ] **Step 5: 跑測試,確認佢綠**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/AudioHookTest.tscn
```
Expected: `AUDIOHOOK PASS fails=0`

- [ ] **Step 6: 跑全部現有測試,確認冇整壞嘢**

```powershell
foreach ($t in @("AudioTest","RegressionTest","SpellFlowTest","BossSpawnTest","WinTest","LoseTest","SpeedScaleTest","BottomBarTest","EconTest","FlowTest","I18nTest","SceneCheck")) {
  Write-Host "--- $t ---"
  & "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . "res://test/$t.tscn"
  Write-Host "exit=$LASTEXITCODE"
}
```
Expected: 全部 `exit=0`

- [ ] **Step 7: Commit**

```bash
git add scripts/ test/AudioHookTest.gd test/AudioHookTest.tscn
git commit -m "$(cat <<'EOF'
Wire every sound to the event it belongs to, and test that they actually fire

Sixty-four sounds existed as files and six call sites used them. Deaths, hits,
spells, gold, crystals, upgrades, unlocks, the boss klaxon, the base-in-danger
heartbeat and all three jingles are now connected.

The interesting failure mode for audio is not "wrong sound" — it is silence: a
typo'd name or an event nobody hooked up produces no symptom in game and
nobody notices for months. AudioHookTest plays a real battle with a capture
flag on Audio and asserts each of those names was actually dispatched, so the
next refactor that quietly drops one fails the suite.

Two calls are deliberately conditional rather than per-event. The base-danger
heartbeat fires once when the shield first drops under 30%, because firing on
every leak turns a losing run into a continuous alarm, and a continuous alarm
is the same as none. The first-clear jingle is emitted before
Meta.on_level_cleared() runs, since that call is what makes is_cleared() true.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# PART 2 — 難度牆

## File Structure(Part 2)

| 檔 | 責任 |
|---|---|
| `scripts/autoload/GameData.gd` | 修改 — `WALLS` 表 + `wall_slot/wall_def/is_wall/wall_hint_key` + `level_config()` merge |
| `test/WallTest.gd` + `.tscn` | 新增 — 週期、成份、非牆關唔受影響、hint key 兩種語言都有 |
| `test/BalanceSim.gd` | 修改 — 加 `--walls` mode |
| `scripts/ui/LevelSelect.gd` | 修改 — 危險標記 |
| `scripts/ui/Fail.gd` | 修改 — 剋制提示 |
| `i18n/game.csv` | 修改 — 4 個新 key |
| `BALANCE_CHANGELOG.md` | 修改 — 續寫 |

---

### Task 7: `GameData.WALLS` + `level_config()` merge

**Files:**
- Modify: `scripts/autoload/GameData.gd`
- Create: `test/WallTest.gd`, `test/WallTest.tscn`

**Interfaces:**
- Produces:
  - `GameData.WALL_FIRST := 7`、`GameData.WALL_PERIOD := 20`、`GameData.WALL_OFFSETS := [0, 6, 11]`
  - `GameData.WALLS: Dictionary` — key 7/13/18 → `{"add_fams": Array, "spawn_min": float(可選), "hint": String}`
  - `GameData.wall_slot(n: int) -> int` — 返 7/13/18,唔係牆返 0
  - `GameData.wall_def(n: int) -> Dictionary`
  - `GameData.is_wall(n: int) -> bool`
  - `GameData.wall_hint_key(n: int) -> String`
  - `level_config(n)` 多咗一個 key:`"is_wall": bool`

- [ ] **Step 1: 寫失敗嘅測試**

`test/WallTest.gd`:

```gdscript
extends Node
## 難度牆嘅結構測試。
##
## 呢度唔量難唔難 —— 嗰個要跑模擬(BalanceSim --walls)。呢度量嘅係「牆擺得啱唔啱
## 位、成份有冇入到、冇牆嘅關有冇被污染」,即係一堆改完數值之後好易靜靜雞壞咗
## 而又冇人察覺嘅嘢。
##
##   W  週期 —— 7/13/18 之後每 20 關重複,中間嘅關唔可以係牆
##   C  成份 —— 每幅牆該加嘅家族真係入咗 cfg.families
##   N  非牆關 —— families / spawn_interval_min 同加牆之前一模一樣
##   H  提示 —— 每幅牆有 hint key,而且兩種語言都譯咗

var fails := 0

func _ready() -> void:
	_case_period()
	_case_content()
	_case_non_wall_untouched()
	_case_hints()
	print("WALL %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit(0 if fails == 0 else 1)

func _case_period() -> void:
	for n in [7, 13, 18, 27, 33, 38, 47, 53, 58]:
		_ok("W 第 %d 關係牆" % n, GameData.is_wall(n), "is_wall(%d) = false" % n)
	# 呢啲關必須唔係牆。特別留意 17 / 23 / 28 —— 如果週期寫成 10 而唔係 20,
	# 佢哋就會變牆,而 17 同 18 連住兩幅牆會令「牆與牆之間可以一次過」直接失效
	for n in [1, 6, 8, 12, 14, 17, 19, 20, 23, 26, 28, 34, 39]:
		_ok("W 第 %d 關唔係牆" % n, not GameData.is_wall(n), "is_wall(%d) = true" % n)
	# 週期性:第 n 關同第 n+20 關要係同一幅牆
	for n in [7, 13, 18]:
		_ok("W 第 %d 關同第 %d 關同一幅" % [n, n + 20],
			GameData.wall_slot(n) == GameData.wall_slot(n + 20),
			"slot %d vs %d" % [GameData.wall_slot(n), GameData.wall_slot(n + 20)])
	# 20 關入面剛剛好三幅
	var count := 0
	for n in range(1, 21):
		if GameData.is_wall(n):
			count += 1
	_ok("W 頭 20 關有 3 幅牆", count == 3, "got %d" % count)

func _case_content() -> void:
	# 第 7 關:對空 + 治療
	var c7: Dictionary = GameData.level_config(7)
	_ok("C7 標記做牆", bool(c7.get("is_wall", false)), "is_wall missing/false")
	_ok("C7 有飛行族 (bat)", "bat" in c7.families, "families=%s" % str(c7.families))
	_ok("C7 有治療族 (cultist)", "cultist" in c7.families, "families=%s" % str(c7.families))
	_ok("C7 boss 仲係樹妖", String(c7.boss_family) == "treant",
		"boss=%s" % String(c7.boss_family))

	# 第 13 關:分裂 + 密度
	var c13: Dictionary = GameData.level_config(13)
	_ok("C13 標記做牆", bool(c13.get("is_wall", false)), "is_wall missing/false")
	_ok("C13 有分裂族 (slime)", "slime" in c13.families, "families=%s" % str(c13.families))
	_ok("C13 spawn 間隔收窄", float(c13.spawn_interval_min) < 0.45,
		"spawn_interval_min=%.3f" % float(c13.spawn_interval_min))
	_ok("C13 boss 仲係骷髏", String(c13.boss_family) == "skeleton",
		"boss=%s" % String(c13.boss_family))

	# 第 18 關:護甲 + 魔抗同場
	var c18: Dictionary = GameData.level_config(18)
	_ok("C18 標記做牆", bool(c18.get("is_wall", false)), "is_wall missing/false")
	_ok("C18 有魔抗族 (ghost)", "ghost" in c18.families, "families=%s" % str(c18.families))
	var has_armor := false
	for f in c18.families:
		if float(GameData.FAMILIES[f].armor) >= 6.0:
			has_armor = true
	_ok("C18 同場有高甲族", has_armor, "families=%s 冇一個 armor>=6" % str(c18.families))
	_ok("C18 boss 仲係甲蟲", String(c18.boss_family) == "beetle",
		"boss=%s" % String(c18.boss_family))

	# 家族唔可以重複 —— 重複會令 _spawn_wave_monster 嘅隨機權重歪咗
	for n in [7, 13, 18]:
		var f: Array = GameData.level_config(n).families
		var uniq: Dictionary = {}
		for x in f:
			uniq[x] = true
		_ok("C%d 家族冇重複" % n, uniq.size() == f.size(), "families=%s" % str(f))

func _case_non_wall_untouched() -> void:
	## 非牆關要同「冇加過牆」一模一樣。程序生成嘅規則喺 level_config 入面寫死,
	## 所以呢度直接重算一次同一條式做對照 —— 如果 merge 寫漏咗個 if,呢個 case
	## 就會捉到「所有關都加咗 bat」呢類最貴嘅 bug。
	for n in [1, 5, 8, 12, 14, 19, 20]:
		var cfg: Dictionary = GameData.level_config(n)
		var base_i: int = (n - 1) % 10
		var want: Array = [GameData.FAMILY_ORDER[base_i],
			GameData.FAMILY_ORDER[(base_i + 3) % 10]]
		if n % 2 == 0:
			want.append(GameData.FAMILY_ORDER[(base_i + 6) % 10])
		_ok("N 第 %d 關家族冇被污染" % n, Array(cfg.families) == want,
			"got %s want %s" % [str(cfg.families), str(want)])
		_ok("N 第 %d 關 spawn 間隔冇被污染" % n,
			is_equal_approx(float(cfg.spawn_interval_min), 0.45),
			"got %.3f" % float(cfg.spawn_interval_min))
		_ok("N 第 %d 關冇標記做牆" % n, not bool(cfg.get("is_wall", false)), "is_wall true")

func _case_hints() -> void:
	for n in [7, 13, 18]:
		var key: String = GameData.wall_hint_key(n)
		_ok("H 第 %d 關有 hint key" % n, key != "", "empty hint key")
		if key == "":
			continue
		for loc in ["zh_TW", "en"]:
			TranslationServer.set_locale(loc)
			var txt: String = tr(key)
			_ok("H %s / %s 譯咗" % [key, loc], txt != key and txt.strip_edges() != "",
				"tr(%s) returned the key itself" % key)
	TranslationServer.set_locale(Meta.current_locale())
	_ok("H 非牆關冇 hint", GameData.wall_hint_key(5) == "",
		"level 5 returned '%s'" % GameData.wall_hint_key(5))

func _ok(label: String, cond: bool, detail: String) -> void:
	if cond:
		print("WALL ok   %s" % label)
	else:
		fails += 1
		print("WALL FAIL %s — %s" % [label, detail])
```

`test/WallTest.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://test/WallTest.gd" id="1"]

[node name="WallTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/WallTest.tscn
```
Expected: FAIL — `Invalid call. Nonexistent function 'is_wall' in base 'Node (GameData.gd)'`

- [ ] **Step 3: 喺 `GameData.gd` 實作**

喺 `level_config()` 之上加:

```gdscript
# ---------------------------------------------------------------------------
# 難度牆 —— 「第一次到達預期會輸」嘅關卡。
#
# 上一輪將獎勵曲線改成幾何增長之後,模擬 20 關零卡關:「輸 -> 升級 -> 過到」呢個
# 循環根本冇機會觸發,而佢係呢個遊戲嘅主循環。牆嘅作用就係定期強制觸發佢。
#
# 成份全部係機制,唔郁 wave_scale。呢個唔係風格偏好,係因果:乘大血量只會令玩家
# 買多幾級同一樣嘢就過到,而改陣容先係牆要教嘅嘢 —— 一幅「你需要對空手段」嘅牆
# 教到嘅嘢,一幅「所有嘢多 40% 血」嘅牆教唔到。
#
# 每幅牆嘅 boss 係 level_config 程序決定嘅,改唔到,所以成份要夾住個 boss —— 結果
# 反而順:三個 boss 本身就係治療 / 復活 / 反傷。
#   7  遠古樹妖 root_heal   + ambient minion_regen -> 加飛行 + 群療,考對空同
#                                                     「打得快過佢哋回血」
#   13 骷髏君主 revive_aura                        -> 加分裂 + 收窄 spawn 間隔,考 AoE
#   18 甲蟲皇   reflect(該關已有硬殼 + 高甲)      -> 加魔抗,考傷害類型
#
# 週期 20 而唔係 10:10 會令第 17 同第 18 關連住兩幅牆,而「牆與牆之間維持合理
# 操作一次過」係設計目標之一。20 之下間距係 6-5-9 循環。
const WALL_FIRST := 7
const WALL_PERIOD := 20
const WALL_OFFSETS := [0, 6, 11]     # -> 7, 13, 18,然後 27/33/38、47/53/58 …

var WALLS := {
	7:  {"add_fams": ["bat", "cultist"], "hint": "WALL_HINT_7"},
	13: {"add_fams": ["slime"], "spawn_min": 0.30, "hint": "WALL_HINT_13"},
	18: {"add_fams": ["ghost"], "hint": "WALL_HINT_18"},
}

## 呢一關係邊一幅牆?返 WALLS 嘅 key(7/13/18),唔係牆返 0。
func wall_slot(n: int) -> int:
	if n < WALL_FIRST:
		return 0
	var k: int = (n - WALL_FIRST) % WALL_PERIOD
	return WALL_FIRST + k if k in WALL_OFFSETS else 0

func wall_def(n: int) -> Dictionary:
	var slot: int = wall_slot(n)
	return WALLS.get(slot, {}) if slot > 0 else {}

func is_wall(n: int) -> bool:
	return wall_slot(n) > 0

func wall_hint_key(n: int) -> String:
	return String(wall_def(n).get("hint", ""))
```

`level_config()` 入面,`return {...}` 改成先起 `var cfg := {...}`,喺 dict 加一個
`"is_wall": false,`,然後 return 之前加:

```gdscript
	# 難度牆疊喺程序生成之上。Battle.gd 完全唔知道有「牆」呢回事 —— 佢照讀
	# families / spawn_interval_min,所以牆嘅每一個改動都留喺呢個檔案入面。
	var w: Dictionary = wall_def(n)
	if not w.is_empty():
		var fams2: Array = cfg["families"]
		for f in w.get("add_fams", []):
			if not (String(f) in fams2):
				fams2.append(String(f))
		if w.has("spawn_min"):
			cfg["spawn_interval_min"] = float(w["spawn_min"])
		cfg["is_wall"] = true
	return cfg
```

- [ ] **Step 4: 加 4 個 i18n key**

`i18n/game.csv` 加(擺喺 `LEVELSEL_*` 嗰組之後):

```csv
"LEVELSEL_DANGER","危險","Danger"
"WALL_HINT_7","呢關嘅怪會互相治療,而且有嘢喺天上飛","These monsters heal each other — and some of them fly"
"WALL_HINT_13","怪多過你嘅子彈,而且死咗仲會返嚟","They come faster than you can shoot, and they come back"
"WALL_HINT_18","護甲同魔抗各佔一半,單一傷害類型過唔到","Half of them shrug off steel, half shrug off magic"
```

- [ ] **Step 5: 補字型 subset(新字會喺 web 版 tofu)**

```powershell
python tools/subset_font.py
```
Expected: 印出掃到嘅字元數同新 ttf 大小

- [ ] **Step 6: 跑測試,確認佢綠**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/WallTest.tscn
```
Expected: `WALL PASS fails=0`

- [ ] **Step 7: Commit**

```bash
git add scripts/autoload/GameData.gd test/WallTest.gd test/WallTest.tscn i18n/ assets/fonts/
git commit -m "$(cat <<'EOF'
Put three difficulty walls in the curve, built from mechanics rather than multipliers

After last round rebuilt the reward curve, the 20-level simulation cleared
every stage on the first try. That is not the game working — the whole
lose-upgrade-clear loop, which is what the meta economy exists to serve, never
got a chance to run. Walls at levels 7 / 13 / 18 (repeating every 20) are where
it is meant to fire.

None of them raises wave_scale, and that is a causal choice rather than a
stylistic one: multiplying HP means the player buys a few more levels of the
same thing and walks through, whereas the point of a wall is to make them
change what they build. A wall that says "you need an answer to air" teaches
something a wall that says "everything has 40% more HP" cannot.

Each level's boss is fixed by the procedural generator, so the composition had
to be built around it — which turned out to help, since those three bosses are
already heal, revive and reflect. Level 7 adds fliers and healers against the
regenerating treant; 13 adds splitters and tightens the spawn floor against
the reviving skeleton lord; 18 adds magic resistance to a level that already
had hard shells and heavy armour, so no single damage type answers it.

Period 20, not 10: at 10 the walls would land on 17 and 18 back to back, and
"the levels between walls stay clearable in one go" is part of the design.

All of it is a table in GameData — Battle.gd reads families and
spawn_interval_min exactly as before and does not know walls exist.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: `BalanceSim --walls` + 調到達標

**Files:**
- Modify: `test/BalanceSim.gd`
- Modify: `scripts/autoload/GameData.gd`(如果模擬顯示要調 `WALLS`)
- Modify: `BALANCE_CHANGELOG.md`

**Interfaces:**
- Consumes: `GameData.is_wall(n)`(Task 7)
- Produces: `godot --headless --path . res://test/BalanceSim.tscn -- --walls` 出每關通過率表

- [ ] **Step 1: 加 `--walls` mode**

`BalanceSim.gd` `_ready()` 嘅 `elif "--curve" in args:` 之後加:

```gdscript
		elif "--walls" in args:
			await _walls_table()
```

同埋加(擺喺 `_curve_table()` 之後):

```gdscript
# ===========================================================================
# MODE 7 — 難度牆驗收 (--walls)
# ===========================================================================
## 「牆」係一個關於機率嘅講法 —— 「第一次到呢關預期會輸」 —— 所以量佢一定要
## 跑多個 seed。單次 playthrough 答唔到:一次通過只係一個樣本,而 crit / proc /
## spawn 家族嘅骰喺一場入面嘅方差好大(round 6 量過同一個陣容連續兩次 boss 傷害
## 係 47% 同 24%)。
##
## 每個 seed 都由 Meta.reset_save() 開始由第一關打上去,唔係直接跳去嗰關 ——
## 玩家到第 13 關嗰陣有幾多升級,係佢前面十二關賺返嚟嘅,直接跳過去就等於問一個
## 唔存在嘅玩家。
const WALL_SEEDS := 12
const WALL_MAX_TRIES := 3

func _walls_table() -> void:
	print("SIM 難度牆驗收 (%d 個 seed, 每關最多 %d 次)" % [WALL_SEEDS, WALL_MAX_TRIES])
	var first_win: Dictionary = {}     # lv -> 首次就贏嘅 seed 數
	var any_win: Dictionary = {}       # lv -> 三次內贏到嘅 seed 數
	var tries_sum: Dictionary = {}
	for lv in range(1, LEVELS + 1):
		first_win[lv] = 0
		any_win[lv] = 0
		tries_sum[lv] = 0
	for s in WALL_SEEDS:
		Meta.reset_save()
		seed(0xBA1A + s * 7919)
		for lv in range(1, LEVELS + 1):
			var attempt := 0
			var won := false
			while attempt < WALL_MAX_TRIES and not won:
				attempt += 1
				var r: Dictionary = await _play_attempt(lv)
				won = r.win
				if won and attempt == 1:
					first_win[lv] = int(first_win[lv]) + 1
				_spend_crystals()
			tries_sum[lv] = int(tries_sum[lv]) + attempt
			if won:
				any_win[lv] = int(any_win[lv]) + 1
			else:
				# 同 playthrough 一樣強制放行,先至量到成條曲線而唔係淨係量到第一幅牆
				Meta.on_level_cleared(lv)
				_spend_crystals()
		print("SIM   seed %d/%d 完成" % [s + 1, WALL_SEEDS])
	print("SIM  lv | 牆 | 首次通過率 | %d次內通過率 | 平均嘗試 | 達標" % WALL_MAX_TRIES)
	var bad := 0
	for lv in range(1, LEVELS + 1):
		var f: float = float(first_win[lv]) / float(WALL_SEEDS)
		var a: float = float(any_win[lv]) / float(WALL_SEEDS)
		var avg: float = float(tries_sum[lv]) / float(WALL_SEEDS)
		var wall: bool = GameData.is_wall(lv)
		# 牆:第一次去到預期會輸(首通 <= 30%),但投資之後過到(3 次內 >= 90%)
		# 非牆:合理操作一次過(首通 >= 85%)
		var ok: bool = (f <= 0.30 and a >= 0.90) if wall else (f >= 0.85)
		if not ok:
			bad += 1
		print("SIM  %2d | %s | %9.0f%% | %11.0f%% | %8.2f | %s"
			% [lv, "牆" if wall else "  ", f * 100.0, a * 100.0, avg,
			"OK" if ok else "唔達標"])
	print("SIM ---- %d/%d 關達標 ----" % [LEVELS - bad, LEVELS])
	if bad > 0:
		print("SIM 未達標,要調 GameData.WALLS(牆太易 -> 加成份;牆太難 -> 減成份;"
			+ "非牆關跌穿 85% -> 睇下係咪牆嘅成份漏咗落隔離關)")
```

- [ ] **Step 2: 先計時跑一個 seed 版本,確認可行**

暫時將 `WALL_SEEDS` 改做 `1` 跑一次,量實際時間:

```powershell
Measure-Command { & "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BalanceSim.tscn -- --walls } | Select-Object TotalMinutes
```
用呢個數乘 12 估算全跑時間。**如果估算 >15 分鐘,將 `WALL_SEEDS` 定做 8**,
並喺 `BALANCE_CHANGELOG.md` 寫明實際用咗幾多 seed 同點解。

- [ ] **Step 3: 跑全套,睇表**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BalanceSim.tscn -- --walls > sim_walls_r9.log 2>&1
Get-Content sim_walls_r9.log | Select-String "SIM"
```

- [ ] **Step 4: 按表調 `GameData.WALLS`,重跑到達標**

調嘅方向(**只准郁 `WALLS`,唔准郁 `WAVE_GROWTH` 或者 boss 血量** —— 郁咗就會影響
所有關,而牆嘅定義就係「只喺呢幾關」):

| 症狀 | 調法 |
|---|---|
| 牆首通率 >30%(太易) | 加多一個家族入 `add_fams`;或者第 13 關再收窄 `spawn_min`(0.30 → 0.26) |
| 牆 3 次內通過率 <90%(太難) | 由 `add_fams` 拎走最辣嗰個家族;第 13 關放寬 `spawn_min` |
| 非牆關首通率 <85% | 唔關牆事,係基礎曲線問題 —— 記錄落 CHANGELOG,唔好喺呢個 task 改 |

每次調完重跑 Step 3。**每次跑完都要記低表,唔准只記最後嗰次** —— 調嘅過程本身
就係證據。

- [ ] **Step 5: 續寫 `BALANCE_CHANGELOG.md`**

喺檔尾加一節,內容必須包含:
- 三幅牆嘅最終 `WALLS` 內容
- 最終嘅每關通過率表(由 `sim_walls_r9.log` 抄)
- 實際用咗幾多 seed,如果係 8 就寫明點解
- 調嘅過程:每次改咗乜、之後個表點變

- [ ] **Step 6: Commit**

```bash
git add test/BalanceSim.gd scripts/autoload/GameData.gd BALANCE_CHANGELOG.md sim_walls_r9.log
git commit -m "$(cat <<'EOF'
Measure the walls instead of asserting them, across twelve independent runs

"The player is expected to lose here the first time" is a claim about
probability, so a single playthrough cannot check it — one clear is one
sample, and the per-run variance in this game is large (round 6 measured the
same build doing 47% and 24% boss damage on consecutive runs).

--walls plays levels 1..20 from a fresh save on each of twelve seeds, retrying
up to three times with the real spend-crystals-between-attempts loop in
between, and reports first-try and three-try clear rates per level against the
design targets: walls at most 30% first-try and at least 90% within three,
non-walls at least 85% first-try.

Each seed starts from level 1 rather than jumping to the level under test.
What a player has bought by the time they reach level 13 is what the previous
twelve levels paid for, and dropping a fully-funded player straight in would
be measuring somebody who does not exist.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: 危險標記 + 失敗提示

**Files:**
- Modify: `scripts/ui/LevelSelect.gd`, `scripts/ui/Fail.gd`
- Modify: `test/WallTest.gd`

**Interfaces:**
- Consumes: `GameData.is_wall(n)` / `wall_hint_key(n)`(Task 7)、`LEVELSEL_DANGER` / `WALL_HINT_*`(Task 7 Step 4)

- [ ] **Step 1: 加測試 case**

`WallTest.gd` `_ready()` 加 `_case_ui()`,並加:

```gdscript
## 標記同提示真係入到畫面。Task 7 已經驗過 key 存在同譯咗,呢度驗嘅係另一件事:
## 有冇人真係讀嗰個 key —— 一個譯得完美但冇人用嘅 key 對玩家嚟講同冇一樣。
func _case_ui() -> void:
	# 選關:牆嘅卡要有骷髏 icon
	Meta.reset_save()
	Meta.highest_level = 20
	var ls = load("res://scripts/ui/LevelSelect.gd").new()
	add_child(ls)
	var wall_marks := 0
	var plain_marks := 0
	for n in range(1, 21):
		var marked: bool = ls.has_method("_is_marked_danger") and ls._is_marked_danger(n)
		if GameData.is_wall(n):
			if marked: wall_marks += 1
		elif marked:
			plain_marks += 1
	_ok("U 三幅牆都有危險標記", wall_marks == 3, "只有 %d 幅有標記" % wall_marks)
	_ok("U 非牆關冇危險標記", plain_marks == 0, "%d 個非牆關被標記" % plain_marks)
	ls.queue_free()

	# 失敗畫面:輸咗一幅牆要見到提示
	Flow.last_result = {"level": 7, "kills": 20, "crystals": 50,
		"progress": 0.5, "cap": 100, "boss_reached": false}
	var f = load("res://scripts/ui/Fail.gd").new()
	add_child(f)
	var want: String = tr(GameData.wall_hint_key(7))
	_ok("U 輸咗第 7 關見到剋制提示", _finds_text(f, want),
		"畫面上揾唔到 '%s'" % want)
	f.queue_free()

	Flow.last_result = {"level": 5, "kills": 20, "crystals": 50,
		"progress": 0.5, "cap": 100, "boss_reached": false}
	var f2 = load("res://scripts/ui/Fail.gd").new()
	add_child(f2)
	_ok("U 輸咗非牆關冇多餘提示", not _finds_text(f2, tr("WALL_HINT_7")),
		"非牆關竟然顯示緊第 7 關嘅提示")
	f2.queue_free()

## 遞迴揾一段文字有冇出現喺任何一個 Label 度。
func _finds_text(root: Node, want: String) -> bool:
	if want == "":
		return false
	if root is Label and String((root as Label).text).find(want) >= 0:
		return true
	for c in root.get_children():
		if _finds_text(c, want):
			return true
	return false
```

- [ ] **Step 2: 跑測試,確認佢紅**

Expected: FAIL — `U 三幅牆都有危險標記 — 只有 0 幅有標記`

- [ ] **Step 3: 改 `LevelSelect.gd`**

`_level_card(n)` 入面,`btn.add_child(vb)` 之前加:

```gdscript
	# 難度牆:玩家去到之前就應該知道呢關唔同啲。冇呢個標記,一場預期之內嘅失敗
	# 會被讀成「我打得差」而唔係「呢關要換陣容」,而後者先係我哋想佢諗嘅嘢。
	if _is_marked_danger(n):
		var skull := UI.tex_rect(Assets.ui("ic_skull"), Vector2(44, 44))
		skull.position = Vector2(14, 14)
		skull.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(skull)
		var dg := UI.label(tr("LEVELSEL_DANGER"), 22, UI.DANGER)
		dg.position = Vector2(62, 20)
		dg.size = Vector2(140, 32)
		dg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(dg)
```

同埋喺檔尾加:

```gdscript
## 呢張卡使唔使打危險標記。抽出嚟做一個函數,唔係為咗重用 —— 係為咗俾測試問到
## 「你到底標咗邊幾關」,而唔使去數畫面上有幾多個骷髏 sprite。
func _is_marked_danger(n: int) -> bool:
	return GameData.is_wall(n)
```

- [ ] **Step 4: 改 `Fail.gd`**

喺 `prog` 個 Label 加落 panel 之後加:

```gdscript
	# 牆關輸咗,講一句剋制方向。一句就夠,而且唔講具體塔名或者魔法名 ——
	# 講晒就唔係提示係答案,而「自己揾到答案」正正就係一幅牆想俾玩家嘅嘢。
	var hint_key: String = GameData.wall_hint_key(lv)
	if hint_key != "":
		var hint := UI.label(tr(hint_key), 26, UI.DANGER.lightened(0.25))
		hint.position = Vector2(190, 764)
		hint.size = Vector2(700, 70)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(hint)
```

**注意**:`retry` 掣本身喺 y780。加咗提示之後兩者會疊。將 `retry.position` 改
`Vector2(290, 850)`、`home.position` 改 `Vector2(290, 1010)`,並且**只喺有提示嗰陣**
先落呢個位 —— 冇提示嘅局唔應該平白多咗一大舊空白:

```gdscript
	var btn_y: float = 850.0 if hint_key != "" else 780.0
	var retry := UI.button(tr("FAIL_RETRY"), Vector2(500, 130), UI.ACCENT, 40)
	retry.position = Vector2(290, btn_y)
	...
	home.position = Vector2(290, btn_y + 160.0)
```

- [ ] **Step 5: 跑測試,確認佢綠**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/WallTest.tscn
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/I18nTest.tscn
```
Expected: 兩個都 exit 0

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/LevelSelect.gd scripts/ui/Fail.gd test/WallTest.gd
git commit -m "$(cat <<'EOF'
Tell the player a wall is a wall, before and after they hit it

A defeat the designer planned reads to the player as "I played badly" unless
something says otherwise, and "I played badly" leads to trying the same build
harder — which is exactly the response a wall is built to rule out. The level
select now marks the three walls with a skull and the word 危險 before the
player commits, and the fail screen adds one line pointing at the counter.

One line, and no tower or spell named. Working out which answer to build is
the thing the wall exists to teach; handing over the answer would leave it as
just a level that takes three tries.

The marked-danger test asks LevelSelect which levels it marked rather than
counting skull sprites on screen, so it keeps working when the card art moves.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

# PART 3 — 一手勢起塔

## File Structure(Part 3)

| 檔 | 責任 |
|---|---|
| `scripts/ui/UI.gd` | 修改 — 快捷列幾何常數(BattleHUD 同 QuickBar 共用一份) |
| `scripts/autoload/Meta.gd` | 修改 — `quick_slots` 持久化 + 指派 / 對調 / 自動填充 / 清洗 |
| `scripts/ui/BattleHUD.gd` | 修改 — 快捷列取代「建造」把手 |
| `scripts/ui/QuickBar.gd` + `scenes/QuickBar.tscn` | 新增 — 主選單嘅釘選畫面 |
| `scripts/autoload/Flow.gd`、`scripts/ui/MainMenu.gd` | 修改 — 路由 + 入口 |
| `test/BottomBarTest.gd` | 修改 — `Q` 組 + 改 `O` 組 |
| `i18n/game.csv` | 修改 — 4 個新 key |

---

### Task 10: `Meta.quick_slots` 持久化

**Files:**
- Modify: `scripts/autoload/Meta.gd`
- Modify: `test/BottomBarTest.gd`

**Interfaces:**
- Produces:
  - `Meta.QUICK_SLOTS := 6`(const)
  - `Meta.quick_slots: Array` — 長度 6,`0` = 空格
  - `Meta.set_quick_slot(slot: int, id: int) -> void`
  - `Meta.swap_quick_slots(a: int, b: int) -> void`
  - `Meta.quick_slot_ids() -> Array` — 複本,長度必然 6

- [ ] **Step 1: 寫失敗嘅測試**

`BottomBarTest.gd` `_ready()` 入面 `await _case_place()` 之後加 `await _case_quick_persist()`,並加:

```gdscript
# ---------------------------------------------------------------------------
# Q — 快捷槽嘅持久化同不變式
# ---------------------------------------------------------------------------
func _case_quick_persist() -> void:
	Meta.reset_save()
	_ok("Q 預設 = 四座初始塔 + 兩個空格",
		Meta.quick_slot_ids() == [1, 2, 5, 13, 0, 0],
		"got %s" % str(Meta.quick_slot_ids()))
	_ok("Q 長度一定係 6", Meta.quick_slot_ids().size() == Meta.QUICK_SLOTS,
		"got %d" % Meta.quick_slot_ids().size())

	# 解鎖新塔自動入第一個空格
	Meta.crystals = 99999
	Meta.unlock_tower(3)
	_ok("Q 新解鎖入第一個空格", int(Meta.quick_slot_ids()[4]) == 3,
		"slots=%s" % str(Meta.quick_slot_ids()))
	Meta.unlock_tower(4)
	_ok("Q 第二個新解鎖入第二個空格", int(Meta.quick_slot_ids()[5]) == 4,
		"slots=%s" % str(Meta.quick_slot_ids()))
	# 滿咗就唔再自動郁 —— 玩家排好嘅嘢唔可以俾一次解鎖打亂
	var before: Array = Meta.quick_slot_ids()
	Meta.unlock_tower(6)
	_ok("Q 六格滿咗之後解鎖唔會自動取代", Meta.quick_slot_ids() == before,
		"%s -> %s" % [str(before), str(Meta.quick_slot_ids())])

	# 指派一座已經喺另一格嘅塔 = 兩格對調,唔會出現兩次
	Meta.set_quick_slot(0, 4)     # 4 本來喺第 5 格
	var s: Array = Meta.quick_slot_ids()
	_ok("Q 指派已在列嘅塔 = 對調", int(s[0]) == 4 and int(s[5]) == 1,
		"slots=%s" % str(s))
	var seen: Dictionary = {}
	var dupes := 0
	for id in s:
		if int(id) > 0:
			if seen.has(int(id)): dupes += 1
			seen[int(id)] = true
	_ok("Q 冇一座塔佔兩格", dupes == 0, "slots=%s" % str(s))

	# 對調
	Meta.swap_quick_slots(0, 1)
	var s2: Array = Meta.quick_slot_ids()
	_ok("Q 對調", int(s2[0]) == int(s[1]) and int(s2[1]) == int(s[0]),
		"%s -> %s" % [str(s), str(s2)])

	# 存檔 round-trip
	Meta.save_game()
	var want: Array = Meta.quick_slot_ids()
	Meta.quick_slots = [0, 0, 0, 0, 0, 0]
	Meta.load_game()
	_ok("Q 重開遊戲保留", Meta.quick_slot_ids() == want,
		"want %s got %s" % [str(want), str(Meta.quick_slot_ids())])

	# 未解鎖 / 唔存在嘅 id 要當空格。呢個唔係防駭,係防「舊存檔」:
	# 一個 round 9 之前嘅存檔冇 quick_slots,而一個玩到一半又 reset 過嘅存檔
	# 可能有一個而家已經唔屬於佢嘅 id。
	Meta.quick_slots = [1, 999, 7, 0, 0, 0]     # 999 唔存在,7 未解鎖
	Meta.save_game()
	Meta.load_game()
	var s3: Array = Meta.quick_slot_ids()
	_ok("Q 唔存在嘅 id 當空格", int(s3[1]) == 0, "slots=%s" % str(s3))
	_ok("Q 未解鎖嘅 id 當空格", int(s3[2]) == 0, "slots=%s" % str(s3))
	_ok("Q 已解鎖嘅照留", int(s3[0]) == 1, "slots=%s" % str(s3))

	# 完全冇 quick_slots 嘅舊存檔要落返預設
	var raw: Dictionary = Meta.to_dict()
	raw.erase("quick_slots")
	var f := FileAccess.open(Meta.SAVE_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(raw, "\t"))
	f.close()
	Meta.load_game()
	_ok("Q 舊存檔(冇 quick_slots)落返預設",
		Meta.quick_slot_ids().size() == Meta.QUICK_SLOTS
		and int(Meta.quick_slot_ids()[0]) > 0,
		"got %s" % str(Meta.quick_slot_ids()))
```

- [ ] **Step 2: 跑測試,確認佢紅**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BottomBarTest.tscn
```
Expected: FAIL — `Invalid get index 'QUICK_SLOTS' (on base: 'Node (Meta.gd)')`

- [ ] **Step 3: 喺 `Meta.gd` 實作**

喺 `var settings` 附近加:

```gdscript
## 快捷列 —— 戰鬥底欄常駐嗰 6 格。0 = 空格,位置有意義(第 i 格就係畫面第 i 格),
## 所以呢個 Array 唔可以用 _to_int_array() 讀:嗰個會隔走 0 又會去重,
## 兩樣都會令「第 3 格係空」變成「冇第 3 格」。
const QUICK_SLOTS := 6
const QUICK_DEFAULT := [1, 2, 5, 13, 0, 0]
var quick_slots: Array = QUICK_DEFAULT.duplicate()
```

加函數(擺喺 `unlock_tower` 附近):

```gdscript
## 洗乾淨快捷列:長度補到 6、未解鎖同唔存在嘅 id 當空格、同一座塔唔准佔兩格。
##
## 呢個唔係防駭係防舊存檔 —— round 9 之前嘅存檔冇呢個欄位,而一個 reset 過嘅
## 存檔可能仲留住一個佢已經冇咗嘅塔。載入之後一定要叫,而且一定要喺
## unlocked_towers 讀完之後先叫。
func _sanitize_quick_slots() -> void:
	var out: Array = []
	var used: Dictionary = {}
	for i in QUICK_SLOTS:
		var id: int = _to_int(quick_slots[i]) if i < quick_slots.size() else 0
		if id > 0 and is_tower_unlocked(id) and not used.has(id):
			used[id] = true
			out.append(id)
		else:
			out.append(0)
	quick_slots = out

## 指派一座塔落第 `slot` 格。id = 0 即係清空。
## 塔本來喺另一格嘅話兩格對調,唔會出現同一座塔佔兩格 —— 兩格一樣嘅嘢
## 等於白白嘥咗一格,而玩家唔會知自己做咗呢件事。
func set_quick_slot(slot: int, id: int) -> void:
	if slot < 0 or slot >= QUICK_SLOTS:
		return
	if id > 0 and not is_tower_unlocked(id):
		return
	if id > 0:
		var old: int = quick_slots.find(id)
		if old >= 0:
			quick_slots[old] = quick_slots[slot]
	quick_slots[slot] = id
	save_game()

func swap_quick_slots(a: int, b: int) -> void:
	if a < 0 or b < 0 or a >= QUICK_SLOTS or b >= QUICK_SLOTS or a == b:
		return
	var t: int = _to_int(quick_slots[a])
	quick_slots[a] = quick_slots[b]
	quick_slots[b] = t
	save_game()

func quick_slot_ids() -> Array:
	return quick_slots.duplicate()

## 新解鎖嘅塔自動入第一個空格 —— 即係預設嘅「四座初始塔 + 最新解鎖兩座」。
## 六格滿咗就唔再自動郁:嗰陣個列已經係玩家排過嘅嘢,一次解鎖唔應該打亂佢。
func _fill_quick_slot(id: int) -> void:
	if quick_slots.has(id):
		return
	var i: int = quick_slots.find(0)
	if i >= 0:
		quick_slots[i] = id
```

`unlock_tower()` 改成:

```gdscript
func unlock_tower(id: int) -> bool:
	if is_tower_unlocked(id) or not _take_crystals(GameData.tower_by_id(id).unlock):
		return false
	unlocked_towers.append(id)
	_fill_quick_slot(id)
	Audio.play("sfx_unlock")
	save_game()
	return true
```

`to_dict()` 加 `"quick_slots": quick_slots,`。

`load_game()` 入面,`unlocked_towers = ...` 嗰行之後加:

```gdscript
	quick_slots = _to_slot_array(data.get("quick_slots", []))
```
並喺 `save_version = ...` 之後(即所有欄位讀完之後)加:
```gdscript
	# 一定要喺 unlocked_towers 讀完之後 —— 清洗嘅規則要用到「呢座塔解鎖咗未」
	_sanitize_quick_slots()
```

加 parser(擺喺 `_to_int_array` 隔離):

```gdscript
## quick_slots 專用。_to_int_array 唔用得:佢會隔走 0(而 0 喺呢度係「空格」
## 呢個意思)又會去重,兩樣都會令位置資訊冇咗。長度唔啱就落預設。
func _to_slot_array(a) -> Array:
	if not (a is Array) or (a as Array).size() != QUICK_SLOTS:
		return QUICK_DEFAULT.duplicate()
	var out: Array = []
	for v in a:
		out.append(maxi(0, _to_int(v)))
	return out
```

`reset_save()` 加 `quick_slots = QUICK_DEFAULT.duplicate()`(擺喺 `unlocked_towers` 嗰行之後)。

- [ ] **Step 4: 跑測試,確認佢綠**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BottomBarTest.tscn
```
Expected: `BOTTOMBAR PASS fails=0`

- [ ] **Step 5: Commit**

```bash
git add scripts/autoload/Meta.gd test/BottomBarTest.gd
git commit -m "$(cat <<'EOF'
Persist the six quick-bar slots, with position as meaningful as content

quick_slots is a fixed-length array where index means "which box on screen"
and 0 means "empty box". That rules out reusing _to_int_array() to load it —
that helper strips zeros and de-duplicates, both of which would turn "slot 3
is empty" into "there is no slot 3" and shift everything after it left.

Assigning a tower that already sits in another slot swaps the two rather than
appearing twice: two boxes holding the same tower is a wasted box, and nothing
on screen would tell the player they had done it.

A newly unlocked tower drops into the first empty slot, which is where the
default "four starters plus the two newest unlocks" comes from. Once all six
are full nothing moves automatically — by then the row is something the player
arranged, and one unlock should not rearrange it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: 快捷列取代「建造」把手

**Files:**
- Modify: `scripts/ui/UI.gd`, `scripts/ui/BattleHUD.gd`
- Modify: `test/BottomBarTest.gd`
- Modify: `i18n/game.csv`

**Interfaces:**
- Consumes: `Meta.quick_slot_ids()`(Task 10)
- Produces:
  - `UI.QUICK_RECT := Rect2(20, 1586, 1040, 102)`、`UI.QUICK_CELLS := 7`、`UI.QUICK_GAP := 8.0`、`UI.quick_cell_w() -> float`
  - `BattleHUD.quick_cards: Array` — `{id, btn, cost, slot}`
  - `BattleHUD.more_btn: Button`
  - **移除**:`BattleHUD.HANDLE_RECT`、`handle_btn`、`handle_gold`、`_build_handle()`

- [ ] **Step 1: 寫失敗嘅測試**

`BottomBarTest.gd` `_ready()` 加 `await _case_quick_layout()` 同 `await _case_one_gesture()`,並加:

```gdscript
# ---------------------------------------------------------------------------
# Q — 快捷列佈局
# ---------------------------------------------------------------------------
func _case_quick_layout() -> void:
	# 最迫嘅情況:15 個魔法 + 6 個塔槽 + 更多掣同場
	var b = await _start(15, 20)
	var hud = b.hud
	_ok("Q 六格都起咗", hud.quick_cards.size() + _empty_slots(hud) == Meta.QUICK_SLOTS,
		"%d 張卡 + %d 個空格" % [hud.quick_cards.size(), _empty_slots(hud)])
	_ok("Q 有更多掣", hud.more_btn != null, "more_btn is null")
	var rects: Array = []
	for c in hud.quick_cards:
		rects.append(Rect2(c.btn.position, c.btn.size))
	rects.append(Rect2(hud.more_btn.position, hud.more_btn.size))
	for r in rects:
		_ok("Q 觸控目標 %.0fx%.0f" % [r.size.x, r.size.y],
			minf(r.size.x, r.size.y) >= 88.0,
			"min side %.1f < 88" % minf(r.size.x, r.size.y))
		_ok("Q 喺畫面內 @%.0f,%.0f" % [r.position.x, r.position.y],
			r.position.x >= 0.0 and r.end.x <= 1080.0 and r.end.y <= 1920.0,
			"rect %s escapes the screen" % str(r))
	var overlaps := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if rects[i].intersects(rects[j]):
				overlaps += 1
	_ok("Q 七格冇重疊", overlaps == 0, "%d overlapping pairs" % overlaps)
	# 快捷列同魔法 grid 唔可以撞 —— 呢個係最迫佈局嘅真正風險
	for r in rects:
		_ok("Q 唔撞魔法列 @%.0f" % r.position.y,
			r.end.y <= hud.SPELL_AREA.position.y,
			"quick cell bottom %.0f overlaps spells at %.0f"
			% [r.end.y, hud.SPELL_AREA.position.y])
	for c in hud.spell_cards:
		_ok("Q 魔法卡唔撞快捷列",
			c.btn.position.y >= UI.QUICK_RECT.end.y,
			"spell top %.0f is above quick row bottom %.0f"
			% [c.btn.position.y, UI.QUICK_RECT.end.y])
	await _end(b)

func _empty_slots(hud) -> int:
	var n := 0
	for id in Meta.quick_slot_ids():
		if int(id) == 0:
			n += 1
	return n

# ---------------------------------------------------------------------------
# Q — 一個手勢起塔
# ---------------------------------------------------------------------------
func _case_one_gesture() -> void:
	# 20 座全解鎖,但快捷列維持預設 [1,2,5,13,0,0] —— 即係「四張卡 + 兩個空格」
	# 呢個開局形狀,同時保證嗰四個 id 真係解鎖咗
	var b = await _start(4, 20)
	var hud = b.hud
	b.gold = 9999
	_ok("Q 預設四張快捷卡", hud.quick_cards.size() == 4,
		"%d cards, slots=%s" % [hud.quick_cards.size(), str(Meta.quick_slot_ids())])
	var spot := _free_spot(b, hud)
	if spot == Vector2.INF:
		_ok("Q 有空地可放", false, "no legal build spot")
		await _end(b)
		return
	var card: Button = hud.quick_cards[0].btn
	var tid: int = hud.quick_cards[0].id
	var before: int = b.towers.size()
	var gold0: int = b.gold
	# 呢個就係成個 task 嘅重點:由快捷槽按住 -> 拖 -> 放手,一個手勢,
	# 全程唔使開抽屜
	await _drag(card.global_position + card.size * 0.5, spot)
	_ok("Q 一手勢起到塔", b.towers.size() == before + 1,
		"towers %d -> %d" % [before, b.towers.size()])
	_ok("Q 起到嘅係嗰座塔",
		b.towers.size() > before and int(b.towers[b.towers.size() - 1].id) == tid,
		"placed a different tower")
	_ok("Q 有扣金", b.gold < gold0, "gold %d -> %d" % [gold0, b.gold])
	_ok("Q 全程冇開過抽屜", not hud._drawer_open, "drawer opened during the gesture")
	_ok("Q 抽屜真係冇現身", not hud.drawer.visible, "drawer became visible")

	# 空槽撳一下 = 開抽屜
	var empty_btn: Button = _empty_slot_btn(hud)
	_ok("Q 揾到空槽", empty_btn != null, "no empty slot button found")
	if empty_btn != null:
		await _tap(empty_btn.global_position + empty_btn.size * 0.5)
		_ok("Q 撳空槽開抽屜", hud._drawer_open, "drawer did not open")
		await _tap(Vector2(540, 300))
	await _end(b)

## 空槽個掣冇入 quick_cards(佢冇 id),所以按位置揾。
func _empty_slot_btn(hud) -> Button:
	var taken: Dictionary = {}
	for c in hud.quick_cards:
		taken[int(c.slot)] = true
	for i in Meta.QUICK_SLOTS:
		if taken.has(i):
			continue
		var x: float = UI.QUICK_RECT.position.x + i * (UI.quick_cell_w() + UI.QUICK_GAP)
		for ch in hud.get_children():
			if ch is Button and absf(ch.position.x - x) < 1.0 \
					and absf(ch.position.y - UI.QUICK_RECT.position.y) < 1.0:
				return ch
	return null
```

同時改 `_case_open_close()`:將兩處 `hud.HANDLE_RECT.position + hud.HANDLE_RECT.size * 0.5`
換成 `hud.more_btn.global_position + hud.more_btn.size * 0.5`,`await _tap(...)` 三個
call 都要改。

同時改 `_start()`:佢直接寫 `Meta.unlocked_towers` 而唔經 `unlock_tower()`,
所以快捷列可能指住一啲喺呢個 case 入面未解鎖嘅塔。喺 `Flow.selected_level = 1`
之前加一行:

```gdscript
	# 直接寫 unlocked_towers 繞過咗 unlock_tower() 嘅自動填充同載入時嘅清洗,
	# 所以要自己洗一次 —— 唔係就會出現「快捷列有張卡指住一座你未解鎖嘅塔」
	Meta._sanitize_quick_slots()
```

- [ ] **Step 2: 跑測試,確認佢紅**

Expected: FAIL — `Invalid get index 'QUICK_RECT' (on base: 'GDScript')` 同 `quick_cards`

- [ ] **Step 3: 喺 `UI.gd` 加共用幾何**

`const PARCH` 之後加:

```gdscript
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
```

- [ ] **Step 4: 改 `BattleHUD.gd`**

**刪走**:`const HANDLE_RECT`、`var handle_btn`、`var handle_gold`、`var _handle_gold`、
整個 `_build_handle()`、`refresh()` 入面 `if handle_gold != null ...` 嗰三行。

`_build_buildbar()` 尾嗰句 `_build_handle()` 改成 `_build_quickbar()`。

改 `_build_buildbar()` 開頭嘅註解 block(1592/1690 嗰段)成:

```gdscript
# ---------------------------------------------------------------------------
# Bottom bar.
#
#   1586..1688  常駐快捷列 — 6 個塔槽 + 「更多」,一行過
#   1690..1912  魔法 grid — 每個學過嘅魔法,永遠喺畫面上
#   抽屜由「更多」掣拉上嚟,停喺 1584,所以佢永遠唔會冚住快捷列或者魔法列。
#
# 呢一行取代咗舊嘅「建造」把手。把手嘅問題唔係佢佔位,係佢令起塔變成兩個動作:
# 開抽屜,再拖。一個常駐嘅槽令個手勢變返一個 —— 按住、拖出去、放手。
# 抽屜留返做全塔倉庫(20 座塔擺唔落 6 格),入面照樣一手勢拖得。
# ---------------------------------------------------------------------------
```

加(擺喺 `_make_build_card` 之後):

```gdscript
# --- 常駐快捷列 -------------------------------------------------------------
var quick_cards: Array = []      # {id, btn, cost, slot}
var more_btn: Button
## 每幀要檢查買唔買得起嘅卡。抽屜卡同快捷卡合埋一個 Array 起一次,
## 好過喺 refresh() 入面逐幀 `build_cards + quick_cards` 開一個新 Array。
var _afford_cards: Array = []

func _build_quickbar() -> void:
	var cw: float = UI.quick_cell_w()
	var ids: Array = Meta.quick_slot_ids()
	for i in Meta.QUICK_SLOTS:
		# 未解鎖嘅 id 一律當空格。Meta 載入時會洗一次,但呢度唔可以假設佢啱 ——
		# 測試同 art_export 都會直接寫 Meta.unlocked_towers 而唔經 unlock_tower(),
		# 而喺戰鬥入面畫一張買唔到嘅塔卡係比空格差好多嘅結果。
		var id: int = int(ids[i])
		if id > 0 and not Meta.is_tower_unlocked(id):
			id = 0
		var cell := _make_quick_cell(id, i, cw)
		cell.position = Vector2(UI.QUICK_RECT.position.x + i * (cw + UI.QUICK_GAP),
			UI.QUICK_RECT.position.y)
		add_child(cell)
	more_btn = UI.button(tr("HUD_MORE"), Vector2(cw, UI.QUICK_RECT.size.y), UI.PANEL_HI, 26)
	more_btn.position = Vector2(
		UI.QUICK_RECT.position.x + Meta.QUICK_SLOTS * (cw + UI.QUICK_GAP),
		UI.QUICK_RECT.position.y)
	more_btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
	more_btn.pressed.connect(func(): _set_drawer(not _drawer_open))
	add_child(more_btn)
	_afford_cards = build_cards + quick_cards

## 一個快捷槽。空格畫成暗色「+」,撳落去開抽屜 —— 六格闊度永遠一樣,所以
## 解鎖一座新塔唔會令成條底欄跳位。
func _make_quick_cell(id: int, slot: int, cw: float) -> Control:
	var btn := Button.new()
	btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
	btn.custom_minimum_size = btn.size
	btn.add_theme_stylebox_override("normal", UI.frame_box("slot9", 14, 6, 6))
	btn.add_theme_stylebox_override("hover", UI.frame_box("slot9", 14, 6, 6, Color(1.18, 1.18, 1.18)))
	btn.add_theme_stylebox_override("pressed", UI.frame_box("slot9", 14, 6, 6, Color(0.7, 1.1, 0.8)))
	btn.add_theme_stylebox_override("disabled", UI.frame_box("slot9", 14, 6, 6, Color(0.42, 0.42, 0.46)))
	if id <= 0:
		var plus := UI.label("+", 44, Color(0.55, 0.50, 0.44))
		plus.size = btn.size
		plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(plus)
		btn.pressed.connect(func(): _set_drawer(true))
		return btn
	var def := GameData.tower_by_id(id)
	btn.tooltip_text = "%s\n%s" % [tr(def.name), tr(def.desc)]
	# 同抽屜卡行同一條手勢鏈。快捷列唔係抽屜,所以 _over_drawer 唔會否決,
	# _set_drawer(false) 係 no-op —— 個手勢由頭到尾就係一下。
	btn.gui_input.connect(func(e: InputEvent): _card_gui(e, id, false))
	var icon := UI.tex_rect(Assets.tower(id), Vector2(60, 60))
	icon.position = Vector2((cw - 60.0) * 0.5, 4)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(icon)
	var coin := UI.tex_rect(Assets.coin(), Vector2(22, 22))
	coin.position = Vector2(cw * 0.5 - 36.0, 70)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(coin)
	var cost := UI.label(str(def.place_cost), 24, UI.GOLD)
	cost.position = Vector2(cw * 0.5 - 10.0, 68)
	cost.size = Vector2(64, 30)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(cost)
	quick_cards.append({"id": id, "btn": btn, "cost": int(def.place_cost), "slot": slot})
	return btn
```

`refresh()` 入面,將

```gdscript
	for c in build_cards:
```
改成
```gdscript
	for c in _afford_cards:
```

- [ ] **Step 5: 加 i18n key**

`i18n/game.csv` 加:

```csv
"HUD_MORE","更多","More"
```

- [ ] **Step 6: 補字型 subset + 跑測試**

```powershell
python tools/subset_font.py
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BottomBarTest.tscn
```
Expected: `BOTTOMBAR PASS fails=0`,包括全部 `Q` case 同改咗嘅 `O` case

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/UI.gd scripts/ui/BattleHUD.gd test/BottomBarTest.gd i18n/ assets/fonts/
git commit -m "$(cat <<'EOF'
Make building a tower one gesture again with a permanent six-slot row

The drawer that replaced the scrolling build strip fixed the scrolling but
cost a step: building meant open the drawer, then drag. Six slots now live in
the collapsed bar, so a press on a slot, a drag onto the map and a release is
the whole thing. The drawer stays as the full warehouse — twenty towers do not
fit in six boxes — and drags out of it work exactly as before.

The slots reuse the existing card gesture chain unchanged. That works because
the row is not the drawer: _over_drawer never vetoes the drop and the
_set_drawer(false) on release is a no-op, so nothing special was needed.

Geometry moved to UI.gd because the pinning screen has to draw the same row
1:1 — sharing one set of numbers is what makes "what you arrange is what you
get" true rather than approximately true. 102px tall is the tight constraint,
not a round number: a 60px icon plus a price row is 90, and the touch target
minimum is 88.

Empty slots render as a dim "+" that opens the drawer, so the row keeps its
width whatever the player owns and the bottom bar never reflows on an unlock.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: 主選單「快捷列」畫面

**Files:**
- Create: `scripts/ui/QuickBar.gd`, `scenes/QuickBar.tscn`
- Modify: `scripts/autoload/Flow.gd`, `scripts/ui/MainMenu.gd`
- Modify: `test/BottomBarTest.gd`, `i18n/game.csv`

**Interfaces:**
- Consumes: `Meta.set_quick_slot / swap_quick_slots / quick_slot_ids`(Task 10)、`UI.QUICK_RECT / quick_cell_w()`(Task 11)
- Produces: `Flow.QUICKBAR := "res://scenes/QuickBar.tscn"`;`QuickBar.selected_slot: int`(-1 = 未揀)、`QuickBar._slot_pressed(i: int)`(揀 / 取消揀 / 兩格對調)、`QuickBar._tower_pressed(id: int)`(指派 / 清空)、`QuickBar.preview_cell_w() -> float`

- [ ] **Step 1: 寫失敗嘅測試**

`BottomBarTest.gd` 加 `await _case_quickbar_screen()`:

```gdscript
# ---------------------------------------------------------------------------
# Q — 主選單嘅釘選畫面
# ---------------------------------------------------------------------------
func _case_quickbar_screen() -> void:
	Meta.reset_save()
	Meta.crystals = 99999
	Meta.unlock_tower(3)
	Meta.unlock_tower(4)
	var qb = load("res://scripts/ui/QuickBar.gd").new()
	add_child(qb)
	await _idle(3)

	# 預覽用嘅係實際尺寸,唔係另一套數
	_ok("QB 預覽格闊度 = 戰鬥實際",
		is_equal_approx(qb.preview_cell_w(), UI.quick_cell_w()),
		"preview %.2f vs battle %.2f" % [qb.preview_cell_w(), UI.quick_cell_w()])

	# 撳槽 -> 撳塔 = 指派
	var before: Array = Meta.quick_slot_ids()
	qb._slot_pressed(0)
	_ok("QB 撳槽選中", qb.selected_slot == 0, "selected_slot=%d" % qb.selected_slot)
	qb._tower_pressed(6)                    # 6 未解鎖
	_ok("QB 未解鎖嘅塔指派唔到", Meta.quick_slot_ids() == before,
		"%s -> %s" % [str(before), str(Meta.quick_slot_ids())])
	qb._tower_pressed(4)                    # 4 已解鎖,而且已經喺第 6 格
	var s: Array = Meta.quick_slot_ids()
	_ok("QB 指派到第 0 格", int(s[0]) == 4, "slots=%s" % str(s))
	_ok("QB 原本嗰格接走咗被換走嗰座", int(s[5]) == int(before[0]),
		"slots=%s (before %s)" % [str(s), str(before)])

	# 入嚟嗰陣冇嘢揀住,所以撳塔唔應該有嘢發生
	qb.selected_slot = -1
	var s2: Array = Meta.quick_slot_ids()
	qb._tower_pressed(1)
	_ok("QB 未揀槽撳塔冇作用", Meta.quick_slot_ids() == s2,
		"%s -> %s" % [str(s2), str(Meta.quick_slot_ids())])

	# 撳槽 A 再撳槽 B = 兩格對調(重排)
	var s3: Array = Meta.quick_slot_ids()
	qb._slot_pressed(1)
	qb._slot_pressed(3)
	var s4: Array = Meta.quick_slot_ids()
	_ok("QB 撳兩個槽 = 對調",
		int(s4[1]) == int(s3[3]) and int(s4[3]) == int(s3[1]),
		"%s -> %s" % [str(s3), str(s4)])
	_ok("QB 對調完清返揀住嘅槽", qb.selected_slot == -1,
		"selected_slot=%d" % qb.selected_slot)

	# 撳返同一個槽 = 取消揀,唔係對調自己
	var s5: Array = Meta.quick_slot_ids()
	qb._slot_pressed(2)
	qb._slot_pressed(2)
	_ok("QB 撳返同一格 = 取消揀", qb.selected_slot == -1,
		"selected_slot=%d" % qb.selected_slot)
	_ok("QB 取消揀冇郁到內容", Meta.quick_slot_ids() == s5,
		"%s -> %s" % [str(s5), str(Meta.quick_slot_ids())])

	# 揀住嘅槽再撳同一座塔 = 清空
	qb._slot_pressed(0)
	qb._tower_pressed(4)
	_ok("QB 再撳同一座 = 清空", int(Meta.quick_slot_ids()[0]) == 0,
		"slots=%s" % str(Meta.quick_slot_ids()))

	# 改完即刻寫落存檔 —— 玩家唔應該要做多一步「儲存」
	var want: Array = Meta.quick_slot_ids()
	Meta.quick_slots = [0, 0, 0, 0, 0, 0]
	Meta.load_game()
	_ok("QB 改完即刻存檔", Meta.quick_slot_ids() == want,
		"want %s got %s" % [str(want), str(Meta.quick_slot_ids())])
	qb.queue_free()
	await _idle(2)
```

- [ ] **Step 2: 跑測試,確認佢紅**

Expected: FAIL — `res://scripts/ui/QuickBar.gd` 唔存在

- [ ] **Step 3: 寫 `scripts/ui/QuickBar.gd`**

```gdscript
extends Control
## 快捷列設定 —— 決定戰鬥底欄常駐嗰六格擺邊六座塔。
##
## 呢個畫面喺主選單而唔喺戰鬥入面,有兩個理由。一,戰鬥入面唯一夠位嘅手勢係
## 長按,而長按同「按住拖出去起塔」係同一個開頭,兩者一定會撞。二,揀邊六座塔
## 帶上戰場本來就係開打之前先決定嘅事,唔係打到一半先諗。
##
## 上半部 1:1 畫返戰鬥底欄嗰行(共用 UI.QUICK_RECT / UI.quick_cell_w(),
## 唔係另外抄一套數),落半部係已解鎖嘅塔。撳槽 -> 撳塔 = 指派。

const PREVIEW_Y := 260.0
const GRID_TOP := 470.0
const GRID_COLS := 4
const GRID_CELL := Vector2(232, 168)
const GRID_GAP := 16.0

## -1 = 未揀。入嚟嗰陣冇嘢揀住 —— 預設揀住第 0 格會令玩家撳第一座塔嗰時
## 唔知唔覺改咗一格佢冇打算改嘅嘢。
var selected_slot: int = -1
var _slot_btns: Array = []       # index = slot
var _tower_btns: Dictionary = {} # tower id -> Button
var _preview_root: Control

func _ready() -> void:
	UI.menu_backdrop(self)
	add_child(UI.banner_title(tr("QUICKBAR_TITLE"), 26, 620, 50))

	var back := UI.button(tr("NAV_BACK"), Vector2(200, 88), UI.PANEL, 30)
	back.position = Vector2(24, 40)
	back.pressed.connect(func(): Flow.goto(Flow.MAIN_MENU))
	add_child(back)

	var hint := UI.label(tr("QUICKBAR_HINT"), 26, UI.TEXT_DIM)
	hint.position = Vector2(60, 180)
	hint.size = Vector2(960, 60)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_build_preview()
	_build_grid()
	_refresh()

## 幾何直接由 UI 攞。呢度嘅重點就係「你見到嘅就係戰鬥入面嗰行」,
## 所以絕對唔可以喺呢度另外定義一套尺寸。
func preview_cell_w() -> float:
	return UI.quick_cell_w()

func _build_preview() -> void:
	var cw: float = preview_cell_w()
	_preview_root = Control.new()
	_preview_root.position = Vector2(UI.QUICK_RECT.position.x, PREVIEW_Y)
	_preview_root.size = Vector2(UI.QUICK_RECT.size.x, UI.QUICK_RECT.size.y)
	add_child(_preview_root)
	_slot_btns.resize(Meta.QUICK_SLOTS)
	for i in Meta.QUICK_SLOTS:
		var btn := Button.new()
		btn.size = Vector2(cw, UI.QUICK_RECT.size.y)
		btn.custom_minimum_size = btn.size
		btn.position = Vector2(i * (cw + UI.QUICK_GAP), 0)
		btn.pressed.connect(_slot_pressed.bind(i))
		_preview_root.add_child(btn)
		_slot_btns[i] = btn
	# 「更多」格畫出嚟係為咗令預覽真係等於實際嗰行 —— 但佢唔係一個可以指派嘅槽
	var more := UI.button(tr("HUD_MORE"), Vector2(cw, UI.QUICK_RECT.size.y), UI.PANEL, 26)
	more.position = Vector2(Meta.QUICK_SLOTS * (cw + UI.QUICK_GAP), 0)
	more.size = Vector2(cw, UI.QUICK_RECT.size.y)
	more.disabled = true
	_preview_root.add_child(more)

func _build_grid() -> void:
	var ids: Array = Meta.unlocked_towers.duplicate()
	ids.sort()
	for k in ids.size():
		var id: int = int(ids[k])
		var btn := UI.button("", GRID_CELL, UI.PANEL_HI, 24)
		btn.position = Vector2(
			60.0 + (k % GRID_COLS) * (GRID_CELL.x + GRID_GAP),
			GRID_TOP + (k / GRID_COLS) * (GRID_CELL.y + GRID_GAP))
		btn.size = GRID_CELL
		btn.pressed.connect(_tower_pressed.bind(id))
		add_child(btn)
		var def := GameData.tower_by_id(id)
		var icon := UI.tex_rect(Assets.tower(id), Vector2(88, 88))
		icon.position = Vector2((GRID_CELL.x - 88.0) * 0.5, 10)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)
		var nbox := Control.new()
		nbox.position = Vector2(8, 104)
		nbox.size = Vector2(GRID_CELL.x - 16.0, 56)
		nbox.clip_contents = true
		nbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(nbox)
		var nm := UI.label(tr(def.name), 22, UI.TEXT)
		nm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nbox.add_child(nm)
		_tower_btns[id] = btn

## 撳一個槽。撳返已經揀住嗰個 = 取消揀;撳另一個槽 = 兩格對調。
##
## 對調做成「撳兩下」而唔係拖曳,係因為呢啲格得 141px 闊,喺電話上拖一個
## 141px 嘅目標去另一個 141px 嘅目標本身就係一個容易撳錯嘅動作,
## 而「撳 A 再撳 B」冇呢個問題,又同下面「撳槽再撳塔」係同一個句法。
func _slot_pressed(i: int) -> void:
	if selected_slot == i:
		selected_slot = -1
	elif selected_slot >= 0:
		Meta.swap_quick_slots(selected_slot, i)
		selected_slot = -1
	else:
		selected_slot = i
	_refresh()

## 撳一座塔。要有一個揀咗嘅槽先有意義 —— 冇揀槽就撳,唔知放邊格,所以乜都唔做。
## 撳返已經喺揀咗嗰格入面嘅塔 = 清空嗰格(即係「取消釘選」,唔使多一個掣)。
func _tower_pressed(id: int) -> void:
	if selected_slot < 0 or selected_slot >= Meta.QUICK_SLOTS:
		return
	if not Meta.is_tower_unlocked(id):
		return
	var cur: int = int(Meta.quick_slot_ids()[selected_slot])
	Meta.set_quick_slot(selected_slot, 0 if cur == id else id)
	_refresh()

func _refresh() -> void:
	var ids: Array = Meta.quick_slot_ids()
	for i in Meta.QUICK_SLOTS:
		var btn: Button = _slot_btns[i]
		for c in btn.get_children():
			c.queue_free()
		var id: int = int(ids[i])
		var chosen: bool = (i == selected_slot)
		btn.add_theme_stylebox_override("normal",
			UI.frame_box("slot9", 14, 6, 6,
				Color(1.35, 1.25, 0.75) if chosen else Color.WHITE))
		if id > 0:
			var icon := UI.tex_rect(Assets.tower(id), Vector2(60, 60))
			icon.position = Vector2((btn.size.x - 60.0) * 0.5, 4)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(icon)
			var cost := UI.label(str(GameData.tower_by_id(id).place_cost), 24, UI.GOLD)
			cost.position = Vector2(0, 68)
			cost.size = Vector2(btn.size.x, 30)
			cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(cost)
		else:
			var plus := UI.label("+", 44, Color(0.55, 0.50, 0.44))
			plus.size = btn.size
			plus.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			plus.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(plus)
	# 已經喺快捷列嘅塔加個星,方便一眼睇晒仲有邊幾座未擺
	for id in _tower_btns:
		var b: Button = _tower_btns[id]
		b.modulate = Color(1.25, 1.2, 0.85) if ids.has(int(id)) else Color.WHITE
```

`scenes/QuickBar.tscn`:

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/QuickBar.gd" id="1"]

[node name="QuickBar" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

- [ ] **Step 4: 接落 Flow 同主選單**

`Flow.gd` `const BESTIARY` 之後加:

```gdscript
const QUICKBAR := "res://scenes/QuickBar.tscn"
```

`MainMenu.gd`,`up`(升級)個掣加完之後、`bestiary` 之前加:

```gdscript
	var quick := UI.button(tr("MENU_QUICKBAR"), Vector2(600, 110))
	quick.pressed.connect(func(): Flow.goto(Flow.QUICKBAR))
	vb.add_child(quick)
```

**注意**:主選單個 VBox 由 y620 開始,而家有 8 個掣。核對總高:
120 + 110×6 + 90 + 26×7 = 1052,620 + 1052 = 1672 < 1920 ✓。

- [ ] **Step 5: 加 i18n key**

```csv
"MENU_QUICKBAR","快捷列  (戰鬥底欄擺邊六座塔)","Quick Bar  (Your six battle slots)"
"QUICKBAR_TITLE","快捷列設定","Quick Bar"
"QUICKBAR_HINT","撳一個槽,再撳一座塔就放入去。撳兩個槽 = 對調。再撳同一座塔 = 清空。","Tap a slot then a tower to assign it. Tap two slots to swap them. Tap the same tower again to clear."
```

- [ ] **Step 6: 補字型 subset + 跑測試**

```powershell
python tools/subset_font.py
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --import --path .
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/BottomBarTest.tscn
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/SceneCheck.tscn
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . res://test/I18nTest.tscn
```
Expected: 三個都 exit 0。**如果 `SceneCheck` 唔識自動掃新場景,就手動加 `QuickBar.tscn`
入佢張清單度** —— 一個冇人開過嘅場景等於冇測過。

- [ ] **Step 7: Commit**

```bash
git add scripts/ui/QuickBar.gd scenes/QuickBar.tscn scripts/autoload/Flow.gd scripts/ui/MainMenu.gd test/BottomBarTest.gd i18n/ assets/fonts/
git commit -m "$(cat <<'EOF'
Move quick-bar pinning to its own main-menu screen

Pinning inside the battle would have to be a long press, and a long press
starts identically to "hold a slot and drag it onto the map" — the one gesture
this round exists to protect. Deciding which six towers you take into a fight
is also something you do before the fight, not halfway through one.

The screen draws the battle row 1:1 from UI.QUICK_RECT and UI.quick_cell_w()
rather than defining its own sizes, which is the whole point: what you arrange
here is literally what appears down there, not an approximation of it.

Tap a slot then a tower to assign; tapping a tower already in the selected
slot clears it, so unpinning needs no second control. Assigning a tower that
sits in another slot swaps the two, and tapping two slots in a row swaps them
directly — reordering by tap rather than by drag, because dragging a 141px
target onto another 141px target on a phone is a mis-hit waiting to happen and
this reuses the same tap-then-tap grammar as assignment. Every change saves
immediately, so there is no confirm step to forget.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: 最迫佈局截圖自查 + 全套驗收 + push

**Files:**
- Modify: `tools/art_export.gd`
- Create: `docs/superpowers/reports/2026-08-01-round9-report.md`

**Interfaces:**
- Consumes: 全部前面嘅 task

- [ ] **Step 1: 令 art_export 影到最迫佈局**

`tools/art_export.gd` `_unlock_all()` 尾加:

```gdscript
	# 快捷列六格全滿 —— 最迫嘅底欄佈局(15 魔法 + 6 塔槽 + 更多掣)先係要驗嘅
	# 嗰個狀態,四座初始塔加兩個空格證明唔到乜
	Meta.quick_slots = [1, 2, 5, 13, 7, 9]
```

- [ ] **Step 2: 影圖**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --path . tools/art_export.tscn -- --out=res://art_r9/ --locale=zh_TW --log-file "$PWD\art_r9.log"
Get-Content art_r9.log -Tail 5
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --path . tools/art_export.tscn -- --out=res://art_r9_en/ --locale=en --log-file "$PWD\art_r9_en.log"
Get-Content art_r9_en.log -Tail 5
```
Expected: 兩個 log 都有 `ART_EXPORT: DONE`,`art_r9/` 同 `art_r9_en/` 有 PNG

- [ ] **Step 3: 用 Read 睇圖自查**

Read 下面每張,逐項對:

- `art_r9/02_battle.png` 同 `art_r9_en/02_battle.png` — 快捷列七格,每格 icon +
  價錢睇得清、冇疊字、冇出界;快捷列同魔法列之間有肉眼可見嘅間隔
- `art_r9/03_battle_place.png` — 拖緊塔嗰陣快捷列仲喺度
- `art_r9/11_levelselect.png` — 第 7/13/18 關有骷髏 + 危險字樣,其他關冇
- `art_r9/10_fail.png` — 失敗畫面(如果佢影嘅係非牆關,提示唔應該出現)
- `art_r9_en/*` — **英文特別要睇**:英文塔名同 `More` / `Danger` 大約係中文嘅
  1.7 倍闊,呢個 repo 之前為咗英文字寬改過幾次佈局

見到問題就返去改對應嘅 task 檔案,重影,再睇。**唔准跳過呢一步就話「佈局冇問題」。**

- [ ] **Step 4: 跑晒全套測試**

```powershell
$tests = @("AudioTest","AudioHookTest","WallTest","BottomBarTest","RegressionTest",
           "SpellFlowTest","BossSpawnTest","BossHealTest","WinTest","LoseTest",
           "SpeedScaleTest","EconTest","FlowTest","I18nTest","BestiaryTest",
           "ScrollTest","StretchTest","SceneCheck","InputProbe")
$fail = @()
foreach ($t in $tests) {
  & "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . "res://test/$t.tscn" | Out-Host
  if ($LASTEXITCODE -ne 0) { $fail += "$t (exit $LASTEXITCODE)" }
}
if ($fail.Count -eq 0) { "ALL PASS" } else { "FAILED: " + ($fail -join ", ") }
```
Expected: `ALL PASS`。**有任何一個紅就要修到綠先繼續 —— 唔准喺報告寫「已知失敗」。**

- [ ] **Step 5: 5x 效能檢查(音效多咗 53 個,要確認冇拖低)**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --path . tools/perf5x.tscn --log-file "$PWD\perf_r9.log"
Get-Content perf_r9.log -Tail 10
```
Expected: 平均 fps 同上一輪(avg 161 / min 107)喺同一個水平。跌穿 min 55 就要查
係咪 `Audio` 個 pool 唔夠或者 dedup 冇生效。

- [ ] **Step 6: 重建 web export**

```powershell
& "C:\Users\User\Desktop\Jack\AI\Godot_v4.7.1-stable_win64.exe" --headless --path . --export-release "Web" "docs/index.html"
```
Expected: 冇 error;`docs/index.pck` 有更新時間

- [ ] **Step 7: 寫報告**

`docs/superpowers/reports/2026-08-01-round9-report.md`,內容必須有:
- **完整音效清單**:64 個名,每個一句描述(方便下次點名執邊個)
- **難度牆**:最終 `WALLS` 內容 + 每關通過率表(由 `sim_walls_r9.log` 抄)+ 用咗幾多 seed
- **一手勢起塔**:`Q` 組測試結果 + 最迫佈局截圖自查揾到咗乜、改咗乜
- **驗收清單**:逐項打勾,附證據(哪個 log / 哪張圖)
- **commit hash**

- [ ] **Step 8: Commit + push**

```bash
git add tools/art_export.gd docs/ perf_r9.log art_r9.log art_r9_en.log
git commit -m "$(cat <<'EOF'
Verify round 9 against the tightest layout and the whole suite, and rebuild web

art_export now fills all six quick slots before shooting, because the state
worth checking is fifteen spells plus six towers plus the More button sharing
the bottom of a 1080x1920 screen — four starters and two empty boxes prove
nothing about whether it fits.

Shot in both locales: English tower names and "More"/"Danger" run around 1.7x
the width of the 繁中 ones, and layout in this repo has been moved more than
once for exactly that.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push origin main
git log --oneline -1
```

- [ ] **Step 9: 將 commit hash 填返落報告,再 commit 一次**

```bash
git add docs/superpowers/reports/2026-08-01-round9-report.md
git commit -m "$(cat <<'EOF'
Record the round 9 commit hash in the report

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## 驗收清單(對返 spec)

- [ ] 音效總數 64(Task 1-5),`gen_audio.py --verify` 0 problems
- [ ] 由主選單到 boss 戰全程有聲(Task 6 `AudioHookTest`)
- [ ] 5x 唔炒耳(`AudioTest` D 組 dedup + Task 13 Step 5 perf)
- [ ] battle → boss BGM 喺小節線上、無縫(Task 5 `A` 組 + 同 BPM 同長度)
- [ ] 三幅牆 + 非牆關全部達標,附每關通過率表(Task 8)
- [ ] 選關危險標記 + 失敗剋制提示,兩種語言(Task 7 + 9)
- [ ] 一手勢起塔 test pass,全程冇開抽屜(Task 11 `Q` 組)
- [ ] 最迫佈局(15 魔法 + 6 塔槽)截圖自查完成,中英文都睇(Task 13 Step 3)
- [ ] 釘選重開遊戲保留(Task 10 `Q` round-trip + Task 12 `QB` 即時存檔)
- [ ] 測試套件全 pass(Task 13 Step 4)
- [ ] push GitHub,commit hash 喺報告(Task 13 Step 8-9)
