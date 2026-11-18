"""Cut single-firing engine grains from the Iveco diesel recordings.

Each grain spans one combustion pulse between two boundaries in the quiet part
before each firing, plus a fixed raised-cosine overlap on both sides. Neighbours
share their boundaries, so following grains overlap-add back into the original
recording, and the game can place them at any firing rate. Every confident pulse
is kept as part of a contiguous limb: the recordings never hold a raised rpm, so
a held rate has to borrow from many short passes through it.
"""

import argparse
import wave
from pathlib import Path

import numpy as np

from make_pilot_wavs import RATE, engine_eq, read_clip

# (file, start, end) in seconds. The idle file is steady; the others blip the throttle.
SOURCES = (
    ("iveco_idle.wav", 1.0, 13.0),
    ("iveco_lo.wav", 1.0, 34.5),
    ("iveco_hi.wav", 1.0, 20.9),
)
IDLE_SOURCE = 0
IDLE_LIMIT_HZ = 31.0
SLOPE_HZ_PER_S = 18.0
STEADY, RISING, FALLING = 0, 1, 2
# Half-width of the shared crossfade at every boundary, in samples.
FADE = 64
MIN_LIMB = 3
CYLINDERS = 4
# Part of each limb's slow level trend pulled toward the level of its rate and kind.
LEVEL_PULL = 0.7
TREND_GRAINS = 9
BAND_HZ = 4.0
# The top rate the game uses still has this many grains within the match band.
TOP_POOL = 60
TOP_BAND = 0.05


def lowpass(audio, hz):
    frequency = np.fft.rfftfreq(len(audio), 1 / RATE)
    return np.fft.irfft(np.fft.rfft(audio) / (1 + (frequency / hz) ** 4), n=len(audio))


def track_pulse(audio):
    """Firing rate every 10 ms from a normalised autocorrelation of the low band."""
    decimate = 4
    rate = RATE / decimate
    low = lowpass(audio, 300)[::decimate]
    window = int(0.12 * rate)
    hop = int(0.01 * rate)
    lags = np.arange(int(rate / 125), int(rate / 24) + 1)
    times, rates, scores = [], [], []
    for start in range(0, len(low) - window - lags[-1], hop):
        head = low[start:start + window] - np.mean(low[start:start + window])
        energy = np.sqrt(np.sum(head**2)) + 1e-12
        corr = np.empty(len(lags))
        for index, lag in enumerate(lags):
            tail = low[start + lag:start + lag + window]
            tail = tail - np.mean(tail)
            corr[index] = np.dot(head, tail) / (energy * (np.sqrt(np.sum(tail**2)) + 1e-12))
        best = np.max(corr)
        # The shortest lag close to the best peak avoids half-rate picks.
        peaks = [i for i in np.where(corr >= best * 0.92)[0]
                 if 0 < i < len(corr) - 1 and corr[i] >= corr[i - 1] and corr[i] >= corr[i + 1]]
        pick = peaks[0] if peaks else int(np.argmax(corr))
        times.append((start + window / 2) / rate)
        rates.append(rate / lags[pick])
        scores.append(best)
    times, rates, scores = np.array(times), np.array(rates), np.array(scores)
    padded = np.pad(rates, 3, mode="edge")
    rates = np.median(np.lib.stride_tricks.sliding_window_view(padded, 7), axis=1)
    return times, rates, scores


def find_pulses(audio, times, rates, scores):
    """Walk the low band peak by peak, guided by the tracked firing rate."""
    low = lowpass(audio, 300)
    pulses = []
    position = int(times[0] * RATE)
    while True:
        hz = np.interp(position / RATE, times, rates)
        period = RATE / hz
        center = position + period
        left, right = int(center - 0.3 * period), int(center + 0.3 * period)
        if right >= len(low): break
        peak = left + int(np.argmax(low[left:right]))
        confidence = np.interp(peak / RATE, times, scores)
        pulses.append((peak, hz, confidence))
        position = peak
    return pulses


def brightness_db(clip):
    spectrum = np.abs(np.fft.rfft(clip * np.hanning(len(clip)), n=4096)) ** 2
    frequency = np.fft.rfftfreq(4096, 1 / RATE)
    return 10 * np.log10(spectrum[frequency > 1000].sum() / (spectrum.sum() + 1e-20) + 1e-12)


def cut_limbs(audio, pulses, times, rates, source_index):
    """Contiguous runs of confident grains; each grain ends where the next begins."""
    slope = np.gradient(rates, times)
    slope = np.convolve(slope, np.ones(9) / 9, mode="same")
    peaks = [pulse[0] for pulse in pulses]
    # The boundary before each firing sits 30 % of the previous period ahead of its peak.
    bounds = [None] + [peaks[i] - int(0.3 * (peaks[i] - peaks[i - 1])) for i in range(1, len(peaks))]
    limbs, limb = [], []
    for index in range(1, len(pulses) - 1):
        peak, hz, confidence = pulses[index]
        start, end = bounds[index], bounds[index + 1]
        period = end - start
        rate_slope = np.interp(peak / RATE, times, slope)
        kind = RISING if rate_slope > SLOPE_HZ_PER_S else FALLING if rate_slope < -SLOPE_HZ_PER_S else STEADY
        idle = hz < IDLE_LIMIT_HZ and kind == STEADY
        usable = (confidence >= 0.8 and 0.7 < period * hz / RATE < 1.3 and start - FADE >= 0
                  and end + FADE <= len(audio) and idle == (source_index == IDLE_SOURCE))
        if not usable:
            if len(limb) >= MIN_LIMB: limbs.append(limb)
            limb = []
            continue
        span = audio[start:end]
        limb.append({
            "start": start, "period": period, "hz": hz, "kind": kind, "idle": idle,
            "level": 20 * np.log10(np.sqrt(np.mean(span**2)) + 1e-12),
            "brightness": brightness_db(span),
            "cylinder": index % CYLINDERS if source_index == IDLE_SOURCE else -1,
            "source": source_index,
        })
    if len(limb) >= MIN_LIMB: limbs.append(limb)
    return limbs


def level_gains(limbs):
    """Flattens each limb's slow level trend toward the level of its rate and kind."""
    grains = [grain for limb in limbs for grain in limb]
    hz = np.array([grain["hz"] for grain in grains])
    kind = np.array([grain["kind"] for grain in grains])
    level = np.array([grain["level"] for grain in grains])
    for limb in limbs:
        levels = np.array([grain["level"] for grain in limb])
        padded = np.pad(levels, TREND_GRAINS // 2, mode="edge")
        trend = np.convolve(padded, np.ones(TREND_GRAINS) / TREND_GRAINS, mode="valid")
        for grain, slow in zip(limb, trend):
            peers = (np.abs(hz - grain["hz"]) < BAND_HZ) & (kind == grain["kind"])
            grain["gain_db"] = LEVEL_PULL * (np.median(level[peers]) - slow)


def top_rate(grains):
    rates = np.sort([grain["hz"] for grain in grains])
    for hz in rates[::-1]:
        pool = np.sum((rates > hz / (1 + TOP_BAND)) & (rates < hz * (1 + TOP_BAND)))
        if pool >= TOP_POOL: return float(hz)
    return float(rates[-1])


def write_bank(output, sources, limbs, peak_db):
    ramp = np.sin(np.linspace(0.0, np.pi / 2, 2 * FADE)) ** 2
    clips = []
    for limb in limbs:
        audio = sources[limb[0]["source"]]
        for grain in limb:
            clip = audio[grain["start"] - FADE:grain["start"] + grain["period"] + FADE] * 10 ** (grain["gain_db"] / 20)
            clip[:2 * FADE] *= ramp
            clip[-2 * FADE:] *= ramp[::-1]
            clips.append(clip)
    data = np.concatenate(clips)
    gain = 32767 * 10 ** (peak_db / 20) / np.max(np.abs(data))
    with wave.open(str(output / "engine_grains.wav"), "wb") as clip:
        clip.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(data * gain).astype("<i2").tobytes())
    fields = {name: [] for name in ("starts", "periods", "fades", "lengths", "firing_hz", "kinds",
                                    "follows", "levels", "brightness", "cylinders")}
    offset = 0
    for limb in limbs:
        for position, grain in enumerate(limb):
            fields["starts"].append(offset)
            fields["periods"].append(grain["period"])
            fields["fades"].append(FADE)
            fields["lengths"].append(grain["period"] + 2 * FADE)
            fields["firing_hz"].append(round(float(grain["hz"]), 3))
            fields["kinds"].append(grain["kind"])
            fields["follows"].append(len(fields["starts"]) if position < len(limb) - 1 else -1)
            fields["levels"].append(round(float(grain["level"] + grain["gain_db"]), 2))
            fields["brightness"].append(round(float(grain["brightness"]), 2))
            fields["cylinders"].append(grain["cylinder"])
            offset += grain["period"] + 2 * FADE
    grains = [grain for limb in limbs for grain in limb]
    idle_hz = float(np.mean([grain["hz"] for grain in grains if grain["idle"]]))
    floats = {"firing_hz", "levels", "brightness"}

    def packed(name):
        kind = "PackedFloat32Array" if name in floats else "PackedInt32Array"
        return f"{name} = {kind}({', '.join(str(value) for value in fields[name])})"

    resource = "\n".join([
        '[gd_resource type="Resource" script_class="EngineGrainBank" load_steps=3 format=3]',
        "",
        '[ext_resource type="Script" path="res://core/audio/engine_grain_bank.gd" id="1"]',
        '[ext_resource type="AudioStream" path="res://assets/audio/rv/engine_grains.wav" id="2"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        'samples = ExtResource("2")',
        f"idle_hz = {idle_hz:.3f}",
        f"top_hz = {top_rate(grains):.3f}",
        *(packed(name) for name in fields),
        "",
    ])
    (output / "engine_grains.tres").write_text(resource, encoding="utf-8")
    return grains, len(data), idle_hz


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    sources, limbs = [], []
    idle_reference = None
    for source_index, (name, start, end) in enumerate(SOURCES):
        audio = engine_eq(read_clip(args.source / name, start, end)) / 32768
        times, rates, scores = track_pulse(audio)
        pulses = find_pulses(audio, times, rates, scores)
        # The idle passages match the microphone gain between recordings.
        peaks = np.array([pulse[0] for pulse in pulses])
        idle = [i for i in range(len(pulses) - 1) if pulses[i][1] < IDLE_LIMIT_HZ and pulses[i][2] >= 0.8]
        level = np.sqrt(np.mean(np.concatenate([audio[peaks[i]:peaks[i + 1]] for i in idle]) ** 2))
        idle_reference = idle_reference or level
        audio = audio * idle_reference / level
        found = cut_limbs(audio, pulses, times, rates, source_index)
        sources.append(audio)
        limbs.extend(found)
        print(f"{name}: {sum(len(limb) for limb in found)} grains in {len(found)} limbs, "
              f"{rates.min():.1f}-{rates.max():.1f} Hz tracked")
    level_gains(limbs)
    grains, total, idle_hz = write_bank(args.output, sources, limbs, -1.0)
    print(f"bank: {len(grains)} grains in {len(limbs)} limbs, {total / RATE:.2f} s, idle {idle_hz:.1f} Hz")
    for kind, label in ((STEADY, "steady"), (RISING, "rising"), (FALLING, "falling")):
        rates = np.array(sorted(grain["hz"] for grain in grains if grain["kind"] == kind))
        counts = [int(np.sum((rates >= lo) & (rates < lo + 10))) for lo in range(20, 120, 10)]
        print(f"  {label}: {len(rates)} grains, per 10 Hz from 20: {counts}")


if __name__ == "__main__":
    main()
