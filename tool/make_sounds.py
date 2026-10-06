#!/usr/bin/env python3
"""Build every sound in the game from nothing, with ffmpeg.

    python3 tool/make_sounds.py

Writes assets/sounds/*.wav — mono, 22,050 Hz, 16-bit.

WHY SYNTHESIZED. Every sound here is made from noise and sine waves by the
recipes below, so the game owns all of it outright: no licence to track, no
attribution to keep, nothing that can be taken down. It also means none of it
was chosen by ear — whoever wrote this could not hear the result. Treat each
recipe as a first draft. ANY FILE CAN BE REPLACED by dropping a recorded sound
of the same name into assets/sounds/; nothing in the game cares where it came
from. Re-running this script overwrites them, so keep replacements somewhere
else too.

WHY WAV. It is the one format every target plays without argument — Android,
Chrome, Firefox and Safari all decode it — and it loops without the silent
padding MP3 encoders add. The cost is size: the three ambient loops are most
of the total. They are kept short and at 22kHz for that reason.

WHY FFMPEG. It was already on the machine, it generates noise and arbitrary
waveforms (anoisesrc, aevalsrc) and filters them, and a recipe is one line.
Python's standard library does the rest: peak levels, the seam on the loops,
and click-free edges on the one-shots.
"""

import array
import math
import os
import random
import subprocess
import sys
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'sounds')


def render(graph, seconds):
    """Run an ffmpeg filtergraph and return its samples as a list of ints."""
    cmd = [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', graph,
        '-t', str(seconds), '-ac', '1', '-ar', str(RATE),
        '-f', 's16le', '-',
    ]
    raw = subprocess.run(cmd, check=True, capture_output=True).stdout
    a = array.array('h')
    a.frombytes(raw)
    return list(a)


def render_over(layer, graph, seconds):
    """Like render(), but with a layer built in Python fed in as input [0].

    For sounds that are made of EVENTS rather than a continuous signal —
    raindrops — which an ffmpeg expression cannot scatter at random times.
    """
    top = max(1e-9, max(abs(x) for x in layer))
    raw = array.array('h', (int(x / top * 30000) for x in layer)).tobytes()
    cmd = [
        'ffmpeg', '-hide_banner', '-loglevel', 'error',
        '-f', 's16le', '-ar', str(RATE), '-ac', '1', '-i', '-',
        '-filter_complex', graph,
        '-t', str(seconds), '-ac', '1', '-ar', str(RATE),
        '-f', 's16le', '-',
    ]
    out = subprocess.run(cmd, input=raw, check=True, capture_output=True).stdout
    a = array.array('h')
    a.frombytes(out)
    return list(a)


def normalise(samples, peak_db):
    """Scale to a target peak, in dB below full scale."""
    top = max(1, max(abs(s) for s in samples))
    gain = (32767 * 10 ** (peak_db / 20)) / top
    return [int(max(-32768, min(32767, s * gain))) for s in samples]


def edges(samples, fade_in=0.004, fade_out=0.05):
    """Ramp the very ends, so a one-shot never starts or stops on a click."""
    n_in = int(RATE * fade_in)
    n_out = int(RATE * fade_out)
    out = samples[:]
    for i in range(min(n_in, len(out))):
        out[i] = int(out[i] * i / n_in)
    for i in range(min(n_out, len(out))):
        j = len(out) - 1 - i
        out[j] = int(out[j] * i / n_out)
    return out


def loop_seam(samples, overlap):
    """Fold the tail over the head, so the loop has no seam.

    Render `overlap` seconds more than the loop wants; the extra is faded out
    over the start of the loop while the start fades in. When the player wraps
    from the end back to the beginning, it lands on audio that was already
    blending into exactly what it had just been playing.
    """
    n = int(RATE * overlap)
    body, tail = samples[:-n], samples[-n:]
    out = body[:]
    for i in range(n):
        k = i / n
        out[i] = int(body[i] * k + tail[i] * (1 - k))
    return out


def write(name, samples):
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(array.array('h', samples).tobytes())
    kb = os.path.getsize(path) // 1024
    print(f'  {name + ".wav":14} {len(samples) / RATE:5.2f}s  {kb:4d} KB')


def bell_partials(f0, start, decay, gain=1.0):
    """A struck bell: inharmonic partials, the high ones dying first."""
    ratios = [(1.0, 1.0), (2.0, 0.6), (2.42, 0.42), (3.0, 0.3),
              (4.16, 0.22), (5.43, 0.12)]
    t = f'(t-{start})'
    terms = []
    for r, a in ratios:
        d = decay * (1 + (r - 1) * 0.55)
        terms.append(f'{a * gain}*sin(2*PI*{f0 * r}*{t})*exp(-{d}*{t})')
    return f'gte(t,{start})*(' + '+'.join(terms) + ')'


def main():
    os.makedirs(OUT, exist_ok=True)
    print('Synthesizing into assets/sounds/')

    # ---- Ambient loops ----------------------------------------------------

    # The sea: a low wash that swells and falls about every eight seconds —
    # the same period as the swell the world draws — with hiss on the break.
    swell = 'volume=\'0.32+0.68*pow(sin(PI*t/8),2)\':eval=frame'
    sea = render(
        f'anoisesrc=color=brown:seed=7:r={RATE},lowpass=f=700,{swell}[a];'
        f'anoisesrc=color=pink:seed=11:r={RATE},highpass=f=1800,'
        f'lowpass=f=5200,volume=0.35,'
        f'volume=\'pow(sin(PI*(t-0.6)/8),4)\':eval=frame[b];'
        f'[a][b]amix=inputs=2:normalize=0', 18)
    write('sea', normalise(loop_seam(sea, 2), -10))

    # Wind: a band of noise with gusts on two unrelated periods, so it never
    # repeats a shape inside the loop.
    wind = render(
        f'anoisesrc=color=pink:seed=23:r={RATE},bandpass=f=650:width_type=h:w=700,'
        f'volume=\'0.35+0.65*pow(0.5+0.5*sin(2*PI*t/6.0)*sin(2*PI*t/3.7+1.1),1.5)\''
        f':eval=frame', 14)
    write('wind', normalise(loop_seam(wind, 2), -12))

    # Rain. THE FIRST DRAFT WAS STATIC: smooth band-passed white noise, with
    # nothing in it happening at any particular moment. The report was fair —
    # "doesn't sound bad, just off" — because what makes rain sound like rain
    # is that it is thousands of separate drops, each one landing somewhere.
    # So it is built from events now, in three layers:
    #
    #   - DROPS ON WATER: a short "plink" each, gliding slightly up in pitch as
    #     the bubble under it collapses, at random times and loudnesses;
    #   - PATTER: a dense scatter of tiny broadband ticks, which is the crackle
    #     and fizz of rain on everything else;
    #   - A WASH: soft, low noise underneath for the downpour further off —
    #     the only part the first draft had, and now the quietest.
    seconds = 12
    n = RATE * seconds
    rnd = random.Random(41)
    layer = [0.0] * n
    for _ in range(30 * seconds):  # drops on the water
        t0 = rnd.randrange(n)
        f = rnd.uniform(1300, 3600)
        glide = rnd.uniform(0.15, 0.6)
        amp = rnd.uniform(0.25, 1.0) ** 2
        dur = int(RATE * rnd.uniform(0.010, 0.030))
        for i in range(dur):
            j = t0 + i
            if j >= n:
                break
            tt = i / RATE
            ph = 2 * math.pi * f * (tt + glide * tt * tt / (2 * dur / RATE))
            layer[j] += 0.38 * amp * math.sin(ph) * math.exp(-tt * 180)
    for _ in range(900 * seconds):  # patter
        t0 = rnd.randrange(n)
        amp = rnd.uniform(0.05, 1.0) ** 2.2
        for i in range(rnd.randint(2, 9)):
            j = t0 + i
            if j >= n:
                break
            layer[j] += 0.85 * amp * rnd.uniform(-1, 1) * math.exp(-i / 2.5)
    rain = render_over(
        layer,
        '[0:a]highpass=f=700,lowpass=f=9500[d];'
        f'anoisesrc=color=pink:seed=41:r={RATE},bandpass=f=900:width_type=h:w=1100,'
        'volume=0.22[w];'
        "[d][w]amix=inputs=2:normalize=0,"
        "volume='0.82+0.18*sin(2*PI*t/5.3)*sin(2*PI*t/2.9+0.7)':eval=frame",
        seconds)
    write('rain', normalise(loop_seam(rain, 2), -13))

    # ---- One-shots --------------------------------------------------------

    # A ship's bell, rung as a pair — the way the hours are struck aboard.
    # For a hull coming in to the quay or home from a voyage.
    bell = render('aevalsrc=\'' + bell_partials(680, 0, 2.2) + '+' +
                  bell_partials(680, 0.42, 2.2, 0.85) +
                  f'\':s={RATE}', 2.8)
    write('bell', edges(normalise(bell, -4), fade_out=0.3))

    # Coins: three bright clinks a moment apart. For a sale.
    def clink(f, at, g):
        return (f'gte(t,{at})*{g}*(sin(2*PI*{f}*(t-{at}))+0.6*sin(2*PI*{f*1.47}*(t-{at}))'
                f'+0.4*sin(2*PI*{f*2.09}*(t-{at})))*exp(-38*(t-{at}))')
    coins = render('aevalsrc=\'' + '+'.join([
        clink(2900, 0.0, 1.0), clink(3400, 0.075, 0.8), clink(2650, 0.16, 0.7),
    ]) + f'\':s={RATE}', 0.6)
    write('coins', edges(normalise(coins, -6)))

    # A mallet on timber, twice: a dull knock and the body of the board
    # ringing under it. For a shed going up.
    def knock(at):
        return (f'gte(t,{at})*(0.9*sin(2*PI*170*(t-{at}))*exp(-22*(t-{at}))'
                f'+0.5*sin(2*PI*410*(t-{at}))*exp(-40*(t-{at})))')
    hammer = render(
        'aevalsrc=\'' + knock(0) + '+' + knock(0.3) + f'\':s={RATE}[k];'
        f'anoisesrc=color=pink:seed=5:r={RATE},lowpass=f=1600,'
        f'volume=\'0.5*(exp(-60*t)+gte(t,0.3)*exp(-60*(t-0.3)))\':eval=frame[n];'
        f'[k][n]amix=inputs=2:normalize=0', 0.8)
    write('hammer', edges(normalise(hammer, -5)))

    # A gun: a hard low boom, and the echo of it coming back off the water.
    # For a prize taken.
    cannon = render(
        f'anoisesrc=color=brown:seed=3:r={RATE},lowpass=f=420,'
        f'volume=\'min(1,t*400)*exp(-2.6*t)\':eval=frame[n];'
        f'aevalsrc=\'1.2*sin(2*PI*52*t)*exp(-4*t)\':s={RATE}[s];'
        f'[n][s]amix=inputs=2:normalize=0,aecho=0.8:0.6:240|520:0.35|0.18', 2.6)
    write('cannon', edges(normalise(cannon, -3), fade_out=0.4))

    # Thunder: a rumble that rolls and breaks up rather than a single crack.
    thunder = render(
        f'anoisesrc=color=brown:seed=17:r={RATE},lowpass=f=260,'
        f'volume=\'min(1,t*3)*exp(-0.85*t)*(0.65+0.35*sin(2*PI*t*1.7)*sin(2*PI*t*0.9))\''
        f':eval=frame,aecho=0.7:0.5:420|900:0.3|0.2', 4.5)
    write('thunder', edges(normalise(thunder, -4), fade_out=0.6))

    # Gulls. THE FIRST DRAFT SOUNDED LIKE A SYNTHESIZER, and was reported as
    # "birds sound a little odd": each call was a clean stack of harmonics
    # sliding straight down, all three identical — a laser, not a bird. What
    # a herring gull's "kyow" actually has, and this now tries for:
    #
    #   - an ARCHED pitch: up quickly, then a long fall, inside each note;
    #   - a RASP: the voice is rough, so the tone is buzzed at ~70Hz and a
    #     breath of band-limited noise rides along with it;
    #   - a NASAL colour: the second harmonic is the loudest, not the first;
    #   - DISTANCE: highs softened and an echo off the water, mixed low, so it
    #     sits out over the sea rather than in the player's ear;
    #   - VARIETY: three different calls, picked at random in the game, since
    #     a sound that repeats exactly is the quickest way to give a fake away.
    #
    # Still the likeliest file in this folder to want replacing with a
    # recording, which can go in as gull.wav, gull_2.wav and gull_3.wav.
    def kyow(at, dur, base, rise, fall, g, rasp=70):
        # Frequency fa + fb*sin(pi*u) + c*u over the note, u in 0..1; the
        # phase is its closed-form integral, so the pitch glides cleanly.
        tau = f'(t-{at})'
        u = f'({tau}/{dur})'
        ph = (f'2*PI*({base}*{tau}+{rise}*{dur}/PI*(1-cos(PI*{u}))'
              f'+{fall}*pow({tau},2)/(2*{dur}))')
        # max(...,0) BEFORE the root: outside its note the sine goes negative,
        # the square root of that is NaN, and NaN times a zero gate is still
        # NaN — one bad sample, and every filter downstream holds it forever.
        # The first render of these was a flat drone for exactly that reason.
        env = f'pow(max(sin(PI*{u}),0),0.5)'
        buzz = f'(1+0.35*sin(2*PI*{rasp}*{tau}))'
        tone = (f'(0.5*sin({ph})+1.0*sin(2*{ph})+0.75*sin(3*{ph})'
                f'+0.45*sin(4*{ph})+0.25*sin(5*{ph})+0.15*sin(6*{ph}))')
        return f'between(t,{at},{at + dur})*{g}*{env}*{buzz}*{tone}'

    def breath(calls):
        # The same notes as a whisper of noise, for the grain in the voice.
        gates = '+'.join(
            f'between(t,{at},{at + dur})*{g}*pow(max(sin(PI*(t-{at})/{dur}),0),0.5)'
            for at, dur, g in calls)
        return gates

    def gull(name, calls, seconds):
        voice = '+'.join(kyow(*c) for c in calls)
        gates = breath([(c[0], c[1], c[5]) for c in calls])
        samples = render(
            f"aevalsrc='{voice}':s={RATE}[v];"
            f'anoisesrc=color=pink:seed={len(name) * 7}:r={RATE},'
            f'bandpass=f=2600:width_type=h:w=1800,'
            f"volume='0.22*({gates})':eval=frame[n];"
            f'[v][n]amix=inputs=2:normalize=0,'
            f'highpass=f=500,lowpass=f=4800,'
            f'aecho=0.7:0.45:140|310:0.22|0.12', seconds)
        write(name, edges(normalise(samples, -12), fade_out=0.25))

    # (start, length, base Hz, rise Hz, fall Hz, gain)
    gull('gull', [
        (0.00, 0.34, 1050, 430, -520, 1.0),
        (0.44, 0.30, 1000, 400, -480, 0.85),
        (0.84, 0.36, 960, 380, -560, 0.7),
    ], 1.6)
    # The long call: one drawn-out cry, then laughter.
    gull('gull_2', [
        (0.00, 0.55, 980, 460, -600, 1.0),
        (0.70, 0.13, 1250, 220, -300, 0.7),
        (0.88, 0.13, 1230, 220, -300, 0.65),
        (1.06, 0.13, 1200, 200, -300, 0.6),
        (1.24, 0.14, 1170, 200, -320, 0.5),
    ], 1.8)
    # One gull, further off, answered once.
    gull('gull_3', [
        (0.00, 0.40, 1120, 420, -540, 0.9),
        (0.62, 0.32, 1060, 380, -500, 0.5),
    ], 1.4)

    # The light lit: four bells climbing a major chord.
    chime = render('aevalsrc=\'' + '+'.join([
        bell_partials(523.25, 0.0, 1.4, 0.8),
        bell_partials(659.25, 0.2, 1.4, 0.75),
        bell_partials(783.99, 0.4, 1.4, 0.7),
        bell_partials(1046.5, 0.6, 1.1, 0.65),
    ]) + f'\':s={RATE}', 4.0)
    write('chime', edges(normalise(chime, -4), fade_out=0.5))

    # The revenue cutter alongside: a bell rung fast and high. Urgent, not
    # loud — it is a warning, not a punishment.
    alarm = render('aevalsrc=\'' + '+'.join(
        bell_partials(1040, 0.17 * i, 6.0, 1 - 0.1 * i) for i in range(4)
    ) + f'\':s={RATE}', 1.6)
    write('alarm', edges(normalise(alarm, -6), fade_out=0.3))

    print('Done. Every one of these is a first draft by someone who could not')
    print('hear it: replace any file in assets/sounds/ and the game uses yours.')


if __name__ == '__main__':
    try:
        main()
    except subprocess.CalledProcessError as e:
        sys.stderr.write(e.stderr.decode() if e.stderr else str(e))
        sys.exit(1)
