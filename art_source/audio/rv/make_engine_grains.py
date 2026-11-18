"""Cut single-firing engine grains from the Iveco diesel recordings.

Each grain spans one combustion pulse plus a short raised-cosine overlap on both
sides. Consecutive grains from the recording therefore overlap-add back into the
original sound, and the game can place them at any firing rate. The grains keep
their own cycle length, so the uneven rhythm of a real diesel survives.
"""

import argparse
import wave
from pathlib import Path

import numpy as np

from make_pilot_wavs import RATE, engine_eq, read_clip

# (file, start, end) in seconds. Each clip holds idle and stationary revs.
SOURCES = (
    ("iveco_idle.wav", 1.0, 34.0),
    ("iveco_lo.wav", 1.0, 34.5),
    ("iveco_hi.wav", 1.0, 20.9),
)
BIN_HZ = 2.0
RUN = 6
RUNS_PER_BIN = 2
IDLE_RUNS = 8
IDLE_LIMIT_HZ = 31.0
SLOPE_HZ_PER_S = 18.0
STEADY, RISING, FALLING = 0, 1, 2


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


def cut_grains(audio, pulses, times, rates, source_index):
    slope = np.gradient(rates, times)
    slope = np.convolve(slope, np.ones(9) / 9, mode="same")
    grains = []
    for index in range(1, len(pulses) - 2):
        peak, hz, confidence = pulses[index]
        period = pulses[index + 1][0] - peak
        if confidence < 0.8 or not 0.7 < period * hz / RATE < 1.3:
            grains.append(None)
            continue
        # Grain boundaries sit in the quiet part before each firing.
        start = peak - int(0.3 * period)
        fade = max(8, int(0.12 * period))
        clip = audio[start - fade:start + period + fade].copy()
        ramp = np.sin(np.linspace(0.0, np.pi / 2, 2 * fade)) ** 2
        clip[:2 * fade] *= ramp
        clip[-2 * fade:] *= ramp[::-1]
        rate_slope = np.interp(peak / RATE, times, slope)
        kind = RISING if rate_slope > SLOPE_HZ_PER_S else FALLING if rate_slope < -SLOPE_HZ_PER_S else STEADY
        grains.append({"audio": clip, "period": period, "fade": fade, "hz": hz, "kind": kind,
                       "confidence": confidence, "source": source_index, "time": peak / RATE})
    return grains


def runs_of(grains):
    """Consecutive grains of one kind, cut into fixed-length runs."""
    runs, current = [], []
    for grain in grains + [None]:
        if grain is not None and (not current or grain["kind"] == current[0]["kind"]):
            current.append(grain)
        else:
            runs.extend(current[i:i + RUN] for i in range(0, len(current) - RUN + 1, RUN))
            current = [] if grain is None else [grain]
    return runs


def select_runs(runs):
    chosen = {}
    for run in runs:
        rates = np.array([grain["hz"] for grain in run])
        spread = np.ptp(rates) / np.mean(rates)
        if spread > 0.4: continue
        key = (int(np.mean(rates) // BIN_HZ), run[0]["kind"])
        score = np.mean([grain["confidence"] for grain in run]) - spread
        chosen.setdefault(key, []).append((score, run))
    picked = []
    for (bin_index, kind), candidates in chosen.items():
        idle = (bin_index + 1) * BIN_HZ <= IDLE_LIMIT_HZ + BIN_HZ
        limit = IDLE_RUNS if idle else RUNS_PER_BIN
        # Prefer the cleanest runs, but spread picks across the recording.
        candidates.sort(key=lambda item: -item[0])
        taken = []
        for score, run in candidates:
            if len(taken) >= limit: break
            if any(abs(run[0]["time"] - other[0]["time"]) < 0.5 and run[0]["source"] == other[0]["source"]
                   for other in taken):
                continue
            taken.append(run)
        picked.extend(taken)
    return picked


def write_bank(output, runs, peak_db):
    grains = [grain for run in runs for grain in run]
    data = np.concatenate([grain["audio"] for grain in grains])
    gain = 32767 * 10 ** (peak_db / 20) / np.max(np.abs(data))
    wav_path = output / "engine_grains.wav"
    with wave.open(str(wav_path), "wb") as clip:
        clip.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        clip.writeframes(np.rint(data * gain).astype("<i2").tobytes())
    starts, periods, fades, lengths, rates, kinds, follows = [], [], [], [], [], [], []
    offset = 0
    for run in runs:
        for position, grain in enumerate(run):
            starts.append(offset)
            periods.append(grain["period"])
            fades.append(grain["fade"])
            lengths.append(len(grain["audio"]))
            rates.append(round(float(grain["hz"]), 3))
            kinds.append(grain["kind"])
            follows.append(len(starts) if position < len(run) - 1 else -1)
            offset += len(grain["audio"])

    def packed(kind, values):
        return f"{kind}({', '.join(str(value) for value in values)})"

    resource = "\n".join([
        '[gd_resource type="Resource" script_class="EngineGrainBank" load_steps=3 format=3]',
        "",
        '[ext_resource type="Script" path="res://core/audio/engine_grain_bank.gd" id="1"]',
        '[ext_resource type="AudioStream" path="res://assets/audio/rv/engine_grains.wav" id="2"]',
        "",
        "[resource]",
        'script = ExtResource("1")',
        'samples = ExtResource("2")',
        f"starts = {packed('PackedInt32Array', starts)}",
        f"periods = {packed('PackedInt32Array', periods)}",
        f"fades = {packed('PackedInt32Array', fades)}",
        f"lengths = {packed('PackedInt32Array', lengths)}",
        f"firing_hz = {packed('PackedFloat32Array', rates)}",
        f"kinds = {packed('PackedInt32Array', kinds)}",
        f"follows = {packed('PackedInt32Array', follows)}",
        "",
    ])
    (output / "engine_grains.tres").write_text(resource, encoding="utf-8")
    return grains, len(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    all_runs = []
    idle_reference = None
    for source_index, (name, start, end) in enumerate(SOURCES):
        audio = engine_eq(read_clip(args.source / name, start, end)) / 32768
        times, rates, scores = track_pulse(audio)
        pulses = find_pulses(audio, times, rates, scores)
        grains = cut_grains(audio, pulses, times, rates, source_index)
        # The idle passages match the microphone gain between recordings.
        idle = [g for g in grains if g is not None and g["hz"] < IDLE_LIMIT_HZ and g["kind"] == STEADY]
        level = np.sqrt(np.mean(np.concatenate([g["audio"] for g in idle]) ** 2))
        idle_reference = idle_reference or level
        for grain in grains:
            if grain is not None: grain["audio"] *= idle_reference / level
        all_runs.extend(runs_of(grains))
        print(f"{name}: {sum(g is not None for g in grains)} grains, "
              f"{rates.min():.1f}-{rates.max():.1f} Hz tracked")
    runs = select_runs(all_runs)
    runs.sort(key=lambda run: np.mean([grain["hz"] for grain in run]))
    grains, total = write_bank(args.output, runs, -1.0)
    print(f"bank: {len(grains)} grains in {len(runs)} runs, {total / RATE:.2f} s")
    for kind, label in ((STEADY, "steady"), (RISING, "rising"), (FALLING, "falling")):
        rates = sorted(grain["hz"] for grain in grains if grain["kind"] == kind)
        bins = sorted({int(rate // BIN_HZ) for rate in rates})
        gaps = [f"{a * BIN_HZ:.0f}-{b * BIN_HZ:.0f}" for a, b in zip(bins, bins[1:]) if b - a > 2]
        print(f"  {label}: {len(rates)} grains, {rates[0]:.1f}-{rates[-1]:.1f} Hz, gaps over 4 Hz: {gaps or 'none'}")


if __name__ == "__main__":
    main()
