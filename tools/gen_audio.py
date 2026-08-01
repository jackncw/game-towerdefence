#!/usr/bin/env python3
"""Original 8-bit / chiptune audio for Tower Fortress.

Everything here is synthesised from scratch with numpy — no samples, no
recordings, no third-party audio. Output goes to res://assets/generated_audio/
as 16-bit mono WAV at 44.1 kHz.

The shape mirrors tools/gen_art.py on purpose: a small stack of primitives
(oscillators, envelopes, effects) and then ONE function per sound, so any single
sound can be re-tuned without touching the others.

    python tools/gen_audio.py            # everything
    python tools/gen_audio.py ui_click   # just the named sounds

Naming is the contract with scripts/autoload/Audio.gd:
    ui_*      -> UI bus      sfx_*  -> SFX bus      bgm_*  -> BGM bus
"""

import os
import sys
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                   "..", "assets", "generated_audio")

# ---------------------------------------------------------------------------
# primitives
# ---------------------------------------------------------------------------


def t(dur):
    """Time axis for `dur` seconds."""
    return np.arange(int(SR * dur)) / SR


def _phase(freq, dur):
    """Instantaneous phase for a constant or per-sample frequency."""
    ts = t(dur)
    f = np.full_like(ts, float(freq)) if np.isscalar(freq) else np.asarray(freq)[:len(ts)]
    return 2.0 * np.pi * np.cumsum(f) / SR


def square(freq, dur, duty=0.5):
    """The 8-bit workhorse. duty 0.5 = hollow, 0.125 = thin and nasal."""
    ph = _phase(freq, dur) / (2.0 * np.pi)
    return np.where((ph % 1.0) < duty, 1.0, -1.0)


def triangle(freq, dur):
    ph = _phase(freq, dur) / (2.0 * np.pi)
    return 4.0 * np.abs((ph % 1.0) - 0.5) - 1.0


def saw(freq, dur):
    ph = _phase(freq, dur) / (2.0 * np.pi)
    return 2.0 * (ph % 1.0) - 1.0


def sine(freq, dur):
    return np.sin(_phase(freq, dur))


_rng = np.random.default_rng(0xA0D10)


def noise(dur):
    return _rng.uniform(-1.0, 1.0, int(SR * dur))


def sweep(f0, f1, dur, curve="exp"):
    """Per-sample frequency ramp, for pitch drops and rises."""
    ts = np.linspace(0.0, 1.0, int(SR * dur))
    if curve == "exp":
        return f0 * (f1 / f0) ** ts
    return f0 + (f1 - f0) * ts


def adsr(dur, a=0.005, d=0.05, s=0.6, r=0.08):
    """Attack/decay/sustain/release envelope, clamped to fit `dur`."""
    n = int(SR * dur)
    a_n, d_n, r_n = int(SR * a), int(SR * d), int(SR * r)
    if a_n + d_n + r_n > n:                       # squeeze to fit short sounds
        k = n / max(1, a_n + d_n + r_n)
        a_n, d_n, r_n = int(a_n * k), int(d_n * k), int(r_n * k)
    s_n = max(0, n - a_n - d_n - r_n)
    return np.concatenate([
        np.linspace(0.0, 1.0, a_n),
        np.linspace(1.0, s, d_n),
        np.full(s_n, s),
        np.linspace(s, 0.0, r_n),
    ])[:n]


def perc(dur, hold=0.0, curve=4.0):
    """Percussive envelope: instant attack, exponential fall."""
    ts = np.linspace(0.0, 1.0, int(SR * dur))
    env = np.exp(-curve * np.clip(ts - hold, 0.0, None) / max(1e-6, 1.0 - hold))
    env[:max(1, int(SR * 0.002))] *= np.linspace(0.0, 1.0, max(1, int(SR * 0.002)))
    return env


def lowpass(x, cutoff):
    """One-pole lowpass. Cheap, and cheap is the right flavour here."""
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    out = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc = (1.0 - a) * x[i] + a * acc
        out[i] = acc
    return out


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bitcrush(x, bits=6, downsample=1):
    """The single most 8-bit-sounding thing you can do to a waveform."""
    levels = 2 ** bits
    y = np.round(x * (levels / 2)) / (levels / 2)
    if downsample > 1:
        y = np.repeat(y[::downsample], downsample)[:len(x)]
    return y


def pad(x, dur):
    """Right-pad (or trim) to an exact length so sounds can be layered."""
    n = int(SR * dur)
    if len(x) >= n:
        return x[:n]
    return np.concatenate([x, np.zeros(n - len(x))])


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[:len(p)] += p
    return out


def seq(*parts):
    return np.concatenate(parts)


def norm(x, rms=0.10, ceiling=0.92):
    """Normalise to a target RMS, then clamp the peak.

    Peak normalisation was tried first and is wrong for a sound set: a 0.05s
    click and a 0.34s sustained beam hit the same peak but the beam carries four
    times the energy, so peak-matching made the UI click the loudest thing in
    the game and buried the tower fire under it. RMS is what the ear tracks.
    """
    cur = float(np.sqrt(np.mean(x * x)))
    if cur < 1e-9:
        return x
    y = x * (rms / cur)
    m = float(np.max(np.abs(y)))
    if m > ceiling:
        y *= ceiling / m
    return y


def fade_edges(x, ms=3.0):
    """Kill click artifacts at the very start/end of a clip."""
    n = min(len(x) // 2, int(SR * ms / 1000.0))
    if n < 2:
        return x
    x = x.copy()
    x[:n] *= np.linspace(0.0, 1.0, n)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x


## Per-sound loudness, in target RMS. These are RELATIVE levels inside a bus —
## the player's sliders set the absolute volume. Attack sounds sit low because a
## busy field at 5x fires dozens of them a second; the UI click sits low for the
## same reason; the error and the BGM sit where they can be noticed without
## dominating.
LOUDNESS = {
    "ui_click": 0.09,
    "ui_panel_open": 0.11,
    "ui_panel_close": 0.11,
    "ui_error": 0.15,
    "bgm_battle": 0.085,
    # 死亡 / 受擊:5x 之下一秒幾十次,坐低過攻擊聲先唔會蓋住成場
    **{("sfx_die_%s" % f): 0.085 for f in
       ["goblin", "wolf", "skeleton", "golem", "ghost", "bat",
        "treant", "beetle", "cultist", "slime"]},
    "sfx_hit_soft": 0.055, "sfx_hit_hard": 0.070, "sfx_hit_magic": 0.060,
    # 大魔法要有份量,但仲係要坐喺 jingle 之下
    "sfx_spell_meteor": 0.13, "sfx_spell_quake": 0.13,
    "sfx_spell_blackhole": 0.13, "sfx_spell_freezenova": 0.12,
    # 環境聲,唔係事件聲 —— 唔應該同攻擊搶
    "sfx_aura_curse": 0.06, "sfx_field_slow": 0.06,
}
DEFAULT_LOUDNESS = 0.10          # every sfx_atk_* archetype


def save(name, x):
    x = fade_edges(norm(x, LOUDNESS.get(name, DEFAULT_LOUDNESS)))
    data = np.clip(x, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    return path, len(data) / SR


# --- musical helpers --------------------------------------------------------
def note(n):
    """MIDI note number -> Hz. 69 = A4 = 440."""
    return 440.0 * 2.0 ** ((n - 69) / 12.0)


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------


def ui_click():
    """Generic button press. Short, bright, gets out of the way — this one
    plays more often than any other sound in the game."""
    d = 0.055
    body = square(sweep(1180, 880, d), d, duty=0.25) * perc(d, curve=7.0)
    return bitcrush(body, bits=6) * 0.7


def ui_panel_open():
    """Drawer / panel sliding open: two-step rising blip."""
    a = square(660, 0.045, duty=0.5) * perc(0.045, curve=6.0)
    b = square(990, 0.075, duty=0.5) * perc(0.075, curve=5.0)
    return bitcrush(seq(a, b), bits=6) * 0.6


def ui_panel_close():
    """Same figure, falling — open and close have to be each other's mirror or
    the pair reads as two unrelated noises."""
    a = square(990, 0.045, duty=0.5) * perc(0.045, curve=6.0)
    b = square(660, 0.075, duty=0.5) * perc(0.075, curve=5.0)
    return bitcrush(seq(a, b), bits=6) * 0.6


def ui_error():
    """Refusal: not enough gold, spell on cooldown, illegal build spot. Low,
    buzzy, unmistakably negative, and short enough to spam without hurting."""
    d = 0.20
    body = square(sweep(220, 150, d, "lin"), d, duty=0.5) * adsr(d, 0.002, 0.02, 0.7, 0.09)
    grind = square(sweep(110, 74, d, "lin"), d, duty=0.125) * 0.5
    return bitcrush(body + grind * adsr(d, 0.002, 0.02, 0.7, 0.09), bits=5) * 0.55


# ---------------------------------------------------------------------------
# tower attacks — six archetypes, varied per tower by Audio.gd's pitch spread
# ---------------------------------------------------------------------------


def sfx_atk_arrow():
    """Bow/bolt: a noise thwip with a fast downward whistle over it."""
    d = 0.12
    air = highpass(noise(d), 1800.0) * perc(d, curve=12.0) * 0.5
    whistle = triangle(sweep(2400, 900, d), d) * perc(d, curve=9.0) * 0.5
    return bitcrush(air + whistle, bits=7)


def sfx_atk_cannon():
    """Heavy shot: body thump plus a burst of low noise."""
    d = 0.34
    thump = square(sweep(180, 46, d), d, duty=0.5) * perc(d, curve=5.5)
    boom = lowpass(noise(d), 900.0) * perc(d, curve=4.0) * 0.9
    return bitcrush(thump * 0.8 + boom, bits=6)


def sfx_atk_electric():
    """Zap: square carrier whose pitch jitters on a grid, which is how the NES
    faked noise-pitched effects and reads instantly as electricity."""
    d = 0.22
    steps = 26
    f = np.repeat(_rng.uniform(700, 2600, steps), int(SR * d / steps) + 1)[:int(SR * d)]
    body = square(f, d, duty=0.125) * perc(d, curve=6.0)
    fizz = highpass(noise(d), 3000.0) * perc(d, curve=9.0) * 0.35
    return bitcrush(body + fizz, bits=5)


def sfx_atk_fire():
    """Whoosh: filtered noise that opens up then closes, no tonal centre."""
    d = 0.30
    n = noise(d)
    body = lowpass(n, 2200.0) - lowpass(n, 400.0)      # crude bandpass
    swell = np.sin(np.linspace(0.0, np.pi, len(body))) ** 1.4
    growl = triangle(sweep(150, 80, d), d) * perc(d, curve=4.0) * 0.35
    return bitcrush(body * swell * 0.9 + growl, bits=6)


def sfx_atk_frost():
    """Crystalline: a bright triangle chime with a shimmering upper partial."""
    d = 0.26
    base = triangle(sweep(1500, 1180, d), d) * perc(d, curve=5.0)
    shimmer = triangle(sweep(3000, 2360, d), d) * perc(d, curve=8.0) * 0.4
    tick = highpass(noise(0.03), 5000.0) * perc(0.03, curve=14.0) * 0.5
    return bitcrush(mix(base + shimmer, pad(tick, d)), bits=7)

def sfx_atk_beam():
    """Sustained emitter: a saw with vibrato. The only archetype that holds a
    note, so beam/laser towers do not sound like they are firing pellets."""
    d = 0.34
    vib = 1.0 + 0.035 * np.sin(2.0 * np.pi * 22.0 * t(d))
    body = saw(760.0 * vib, d) * adsr(d, 0.02, 0.06, 0.8, 0.10)
    sub = square(380, d, duty=0.5) * adsr(d, 0.02, 0.06, 0.6, 0.10) * 0.4
    return bitcrush(body * 0.7 + sub, bits=5)


# ---------------------------------------------------------------------------
# tower attacks — five bespoke ones. Each of these mechanics reads as
# something other than a bow (a spray, a spinning return, a spike, a pulse, a
# phase-shift), so re-pitching sfx_atk_arrow for them just sounds like an
# out-of-tune arrow tower instead of its own thing.
# ---------------------------------------------------------------------------


def sfx_atk_poison():
    """Poison spray: crude bandpassed noise (the wet spray itself) plus a
    falling sine underneath for a sticky low body — the low layer is what
    separates this from sfx_atk_fire's whoosh, which has no tonal centre."""
    d = 0.20
    n = noise(d)
    spray = (lowpass(n, 1400.0) - lowpass(n, 350.0)) * perc(d, curve=5.0)
    ooze = sine(sweep(200.0, 130.0, d), d) * perc(d, curve=6.0) * 0.35
    return bitcrush(spray + ooze, bits=6)


def sfx_atk_boomerang():
    """Boomerang: a rising triangle whirr amplitude-modulated at 14Hz so it
    reads as something spinning through the air, not a straight shot — the
    rotation modulation is the one thing that tells it apart from a bow."""
    d = 0.26
    body = triangle(sweep(600.0, 900.0, d, "lin"), d)
    spin = 0.45 + 0.55 * np.sin(2.0 * np.pi * 14.0 * t(d))
    return bitcrush(body * spin * perc(d, curve=3.5), bits=7)


def sfx_atk_thorn():
    """Thorn spike: a thin rising square snap plus a very short high-noise
    tick layered at the front for the spike physically popping out."""
    d = 0.14
    snap = square(sweep(1500.0, 2200.0, d, "lin"), d, duty=0.125) * perc(d, curve=12.0)
    tick = highpass(noise(0.05), 4000.0) * perc(0.05, curve=15.0) * 0.5
    out = snap.copy()
    out[:len(tick)] += tick
    return bitcrush(out, bits=7)


def sfx_atk_magnet():
    """Magnet pulse: a rising sine sub plus a mid square layer, both low and
    with no high end at all — the pull is felt, not heard as a click."""
    d = 0.28
    sub = sine(sweep(90.0, 240.0, d, "lin"), d) * perc(d, curve=4.0)
    body = square(180, d, duty=0.5) * perc(d, curve=5.0) * 0.35
    return bitcrush(sub + body, bits=6)


def sfx_atk_teleport():
    """Teleport: a fast rising square (the target vanishing) with a falling
    square layered under it (arriving elsewhere) — the pair is what reads as
    a phase-shift rather than a shot. bits=4 for the roughest crush in the
    tower set, matching a system snapping through space rather than firing."""
    d = 0.18
    out_rise = square(sweep(400.0, 3000.0, d), d, duty=0.125) * perc(d, curve=6.0)
    in_fall = square(sweep(3000.0, 400.0, d), d, duty=0.125) * perc(d, curve=8.0) * 0.4
    return bitcrush(out_rise + in_fall, bits=4)


# ---------------------------------------------------------------------------
# tower non-attack events — barracks spawn, curse aura refresh, slowfield
# pulse. None of these three towers has a discrete shot, so they get sounds
# tied to their actual events instead of an archetype (wired in a later task).
# ---------------------------------------------------------------------------


def sfx_tower_barracks():
    """Muster call: a two-note rising horn call on soldier spawn — a fifth
    apart (note 57 -> 64), which reads as a call/response fanfare rather
    than a single blip repeating."""
    a = square(note(57), 0.12, duty=0.25) * adsr(0.12, 0.01, 0.03, 0.8, 0.04)
    b = square(note(64), 0.18, duty=0.25) * adsr(0.18, 0.01, 0.03, 0.7, 0.06)
    return bitcrush(seq(a, b), bits=6)


def sfx_aura_curse():
    """Curse aura refresh: a slow low drone — long attack/release ADSR so it
    never snaps in or out, because this fires on every aura tick and has to
    sit under the mix rather than announce itself like an attack does."""
    d = 0.50
    body = saw(sweep(110.0, 88.0, d), d) * adsr(d, 0.12, 0.10, 0.55, 0.20)
    sub = triangle(note(45), d) * adsr(d, 0.12, 0.1, 0.5, 0.2) * 0.4
    return bitcrush(body + sub, bits=6)


def sfx_field_slow():
    """Slowfield pulse: a falling triangle tone with a slow 5Hz breathing
    tremolo over it, so a repeating field pulse reads as one living thing
    breathing rather than a metronome click."""
    d = 0.44
    body = triangle(sweep(340.0, 250.0, d), d) * adsr(d, 0.08, 0.08, 0.6, 0.16)
    breath = 1.0 + 0.18 * np.sin(2.0 * np.pi * 5.0 * t(d))
    return bitcrush(body * breath, bits=6)


# ---------------------------------------------------------------------------
# monster deaths — one per family, so the player can tell WHAT died by ear
# alone at 5x, when there is no time to look
# ---------------------------------------------------------------------------


def sfx_die_goblin():
    """Goblin death: a thin shriek with a short hiss stapled onto the tail —
    the hiss is the only part above 3kHz, so it reads as breath/spit, not
    an echo of the shriek itself."""
    d = 0.22
    scream = square(sweep(900, 300, d), d, duty=0.125) * perc(d, curve=8.0)
    tail = highpass(noise(0.05), 3000.0) * perc(0.05, curve=12.0) * 0.4
    out = scream.copy()
    out[-len(tail):] += tail
    return bitcrush(out, bits=6)


def sfx_die_wolf():
    """Wolf death: a falling howl. The vibrato is applied AFTER the envelope
    so it modulates the sustain, not the attack — a howl wavers once it is
    already holding a note, not from the first instant."""
    d = 0.34
    howl = saw(sweep(420, 160, d), d) * adsr(d, 0.01, 0.06, 0.5, 0.18)
    vibrato = 1.0 + 0.25 * np.sin(2.0 * np.pi * 7.0 * t(d))
    return bitcrush(howl * vibrato, bits=6)


def sfx_die_skeleton():
    """Skeleton death: six dry clicks at random moments across the clip, no
    bass under any of them — bones rattling apart, not a drum hit."""
    d = 0.30
    n_total = int(SR * d)
    click_len = 0.04
    out = np.zeros(n_total)
    offsets = np.sort(_rng.uniform(0.0, d - click_len, 6))
    for i in range(6):
        click = square(note(72 - 4 * i), click_len, duty=0.25) * perc(click_len, curve=14.0)
        start = int(SR * offsets[i])
        end = min(n_total, start + len(click))
        out[start:end] += click[:end - start]
    return bitcrush(out, bits=6)


def sfx_die_golem():
    """Golem death: a bed of low rubble noise with three stone thuds landing
    at staggered moments over it, like a body breaking apart in pieces
    rather than all at once."""
    d = 0.42
    out = lowpass(noise(d), 700.0) * perc(d, curve=3.5)
    thud = sine(sweep(120, 40, 0.08), 0.08) * perc(0.08, curve=9.0)
    for offset in (0.02, 0.14, 0.27):
        start = int(SR * offset)
        end = min(len(out), start + len(thud))
        out[start:end] += thud[:end - start]
    return bitcrush(out, bits=6)


def sfx_die_ghost():
    """Ghost death: dissolving, not striking — the only death sound with no
    attack at all. It fades IN over the first 80ms before the pitch-rising
    body even starts its own decay, so the whole thing reads as materialising
    out of nothing and then thinning away."""
    d = 0.46
    n = int(SR * d)
    body = triangle(sweep(700, 1800, d), d) * (np.linspace(1.0, 0.0, n) ** 2)
    fade_in = np.linspace(0.0, 1.0, int(SR * 0.08))
    body[:len(fade_in)] *= fade_in
    hiss = highpass(noise(d), 4000.0) * 0.15
    return bitcrush(body + hiss, bits=6)


def sfx_die_bat():
    """Bat death: a short high squeak. bits=5 rather than the usual 6 — at
    this pitch the extra crush reads as a screech instead of adding noise."""
    d = 0.16
    body = square(sweep(2600, 1400, d), d, duty=0.125) * perc(d, curve=11.0)
    return bitcrush(body, bits=5)


def sfx_die_treant():
    """Treant death: a crisp snap up front, then a slow falling groan for the
    rest of the clip — a tree splintering and then toppling, not one noise."""
    d = 0.40
    crack = highpass(noise(0.06), 2000.0) * perc(0.06, curve=16.0)
    fall = triangle(sweep(220, 70, d), d) * perc(d, curve=4.0)
    return bitcrush(mix(pad(crack, d), fall), bits=6)


def sfx_die_beetle():
    """Beetle death: a brittle shell crack followed by a short crunch, both
    padded to the full clip length so the crunch's silence-tail is part of
    the sound instead of getting truncated."""
    d = 0.24
    crack = highpass(noise(0.08), 2500.0) * perc(0.08, curve=13.0) * 0.9
    crunch = square(sweep(520, 180, 0.18), 0.18, duty=0.5) * perc(0.18, curve=7.0)
    return bitcrush(mix(pad(crack, d), pad(crunch, d)), bits=6)


def sfx_die_cultist():
    """Cultist death: a held chant note that snaps into a falling, decaying
    wail — seq() rather than mix() because the chant has to visibly stop
    before the death cry starts, not blend into it."""
    d1, d2 = 0.16, 0.22
    chant = saw(note(57), d1) * adsr(d1, 0.02, 0.04, 0.8, 0.04)
    cutoff = saw(sweep(note(57), note(45), d2), d2) * perc(d2, curve=6.0)
    return bitcrush(seq(chant, cutoff), bits=6)


def sfx_die_slime():
    """Slime death: a wet low burst with a slow pitch-falling wobble under
    it, no high end anywhere — the one death sound that is all body and
    no crack or hiss, because slime has neither bone nor shell to break."""
    d = 0.30
    burst = lowpass(noise(d), 1100.0) * perc(d, curve=5.0)
    wobble = sine(sweep(300, 60, d), d) * perc(d, curve=4.0) * 0.7
    return bitcrush(burst + wobble, bits=6)


# ---------------------------------------------------------------------------
# hits — picked by the target's defence (armour / magic resist), not by the
# attacker's damage type, so the player hears "is this thing tough" directly
# ---------------------------------------------------------------------------


def sfx_hit_soft():
    """Unarmoured hit: a quick low thud with barely any tone under it."""
    d = 0.07
    thud = lowpass(noise(d), 1800.0) * perc(d, curve=14.0) * 0.8
    tone = square(420, d, duty=0.5) * perc(d, curve=16.0) * 0.4
    return bitcrush(thud + tone, bits=6)


def sfx_hit_hard():
    """Armoured hit: a clank rather than a thud — lower noise cutoff, a
    falling metallic tone, and bits=5 for extra grit on impact."""
    d = 0.10
    clank = lowpass(noise(d), 900.0) * perc(d, curve=10.0)
    tone = square(sweep(260, 150, d), d, duty=0.5) * perc(d, curve=9.0)
    return bitcrush(clank + tone, bits=5)


def sfx_hit_magic():
    """Ward hit: a bright falling chime with a burst of high hiss — the only
    hit sound with no low end at all, so it never gets confused with soft
    or hard on a busy field."""
    d = 0.09
    chime = triangle(sweep(1800, 1150, d), d) * perc(d, curve=12.0)
    sparkle = highpass(noise(d), 5000.0) * perc(d, curve=16.0) * 0.35
    return bitcrush(chime + sparkle, bits=6)


# ---------------------------------------------------------------------------
# spells — fifteen of them, each its own sound (no shared archetype). A spell
# fires a handful of times a match and every cast is a deliberate choice, so
# unlike tower fire it earns its own timbre instead of a re-pitched one.
# ---------------------------------------------------------------------------


def sfx_spell_meteor():
    """Meteor: a rising whistle as the rock falls, then a heavy low impact.
    seq() not mix() — the whistle has to finish arriving before the impact
    lands, or the fall and the hit blur into one noise instead of reading
    as two events in sequence."""
    whistle = lowpass(noise(0.35), 1500.0) * np.linspace(0.0, 1.0, int(SR * 0.35)) ** 2
    body = sine(sweep(180, 30, 0.40), 0.40) * perc(0.40, curve=3.5)
    boom = lowpass(noise(0.40), 600.0) * perc(0.40, curve=3.0)
    return bitcrush(seq(whistle, body + boom), bits=6)


def sfx_spell_stormbolt():
    """Storm bolt: seven quick strikes, each a different random pitch — like
    sfx_atk_electric's jitter trick but applied once per strike instead of
    within one, so the bolts read as seven discrete hits, not one buzz."""
    d = 0.30
    hit_len = 0.035
    n_total = int(SR * d)
    out = np.zeros(n_total)
    for i in range(7):
        f = _rng.uniform(900, 2800)
        hit = square(f, hit_len, duty=0.125) * perc(hit_len, curve=10.0)
        start = int(SR * i * hit_len)
        end = min(n_total, start + len(hit))
        out[start:end] += hit[:end - start]
    return bitcrush(out, bits=5)


def sfx_spell_freezenova():
    """Freeze nova: two ringing triangle sweeps (fundamental plus a bright
    upper partial) over a short crack at the very front — the crack is the
    ice sheet breaking outward, the sweeps are the cold ringing after."""
    d = 0.60
    body = triangle(sweep(2600, 900, d), d) * perc(d, curve=3.0)
    shimmer = triangle(sweep(5200, 1800, d), d) * perc(d, curve=5.0) * 0.35
    crack = lowpass(noise(0.10), 800.0) * perc(0.10, curve=6.0) * 0.6
    return bitcrush(mix(body + shimmer, pad(crack, d)), bits=6)


def sfx_spell_miasma():
    """Miasma: a bandpassed hiss that swells and fades — the poison cloud
    spreading out then settling — over a low sawtooth growl for weight, so
    it does not read as pure hiss with nothing underneath it."""
    d = 0.42
    n = noise(d)
    hiss = (lowpass(n, 900.0) - lowpass(n, 200.0)) * np.sin(np.linspace(0.0, np.pi, len(n)))
    growl = saw(sweep(90, 60, d), d) * perc(d, curve=3.0) * 0.4
    return bitcrush(hiss + growl, bits=6)


def sfx_spell_summon():
    """Summon: a rising three-note fanfare (root, major third, fifth) with a
    trail of high magic dust laid under the whole thing — the dust is what
    tells the ear "magic", the notes are what tell it "arriving"."""
    notes = seq(*[square(note(57 + k), 0.10, duty=0.25) * perc(0.10, curve=7.0)
                  for k in (0, 4, 7)])
    dust = highpass(noise(0.34), 4000.0) * perc(0.34, curve=5.0) * 0.2
    return bitcrush(mix(notes, dust), bits=6)


def sfx_spell_midas():
    """Midas touch: five coin chimes at random pitches landing at random
    moments, like a small pile of gold hitting the ground rather than one
    coordinated jingle — bits=7 keeps them bright instead of grainy."""
    d = 0.30
    coin_len = 0.05
    n_total = int(SR * d)
    out = np.zeros(n_total)
    offsets = np.sort(_rng.uniform(0.0, d - coin_len, 5))
    for off in offsets:
        coin = triangle(note(84 + _rng.integers(-3, 4)), coin_len) * perc(coin_len, curve=12.0)
        start = int(SR * off)
        end = min(n_total, start + len(coin))
        out[start:end] += coin[:end - start]
    return bitcrush(out, bits=7)


def sfx_spell_timewarp():
    """Time warp: a falling sawtooth under a slow 3Hz wobble. The wobble is
    slow enough to read as time itself dragging, not as ordinary tremolo —
    a faster rate here would sound like an effect instead of the mechanic."""
    d = 0.44
    body = saw(sweep(700, 180, d), d) * adsr(d, 0.02, 0.08, 0.6, 0.14)
    wobble = 1.0 + 0.15 * np.sin(2.0 * np.pi * 3.0 * t(d))
    return bitcrush(body * wobble, bits=6)


def sfx_spell_warcry():
    """War cry: a rising square shout with a low noise rasp under it for a
    voice-like texture — a pure tone alone read as a siren, not a shout."""
    d = 0.36
    shout = square(sweep(300, 460, d, "lin"), d, duty=0.5) * adsr(d, 0.01, 0.05, 0.8, 0.10)
    rasp = lowpass(noise(d), 1200.0) * perc(d, curve=4.0) * 0.35
    return bitcrush(shout + rasp, bits=6)


def sfx_spell_barrier():
    """Barrier: a rising tone that settles into a held, steady hum — seq()
    because a shield snapping up has a distinct rise and then a sustain,
    not one continuously-changing pitch."""
    rise = sine(sweep(300, 620, 0.18), 0.18) * perc(0.18, curve=5.0)
    hold = triangle(620, 0.22) * adsr(0.22, 0.01, 0.03, 0.85, 0.08)
    return bitcrush(seq(rise, hold), bits=6)


def sfx_spell_tornado():
    """Tornado: bandpassed noise amplitude-modulated at 9Hz so it reads as
    something spinning rather than a static gust of wind."""
    d = 0.40
    n = noise(d)
    body = lowpass(n, 2400.0) - lowpass(n, 500.0)
    spin = 0.5 + 0.5 * np.sin(2.0 * np.pi * 9.0 * t(d))
    return bitcrush(body * spin, bits=6)


def sfx_spell_quake():
    """Earthquake: a deep falling sine as the main shock plus a rumbling
    noise bed under it, with three short rubble ticks scattered on top —
    grit settling after the shock rather than one flat rumble."""
    d = 0.70
    body = sine(sweep(70, 26, d), d) * perc(d, curve=2.5)
    rumble = lowpass(noise(d), 400.0) * perc(d, curve=2.2) * 0.8
    out = body + rumble
    rubble = highpass(noise(0.05), 2500.0) * perc(0.05, curve=13.0) * 0.5
    for offset in (0.15, 0.35, 0.55):
        start = int(SR * offset)
        end = min(len(out), start + len(rubble))
        out[start:end] += rubble[:end - start]
    return bitcrush(out, bits=6)


def sfx_spell_firewall():
    """Firewall: bandpassed noise that swells in from nothing — the burn
    spreading down the line rather than igniting all at once — under a low
    triangle growl for weight."""
    d = 0.44
    n = noise(d)
    body = lowpass(n, 2000.0) - lowpass(n, 300.0)
    swell = np.linspace(0.0, 1.0, len(body)) ** 0.6
    growl = triangle(sweep(160, 110, d), d) * perc(d, curve=3.0) * 0.35
    return bitcrush(body * swell + growl, bits=6)


def sfx_spell_smite():
    """Smite: a short bright crack (the strike landing) then a held root +
    fifth chord ringing out — the open fifth is what makes it read as holy
    rather than violent, the way the crack alone would."""
    strike = saw(note(81), 0.06) * perc(0.06, curve=9.0)
    root = triangle(note(69), 0.28) * adsr(0.28, 0.005, 0.05, 0.7, 0.12)
    fifth = triangle(note(76), 0.28) * adsr(0.28, 0.005, 0.05, 0.7, 0.12) * 0.5
    return bitcrush(seq(strike, root + fifth), bits=6)


def sfx_spell_emp():
    """EMP: a square wave falling almost three octaves across the clip, plus
    a burst of high static at the front — bits=4 is the roughest crush in
    the whole set, matching a system getting fried rather than struck."""
    d = 0.28
    drop = square(sweep(2200, 120, d), d, duty=0.125) * perc(d, curve=5.0)
    zap = highpass(noise(0.06), 3500.0) * perc(0.06, curve=14.0) * 0.5
    out = drop.copy()
    out[:len(zap)] += zap
    return bitcrush(out, bits=4)


def sfx_spell_blackhole():
    """Black hole: a rising saw pulled inward, then a falling sine as it
    collapses — seq() so the pull and the collapse read as two distinct
    phases — with a constant low rumble mixed under the full 0.80s so the
    field never drops out silent between them."""
    d = 0.80
    pull = saw(sweep(120, 900, 0.55), 0.55) * np.linspace(0.0, 1.0, int(SR * 0.55)) ** 1.5
    collapse = sine(sweep(900, 40, 0.25), 0.25) * perc(0.25, curve=4.0)
    body = seq(pull, collapse)
    rumble = lowpass(noise(d), 300.0) * 0.3
    return bitcrush(mix(body, rumble), bits=6)


# ---------------------------------------------------------------------------
# BGM
# ---------------------------------------------------------------------------


def _bgm_track(root, prog, bars, bpm, lead_pattern, duty=0.25):
    """One chiptune loop: bass + arpeggio + lead + noise drums.

    `prog` is a list of scale-degree offsets, one per bar. Everything is built
    from the same square/triangle/noise primitives as the sound effects so the
    music and the SFX share a timbre family.
    """
    spb = 60.0 / bpm                      # seconds per beat
    beats = 4
    bar_len = spb * beats
    total = bar_len * bars
    n_total = int(SR * total)

    bass = np.zeros(n_total)
    arp = np.zeros(n_total)
    lead = np.zeros(n_total)
    drum = np.zeros(n_total)

    def place(buf, x, at):
        i = int(SR * at)
        j = min(n_total, i + len(x))
        buf[i:j] += x[:j - i]

    for b in range(bars):
        off = prog[b % len(prog)]
        bar_t = b * bar_len
        chord = [root + off, root + off + 3, root + off + 7]      # minor triad
        # bass: root on every beat, octave down, short and punchy
        for k in range(beats):
            d = spb * 0.9
            v = square(note(chord[0] - 12), d, duty=0.5) * perc(d, curve=5.0) * 0.55
            place(bass, v, bar_t + k * spb)
        # arpeggio: eighth notes cycling the triad
        for k in range(beats * 2):
            d = spb * 0.45
            nn = chord[k % 3]
            v = triangle(note(nn), d) * perc(d, curve=6.0) * 0.28
            place(arp, v, bar_t + k * spb * 0.5)
        # lead melody
        for (beat, deg, ln) in lead_pattern:
            d = spb * ln
            v = square(note(root + off + deg + 12), d, duty=duty) \
                * adsr(d, 0.005, 0.04, 0.55, 0.06) * 0.34
            place(lead, v, bar_t + beat * spb)
        # drums: kick on 1 and 3, hat on the offbeats
        for k in (0, 2):
            d = 0.14
            v = sine(sweep(150, 48, d), d) * perc(d, curve=7.0) * 0.6
            place(drum, v, bar_t + k * spb)
        for k in range(beats):
            d = 0.05
            v = highpass(noise(d), 6000.0) * perc(d, curve=13.0) * 0.16
            place(drum, v, bar_t + k * spb + spb * 0.5)

    return bitcrush(bass + arp + lead + drum, bits=7)


def bgm_battle():
    """Combat loop: driving, minor, and deliberately unobtrusive in the mid
    range so tower fire and monster deaths still cut through."""
    lead = [(0, 0, 0.5), (0.5, 3, 0.5), (1, 7, 1.0), (2, 5, 0.5),
            (2.5, 3, 0.5), (3, 0, 1.0)]
    return _bgm_track(root=57, prog=[0, 0, 5, 3], bars=8, bpm=132,
                      lead_pattern=lead, duty=0.25) * 0.8


# ---------------------------------------------------------------------------
SOUNDS = {
    # UI bus
    "ui_click": ui_click,
    "ui_panel_open": ui_panel_open,
    "ui_panel_close": ui_panel_close,
    "ui_error": ui_error,
    # SFX bus — tower attack archetypes
    "sfx_atk_arrow": sfx_atk_arrow,
    "sfx_atk_cannon": sfx_atk_cannon,
    "sfx_atk_electric": sfx_atk_electric,
    "sfx_atk_fire": sfx_atk_fire,
    "sfx_atk_frost": sfx_atk_frost,
    "sfx_atk_beam": sfx_atk_beam,
    # SFX bus — tower attack, bespoke (mechanic doesn't fit an archetype)
    "sfx_atk_poison": sfx_atk_poison,
    "sfx_atk_boomerang": sfx_atk_boomerang,
    "sfx_atk_thorn": sfx_atk_thorn,
    "sfx_atk_magnet": sfx_atk_magnet,
    "sfx_atk_teleport": sfx_atk_teleport,
    # SFX bus — tower non-attack events (spawn / aura / field pulse)
    "sfx_tower_barracks": sfx_tower_barracks,
    "sfx_aura_curse": sfx_aura_curse,
    "sfx_field_slow": sfx_field_slow,
    # SFX bus — monster deaths, one per family
    "sfx_die_goblin": sfx_die_goblin,
    "sfx_die_wolf": sfx_die_wolf,
    "sfx_die_skeleton": sfx_die_skeleton,
    "sfx_die_golem": sfx_die_golem,
    "sfx_die_ghost": sfx_die_ghost,
    "sfx_die_bat": sfx_die_bat,
    "sfx_die_treant": sfx_die_treant,
    "sfx_die_beetle": sfx_die_beetle,
    "sfx_die_cultist": sfx_die_cultist,
    "sfx_die_slime": sfx_die_slime,
    # SFX bus — hits, by target defence
    "sfx_hit_soft": sfx_hit_soft,
    "sfx_hit_hard": sfx_hit_hard,
    "sfx_hit_magic": sfx_hit_magic,
    # SFX bus — spells, one per spell (no shared archetype)
    "sfx_spell_meteor": sfx_spell_meteor,
    "sfx_spell_stormbolt": sfx_spell_stormbolt,
    "sfx_spell_freezenova": sfx_spell_freezenova,
    "sfx_spell_miasma": sfx_spell_miasma,
    "sfx_spell_summon": sfx_spell_summon,
    "sfx_spell_midas": sfx_spell_midas,
    "sfx_spell_timewarp": sfx_spell_timewarp,
    "sfx_spell_warcry": sfx_spell_warcry,
    "sfx_spell_barrier": sfx_spell_barrier,
    "sfx_spell_tornado": sfx_spell_tornado,
    "sfx_spell_quake": sfx_spell_quake,
    "sfx_spell_firewall": sfx_spell_firewall,
    "sfx_spell_smite": sfx_spell_smite,
    "sfx_spell_emp": sfx_spell_emp,
    "sfx_spell_blackhole": sfx_spell_blackhole,
    # BGM bus
    "bgm_battle": bgm_battle,
}


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


def main(argv):
    if len(argv) > 1 and argv[1] == "--verify":
        return verify()
    want = argv[1:] if len(argv) > 1 else sorted(SOUNDS)
    unknown = [w for w in want if w not in SOUNDS]
    if unknown:
        print("unknown sound(s): %s" % ", ".join(unknown))
        print("available: %s" % ", ".join(sorted(SOUNDS)))
        return 1
    total = 0.0
    for name in want:
        path, dur = save(name, SOUNDS[name]())
        total += dur
        print("  %-20s %5.2fs  %s" % (name, dur, os.path.relpath(path, os.getcwd())))
    print("%d sound(s), %.1fs total" % (len(want), total))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
