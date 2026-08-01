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
    # BGM bus
    "bgm_battle": bgm_battle,
}


def main(argv):
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
