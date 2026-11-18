"""Build the RV rolling and wind loops.

Asphalt and rough road come from an in-cab recording of a diesel van. Gravel
and wind have no engine-free CC0 recording, so they are generated here with a
fixed seed. Generated loops are built circularly, so their seams are inherent.
"""

import argparse
from pathlib import Path

import numpy as np

from make_pilot_wavs import RATE, loop_engine, read_clip, write_clip

SEED = 4127


def highpass(audio, hz, order=4):
    frequency = np.fft.rfftfreq(len(audio), 1 / RATE)
    response = 1 - 1 / (1 + (frequency / hz) ** (2 * order))
    return np.fft.irfft(np.fft.rfft(audio) * np.sqrt(response), n=len(audio))


def shaped_noise(rng, length, low, high, tilt_db_per_octave):
    """Circular noise with a band and a spectral tilt, so it loops seamlessly."""
    spectrum = rng.normal(size=length // 2 + 1) + 1j * rng.normal(size=length // 2 + 1)
    frequency = np.fft.rfftfreq(length, 1 / RATE)
    safe = np.maximum(frequency, 1.0)
    gain = (safe / 1000.0) ** (tilt_db_per_octave / 6.02)
    gain *= 1 / np.sqrt(1 + (low / safe) ** 4) / np.sqrt(1 + (safe / high) ** 4)
    gain[0] = 0.0
    noise = np.fft.irfft(spectrum * gain, n=length)
    return noise / np.sqrt(np.mean(noise**2))


def periodic_curve(rng, length, cycles, depth):
    """Slow modulation made of whole cycles per loop."""
    t = np.arange(length) / length
    curve = np.zeros(length)
    for count in cycles:
        curve += rng.uniform(0.4, 1.0) * np.sin(2 * np.pi * (count * t + rng.uniform()))
    curve /= np.max(np.abs(curve))
    return 1.0 + depth * curve


def add_circular(target, start, burst):
    index = (start + np.arange(len(burst))) % len(target)
    np.add.at(target, index, burst)


def gravel(rng, seconds):
    length = int(seconds * RATE)
    audio = 0.3 * shaped_noise(rng, length, 35, 1400, -3.5)
    audio *= periodic_curve(rng, length, (3, 7, 13), 0.35)
    # Stones flicked against the tyres and wheel arches.
    for _ in range(int(900 * seconds)):
        size = int(rng.uniform(0.0015, 0.006) * RATE)
        envelope = np.exp(-np.arange(size) / (size / 4))
        burst = highpass(rng.normal(size=size * 4), rng.uniform(900, 2600), 2)[:size] * envelope
        add_circular(audio, rng.integers(length), burst * rng.lognormal(-3.4, 0.8))
    # Suspension thumps over ruts.
    for _ in range(int(2.5 * seconds)):
        size = int(0.12 * RATE)
        t = np.arange(size) / RATE
        thump = np.sin(2 * np.pi * rng.uniform(55, 95) * t) * np.exp(-t * 28)
        add_circular(audio, rng.integers(length), thump * rng.uniform(0.15, 0.4))
    return audio


def wind(rng, seconds):
    length = int(seconds * RATE)
    audio = shaped_noise(rng, length, 180, 3200, -3.0)
    # Gusts plus a slower swell, both whole cycles per loop.
    audio *= periodic_curve(rng, length, (2, 5, 9), 0.45)
    return audio


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, start, end in (("road_asphalt", 2.0, 18.0), ("road_rough", 44.0, 58.0)):
        audio = highpass(read_clip(args.source / "vw_t5_road.wav", start, end), 28)
        write_clip(args.output / f"{name}.wav", loop_engine(audio, 0.5), -1.0, loop=True, rms_db=-20.0)
    rng = np.random.default_rng(SEED)
    write_clip(args.output / "road_gravel.wav", gravel(rng, 12.0), -1.0, loop=True, rms_db=-20.0)
    write_clip(args.output / "wind.wav", wind(rng, 12.0), -1.0, loop=True, rms_db=-20.0)


if __name__ == "__main__":
    main()
